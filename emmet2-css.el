;;; emmet2-css.el --- CSS rules and output projections -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Own CSS abbreviation choices, aliases, explicit values, selectors and
;; at-rules.  CSS-in-JS is an output projection of the same declaration result.
;; It neither reads nor writes editor state.  One deadline covers all core calls.

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
  name source literal important)

(defun emmet2-css--choice (choice suffix)
  "Keep search CHOICE's property identity and value SUFFIX separate."
  (emmet2-css--property :name (car choice)
                       :source (or (cdr choice) (string-remove-suffix "!" suffix))
                       :literal (and (cdr choice) t)
                       :important (string-suffix-p "!" suffix)))

(defun emmet2-css--all-properties (property)
  "Apply the established four-side `all' alias to PROPERTY's value."
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
  "Return TOKEN's alias declarations, or nil when it has no alias."
  (let ((case-fold-search nil))
    (cond
     ((string-match "\\`pos\\([af]\\)\\(.*\\)\\'" token)
      (let ((value (if (equal (match-string 1 token) "a") "absolute" "fixed"))
            (suffix (match-string 2 token)))
        (list (emmet2-css--choice (cons "position" value) "")
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
  "Project PROPERTY for the public string-choice API.
The expansion and completion pipelines never parse this projection."
  (let ((name (emmet2-css--property-name property))
        (source (emmet2-css--property-source property))
        (case-fold-search nil))
    (concat name
            ;; A generated alternative must not turn margin-top + -a back
            ;; into an ambiguous property query. The delimiter is syntax only.
            (when (and (not (emmet2-css--property-literal property))
                       (string-search "-" name) (string-match-p "\\`\\(?:-[a-zA-Z]\\|[A-Z]\\)" source))
              " ")
            (if (emmet2-css--property-literal property) (concat "[" source "]") source)
            (if (emmet2-css--property-important property) "!" ""))))

(defun emmet2-css--resolve-property (token limit &optional at-rule)
  "Return up to LIMIT resolved property readings of TOKEN, best first.
Keep a complete canonical name first, including obsolete properties omitted
from fuzzy search.  A compact keyword becomes a bracket value.  Leading
hyphenated words may continue a name, as in inset-b10, or be keyword values,
as in t-a; the reading whose values the best property accepts comes first.
AT-RULE admits its descriptors.  Return nil when no property matches."
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
                         ;; A best bare property the query begins also offers up to half
                         ;; the list as its own keywords, before the other properties.
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
                         (properties (emmet2-css-search name limit t at-rule))
                         (valid (lambda (choice)
                                  (cl-every (lambda (part) (emmet2-css-search-values (car choice) part 1 at-rule)) parts)))
                         (readings (lambda (choices)
                                     (mapcar (lambda (choice) (emmet2-css--choice choice (concat suffix important)))
                                             choices)))
                         (values (funcall readings (cl-remove-if-not valid properties)))
                         (names (mapcar (lambda (choice)
                                          (emmet2-css--choice
                                           choice (concat (substring suffix (length words)) important)))
                                        (emmet2-css-search (concat name words) limit t at-rule))))
                    (seq-take (or (delete-dups (if (and properties (funcall valid (car properties)))
                                                   (append values names)
                                                 (append names values)))
                                  ;; An authored value such as ff-inter need not be a keyword.
                                  (funcall readings properties))
                              limit))))))
    (if exact (seq-take (cons authored (delete authored choices)) limit) choices)))

(defun emmet2-css--declarations (property at-rule scale)
  "Parse PROPERTY's value once and resolve its declarations in AT-RULE.
SCALE is an alist of (PROPERTY . FUNCTION) for parenthesized values; t
names the function of every other property."
  (let* ((case-fold-search nil)
         (name (emmet2-css--property-name property))
         (resolved name)
         (source (emmet2-css--property-source property))
         (suffix source)
         (important (emmet2-css--property-important property))
         (value (and (emmet2-css--property-literal property) suffix)))
    (unless resolved
      (let ((split (emmet2-css--split-property (string-remove-suffix "!" source))))
        (setq name (car split) suffix (or (cadr split) "")
              important (string-suffix-p "!" source))))
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
                                 ;; A zero length needs no function, but scale step 0
                                 ;; of font-size is the base size.
                                 (if (and (equal arg "0") (not (equal name "font-size"))) "0"
                                   (concat function "(" arg ")")))
                               (split-string suffix "[()]" t) " ")))))
    (if (or resolved value)
        (progn
          ;; Literal fallback names retain the canonical parser's grammar.
          ;; Search-resolved names already have an authoritative identity.
          (unless resolved (emmet2-engine-stylesheet-property-prefix name))
          (when (string-match "\\`[A-Z]" suffix)
            (setq suffix (concat (downcase (substring suffix 0 1)) (substring suffix 1))))
          (list (emmet2-engine-stylesheet-declaration
                 name (or value suffix) :literal (and value t)
                 :important important :at-rule at-rule)))
      ;; The canonical parser also owns the public literal-name fallback.
      (when (string-match "\\`-?[a-z]+\\([A-Z]\\)" source)
        (setq source (replace-match (concat ":" (downcase (match-string 1 source))) t t source 1)))
      (emmet2-engine-stylesheet-parse source at-rule t))))

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
  "Remove the syntactic prefix of pseudo or at-rule NAME for fuzzy scoring."
  (string-trim-left name "[:@]+"))

