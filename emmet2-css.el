;;; emmet2-css.el --- CSS abbreviation expansion and choices -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Expand CSS abbreviations: property readings and their ranked choices,
;; aliases such as posa, bracketed values, pseudo selectors and at-rules.
;; CSS-in-JS renders the same declarations as object members.  Property
;; names, final pseudo and at-rule names, top-level value words and units
;; outside the CSS data signal `emmet2-parse-error'.  Each public entry point
;; runs under one expansion deadline.  Nothing here reads or writes editor
;; state.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'emmet2-engine)
(require 'emmet2-engine-stylesheet)
(require 'emmet2-fuzzy)
(require 'emmet2-css-search)
(require 'emmet2-extract)

(defun emmet2-css--split (text separators)
  "Split TEXT only at top-level SEPARATORS, retaining quoted and paired content."
  (let ((i 0) (start 0) stack quote escaped parts)
    (while (< i (length text))
      (let ((ch (aref text i)))
        (cond
         (escaped (setq escaped nil))
         ((eq ch ?\\) (setq escaped t))
         (quote (when (= ch quote) (setq quote nil)))
         ((memq ch '(?\" ?\')) (setq quote ch))
         ((memq ch '(?\( ?\[ ?\{)) (push ch stack))
         ((memq ch '(?\) ?\] ?\}))
          (unless (eq (pop stack) (cdr (assq ch '((?\) . ?\() (?\] . ?\[) (?\} . ?\{)))))
            (signal 'emmet2-parse-error (list "Mismatched delimiter" i))))
         ((and (null stack) (memq ch separators))
          (push (substring text start i) parts)
          (setq start (1+ i)))))
      (cl-incf i))
    (when (or stack quote escaped)
      (signal 'emmet2-parse-error (list "Unclosed CSS expression" i)))
    (nreverse (cons (substring text start) parts))))

(cl-defstruct (emmet2-css--property (:constructor emmet2-css--property))
  "A property reading holds NAME, value SOURCE and the IMPORTANT flag.
LITERAL is non-nil when SOURCE is a search keyword kept verbatim."
  name source literal important)

(defun emmet2-css--choice (choice suffix)
  "Return a property reading of search CHOICE with value SUFFIX.
CHOICE is (PROPERTY . KEYWORD).  A KEYWORD becomes the verbatim value in
place of SUFFIX; a trailing ! in SUFFIX marks the reading important."
  (emmet2-css--property :name (car choice)
                       :source (or (cdr choice) (string-remove-suffix "!" suffix))
                       :literal (and (cdr choice) t)
                       :important (string-suffix-p "!" suffix)))

(defun emmet2-css--all-properties (property)
  "Copy PROPERTY's reading to top, right, bottom and left, the all alias."
  (mapcar (lambda (name)
            (let ((copy (copy-emmet2-css--property property)))
              (setf (emmet2-css--property-name copy) name)
              copy))
          '("top" "right" "bottom" "left")))

(defun emmet2-css--all-keyword-p (suffix)
  "Whether SUFFIX gives the real all property one of its CSS-wide keywords.
Such values, as in allu or all[unset], are not the four-side alias."
  (let ((value (if (string-match "\\`\\[\\(.*\\)\\]\\'" suffix) (match-string 1 suffix)
                 (string-remove-prefix "-" suffix))))
    (and (string-match-p "\\`[a-zA-Z][-a-zA-Z]*\\'" value)
         (emmet2-css-search-values "all" value 1)
         t)))

