;;; emmet2-fuzzy.el --- Ordered matching and match positions -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Case-insensitive subsequence search implemented here, so ranking does not
;; depend on the user's completion styles.  Each query character consumes a
;; distinct candidate character.  Exact names, prefixes, word initials and
;; contiguous runs rank ahead of scattered matches.  The same
;; match supplies scoring and highlighting; equal scores retain source order.
;; Optional partial matching is a public utility; CSS abbreviation search
;; has its own word-aware index in emmet2-css-search.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defun emmet2-fuzzy--boundary-p (text position)
  "Whether POSITION begins a word in TEXT."
  (or (= position 0)
      (memq (aref text (1- position)) '(?- ?_ ?\s ?\t ?\n ?: ?/ ?. ?@))
      (and (<= ?a (aref text (1- position)) ?z)
           (<= ?A (aref text position) ?Z))))

(defun emmet2-fuzzy--positions (needle text &optional original)
  "Find ordered, already case-folded NEEDLE positions in TEXT, or nil.
When ORIGINAL is supplied, require word initials in its original spelling."
  (let ((offset 0) positions)
    (catch 'missing
      (dotimes (index (length needle))
        (let ((position (cl-position (aref needle index) text :start offset)))
          (while (and position original (not (emmet2-fuzzy--boundary-p original position)))
            (setq position (cl-position (aref needle index) text :start (1+ position))))
          (unless position (throw 'missing nil))
          (push position positions)
          (setq offset (1+ position))))
      (nreverse positions))))

(defun emmet2-fuzzy-match (query candidate &optional partial)
  "Return QUERY's match against CANDIDATE, or nil.
The result has :score and zero-based :positions in CANDIDATE.  Scores are
positive and at most one.  Positions strictly increase, including repeated
query characters.  With PARTIAL, a nonempty matched query prefix suffices;
the score is discounted by the proportion of query characters consumed.
Empty queries do not match.  Work grows with the product of the two string
lengths."
  (let* ((needle (downcase query)) (text (downcase candidate))
         (size (length text)) (count (length needle)) initials substring)
    (when (and (> count 0) (> size 0))
      (cond
       ((string-prefix-p needle text)
        (list :score (if (= count size) 1.0 (+ 0.9 (/ 0.09 (1+ (- size count)))))
              :positions (number-sequence 0 (1- count))))
       ((and partial (string-prefix-p text needle))
        (list :score (+ (* 0.49 (/ (float size) count)) 0.001)
              :positions (number-sequence 0 (1- size))))
       ((and (not partial) (not (emmet2-fuzzy--positions needle text))) nil)
       ((setq initials (emmet2-fuzzy--positions needle text candidate))
        (list :score (+ 0.8 (/ 0.09 (1+ (+ (car initials) (- size count))))) :positions initials))
       ((setq substring (string-search needle text))
        (let ((quality (+ (* 16 count) (* 16 (1- count))
                          (if (emmet2-fuzzy--boundary-p candidate substring) 16 0) (- substring))))
          (list :score (+ 0.5 (/ 0.09 (1+ (+ (- (* 48 count) quality) (- size count)))))
                :positions (number-sequence substring (+ substring count -1)))))
       (t
        (let ((previous nil) (row 0) best matched done)
          (while (and (< row count) (not done))
            ;; Row R has matched R query characters; keep only the columns that leave room for the rest.
            (let ((current (make-vector (if partial (- size row) (1+ (- size count))) nil))
                  gap-best gap-position row-best)
              (dotimes (column (length current))
                (let ((position (+ row column)))
                  (when (and (> row 0) (aref previous column))
                    (let* ((state (aref previous column))
                           (value (+ (car state) (1- position))))
                      (when (or (null gap-best) (> value (+ (car gap-best) gap-position)))
                        (setq gap-best state gap-position (1- position)))))
                  (when (= (aref needle row) (aref text position))
                    (let* ((adjacent (and (> row 0) (aref previous column)))
                           (prior gap-best)
                           (score (cond ((= row 0) (- position))
                                        (gap-best (+ (car gap-best) gap-position (- position) 1)))))
                      (when (and (> row 0) adjacent
                                 (or (null score) (> (+ (car adjacent) 16) score)))
                        (setq score (+ (car adjacent) 16) prior adjacent))
                      (when score
                        (let ((state (cons (+ score 16 (if (emmet2-fuzzy--boundary-p candidate position) 16 0))
                                           (cons position (and (> row 0) (cdr prior))))))
                          (aset current column state)
                          (when (or (null row-best) (> (car state) (car row-best)))
                            (setq row-best state))))))))
              (if row-best
                  (setq previous current best row-best matched (1+ row) row (1+ row))
                (setq done t))))
          (when (and best (or partial (= matched count)))
            (let* ((positions (reverse (cdr best)))
                   (prefix (equal positions (number-sequence 0 (1- matched))))
                   (tier (cond ((and prefix (= matched size)) 1.0)
                               (prefix 0.9)
                               ((cl-every (lambda (position) (emmet2-fuzzy--boundary-p candidate position)) positions) 0.8)
                               (t 0.5)))
                   (quality (/ 0.09 (1+ (+ (- (* 48 matched) (car best)) (- size matched))))))
              (list :score (if (= matched count) (if (= tier 1.0) tier (+ tier quality))
                             (+ (* 0.49 (/ (float matched) count)) (* 0.001 tier)))
                    :positions positions)))))))))

(defun emmet2-fuzzy-score (query candidate &optional partial)
  "Return QUERY's score against CANDIDATE, or zero; see `emmet2-fuzzy-match'.
PARTIAL permits a nonempty matched query prefix."
  (or (plist-get (emmet2-fuzzy-match query candidate partial) :score) 0.0))

(defun emmet2-fuzzy-find (query candidates &optional min-score partial key)
  "Find the best CANDIDATES item for QUERY, or nil.
MIN-SCORE defaults to zero.  PARTIAL allows an unmatched query suffix.
KEY extracts the candidate text.  Exact hits return immediately; ties keep
the first item so callers can supply a stable, deliberate source order."
  (let ((maximum 0.0) best)
    (catch 'exact
      (dolist (candidate candidates)
        (let ((score (emmet2-fuzzy-score query (if key (funcall key candidate) candidate) partial)))
          (when (= score 1.0) (throw 'exact candidate))
          (when (> score maximum) (setq maximum score best candidate))))
      (and (>= maximum (or min-score 0)) best))))

(defun emmet2-fuzzy-filter (query candidates &optional key)
  "Return CANDIDATES matching all of QUERY, in descending score order.
KEY extracts a candidate string.  Equal scores retain the input order.
An empty QUERY returns a fresh list of all candidates.  Neither the input
list nor its items are modified; this function does not inspect a buffer."
  (if (string-empty-p query) (copy-sequence candidates)
    (let (matches)
      (dolist (candidate candidates)
        (when-let* ((match (emmet2-fuzzy-match query (if key (funcall key candidate) candidate))))
          (push (cons (plist-get match :score) candidate) matches)))
      (mapcar #'cdr (cl-stable-sort (nreverse matches) #'> :key #'car)))))

(provide 'emmet2-fuzzy)
;;; emmet2-fuzzy.el ends here
