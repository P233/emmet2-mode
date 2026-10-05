;;; emmet2-capf.el --- Live expansion completion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Each completion table keeps the analysis of one input revision and expands
;; its choices when first asked; a bare CSS word is expanded at once, because
;; it counts as an abbreviation only if it has a choice.  The buffer keeps the
;; last expansion batch so repeated calls for the same input reuse it.  Every
;; candidate string is the typed abbreviation and a text property identifies
;; its expansion; the affixation function supplies the menu text.
;; Labels and previews are formatted only when requested.  Only a
;; choice accepted with status `finished' on unchanged source is inserted,
;; through `emmet2-insert'.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'emmet2-context)
(require 'emmet2-expand)
(defvar emmet2-mode nil)
(autoload 'emmet2-preview "emmet2-preview")
(declare-function emmet2-corfu--enable "emmet2-corfu" ())

(defvar emmet2-capf--explicit nil
  "Non-nil when the user explicitly requests completion.")

(defvar-local emmet2-capf--batch nil
  "Last choice batch, with the analysis and revision it was built for.
The value is (:revision R :settings S :provider P :request K :analysis A
:batch B).  K is `automatic' or `explicit', identifying the analysis policy.  B
came from `emmet2-expand-choices' for analysis A when
`emmet2-context-revision' was R.  `emmet2-capf--choices' reuses its results
but copies its choices, so tables never share candidates.  Each expansion
replaces the entry, or leaves it nil when the source changed meanwhile;
changing the major mode discards it.")

(defun emmet2-capf--analyze (automatic)
  "Analyze AUTOMATIC's request, reusing the last batch's unchanged context.
Only a completed batch can supply an answer; declined or interrupted
analyses are never cached.  Provider identity, request kind and all context
inputs must still match."
  (if (and emmet2-capf--batch
           (eq emmet2-context-provider (plist-get emmet2-capf--batch :provider))
           (eq (if automatic 'automatic 'explicit) (plist-get emmet2-capf--batch :request))
           (equal (emmet2-context-revision) (plist-get emmet2-capf--batch :revision)))
      (plist-get emmet2-capf--batch :analysis)
    (emmet2-context-analyze automatic)))

(defun emmet2-capf--element-line-p (analysis)
  "Whether ANALYSIS is a known HTML element name alone on its line."
  (and (emmet2-css-search-element-p (plist-get analysis :abbr))
       (save-excursion (goto-char (plist-get analysis :beg)) (skip-chars-backward " \t") (bolp))
       (save-excursion (goto-char (plist-get analysis :end)) (skip-chars-forward " \t") (eolp))))

(defun emmet2-capf--confident-p (analysis)
  "Return non-nil when ANALYSIS's abbreviation is likely Emmet input.
Return `search' for a bare lowercase CSS word, such as ta, which counts only
if it has a CSS choice.  Other property-led input in a confirmed declaration
slot is expanded lazily; the expansion owns its continuation punctuation.
A bare markup word counts only when it is a known element alone on its
line; a markup word ending in a period never counts."
  (let ((abbreviation (plist-get analysis :abbr)) (case-fold-search nil))
    (pcase (plist-get analysis :lang)
      ;; A bare word or sentence end (e.g.) is prose unless an element is alone on its line.
      ('markup (or (not (string-match-p "\\`\\(?:[[:alnum:]_:-]+\\|[[:alnum:]_:.-]*\\.\\)\\'" abbreviation))
                   (emmet2-capf--element-line-p analysis)))
      ((or 'css 'css-in-js)
       (or (and (eq (plist-get analysis :position) 'declaration-start)
                ;; Bare Sass variables and custom property names belong to the host.
                (string-match-p "\\`-?[[:alpha:]]" abbreviation)
                (eq (emmet2-extensions-css-kind abbreviation
                                                (eq (plist-get analysis :lang) 'css-in-js))
                    'properties)
                ;; Preserve Sass-only admission for p$ and p$name, without
                ;; rejecting dollars inside a raw value such as ct['$'].
                (or (eq (plist-get analysis :syntax) 'scss)
                    (not (string-match-p "\\`[-[:alpha:]]+\\$" abbreviation)))
                ;; An element name before a single trailing comma is a selector-list line.
                (not (and (string-suffix-p "," abbreviation)
                          (emmet2-css-search-element-p (substring abbreviation 0 -1))))
                (if (string-match-p "\\`[a-z][-a-z]*\\'" abbreviation) 'search t))
           (and (eq (plist-get analysis :lang) 'css)
                (string-match-p "\\`\\(?:@[[:alpha:]]\\|[^:]*::?[[:alpha:]]\\)" abbreviation)))))))

(defun emmet2-capf--settings (analysis)
  "Return the options that decide ANALYSIS's expansion and its lifetime."
  (list emmet2-mode emmet2-markup-variant emmet2-jsx-class-style emmet2-css-modules-object
        emmet2-class-names-constructor emmet2-css-scale-functions
        (emmet2-insert-render-options analysis)))

(defun emmet2-capf--current-p (analysis snapshot settings automatic &optional analyzed)
  "Whether ANALYSIS, SNAPSHOT and SETTINGS still match the buffer.
Point may be at the snapshot's point or at the abbreviation end, where
completion leaves it.  AUTOMATIC is the kind of context analysis to repeat;
non-nil ANALYZED skips the repeat because ANALYSIS already matched at the
current `emmet2-context-revision'."
  (and (eq (current-buffer) (plist-get snapshot :buffer))
       (<= (point-min) (plist-get snapshot :point) (point-max))
       (memq (point) (list (plist-get snapshot :point) (plist-get snapshot :end)))
       (save-excursion
         (goto-char (plist-get snapshot :point))
         (emmet2-insert-snapshot-valid-p snapshot))
       (equal settings (emmet2-capf--settings analysis))
       (or analyzed (equal analysis (emmet2-context-analyze automatic)))))

(defun emmet2-capf--same-context-p (before after)
  "Whether BEFORE and AFTER have the same source anchor and host context."
  (and after
       (cl-every (lambda (key) (equal (plist-get before key) (plist-get after key)))
                 '(:beg :lang :syntax :position :property :at-rule))))

(defun emmet2-capf--preview-text (text base-indent)
  "Make TEXT start at column zero while retaining its relative indentation.
Remove the renderer's BASE-INDENT after newlines.  Expand leading tabs using
the source buffer's `tab-width', so preview buffers need no source settings."
  (unless (string-empty-p base-indent)
    (setq text (replace-regexp-in-string (concat "\n" (regexp-quote base-indent)) "\n" text t t)))
  (replace-regexp-in-string
   "^[ \t]*\t[ \t]*"
   (lambda (whitespace)
     (let ((column 0))
       (seq-doseq (character whitespace)
         (setq column (+ column (if (eq character ?\t) (- tab-width (% column tab-width)) 1))))
       (make-string column ?\s)))
   text t t))

(defun emmet2-capf--choices (analysis &optional automatic)
  "Return ANALYSIS's choice batch with independent choice identities.
AUTOMATIC identifies the request policy that produced ANALYSIS.
Reuse `emmet2-capf--batch' when it was built for the same analysis and
`emmet2-context-revision'.  Otherwise expand again, passing the old batch to
`emmet2-expand-choices' when the provider, settings and context match.  Each
call copies the choices, so tables never share candidates.  Presentation is
derived only when the frontend requests labels or a preview."
  (let* ((revision (emmet2-context-revision))
         (settings (emmet2-capf--settings analysis))
         (provider emmet2-context-provider)
         (previous emmet2-capf--batch)
         (compatible (and previous
                          (eq provider (plist-get previous :provider))
                          (equal settings (plist-get previous :settings))
                          (emmet2-capf--same-context-p (plist-get previous :analysis) analysis)))
         (batch
          (if (and compatible
                   (equal revision (plist-get previous :revision))
                   (equal analysis (plist-get previous :analysis)))
              (plist-get previous :batch)
            ;; A failed or interrupted expansion must not leave reusable results.
            (setq emmet2-capf--batch nil)
            (let ((result (emmet2-expand-choices
                           analysis emmet2-css-choice-limit
                           (and compatible (plist-get previous :batch)))))
              (when (and (eq provider emmet2-context-provider)
                         (equal revision (emmet2-context-revision))
                         (equal settings (emmet2-capf--settings analysis)))
                (setq emmet2-capf--batch
                      (list :revision revision :settings settings :provider provider
                            :request (if automatic 'automatic 'explicit)
                            :analysis analysis :batch result))
                result)))))
    (plist-put (copy-sequence batch) :choices
               (mapcar (lambda (entry) (append entry (list :text nil :display nil)))
                       (plist-get batch :choices)))))

(defun emmet2-capf--display (text abbreviation)
  "Return TEXT as one menu row, highlighting ABBREVIATION.
Normalize line breaks and surrounding indentation.  Use the same ordered
matcher as candidate search; aliases without a literal correspondence remain
unhighlighted.  Return a fresh string; preview and insertion still use the
full result."
  (let ((text (if (string-search "\n" text)
                  (replace-regexp-in-string "[ \t]*\n[ \t\n]*" " " text)
                (copy-sequence text)))
        (needle (if (string-match-p "[^[:alnum:]_-]" abbreviation)
                    (replace-regexp-in-string "[^[:alnum:]_-]" "" abbreviation)
                  abbreviation)))
    (emmet2-fuzzy--highlight (plist-get (emmet2-fuzzy-match needle text) :positions) text)))

(defmacro emmet2-capf--guard (quiet cleanup &rest body)
  "Run BODY and evaluate CLEANUP if BODY fails or quits.
When QUIET is non-nil, errors make the form return nil; otherwise they
signal `user-error' with the cause.  Quitting propagates, and
`debug-on-error' still enters the debugger.  New input via `throw-on-input'
propagates without CLEANUP, so an interrupted query can be retried."
  (declare (indent 2) (debug (form form body)))
  (let ((completed (make-symbol "completed")) (error-data (make-symbol "error-data"))
        (input-tag (make-symbol "input-tag")) (result (make-symbol "result")))
    `(let (,completed (,input-tag (or throw-on-input (make-symbol "no-input"))))
       (unwind-protect
           (condition-case-unless-debug ,error-data
               (let ((,result (catch ,input-tag
                                (prog1 (progn ,@body) (setq ,completed t)))))
                 (if ,completed ,result
                   (setq ,completed t)
                   (throw ,input-tag ,result)))
             (error (unless ,quiet
                      (if (eq (car ,error-data) 'user-error)
                          (signal 'user-error (cdr ,error-data))
                        (user-error "Emmet: %s" (error-message-string ,error-data))))))
         (unless ,completed ,cleanup)))))

(defun emmet2-capf--admit (explicit)
  "Return (AUTOMATIC ANALYSIS CONFIDENCE) for the abbreviation at point, or nil.
EXPLICIT non-nil analyzes context as an explicit request, except in built-in
CSS, which always uses the automatic rules.  AUTOMATIC is the kind of
analysis used.  CONFIDENCE is t after an explicit analysis and otherwise the
value of `emmet2-capf--confident-p', where `search' means the abbreviation
counts only if it has a CSS choice."
  (let ((automatic (or (not explicit)
                       (and (derived-mode-p 'css-base-mode) (not emmet2-context-provider)))))
    ;; Company binds `buffer-read-only' while it probes and tries tables; only insertion checks it.
    (when-let* ((analysis (emmet2-capf--analyze automatic))
                (confidence (or (not automatic) (emmet2-capf--confident-p analysis))))
      (list automatic analysis confidence))))

;;;###autoload
(defun emmet2-capf ()
  "Return completion data for the Emmet abbreviation at point, or nil.
Use this in `completion-at-point-functions'; `emmet2-mode' adds it there.
Choices are expanded when a frontend first asks for them, so it can apply
its prefix threshold first, but a bare CSS word such as ta is expanded at
once and offered only when it has a choice.  Choices follow typing in the
same context.  Every candidate string is the abbreviation itself and a text
property tells alternative expansions apart, so frontends that drop text
properties still accept the first choice.  Errors make automatic requests
offer nothing; explicit requests and acceptance signal `user-error'.
Offering choices also installs the Corfu advice of emmet2-corfu.el, which
affects only tables that emmet2 builds."
  (emmet2-capf--guard (not emmet2-capf--explicit) nil
    (pcase-let ((quiet (not emmet2-capf--explicit))
                (`(,automatic ,analysis ,confidence) (emmet2-capf--admit emmet2-capf--explicit)))
      (when-let* ((_ analysis)
                  ;; A bare CSS word counts only if it has choices; reuse that batch for the first query.
                  (first (if (eq confidence 'search)
                             (let ((batch (emmet2-capf--choices analysis automatic)))
                               (and (plist-get batch :choices) batch))
                           'unexpanded)))
        (require 'emmet2-corfu)
        (emmet2-corfu--enable)
        (let* ((provider emmet2-context-provider)
               (settings (emmet2-capf--settings analysis))
               ;; Publish a whole revision at once.  An interrupted refresh keeps
               ;; the preceding revision; interrupted expansion stays unexpanded.
               ;; STATE is (ANALYSIS SNAPSHOT VALIDATED CHOICES), or nil if invalid.
               (state (list analysis (emmet2-insert-snapshot analysis)
                            (emmet2-context-revision)
                            (if (eq first 'unexpanded) first (plist-get first :choices)))))
          (cl-labels
              ((invalidate () (setq state nil))
               (abbreviation () (plist-get (car state) :abbr))
               (current-p ()
                 (when (and state (not (eq provider emmet2-context-provider)))
                   (invalidate))
                 (and state
                      (let ((revision (emmet2-context-revision)))
                        (when (emmet2-capf--current-p (car state) (cadr state) settings automatic
                                                      (equal revision (nth 2 state)))
                          (setcar (nthcdr 2 state) revision)
                          t))))
               (refresh ()
                 (or (current-p)
                     (when state
                       (let* ((analysis (car state)) (snapshot (cadr state))
                              (next (and (eq (current-buffer) (plist-get snapshot :buffer))
                                        (eq major-mode (plist-get snapshot :mode))
                                        (emmet2-capf--analyze automatic))))
                         (if (and (emmet2-capf--same-context-p analysis next)
                                  (equal settings (emmet2-capf--settings next))
                                  (<= (plist-get next :beg) (point) (plist-get next :end))
                                  (not (= (buffer-chars-modified-tick) (plist-get snapshot :tick)))
                                  (not (equal (abbreviation) (plist-get next :abbr)))
                                  (or (not automatic) (emmet2-capf--confident-p next)))
                             (progn
                               (setq state (list next (emmet2-insert-snapshot next)
                                                 (emmet2-context-revision) 'unexpanded))
                               t)
                           (invalidate))))))
               (expanded ()
                 (when (current-p)
                   (when (eq (nth 3 state) 'unexpanded)
                     ;; Publish only complete choices.  The guard still invalidates
                     ;; real failures, but new input leaves this query retryable.
                     (let ((next (emmet2-capf--choices (car state) automatic)))
                       (if (current-p)
                           (setcar (nthcdr 3 state) (plist-get next :choices))
                         (invalidate))))
                   (and state (nth 3 state))))
               (choice (candidate entries)
                 (if-let* ((entry (get-text-property 0 'emmet2--choice candidate)))
                     (and (memq entry entries) entry)
                   (car entries))))
            (list
             (plist-get analysis :beg) (plist-get analysis :end)
             (lambda (string predicate action)
               (emmet2-capf--guard quiet (invalidate)
                 (cond
                  ((eq action 'metadata)
                   '(metadata (category . emmet2) (display-sort-function . identity)
                              (cycle-sort-function . identity)))
                  ((eq (car-safe action) 'boundaries) nil)
                  ((and (refresh) (expanded))
                   (let* ((abbreviation (abbreviation))
                          (candidates (mapcar (lambda (entry)
                                                (propertize abbreviation 'emmet2--choice entry))
                                              (nth 3 state))))
                     (if (and (null action) (equal string abbreviation)
                              (test-completion string candidates predicate))
                         string
                       (complete-with-action action candidates string predicate)))))))
             :exclusive 'no
             :company-doc-buffer
             (lambda (candidate)
               (emmet2-capf--guard quiet (invalidate)
                 (when-let* ((_ (equal candidate (abbreviation)))
                             (entry (choice candidate (expanded)))
                             (text (plist-get (plist-get entry :result) :text))
                             (_ (string-match-p "\n" text)))
                   (emmet2-preview
                    (or (plist-get entry :text)
                        (setf (plist-get entry :text)
                              (emmet2-capf--preview-text
                               text (plist-get (emmet2-insert-render-options (car state)) :base-indent))))
                    (emmet2--output-syntax (car state))))))
             :affixation-function
             (lambda (candidates)
               (emmet2-capf--guard quiet (invalidate)
                 ;; Validate once for this synchronous display batch, not for each row.
                 (let* ((abbreviation (abbreviation))
                        (entries (and (member abbreviation candidates) (expanded))))
                   (mapcar (lambda (candidate)
                             (let ((label (if-let* ((entry (and (equal candidate abbreviation)
                                                                (choice candidate entries))))
                                              (copy-sequence
                                               (or (plist-get entry :display)
                                                   (setf (plist-get entry :display)
                                                         (emmet2-capf--display (plist-get entry :label)
                                                                              (plist-get entry :query))))) "")))
                               ;; Preserve the candidate and its choice identity for native
                               ;; *Completions* too.  Only this display copy is concealed; it
                               ;; also carries the label past frontend margin formatters.
                               (list (propertize candidate 'display "" 'emmet2--label label) label "")))
                           candidates))))
             :exit-function
             (lambda (candidate status)
               (emmet2-capf--guard nil (invalidate)
                 (when-let* ((_ (and (eq status 'finished) (equal candidate (abbreviation))))
                             (entry (choice candidate (expanded))))
                   (emmet2-insert (emmet2-insert-snapshot (car state)) (plist-get entry :result))))))))))))

;;;###autoload
(defun emmet2-complete ()
  "Request Emmet choices at point through `completion-at-point'.
This is an explicit request: JS hosts create a missing tree-sitter parser
and report a missing grammar, and a major mode without a built-in host or
`emmet2-context-provider' offers plain markup.  Built-in CSS modes use the
automatic rules.  The completion frontend shows the choices and decides
whether to accept a sole choice at once; Corfu keeps a sole Emmet choice in
its popup.  Signal `user-error' when there is nothing to complete or the
expansion fails."
  (interactive)
  (emmet2-capf--guard nil nil
    (let ((completion-at-point-functions '(emmet2-capf))
          (emmet2-capf--explicit t))
      (unless (completion-at-point)
        (user-error "There is no Emmet completion at point")))))

;;;###autoload
(defun emmet2-expand-at-point ()
  "Expand the abbreviation at point at once, without showing choices.
The context is that of `emmet2-complete' and the text is that of its first
choice, with the same initial cursor, fields and single undo step.  Signal
`user-error' when there is no abbreviation or it does not expand."
  (interactive)
  (emmet2-capf--guard nil nil
    (barf-if-buffer-read-only)
    (let* ((analysis (or (nth 1 (emmet2-capf--admit t))
                         (user-error "There is no Emmet abbreviation at point")))
           (snapshot (emmet2-insert-snapshot analysis)))
      (emmet2-insert snapshot (emmet2-expand-analysis analysis)))))

(provide 'emmet2-capf)
;;; emmet2-capf.el ends here
