;;; emmet2-css-search.el --- Ranked CSS property and keyword search -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Rank CSS declarations for an abbreviation.  Query segments abbreviate the
;; words of a property, and optionally of one keyword value, in order.  Scores
;; are log-likelihoods: how a word is abbreviated, which words stay implicit,
;; the property's relevance in data/css-index.json, generated from a pinned
;; VS Code custom data commit, and the size of the keyword's value set.
;; Popularity therefore decides short queries, while longer queries follow
;; their word structure.  Scores are fixnums in thousandths of a natural log
;; unit, so ranking allocates no boxed floats.  Authored word aliases claim
;; their letters; property aliases rank first without hiding other choices.
;; The index and aliases are immutable after loading; each query allocates
;; its own scratch tables.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emmet2-engine)

;; Parameters were selected against test/fixtures/css-search-corpus.json.
(defconst emmet2-css-search--likelihoods
  '((word . 0.3) (skeleton . 0.02) (fixed . 0.5) (uncovered . 0.35) (middle . 0.3)
    (leading . 0.12) (own . 0.3) (wide . 0.05) (function . 0.01) (rare . 0.005) (alias . 0.95))
  "Likelihoods of word matches, skipped words and keyword priors.
A skeleton keeps a word's letters in order from its initial.  Uncovered,
middle and leading apply to each unmatched trailing word, skipped inner word
and skipped first word.  Word is a whole-word match and fixed a segment
spelled by an authored word alias.  Own, wide, function and rare are keyword
priors; alias begins a property named by an authored abbreviation.")

(defun emmet2-css-search--score (likelihood)
  "Return LIKELIHOOD's natural log in thousandths, as a fixnum."
  (round (* 1000 (log likelihood))))

(defconst emmet2-css-search--weights
  (mapcar (lambda (entry) (cons (car entry) (emmet2-css-search--score (cdr entry))))
          emmet2-css-search--likelihoods)
  "Scores of `emmet2-css-search--likelihoods'.")

