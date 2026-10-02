;;; emmet2-engine-stylesheet.el --- Native stylesheet expansion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Grammar and formatting derived from Emmet 2.4.11 (MIT); see data/emmet/LICENSE.

;;; Commentary:
;; Pure stylesheet pipeline shared by completion and previews.  Property names
;; arrive canonical from the extension layer; this module never guesses one.
;; Keyword values resolve among the property's own and inherited keywords.
;; Parsed declarations are the shared input of CSS and JavaScript rendering.
;; Fields are emitted with their text; no rendered declaration is parsed back.
;; Parsed input, resolved values and output belong to one expansion.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emmet2-engine)
(require 'emmet2-css-search)

(cl-defstruct (emmet2-stylesheet--node (:constructor emmet2-stylesheet--node))
  name values important clear-defaults)
(cl-defstruct (emmet2-stylesheet--output (:constructor emmet2-stylesheet--output (base-indent)))
  base-indent parts fields (offset 0) clear-defaults trim-leading escape)

(defconst emmet2-stylesheet--property-regexp
  (concat (regexp-opt (emmet2-css-search-property-names t) t)
          "\\(?:\\'\\|[^a-zA-Z-]\\|-[0-9]\\|-\\.[0-9]\\|--\\)")
  "Recognize canonical property names before parsing abbreviation operators.")

(defconst emmet2-stylesheet--unitless-properties
  '("additive-symbols" "animation-iteration-count" "aspect-ratio" "base-palette"
    "border-image-slice" "box-flex" "box-flex-group" "box-ordinal-group" "column-count"
    "counter-increment" "counter-reset" "counter-set" "fill-opacity" "flex"
    "flex-grow" "flex-shrink" "flood-opacity" "font-feature-settings" "font-size-adjust"
    "font-variation-settings" "font-weight" "grid-area" "grid-column" "grid-column-end"
    "grid-column-start" "grid-row" "grid-row-end" "grid-row-start" "hyphenate-limit-chars"
    "initial-letter" "line-clamp" "line-height" "mask-border-slice" "math-depth"
    "max-lines" "nav-index" "opacity" "order" "orphans" "override-colors" "pad" "range"
    "reading-order" "scale" "shape-image-threshold" "stop-opacity" "stroke-miterlimit"
    "stroke-opacity" "system" "text-combine-upright" "widows" "z-index" "zoom")
  "Properties whose bare numbers must not acquire a length unit.
Keep this formatting policy in the shared core.  Other number/length properties
retain their existing defaults; explicit units always take precedence.")

(defconst emmet2-stylesheet--units
  '("%" "px" "cm" "mm" "q" "in" "pc" "pt" "em" "rem" "ex" "rex" "cap" "rcap" "ch" "rch"
    "ic" "ric" "lh" "rlh" "vw" "vh" "vi" "vb" "vmin" "vmax" "svw" "svh" "svi" "svb" "svmin"
    "svmax" "lvw" "lvh" "lvi" "lvb" "lvmin" "lvmax" "dvw" "dvh" "dvi" "dvb" "dvmin" "dvmax"
    "cqw" "cqh" "cqi" "cqb" "cqmin" "cqmax" "deg" "grad" "rad" "turn" "s" "ms" "hz" "khz"
    "dpi" "dpcm" "dppx" "x" "fr")
  "CSS units a number may carry after the e, p, x and r aliases are applied.")

(defun emmet2-engine-stylesheet-property-end (text &optional start)
  "Return the end of a canonical property at START in TEXT, or nil.
START defaults to zero.  Hyphens within names stay intact; negative numbers
and double-dash variable values can follow a complete name."
  (let ((case-fold-search nil) (start (or start 0)))
    (when (and (string-match emmet2-stylesheet--property-regexp text start)
               (= (match-beginning 0) start))
      (match-end 1))))

