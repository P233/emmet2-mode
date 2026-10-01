;;; emmet2-expand.el --- Editor requests and project options -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Translate a confirmed host analysis and buffer layout into pure language
;; requests.  This editor facade reads buffer settings; the language engines
;; neither read the buffer nor choose project options.  Results never write.

;;; Code:
(require 'emmet2-extensions)
(require 'emmet2-css)
(require 'emmet2-insert)

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

(defun emmet2-expand-analysis (analysis)
  "Expand ANALYSIS using current project options and formatter layout.
ANALYSIS is a confirmed context from `emmet2-context-analyze'.  This read-only
path produces the same canonical :text, :fields and :cursor used by completion.
Use `emmet2-insert-snapshot' before expansion and `emmet2-insert' to accept
the result synchronously.  Live choices should use `emmet2-capf', which also
revalidates host context and rejects stale candidates before insertion."
  (let ((options (emmet2-insert-render-options analysis))
        (abbreviation (plist-get analysis :abbr)))
    (pcase (plist-get analysis :lang)
      ('markup
       (apply #'emmet2-extensions-markup abbreviation
              :jsx (eq (emmet2--output-syntax analysis) 'jsx)
              :variant emmet2-markup-variant :css-modules-object emmet2-css-modules-object
              :class-names-constructor emmet2-class-names-constructor options))
      ('css
       (apply #'emmet2-extensions-css abbreviation :syntax (plist-get analysis :syntax)
              :at-rule (plist-get analysis :at-rule) options))
      ('css-in-js
       (apply #'emmet2-extensions-css abbreviation :css-in-js t
              :at-rule (plist-get analysis :at-rule) options)))))

(defun emmet2-expand-choices (analysis limit &optional previous)
  "Return language-owned choices for ANALYSIS, bounded by LIMIT.
PREVIOUS is an opaque batch from the same verified context and render options.
Each choice carries its result, menu label and matching query together."
  (emmet2-engine-with-expansion
    (let ((abbreviation (plist-get analysis :abbr)))
      (if (memq (plist-get analysis :lang) '(css css-in-js))
          (apply #'emmet2-css-completions abbreviation
                 :css-in-js (eq (plist-get analysis :lang) 'css-in-js)
                 :syntax (plist-get analysis :syntax) :at-rule (plist-get analysis :at-rule)
                 :limit limit :previous previous
                 :declaration-start (eq (plist-get analysis :position) 'declaration-start)
                 (emmet2-insert-render-options analysis))
        (let ((result (emmet2-expand-analysis analysis)))
          (list :choices (list (list :abbreviation abbreviation :result result
                                     :label (plist-get result :text) :query abbreviation))))))))

(provide 'emmet2-expand)
;;; emmet2-expand.el ends here
