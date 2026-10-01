;;; emmet2-capf.el --- Live expansion completion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A table owns the current input revision and its lazy expansion choices.
;; Candidates retain the typed text; properties identify alternative expansions.
;; Only a finished, current choice may write through the single insert owner.
;; Affixation supplies display text without changing the completion payload.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'emmet2-context)
(require 'emmet2-expand)
(defvar emmet2-mode nil)
(autoload 'emmet2-preview "emmet2-preview")
(declare-function emmet2-corfu--enable "emmet2-corfu" ())

(defconst emmet2-capf--limit 10
  "Most CSS choices built for one input revision; each costs an expansion.")

(defvar emmet2-capf--explicit nil
  "Non-nil when the user explicitly requests completion.")

(defun emmet2-capf--element-line-p (analysis)
  "Whether ANALYSIS is a known HTML element name alone on its line."
  (and (emmet2-css-search-element-p (plist-get analysis :abbr))
       (save-excursion (goto-char (plist-get analysis :beg)) (skip-chars-backward " \t") (bolp))
       (save-excursion (goto-char (plist-get analysis :end)) (skip-chars-forward " \t") (eolp))))

(defun emmet2-capf--confident-p (analysis)
  "Whether ANALYSIS has an expansion signal or a CSS search choice."
  (let ((abbreviation (plist-get analysis :abbr)) (case-fold-search nil))
    (pcase (plist-get analysis :lang)
      ;; Words ending a sentence, such as end. or e.g., are prose.  A known
      ;; element such as div alone on its line is being written as markup.
      ('markup (or (not (string-match-p "\\`\\(?:[[:alnum:]_:-]+\\|[[:alnum:]_:.-]*\\.\\)\\'" abbreviation))
                   (emmet2-capf--element-line-p analysis)))
      ((or 'css 'css-in-js)
       (or (string-match-p (rx (or digit upper (in "#!%,(+["))) abbreviation)
           ;; Keep p$ and p$- live while a Sass variable name is being typed.
           ;; A bare $name stays with the host's variable completion.
           (and (eq (plist-get analysis :syntax) 'scss)
                (string-match-p "\\`[a-z][-a-z]*\\$-?\\(?:[_[:alpha:]]\\|\\'\\)" abbreviation))
           (and (string-match-p "\\`[a-z][-a-z]*\\'" abbreviation)
                (emmet2-extensions-css-choices abbreviation :css-in-js (eq (plist-get analysis :lang) 'css-in-js)
                                               :limit 1 :at-rule (plist-get analysis :at-rule)))
           (and (eq (plist-get analysis :lang) 'css)
                (string-match-p "\\`\\(?:@[[:alpha:]]\\|[^:]*::?[[:alpha:]]\\)" abbreviation)))))))

(defun emmet2-capf--settings (analysis)
  "Return the source settings affecting ANALYSIS's result and lifetime."
  (list emmet2-mode emmet2-markup-variant emmet2-css-modules-object
        emmet2-class-names-constructor (emmet2-insert-render-options analysis)))

(defun emmet2-capf--current-p (analysis snapshot settings automatic &optional analyzed)
  "Whether ANALYSIS, SNAPSHOT and SETTINGS still describe this input revision.
Completion may move point from its original position to the candidate end.
Source checks remain strict; only table queries may advance the revision.
AUTOMATIC repeats the session's kind of context analysis, unless ANALYZED
says ANALYSIS already matched at the current `emmet2-context-revision'."
  (and (not buffer-read-only)
       (eq (current-buffer) (plist-get snapshot :buffer))
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

(defun emmet2-capf--choices (analysis &optional previous)
  "Prepare ANALYSIS's language-owned results for the completion frontend.
PREVIOUS is a batch from the same verified context and render settings.
The language owns choice construction, fragment labels and any result reuse;
the frontend only prepares preview layout and menu highlighting."
  (let* ((options (emmet2-insert-render-options analysis))
         (batch (emmet2-expand-choices analysis emmet2-capf--limit previous)))
    (dolist (entry (plist-get batch :choices))
      (plist-put entry :text (emmet2-capf--preview-text
                              (plist-get (plist-get entry :result) :text)
                              (plist-get options :base-indent)))
      (plist-put entry :display (emmet2-capf--display (plist-get entry :label) (plist-get entry :query))))
    batch))

(defun emmet2-capf--display (text abbreviation)
  "Return TEXT as one menu row, highlighting ABBREVIATION.
Normalize line breaks and surrounding indentation.  Use the same ordered
matcher as candidate search; aliases without a literal correspondence remain
unhighlighted.  Never modify the supplied text; the full result still owns
preview, insertion and field positions."
  (let* ((text (copy-sequence
                (replace-regexp-in-string "[ \t]*\n[ \t\n]*" " " text)))
         (needle (replace-regexp-in-string "[^[:alnum:]_-]" "" abbreviation)))
    (dolist (position (plist-get (emmet2-fuzzy-match needle text) :positions))
      (add-face-text-property position (1+ position) 'completions-common-part nil text))
    text))

(defmacro emmet2-capf--guard (quiet cleanup &rest body)
  "Run BODY at an editor boundary, invalidating through CLEANUP on failure.
QUIET automatic requests return no match.  Explicit requests report the cause.
Cancellation propagates, and `debug-on-error' retains the original debugger."
  (declare (indent 2) (debug (form form body)))
  (let ((completed (make-symbol "completed")) (error-data (make-symbol "error-data")))
    `(let (,completed)
       (unwind-protect
           (condition-case-unless-debug ,error-data
               (prog1 (progn ,@body) (setq ,completed t))
             (error (unless ,quiet
                      (if (eq (car ,error-data) 'user-error)
                          (signal 'user-error (cdr ,error-data))
                        (user-error "Emmet: %s" (error-message-string ,error-data))))))
         (unless ,completed ,cleanup)))))

;;;###autoload
(defun emmet2-capf ()
  "Offer expansion choices and update them while typing in the same context.
Expansion is lazy so a frontend can apply its prefix threshold first.
Candidate properties distinguish choices with identical source text, as with
overloaded language-server completions.  Frontends which discard properties
can still accept the first expansion."
  (emmet2-capf--guard (not emmet2-capf--explicit) nil
    (let ((automatic (or (not emmet2-capf--explicit)
                         (and (derived-mode-p 'css-base-mode) (not emmet2-context-provider))))
          (quiet (not emmet2-capf--explicit)))
      (when-let* ((analysis (and (not buffer-read-only) (emmet2-context-analyze automatic)))
                  (_ (or (not automatic) (emmet2-capf--confident-p analysis))))
        (require 'emmet2-corfu)
        (emmet2-corfu--enable)
        (let* ((provider emmet2-context-provider)
               (snapshot (emmet2-insert-snapshot analysis))
               (settings (emmet2-capf--settings analysis))
               ;; Frontends query a table many times per keystroke.  Classify the
               ;; host again only when an input of that analysis has changed.
               (validated (emmet2-context-revision))
               (abbreviation (plist-get analysis :abbr))
               (choices 'unexpanded)
               (cache nil)
               (live t))
          (cl-labels
              ((invalidate () (setq live nil choices nil cache nil))
               (current-p ()
                 (when (and live (not (eq provider emmet2-context-provider)))
                   (setq live nil choices nil cache nil))
                 (and live
                      (let ((revision (emmet2-context-revision)))
                        (when (emmet2-capf--current-p analysis snapshot settings automatic
                                                      (equal revision validated))
                          (setq validated revision)
                          t))))
               (refresh ()
                 (or (current-p)
                     (when live
                       (let ((next (and (eq (current-buffer) (plist-get snapshot :buffer))
                                        (eq major-mode (plist-get snapshot :mode))
                                        (not buffer-read-only)
                                        (emmet2-context-analyze automatic))))
                         (if (and (emmet2-capf--same-context-p analysis next)
                                  (equal settings (emmet2-capf--settings next))
                                  (<= (plist-get next :beg) (point) (plist-get next :end))
                                  (not (= (buffer-chars-modified-tick) (plist-get snapshot :tick)))
                                  (not (equal abbreviation (plist-get next :abbr)))
                                  (or (not automatic) (emmet2-capf--confident-p next)))
                             (progn
                               (setq analysis next snapshot (emmet2-insert-snapshot next)
                                     abbreviation (plist-get next :abbr) choices 'unexpanded
                                     validated (emmet2-context-revision))
                               t)
                           (setq live nil cache nil choices nil))))))
               (expanded ()
                 (when (current-p)
                   (when (eq choices 'unexpanded)
                     ;; Failure belongs to this input revision.  Never retry it on
                     ;; another metadata or display query.
                     (setq choices nil)
                     (let ((next (emmet2-capf--choices analysis cache)))
                       (if (current-p)
                           (setq cache next choices (plist-get next :choices))
                         (setq live nil cache nil))))
                   (and live choices)))
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
                   (let ((candidates (mapcar (lambda (entry)
                                               (propertize abbreviation 'emmet2--choice entry)) choices)))
                     (if (and (null action) (equal string abbreviation)
                              (test-completion string candidates predicate))
                         string
                       (complete-with-action action candidates string predicate)))))))
             :exclusive 'no
             :company-kind (lambda (_) 'snippet)
             :company-doc-buffer
             (lambda (candidate)
               (emmet2-capf--guard quiet (invalidate)
                 (when-let* ((_ (equal candidate abbreviation))
                             (entry (choice candidate (expanded)))
                             (text (plist-get entry :text))
                             (_ (string-match-p "\n" text)))
                   (emmet2-preview text (emmet2--output-syntax analysis)))))
             :affixation-function
             (lambda (candidates)
               (emmet2-capf--guard quiet (invalidate)
                 ;; Validate once for this synchronous display batch, not for each row.
                 (let ((entries (and (member abbreviation candidates) (expanded))))
                   (mapcar (lambda (candidate)
                             ;; Preserve the candidate and its choice identity for native
                             ;; *Completions* too.  Only this display copy is concealed.
                             (list (propertize candidate 'display "")
                                   (if-let* ((entry (and (equal candidate abbreviation)
                                                         (choice candidate entries))))
                                       (copy-sequence (plist-get entry :display)) "") ""))
                           candidates))))
             :exit-function
             (lambda (candidate status)
               (emmet2-capf--guard nil (invalidate)
                 (when-let* ((_ (and (eq status 'finished) (equal candidate abbreviation)))
                             (entry (choice candidate (expanded))))
                   (emmet2-insert (emmet2-insert-snapshot analysis) (plist-get entry :result))))))))))))

;;;###autoload
(defun emmet2-complete ()
  "Request Emmet choices through the configured completion frontend.
Built-in CSS uses exactly the automatic CAPF's admission rules.  Other hosts
retain their explicit-request contract, including manual markup and grammar
initialization.  The frontend decides presentation and sole-match acceptance;
this command does not choose or insert the first candidate itself."
  (interactive)
  (emmet2-capf--guard nil nil
    (let ((completion-at-point-functions '(emmet2-capf))
          (emmet2-capf--explicit t))
      (unless (completion-at-point)
        (user-error "There is no Emmet completion at point")))))

(provide 'emmet2-capf)
;;; emmet2-capf.el ends here
