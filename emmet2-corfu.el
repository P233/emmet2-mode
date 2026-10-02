;;; emmet2-corfu.el --- Optional Corfu presentation adapter -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Keep Emmet labels in Corfu's main column, anchor each completion popup at
;; its initial cursor position and keep it open for an unchanged abbreviation.
;; Candidate payloads and user frontend settings remain unchanged.  Corfu is
;; not required or enabled here.

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

(defun emmet2-corfu--try-completion (try str table pred pt &rest rest)
  "Call TRY with STR, TABLE, PRED, PT and REST; Emmet input is never complete.
Each Emmet choice's text is the abbreviation, which accepting expands.  Corfu
then behaves as with `corfu-on-exact-match' set to `show', for Emmet only.
REST may hold Corfu's metadata; other arguments pass through unchanged."
  (let ((result (apply try str table pred pt rest)))
    (if (and (eq result t)
             (eq (completion-metadata-get
                  (or (car rest) (completion-metadata (substring str 0 pt) table pred)) 'category)
                 'emmet2))
        (cons str pt)
      result)))

(defun emmet2-corfu--enable ()
  "Install the category-scoped display adapter without loading Corfu.
Repeated installation is idempotent, including after package unload.  An
installed advice is left in place; re-adding it would move it outside advice
added later by the user."
  (unless (advice-member-p #'emmet2-corfu--rows 'corfu--format-candidates)
    (advice-add 'corfu--format-candidates :filter-args #'emmet2-corfu--rows))
  (unless (advice-member-p #'emmet2-corfu--anchor 'corfu--candidates-popup)
    (advice-add 'corfu--candidates-popup :around #'emmet2-corfu--anchor))
  (unless (advice-member-p #'emmet2-corfu--try-completion 'corfu--try-completion)
    (advice-add 'corfu--try-completion :around #'emmet2-corfu--try-completion)))

(defun emmet2-corfu-unload-function ()
  "Remove the optional Corfu advice owned by this module."
  (advice-remove 'corfu--format-candidates #'emmet2-corfu--rows)
  (advice-remove 'corfu--candidates-popup #'emmet2-corfu--anchor)
  (advice-remove 'corfu--try-completion #'emmet2-corfu--try-completion)
  nil)

(provide 'emmet2-corfu)
;;; emmet2-corfu.el ends here
