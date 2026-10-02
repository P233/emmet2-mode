;;; emmet2-completion.el --- Shared semantic name completion -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Hosts supply candidates, spelling identity and replacement bounds.  This
;; module owns table protocol, fuzzy matching and function acceptance; it does
;; not classify source or discover host symbols.  Expansion keeps its own CAPF.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'emmet2-fuzzy)
;; Matching.  A completion table must return candidates that begin with its
;; input, so fuzzy, escape-aware and Sass-equivalent matching cannot live in
;; one.  The table names its identity rules in its metadata, and this style,
;; the default for the host category, applies them.

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
      (dolist (position (plist-get (emmet2-fuzzy-match input spelling) :positions))
        (add-face-text-property position (1+ position)
                                'completions-common-part nil name)))
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
  "Return SUFFIX without the longest beginning that COMPLETION already ends with."
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
             ;; Different escape spellings can share an incomplete escape or
             ;; a shorter raw prefix.  Keep the input while showing candidates.
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
  "Return a semantic CAPF for ENTRIES replacing BEGIN through END.
ENTRIES are (NAME . DOCUMENTATION) pairs.  IDENTITY maps spellings to names;
FUZZY selects case-insensitive fuzzy matching instead of literal prefixes.
CATEGORY owns the user's completion-style choice.  ANNOTATION labels rows;
PREFIX permits immediate completion after a host's syntactic trigger.
Accepted empty function calls place point inside their parentheses.
Hosts own subsequent navigation; this callback creates no snippet fields."
  (let* (;; Completing a function name before an existing call keeps its
         ;; authored arguments and parentheses outside the replacement range.
         (entries (if (eq (char-after end) ?\()
                      (mapcar (lambda (entry)
                                (if (string-suffix-p "()" (car entry))
                                    (cons (substring (car entry) 0 -2) (cdr entry))
                                  entry)) entries)
                    entries))
         (names (delete-dups (mapcar #'car entries)))
         (buffer (current-buffer))
         (mode major-mode)
         (metadata `(metadata (category . ,category)
                              (display-sort-function . identity)
                              (cycle-sort-function . identity)
                              (emmet2-identity . ,identity)
                              (emmet2-fuzzy . ,fuzzy))))
    (list begin end
          (lambda (string predicate action)
            (if (eq action 'metadata) metadata
              (complete-with-action action names string predicate)))
          :exclusive t :company-prefix-length prefix
          :annotation-function (lambda (_) annotation)
          :company-docsig (lambda (candidate) (or (cdr (assoc candidate entries)) candidate))
          :exit-function
          (lambda (candidate status)
            (when (and (eq status 'finished) (eq buffer (current-buffer))
                       (eq mode major-mode) (member candidate names)
                       (<= (point-min) begin (point))
                       (equal candidate (buffer-substring-no-properties begin (point))))
              (when (string-suffix-p "()" candidate)
                (backward-char)))))))

(provide 'emmet2-completion)
;;; emmet2-completion.el ends here
