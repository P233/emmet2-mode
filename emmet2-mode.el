;;; emmet2-mode.el --- An Emmet-enhanced minor mode for Emacs.  -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2023 Peiwen Lu

;; Author: Peiwen Lu <hi@peiwen.lu>
;; Created: 10 Oct 2022
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
(declare-function emmet2-node-stop "emmet2-engine-node" (&optional process))
(autoload 'emmet2-capf "emmet2-capf" nil nil)
(autoload 'emmet2-complete "emmet2-capf" nil t)

(defgroup emmet2 nil "Emmet abbreviation expansion." :group 'convenience)

(defcustom emmet2-markup-variant nil
  "Optional markup dialect.  The string \"solid\" selects Solid JSX."
  :type '(choice (const :tag "From context" nil) (const "solid"))
  :safe (lambda (value) (member value '(nil "solid"))) :group 'emmet2)

(defcustom emmet2-css-modules-object "css"
  "Authored JavaScript reference for the project's CSS Modules object."
  :type 'string :safe #'stringp :group 'emmet2)

(defcustom emmet2-class-names-constructor "clsx"
  "Authored JavaScript reference for joining JSX class names."
  :type 'string :safe #'stringp :group 'emmet2)

(defun emmet2--expand-analysis (analysis)
  "Expand ANALYSIS using current project options and formatter layout.
This shared read-only path produces the final insertion and preview result."
  (let ((options (emmet2-insert-render-options analysis))
        (abbreviation (plist-get analysis :abbr)))
    (pcase (plist-get analysis :lang)
      ('markup
       (apply #'emmet2-extensions-markup abbreviation
              :jsx (or (eq (plist-get analysis :syntax) 'jsx) (equal emmet2-markup-variant "solid"))
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
  "Expand with C-j and offer confident Emmet abbreviations for completion."
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
  "Release mode-owned context resources and the interim backend."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (if (bound-and-true-p emmet2-mode) (emmet2-mode -1)
        (when (emmet2-context--owner) (emmet2-context-stop)))))
  (when (fboundp 'emmet2-node-stop) (emmet2-node-stop))
  nil)

(provide 'emmet2-mode)
;;; emmet2-mode.el ends here
