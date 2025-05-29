;;; emmet2-mode.el --- An Emmet-enhanced minor mode for Emacs.  -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2023 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Created: 10 Oct 2022
;; URL: https://github.com/P233/emmet2-mode
;; Compatibility: emacs-version >= 28
;; Package-Requires: ((emacs "28") (deno-bridge "0.1"))

;;; This file is NOT part of GNU Emacs

;;; License

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Please check the README.

;;; Code:
(require 'deno-bridge)

(defconst emmet2-backend-path (concat (file-name-directory load-file-name) "src/index.ts"))
(deno-bridge-start "emmet2" emmet2-backend-path)

(defvar emmet2-file-extension "")
(defvar emmet2-markup-variant nil)
(defvar emmet2-css-modules-object "css")
(defvar emmet2-class-names-constructor "clsx")

(defun emmet2-after-hook ()
  (make-local-variable 'emmet2-file-extension)
  (make-local-variable 'emmet2-markup-variant)
  (make-local-variable 'emmet2-css-modules-object)
  (make-local-variable 'emmet2-class-names-constructor)
  (setq emmet2-file-extension (file-name-extension buffer-file-name)))

(defun emmet2-check-in-between (open close)
  (let ((backward-open (save-excursion (re-search-backward open nil t)))
        (backward-close (save-excursion (re-search-backward close nil t)))
        (forward-open (save-excursion (re-search-forward open nil t)))
        (forward-close (save-excursion (re-search-forward close nil t)))) 
    (and backward-open forward-close
         (or (not backward-close) (> backward-open backward-close))
         (or (not forward-open) (< forward-close forward-open)))))

(defun emmet2-detect-css-in-markup ()
  (or
   (emmet2-check-in-between "style=[\"']" "[^=][\"']")
   (emmet2-check-in-between "<style.*>" "</style>")))

(defun emmet2-detect-css-in-js ()
  (or
   (emmet2-check-in-between "style={" "}")
   (emmet2-check-in-between "StyleSheet.create({" "})")))

(defun emmet2-detect-expand-lang ()
  (cond ((member emmet2-file-extension '("scss" "css")) "css")
        ((emmet2-detect-css-in-js) "css-in-js")
        ((emmet2-detect-css-in-markup) "css")
        ((stringp emmet2-markup-variant) emmet2-markup-variant)
        ((member emmet2-file-extension '("tsx" "jsx")) "jsx")
        (t "html")))

(defun emmet2-expand-css ()
  (when (thing-at-point-looking-at "@?[a-zA-Z0-9_#.:(+,)$!-]+")
    (let* ((bounds-beginning (match-beginning 0))
           (bounds-end (match-end 0))
           (input (buffer-substring-no-properties bounds-beginning bounds-end)))
      (deno-bridge-call "emmet2" "css" input bounds-beginning))))

(defun emmet2-expand-css-in-js ()
  (when (thing-at-point-looking-at "\\b[a-zA-Z0-9_(+,)!-]+")
    (let* ((bounds-beginning (match-beginning 0))
           (bounds-end (match-end 0))
           (input (buffer-substring-no-properties bounds-beginning bounds-end)))
      (deno-bridge-call "emmet2" "css-in-js" input bounds-beginning))))

(defun emmet2-expand-markup (lang)
  (let* ((bounds-beginning (save-excursion
                             (re-search-backward "\\(?:<.*?>\\|/>\\|}>\\|return (\\|=> (\\|)}\\|^\\)[[:space:]]*\\(.?\\)" nil t)
                             (match-beginning 1)))
         (left-paren? (string-match "\\(return\\|=>\\) ($" (buffer-substring-no-properties (match-beginning 0) bounds-beginning)))
         (bounds-end (save-excursion
                       (re-search-forward "<\\|$" nil t)
                       (match-beginning 0)))
         (right-paren? (and left-paren? (string-equal ")" (buffer-substring-no-properties (- bounds-end 1) bounds-end))))
         (bounds-end (if right-paren? (- bounds-end 1) bounds-end))
         (input (buffer-substring-no-properties bounds-beginning bounds-end)))
    (if (or (string-equal input "") (string-equal input ">"))
        (message "There is no abbr under the point")
      (deno-bridge-call "emmet2" lang input bounds-beginning (point) emmet2-css-modules-object emmet2-class-names-constructor))))

(defun emmet2-expand ()
  (interactive)
  (let ((lang (emmet2-detect-expand-lang)))
    (cond ((string-equal lang "css") (emmet2-expand-css))
          ((string-equal lang "css-in-js") (emmet2-expand-css-in-js))
          (t (emmet2-expand-markup lang)))))

(defun emmet2-insert (snippet bounds-beginning bounds-end reposition? indent?)
  (delete-region bounds-beginning bounds-end)
  (insert snippet)
  (when indent?
    (indent-region bounds-beginning (point)))
  (when reposition?
    (re-search-backward "|" bounds-beginning t)
    (delete-char 1)))

;;;###autoload
(define-minor-mode emmet2-mode
  "Minor mode for expanding emmet html and css abbreviations with opinionated enhancements."
  :lighter " emmet2"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-j") 'emmet2-expand)
            map)
  :after-hook (emmet2-after-hook))


(provide 'emmet2-mode)

;;; emmet2-mode.el ends here
