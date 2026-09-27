;;; emmet2-capf.el --- Original-abbreviation completion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A completion session owns one immutable source snapshot and one lazy result.
;; Candidate text is always the abbreviation; only a finished, current session
;; may expand it.  Frontend settings and source restoration are not ours.

;;; Code:
(require 'emmet2-mode)
(autoload 'emmet2-preview "emmet2-preview")

(defun emmet2-capf--confident-p (analysis)
  "Whether ANALYSIS has a completion signal beyond a bare identifier."
  (let ((abbreviation (plist-get analysis :abbr)) (case-fold-search nil))
    (pcase (plist-get analysis :lang)
      ('markup (not (string-match-p "\\`[[:alnum:]_:-]+\\'" abbreviation)))
      ((or 'css 'css-in-js)
       (or (string-match-p (rx (or digit upper (in "#!%,(+["))) abbreviation)
           (and (eq (plist-get analysis :lang) 'css)
                (string-match-p "\\`\\(?:@[[:alpha:]]\\|[^:]*::?[[:alpha:]]\\)" abbreviation)))))))

(defun emmet2-capf--settings (analysis)
  "Return the source settings affecting ANALYSIS's result and lifetime."
  (list emmet2-mode emmet2-markup-variant emmet2-css-modules-object
        emmet2-class-names-constructor (emmet2-insert-render-options analysis)))

(defun emmet2-capf--current-p (analysis snapshot settings)
  "Whether ANALYSIS, SNAPSHOT and SETTINGS still describe this session.
Completion may move point from its original position to the candidate end.
All source checks remain strict; a text edit ends this immutable session."
  (and (eq (current-buffer) (plist-get snapshot :buffer))
       (memq (point) (list (plist-get snapshot :point) (plist-get snapshot :end)))
       (save-excursion
         (goto-char (plist-get snapshot :point))
         (emmet2-insert-snapshot-valid-p snapshot))
       (equal settings (emmet2-capf--settings analysis))
       (equal analysis (emmet2-context-analyze t))))

;;;###autoload
(defun emmet2-capf ()
  "Complete one original abbreviation in a confirmed, confident context.
Expansion is lazy so a frontend can apply its prefix threshold first."
  (when-let* ((analysis (and (not buffer-read-only) (emmet2-context-analyze t)))
              (_ (emmet2-capf--confident-p analysis)))
    (let* ((snapshot (emmet2-insert-snapshot analysis))
           (settings (emmet2-capf--settings analysis))
           (abbreviation (plist-get analysis :abbr))
           (result 'unexpanded))
      (cl-labels
          ((current-p () (emmet2-capf--current-p analysis snapshot settings))
           (expanded ()
             (when (current-p)
               (if (not (eq result 'unexpanded)) result
                 (setq result (condition-case nil (emmet2--expand-analysis analysis)
                                (emmet2-parse-error nil)))
                 ;; Only the backend can run process filters/timers between
                 ;; validation and returning the session's cached result.
                 (when (current-p) result)))))
        (list
         (plist-get analysis :beg) (plist-get analysis :end)
         (lambda (string predicate action)
           (cond
            ((eq action 'metadata) '(metadata (category . emmet2)))
            ((expanded)
             (if (and (null action) (equal string abbreviation)
                      (test-completion string (list abbreviation) predicate))
                 string
               (complete-with-action action (list abbreviation) string predicate)))))
         :exclusive 'no
         :company-kind (lambda (_) 'snippet)
         :company-doc-buffer
         (lambda (candidate)
           (when (and (equal candidate abbreviation) (expanded))
             (emmet2-preview (plist-get result :text) (emmet2--output-syntax analysis))))
         :annotation-function
         (lambda (candidate)
           (when (and (equal candidate abbreviation) (expanded))
             (concat "  " (truncate-string-to-width
                            (replace-regexp-in-string "[\n\r\t ]+" " " (plist-get result :text))
                            60 nil nil "…"))))
         :exit-function
         (lambda (candidate status)
           (when (and (eq status 'finished) (equal candidate abbreviation) (expanded))
             (emmet2-insert (emmet2-insert-snapshot analysis) result))))))))

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