(defun emmet2-stylesheet--tokenize (text &optional value-only)
  "Tokenize stylesheet abbreviation TEXT.
Tokens are [TYPE VALUE START END], with character offsets.  Functions have
no source span, matching the upstream parser's field-adjacency contract.
VALUE-ONLY means an initial variable is a value, not a property name."
  (let ((pos 0) (size (length text)) (depth 0) tokens)
    (cl-labels
        ((peek (&optional delta) (and (< (+ pos (or delta 0)) size) (aref text (+ pos (or delta 0)))))
         (eat (ch) (when (eq (peek) ch) (cl-incf pos) t))
         (digit (ch) (and ch (<= ?0 ch ?9)))
         (alpha (ch) (and ch (or (<= ?a ch ?z) (<= ?A ch ?Z))))
         (word (ch) (or (alpha ch) (eq ch ?_)))
         (literal (ch) (or (word ch) (memq ch '(?% ?/))))
         (keyword (ch) (or (word ch) (digit ch) (eq ch ?-)))
         (space (ch) (memq ch '(?\s ?\t ?\r ?\n #xa0)))
         (operator (ch) (memq ch '(?+ ?! ?, ?: ?-)))
         (hex (ch) (and ch (or (digit ch) (<= ?a ch ?f) (<= ?A ch ?F))))
         (fail (message at) (signal 'emmet2-parse-error (list message at)))
         (placeholder ()
           (let ((start pos) stack done)
             (while (and (< pos size) (not done))
               (cond ((eat ?\{) (push pos stack))
                     ((eq (peek) ?\}) (if stack (progn (pop stack) (cl-incf pos)) (setq done t)))
                     (t (cl-incf pos))))
             (when stack (fail "Expecting }" (car stack)))
             (substring text start pos)))
         (number ()
           (let ((start pos) digits fraction)
             (eat ?-)
             (while (digit (peek)) (setq digits t) (cl-incf pos))
             (when (eat ?.)
               (while (digit (peek)) (setq fraction t) (cl-incf pos))
               (unless (or digits fraction) (cl-decf pos)))
             (if (or digits fraction)
                 (let ((raw (substring text start pos)) (unit-start pos))
                   (unless (eat ?%) (while (word (peek)) (cl-incf pos)))
                   (vector (string-to-number raw) (substring text unit-start pos) raw))
               (setq pos start) nil)))
         (color-alpha ()
           (when (eat ?.)
             (let ((start pos))
               (while (digit (peek)) (cl-incf pos))
               (if (= start pos) 1.0 (string-to-number (concat "0." (substring text start pos))))))))
      (while (< pos size)
        (emmet2-engine--check-deadline)
        (let ((start pos) (ch (peek)) type value)
          (cond
           ((and (eq ch ?$) (eq (peek 1) ?\{))
            (cl-incf pos 2)
            (let ((begin pos) index (default ""))
              (cond ((digit (peek))
                     (while (digit (peek)) (cl-incf pos))
                     ;; JS field identifiers use IEEE doubles too: integers
                     ;; above 2^53 can denote the same mirror group.
                     (setq index (float (string-to-number (substring text begin pos))))
                     (unless (= index 1.0e+INF) (setq index (truncate index)))
                     (when (eat ?:) (setq default (placeholder))))
                    ((alpha (peek)) (setq default (placeholder))))
              (unless (eat ?\}) (fail "Expecting }" pos))
              (setq type 'field value (cons index default))))
           ((and (eq ch ?-) (eq (peek 1) ?-))
            (cl-incf pos 2)
            (while (keyword (peek)) (cl-incf pos))
            (setq type 'custom value (substring text start pos)))
           ((setq value (number)) (setq type 'number))
           ((eat ?#)
            (let ((begin pos) color alpha)
              (cond ((hex (peek))
                     (while (hex (peek)) (cl-incf pos))
                     (setq color (substring text begin pos) alpha (color-alpha)))
                    ((eat ?t) (setq color "0" alpha (or (color-alpha) 0)))
                    (t (setq alpha (color-alpha))))
              (cond
               ;; Keep authored #rgba, #rrggbbaa and other non-shorthand lengths.
               ((and color (not alpha) (not (memq (length color) '(1 2 3 6))))
                (setq type 'literal value (concat "#" (downcase color))))
               ((or color alpha (= pos size))
                (let ((rgb (pcase (length color)
                             (0 "000000") (1 (make-string 6 (aref color 0)))
                             (2 (concat color color color))
                             ((or 3 4) (concat (make-string 2 (aref color 0))
                                               (make-string 2 (aref color 1)) (make-string 2 (aref color 2))))
                             (_ (substring (concat color color) 0 6)))))
                  (setq type 'color value (vector (string-to-number (substring rgb 0 2) 16)
                                                  (string-to-number (substring rgb 2 4) 16)
                                                  (string-to-number (substring rgb 4 6) 16) (or alpha 1)))))
               (t (setq type 'literal value "#")))))
           ((memq ch '(?\" ?\'))
            (cl-incf pos)
            (let ((begin pos))
              (while (and (< pos size) (not (eq (peek) ch))) (cl-incf pos))
              (setq type 'string value (cons ch (substring text begin pos)))
              (eat ch)))
           ((memq ch '(?\( ?\)))
            (cl-incf pos)
            (setq type 'bracket value ch)
            (when (and (= depth 0) (= ch ?\())
              (let ((end 0) (begin 0))
                (while (memq (aref (or (car tokens) [nil]) 0) '(literal number))
                  (setq begin (aref (car tokens) 2))
                  (when (= end 0) (setq end (aref (car tokens) 3)))
                  (pop tokens))
                (unless (= begin end)
                  (push (vector 'literal (substring text begin end) begin end) tokens))))
            (cl-incf depth (if (= ch ?\() 1 -1))
            (when (< depth 0) (fail "Unexpected bracket" start)))
           ((operator ch) (cl-incf pos) (setq type 'operator value ch))
           ((space ch)
            (while (space (peek)) (cl-incf pos))
            (setq type 'space))
           (t
            (cond ((memq ch '(?@ ?$))
                   (cl-incf pos)
                   (while (if (and (= start 0) (not value-only)) (literal (peek)) (keyword (peek))) (cl-incf pos)))
                  ((and (= depth 0)
                        (let ((end (emmet2-engine-stylesheet-property-end text pos)))
                          (when end (setq pos end)))))
                  ((word ch)
                   (cl-incf pos)
                   (while (if (= depth 0) (literal (peek)) (keyword (peek)))
                     (cl-incf pos)))
                  (t (eat ?.) (while (literal (peek)) (cl-incf pos))))
            (when (= pos start) (fail "Unexpected character" pos))
            (setq type 'literal value (substring text start pos))))
          (push (vector type value start pos) tokens)
          ;; A dash after a unitless number/color separates positive values.
          (when (and (or (eq type 'color) (and (eq type 'number) (equal (aref value 1) "")))
                     (operator (peek)))
            (push (vector 'operator (peek) pos (1+ pos)) tokens)
            (cl-incf pos)))))
    (nreverse tokens)))

(defun emmet2-stylesheet--parse (text &optional property)
  "Parse TEXT into fresh declaration nodes.
When PROPERTY is supplied, TEXT contains only its authored value."
  (let ((tokens (emmet2-stylesheet--tokenize text property)) nodes)
    (cl-labels
        ((kind () (and tokens (aref (car tokens) 0)))
         (eat (type &optional value)
           (when (and (eq (kind) type) (or (null value) (eql (aref (car tokens) 1) value)))
             (pop tokens) t))
         (fail ()
           ;; A delimiter-only input can exhaust the token stream.  Upstream
           ;; then has no source position, so its adapter reports backend-error.
           (if tokens (signal 'emmet2-parse-error (list "Unexpected token" (aref (car tokens) 2)))
             (signal 'emmet2-backend-error '("Unexpected token"))))
         (arguments ()
           (let (args done)
             (while (and tokens (not done))
               (emmet2-engine--check-deadline)
               (cond ((eat 'bracket ?\)) (setq done t))
                     ((let ((value (fragment t))) (when value (push value args) t)))
                     ((or (eat 'space) (eat 'operator ?,)))
                     (t (fail))))
             (nreverse args)))
         (fragment (in-argument)
           (let (values done)
             (while (and tokens (not done))
               (emmet2-engine--check-deadline)
               (cond
                ((memq (kind) '(string number color literal field custom))
                 (let ((token (pop tokens)))
                   (push (if (and (eq (aref token 0) 'literal) (eat 'bracket ?\())
                             (vector 'function (cons (aref token 1) (arguments)) nil nil)
                           token) values)))
                ((or (eat 'operator ?:) (eat 'operator ?-) (and in-argument (eat 'space))))
                (t (setq done t))))
             (nreverse values))))
      (when property (while (eat 'space)))
      (while tokens
        (emmet2-engine--check-deadline)
        (let ((name property) (before tokens) values important done)
          (when (and (not property) (eq (kind) 'literal)
                     (not (and (cadr tokens) (eq (aref (cadr tokens) 0) 'bracket))))
            (setq name (aref (pop tokens) 1))
            (or (eat 'operator ?:) (eat 'operator ?-)))
          (while (and tokens (not done))
            (let (value)
              (cond ((eat 'operator ?!) (setq important t))
                    ((setq value (fragment nil)) (push value values))
                    ((eat 'operator ?,))
                    (t (setq done t)))))
          (if (or name values important)
              (push (emmet2-stylesheet--node :name name :values (nreverse values) :important important) nodes)
            (unless (eat 'operator ?+) (fail)))
          (when (eq before tokens) (fail)))))
    (nreverse nodes)))

(defun emmet2-stylesheet--frac (number &optional digits)
  "Format NUMBER with the pinned JS toFixed/trim rule and DIGITS places.
Use the exact binary significand to round ties up, not printf's ties to even.
The upstream trimming also applies to scientific notation at 1e21 and above."
  (let* ((number (float number)) (digits (or digits 4)) (absolute (abs number)))
    (cond ((= number 0) "0")
          ((= absolute 1.0e+INF) (if (< number 0) "-Infinity" "Infinity"))
          ((>= absolute 1.0e+21)
           (replace-regexp-in-string "\\.?0+\\'" "" (number-to-string number)))
          ((= number (truncate number)) (format "%.0f" number))
          (t
           (let* ((binary (frexp absolute))
                  (scale (expt 10 digits))
                  (scaled (* (truncate (* (car binary) (expt 2 53))) scale))
                  (exponent (- (cdr binary) 53))
                  (rounded (if (>= exponent 0) (ash scaled exponent)
                             (let ((denominator (ash 1 (- exponent))))
                               (/ (+ scaled (/ denominator 2)) denominator)))))
             (replace-regexp-in-string
              "\\.?0+\\'" ""
              (format (format "%%s%%d.%%0%dd" digits)
                      (if (< number 0) "-" "") (/ rounded scale) (% rounded scale))))))))

(defun emmet2-stylesheet--color (rgba)
  "Format RGBA using short hex, rgba, or transparent."
  (let ((r (aref rgba 0)) (g (aref rgba 1)) (b (aref rgba 2)) (a (aref rgba 3)))
    (cond ((and (= r 0) (= g 0) (= b 0) (= a 0)) "transparent")
          ((/= a 1) (format "rgba(%s, %s, %s, %s)" r g b (emmet2-stylesheet--frac a 8)))
          ((and (= (% r 17) 0) (= (% g 17) 0) (= (% b 17) 0)) (format "#%x%x%x" (/ r 17) (/ g 17) (/ b 17)))
          (t (format "#%02x%02x%02x" r g b)))))

(defun emmet2-stylesheet--resolve (node &optional at-rule strict)
  "Resolve call-owned NODE's keyword values and number units in place.
A literal becomes the best keyword of NODE's property that it abbreviates,
as a in top-a is auto.  AT-RULE selects descriptor values.  Unmatched
literals and units stay, unless STRICT rejects a word that is not a keyword
of the property or a unit outside `emmet2-stylesheet--units'."
  (when-let* ((name (emmet2-stylesheet--node-name node)))
    (setf (emmet2-stylesheet--node-values node)
          (mapcar (lambda (fragment)
                    (mapcar (lambda (token)
                              (or (and (eq (aref token 0) 'literal)
                                       (when-let* ((keyword (car (emmet2-css-search-values name (aref token 1) 1 at-rule))))
                                         (vector 'literal keyword nil nil)))
                                  (if (and strict (eq (aref token 0) 'literal)
                                           (string-match-p "\\`[a-zA-Z]" (aref token 1)))
                                      (signal 'emmet2-parse-error
                                              (list (format "Unknown CSS value: %s" (aref token 1))
                                                    (or (aref token 2) 0)))
                                    token)))
                            fragment))
                  (emmet2-stylesheet--node-values node)))
    (dolist (fragment (emmet2-stylesheet--node-values node))
      (dolist (token fragment)
        (when (eq (aref token 0) 'number)
          (let* ((value (aref token 1))
                 (unit (or (cdr (assoc (aref value 1) '(("e" . "em") ("p" . "%") ("x" . "ex") ("r" . "rem"))))
                           (aref value 1))))
            (when (and strict (not (equal unit "")) (not (member (downcase unit) emmet2-stylesheet--units)))
              (signal 'emmet2-parse-error (list (format "Unknown CSS unit: %s" unit) (or (aref token 2) 0))))
            (aset value 1
                  (cond ((not (equal unit "")) unit)
                        ((or (= (aref value 0) 0)
                             (member name emmet2-stylesheet--unitless-properties)) "")
                        ((string-search "." (aref value 2)) "rem") (t "px"))))))))
  node)

(defun emmet2-stylesheet--push (out text &optional lines)
  "Append TEXT to OUT, processing newlines when LINES is non-nil."
  (when lines
    (setq text (replace-regexp-in-string "\r\n\\|[\r\n]" (concat "\n" (emmet2-stylesheet--output-base-indent out)) text t t)))
  (when (emmet2-stylesheet--output-trim-leading out)
    (setq text (string-trim-left text "[ \t\r\n]+"))
    (unless (string-empty-p text) (setf (emmet2-stylesheet--output-trim-leading out) nil)))
  (when (emmet2-stylesheet--output-escape out)
    (setq text (mapconcat #'emmet2-engine-js-character text)))
  (push text (emmet2-stylesheet--output-parts out))
  (cl-incf (emmet2-stylesheet--output-offset out) (length text)))

(defun emmet2-stylesheet--emit-token (out token)
  "Format TOKEN into OUT, recording field spans before normalization."
  (emmet2-engine--check-deadline)
  (let ((value (aref token 1)))
    (pcase (aref token 0)
      ((or 'literal 'custom) (emmet2-stylesheet--push out value t))
      ('number (emmet2-stylesheet--push out (concat (emmet2-stylesheet--frac (aref value 0)) (aref value 1)) t))
      ('color (emmet2-stylesheet--push out (emmet2-stylesheet--color value)))
      ('string (emmet2-stylesheet--push out (concat (char-to-string (car value)) (cdr value) (char-to-string (car value))) t))
      ('field
       ;; A returned field must not share a string with this module's
       ;; constant empty field.
       (let ((start (emmet2-stylesheet--output-offset out)) (default (copy-sequence (cdr value))))
         (unless (emmet2-stylesheet--output-clear-defaults out)
           (emmet2-stylesheet--push out default))
         (push (list start (emmet2-stylesheet--output-offset out) (car value) default)
               (emmet2-stylesheet--output-fields out))))
      ('raw
       ;; A raw value keeps its spelling. Empty pairs are real editable fields,
       ;; emitted between chunks so escaping cannot invalidate their offsets.
       (let ((start 0) (search 0))
         (while (string-match "()\\|\"\"\\|''" value search)
           (let ((inside (1+ (match-beginning 0))) (end (match-end 0)))
             (emmet2-stylesheet--push out (substring value start inside))
             (emmet2-stylesheet--emit-token out [field (0 . "") nil nil])
             (setq start inside search end)))
         (emmet2-stylesheet--push out (substring value start))))
      ('function
       (emmet2-stylesheet--push out (concat (car value) "("))
       (let ((first t))
         (dolist (argument (cdr value))
           (unless first (emmet2-stylesheet--push out ", "))
           (setq first nil)
           (emmet2-stylesheet--emit-value out argument)))
       (emmet2-stylesheet--push out ")")))))

(defun emmet2-stylesheet--emit-value (out fragment)
  "Format property or argument FRAGMENT into OUT, preserving adjacent fields."
  (let ((first t) (previous-end -1))
    (dolist (token fragment)
      (unless (or first (and (eq (aref token 0) 'field) (eql (aref token 2) previous-end)))
        (emmet2-stylesheet--push out " "))
      (emmet2-stylesheet--emit-token out token)
      (setq first nil previous-end (aref token 3)))))

(defun emmet2-stylesheet--finish (out)
  "Normalize OUT's field identities and return its canonical result."
  (let* ((text (apply #'concat (nreverse (emmet2-stylesheet--output-parts out))))
         (fields (nreverse (emmet2-stylesheet--output-fields out)))
           (sorted (cl-stable-sort (copy-sequence fields)
                                   (lambda (a b) (< (if (or (null (nth 2 a)) (eq (nth 2 a) 0)) 1.0e+INF (nth 2 a))
                                                     (if (or (null (nth 2 b)) (eq (nth 2 b) 0)) 1.0e+INF (nth 2 b))))))
           (groups (make-hash-table :test #'equal)) (next 0))
      (dolist (field sorted)
        (let* ((index (nth 2 field)) (key (cons index (nth 3 field)))
               (group (and (not (eq index 0)) (gethash key groups))))
          (unless group (setq group (cl-incf next)) (puthash key group groups))
          (setcar (nthcdr 2 field) group)
          (setcar (nthcdr 3 field) (substring text (car field) (cadr field)))))
    (when (emmet2-stylesheet--output-clear-defaults out)
      (let ((merged (make-hash-table :test #'eql)) unique)
        (cl-labels ((group (index)
                      (while (gethash index merged) (setq index (gethash index merged)))
                      index))
          (dolist (field fields)
            (if (and unique (= (caar unique) (car field)))
                (let ((a (group (nth 2 (car unique)))) (b (group (nth 2 field))))
                  (unless (= a b) (puthash (max a b) (min a b) merged)))
              (push field unique)))
          (dolist (field unique) (setcar (nthcdr 2 field) (group (nth 2 field)))))
        (setq fields (nreverse unique))))
    (emmet2-result-create text fields)))

(defun emmet2-stylesheet--js-number (node)
  "Return NODE's single numeric JavaScript value, or nil for a string value."
  (let* ((values (emmet2-stylesheet--node-values node))
         (token (and (= (length values) 1) (= (length (car values)) 1) (caar values)))
         (raw (pcase (and token (aref token 0))
                ('number (let ((value (aref token 1)))
                           (concat (emmet2-stylesheet--frac (aref value 0)) (aref value 1))))
                ('raw (aref token 1)))))
    ;; Raw leading-zero spellings must remain strings, avoiding JS octal.
    (when (and raw (not (emmet2-stylesheet--node-important node))
               (string-match-p "\\`-?\\(?:0\\|[1-9][0-9]*\\)\\(?:\\.[0-9]*\\)?\\(?:px\\)?\\'" raw))
      (string-remove-suffix "px" raw))))

(defun emmet2-stylesheet--value-text-p (node)
  "Whether NODE emits nonempty value text, ignoring its property name."
  (let ((values (emmet2-stylesheet--node-values node)))
    (or (emmet2-stylesheet--node-important node) (> (length values) 1)
        (cl-some (lambda (token)
                   (pcase (aref token 0)
                     ('field (and (not (emmet2-stylesheet--node-clear-defaults node))
                                  (not (string-empty-p (cdr (aref token 1))))))
                     ((or 'raw 'literal 'custom) (not (string-empty-p (aref token 1))))
                     (_ t)))
                 (car values)))))

(defun emmet2-stylesheet--format (node base-indent &optional css-in-js)
  "Render resolved NODE with BASE-INDENT, optionally as CSS-IN-JS.
Generate text and field offsets together, with independent group scope."
  (let* ((case-fold-search nil)
         (out (emmet2-stylesheet--output base-indent))
         (name (emmet2-stylesheet--node-name node))
         (values (emmet2-stylesheet--node-values node))
         (number (and css-in-js (emmet2-stylesheet--js-number node)))
         (quoted (and css-in-js (not number) (emmet2-stylesheet--value-text-p node))))
    (when css-in-js
      (unless name (signal 'emmet2-parse-error '("Expected a declaration for CSS-in-JS" 0)))
      (unless (string-prefix-p "--" name)
        (setq name (replace-regexp-in-string "-[a-z]" (lambda (part) (upcase (substring part 1))) name t t))
        (when (string-prefix-p "Ms" name) (setq name (concat "ms" (substring name 2)))))
      (unless (string-match-p "\\`[a-zA-Z_$][a-zA-Z0-9_$]*\\'" name)
        (setq name (concat "\"" (mapconcat #'emmet2-engine-js-character name) "\""))))
    (when name (emmet2-stylesheet--push out (concat name ": ") t))
    (when quoted (emmet2-stylesheet--push out "\""))
    (setf (emmet2-stylesheet--output-clear-defaults out) (emmet2-stylesheet--node-clear-defaults node)
          (emmet2-stylesheet--output-trim-leading out) (and name (emmet2-stylesheet--node-clear-defaults node))
          (emmet2-stylesheet--output-escape out) quoted)
    (cond
     (number (emmet2-stylesheet--push out number))
     (name
      (if values
          (let ((first t))
            (dolist (fragment values)
              (unless first (emmet2-stylesheet--push out ", "))
              (setq first nil)
              (emmet2-stylesheet--emit-value out fragment)))
        (emmet2-stylesheet--emit-token out [field (0 . "") nil nil])))
     (t (dolist (fragment values)
          (dolist (token fragment) (emmet2-stylesheet--emit-token out token)))))
    (when (emmet2-stylesheet--node-important node)
      (emmet2-stylesheet--push out (if (or name values) " !important" "!important")))
    (setf (emmet2-stylesheet--output-escape out) nil)
    (when quoted (emmet2-stylesheet--push out "\""))
    (when (and name (not css-in-js)) (emmet2-stylesheet--push out ";"))
    (emmet2-stylesheet--finish out)))

(cl-defun emmet2-engine-stylesheet-declaration (name source &key literal important at-rule)
  "Create a resolved declaration of NAME from authored value SOURCE.
LITERAL preserves SOURCE, including empty-pair fields; otherwise parse value
syntax and omit field defaults.  IMPORTANT and AT-RULE carry source context.
The returned declaration is call-owned and is opaque to the caller."
  (unless (and (stringp name) (string-match-p "\\`[-a-zA-Z_$][-a-zA-Z0-9_$]*\\'" name)
               (stringp source))
    (signal 'emmet2-parse-error '("Expected a CSS property and value" 0)))
  (let* ((nodes (unless literal (emmet2-stylesheet--parse source name)))
         (node (or (car nodes) (emmet2-stylesheet--node :name name))))
    (when (cdr nodes) (signal 'emmet2-parse-error '("Expected one CSS value" 0)))
    (if literal
        (setf (emmet2-stylesheet--node-values node) (list (list (vector 'raw source nil nil))))
      (setf (emmet2-stylesheet--node-clear-defaults node) t)
      (emmet2-stylesheet--resolve node at-rule t))
    (when important (setf (emmet2-stylesheet--node-important node) t))
    node))

(defun emmet2-engine-stylesheet-render (declaration &optional css-in-js base-indent)
  "Render resolved DECLARATION as CSS or CSS-IN-JS, using BASE-INDENT."
  (emmet2-stylesheet--format declaration (or base-indent "") css-in-js))

(defun emmet2-engine-stylesheet-parse (abbreviation &optional at-rule clear-defaults)
  "Resolve canonical ABBREVIATION into call-owned declarations.
AT-RULE selects descriptor values.  CLEAR-DEFAULTS omits field defaults during
rendering, while retaining field groups and source adjacency."
  (mapcar (lambda (node)
            (setf (emmet2-stylesheet--node-clear-defaults node) clear-defaults)
            (emmet2-stylesheet--resolve node at-rule))
          (emmet2-stylesheet--parse abbreviation)))

(cl-defun emmet2-engine-stylesheet-expand (abbreviation &key (preset 'stylesheet) (indent "\t") (base-indent "") at-rule)
  "Expand stylesheet ABBREVIATION, whose property names are canonical.
Other names stay literal.  PRESET must be stylesheet.  INDENT and BASE-INDENT
follow the common engine contract; declarations need no nested indentation.
AT-RULE selects the enclosing rule's descriptor values."
  (unless (and (stringp abbreviation) (eq preset 'stylesheet) (stringp indent) (stringp base-indent))
    (signal 'emmet2-error '("Invalid stylesheet abbreviation, preset or indentation")))
  (emmet2-engine-with-expansion
    (let ((nodes (emmet2-engine-stylesheet-parse abbreviation at-rule)) results (first t))
      (dolist (node nodes)
        (emmet2-engine--check-deadline)
        (unless first (push (emmet2-result-create (concat "\n" base-indent)) results))
        (setq first nil)
        (push (emmet2-engine-stylesheet-render node nil base-indent) results))
      (apply #'emmet2-result-concat (nreverse results)))))

(provide 'emmet2-engine-stylesheet)
;;; emmet2-engine-stylesheet.el ends here