(defconst emmet2-css--pseudos (emmet2-css-search-pseudos))

(defun emmet2-css--rank (abbreviation names alias-key)
  "Return NAMES ranked for ABBREVIATION, with its ALIAS-KEY override first.
Candidates share the query's initial, so an unknown CSS @us cannot become
@counter-style.  The first name is what expansion chooses."
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
  "Resolve ABBREVIATION to its best NAMES entry by ALIAS-KEY, or keep it literal."
  (or (car (emmet2-css--rank abbreviation names alias-key)) abbreviation))

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
  "Expand ABBREVIATION for host SYNTAX with INDENT and BASE-INDENT.
Plain `css' resolves among CSS at-rules only; otherwise names and local Sass
templates both apply."
  (let* ((names (emmet2-css--at-rule-names syntax))
         (name (emmet2-css--resolve abbreviation names "atRuleAliases"))
         (template (and (not (eq syntax 'css))
                        (gethash name (emmet2-css-search-override "atRuleTemplates")))))
    (if template
        (let ((cursor (gethash "cursor" template)))
          (emmet2-css--render-template
           (emmet2-result-create (gethash "text" template) (list (list cursor cursor 1 "")))
           indent base-indent))
      (emmet2-result-create (concat name (if (member name names) " " ""))))))

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

(defun emmet2-css--pseudo-chain (text)
  "Expand TEXT into a canonical result, including nested pseudo arguments."
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
              (setq name (emmet2-css--resolve
                          name (emmet2-css-search-override "pseudoFunctions") "pseudoAliases"))
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
                ;; Keep legacy :not chaining; it matches the same elements but
                ;; adds specificity.  Other lists must retain their OR semantics.
                (if (equal name ":not")
                    (dolist (argument arguments)
                      (push (emmet2-css--pseudo-function name (list argument)) pieces))
                  (push (emmet2-css--pseudo-function name arguments) pieces))))
          (setq name (emmet2-css--resolve name emmet2-css--pseudos "pseudoAliases"))
          (push (if (and (member name (emmet2-css-search-override "pseudoFunctions"))
                         (not (member name (emmet2-css-search-override "pseudoOptionalFunctions"))))
                    (emmet2-css--pseudo-function name (list (emmet2-result-create "")))
                  (emmet2-result-create name))
                pieces))))
    (apply #'emmet2-result-concat (nreverse pieces))))

(defun emmet2-css--selector (abbreviation)
  "Expand pseudo names and arguments in ABBREVIATION.
Keep an authored selector prefix; a leading underscore is an omission marker.
Leave point after the name, or inside an empty argument."
  (let* ((colon (emmet2-extract-css-pseudo abbreviation))
         (prefix (substring abbreviation 0 colon)))
    (emmet2-result-concat
     (emmet2-result-create (if (equal prefix "_") "" prefix))
     (emmet2-css--pseudo-chain (substring abbreviation colon)))))

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
              (seq-take (emmet2-css--rank pseudo emmet2-css--pseudos "pseudoAliases") limit)))))

(defun emmet2-css--property-choices (abbreviation limit at-rule)
  "Return ranked property programs for ABBREVIATION, bounded by LIMIT.
AT-RULE selects descriptor names and values.  Alias programs retain all of
their declarations; ordinary search choices contain one property reading."
  (let ((alias (emmet2-css--aliases abbreviation))
        (choices (mapcar #'list (emmet2-css--resolve-property abbreviation limit at-rule))))
    (when alias
      ;; A reading spelled like its alias, such as bare all, could not expand as itself.
      (setq choices (cl-remove-if (lambda (program) (equal (emmet2-css--program-token program) abbreviation))
                                  choices)))
    (seq-take (delete-dups (if alias (cons alias choices) choices)) limit)))

(defun emmet2-css--program-token (properties)
  "Project PROPERTIES for the public string-choice API and stable cache keys."
  (mapconcat #'emmet2-css--choice-token properties "+"))

(defun emmet2-css--program (abbreviation at-rule)
  "Read ABBREVIATION's declarations under AT-RULE without re-encoding choices."
  (let (properties)
    (dolist (token (emmet2-css--split abbreviation '(?+ ?,)))
      (when (string-empty-p token) (signal 'emmet2-parse-error '("Empty CSS property" 0)))
      (dolist (property (or (emmet2-css--aliases token)
                            (emmet2-css--resolve-property token 1 at-rule)
                            (list (emmet2-css--property :source token))))
        (push property properties)))
    (nreverse properties)))

(defun emmet2-css--expand-properties (properties css-in-js base-indent at-rule scale)
  "Resolve PROPERTIES once and render their shared declarations.
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

(cl-defun emmet2-extensions-css-choices (abbreviation &key css-in-js (syntax 'scss) (limit 10) at-rule)
  "Return up to LIMIT ranked alternatives of one CSS ABBREVIATION, or nil.
ABBREVIATION is one property, selector or at-rule.  The first alternative is
what `emmet2-extensions-css' expands; the others follow in rank order.  Each
expands on its own with the same AT-RULE descriptor context.
CSS-IN-JS allows properties only; SYNTAX selects at-rules."
  (let ((case-fold-search nil))
    (pcase (emmet2-extensions-css-kind abbreviation css-in-js)
      ('at-rule (seq-take (emmet2-css--rank abbreviation (emmet2-css--at-rule-names syntax)
                                            "atRuleAliases")
                          limit))
      ('selector (emmet2-css--selector-choices abbreviation limit))
      (_ (delete-dups
          (mapcar #'emmet2-css--program-token (emmet2-css--property-choices abbreviation limit at-rule)))))))

(defun emmet2-css--completion-input (abbreviation css-in-js declaration-start)
  "Return (WHOLE CONFIRMED INPUT) for ABBREVIATION's final active fragment.
CSS-IN-JS commas belong to the host.  DECLARATION-START admits a pending CSS
separator.  Selectors retain their prefix and never split as property lists."
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

(cl-defun emmet2-css-completion-parts (abbreviation &key css-in-js (syntax 'scss) (limit 10)
                                                    at-rule declaration-start)
  "Return (NAMES CONFIRMED INPUT) for CSS ABBREVIATION.
NAMES holds up to LIMIT ranked full abbreviations for the final fragment,
or the abbreviation itself when no alternatives match.  CONFIRMED excludes
the last separator; INPUT is the final property, selector or at-rule.
Selectors retain their literal prefix and never enter property-list splitting.
CSS-IN-JS allows properties only; SYNTAX and AT-RULE select available names.
At DECLARATION-START, a pending property separator keeps the preceding
fragment.  A CSS-IN-JS comma belongs to the host and cannot be pending.
This pure completion projection does not relax expansion's property grammar."
  (pcase-let* ((`(,whole ,confirmed ,input)
                (emmet2-css--completion-input abbreviation css-in-js declaration-start))
               (choices (emmet2-extensions-css-choices
                         input :css-in-js css-in-js :at-rule at-rule :syntax syntax :limit limit))
               (head (substring whole 0 (- (length whole) (length input)))))
    (list (if choices (mapcar (lambda (choice) (concat head choice)) choices) (list whole))
          confirmed input)))

(cl-defun emmet2-css-completions (abbreviation &key css-in-js (syntax 'scss) (limit 10)
                                             (indent "\t") (base-indent "") at-rule
                                             scale-functions declaration-start previous)
  "Build complete results and explicit labels for ABBREVIATION.
CSS-IN-JS and SYNTAX select the language; INDENT and BASE-INDENT are literal
layout.  AT-RULE selects descriptors.  SCALE-FUNCTIONS is as in
`emmet2-extensions-css'.  DECLARATION-START admits a pending
separator.  LIMIT bounds the ranked choices.  PREVIOUS may be a preceding
batch only under identical context and render settings.  Return a plist with
:choices and an opaque :prefix cache; each choice has a result, label and query.
Only immutable results are reused; each call gives choices fresh identities."
  (emmet2-engine-with-expansion
    (pcase-let* ((`(,whole ,confirmed ,input)
                  (emmet2-css--completion-input abbreviation css-in-js declaration-start))
                 (kind (emmet2-extensions-css-kind input css-in-js))
                 (head (substring whole 0 (- (length whole) (length input))))
                 (programs (and (eq kind 'properties)
                                (emmet2-css--property-choices input limit at-rule)))
                 (alternatives (if programs (mapcar (lambda (program) (cons (emmet2-css--program-token program) program)) programs)
                                 (mapcar #'list (or (emmet2-extensions-css-choices
                                                    input :css-in-js css-in-js :syntax syntax :at-rule at-rule :limit limit)
                                                   (list input)))))
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
plain CSS; the default `scss' also offers Sass rules.  INDENT and BASE-INDENT
are literal rendering strings.  Generated layout uses them; literal raw text
is preserved.  Pseudo completion expands only selector names and arguments.
AT-RULE names the enclosing rule whose descriptors are available.
SCALE-FUNCTIONS is an alist of (PROPERTY . FUNCTION), with t for every other
property, as in `emmet2-css-scale-functions'.  In SCSS outside CSS-in-JS it
writes each parenthesized group, as in p(1)(2), as a FUNCTION call."
  (emmet2-engine-with-expansion
    (let ((case-fold-search nil))
      (pcase (emmet2-extensions-css-kind abbreviation css-in-js)
        ('at-rule
         (emmet2-css--at-rule abbreviation syntax indent base-indent))
        ('selector
         (emmet2-css--selector abbreviation))
        (_ (emmet2-css--expand-properties (emmet2-css--program abbreviation at-rule)
                                          css-in-js base-indent at-rule
                                          (emmet2-css--scale scale-functions syntax css-in-js)))))))

(provide 'emmet2-css)
;;; emmet2-css.el ends here
