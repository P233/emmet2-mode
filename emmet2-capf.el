;;; emmet2-capf.el --- Live expansion completion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A table owns the current input revision and its lazy expansion choices.
;; Candidates retain the typed text; properties identify alternative expansions.
;; Only a finished, current choice may write through the single insert owner.
;; Affixation supplies display text without changing the completion payload.

;;; Code:
(require 'emmet2-mode)
(autoload 'emmet2-preview "emmet2-preview")

(defun emmet2-capf--confident-p (analysis)
  "Whether ANALYSIS has an Emmet signal or a known CSS snippet prefix."
  (let ((abbreviation (plist-get analysis :abbr)) (case-fold-search nil))
    (pcase (plist-get analysis :lang)
      ;; Words ending a sentence, such as end. or e.g., are prose.
      ('markup (not (string-match-p "\\`\\(?:[[:alnum:]_:-]+\\|[[:alnum:]_:.-]*\\.\\)\\'" abbreviation)))
      ((or 'css 'css-in-js)
       (or (string-match-p (rx (or digit upper (in "#!%,(+["))) abbreviation)
           (and (string-match-p "\\`[a-z]+\\'" abbreviation)
                (or (emmet2-engine-stylesheet-completions abbreviation)
                    (emmet2-extensions-css-value-abbreviation-p abbreviation)))
           (and (eq (plist-get analysis :lang) 'css)
                (string-match-p "\\`\\(?:@[[:alpha:]]\\|[^:]*::?[[:alpha:]]\\)" abbreviation)))))))

(defun emmet2-capf--settings (analysis)
  "Return the source settings affecting ANALYSIS's result and lifetime."
  (list emmet2-mode emmet2-markup-variant emmet2-css-modules-object
        emmet2-class-names-constructor (emmet2-insert-render-options analysis)))

(defun emmet2-capf--current-p (analysis snapshot settings)
  "Whether ANALYSIS, SNAPSHOT and SETTINGS still describe this input revision.
Completion may move point from its original position to the candidate end.
Source checks remain strict; only table queries may advance the revision."
  (and (not buffer-read-only)
       (eq (current-buffer) (plist-get snapshot :buffer))
       (<= (point-min) (plist-get snapshot :point) (point-max))
       (memq (point) (list (plist-get snapshot :point) (plist-get snapshot :end)))
       (save-excursion
         (goto-char (plist-get snapshot :point))
         (emmet2-insert-snapshot-valid-p snapshot))
       (equal settings (emmet2-capf--settings analysis))
       (equal analysis (emmet2-context-analyze t))))

(defun emmet2-capf--same-context-p (before after)
  "Whether BEFORE and AFTER have the same source anchor and host context."
  (and after
       (cl-every (lambda (key) (equal (plist-get before key) (plist-get after key)))
                 '(:beg :lang :syntax :position))))

(defun emmet2-capf--completion-parts (analysis)
  "Return (NAMES CONFIRMED INPUT) for ANALYSIS.
NAMES contains exact and CSS prefix choices for the last property.  CONFIRMED
is the source before the last top-level comma; INPUT is the remaining fragment.
A pending CSS comma keeps the preceding fragment.  Explicit expansion remains
strict about empty properties."
  (let ((abbreviation (plist-get analysis :abbr)))
    (if (not (memq (plist-get analysis :lang) '(css css-in-js)))
        (list (list abbreviation) nil abbreviation)
      (let ((parts (condition-case nil
                       (emmet2-extensions--split abbreviation '(?,))
                     (emmet2-parse-error nil))))
        (when (and (eq (plist-get analysis :lang) 'css)
                   (eq (plist-get analysis :position) 'declaration-start)
                   (string-suffix-p "," abbreviation)
                   (equal (car (last parts)) ""))
          (setq abbreviation (substring abbreviation 0 -1) parts (butlast parts)))
        (let* ((input (if parts (car (last parts)) abbreviation))
               (tail (condition-case nil
                         (car (last (emmet2-extensions--split input '(?+))))
                       (emmet2-parse-error input)))
               (prefix (substring abbreviation 0 (- (length abbreviation) (length tail))))
               (confirmed-length (- (length abbreviation) (length input))))
          (list (cons abbreviation
                      (mapcar (lambda (name) (concat prefix name))
                              (emmet2-engine-stylesheet-completions tail)))
                (when (> confirmed-length 0) (substring abbreviation 0 (1- confirmed-length)))
                input))))))

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

(defun emmet2-capf--choices (analysis)
  "Build ANALYSIS's full results, previews and current-fragment menu labels.
The exact abbreviation ranks first.  Share one expansion budget and expand the
confirmed prefix only once to locate the display boundary in canonical text.
Invalid individual abbreviations do not hide other valid choices."
  (pcase-let* ((`(,names ,confirmed ,input) (emmet2-capf--completion-parts analysis))
               (base-indent (plist-get (emmet2-insert-render-options analysis) :base-indent))
               (seen (make-hash-table :test #'equal)) (choices nil))
    (emmet2-engine-with-expansion
      (let ((prefix (when confirmed
                      (concat (plist-get (emmet2--expand-analysis
                                          (plist-put (copy-sequence analysis) :abbr confirmed)) :text)
                              (if (eq (plist-get analysis :lang) 'css-in-js) ", "
                                (concat "\n" base-indent))))))
        (dolist (name (delete-dups names))
          (let ((result (condition-case nil
                            (emmet2--expand-analysis
                             (plist-put (copy-sequence analysis) :abbr name))
                          (emmet2-parse-error nil))))
            (when (and result (not (gethash result seen)))
              (puthash result t seen)
              (let* ((text (plist-get result :text))
                     ;; Selectors and at-rules use different rendering paths;
                     ;; only hide a prefix that the property formatter emitted.
                     (split (and prefix (string-prefix-p prefix text))))
                (push (list :result result
                            :text (emmet2-capf--preview-text text base-indent)
                            :label (concat
                                    (when split "… ")
                                    (emmet2-capf--display
                                     (if split (substring text (length prefix)) text)
                                     (if (and prefix (not split)) (plist-get analysis :abbr) input))))
                      choices)))))))
    (nreverse choices)))

(defun emmet2-capf--display (text abbreviation)
  "Return TEXT as one menu row, highlighting ABBREVIATION.
Normalize line breaks and surrounding indentation.  Highlight
word characters when they all occur in order; aliases without a literal
correspondence remain unhighlighted.  Never modify the supplied text."
  (let* ((text (copy-sequence
                (replace-regexp-in-string "[ \t]*\n[ \t\n]*" " " text)))
         (needle (downcase (replace-regexp-in-string "[^[:alnum:]_-]" "" abbreviation)))
         (haystack (downcase text)) (offset 0) positions)
    (when (cl-every
           (lambda (character)
             (when-let* ((position (cl-position character haystack :start offset)))
               (push position positions) (setq offset (1+ position))))
           needle)
      (dolist (position positions)
        (add-face-text-property position (1+ position) 'completions-common-part nil text)))
    text))

;;;###autoload
(defun emmet2-capf ()
  "Offer expansion choices and update them while typing in the same context.
Expansion is lazy so a frontend can apply its prefix threshold first.
Candidate properties distinguish choices with identical source text, as with
overloaded language-server completions.  Frontends which discard properties
can still accept the first expansion."
  (when-let* ((analysis (and (not buffer-read-only) (emmet2-context-analyze t)))
              (_ (emmet2-capf--confident-p analysis)))
    (let* ((snapshot (emmet2-insert-snapshot analysis))
           (settings (emmet2-capf--settings analysis))
           (abbreviation (plist-get analysis :abbr))
           (choices 'unexpanded)
           (live t))
      (cl-labels
          ((current-p () (and live (emmet2-capf--current-p analysis snapshot settings)))
           (refresh ()
             (or (current-p)
                 (when live
                   (let ((next (and (eq (current-buffer) (plist-get snapshot :buffer))
                                    (eq major-mode (plist-get snapshot :mode))
                                    (not buffer-read-only)
                                    (emmet2-context-analyze t))))
                     (if (and (emmet2-capf--same-context-p analysis next)
                              (equal settings (emmet2-capf--settings next))
                              (<= (plist-get next :beg) (point) (plist-get next :end))
                              (not (= (buffer-chars-modified-tick) (plist-get snapshot :tick)))
                              (not (equal abbreviation (plist-get next :abbr)))
                              (emmet2-capf--confident-p next))
                         (progn
                           (setq analysis next snapshot (emmet2-insert-snapshot next)
                                 abbreviation (plist-get next :abbr) choices 'unexpanded)
                           t)
                       (setq live nil))))))
           (expanded ()
             (when (current-p)
               (when (eq choices 'unexpanded)
                 ;; Failure belongs to this input revision.  Never retry it on
                 ;; another metadata/display query; explicit expansion reports it.
                 (setq choices nil)
                 (let ((next (condition-case nil (emmet2-capf--choices analysis)
                               (emmet2-error nil))))
                   (if (current-p) (setq choices next) (setq live nil))))
               (and live choices)))
           (choice (candidate entries)
             (if-let* ((entry (get-text-property 0 'emmet2--choice candidate)))
                 (and (memq entry entries) entry)
               (car entries))))
        (list
         (plist-get analysis :beg) (plist-get analysis :end)
         (lambda (string predicate action)
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
                 (complete-with-action action candidates string predicate))))))
         :exclusive 'no
         :company-kind (lambda (_) 'snippet)
         :company-doc-buffer
         (lambda (candidate)
           (when-let* ((_ (equal candidate abbreviation))
                       (entry (choice candidate (expanded)))
                       (text (plist-get entry :text))
                       (_ (string-match-p "\n" text)))
             (emmet2-preview text (emmet2--output-syntax analysis))))
         :affixation-function
         (lambda (candidates)
           ;; Validate once for this synchronous display batch, not for each row.
           (let ((entries (and (member abbreviation candidates) (expanded))))
             (mapcar (lambda (candidate)
                       ;; Preserve the candidate and its choice identity for native
                       ;; *Completions* too.  Only this display copy is concealed.
                       (list (propertize candidate 'display "")
                             (if-let* ((entry (and (equal candidate abbreviation)
                                                   (choice candidate entries))))
                                 (copy-sequence (plist-get entry :label)) "") ""))
                     candidates)))
         :exit-function
         (lambda (candidate status)
           (when-let* ((_ (and (eq status 'finished) (equal candidate abbreviation)))
                       (entry (choice candidate (expanded))))
             (emmet2-insert (emmet2-insert-snapshot analysis) (plist-get entry :result)))))))))

;;;###autoload
(defun emmet2-complete ()
  "Request Emmet completion alone, using the normal confidence gate.
The public completion frontend and its settings determine presentation."
  (interactive)
  (condition-case error-data
      (progn
        ;; Explicit analysis initializes grammars and reports missing ones;
        ;; the capf still enforces automatic host and confidence restrictions.
        (emmet2-context-analyze)
        (let ((completion-at-point-functions '(emmet2-capf)))
          (unless (completion-at-point)
            (user-error "There is no Emmet completion at point"))))
    (emmet2-error (user-error "%s" (error-message-string error-data)))))

(provide 'emmet2-capf)
;;; emmet2-capf.el ends here
