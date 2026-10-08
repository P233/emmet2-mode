;;; emmet2-preview.el --- Fontified preview buffers for expansions -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Keep one hidden, read-only buffer per output syntax (html, jsx and css)
;; for completion previews.  Callers supply the final text; no source
;; analysis, expansion, snippet or user mode hook runs here.

;;; Code:
(require 'font-lock)

(defvar emmet2-preview--buffers nil
  "Preview buffers, at most one each for html, jsx and css.")

(defvar shr-color-html-colors-alist)

(defun emmet2-preview--color-face (hex)
  "Return a face displaying the CSS color HEX on itself, without its alpha digits."
  (let ((color (substring hex 0 (if (> (length hex) 5) 7 4))))
    (list :background color :foreground (readable-foreground-color color)
          :box '(:line-width -1))))

(defconst emmet2-preview--css-keywords
  '(("^[ \t]*\\(-\\{0,2\\}[[:alpha:]][-[:alnum:]]*\\)[ \t]*:" 1 'font-lock-keyword-face)
    ("@[-[:alnum:]]+" . 'font-lock-builtin-face)
    ("\\$[-_[:alnum:]]+" . 'font-lock-variable-name-face)
    ("![ \t]*important" . 'font-lock-builtin-face)
    ("#\\(?:[[:xdigit:]]\\{8\\}\\|[[:xdigit:]]\\{6\\}\\|[[:xdigit:]]\\{3,4\\}\\)\\_>"
     0 (emmet2-preview--color-face (match-string 0)))
    (emmet2-preview--match-color-name
     0 (emmet2-preview--color-face
        (cdr (assoc-string (match-string 0) shr-color-html-colors-alist t)))))
  "Font Lock rules for the declarations and at-rules that Emmet writes.")

(defun emmet2-preview--match-color-name (limit)
  "Match the next CSS color name in a declaration value before LIMIT."
  (catch 'found
    (while (re-search-forward "\\_<[[:alpha:]]+\\_>" limit t)
      (let ((data (match-data t)))
        (when (and (assoc-string (match-string 0) shr-color-html-colors-alist t)
                   (not (eq (char-after) ?\())
                   (save-excursion
                     (goto-char (car data))
                     (and (not (nth 8 (syntax-ppss)))
                          (search-backward ":" (line-beginning-position) t))))
          (set-match-data data)
          (throw 'found t))))
    nil))

(defconst emmet2-preview--css-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?/ ". 14" table)
    (modify-syntax-entry ?* ". 23b" table)
    (modify-syntax-entry ?\' "\"" table)
    (dolist (char '(?@ ?# ?. ?- ?$))
      (modify-syntax-entry char "_" table))
    table)
  "Syntax table of CSS previews: comments, strings and name characters.")

;; Loading css-mode for a preview would also load eww, shr and SMIE.
(define-derived-mode emmet2-preview-css-mode prog-mode "Emmet CSS"
  "Color an Emmet CSS expansion as `css-mode' would, without loading it."
  :syntax-table emmet2-preview--css-syntax-table
  :abbrev-table nil
  (require 'shr-color)
  (setq-local font-lock-defaults '(emmet2-preview--css-keywords)))

(defun emmet2-preview--kill (buffer)
  "Kill BUFFER, ignoring `kill-buffer-query-functions'.
A veto would leave a preview buffer that nothing tracks any more."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((kill-buffer-query-functions nil)) (kill-buffer buffer)))))

(defun emmet2-preview--create (syntax mode)
  "Create the owned preview buffer for SYNTAX using MODE."
  (let ((buffer (generate-new-buffer (format " *emmet2-preview-%s*" syntax))) complete)
    (unwind-protect
        (with-current-buffer buffer
          (let ((change-major-mode-hook nil))
            (delay-mode-hooks (funcall mode)))
          ;; Do not leave deferred user hooks for a later mode transition.
          (setq delayed-mode-hooks nil delayed-after-hook-functions nil)
          (buffer-disable-undo)
          (setq buffer-read-only t)
          (setf (alist-get syntax emmet2-preview--buffers) buffer)
          (setq complete t)
          buffer)
      (unless complete (emmet2-preview--kill buffer)))))

;;;###autoload
(defun emmet2-preview (text syntax)
  "Return a read-only, fontified buffer containing exactly TEXT.
SYNTAX is html, jsx or css and selects the major mode; any other value
signals an error.  The buffer is reused for the next preview of the same
SYNTAX, so display it but do not modify or keep it; `emmet2-preview-clear'
kills it.  The current buffer, point and text are unchanged."
  (let* ((mode (pcase syntax ('html #'html-mode) ('jsx #'js-jsx-mode) ('css #'emmet2-preview-css-mode)
                     (_ (error "Unsupported Emmet preview syntax: %s" syntax))))
         (existing (alist-get syntax emmet2-preview--buffers))
         (buffer (if (buffer-live-p existing) existing (emmet2-preview--create syntax mode))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (widen)
        ;; Font Lock mode is off here, so `font-lock-ensure' would refontify unchanged text.
        (unless (equal text (buffer-substring-no-properties (point-min) (point-max)))
          (let (complete)
            (unwind-protect
                (progn (erase-buffer) (insert text) (font-lock-ensure) (setq complete t))
              ;; Partly fontified text must not pass for a finished preview.
              (unless complete (erase-buffer)))))
        (goto-char (point-min))
        (set-buffer-modified-p nil)))
    buffer))

(defun emmet2-preview-clear ()
  "Delete all owned preview buffers."
  (dolist (entry emmet2-preview--buffers)
    (emmet2-preview--kill (cdr entry)))
  (setq emmet2-preview--buffers nil))

(defun emmet2-preview-unload-function ()
  "Release preview resources when unloading the module."
  (emmet2-preview-clear)
  nil)

(provide 'emmet2-preview)
;;; emmet2-preview.el ends here
