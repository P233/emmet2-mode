;;; emmet2-corfu.el --- Optional Corfu adapter for emmet2 completion tables -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; While Corfu shows Emmet candidates, keep their labels in the main column,
;; keep the popup at its first cursor position, and never let Corfu treat the
;; typed abbreviation as complete, so a sole choice stays open.  For Emmet
;; candidates and the name tables of `emmet2-completion-capf', Corfu's row
;; formatting also returns strings without a line break as they are, instead
;; of copying each one on every refresh.  Other candidates and user settings
;; are unchanged.  Corfu is not required or enabled here.

;;; Code:
(eval-when-compile (require 'cl-lib))
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
                        (let ((label (or (get-text-property 0 'emmet2--label (car row)) (cadr row))))
                          (list (if (<= (string-width label) width)
                                    (copy-sequence label)
                                  (truncate-string-to-width label width nil nil "…"))
                                "" "")))
                      (car arguments))))
    arguments))

(defun emmet2-corfu--own-table-p ()
  "Return non-nil when emmet2-mode built the table Corfu is completing from.
These are Emmet tables, of the `emmet2' category, and the name tables of
`emmet2-completion-capf', whose metadata carries `emmet2-identity'."
  (or (eq (corfu--metadata-get 'category) 'emmet2)
      (corfu--metadata-get 'emmet2-identity)))

(defun emmet2-corfu--format (format candidates)
  "Call FORMAT with CANDIDATES, sparing emmet2 rows a needless copy.
Corfu replaces each row string's line breaks with `replace-regexp-in-string',
which copies the string even when it has none.  While FORMAT formats a table
of `emmet2-corfu--own-table-p', exactly that replacement returns a string
without a line break unchanged; any other call runs as usual."
  (if (emmet2-corfu--own-table-p)
      (let ((replace (symbol-function 'replace-regexp-in-string)))
        ;; INTERIM (since 2026-10-03, until Corfu skips strings without line breaks): see ARCHITECTURE.md#corfu-adapter.
        (cl-letf (((symbol-function 'replace-regexp-in-string)
                   (lambda (regexp rep string &rest rest)
                     (if (and (null rest) (stringp string)
                              (equal regexp "[ \t]*\n[ \t]*") (equal rep " ")
                              (not (string-search "\n" string)))
                         string
                       (apply replace regexp rep string rest)))))
          (funcall format candidates)))
    (funcall format candidates)))

(defun emmet2-corfu--anchor (show position)
  "Call SHOW at the Emmet session's first cursor position, else POSITION."
  (if (eq (corfu--metadata-get 'category) 'emmet2)
      (let* ((properties (nth 4 completion-in-region--data))
             (anchor (plist-get properties :emmet2-corfu-anchor)))
        (unless anchor
          (setq anchor (or (posn-at-point) position))
          ;; Corfu discards this session data on exit, so the anchor needs no cleanup.
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
  "Advise Corfu for tables emmet2-mode builds, without loading Corfu.
The advice formats Emmet rows, keeps the popup at its first position and
keeps a sole Emmet choice open; rows of every table emmet2-mode builds skip
a needless copy.  Other candidates are unaffected.  Installing again changes
nothing, also after `emmet2-corfu-unload-function'.  Existing advice stays in
place, so it keeps its order relative to advice added later by the user."
  (unless (advice-member-p #'emmet2-corfu--rows 'corfu--format-candidates)
    (advice-add 'corfu--format-candidates :filter-args #'emmet2-corfu--rows))
  (unless (advice-member-p #'emmet2-corfu--format 'corfu--format-candidates)
    (advice-add 'corfu--format-candidates :around #'emmet2-corfu--format))
  (unless (advice-member-p #'emmet2-corfu--anchor 'corfu--candidates-popup)
    (advice-add 'corfu--candidates-popup :around #'emmet2-corfu--anchor))
  (unless (advice-member-p #'emmet2-corfu--try-completion 'corfu--try-completion)
    (advice-add 'corfu--try-completion :around #'emmet2-corfu--try-completion)))

(defun emmet2-corfu-unload-function ()
  "Remove the optional Corfu advice owned by this module."
  (advice-remove 'corfu--format-candidates #'emmet2-corfu--rows)
  (advice-remove 'corfu--format-candidates #'emmet2-corfu--format)
  (advice-remove 'corfu--candidates-popup #'emmet2-corfu--anchor)
  (advice-remove 'corfu--try-completion #'emmet2-corfu--try-completion)
  nil)

(provide 'emmet2-corfu)
;;; emmet2-corfu.el ends here
