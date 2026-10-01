;;; emmet2-context.el --- Host routing and provider contract -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Route context requests to one authoritative host.  External providers
;; bypass built-in classification.  Host adapters own their parser or scan
;; resources; this entry validates confirmed bounds against the visible view.

;;; Code:

(require 'cl-lib)
(require 'emmet2-engine)
(require 'emmet2-extract)
(require 'emmet2-context-js)
(require 'emmet2-context-web)
(require 'emmet2-context-css)

(defvar emmet2-mode)

(defvar-local emmet2-context-provider nil
  "Optional host-owned context provider for this buffer.
Set an immutable plist with two functions, :analyze and :revision.  The host
owns its lifetime; install it buffer-locally before enabling `emmet2-mode',
or call `emmet2-capf' from the host's dispatcher without enabling the mode.
Set :field-navigation to host when the host owns value navigation; insertion
keeps canonical text and cursor without creating yasnippet fields.

:analyze receives AUTOMATIC, non-nil for automatic completion.  Return nil
to forbid expansion, with no built-in fallback, or a confirmed analysis:
  :beg, :end       Absolute integer replacement bounds containing point.
  :lang           css, css-in-js or markup.
  :syntax         css/scss for CSS, jsx for CSS-in-JS, html/jsx for markup.
  :position       declaration-start or selector for CSS; declaration-start
                  for CSS-in-JS; markup for markup.
  :indent-width   Optional nonnegative indentation width in columns.
Emmet derives :abbr from the current source; hosts need not supply it.
Extra immutable context, such as :property and :at-rule, is retained.
Values, comments and other forbidden positions must return nil.  The host
owns syntax checks, parser state and whether the position allows expansion.
The automatic CAPF still applies its abbreviation confidence gate.

:revision takes no arguments and returns a cheap immutable value compared
with `equal'.  Include every non-text input to :analyze, such as dialect,
feature settings or parser generation.  Text tick, point, visible bounds,
major mode and Emmet mode are already tracked.  Both functions must be
read-only.  Emmet caches analysis only within a completion table, invokes
:analyze again when the revision changes, and never caches provider results
globally.  Replacing the provider invalidates its existing tables.")

(defun emmet2-context--provider-function (key)
  "Return the host provider's function at KEY, or report a contract error."
  (let ((function (plist-get emmet2-context-provider key)))
    (unless (functionp function)
      (signal 'emmet2-error (list (format "Context provider requires a %s function" key))))
    function))

(defun emmet2-context--validate (analysis)
  "Validate confirmed ANALYSIS against the restored visible buffer view.
All hosts share this boundary.  Derive the abbreviation from source exactly
once here; a provider's spelling cannot substitute different source text."
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
  "Return the inputs of `emmet2-context-analyze', besides owned caches.
An analysis stays valid while this is unchanged: the text by its modification
tick, point, the visible region, the major mode, `emmet2-mode', and web-mode's
engine and content type, or the external provider's revision.  Parser warmup
can only turn a nil automatic analysis into a result."
  (list (buffer-chars-modified-tick) (point) (point-min) (point-max) major-mode
        (bound-and-true-p emmet2-mode)
        (if emmet2-context-provider
            (list emmet2-context-provider
                  (save-match-data
                    (save-excursion
                      (save-restriction
                        (funcall (emmet2-context--provider-function :revision))))))
          (and (derived-mode-p 'web-mode) (emmet2-context-web-revision)))))

(defun emmet2-context-analyze (&optional automatic)
  "Return a confirmed abbreviation at point, or nil.
AUTOMATIC requires trusted positions and warmed JS parsers.  Explicit calls
initialize required grammars and allow manual markup in other major modes.
With `emmet2-context-provider', the host alone confirms context and bounds."
  (save-match-data
    (emmet2-context--validate
     (save-excursion
       (save-restriction
         (if emmet2-context-provider
             (progn
               (emmet2-context--provider-function :revision)
               (funcall (emmet2-context--provider-function :analyze) automatic))
           ;; Hidden enclosing syntax still informs the host. Acceptance is
           ;; checked only after this widened view and point have been restored.
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
  "Extract HTML markup inside the confirmed host REGION."
  (when-let* ((candidate (emmet2-extract (nth 1 region) (nth 2 region))))
    (unless (equal (plist-get candidate :abbr) "()")
      (append candidate '(:lang markup :syntax html :position markup)))))

(defun emmet2-context-start ()
  "Start built-in host resources unless an external provider owns context."
  (unless emmet2-context-provider (emmet2-context-js-start)))

(defun emmet2-context-stop ()
  "Release resources owned by each built-in host adapter."
  (emmet2-context-js-stop)
  (emmet2-context-web-stop))

(provide 'emmet2-context)
;;; emmet2-context.el ends here
