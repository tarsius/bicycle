;;; bicycle.el --- Cycle outline and code visibility  -*- lexical-binding:t -*-

;; Copyright (C) 2018-2025 Jonas Bernoulli

;; Author: Jonas Bernoulli <emacs.bicycle@jonas.bernoulli.dev>
;; Homepage: https://github.com/tarsius/bicycle
;; Keywords: outlines

;; Package-Version: 1.0.2
;; Package-Requires: ((emacs "26.1") (compat "30.1"))

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides commands for cycling the visibility of
;; outline sections and code blocks.  These commands are intended to
;; be bound in `outline-minor-mode-map' and do most of the work using
;; functions provided by the `outline' package.

;; This package is named `bicycle' because it can additionally make
;; use of the `hideshow' package.

;; If `hs-minor-mode' is enabled and point is at the start of a code
;; block, then `hs-toggle-hiding' is used instead of some `outline'
;; function.  When you later cycle the visibility of a section that
;; contains code blocks (which is done using `outline' functions),
;; then code block that have been hidden using `hs-toggle-hiding',
;; are *not* extended.

;; A reasonable configuration could be:
;;
;;   (use-package bicycle
;;     :after outline
;;     :bind (:map outline-minor-mode-map
;;                 ([C-tab] . bicycle-cycle)
;;                 ([S-tab] . bicycle-cycle-global)))
;;
;;   (use-package prog-mode
;;     :config
;;     (add-hook 'prog-mode-hook #'outline-minor-mode)
;;     (add-hook 'prog-mode-hook #'hs-minor-mode))

;;; Code:

(require 'compat)

(require 'hideshow)
(require 'outline)

(defvar-local outline-code-level 1000)

;;; Options

(defgroup bicycle nil
  "Cycle outline and code visibility."
  :group 'hideshow
  :group 'outlines)

(defcustom bicycle-echo-state t
  "Whether to echo the name of the new state while cycling."
  :package-version '(bicycle . "0.1.0")
  :group 'bicycle
  :type 'boolean)

;;; Commands

;;;###autoload
(defun bicycle-cycle (&optional global)
  "Cycle local or global visibility.

With a prefix argument call `bicycle-cycle-global'.
Without a prefix argument call `bicycle-cycle-local'."
  (interactive "P")
  (if global
      (bicycle-cycle-global)
    (bicycle-cycle-local)))

;;;###autoload
(defun bicycle-cycle-global ()
  "Cycle visibility of all sections.

1. OVERVIEW: Show only top-level headings.

\(2.          There is no equivalent of `bicycle-cycle-local's
             CHILDREN state.)

3. TOC:      Recursively show all headings,
             without treating code blocks as sections.

4. TREES:    Recursively show all headings,
             treating code blocks as sections
             (i.e., their first line is treated as a heading).

5. ALL:      Show everything, including code blocks,
             empty lines and comments.
             However, do not expand code blocks that were
             previously collapsed individually.

In situations when cycling to a state makes no difference compared
to the previous state, then immediately continue to the next state."
  (interactive)
  (setq deactivate-mark t)
  (save-excursion
    (goto-char (point-min))
    (unless (re-search-forward outline-regexp nil t)
      (user-error "Found no heading"))
    (cond
     ((bicycle--maybe-cycle 'outline-cycle-overview 'outline-cycle-toc
        (lambda () (and (bicycle--top-level-p) (bicycle--non-code-children-p)))
        (lambda ()
          (bicycle--show-children
           (- outline-code-level (bicycle--top-level) 1)
           t)))
      (bicycle--message "TOC"))
     ((bicycle--maybe-cycle 'outline-cycle-toc 'outline-cycle-trees
        (lambda () (cdr (bicycle--child-types)))
        #'outline-show-branches)
      (bicycle--message "TREES"))
     ((eq last-command 'outline-cycle-trees)
      (outline-show-all)
      (bicycle--message "ALL"))
     (t
      (outline-hide-sublevels (bicycle--level))
      (bicycle--message "OVERVIEW")
      (setq this-command 'outline-cycle-overview)))))

(defun bicycle-cycle-local ()
  "Cycle visibility of the current section.

If point is within a code block, then toggle its visibility,
provided `hs-minor-mode' is enabled.  Otherwise move to the
previous outline heading.

If point is in between code blocks, then move to the previous
outline heading.

If point is within an outline heading line, then rotate the
visibility of that subtree through these four states:

1. FOLDED:   Show only the current heading.

2. CHILDREN: Show headings of children,
             treating top-level code block as sections
             (i.e., their first line is treated as a heading).

3. HEADINGS: Recursively show headings of all subsections,
             without treating top-level code blocks as sections.

3. BRANCHES: Recursively show headings of all subsections,
             treating top-level code block as sections
             (i.e., their first line is treated as a heading).

5. SUBTREE:  Show the entire subtree, including code blocks,
             empty lines and comments.
             However, do not expand code blocks that were
             previously collapsed individually.

If the section has no children then toggle between HIDE and SHOW.
This also works for code blocks.  This is one way to collapsed a
code block \"individually\", with has the side-effect mentioned
above.

If the section has no body (not even empty lines), then there is
only one state, EMPTY, and cycling does nothing."
  (let ((eol (save-excursion (end-of-visible-line)    (point)))
        (eoh (save-excursion (outline-end-of-heading) (point)))
        (eos (save-excursion (outline-end-of-subtree) (point))))
    (setq deactivate-mark t)
    (skip-chars-forward "\s\t")
    (cond
     ((and hs-minor-mode
           (bicycle--code-level-p)
           (or (hs-looking-at-block-start-p)
               (hs-find-block-beginning)))
      (cond
       ((outline-invisible-p eoh)
        (outline-show-entry)
        (hs-life-goes-on
         (when (hs-already-hidden-p)
           (save-excursion (hs-show-block)))))
       (t
        (hs-life-goes-on
         (if (hs-already-hidden-p)
             (progn
               (save-excursion (hs-show-block))
               (outline-show-entry))
           (save-excursion (hs-hide-block))
           (outline-hide-entry))))))
     ((save-excursion
        (beginning-of-line 1)
        (not (outline-on-heading-p t)))
      (outline-back-to-heading)
      (when (bicycle--code-level-p)
        (outline-up-heading 1)))
     (t
      (outline-back-to-heading)
      (cond
       ((bicycle--code-level-p)
        (outline-toggle-children)
        (bicycle--message "CODE"))
       ((or (= eos eoh)
            (= (1+ eoh) (point-max)))
        (outline-show-entry)
        (bicycle--message "EMPTY"))
       ((null (bicycle--child-types))
        (cond ((outline-invisible-p eoh)
               (outline-show-entry)
               (bicycle--message "SHOW"))
              (t
               (outline-hide-entry)
               (bicycle--message "HIDE"))))
       ((and (>= eol eos)
             (not (eq last-command 'outline-cycle-children)))
        (bicycle--show-children)
        (bicycle--message "CHILDREN")
        (setq this-command 'outline-cycle-children))
       ((and (not (derived-mode-p 'outline-mode))
             (bicycle--maybe-cycle
               'outline-cycle-children 'outline-cycle-headings
               #'bicycle--non-code-children-p
               #'outline-show-children
               eoh eos))
        (bicycle--message "HEADINGS"))
       ((and (not (derived-mode-p 'outline-mode))
             (bicycle--maybe-cycle
               'outline-cycle-headings 'outline-cycle-branches
               (lambda () (not (bicycle--code-level-p)))
               #'outline-show-branches
               eoh eos))
        (bicycle--message "BRANCHES"))
       ((eq last-command 'outline-cycle-branches)
        (outline-show-subtree)
        (bicycle--message "SUBTREE"))
       (t
        (outline-hide-subtree)
        (bicycle--message "FOLDED")))))))

;;; Utilities

(defun bicycle--maybe-cycle (last-cmd this-cmd pred cycle &optional beg end)
  (declare (indent defun))
  (and (eq last-command last-cmd)
       (let ((noop t))
         (outline-map-region (lambda ()
                               (when (funcall pred)
                                 (funcall cycle)
                                 (setq noop nil)))
                             (or beg (point-min))
                             (or end (point-max)))
         (if noop
             (setq last-command this-cmd)
           (setq this-command this-cmd))
         (not noop))))

(defun bicycle--show-children (&optional level nocode)
  "Show all direct subheadings of this heading.
Prefix arg LEVEL is how many levels below the current level
should be shown.  Default is enough to cause the following
heading to appear.  Unlike for `outline-show-children' code
is not considered to be a sublevel."
  (interactive "P")
  (if (or level
          (derived-mode-p 'outline-mode)
          (not (bicycle--non-code-children-p)))
      (outline-show-children level)
    (let ((start-level (funcall outline-level))
          (eos (save-excursion (outline-end-of-subtree) (point)))
          (eoc nil))
      (save-excursion
        (outline-back-to-heading)
        (while (and (not level) (outline-next-heading))
          (cond
           ((eobp)
            (setq level 1))
           ((bicycle--code-level-p)
            (unless level
              (setq eoc (1+ (point)))))
           ((not (> (point) eos))
            (setq level (max 1 (- (funcall outline-level) start-level)))))))
      (outline-show-children
       (or level (max 1 (- outline-code-level start-level))))
      (when (and eoc (not nocode))
        (save-excursion
          (outline-back-to-heading)
          (outline-end-of-heading)
          (outline-map-region #'outline-show-heading (point) eoc))))))

(defun bicycle--level ()
  "Return the depth to which a statement is nested in the outline.
Point must be on a header line (but unlike for `outline-level',
not necessarily at its beginning)."
  (and (outline-on-heading-p t)
       (save-excursion
         (beginning-of-line)
         (funcall outline-level))))

(defvar-local bicycle--top-level nil)

(defun bicycle--top-level ()
  "Return the number identifying the top-level in this buffer.
Ideally this would always be 1, then we would not have to
guess and risk that the guess was wrong, but sadly this
number depends on the regexp used to identify headings."
  (or bicycle--top-level
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (let ((min (or (bicycle--level) outline-code-level)))
            (while (outline-next-heading)
              (setq min (min min (bicycle--level))))
            (setq bicycle--top-level min))))))

(defun bicycle--top-level-p ()
  "Return t if inside the heading of a top-level section."
  (let ((lvl (bicycle--level))
        (top (bicycle--top-level)))
    (when (< lvl top)
      (setq bicycle--top-level nil)
      (setq top (bicycle--top-level)))
    (= lvl top)))

(defun bicycle--code-level-p ()
  "Return t if inside a code block.
On outline headings and in between code blocks,
return nil."
  (= (funcall outline-level) outline-code-level))

(defun bicycle--non-code-children-p ()
  "Return t if the current section has subsections."
  (catch 'non-code
    (save-excursion
      (outline-back-to-heading)
      (outline-end-of-heading)
      (outline-map-region
       (lambda ()
         (and (not (bicycle--code-level-p))
              (throw 'non-code t)))
       (point)
       (progn (outline-end-of-subtree)
              (if (eobp) (point-max) (1+ (point))))))
    nil))

(defun bicycle--child-types ()
  "Indicate what types of children the current section has.
If the current section has no children, then return nil.
Otherwise return (HEADINGS . CODE), where HEADINGS and
CODE are booleans indicating whether the section contains
headings and/or code blocks."
  (let (headings code)
    (catch 'both
      (save-excursion
        (outline-back-to-heading)
        (outline-end-of-heading)
        (outline-map-region
         (lambda ()
           (if (bicycle--code-level-p)
               (setq code t)
             (setq headings t))
           (when (and headings code)
             (throw 'both nil)))
         (point)
         (progn (outline-end-of-subtree)
                (if (eobp) (point-max) (1+ (point)))))))
    (and (or headings code)
         (cons headings code))))

(defun bicycle--message (format-string &rest args)
  "Like `message' but if `bicycle-echo-state' is nil then do nothing."
  (when bicycle-echo-state
    (apply #'message format-string args)))

;;; _
(provide 'bicycle)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; bicycle.el ends here
