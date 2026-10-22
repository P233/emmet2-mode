;;; emmet2-corfu.el --- Optional Corfu adapter for emmet2 completion tables -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: Peiwen Lu <hi@peiwen.lu>
;; Assisted-by: Claude:Opus-5.5
;; Assisted-by: Codex:gpt-6-astra
;; Assisted-by: Codex:gpt-6.1-sol

;;; Commentary:
;; While Corfu shows Emmet candidates, keep their labels in the main column,
;; keep the popup at its first cursor position, and never let Corfu treat the
;; typed abbreviation as complete, so a sole choice stays open.  For Emmet
;; previews only, popupinfo's side margins are temporarily zero during display,
;; including frame sizing.  Other tables keep the user's margin setting.
;; Other user settings are unchanged.  Corfu is not required or enabled here.

;;; Code:
(eval-when-compile (require 'cl-lib))
(declare-function corfu--metadata-get "ext:corfu" (property))
(defvar corfu-max-width)

(defvar corfu--candidates)
(defvar corfu-popupinfo-margin-width)

(defun emmet2-corfu--emmet-p ()
  "Whether Corfu's current table is an Emmet expansion table."
  (and (fboundp 'corfu--metadata-get)
       (eq (corfu--metadata-get 'category) 'emmet2)))

(defun emmet2-corfu--rows (format &rest arguments)
  "Call FORMAT with Emmet labels in the main column of ARGUMENTS."
  (let ((adapted
         (condition-case nil
             (when (emmet2-corfu--emmet-p)
               (let ((width (min corfu-max-width (- (frame-width) 4))))
                 (cons (mapcar (lambda (row)
                                 (let ((label (or (get-text-property 0 'emmet2--label (car row))
                                                  (cadr row))))
                                   (list (if (<= (string-width label) width)
                                             (copy-sequence label)
                                           (truncate-string-to-width label width nil nil "…"))
                                         "" "")))
                               (car arguments))
                       (cdr arguments))))
           (error nil))))
    (if adapted
        (condition-case nil (apply format adapted)
          (error (apply format arguments)))
      (apply format arguments))))

(defun emmet2-corfu--anchor (show &rest arguments)
  "Call SHOW at the Emmet session's first cursor position in ARGUMENTS."
  (let ((adapted
         (condition-case nil
             (when (emmet2-corfu--emmet-p)
               (let* ((properties (nth 4 completion-in-region--data))
                      (anchor (plist-get properties :emmet2-corfu-anchor)))
                 (unless anchor
                   (setq anchor (point))
                   (setf (nth 4 completion-in-region--data)
                         (plist-put properties :emmet2-corfu-anchor anchor)))
                 ;; Keep a buffer position, not a posn, so scrolling cannot leave the popup behind.
                 (cons (or (posn-at-point (min anchor (point-max))) (car arguments)) (cdr arguments))))
           (error nil))))
    (if adapted
        (condition-case nil (apply show adapted)
          (error (apply show arguments)))
      (apply show arguments))))

(defun emmet2-corfu--try-completion (try &rest arguments)
  "Call TRY with ARGUMENTS, keeping exact Emmet input open for expansion."
  (let ((result (apply try arguments)))
    (condition-case nil
        (pcase-let ((`(,str ,table ,pred ,pt . ,rest) arguments))
          (if (and (eq result t)
                   (eq (completion-metadata-get
                        (or (car rest) (completion-metadata (substring str 0 pt) table pred))
                        'category) 'emmet2))
              (cons str pt)
            result))
      (error result))))

(defun emmet2-corfu--popupinfo (show &rest arguments)
  "Call SHOW with zero preview margins for a current Emmet candidate.
ARGUMENTS pass through unchanged; foreign tables keep the user's margins."
  (let ((emmet
         (condition-case nil
             (and (emmet2-corfu--emmet-p)
                  (memq (car arguments) corfu--candidates)
                  (get-text-property 0 'emmet2--choice (car arguments)))
           (error nil))))
    (if emmet
        (condition-case nil
            (let ((corfu-popupinfo-margin-width 0)) (apply show arguments))
          (error (apply show arguments)))
      (apply show arguments))))

(defun emmet2-corfu--enable ()
  "Install table-scoped Corfu advice idempotently without loading Corfu."
  (dolist (entry '((corfu--format-candidates . emmet2-corfu--rows)
                   (corfu--candidates-popup . emmet2-corfu--anchor)
                   (corfu--try-completion . emmet2-corfu--try-completion)
                   (corfu-popupinfo--show . emmet2-corfu--popupinfo)))
    (unless (advice-member-p (cdr entry) (car entry))
      (advice-add (car entry) :around (cdr entry)))))

(defun emmet2-corfu-unload-function ()
  "Remove the optional Corfu advice owned by this module."
  (advice-remove 'corfu--format-candidates #'emmet2-corfu--rows)
  (advice-remove 'corfu--candidates-popup #'emmet2-corfu--anchor)
  (advice-remove 'corfu--try-completion #'emmet2-corfu--try-completion)
  (advice-remove 'corfu-popupinfo--show #'emmet2-corfu--popupinfo)
  nil)

(provide 'emmet2-corfu)
;;; emmet2-corfu.el ends here
