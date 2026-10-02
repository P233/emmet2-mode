;;; emmet2-mode.el --- Expand Emmet abbreviations  -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2026 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Created: 10 Oct 2022
;; Version: 2.0.0
;; URL: https://github.com/P233/emmet2-mode
;; Keywords: abbrev, convenience, languages
;; Package-Requires: ((emacs "30"))

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

;; Expand HTML, JSX, CSS, SCSS and CSS-in-JS abbreviations through
;; completion-at-point.  Previews and insertion share the same expansion text.
;; See README.md for installation and examples, and CHANGELOG.md for upgrade
;; notes.

;;; Code:
(require 'emmet2-context)
(require 'emmet2-expand)
(declare-function emmet2-preview-clear "emmet2-preview" ())
(declare-function emmet2-corfu-unload-function "emmet2-corfu" ())
(autoload 'emmet2-capf "emmet2-capf" nil nil)
(autoload 'emmet2-css-value-capf "emmet2-css-value" nil nil)
(autoload 'emmet2-complete "emmet2-capf" nil t)
(autoload 'emmet2-expand-at-point "emmet2-capf" nil t)

;;;###autoload
(define-minor-mode emmet2-mode
  "Offer Emmet expansions as completion choices while typing.
Accepting a choice replaces the abbreviation; typing alone never expands.
In CSS Base modes without `emmet2-context-provider', also complete property
values with `emmet2-css-value-capf'.  The keymap `emmet2-mode-map' is empty;
bind `emmet2-complete' or `emmet2-expand-at-point' in it."
  :lighter " emmet2"
  :keymap (make-sparse-keymap)
  (if emmet2-mode
      (progn
        (add-hook 'completion-at-point-functions #'emmet2-capf -50 t)
        (when (and (derived-mode-p 'css-base-mode) (not emmet2-context-provider))
          (add-hook 'completion-at-point-functions #'emmet2-css-value-capf -60 t))
        (emmet2-context-start))
    (remove-hook 'completion-at-point-functions #'emmet2-capf t)
    (remove-hook 'completion-at-point-functions #'emmet2-css-value-capf t)
    (emmet2-context-stop)))

(defun emmet2-mode-unload-function ()
  "Disable `emmet2-mode' everywhere and release its buffers and advice."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (if (bound-and-true-p emmet2-mode) (emmet2-mode -1)
        (emmet2-context-stop))))
  (when (fboundp 'emmet2-preview-clear) (emmet2-preview-clear))
  (when (fboundp 'emmet2-corfu-unload-function) (emmet2-corfu-unload-function))
  nil)

(provide 'emmet2-mode)
;;; emmet2-mode.el ends here
