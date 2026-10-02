;;; emmet2-expand.el --- Editor requests and project options -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Turn an analysis from `emmet2-context-analyze' into calls to the pure
;; expansion functions, adding the user options and the buffer's indentation.
;; Only this layer reads buffer settings; the engines read neither the buffer
;; nor user options.  Nothing here modifies the buffer.

;;; Code:
(require 'emmet2-extensions)
(require 'emmet2-css)
(require 'emmet2-insert)

(defgroup emmet2 nil "Emmet abbreviation expansion." :group 'convenience)

(defcustom emmet2-markup-variant nil
  "Markup dialect, or nil to follow the context.
With nil, HTML contexts get HTML and JSX contexts get React JSX.  The string
\"solid\" writes Solid JSX, with class instead of className, in every markup
context, including HTML files."
  :type '(choice (const :tag "From context" nil) (const "solid"))
  :safe (lambda (value) (member value '(nil "solid"))) :group 'emmet2)

(defcustom emmet2-jsx-class-style 'css-modules
  "How JSX class names are written.
`css-modules' references `emmet2-css-modules-object' members and joins
several with `emmet2-class-names-constructor'.  `plain' keeps them as a
string, as in className=\"card active\".  A leading _ in an abbreviation,
as in _div.card, keeps that expansion's classes as a string."
  :type '(choice (const :tag "Class name string" plain)
                 (const :tag "CSS Modules references" css-modules))
  :safe (lambda (value) (memq value '(plain css-modules))) :group 'emmet2)

(defcustom emmet2-css-modules-object "styles"
  "JavaScript reference for the project's CSS Modules class name map.
Used when `emmet2-jsx-class-style' is `css-modules'.  Use the name imported
in the source file, such as styles or cardStyles.  Emmet inserts the
reference; add the matching import in the source file."
  :type 'string :safe #'stringp :group 'emmet2)

(defcustom emmet2-class-names-constructor "clsx"
  "JavaScript function reference for joining multiple JSX class names.
Used when `emmet2-jsx-class-style' is `css-modules'.  Use the function
imported in the source file, such as clsx or cx.  A single class uses the
CSS Modules reference directly."
  :type 'string :safe #'stringp :group 'emmet2)

(defcustom emmet2-css-scale-functions nil
  "Sass functions for parenthesized SCSS values, such as p(1)(2).
Each entry is (PROPERTY . FUNCTION); PROPERTY t applies to every other
property.  Each (N) group becomes FUNCTION(N).  A zero group stays 0, except
for font-size, whose scale step 0 is the base size.  For example,
\\='((\"font-size\" . \"ms\") (t . \"rhythm\")) expands p(0)(2) to
padding: 0 rhythm(2).  Plain CSS and CSS-in-JS ignore this option.  With
nil, the default, such values are invalid and offer no choice."
  :type '(alist :key-type (choice (const :tag "Other properties" t) string)
                :value-type string)
  :safe (lambda (value)
          (and (proper-list-p value)
               (seq-every-p (lambda (entry)
                              (and (consp entry) (or (eq (car entry) t) (stringp (car entry)))
                                   (stringp (cdr entry))))
                            value)))
  :group 'emmet2)

(defun emmet2--output-syntax (analysis)
  "Return the syntax of ANALYSIS's final output under current project options."
  (pcase (plist-get analysis :lang)
    ('markup (if (or (eq (plist-get analysis :syntax) 'jsx)
                     (equal emmet2-markup-variant "solid")) 'jsx 'html))
    ('css-in-js 'jsx)
    ('css 'css)))

(defun emmet2-expand-analysis (analysis)
  "Return the expansion of ANALYSIS as a canonical result.
ANALYSIS is a non-nil value of `emmet2-context-analyze'.  The result uses the
current project options and the buffer's indentation, and it is the result
of the first completion choice, so a pending separator, as in \"m10,\", is
consumed.  Signal `emmet2-parse-error' when the abbreviation does not expand,
such as an unknown CSS name, value or unit, and `emmet2-error' for other
failures.  Call `emmet2-insert-snapshot' before this function and pass both
values to `emmet2-insert'.  For live choices use `emmet2-capf', which also
checks the context again before inserting."
  (let ((options (emmet2-insert-render-options analysis))
        (abbreviation (plist-get analysis :abbr)))
    (pcase (plist-get analysis :lang)
      ('markup
       (apply #'emmet2-extensions-markup abbreviation
              :jsx (eq (emmet2--output-syntax analysis) 'jsx)
              :variant emmet2-markup-variant :class-style emmet2-jsx-class-style
              :css-modules-object emmet2-css-modules-object
              :class-names-constructor emmet2-class-names-constructor options))
      (lang
       ;; One deadline covers the choices and, without a first choice, the expansion reporting why.
       (emmet2-engine-with-expansion
         (or (plist-get (car (plist-get (emmet2-expand-choices analysis emmet2-css-choice-limit) :choices))
                        :result)
             (apply #'emmet2-extensions-css abbreviation :css-in-js (eq lang 'css-in-js)
                    :syntax (plist-get analysis :syntax) :at-rule (plist-get analysis :at-rule)
                    :scale-functions emmet2-css-scale-functions options)))))))

(defun emmet2-expand-choices (analysis limit &optional previous)
  "Return a batch of expansion choices for ANALYSIS.
The batch is a plist whose :choices holds at most LIMIT CSS choices, or one
markup choice; each choice is a plist with :abbreviation, :result, :label
and :query.  CSS readings that do not expand are left out, while a markup
error is signaled.  PREVIOUS is a batch for the same context and render
options, whose results may be reused.  The batch format is internal."
  (emmet2-engine-with-expansion
    (let ((abbreviation (plist-get analysis :abbr)))
      (if (memq (plist-get analysis :lang) '(css css-in-js))
          (apply #'emmet2-css-completions abbreviation
                 :css-in-js (eq (plist-get analysis :lang) 'css-in-js)
                 :syntax (plist-get analysis :syntax) :at-rule (plist-get analysis :at-rule)
                 :scale-functions emmet2-css-scale-functions :limit limit :previous previous
                 :declaration-start (eq (plist-get analysis :position) 'declaration-start)
                 (emmet2-insert-render-options analysis))
        (let ((result (emmet2-expand-analysis analysis)))
          (list :choices (list (list :abbreviation abbreviation :result result
                                     :label (plist-get result :text) :query abbreviation))))))))

(provide 'emmet2-expand)
;;; emmet2-expand.el ends here
