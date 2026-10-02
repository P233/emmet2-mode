;;; emmet2-context.el --- Host routing and provider contract -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Ask exactly one host for the abbreviation context at point: the buffer's
;; `emmet2-context-provider' when set, otherwise the built-in web-mode, CSS or
;; JS adapter for the major mode.  Adapters keep their own parsers and scan
;; state.  This module checks every answer and reads the abbreviation text
;; from the buffer.

;;; Code:

(require 'cl-lib)
(require 'emmet2-engine)
(require 'emmet2-extract)
(require 'emmet2-context-js)
(require 'emmet2-context-web)
(require 'emmet2-context-css)

(defvar emmet2-mode)

(defvar-local emmet2-context-provider nil
  "Context provider that replaces built-in context detection, or nil.
The value is a plist of two functions, :analyze and :revision.  Set it
buffer-locally before enabling `emmet2-mode', or call `emmet2-capf' from the
host's own completion function without the mode.  Replace the plist instead
of modifying it; replacing or clearing it ends every open completion table.
Changing the major mode clears it.

:analyze receives AUTOMATIC, non-nil for automatic completion and nil for an
explicit request such as `emmet2-complete'.  Return nil to decline, and Emmet
then offers nothing, or an analysis plist:
  :beg, :end     Integer bounds of the abbreviation, nonempty, inside the
                 visible region and containing point.
  :lang          css, css-in-js or markup.
  :syntax        css or scss for css, jsx for css-in-js, html or jsx for
                 markup.
  :position      declaration-start or selector for css, declaration-start
                 for css-in-js, markup for markup.
  :indent-width  Optional nonnegative indentation width in columns.
  :at-rule       Optional enclosing at-rule, such as \"@font-face\", whose
                 descriptors CSS expansion then offers.
  :property      Optional property name, used only to tell contexts apart.
Emmet reads :abbr from the buffer between :beg and :end.  Bounds that are
empty, hidden or exclude point make the analysis nil; other invalid values
signal `emmet2-error'.  Return nil in values, comments and other places where
expansion is wrong, even for explicit requests.  Automatic completion also
skips text that does not look like an abbreviation, such as a bare CSS word
without any CSS choice.

:revision takes no arguments and returns a cheap value compared with
`equal'.  It must change whenever :analyze could answer differently for a
reason that Emmet does not track itself, such as dialect, settings or parser
generation; Emmet tracks the text, point, visible region, major mode and
`emmet2-mode'.  Neither function may modify the buffer.  Within one
completion table, Emmet reuses an answer while `emmet2-context-revision',
which includes this value, is unchanged; it never caches answers across
tables.")

(defun emmet2-context--provider-function (key)
  "Return the host provider's function at KEY, or report a contract error."
  (let ((function (plist-get emmet2-context-provider key)))
    (unless (functionp function)
      (signal 'emmet2-error (list (format "Context provider requires a %s function" key))))
    function))

(defun emmet2-context--validate (analysis)
  "Return a copy of ANALYSIS with :abbr read from the buffer, or nil.
Return nil when the bounds are empty, outside the visible region or exclude
point.  Signal `emmet2-error' for a malformed ANALYSIS.  Every host's answer
passes through here, so a provider's :abbr never replaces the source text."
  (when analysis
    (unless (proper-list-p analysis)
      (signal 'emmet2-error '("Host context must be a property list")))
    (let ((beg (plist-get analysis :beg)) (end (plist-get analysis :end))
          (syntax (plist-get analysis :syntax)) (position (plist-get analysis :position))
          (width (plist-get analysis :indent-width)))
      (unless (and (integerp beg) (integerp end)
                   (or (null width) (and (integerp width) (>= width 0)))
                   (pcase (plist-get analysis :lang)
                     ('css (and (memq syntax '(css scss)) (memq position '(declaration-start selector))))
                     ('css-in-js (and (eq syntax 'jsx) (eq position 'declaration-start)))
                     ('markup (and (memq syntax '(html jsx)) (eq position 'markup)))))
        (signal 'emmet2-error '("Invalid host context bounds, language, syntax, position or indentation")))
      (when (and (< beg end) (<= (point-min) beg (point) end (point-max)))
        (plist-put (copy-sequence analysis) :abbr (buffer-substring-no-properties beg end))))))

(defun emmet2-context-revision ()
  "Return the inputs of `emmet2-context-analyze' as one comparable value.
Compare values with `equal'.  The value covers the text's modification tick,
point, the visible region, the major mode and `emmet2-mode', plus either the
provider's :revision or, for built-in hosts, web-mode's engine, content type
and file name and the CSS-in-JS options.  It ignores parser warmup, which can
only turn a nil automatic analysis into a result."
  (list (buffer-chars-modified-tick) (point) (point-min) (point-max) major-mode
        (bound-and-true-p emmet2-mode)
        (if emmet2-context-provider
            (list emmet2-context-provider
                  (save-match-data
                    (save-excursion
                      (save-restriction
                        (funcall (emmet2-context--provider-function :revision))))))
          (list (and (derived-mode-p 'web-mode) (emmet2-context-web-revision))
                (emmet2-context-js-revision)))))

(defun emmet2-context-analyze (&optional automatic)
  "Return the Emmet abbreviation context at point, or nil.
The value is a plist with :beg, :end, :abbr, :lang, :syntax and :position,
plus any :at-rule, :property or :indent-width; see `emmet2-context-provider'
for their values.  Non-nil AUTOMATIC applies the stricter rules of automatic
completion; for example, JS hosts use only an already warmed parser and skip
text that could be a JSX expression.  With nil AUTOMATIC, JS hosts create a
missing parser, signaling `emmet2-error' when its grammar is not installed,
and a major mode without a built-in host is treated as markup.  With
`emmet2-context-provider', only the provider decides, and an invalid answer
signals `emmet2-error'."
  (save-match-data
    (emmet2-context--validate
     (save-excursion
       (save-restriction
         (if emmet2-context-provider
             (progn
               (emmet2-context--provider-function :revision)
               (funcall (emmet2-context--provider-function :analyze) automatic))
           ;; Widen so the host sees hidden enclosing syntax; validation runs after point and narrowing return.
           (widen)
           (let ((region
                  (cond
                   ((derived-mode-p 'web-mode) (emmet2-context-web-region))
                   ((derived-mode-p 'css-base-mode)
                    (list 'css (point-min) (point-max) nil (if (derived-mode-p 'scss-mode) 'scss 'css)))
                   ((emmet2-context-js-region))
                   ((not automatic) (list 'markup (point-min) (point-max))))))
             (pcase (car region)
               ('css (emmet2-context-css-analyze region automatic))
               ('markup (emmet2-context--markup region))
               ((or 'javascript 'typescript 'tsx) (emmet2-context-js-analyze region automatic))))))))))

(defun emmet2-context--markup (region)
  "Extract an HTML abbreviation inside markup REGION."
  (when-let* ((candidate (emmet2-extract (nth 1 region) (nth 2 region))))
    (unless (equal (plist-get candidate :abbr) "()")
      (append candidate '(:lang markup :syntax html :position markup)))))

(defun emmet2-context-start ()
  "Schedule JS parser warmup unless `emmet2-context-provider' is set."
  (unless emmet2-context-provider (emmet2-context-js-start)))

(defun emmet2-context-stop ()
  "Release resources owned by each built-in host adapter."
  (emmet2-context-js-stop)
  (emmet2-context-web-stop))

(provide 'emmet2-context)
;;; emmet2-context.el ends here
