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
  (let* ((mode (pcase syntax ('html #'html-mode) ('jsx #'js-jsx-mode) ('css #'css-mode)
                     (_ (error "Unsupported Emmet preview syntax: %s" syntax))))
         (existing (alist-get syntax emmet2-preview--buffers))
         (buffer (if (buffer-live-p existing) existing (emmet2-preview--create syntax mode))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (widen)
        (unless (equal text (buffer-substring-no-properties (point-min) (point-max)))
          (erase-buffer)
          (insert text))
        (font-lock-ensure)
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
