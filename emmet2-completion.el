;;; emmet2-completion.el --- Fuzzy name completion for hosts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Value and name completion for hosts.  Hosts supply candidates, replacement
;; bounds and an identity function mapping each spelling to its name; this
;; module provides the completion table, the emmet2-name style with fuzzy
;; matching, and placing point inside an accepted empty call such as calc().
;; It does not inspect the buffer.  Abbreviation expansion uses `emmet2-capf'.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'emmet2-fuzzy)
(declare-function emmet2-corfu--enable "emmet2-corfu" ())
;; A completion table must return candidates that start with its input, so
;; fuzzy, escape-aware and Sass-equivalent matching happen in the emmet2-name
;; style, which reads the table's identity rules from its metadata.

(defun emmet2-completion--style-match (string table predicate point)
  "Match STRING at POINT against TABLE under PREDICATE.
Return (PAIRS IDENTITY FOLD), or nil for a table without name metadata.
PAIRS are (SPELLING . NAME) for the candidates whose NAME, their spelling
under IDENTITY, matches the text before POINT and contains the text after
it.  FOLD is non-nil when names compare without regard to case."
  (let* ((input (substring string 0 point))
         (metadata (completion-metadata input table predicate))
         (identity (completion-metadata-get metadata 'emmet2-identity)))
    (when identity
      (let* ((fold (completion-metadata-get metadata 'emmet2-fuzzy))
             (case-fold-search fold)
             (query (funcall identity input))
             (rest (funcall identity (substring string point)))
             (pairs (mapcar (lambda (name) (cons name (funcall identity name)))
                            (all-completions "" table predicate)))
             (pairs (if fold
                        (emmet2-fuzzy-filter query pairs #'cdr)
                      (cl-remove-if-not
                       (lambda (pair) (string-prefix-p query (cdr pair))) pairs))))
        (list (if (string-empty-p rest)
                  pairs
                (cl-remove-if-not
                 (lambda (pair)
                   (string-match-p (regexp-quote rest) (cdr pair)
                                   (if fold 0 (length query))))
                 pairs))
              identity fold)))))

(defun emmet2-completion--highlight (spelling input fold)
  "Return a copy of SPELLING with its match of INPUT marked for display.
With FOLD the match is fuzzy; otherwise INPUT is a prefix."
  (let ((name (copy-sequence spelling)))
    (cond
     (fold
      (emmet2-fuzzy--highlight (plist-get (emmet2-fuzzy-match input spelling) :positions) name))
     ((string-prefix-p input spelling)
      (add-face-text-property 0 (length input) 'completions-common-part nil name)))
    name))

(defun emmet2-completion--style-all (string table predicate point)
  "Return TABLE's candidates for STRING at POINT under PREDICATE, best first."
  (pcase-let ((`(,pairs ,_ ,fold) (emmet2-completion--style-match
                                   string table predicate point)))
    (when pairs
      (let ((input (substring string 0 point))
            (names (mapcar #'car pairs)))
        (if completion-lazy-hilit
            (setq completion-lazy-hilit-fn
                  (lambda (name) (emmet2-completion--highlight name input fold)))
          (setq names (mapcar (lambda (name)
                                (emmet2-completion--highlight name input fold))
                              names)))
        (nconc names 0)))))

(defun emmet2-completion--merge-suffix (completion suffix fold)
  "Return SUFFIX without the longest beginning that COMPLETION already ends with.
Non-nil FOLD ignores case."
  (let ((overlap (min (length completion) (length suffix))))
    (while (and (> overlap 0)
                (not (eq t (compare-strings completion (- (length completion) overlap) nil
                                            suffix 0 overlap fold))))
      (setq overlap (1- overlap)))
    (substring suffix overlap)))

(defun emmet2-completion--style-try (string table predicate point)
  "Complete STRING at POINT in TABLE under PREDICATE as far as is unambiguous.
Candidates keep their spelling, and the text after POINT is kept without
repeating what the completion already supplies.  Ambiguous matches keep the
input unless every candidate extends it the same way."
  (pcase-let ((`(,pairs ,identity ,fold) (emmet2-completion--style-match
                                          string table predicate point)))
    (when pairs
      (let* ((completion-ignore-case fold)
             (input (substring string 0 point))
             (suffix (substring string point))
             (query (funcall identity input))
             (spellings (mapcar #'car pairs))
             (names (mapcar #'cdr pairs))
             (common (try-completion "" spellings))
             (common (if (eq common t) (car spellings) common))
             (plain-common (funcall identity common))
             (semantic-common (try-completion "" names))
             (semantic-common (if (eq semantic-common t) (car names) semantic-common))
             ;; Escape spellings can share an incomplete escape or raw prefix; then keep the input as typed.
             (result (if (and (not (string-suffix-p "\\" common))
                              (string-prefix-p query plain-common fold)
                              (string-prefix-p plain-common semantic-common fold))
                         common
                       input))
             (merged (concat result
                             (emmet2-completion--merge-suffix result suffix fold))))
        (if (cdr pairs) (cons merged (length result))
          ;; A sole match replaces the whole field; matching found the text after point in it.
          (let ((spelling (car spellings)))
            (if (and (equal spelling string) (= point (length string))) t
              (cons spelling (length spelling)))))))))

(add-to-list 'completion-styles-alist
             '(emmet2-name emmet2-completion--style-try emmet2-completion--style-all
                           "Names matched by host identity, optionally fuzzily."))
(add-to-list 'completion-category-defaults '(emmet2-value (styles emmet2-name)))

(cl-defun emmet2-completion-capf (begin end entries &key (category 'emmet2-value)
                                        (identity #'identity) (fuzzy t) annotation prefix)
  "Return completion data offering ENTRIES between BEGIN and END.
ENTRIES are (NAME . DOCUMENTATION) pairs, or a zero-argument function which
collects them on the first candidate query.  Its completed result, including
nil, belongs to this table; metadata queries do not call it.  Collection
requires the original buffer, mode, text, point and restriction.  An input
interruption leaves collection retryable.  DOCUMENTATION, which may be nil,
is returned through :company-docsig.  Return the value from a function in
`completion-at-point-functions'.  It is exclusive, so return nil yourself
when no entry fits; function ENTRIES cannot tell in advance, and an empty
collection still keeps later completion functions from running.  CATEGORY,
`emmet2-value' by default, is the completion category; IDENTITY and FUZZY
take effect only where the emmet2-name style
applies, which is the default for `emmet2-value' alone.  IDENTITY maps a
spelling to the name it denotes, `identity' by default.  Non-nil FUZZY, the
default, matches case-insensitively and fuzzily; nil matches literal
prefixes.  ANNOTATION is a string shown after every candidate.  PREFIX is
passed as :company-prefix-length; t lets Corfu and Company complete before
their prefix threshold.  When ( already follows END, names ending in () are
offered without them.  Accepting an empty call such as calc() moves point
inside its parentheses; no snippet fields are created.  Offering a table also
installs the Corfu advice of emmet2-corfu.el, which affects only tables that
emmet2 builds."
  ;; INTERIM (since 2026-10-03, until Corfu skips strings without line breaks): only the line-break guard needs this; see ARCHITECTURE.md#corfu-adapter.
  (require 'emmet2-corfu)
  (emmet2-corfu--enable)
  (let* ((buffer (current-buffer))
         (mode major-mode)
         (revision (list major-mode (buffer-chars-modified-tick) (point) (point-min) (point-max)))
         (call-follows (eq (char-after end) ?\())
         ;; One publication keeps even an interrupted collection retryable.
         ;; A cons of entries and names distinguishes an empty result from nil.
         prepared
         (metadata `(metadata (category . ,category)
                              (display-sort-function . identity)
                              (cycle-sort-function . identity)
                              (emmet2-identity . ,identity)
                              (emmet2-fuzzy . ,fuzzy))))
    (cl-labels
        ((prepare ()
           (or prepared
               (when (or (not (functionp entries))
                         (and (eq buffer (current-buffer))
                              (equal revision (list major-mode (buffer-chars-modified-tick)
                                                    (point) (point-min) (point-max)))))
                 (let* ((values (if (functionp entries) (funcall entries) entries))
                        ;; Leave existing call arguments intact.
                        (values (if call-follows
                                    (mapcar (lambda (entry)
                                              (if (string-suffix-p "()" (car entry))
                                                  (cons (substring (car entry) 0 -2) (cdr entry))
                                                entry)) values)
                                  values)))
                   (setq prepared (cons values (delete-dups (mapcar #'car values)))))))))
      (unless (functionp entries) (prepare))
      (list begin end
            (lambda (string predicate action)
              (cond ((eq action 'metadata) metadata)
                    ((eq (car-safe action) 'boundaries) nil)
                    (t (complete-with-action action (cdr (prepare)) string predicate))))
            :exclusive t :company-prefix-length prefix
            :annotation-function (lambda (_) annotation)
            :company-docsig (lambda (candidate) (or (cdr (assoc candidate (car (prepare)))) candidate))
            :exit-function
            (lambda (candidate status)
              (when (and (eq status 'finished) (eq buffer (current-buffer))
                         (eq mode major-mode) (member candidate (cdr (prepare)))
                         (<= (point-min) begin (point))
                         (equal candidate (buffer-substring-no-properties begin (point))))
                (when (string-suffix-p "()" candidate)
                  (backward-char))))))))

(provide 'emmet2-completion)
;;; emmet2-completion.el ends here
