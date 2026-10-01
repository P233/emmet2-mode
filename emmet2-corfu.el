;;; emmet2-corfu.el --- Optional Corfu presentation adapter -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Keep Emmet labels in Corfu's main column and anchor each completion popup
;; at its initial cursor position.  Candidate payloads and user frontend
;; settings remain unchanged.  Corfu is not required or enabled here.

;;; Code:
(declare-function corfu--metadata-get "ext:corfu" (property))
(defvar corfu-max-width)

(defun emmet2-corfu--rows (arguments)
  "Move Emmet labels to the main display column in Corfu's ARGUMENTS."
  (if (eq (corfu--metadata-get 'category) 'emmet2)
      ;; CAPF affixes keep candidate identities intact for other frontends.
      ;; Only Corfu's display copy uses the label as the main column.  Margin
      ;; formatters such as icon packages replace the prefix, so rows read the
      ;; label from the candidate and stay plain text.
      (let ((width (min corfu-max-width (- (frame-width) 4))))
        (list (mapcar (lambda (row)
                        (list (truncate-string-to-width
                               (or (get-text-property 0 'emmet2--label (car row)) (cadr row))
                               width nil nil "…")
                              "" ""))
                      (car arguments))))
    arguments))

(defun emmet2-corfu--anchor (show position)
  "Call SHOW at the Emmet session's first cursor position, else POSITION."
  (if (eq (corfu--metadata-get 'category) 'emmet2)
      (let* ((properties (nth 4 completion-in-region--data))
             (anchor (plist-get properties :emmet2-corfu-anchor)))
        (unless anchor
          (setq anchor (or (posn-at-point) position))
          ;; The completion session owns this position and releases it on exit.
          (setf (nth 4 completion-in-region--data)
                (plist-put properties :emmet2-corfu-anchor anchor)))
        (funcall show anchor))
    (funcall show position)))

(defun emmet2-corfu--enable ()
  "Install the category-scoped display adapter without loading Corfu.
Repeated installation is idempotent, including after package unload."
  (advice-add 'corfu--format-candidates :filter-args #'emmet2-corfu--rows)
  (advice-add 'corfu--candidates-popup :around #'emmet2-corfu--anchor))

(defun emmet2-corfu-unload-function ()
  "Remove the optional Corfu advice owned by this module."
  (advice-remove 'corfu--format-candidates #'emmet2-corfu--rows)
  (advice-remove 'corfu--candidates-popup #'emmet2-corfu--anchor)
  nil)

(provide 'emmet2-corfu)
;;; emmet2-corfu.el ends here