(defun emmet2-css--aliases (token)
  "Return TOKEN's alias property readings, or nil when it has no alias.
Aliases are posa and posf, the four-side all, fwN for font-weight and wf or
hf, optionally after ma or mi, for 100%."
  (let ((case-fold-search nil))
    (cond
     ((string-match "\\`pos\\([af]\\)\\(.*\\)\\'" token)
      (let ((value (if (equal (match-string 1 token) "a") "absolute" "fixed"))
            (suffix (match-string 2 token)))
        ;; A trailing ! marks both declarations, as with the four-side all alias.
        (list (emmet2-css--choice (cons "position" value) (if (string-suffix-p "!" suffix) "!" ""))
              (emmet2-css--choice '("z-index") suffix))))
     ((and (string-prefix-p "all" token)
           (not (emmet2-css--all-keyword-p (string-remove-suffix "!" (substring token 3)))))
      (emmet2-css--all-properties (emmet2-css--choice '("all") (substring token 3))))
     ((string-match "\\`fw\\([0-9]\\)\\(!?\\)\\'" token)
      (list (emmet2-css--choice '("font-weight") (concat (match-string 1 token) "00" (match-string 2 token)))))
     ((string-match "\\`\\(ma\\|mi\\)?\\([wh]\\)f\\(!?\\)\\'" token)
      (let ((name (concat (pcase (match-string 1 token) ("ma" "max-") ("mi" "min-") (_ ""))
                          (if (equal (match-string 2 token) "w") "width" "height")))
            (suffix (concat "100p" (match-string 3 token))))
        (list (emmet2-css--choice (list name) suffix)))))))

(defun emmet2-css--split-property (body)
  "Return (NAME SUFFIX CANONICAL) for BODY's leading property, or nil.
CANONICAL means NAME is a complete property directly followed by its value.
Otherwise NAME is the leading letters; single letters such as d abbreviate
common properties even when a property shares their spelling."
  (let* ((case-fold-search nil)
         (canonical (emmet2-engine-stylesheet-property-end body))
         (canonical (and canonical (> canonical 1) canonical))
         (end (or canonical (and (string-match "\\`-?[a-zA-Z]+" body) (match-end 0)))))
    (when end (list (substring body 0 end) (substring body end) (and canonical t)))))

(defun emmet2-css--choice-token (property)
  "Return PROPERTY as a choice string that `emmet2-extensions-css' expands."
  (let ((name (emmet2-css--property-name property))
        (source (emmet2-css--property-source property))
        (case-fold-search nil))
    (concat name
            ;; A space keeps margin-top + -a from reading back as the name margin-top-a.
            (when (and (not (emmet2-css--property-literal property))
                       (string-search "-" name) (string-match-p "\\`\\(?:-[a-zA-Z]\\|[A-Z]\\)" source))
              " ")
            (if (emmet2-css--property-literal property) (concat "[" source "]") source)
            (if (emmet2-css--property-important property) "!" ""))))

(defun emmet2-css--resolve-property (token limit &optional at-rule)
  "Return up to LIMIT resolved property readings of TOKEN, best first.
Keep a complete property name first, including obsolete properties omitted
from ranked search.  A keyword found by compact search, as center in tac,
becomes a verbatim value.  Leading hyphenated words may continue a name, as
in inset-b10, or be keyword values, as in t-a; the reading whose values the
best property accepts comes first.  AT-RULE admits its descriptors.  Return
nil when no reading matches, including when the searched properties accept
none of the hyphenated words, as in ff-inter."
  (pcase-let* ((case-fold-search nil)
               (important (if (string-suffix-p "!" token) "!" ""))
               (`(,name ,suffix ,canonical) (emmet2-css--split-property (string-remove-suffix "!" token)))
               (exact (and canonical (emmet2-css-search-property-p name at-rule)))
               (authored (and name (emmet2-css--choice (list name) (concat suffix important))))
               (words (and suffix (string-match "\\`\\(?:-[a-z]+\\)*\\(?:-\\'\\)?" suffix)
                           (match-string 0 suffix)))
               (choices
                (cond
                 ((null name) nil)
                 ((and exact (= limit 1)) (list authored))
                 ((string-empty-p suffix)
                  (let* ((choices (emmet2-css-search name limit nil at-rule)) (best (car choices))
                         ;; A bare best property sharing the query's initial adds its keywords, up to half the list.
                         (keywords (and (> limit 1) best (null (cdr best))
                                        (eq (downcase (aref name 0)) (aref (car best) 0))
                                        (seq-take (emmet2-css-search-keywords (car best) at-rule) (/ limit 2)))))
                    (seq-take (mapcar (lambda (choice) (emmet2-css--choice choice important))
                                      (append (and best (list best))
                                              (mapcar (lambda (keyword) (cons (car best) keyword)) keywords)
                                              (cdr choices)))
                              limit)))
                 ((string-empty-p words)
                  (mapcar (lambda (choice) (emmet2-css--choice choice (concat suffix important)))
                          (emmet2-css-search name limit t at-rule)))
                 (t
                  ;; t-a is top: auto, while inset-b10 is inset-block: 10px.
                  (let* ((parts (split-string words "-" t))
                         ;; Rank enough properties that the first reading matches the first choice.
                         (properties (emmet2-css-search name (max limit 10) t at-rule))
                         (valid (lambda (choice)
                                  (cl-every (lambda (part) (emmet2-css-search-values (car choice) part 1 at-rule)) parts)))
                         (reading (lambda (choice) (emmet2-css--choice choice (concat suffix important))))
                         (top-valid (and properties (funcall valid (car properties)))))
                    ;; A valid best property comes first, so one reading needs no other checks.
                    (if (and top-valid (= limit 1)) (list (funcall reading (car properties)))
                      (let ((values (mapcar reading (cl-remove-if-not valid properties)))
                            (names (mapcar (lambda (choice)
                                             (emmet2-css--choice
                                              choice (concat (substring suffix (length words)) important)))
                                           (emmet2-css-search (concat name words) limit t at-rule))))
                        (seq-take (delete-dups (if top-valid (append values names) (append names values)))
                                  limit))))))))
    (if exact (seq-take (cons authored (delete authored choices)) limit) choices)))

(defun emmet2-css--declarations (property at-rule scale)
  "Return a one-element list with PROPERTY's declaration resolved in AT-RULE.
SCALE is an alist of (NAME . FUNCTION) for parenthesized values; t names the
function of every other property.  Signal `emmet2-parse-error' for a value
word or unit outside the CSS data."
  (let* ((case-fold-search nil)
         (name (emmet2-css--property-name property))
         (suffix (emmet2-css--property-source property))
         (value (and (emmet2-css--property-literal property) suffix)))
    (cond
     (value)
     ((and (string-prefix-p "[" suffix) (string-suffix-p "]" suffix))
      (setq value (substring suffix 1 -1)))
     ((string-match-p "\\`--[a-zA-Z0-9_-]+\\'" suffix)
      (setq value (mapconcat (lambda (part) (concat "var(--" part ")"))
                             (split-string suffix "--" t) " ")))
     ((and scale (string-match-p "\\`\\(?:(-?\\(?:[0-9]+\\(?:\\.[0-9]*\\)?\\|\\.[0-9]+\\))\\)+\\'" suffix))
      (when-let* ((function (cdr (or (assoc name scale) (assq t scale)))))
        (setq value (mapconcat (lambda (arg)
                                 ;; Step 0 is a bare zero length, except for font-size, where it is the base size.
                                 (if (and (equal arg "0") (not (equal name "font-size"))) "0"
                                   (concat function "(" arg ")")))
                               (split-string suffix "[()]" t) " ")))))
    (when (string-match "\\`[A-Z]" suffix)
      (setq suffix (concat (downcase (substring suffix 0 1)) (substring suffix 1))))
    (list (emmet2-engine-stylesheet-declaration
           name (or value suffix) :literal (and value t)
           :important (emmet2-css--property-important property) :at-rule at-rule))))

(defun emmet2-css--map-chars (result transform)
  "Apply TRANSFORM to each character of RESULT, remapping all field boundaries."
  (let* ((text (plist-get result :text)) (map (make-vector (1+ (length text)) 0))
         (offset 0) chunks)
    (dotimes (i (length text))
      (let ((chunk (funcall transform (aref text i))))
        (push chunk chunks)
        (cl-incf offset (length chunk))
        (aset map (1+ i) offset)))
    (setq text (apply #'concat (nreverse chunks)))
    (emmet2-result-create
     text (mapcar (lambda (field)
                    (pcase-let ((`(,beg ,end ,index ,_) field))
                      (list (aref map beg) (aref map end) index
                            (substring text (aref map beg) (aref map end)))))
                  (plist-get result :fields)))))

(defun emmet2-css--bare-name (name)
  "Remove the : or @ prefix of pseudo or at-rule NAME for fuzzy scoring."
  (string-trim-left name "[:@]+"))

(defvar emmet2-css--pseudos nil
  "Standard pseudo-class and pseudo-element names, or nil until first needed.")

(defun emmet2-css--pseudos ()
  "Return the standard pseudo-class and pseudo-element names."
  (with-memoization emmet2-css--pseudos (emmet2-css-search-pseudos)))

(defun emmet2-css--rank (abbreviation names alias-key)
  "Return NAMES ranked for ABBREVIATION, with its authored alias first.
ALIAS-KEY names the alias table in `emmet2-css-search-override'.  Candidates
share the query's initial, so an unknown CSS @us cannot become
@counter-style, and a :: query admits only pseudo-elements.  The first name
is what expansion chooses."
  (let* ((alias (gethash abbreviation (emmet2-css-search-override alias-key)))
         (elements-only (and (equal alias-key "pseudoAliases") (string-prefix-p "::" abbreviation)))
         (query (emmet2-css--bare-name abbreviation))
         (ranked (and (not (string-empty-p query))
                      (emmet2-fuzzy-filter
                       query (cl-remove-if-not (lambda (name)
                                                 (and (or (not elements-only) (string-prefix-p "::" name))
                                                      (string-prefix-p (substring query 0 1)
                                                                       (emmet2-css--bare-name name) t)))
                                               names)
                       #'emmet2-css--bare-name))))
    (if (member alias names) (cons alias (delete alias ranked)) ranked)))

(defun emmet2-css--resolve (abbreviation names alias-key)
  "Return ABBREVIATION's best NAMES entry, ranked with ALIAS-KEY.
Signal `emmet2-parse-error' when no name matches."
  (or (car (emmet2-css--rank abbreviation names alias-key))
      (signal 'emmet2-parse-error (list (format "Unknown CSS name: %s" abbreviation) 0))))

(defun emmet2-css--render-template (result indent base-indent)
  "Render authored template RESULT with INDENT and BASE-INDENT."
  (emmet2-css--map-chars
   result (lambda (ch) (cond ((= ch ?\t) indent) ((= ch ?\n) (concat "\n" base-indent))
                             (t (char-to-string ch))))))

(defun emmet2-css--at-rule-names (syntax)
  "Return CSS at-rule names, plus Sass templates unless SYNTAX is `css'."
  (sort (delete-dups (append (emmet2-css-search-at-rules)
                             (unless (eq syntax 'css)
                               (hash-table-keys (emmet2-css-search-override "atRuleTemplates")))))
        #'string<))

(defun emmet2-css--at-rule (abbreviation syntax indent base-indent)
  "Expand at-rule ABBREVIATION for host SYNTAX with INDENT and BASE-INDENT.
Plain `css' resolves among CSS at-rules only; otherwise the authored Sass
templates also apply.  Signal `emmet2-parse-error' for an unknown at-rule."
  (let* ((names (emmet2-css--at-rule-names syntax))
         (name (emmet2-css--resolve abbreviation names "atRuleAliases"))
         (template (and (not (eq syntax 'css))
                        (gethash name (emmet2-css-search-override "atRuleTemplates")))))
    (if template
        (let ((cursor (gethash "cursor" template)))
          (emmet2-css--render-template
           (emmet2-result-create (gethash "text" template) (list (list cursor cursor 1 "")))
           indent base-indent))
      (emmet2-result-create (concat name " ")))))

(defun emmet2-css--pseudo-function (name arguments)
  "Wrap canonical ARGUMENTS in pseudo-function NAME, keeping empty slots editable."
  (let ((pieces (list (emmet2-result-create (concat name "(")))))
    (dolist (argument arguments)
      (when (cdr pieces) (push (emmet2-result-create ", ") pieces))
      (push (if (string-empty-p (plist-get argument :text))
                (emmet2-result-create "" '((0 0 1 "")))
              argument)
            pieces))
    (push (emmet2-result-create ")") pieces)
    (apply #'emmet2-result-concat (nreverse pieces))))

(defun emmet2-css--pseudo-name (name names query)
  "Resolve pseudo NAME among NAMES.
When QUERY is non-nil, NAME is the final pseudo and must match, or signal
`emmet2-parse-error'.  Otherwise an unmatched NAME, such as :global in
:global(.a):hv, keeps its spelling."
  (if query (emmet2-css--resolve name names "pseudoAliases")
    (or (car (emmet2-css--rank name names "pseudoAliases")) name)))

(defun emmet2-css--pseudo-chain (text &optional final)
  "Expand TEXT into a canonical result, including nested pseudo arguments.
FINAL makes the last pseudo the query, which must be a known name."
  (let ((pos 0) pieces)
    (while (< pos (length text))
      (unless (and (string-match "::?[-a-zA-Z0-9]+" text pos) (= (match-beginning 0) pos))
        (signal 'emmet2-parse-error (list "Expected a pseudo selector" pos)))
      (let ((name (match-string 0 text)) (end (match-end 0)))
        (setq pos end)
        (if (and (< pos (length text)) (= (aref text pos) ?\())
            (let ((start (1+ pos)) (depth 1) quote escaped)
              (cl-incf pos)
              (while (and (> depth 0) (< pos (length text)))
                (let ((ch (aref text pos)))
                  (cond (escaped (setq escaped nil)) ((= ch ?\\) (setq escaped t))
                        (quote (when (= ch quote) (setq quote nil)))
                        ((memq ch '(?\' ?\")) (setq quote ch))
                        ((= ch ?\() (cl-incf depth)) ((= ch ?\)) (cl-decf depth))))
                (cl-incf pos))
              (unless (zerop depth) (signal 'emmet2-parse-error (list "Unclosed pseudo function" start)))
              (setq name (emmet2-css--pseudo-name name (emmet2-css-search-override "pseudoFunctions")
                                                  (and final (= pos (length text)))))
              (let ((arguments
                     (mapcar (lambda (argument)
                               (setq argument (string-trim argument))
                               (if (string-prefix-p ":" argument)
                                   (emmet2-css--pseudo-chain argument)
                                 (emmet2-result-create
                                  (if (string-match "\\`[+>~]" argument)
                                      (concat (substring argument 0 1) " "
                                              (string-trim-left (substring argument 1)))
                                    argument))))
                             (emmet2-css--split (substring text start (1- pos)) '(?,)))))
                ;; Only :not spreads its list into chained calls: same elements, more specificity.
                (if (equal name ":not")
                    (dolist (argument arguments)
                      (push (emmet2-css--pseudo-function name (list argument)) pieces))
                  (push (emmet2-css--pseudo-function name arguments) pieces))))
          (setq name (emmet2-css--pseudo-name name (emmet2-css--pseudos) (and final (= pos (length text)))))
          (push (if (and (member name (emmet2-css-search-override "pseudoFunctions"))
                         (not (member name (emmet2-css-search-override "pseudoOptionalFunctions"))))
                    (emmet2-css--pseudo-function name (list (emmet2-result-create "")))
                  (emmet2-result-create name))
                pieces))))
    (apply #'emmet2-result-concat (nreverse pieces))))

(defun emmet2-css--selector (abbreviation)
  "Expand pseudo names and arguments in ABBREVIATION.
Keep an authored selector prefix; a prefix of exactly _ stands for none, as
in _:hv.  Leave point after the name, or inside an empty argument."
  (let* ((colon (emmet2-extract-css-pseudo abbreviation))
         (prefix (substring abbreviation 0 colon)))
    (emmet2-result-concat
     (emmet2-result-create (if (equal prefix "_") "" prefix))
     (emmet2-css--pseudo-chain (substring abbreviation colon) t))))

(defun emmet2-extensions-css-kind (abbreviation &optional css-in-js)
  "Return ABBREVIATION's expansion kind: properties, selector or at-rule.
CSS-IN-JS supports only object properties.  This classifies expansion syntax,
not the source buffer's host context."
  (cond (css-in-js 'properties)
        ((string-prefix-p "@" abbreviation) 'at-rule)
        ((emmet2-extract-css-pseudo abbreviation) 'selector)
        (t 'properties)))

(defun emmet2-css--selector-choices (abbreviation limit)
  "Return up to LIMIT variants of ABBREVIATION with ranked final pseudos, or nil."
  (when (string-match "::?[-a-zA-Z0-9]+\\'" abbreviation)
    (let ((head (substring abbreviation 0 (match-beginning 0))) (pseudo (match-string 0 abbreviation)))
      (mapcar (lambda (name) (concat head name))
              (seq-take (emmet2-css--rank pseudo (emmet2-css--pseudos) "pseudoAliases") limit)))))

(defun emmet2-css--property-choices (abbreviation limit at-rule)
  "Return up to LIMIT ranked programs for ABBREVIATION.
A program is a list of property readings that expand together.  AT-RULE
selects descriptor names and values.  An alias program, such as posa, holds
all of its readings; a search program holds one."
  (let ((alias (emmet2-css--aliases abbreviation))
        (choices (mapcar #'list (emmet2-css--resolve-property abbreviation limit at-rule))))
    (when alias
      ;; A reading spelled like its alias, such as bare all, could not expand as itself.
      (setq choices (cl-remove-if (lambda (program) (equal (emmet2-css--program-token program) abbreviation))
                                  choices)))
    (seq-take (delete-dups (if alias (cons alias choices) choices)) limit)))

(defun emmet2-css--program-token (properties)
  "Return PROPERTIES as one choice string, also used as a completion cache key."
  (mapconcat #'emmet2-css--choice-token properties "+"))

(defconst emmet2-css-choice-limit 10
  "Ranked choices offered for one CSS property, and readings expansion tries.")

(defun emmet2-css--expand-abbreviation (abbreviation css-in-js base-indent at-rule scale)
  "Expand each property of ABBREVIATION as its first ranked program that expands.
This is the reading that completion offers first.  CSS-IN-JS, BASE-INDENT,
AT-RULE and SCALE are as in `emmet2-css--expand-properties'.  Signal
`emmet2-parse-error' for an empty or unknown property, and the first
program's error when none of its programs expands."
  (let ((offset 0) results
        (separator (emmet2-result-create (emmet2-css-property-separator css-in-js base-indent))))
    (dolist (token (emmet2-css--split abbreviation '(?+ ?,)))
      (when (string-empty-p token) (signal 'emmet2-parse-error '("Empty CSS property" 0)))
      ;; The top program, an alias or the best reading, is the same at any limit;
      ;; rank the rest only when it fails.
      (let ((programs (if-let* ((alias (emmet2-css--aliases token))) (list alias)
                        (emmet2-css--property-choices token 1 at-rule)))
            (ranked nil) result failure)
        (unless programs
          (signal 'emmet2-parse-error (list (format "Unknown CSS property or value: %s" token) offset)))
        (while (and programs (not result))
          (condition-case error
              (setq result (emmet2-css--expand-properties (pop programs) css-in-js base-indent at-rule scale))
            (emmet2-parse-error
             (setq failure (or failure error))
             (unless (or programs ranked)
               (setq ranked t
                     programs (cdr (emmet2-css--property-choices token emmet2-css-choice-limit at-rule)))))))
        (unless result (signal (car failure) (cdr failure)))
        (when results (push separator results))
        (push result results))
      (cl-incf offset (1+ (length token))))
    (apply #'emmet2-result-concat (nreverse results))))

(defun emmet2-css--expand-properties (properties css-in-js base-indent at-rule scale)
  "Resolve PROPERTIES once and render their declarations.
CSS-IN-JS chooses the renderer; BASE-INDENT and AT-RULE select layout/context.
SCALE maps parenthesized values to functions, as in `emmet2-css--declarations'."
  (let (results)
    (dolist (reading properties)
      ;; A search reading named all, as from al8, follows the four-side alias.
      (dolist (property (if (and (equal (emmet2-css--property-name reading) "all")
                                 (not (emmet2-css--all-keyword-p (emmet2-css--property-source reading))))
                            (emmet2-css--all-properties reading) (list reading)))
        (dolist (declaration (emmet2-css--declarations property at-rule scale))
          (emmet2-engine--check-deadline)
          (when results
            (push (emmet2-result-create (emmet2-css-property-separator css-in-js base-indent)) results))
          (push (emmet2-engine-stylesheet-render declaration css-in-js) results))))
    (apply #'emmet2-result-concat (nreverse results))))

(cl-defun emmet2-extensions-css-choices (abbreviation &key css-in-js (syntax 'scss) (limit emmet2-css-choice-limit) at-rule
                                                      scale-functions)
  "Return up to LIMIT ranked alternatives of one CSS ABBREVIATION, or nil.
ABBREVIATION is one property, selector or at-rule.  LIMIT defaults to ten
and SYNTAX to `scss'.  The first alternative is what `emmet2-extensions-css'
expands; the others follow in rank order.  Each expands on its own with the
same CSS-IN-JS, SYNTAX, AT-RULE and SCALE-FUNCTIONS, so names, values and
units outside the CSS data offer nothing.  CSS-IN-JS allows properties only;
SYNTAX selects at-rules and, as in `emmet2-extensions-css', whether
SCALE-FUNCTIONS apply."
  (emmet2-engine-with-expansion
    (let ((case-fold-search nil) (scale (emmet2-css--scale scale-functions syntax css-in-js)))
      (cl-flet ((expandable-p (expand)
                  (condition-case nil (progn (funcall expand) t) (emmet2-parse-error nil))))
        (pcase (emmet2-extensions-css-kind abbreviation css-in-js)
          ('at-rule (seq-take (emmet2-css--rank abbreviation (emmet2-css--at-rule-names syntax)
                                                "atRuleAliases")
                              limit))
          ('selector (cl-remove-if-not (lambda (choice) (expandable-p (lambda () (emmet2-css--selector choice))))
                                       (emmet2-css--selector-choices abbreviation limit)))
          (_ (delete-dups
              (mapcar #'emmet2-css--program-token
                      (cl-remove-if-not
                       (lambda (program)
                         (expandable-p (lambda () (emmet2-css--expand-properties program css-in-js "" at-rule scale))))
                       (emmet2-css--property-choices abbreviation limit at-rule))))))))))

(defun emmet2-css--completion-input (abbreviation css-in-js declaration-start)
  "Return (WHOLE CONFIRMED INPUT) for ABBREVIATION's final active fragment.
DECLARATION-START admits a pending separator, but in CSS-IN-JS a trailing
comma ends the host's object member and is never pending.  Selectors retain
their prefix and never split as property lists."
  (let ((kind (emmet2-extensions-css-kind abbreviation css-in-js)))
    (if (not (eq kind 'properties)) (list abbreviation nil abbreviation)
      (let ((parts (condition-case nil (emmet2-css--split abbreviation '(?, ?+))
                     (emmet2-parse-error nil))))
        (when (and (eq kind 'properties) declaration-start
                   (or (string-suffix-p "+" abbreviation)
                       (and (not css-in-js) (string-suffix-p "," abbreviation)))
                   (equal (car (last parts)) "")
                   (let ((property (car (last parts 2))))
                     (and (string-match-p "\\`[a-zA-Z-]" property)
                          (eq (emmet2-extensions-css-kind property css-in-js) 'properties))))
          (setq abbreviation (substring abbreviation 0 -1) parts (butlast parts)))
        (let* ((input (if parts (car (last parts)) abbreviation))
               (length (- (length abbreviation) (length input))))
          (list abbreviation (when (> length 0) (substring abbreviation 0 (1- length))) input))))))

(cl-defun emmet2-css-completions (abbreviation &key css-in-js (syntax 'scss) (limit emmet2-css-choice-limit)
                                             (indent "\t") (base-indent "") at-rule
                                             scale-functions declaration-start previous)
  "Build complete results and explicit labels for ABBREVIATION.
CSS-IN-JS and SYNTAX, `scss' by default, select the language; INDENT and
BASE-INDENT are literal layout.  AT-RULE selects descriptors.
SCALE-FUNCTIONS is as in `emmet2-extensions-css'.  DECLARATION-START admits
a pending separator.  LIMIT, ten by default, bounds the ranked choices.
PREVIOUS may be a preceding batch only under identical context and render
settings.  Return a plist with :choices and an opaque :prefix cache; each
choice is a plist of :abbreviation, :result, :label and :query.  A property
with no matching reading yields no choices.  Signal `emmet2-parse-error'
when the confirmed text before the last separator does not expand.
Only immutable results are reused; each call gives choices fresh identities."
  (emmet2-engine-with-expansion
    (pcase-let* ((`(,whole ,confirmed ,input)
                  (emmet2-css--completion-input abbreviation css-in-js declaration-start))
                 (kind (emmet2-extensions-css-kind input css-in-js))
                 (head (substring whole 0 (- (length whole) (length input))))
                 (programs (and (eq kind 'properties)
                                (emmet2-css--property-choices input limit at-rule)))
                 (alternatives (cond
                                (programs (mapcar (lambda (program) (cons (emmet2-css--program-token program) program))
                                                  programs))
                                ;; Properties have no other source; a second search would find nothing.
                                ((eq kind 'properties) nil)
                                (t (mapcar #'list (or (emmet2-extensions-css-choices
                                                       input :css-in-js css-in-js :syntax syntax :at-rule at-rule
                                                       :limit limit)
                                                      (list input))))))
                 (cached-prefix (plist-get previous :prefix))
                 (prefix (when confirmed
                           (if (equal confirmed (car cached-prefix)) cached-prefix
                             (cons confirmed (emmet2-extensions-css
                                              confirmed :css-in-js css-in-js :syntax syntax :indent indent
                                              :base-indent base-indent :at-rule at-rule
                                              :scale-functions scale-functions)))))
                 (reuse-prefix (and confirmed (eq (emmet2-extensions-css-kind confirmed css-in-js) 'properties)
                                    (eq kind 'properties)))
                 (separator (emmet2-result-create (emmet2-css-property-separator css-in-js base-indent)))
                 (prior (make-hash-table :test #'equal)) (seen (make-hash-table :test #'equal)) (entries nil))
      (dolist (entry (plist-get previous :choices)) (puthash (plist-get entry :abbreviation) entry prior))
      (dolist (alternative alternatives)
        (let* ((name (concat head (car alternative)))
               (old (gethash name prior))
               (fragment (unless old
                           (condition-case nil
                                 (if (cdr alternative)
                                     (emmet2-css--expand-properties
                                      (cdr alternative) css-in-js base-indent at-rule
                                      (emmet2-css--scale scale-functions syntax css-in-js))
                                   (emmet2-extensions-css (car alternative) :css-in-js css-in-js :syntax syntax
                                                         :indent indent :base-indent base-indent :at-rule at-rule
                                                         :scale-functions scale-functions))
                             (emmet2-parse-error nil))))
               (result (or (plist-get old :result)
                           (and fragment
                                (if reuse-prefix (emmet2-result-concat (cdr prefix) separator fragment)
                                  (if confirmed
                                      (condition-case nil
                                          (emmet2-extensions-css name :css-in-js css-in-js :syntax syntax :indent indent
                                                                :base-indent base-indent :at-rule at-rule
                                                                :scale-functions scale-functions)
                                        (emmet2-parse-error nil))
                                    fragment))))))
          (when (and result (not (gethash result seen)))
            (puthash result t seen)
            (let* ((label (or (plist-get old :label)
                              (plist-get (if (or reuse-prefix (not confirmed)) fragment result) :text)))
                   (query (if (and confirmed (not reuse-prefix)) whole input)))
              (when (eq kind 'selector)
                (let* ((colon (emmet2-extract-css-pseudo input))
                       (prefix-length (if (equal (substring input 0 colon) "_") 0 colon)))
                  (unless old (setq label (substring label prefix-length)))
                  (setq query (substring input colon))))
              (push (list :abbreviation name :result result :label label :query query) entries)))))
      (list :choices (nreverse entries) :prefix prefix))))

(defun emmet2-css--scale (scale-functions syntax css-in-js)
  "Return SCALE-FUNCTIONS for SCSS SYNTAX outside CSS-IN-JS, otherwise nil.
These are Sass functions, meaningless in plain CSS and JavaScript."
  (and (eq syntax 'scss) (not css-in-js) scale-functions))

(defun emmet2-css-property-separator (css-in-js base-indent)
  "Return the declaration separator for CSS-IN-JS and BASE-INDENT.
Whole expansion and completion's cached prefix use the same layout."
  (if css-in-js ", " (concat "\n" base-indent)))

(cl-defun emmet2-extensions-css (abbreviation &key css-in-js (syntax 'scss) (indent "\t") (base-indent "")
                                              at-rule scale-functions)
  "Expand CSS ABBREVIATION to a canonical result.
CSS-IN-JS requests object member syntax.  SYNTAX `css' limits at-rules to
plain CSS; the default `scss' also offers Sass rules.  INDENT, a tab by
default, and BASE-INDENT, empty by default, are literal strings for
generated layout; bracketed values, as in ff[Inter], keep their text.
A selector keeps its prefix and expands only pseudo names and arguments.
AT-RULE names the enclosing rule whose descriptors are available.
SCALE-FUNCTIONS is an alist of (PROPERTY . FUNCTION), with t for every other
property, as in `emmet2-css-scale-functions'.  In SCSS outside CSS-in-JS it
writes each parenthesized group, as in p(1)(2), as a FUNCTION call.
Signal `emmet2-parse-error' for property names, final pseudo and at-rule
names, top-level value words and units outside the CSS data, and
`emmet2-backend-error' when the expansion deadline expires."
  (emmet2-engine-with-expansion
    (let ((case-fold-search nil))
      (pcase (emmet2-extensions-css-kind abbreviation css-in-js)
        ('at-rule
         (emmet2-css--at-rule abbreviation syntax indent base-indent))
        ('selector
         (emmet2-css--selector abbreviation))
        (_ (emmet2-css--expand-abbreviation abbreviation css-in-js base-indent at-rule
                                            (emmet2-css--scale scale-functions syntax css-in-js)))))))

(provide 'emmet2-css)
;;; emmet2-css.el ends here
