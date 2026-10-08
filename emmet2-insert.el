;;; emmet2-insert.el --- Source snapshots and atomic insertion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Expansion text arrives formatted and is inserted as is.  This module
;; captures the source snapshot before expansion, turns markup fields into a
;; yasnippet template when yasnippet is installed, and makes the one buffer
;; edit of each expansion.

;;; Code:

(require 'cl-lib)
(require 'emmet2-engine)
(declare-function yas-expand-snippet "yasnippet" (snippet &optional start end expand-env))
(declare-function yas-minor-mode "yasnippet" (&optional arg))
(defvar yas-before-expand-snippet-hook)
(defvar yas-after-exit-snippet-hook)

(defcustom emmet2-css-auto-newline t
  "Whether complete CSS declarations continue on the next line.
In `css-base-mode' derivatives, including CSS and SCSS modes, an expansion
at a declaration start moves to the next line when the abbreviation is
alone on its line and the result ends in a semicolon with no fields.
Reuse an immediately following blank line, or insert one, with the source
line's indentation.  Expansion and continuation share one undo step.
Embedded styles, value completion and incomplete fields are unaffected."
  :type 'boolean :safe #'booleanp :group 'emmet2)

(defun emmet2-insert--indent-width (analysis)
  "Read ANALYSIS's host width, or the active mode's indentation width."
  (or (plist-get analysis :indent-width)
    (let* ((variables
            (cond
             ((derived-mode-p 'web-mode)
              (list (cond ((eq (plist-get analysis :lang) 'css) 'web-mode-css-indent-offset)
                          ((or (eq (plist-get analysis :lang) 'css-in-js)
                               (eq (plist-get analysis :syntax) 'jsx)) 'web-mode-code-indent-offset)
                          (t 'web-mode-markup-indent-offset))))
             ((derived-mode-p 'typescript-ts-mode 'tsx-ts-mode)
              '(typescript-ts-indent-offset typescript-ts-mode-indent-offset))
             ((derived-mode-p 'js-mode 'js-ts-mode)
              (if (eq (plist-get analysis :lang) 'markup)
                  '(js-jsx-indent-level js-indent-level) '(js-indent-level)))
             ((derived-mode-p 'css-base-mode) '(css-indent-offset))
             ((derived-mode-p 'sgml-mode) '(sgml-basic-offset))))
           (width (cl-loop for variable in variables
                           when (and (boundp variable) (integerp (symbol-value variable)))
                           return (symbol-value variable))))
      (or width standard-indent))))

(defun emmet2-insert--whitespace (columns)
  "Return whitespace spanning COLUMNS from column zero."
  (if indent-tabs-mode
      (concat (make-string (/ columns tab-width) ?\t) (make-string (% columns tab-width) ?\s))
    (make-string columns ?\s)))

(defun emmet2-insert-render-options (analysis)
  "Return the indentation options for expanding ANALYSIS.
The value is a plist (:indent STRING :base-indent STRING) for the expansion
functions.  :base-indent spans the abbreviation's display column, including
tabs and wide characters.  :indent is one level of the mode's indentation
width, or of ANALYSIS's :indent-width; it uses spaces unless both the column
and the width are multiples of `tab-width' under `indent-tabs-mode'.  Signal
`emmet2-error' when the width is not a nonnegative integer.  The buffer is
not changed."
  (save-excursion
    (goto-char (plist-get analysis :beg))
    (let ((column (current-column)) (width (emmet2-insert--indent-width analysis)))
      (unless (and (integerp width) (>= width 0))
        (signal 'emmet2-error '("Mode indentation must be a nonnegative integer")))
      (list :indent (if (and indent-tabs-mode (zerop (% column tab-width))
                            (zerop (% width tab-width)))
                       (emmet2-insert--whitespace width) (make-string width ?\s))
            :base-indent (emmet2-insert--whitespace column)))))

(defun emmet2-insert-snapshot (analysis)
  "Return a snapshot of the source that ANALYSIS would replace.
The snapshot records the buffer, major mode, modification tick, point,
bounds, abbreviation, language and insertion role.  `emmet2-insert' rejects
stale source snapshots, so capture it before expanding and never reuse it.
It holds no markers or other resources and needs no cleanup."
  (list :buffer (current-buffer) :mode major-mode :tick (buffer-chars-modified-tick)
        :point (point) :beg (plist-get analysis :beg) :end (plist-get analysis :end)
        :abbr (plist-get analysis :abbr) :lang (plist-get analysis :lang)
        :position (plist-get analysis :position)))

(defun emmet2-insert-snapshot-valid-p (snapshot)
  "Whether SNAPSHOT still describes the current source and point."
  (and (eq (current-buffer) (plist-get snapshot :buffer))
       (eq major-mode (plist-get snapshot :mode))
       (= (buffer-chars-modified-tick) (plist-get snapshot :tick))
       (= (point) (plist-get snapshot :point))
       (<= (point-min) (plist-get snapshot :beg) (plist-get snapshot :end) (point-max))
       (equal (buffer-substring-no-properties (plist-get snapshot :beg) (plist-get snapshot :end))
              (plist-get snapshot :abbr))))

(defun emmet2-insert--escape (text)
  "Quote literal TEXT in a yasnippet body or field default."
  (replace-regexp-in-string "[\\\\$`{}]" (lambda (match) (concat "\\" match)) text t t))

(defun emmet2-insert--template (result)
  "Encode canonical RESULT as a yasnippet template with a final exit."
  (let ((text (plist-get result :text)) (seen (make-hash-table :test #'eql))
        (offset 0) parts)
    ;; Zero-width fields at a nonempty field's start must precede its text.
    (dolist (field (cl-stable-sort (copy-sequence (plist-get result :fields))
                                  (lambda (a b) (or (< (car a) (car b))
                                                   (and (= (car a) (car b)) (< (cadr a) (cadr b)))))))
      (pcase-let ((`(,beg ,end ,index ,placeholder) field))
        (push (emmet2-insert--escape (substring text offset beg)) parts)
        (push (if (gethash index seen) (format "${%d}" index)
                (puthash index t seen)
                (format "${%d:%s}" index (emmet2-insert--escape placeholder))) parts)
        (setq offset end)))
    (push (emmet2-insert--escape (substring text offset)) parts)
    (concat (apply #'concat (nreverse parts)) "$0")))

(defun emmet2-insert--css-continuation-indent (snapshot result)
  "Return the continuation indentation for SNAPSHOT and RESULT, or nil."
  (when (and emmet2-css-auto-newline (derived-mode-p 'css-base-mode)
             (eq (plist-get snapshot :lang) 'css)
             (eq (plist-get snapshot :position) 'declaration-start)
             (not (plist-get result :fields))
             (= (plist-get result :cursor) (length (plist-get result :text)))
             (string-suffix-p ";" (plist-get result :text)))
    (let ((beg (plist-get snapshot :beg)) (end (plist-get snapshot :end))
          (limit (point-max)))
      (save-excursion
        (save-restriction
          ;; Narrowing must not conceal adjacent code or an existing blank line.
          (widen)
          (goto-char beg)
          (let ((line-beg (line-beginning-position)))
            (when (and (<= end (line-end-position))
                       (<= (line-end-position 2) limit)
                       (progn (skip-chars-backward " \t") (bolp))
                       (progn (goto-char end) (skip-chars-forward " \t") (eolp)))
              (buffer-substring-no-properties line-beg beg))))))))

(defun emmet2-insert--css-continue (indent)
  "Move from a completed declaration to a blank line with INDENT."
  (delete-region (point) (line-end-position))
  (if (eobp)
      (insert "\n")
    (forward-char)
    (unless (looking-at-p "[ \t]*$")
      (insert "\n") (backward-char)))
  (delete-region (point) (line-end-position))
  (insert indent))

(defun emmet2-insert (snapshot result)
  "Replace SNAPSHOT's abbreviation with RESULT's text as one undoable change.
Signal `emmet2-error' without changing the buffer when SNAPSHOT no longer
matches it; see `emmet2-insert-snapshot-valid-p'.  For markup, when
yasnippet is installed, RESULT's fields become snippet fields and
`yas-minor-mode' is enabled if needed, as Eglot does.  Otherwise, including
every CSS and CSS-in-JS result, point moves to RESULT's :cursor and no
fields are created, so TAB keeps its binding.  The text is inserted as is,
without reindenting; a non-markup result ending in a semicolon also replaces
a semicolon right after the abbreviation, so the declaration keeps one
terminator.  With `emmet2-css-auto-newline', complete standalone
CSS declarations continue on an indented blank line in the same undo group.
On any error the buffer and point are restored."
  (unless (emmet2-insert-snapshot-valid-p snapshot)
    (signal 'emmet2-error '("Source changed before expansion could be inserted")))
  (let* ((beg (plist-get snapshot :beg)) (end (plist-get snapshot :end))
         (original-point (point)) (success nil)
         (continuation (emmet2-insert--css-continuation-indent snapshot result))
         (template (when (and (eq (plist-get snapshot :lang) 'markup)
                              (plist-get result :fields) (fboundp 'yas-minor-mode))
                     (emmet2-insert--template result))))
    (undo-boundary)
    (unwind-protect
        (progn
          (with-undo-amalgamate
            (atomic-change-group
              ;; Restore the source buffer before transaction and point cleanup.
              (save-current-buffer
                (if template
                    (progn
                      ;; Enabling yas-minor-mode runs user hooks; roll back their edits with the snippet's.
                      (unless (bound-and-true-p yas-minor-mode) (yas-minor-mode 1))
                      (let ((yas-before-expand-snippet-hook
                             (append yas-before-expand-snippet-hook
                                     (list (lambda ()
                                             (unless (emmet2-insert-snapshot-valid-p snapshot)
                                               (signal 'emmet2-error '("Source changed in yas before-expand hook"))))))))
                        (yas-expand-snippet
                         template beg end
                         `((yas-indent-line nil) (yas-wrap-around-region nil) (case-fold-search nil)
                           ;; web-mode otherwise reformats the whole expansion on exit.
                           (yas-after-exit-snippet-hook
                            (remq 'web-mode-yasnippet-exit-hook yas-after-exit-snippet-hook))))))
                  (delete-region beg (if (and (not (eq (plist-get snapshot :lang) 'markup))
                                              (string-suffix-p ";" (plist-get result :text))
                                              (eq (char-after end) ?\;))
                                         (1+ end) end))
                  (goto-char beg) (insert (plist-get result :text))
                  (goto-char (+ beg (plist-get result :cursor)))
                  (when continuation (emmet2-insert--css-continue continuation))))))
          (setq success t)
          (undo-boundary))
      (unless success (goto-char original-point)))))

(provide 'emmet2-insert)
;;; emmet2-insert.el ends here
