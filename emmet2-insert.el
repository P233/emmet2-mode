;;; emmet2-insert.el --- Rendering and atomic source replacement -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; The formatter owns layout.  This module captures a source snapshot, encodes
;; canonical fields for optional yasnippet, and owns the single text mutation.

;;; Code:

(require 'cl-lib)
(require 'emmet2-engine)
(defvar emmet2-context-provider)
(declare-function yas-expand-snippet "yasnippet" (snippet &optional start end expand-env))
(declare-function yas-minor-mode "yasnippet" (&optional arg))
(defvar yas--escaped-characters)
(defvar yas-before-expand-snippet-hook)
(defvar yas-after-exit-snippet-hook)
(defvar emmet2-insert--yas-fields nil
  "Non-nil only inside the expansion environment of an Emmet snippet.")

(defun emmet2-insert--yas-protect-text (original &rest args)
  "Call yas protection ORIGINAL with ARGS without changing Emmet's text.
Yas adds a newline for an EOF field solely to extend its protection overlay.
Emacs already clips that overlay to the buffer end.  Scope this compatibility
fix to Emmet snippets; retain all of yas's overlay and field bookkeeping."
  (if emmet2-insert--yas-fields
      (cl-letf (((symbol-function 'newline) #'ignore)) (apply original args))
    (apply original args)))

(defun emmet2-insert--indent-width (analysis)
  "Read ANALYSIS's host width, or the active mode's indentation width."
  (if (plist-member analysis :indent-width) (plist-get analysis :indent-width)
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
  "Derive formatter indentation from ANALYSIS without changing the buffer.
Use the abbreviation's display column, including tabs and wide characters.
Unaligned nesting uses spaces so every level advances by the mode's width.
ANALYSIS may supply :indent-width to use an external host's width instead."
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
  "Capture the source identity for one expansion of ANALYSIS.
This short-lived value owns no markers, parser, timer or mutable cache."
  (list :buffer (current-buffer) :mode major-mode :tick (buffer-chars-modified-tick)
        :point (point) :beg (plist-get analysis :beg) :end (plist-get analysis :end)
        :abbr (plist-get analysis :abbr)
        :field-navigation (plist-get (bound-and-true-p emmet2-context-provider)
                                    :field-navigation)))

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
  "Quote literal TEXT in a yasnippet body or field default.
Restore Y last so authored YASESCAPE...PROTECTGUARD text cannot collide with
yas's internal escape transport.  The expansion environment owns that order."
  (let ((case-fold-search nil))
    (replace-regexp-in-string "[\\\\$`{}Y]" (lambda (match) (concat "\\" match)) text t t)))

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

(defun emmet2-insert (snapshot result)
  "Atomically replace SNAPSHOT with canonical RESULT in the current buffer.
Reject stale source before any change.  An installed yasnippet owns fields;
as in Eglot, its mode is enabled on demand.  Otherwise place point at the same
initial cursor.  Hosts that request their own field navigation use the same
initial cursor without YAS fields.  Do not reformat the text."
  (unless (emmet2-insert-snapshot-valid-p snapshot)
    (signal 'emmet2-error '("Source changed before expansion could be inserted")))
  (let* ((beg (plist-get snapshot :beg)) (end (plist-get snapshot :end))
         (original-point (point)) (success nil)
         (template (when (and (not (eq (plist-get snapshot :field-navigation) 'host))
                              (plist-get result :fields) (fboundp 'yas-minor-mode))
                     (emmet2-insert--template result))))
    (undo-boundary)
    (unwind-protect
        (progn
          (with-undo-amalgamate
            (atomic-change-group
              (if template
                  (progn
                    ;; Activation runs user hooks too.  Include their text
                    ;; changes in the same rollback as snippet expansion.
                    (unless (bound-and-true-p yas-minor-mode) (yas-minor-mode 1))
                    (advice-add 'yas--make-move-field-protection-overlays :around #'emmet2-insert--yas-protect-text)
                    (let ((yas-before-expand-snippet-hook
                           (append yas-before-expand-snippet-hook
                                   (list (lambda ()
                                           (unless (emmet2-insert-snapshot-valid-p snapshot)
                                             (signal 'emmet2-error '("Source changed in yas before-expand hook"))))))))
                      (yas-expand-snippet
                       template beg end
                       `((yas-indent-line nil) (yas-wrap-around-region nil) (case-fold-search nil)
                         (emmet2-insert--yas-fields t)
                         ;; web-mode otherwise reformats the whole expansion on exit.
                         (yas-after-exit-snippet-hook
                          (remq 'web-mode-yasnippet-exit-hook yas-after-exit-snippet-hook))
                         (yas--escaped-characters ',(append (remq ?Y yas--escaped-characters) '(?Y)))))))
                (delete-region beg end)
                (goto-char beg) (insert (plist-get result :text))
                (goto-char (+ beg (plist-get result :cursor))))))
          (setq success t)
          (undo-boundary))
      (unless success (goto-char original-point)))))

(defun emmet2-insert-unload-function ()
  "Remove the optional yas compatibility advice owned by this module."
  (advice-remove 'yas--make-move-field-protection-overlays #'emmet2-insert--yas-protect-text)
  nil)

(provide 'emmet2-insert)
;;; emmet2-insert.el ends here
