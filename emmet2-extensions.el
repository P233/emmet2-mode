;;; emmet2-extensions.el --- Public expansion policy entries -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Markup project options become structured AST rendering options here.
;; CSS policy has its own module; retain the existing public expansion names
;; so callers need not know the private module layout.

;;; Code:

(require 'emmet2-engine)

(autoload 'emmet2-extensions-css "emmet2-css")
(autoload 'emmet2-extensions-css-choices "emmet2-css")
(autoload 'emmet2-extensions-css-kind "emmet2-css")

(cl-defun emmet2-extensions-markup (abbreviation &key jsx variant (class-style 'css-modules)
                                                (css-modules-object "styles")
                                                (class-names-constructor "clsx")
                                                (indent "\t") (base-indent ""))
  "Expand markup ABBREVIATION, optionally with JSX project semantics.
VARIANT equal to \"solid\" emits class instead of className.  CLASS-STYLE
`css-modules' references JSX class names as CSS-MODULES-OBJECT members joined
by CLASS-NAMES-CONSTRUCTOR, which are authored JavaScript references; `plain'
keeps them as a string.  A leading _ in ABBREVIATION, as in _div.card, selects
`plain' for this expansion.  INDENT and BASE-INDENT affect generated layout
only.  JSX transformation operates on the markup AST because rendered
attribute text loses quoting boundaries."
  (unless (memq class-style '(plain css-modules))
    (signal 'emmet2-error (list "Invalid JSX class style" class-style)))
  ;; No HTML element name starts with _, so the marker cannot hide a tag.
  (when (and (string-prefix-p "_" abbreviation) (> (length abbreviation) 1))
    (setq abbreviation (substring abbreviation 1) class-style 'plain))
  (emmet2-engine-with-expansion
    (emmet2-engine-expand
     abbreviation :preset (if jsx 'jsx 'html) :indent indent :base-indent base-indent
     :jsx (and jsx (append (list :classAttribute (if (equal variant "solid") "class" "className"))
                           (when (eq class-style 'css-modules)
                             (list :cssModulesObject css-modules-object
                                   :classConstructor class-names-constructor)))))))

(provide 'emmet2-extensions)
;;; emmet2-extensions.el ends here