(defconst emmet2-css-search--prefix (vconcat (mapcar #'emmet2-css-search--score '(0.5 0.1 0.15 0.1)))
  "Scores of a word prefix of one, two, three, and four or more letters.
Two letters are often two initials or a property initial and a value.")

(defconst emmet2-css-search--prior-scale 60 "Score per relevance point; the full range is six log units.")
(defconst emmet2-css-search--set-scale 3.0 "A shared keyword's prior is at most this over its set size.")
(defconst emmet2-css-search--exact 5000 "Score bonus for a complete property name or property alias.")

(defconst emmet2-css-search--common '("transparent" "currentColor" "white" "black")
  "Shared keywords used far more often than the rest of their value sets.")

(defconst emmet2-css-search--rare '("type:system-color" "type:system-family-name")
  "Small shared value sets that are valid but rarely written, such as LinkText.
Their size alone would give each keyword a high prior.")

(defun emmet2-css-search--weight (name)
  "Return the score of likelihood NAME from `emmet2-css-search--weights'."
  (alist-get name emmet2-css-search--weights))

(defconst emmet2-css-search--directory
  (file-name-directory (or load-file-name buffer-file-name)))

(defun emmet2-css-search--share (object strings)
  "Return parsed data OBJECT with its equal strings shared through STRINGS.
Lists and pairs are updated in place, so OBJECT must be call-owned; hash
tables are copied.  The shared strings must stay read-only."
  (cond
   ((stringp object) (or (gethash object strings) (puthash object object strings)))
   ((consp object)
    (let ((tail object))
      (while (consp tail)
        (setcar tail (emmet2-css-search--share (car tail) strings))
        (unless (listp (cdr tail))
          (setcdr tail (emmet2-css-search--share (cdr tail) strings)))
        (setq tail (cdr tail))))
    object)
   ((hash-table-p object)
    (let ((copy (make-hash-table :test (hash-table-test object) :size (hash-table-count object))))
      (maphash (lambda (key value)
                 (puthash (emmet2-css-search--share key strings)
                          (emmet2-css-search--share value strings) copy))
               object)
      copy))
   (t object)))

(defun emmet2-css-search--read (name)
  "Read packaged JSON data NAME, sharing its equal strings."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name emmet2-css-search--directory))
    (emmet2-css-search--share (json-parse-buffer :array-type 'list)
                              (make-hash-table :test #'equal))))

(cl-defstruct (emmet2-css-search--property (:constructor emmet2-css-search--property) (:copier nil))
  name words prior keywords own sets descriptor letters)
(cl-defstruct (emmet2-css-search--value (:constructor emmet2-css-search--value) (:copier nil))
  name words prior)

(defun emmet2-css-search--words (name pool)
  "Return NAME's lowercase words as a vector shared through POOL.
POOL maps (NAME) to the vector, and NAME and each word to one shared string,
so a single-word lowercase NAME can be its own word."
  (with-memoization (gethash (list name) pool)
    (with-memoization (gethash name pool) name)
    (vconcat (mapcar (lambda (word) (with-memoization (gethash word pool) word))
                     (split-string (downcase name) "-" t)))))

(defun emmet2-css-search--letters (text)
  "Return the set of lowercase ASCII letters and digits in TEXT as a fixnum."
  (let ((letters 0))
    (dotimes (index (length text))
      (let ((character (aref text index)))
        (cond ((<= ?a character ?z) (setq letters (logior letters (ash 1 (- character ?a)))))
              ((<= ?0 character ?9) (setq letters (logior letters (ash 1 (+ 26 (- character ?0)))))))))
    letters))

(defun emmet2-css-search--bucket (names prior pool)
  "Index keyword NAMES by lowercase initial with score PRIOR.
Return an alist of (INITIAL . VALUES).  Functions score no higher than the
function prior; common keywords no lower than the own prior.  Equal entries
are shared through POOL under (NAME . SCORE), and their words as in
`emmet2-css-search--words'."
  (let ((own (emmet2-css-search--weight 'own)) bucket)
    (dolist (name names bucket)
      (let* ((score (cond ((string-suffix-p "()" name) (min prior (emmet2-css-search--weight 'function)))
                          ((member name emmet2-css-search--common) (max prior own))
                          (t prior)))
             (value (with-memoization (gethash (cons name score) pool)
                      (emmet2-css-search--value
                       :name name :words (emmet2-css-search--words name pool) :prior score)))
             (initial (downcase (aref name 0)))
             (cell (assq initial bucket)))
        (if cell (push value (cdr cell)) (push (list initial value) bucket))))))

(defconst emmet2-css-search--index (emmet2-css-search--read "data/css-index.json")
  "Names, relevance and keyword sets generated alongside data/css-data.json.")

(defconst emmet2-css-search--overrides (emmet2-css-search--read "data/css-overrides.json")
  "Authored CSS overrides, shared by search and expansion.
Search reads the word and property aliases; emmet2-css reads the pseudo and
at-rule keys.")

(defun emmet2-css-search-override (key)
  "Return authored CSS override KEY from the shared immutable catalog.
Search aliases and expansion templates share one packaged data load.
Callers must not modify the returned data."
  (gethash key emmet2-css-search--overrides))

(defconst emmet2-css-search--word-aliases
  (let (aliases)
    (maphash (lambda (key word) (push (cons key word) aliases))
             (gethash "wordAliases" emmet2-css-search--overrides))
    aliases)
  "Authored (ABBREVIATION . WORD) pairs, such as bg for background.")

(defconst emmet2-css-search--property-aliases (gethash "propertyAliases" emmet2-css-search--overrides)
  "Authored abbreviations of properties without a word structure, such as fz.")

(defconst emmet2-css-search--max-alias-length
  (cl-loop for (alias . _) in emmet2-css-search--word-aliases maximize (length alias))
  "Longest authored word alias, which bounds a matching segment.")

(defun emmet2-css-search--index-property (entry pool)
  "Build one immutable search property from generated ENTRY.
Equal keyword entries and words are shared through POOL."
  (let ((name (gethash "name" entry)) (keywords (gethash "values" entry)))
    (emmet2-css-search--property
     :name name :words (emmet2-css-search--words name pool)
     :prior (and (not (gethash "obsolete" entry))
                 (* emmet2-css-search--prior-scale (round (gethash "relevance" entry))))
     :keywords keywords
     :own (emmet2-css-search--bucket keywords (emmet2-css-search--weight 'own) pool)
     :sets (gethash "sets" entry)
     :descriptor (and (gethash "atRule" entry) t)
     :letters (emmet2-css-search--letters name))))

(defun emmet2-css-search--build (index)
  "Build the keyword and property tables of generated INDEX.
Return (SETS WIDE CANONICAL DESCRIPTORS), the values of the constants of
those names.  One call-owned pool shares equal keyword entries, word
vectors and words among them."
  (let ((pool (make-hash-table :test #'equal))
        (own (alist-get 'own emmet2-css-search--likelihoods))
        (sets (make-hash-table :test #'equal))
        (canonical (make-hash-table :test #'equal))
        (descriptors (make-hash-table :test #'equal)))
    ;; One keyword among many shared siblings, such as a named color, is unlikely.
    (maphash (lambda (key names)
               (puthash key (emmet2-css-search--bucket
                             names (emmet2-css-search--score
                                    (if (member key emmet2-css-search--rare)
                                        (alist-get 'rare emmet2-css-search--likelihoods)
                                      (min own (/ emmet2-css-search--set-scale (length names)))))
                             pool)
                        sets))
             (gethash "sets" index))
    (dolist (entry (gethash "properties" index))
      (puthash (gethash "name" entry) (emmet2-css-search--index-property entry pool) canonical))
    (dolist (entry (gethash "descriptors" index))
      (push (emmet2-css-search--index-property entry pool) (gethash (gethash "atRule" entry) descriptors)))
    (list sets (emmet2-css-search--bucket (gethash "wide" index) (emmet2-css-search--weight 'wide) pool)
          canonical descriptors)))

(defconst emmet2-css-search--tables (emmet2-css-search--build emmet2-css-search--index)
  "The keyword and property tables, built together so they share entries.")

(defconst emmet2-css-search--sets (nth 0 emmet2-css-search--tables)
  "Shared keyword sets by key, each indexed by initial.")

(defconst emmet2-css-search--wide (nth 1 emmet2-css-search--tables)
  "CSS-wide keywords accepted by every ordinary property, not by descriptors.")

(defconst emmet2-css-search--canonical (nth 2 emmet2-css-search--tables)
  "Every ordinary property by name.  Obsolete properties have no prior.")

(defconst emmet2-css-search--descriptors (nth 3 emmet2-css-search--tables)
  "Descriptor entries grouped by their enclosing at-rule, from the same index.")

(defun emmet2-css-search--entry (name at-rule)
  "Return NAME's descriptor in AT-RULE, or its ordinary property entry."
  (or (and at-rule (cl-find name (gethash (downcase at-rule) emmet2-css-search--descriptors)
                            :key #'emmet2-css-search--property-name :test #'equal))
      (gethash name emmet2-css-search--canonical)))

(defconst emmet2-css-search--ranked
  (cl-remove-if-not #'emmet2-css-search--property-prior
                    (mapcar (lambda (entry) (gethash (gethash "name" entry) emmet2-css-search--canonical))
                            (gethash "properties" emmet2-css-search--index)))
  "Properties offered as choices, in name order.")

(defconst emmet2-css-search--widest
  (let ((widest 1))
    (dolist (property (append (hash-table-values emmet2-css-search--canonical)
                              (apply #'append (hash-table-values emmet2-css-search--descriptors))))
      (setq widest (max widest (length (emmet2-css-search--property-words property))))
      (dolist (cell (emmet2-css-search--property-own property))
        (dolist (value (cdr cell))
          (setq widest (max widest (length (emmet2-css-search--value-words value)))))))
    (dolist (bucket (cons emmet2-css-search--wide (hash-table-values emmet2-css-search--sets)) widest)
      (dolist (cell bucket)
        (dolist (value (cdr cell))
          (setq widest (max widest (length (emmet2-css-search--value-words value))))))))
  "Most words in any property or keyword name, which bounds alignment tables.")

(defconst emmet2-css-search--max-query-length
  (let ((property-width 0) (value-width 0))
    (dolist (entry (append (gethash "properties" emmet2-css-search--index)
                          (gethash "descriptors" emmet2-css-search--index)))
      (setq property-width (max property-width (length (gethash "name" entry))))
      (dolist (value (gethash "values" entry))
        (setq value-width (max value-width (length value)))))
    (dolist (alias (hash-table-keys emmet2-css-search--property-aliases))
      (setq property-width (max property-width (length alias))))
    (dolist (values (cons (gethash "wide" emmet2-css-search--index)
                         (hash-table-values (gethash "sets" emmet2-css-search--index))))
      (dolist (value values) (setq value-width (max value-width (length value)))))
    (+ property-width value-width (* 2 emmet2-css-search--widest emmet2-css-search--max-alias-length)))
  "Conservative bound for a property and keyword, including authored aliases.
It derives from the pinned vocabulary, not the length of untrusted input.")

(defconst emmet2-css-search--elements
  (let ((table (make-hash-table :test #'equal)))
    (dolist (name (gethash "elements" emmet2-css-search--index) table) (puthash name t table)))
  "Known HTML element names, which are also CSS type selectors.")

;;; Matching

(defsubst emmet2-css-search--find (character string start)
  "Return the index of CHARACTER in STRING from START, or nil.
Unlike `cl-position', this allocates no keyword argument list."
  (let ((index start) (size (length string)))
    (while (and (< index size) (/= (aref string index) character))
      (setq index (1+ index)))
    (and (< index size) index)))

(defun emmet2-css-search--prepare (query)
  "Return (FIXED . CLAIMED) segment tables for lowercase QUERY.
FIXED names the word of each segment that is an authored alias.  CLAIMED
names that word for longer segments beginning with the alias: bgr is bg + r,
never a skeleton of background, though rsz may still abbreviate resize."
  (emmet2-engine--check-deadline)
  (let* ((n (length query)) (width (1+ n))
         (fixed (make-vector (* width width) nil)) (claimed (make-vector (* width width) nil)))
    (dolist (alias emmet2-css-search--word-aliases)
      (let ((size (length (car alias))))
        (dotimes (start (max 0 (1+ (- n size))))
          (when (eq t (compare-strings query start (+ start size) (car alias) 0 nil))
            (aset fixed (+ (* start width) start size) (cdr alias))
            (cl-loop for end from (+ start size 1) to n
                     do (aset claimed (+ (* start width) end) (cdr alias)))))))
    (cons fixed claimed)))

(defun emmet2-css-search--segment (query start end word tables)
  "Return the score that QUERY[START,END) abbreviates WORD, or nil.
TABLES come from `emmet2-css-search--prepare' for QUERY."
  (let* ((key (+ (* start (1+ (length query))) end))
         (fixed (aref (car tables) key)) (size (- end start)) (length (length word)))
    (cond
     (fixed (and (string= fixed word) (emmet2-css-search--weight 'fixed)))
     ((> size length) nil)
     ((eq t (compare-strings query start end word 0 size))
      (if (= size length) (emmet2-css-search--weight 'word)
        (aref emmet2-css-search--prefix (min 3 (1- size)))))
     ((equal (aref (cdr tables) key) word) nil)
     ((eq (aref query start) (aref word 0))
      (let ((offset 1) (index (1+ start)))
        (while (and offset (< index end))
          (setq offset (emmet2-css-search--find (aref query index) word offset))
          (when offset (setq offset (1+ offset) index (1+ index))))
        (and offset (emmet2-css-search--weight 'skeleton)))))))

(defun emmet2-css-search--scratch (n)
  "Return reusable alignment vectors for queries of at most N characters."
  (let ((size (* (1+ n) (1+ emmet2-css-search--widest))))
    (vector (make-vector size nil) (make-vector size nil) (make-vector (1+ n) nil))))

(defun emmet2-css-search--align (query words tables anchored scratch)
  "Align lowercase QUERY's prefixes to WORDS in order, using segment TABLES.
Return a vector whose element I is the best score of QUERY[0,I) with
the remaining words uncovered, or nil.  Hyphens in QUERY must separate
words.  ANCHORED requires the first segment to start the first word.  The
result is SCRATCH's own vector, valid until SCRATCH aligns again."
  (emmet2-engine--check-deadline)
  (let* ((n (length query)) (k (length words)) (width (1+ k))
         (ended (fillarray (aref scratch 0) nil))
         (reach (fillarray (aref scratch 1) nil))
         (result (fillarray (aref scratch 2) nil))
         (leading (emmet2-css-search--weight 'leading))
         (middle (emmet2-css-search--weight 'middle))
         (uncovered (emmet2-css-search--weight 'uncovered)))
    (dotimes (before n)
      (let ((i (1+ before)))
        (dotimes (word k)
          (let ((j (1+ word)) best)
            (if (eq (aref query before) ?-)
                (when (> before 0) (setq best (aref ended (+ (* before width) j))))
              (let ((start before)
                    (minimum (max 0 (- i (max (length (aref words word))
                                             emmet2-css-search--max-alias-length)))))
                (while (and (>= start minimum) (or (= start before) (not (eq (aref query start) ?-))))
                  (let ((prior (if (= start 0) (and (or (not anchored) (= word 0)) (* word leading))
                                 (aref reach (+ (* start width) word)))))
                    (when-let* ((prior prior)
                                (segment (emmet2-css-search--segment query start i (aref words word) tables)))
                      (when (or (null best) (> (+ prior segment) best))
                        (setq best (+ prior segment)))))
                  (setq start (1- start)))))
            (aset ended (+ (* i width) j) best)
            (let* ((previous (and (> word 0) (aref reach (+ (* i width) word))))
                   (skip (and previous (+ previous middle))))
              (aset reach (+ (* i width) j) (if (and best skip) (max best skip) (or best skip))))))
        (dotimes (word k)
          (when-let* ((score (aref ended (+ (* i width) (1+ word)))))
            (let ((total (+ score (* (- k word 1) uncovered))))
              (when (or (null (aref result i)) (> total (aref result i)))
                (aset result i total)))))))
    result))

(defun emmet2-css-search--subsequence-p (query name)
  "Whether QUERY's letters occur in order in NAME."
  (let ((offset 0) (index 0) (n (length query)))
    (while (and offset (< index n))
      (unless (eq (aref query index) ?-)
        (setq offset (emmet2-css-search--find (aref query index) name offset))
        (when offset (setq offset (1+ offset))))
      (setq index (1+ index)))
    (and offset t)))

(defun emmet2-css-search--before-p (score name keyword entry)
  "Whether candidate SCORE, NAME and KEYWORD precedes ranked ENTRY.
ENTRY is (SCORE NAME . KEYWORD); equal scores use spelling."
  (or (> score (car entry))
      (and (= score (car entry))
           (or (string< name (cadr entry))
               (and (string= name (cadr entry)) (string< (or keyword "") (or (cddr entry) "")))))))

(defun emmet2-css-search--offer (hits limit score name keyword)
  "Return ranked HITS after offering SCORE, NAME and KEYWORD.
HITS holds at most LIMIT distinct (SCORE NAME . KEYWORD) entries, best
first, and may be modified.  A property's own keywords and a shared set can
spell the same keyword, so choices compare by spelling.  Rejected candidates
allocate nothing."
  (let ((tail hits) existing)
    (while (and tail (not existing))
      (let ((entry (car tail)))
        (if (and (equal (cadr entry) name) (equal (cddr entry) keyword)) (setq existing entry)
          (setq tail (cdr tail)))))
    (cond
     ((and existing (not (emmet2-css-search--before-p score name keyword existing))) hits)
     ((and (not existing) (>= (length hits) limit)
           (not (emmet2-css-search--before-p score name keyword (car (last hits)))))
      hits)
     (t
      (let ((entry (cons score (cons name keyword))) (rest (if existing (delq existing hits) hits)) head)
        (while (and rest (not (emmet2-css-search--before-p score name keyword (car rest))))
          (push (pop rest) head))
        (setq hits (nconc (nreverse head) (cons entry rest)))
        (when (> (length hits) limit) (setcdr (nthcdr (1- limit) hits) nil))
        hits)))))

(defun emmet2-css-search--value-matches (tail property tables cache scratch hits limit offset)
  "Offer PROPERTY's keywords matching lowercase TAIL to HITS; return HITS.
Each keyword scores its alignment, its prior and OFFSET; LIMIT bounds HITS as
in `emmet2-css-search--offer'.  TABLES and SCRATCH serve TAIL.  Shared sets
are scored once per query through CACHE."
  (let ((initial (aref tail 0)) (name (emmet2-css-search--property-name property)))
    (cl-flet ((score (value)
                (when-let* ((score (aref (emmet2-css-search--align
                                          tail (emmet2-css-search--value-words value) tables t scratch)
                                         (length tail))))
                  ;; Shorter keywords break structural ties, as block before blink.
                  (- (+ score (emmet2-css-search--value-prior value))
                     (length (emmet2-css-search--value-name value))))))
      (dolist (value (cdr (assq initial (emmet2-css-search--property-own property))))
        (when-let* ((score (score value)))
          (setq hits (emmet2-css-search--offer hits limit (+ score offset) name
                                               (emmet2-css-search--value-name value)))))
      (dolist (key (if (emmet2-css-search--property-descriptor property)
                      (emmet2-css-search--property-sets property)
                    (cons nil (emmet2-css-search--property-sets property))))
        (let* ((cache-key (cons key tail)) (shared (gethash cache-key cache 'miss)))
          (when (eq shared 'miss)
            (setq shared nil)
            (dolist (value (cdr (assq initial (if key (gethash key emmet2-css-search--sets)
                                                emmet2-css-search--wide))))
              (when-let* ((score (score value)))
                (push (cons score (emmet2-css-search--value-name value)) shared)))
            (puthash cache-key shared cache))
          (dolist (hit shared)
            (setq hits (emmet2-css-search--offer hits limit (+ (car hit) offset) name (cdr hit)))))))
    hits))

(defun emmet2-css-search (query &optional limit bare at-rule)
  "Return up to LIMIT ranked (PROPERTY . KEYWORD) choices for QUERY.
QUERY abbreviates a property's words, optionally followed by one keyword
value: tac is text-align with center.  After a lowercase start, an
uppercase letter begins the value explicitly, as in mA; otherwise case
is ignored.  Hyphens separate words; only compact queries, at most eight
characters without hyphens, combine a property and a value implicitly.
KEYWORD is nil for a bare property.  BARE offers properties only, as
when an explicit value follows.  Unaligned queries have no choices.
LIMIT defaults to ten.  AT-RULE admits its descriptors.  Signal
`emmet2-backend-error' when the expansion deadline expires."
  (emmet2-engine-with-expansion
    (let ((case-fold-search nil) (limit (or limit 10)))
      ;; Digits occur only inside a few names, such as scrollbar-3dlight-color.
      (when (and (> limit 0) (<= (length query) emmet2-css-search--max-query-length)
                 (string-match-p "\\`[a-zA-Z][-a-zA-Z0-9]*\\'" query))
        (let* ((boundary (and (not bare) (<= ?a (aref query 0) ?z)
                              (string-match "[A-Z]" query 1) (match-beginning 0)))
               (text (downcase query)) (n (length text)) (letters (emmet2-css-search--letters text))
               (compact (and (not bare) (<= n 8) (not (string-search "-" text))))
               (head (if boundary (substring text 0 boundary) text))
               (tables (emmet2-css-search--prepare head))
               (cache (make-hash-table :test #'equal))
               (heads-scratch (emmet2-css-search--scratch (length head)))
               (values-scratch (emmet2-css-search--scratch n))
               (alias-head (emmet2-css-search--weight 'alias))
               (descriptors (and at-rule (gethash (downcase at-rule) emmet2-css-search--descriptors)))
               (shadowed (mapcar (lambda (entry)
                                  (gethash (emmet2-css-search--property-name entry) emmet2-css-search--canonical))
                                descriptors))
               ;; Each split's value tail, its tables and the alias of its head.
               (splits (and (or boundary compact)
                            (cl-loop for split from 1 below n
                                     when (or (null boundary) (= split boundary))
                                     collect (let ((tail (substring text split)))
                                               (list split tail (emmet2-css-search--prepare tail)
                                                     (gethash (substring text 0 split)
                                                              emmet2-css-search--property-aliases))))))
               hits)
          (dolist (property (if descriptors
                               (append (cl-remove-if-not
                                        #'emmet2-css-search--property-prior
                                       descriptors)
                                       (cl-remove-if
                                        (lambda (entry) (memq entry shadowed))
                                        emmet2-css-search--ranked))
                             emmet2-css-search--ranked))
            (let* ((name (emmet2-css-search--property-name property))
                   (prior (emmet2-css-search--property-prior property))
                   (anchored (eq (aref text 0) (aref name 0)))
                   (heads (and (or (and anchored (or boundary compact))
                                   ;; A subsequence needs every letter of TEXT.
                                   (and (= (logand letters (emmet2-css-search--property-letters property))
                                           letters)
                                        (emmet2-css-search--subsequence-p text name)))
                               (emmet2-css-search--align head (emmet2-css-search--property-words property)
                                                         tables nil heads-scratch))))
              (unless boundary
                (when-let* ((score (cond ((or (equal (gethash text emmet2-css-search--property-aliases) name)
                                              (and (> n 1) (string= text name)))
                                          emmet2-css-search--exact)
                                         (heads (aref heads n)))))
                  (setq hits (emmet2-css-search--offer hits limit (+ score prior) name nil))))
              (when (and anchored heads)
                (pcase-dolist (`(,split ,tail ,tail-tables ,alias) splits)
                  (when-let* ((head (if (equal alias name) alias-head (aref heads split))))
                    (setq hits (emmet2-css-search--value-matches tail property tail-tables cache values-scratch
                                                                 hits limit (+ head prior))))))))
          (mapcar #'cdr hits))))))

(defun emmet2-css-search-values (property query &optional limit at-rule)
  "Return up to LIMIT keywords of PROPERTY ranked for QUERY.
Keywords include PROPERTY's own values, values reachable through its syntax,
and CSS-wide keywords for ordinary properties.  QUERY abbreviates a keyword
from its first letter, as ib for inline-block.  LIMIT defaults to ten.
Return nil for an unknown PROPERTY.
AT-RULE selects a descriptor's values when PROPERTY is declared there."
  (emmet2-engine-with-expansion
    (when-let* ((entry (emmet2-css-search--entry property at-rule))
                (limit (or limit 10))
                (_ (and (> limit 0) (<= (length query) emmet2-css-search--max-query-length)
                        (string-match-p "\\`[a-zA-Z][-a-zA-Z]*\\'" query))))
      (let ((text (downcase query)))
        (mapcar #'cddr (emmet2-css-search--value-matches text entry (emmet2-css-search--prepare text)
                                                         (make-hash-table :test #'equal)
                                                         (emmet2-css-search--scratch (length text))
                                                         nil limit 0))))))

(defun emmet2-css-search-value-names (property &optional at-rule)
  "Return fresh PROPERTY value names, including shared and substitution values.
Keywords share ranked search's membership, without its scores.  Substitution
templates additionally include env(), and var() for ordinary properties.
Strings remain shared and read-only; the list may repeat a name, which the
caller may remove.
AT-RULE selects descriptor values, as in ranked search."
  (let* ((entry (emmet2-css-search--entry property at-rule))
         (cascading (not (and entry (emmet2-css-search--property-descriptor entry))))
         (sets (gethash "sets" emmet2-css-search--index)))
    (append (and entry (emmet2-css-search--property-keywords entry))
            (cl-loop for key in (and entry (emmet2-css-search--property-sets entry))
                     append (copy-sequence (gethash key sets)))
            (when cascading (gethash "wide" emmet2-css-search--index))
            (when cascading '("var()"))
            (list "env()"))))

(defun emmet2-css-search-keywords (property &optional at-rule)
  "Return PROPERTY's own keywords in AT-RULE, in source order, sans functions."
  (when-let* ((entry (emmet2-css-search--entry property at-rule)))
    (cl-remove-if (lambda (keyword) (string-suffix-p "()" keyword))
                  (emmet2-css-search--property-keywords entry))))

(defun emmet2-css-search-property-p (name &optional at-rule)
  "Whether NAME is a CSS property or a descriptor admitted by AT-RULE.
Without AT-RULE, accept only ordinary properties, including obsolete ones."
  (and (emmet2-css-search--entry name at-rule) t))

(defun emmet2-css-search-property-names (&optional descriptors)
  "Return ordinary CSS property names; DESCRIPTORS includes descriptors.
The list is fresh; its strings are shared and read-only.  The stylesheet
tokenizer recognizes every spelling; ranked search admits descriptors only
in their enclosing at-rule."
  (let ((names (mapcar (lambda (entry) (gethash "name" entry))
                       (gethash "properties" emmet2-css-search--index))))
    (if descriptors
        (delete-dups (append names (mapcar (lambda (entry) (gethash "name" entry))
                                          (gethash "descriptors" emmet2-css-search--index))))
      names)))

(defun emmet2-css-search-element-p (name)
  "Whether NAME is a known HTML element, also usable as a CSS type selector."
  (and (gethash name emmet2-css-search--elements) t))

(defun emmet2-css-search-at-rules ()
  "Return a fresh list of standard CSS at-rule names."
  (copy-sequence (gethash "atRules" emmet2-css-search--index)))

(defun emmet2-css-search-pseudos ()
  "Return a fresh list of standard CSS pseudo-class and pseudo-element names."
  (copy-sequence (gethash "pseudos" emmet2-css-search--index)))

(provide 'emmet2-css-search)
;;; emmet2-css-search.el ends here
