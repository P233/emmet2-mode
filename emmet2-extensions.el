;;; emmet2-extensions.el --- Pure expansion entry points -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Public pure expansion entry points.  `emmet2-extensions-markup' turns markup
;; project options into rendering options; the CSS entries live in emmet2-css.el
;; and are autoloaded here, so callers need only require this file.

;;; Code:

(require 'emmet2-engine)

(autoload 'emmet2-extensions-css "emmet2-css")
(autoload 'emmet2-extensions-css-choices "emmet2-css")
(autoload 'emmet2-extensions-css-kind "emmet2-css")

(cl-defun emmet2-extensions-markup (abbreviation &key jsx variant (class-style 'css-modules)
                                                (css-modules-object "styles")
                                                (class-names-constructor "clsx")
                                                (indent "\t") (base-indent ""))
  "Expand markup ABBREVIATION and return a canonical result.
Non-nil JSX writes JSX instead of HTML; VARIANT and the class options apply
only then.  VARIANT \"solid\" writes class instead of className.
CLASS-STYLE `css-modules', the default, writes class names as members of
CSS-MODULES-OBJECT, default \"styles\", joined by CLASS-NAMES-CONSTRUCTOR,
default \"clsx\"; `plain' writes a string.  A leading _ in ABBREVIATION, as
in _div.card, selects `plain' for this expansion.  INDENT, a tab by default,
and BASE-INDENT, empty by default, are literal layout strings.  Signal
`emmet2-parse-error' for an invalid abbreviation and `emmet2-error' for an
invalid CLASS-STYLE."
  (unless (memq class-style '(plain css-modules))
    (signal 'emmet2-error (list "Invalid JSX class style" class-style)))
  ;; No HTML element name starts with _, so the marker cannot hide a tag.
  (when (and (string-prefix-p "_" abbreviation) (> (length abbreviation) 1))
    (setq abbreviation (substring abbreviation 1) class-style 'plain))
  ;; JSX options act on the AST because rendered attributes lose quoting.
  (emmet2-engine-with-expansion
    (emmet2-engine-expand
     abbreviation :preset (if jsx 'jsx 'html) :indent indent :base-indent base-indent
     :jsx (and jsx (append (list :classAttribute (if (equal variant "solid") "class" "className"))
                           (when (eq class-style 'css-modules)
                             (list :cssModulesObject css-modules-object
                                   :classConstructor class-names-constructor)))))))

(provide 'emmet2-extensions)
;;; emmet2-extensions.el ends here
