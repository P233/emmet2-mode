;;; emmet2-mode.el --- Expand Emmet abbreviations  -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2023 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Created: 10 Oct 2022
;; Version: 2.0.0
;; URL: https://github.com/P233/emmet2-mode
;; Compatibility: emacs-version >= 30
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

;; Please check the README.

;;; Code:
(require 'emmet2-context)
(require 'emmet2-extensions)
(require 'emmet2-insert)
(declare-function emmet2-preview-clear "emmet2-preview" ())
(autoload 'emmet2-capf "emmet2-capf" nil nil)
(autoload 'emmet2-complete "emmet2-capf" nil t)

(defgroup emmet2 nil "Emmet abbreviation expansion." :group 'convenience)

(defcustom emmet2-markup-variant nil
  "Optional markup dialect.  The string \"solid\" selects Solid JSX."
  :type '(choice (const :tag "From context" nil) (const "solid"))
  :safe (lambda (value) (member value '(nil "solid"))) :group 'emmet2)

(defcustom emmet2-css-modules-object "styles"
  "JavaScript reference for the project's CSS Modules class name map.
Use the name imported in the source file, such as styles or cardStyles.
Emmet inserts the reference; add the matching import in the source file."
  :type 'string :safe #'stringp :group 'emmet2)

(defcustom emmet2-class-names-constructor "clsx"
  "JavaScript function reference for joining multiple JSX class names.
Use the function imported in the source file, such as clsx or cx.
A single class uses the CSS Modules reference directly."
  :type 'string :safe #'stringp :group 'emmet2)

(defun emmet2--output-syntax (analysis)
  "Return the syntax of ANALYSIS's final output under current project options."
  (pcase (plist-get analysis :lang)
    ('markup (if (or (eq (plist-get analysis :syntax) 'jsx)
                     (equal emmet2-markup-variant "solid")) 'jsx 'html))
    ('css-in-js 'jsx)
    ('css 'css)))

(defun emmet2--expand-analysis (analysis)
  "Expand ANALYSIS using current project options and formatter layout.
This shared read-only path produces the final insertion and preview result."
  (let ((options (emmet2-insert-render-options analysis))
        (abbreviation (plist-get analysis :abbr)))
    (pcase (plist-get analysis :lang)
      ('markup
       (apply #'emmet2-extensions-markup abbreviation
              :jsx (eq (emmet2--output-syntax analysis) 'jsx)
              :variant emmet2-markup-variant :css-modules-object emmet2-css-modules-object
              :class-names-constructor emmet2-class-names-constructor options))
      ((or 'css 'css-in-js)
       (apply #'emmet2-extensions-css abbreviation
              :css-in-js (eq (plist-get analysis :lang) 'css-in-js) options)))))

;;;###autoload
(defun emmet2-expand ()
  "Expand the abbreviation at point, preserving confirmed host exclusions."
  (interactive)
  (condition-case error-data
      (if-let* ((analysis (emmet2-context-analyze)))
          (let* ((snapshot (emmet2-insert-snapshot analysis))
                 (result (emmet2--expand-analysis analysis)))
            (emmet2-insert snapshot result))
        (user-error "There is no Emmet abbreviation at point"))
    (emmet2-error (user-error "%s" (error-message-string error-data)))))

;;;###autoload
(define-minor-mode emmet2-mode
  "Expand with \\[emmet2-expand] and offer confident Emmet completion."
  :lighter " emmet2"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-j") #'emmet2-expand)
            map)
  (if emmet2-mode
      (progn
        (add-hook 'completion-at-point-functions #'emmet2-capf -50 t)
        (emmet2-context-start))
    (remove-hook 'completion-at-point-functions #'emmet2-capf t)
    (emmet2-context-stop)))

(defun emmet2-mode-unload-function ()
  "Release mode-owned context resources and preview buffers."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (if (bound-and-true-p emmet2-mode) (emmet2-mode -1)
        (when (emmet2-context--owner) (emmet2-context-stop)))))
  (when (fboundp 'emmet2-preview-clear) (emmet2-preview-clear))
  nil)

(provide 'emmet2-mode)
;;; emmet2-mode.el ends here
