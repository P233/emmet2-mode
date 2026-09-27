;;; emmet2-engine-stylesheet.el --- Native stylesheet expansion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Grammar and resolution derived from Emmet 2.4.11 (MIT); see data/emmet/LICENSE.

;;; Commentary:
;; Pure stylesheet pipeline shared by commands, completion and previews.
;; Packaged snippets and their lookup index are immutable after module loading.
;; Parsed input, resolved values and output belong to one expansion.  CSS
;; extension syntax and default removal remain in emmet2-extensions.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emmet2-engine)
(require 'emmet2-fuzzy)

(cl-defstruct (emmet2-stylesheet--node (:constructor emmet2-stylesheet--node))
  name values important)
(cl-defstruct (emmet2-stylesheet--snippet (:constructor emmet2-stylesheet--snippet))
  key property choices keywords dependencies raw)
(cl-defstruct (emmet2-stylesheet--output (:constructor emmet2-stylesheet--output (base-indent)))
  base-indent parts fields (offset 0))

(defun emmet2-stylesheet--tokenize (text &optional value-mode)
  "Tokenize TEXT, using long literals in VALUE-MODE.
Tokens are [TYPE VALUE START END], with character offsets.  Functions have
no source span, matching the upstream parser's field-adjacency contract."
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
              (if (or color alpha (= pos size))
                  (let ((rgb (pcase (length color)
                               (0 "000000") (1 (make-string 6 (aref color 0)))
                               (2 (concat color color color))
                               (3 (concat (make-string 2 (aref color 0))
                                          (make-string 2 (aref color 1)) (make-string 2 (aref color 2))))
                               (_ (substring (concat color color) 0 6)))))
                    (setq type 'color value (vector (string-to-number (substring rgb 0 2) 16)
                                                    (string-to-number (substring rgb 2 4) 16)
                                                    (string-to-number (substring rgb 4 6) 16) (or alpha 1))))
                (setq type 'literal value "#"))))
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
                   (while (if (= start 0) (literal (peek)) (keyword (peek))) (cl-incf pos)))
                  ((word ch)
                   (cl-incf pos)
                   (while (if (and (= depth 0) (not value-mode)) (literal (peek)) (keyword (peek)))
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

(defun emmet2-stylesheet--parse (text &optional value-mode)
  "Parse TEXT into fresh property nodes, optionally in VALUE-MODE."
  (let ((tokens (emmet2-stylesheet--tokenize text value-mode)) nodes)
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
      (while tokens
        (emmet2-engine--check-deadline)
        (let (name values important done)
          (when (and (not value-mode) (eq (kind) 'literal)
                     (not (and (cadr tokens) (eq (aref (cadr tokens) 0) 'bracket))))
            (setq name (aref (pop tokens) 1))
            (or (eat 'operator ?:) (eat 'operator ?-)))
          (when value-mode (eat 'space))
          (while (and tokens (not done))
            (let (value)
              (cond ((eat 'operator ?!) (setq important t))
                    ((setq value (fragment value-mode)) (push value values))
                    ((eat 'operator ?,))
                    (t (setq done t)))))
          (if (or name values important)
              (push (emmet2-stylesheet--node :name name :values (nreverse values) :important important) nodes)
            (unless (eat 'operator ?+) (fail))))))
    (nreverse nodes)))

(defun emmet2-stylesheet--load-snippets ()
  "Parse packaged snippets and build the immutable dependency/index table."
  (let ((case-fold-search nil) snippets stack (index (make-hash-table :test #'eql)))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name "data/emmet/css.json" (file-name-directory (or load-file-name buffer-file-name))))
      (maphash
       (lambda (names raw)
         (dolist (key (split-string names "|"))
           (let ((snippet (emmet2-stylesheet--snippet :key key)))
             (if (string-match "\\`\\([a-z-]+\\)\\(?:[ \t]*:[ \t]*\\([^\n\r;]+?\\);*\\)?\\'" raw)
                 (let ((property (match-string 1 raw)) (value (match-string 2 raw)) keywords)
                   (setf (emmet2-stylesheet--snippet-property snippet) property
                         (emmet2-stylesheet--snippet-choices snippet)
                         (when value
                           (mapcar (lambda (choice)
                                     (emmet2-stylesheet--node-values
                                      (car (emmet2-stylesheet--parse (string-trim choice) t))))
                                   (split-string value "|"))))
                   (dolist (choice (emmet2-stylesheet--snippet-choices snippet))
                     (dolist (fragment choice)
                       (dolist (token fragment)
                         (let ((name (pcase (aref token 0)
                                       ('literal (aref token 1)) ('function (car (aref token 1)))
                                       ('field (string-trim (cdr (aref token 1)))))))
                           (when (and name (not (equal name "")))
                             (let* ((entry (assoc name keywords))
                                    (value (if (eq (aref token 0) 'field) (vector 'literal name nil nil) token)))
                               (if entry (setcdr entry value) (push (cons name value) keywords))))))))
                   (setf (emmet2-stylesheet--snippet-keywords snippet) (nreverse keywords)))
               (setf (emmet2-stylesheet--snippet-raw snippet) raw))
             (push snippet snippets))))
       (json-parse-buffer)))
    (setq snippets (sort snippets (lambda (a b) (string< (emmet2-stylesheet--snippet-key a)
                                                        (emmet2-stylesheet--snippet-key b)))))
    (dolist (snippet snippets)
      (when-let* ((property (emmet2-stylesheet--snippet-property snippet)))
        (while (and stack
                    (not (string-prefix-p (concat (emmet2-stylesheet--snippet-property (car stack)) "-") property)))
          (pop stack))
        (when stack (push snippet (emmet2-stylesheet--snippet-dependencies (car stack))))
        (push snippet stack))
      (push snippet (gethash (aref (downcase (emmet2-stylesheet--snippet-key snippet)) 0) index)))
    (dolist (snippet snippets)
      (setf (emmet2-stylesheet--snippet-dependencies snippet)
            (nreverse (emmet2-stylesheet--snippet-dependencies snippet))))
    (maphash (lambda (key bucket) (puthash key (nreverse bucket) index)) index)
    index))

(defconst emmet2-stylesheet--snippets (emmet2-stylesheet--load-snippets))

(defun emmet2-stylesheet--keyword (name snippet)
  "Resolve NAME in SNIPPET, direct dependencies, then global keywords."
  (or (catch 'found
        (dolist (item (and snippet (cons snippet (emmet2-stylesheet--snippet-dependencies snippet))))
          (when-let* ((entry (emmet2-fuzzy-find name (emmet2-stylesheet--snippet-keywords item) nil nil #'car)))
            (throw 'found (copy-tree (cdr entry) t)))))
      (when-let* ((name (emmet2-fuzzy-find name '("auto" "inherit" "unset" "none"))))
        (vector 'literal name nil nil))))

(defun emmet2-stylesheet--unmatched (abbreviation key)
  "Return the suffix of ABBREVIATION not consumed in order from KEY."
  (let ((offset 0) tail)
    (catch 'done
      (dotimes (i (length abbreviation))
        (let ((next (cl-position (aref abbreviation i) key :start offset)))
          (unless next (setq tail (substring abbreviation i)) (throw 'done nil))
          (setq offset (1+ next)))))
    tail))

(defun emmet2-stylesheet--has-field-p (values)
  "Whether VALUES contain a field, including nested functions."
  (cl-some (lambda (fragment)
             (cl-some (lambda (token)
                        (or (eq (aref token 0) 'field)
                            (and (eq (aref token 0) 'function)
                                 (emmet2-stylesheet--has-field-p (cdr (aref token 1)))))) fragment)) values))

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

(defun emmet2-stylesheet--wrap (fragment &optional state)
  "Wrap a default choice FRAGMENT in fields, sharing numbering STATE."
  (let ((state (or state (list 0))) values)
    (cl-labels ((field (text) (push (vector 'field (cons (cl-incf (car state)) text) nil nil) values)))
      (dolist (token fragment)
        (let ((value (aref token 1)))
          (pcase (aref token 0)
            ('color (field (emmet2-stylesheet--color value)))
            ('literal (field value))
            ('number (field (concat (emmet2-stylesheet--frac (aref value 0)) (aref value 1))))
            ('string (field (concat (char-to-string (car value)) (cdr value) (char-to-string (car value)))))
            ('function
             (field (car value)) (push [literal "(" nil nil] values)
             (let ((first t))
               (dolist (argument (cdr value))
                 (unless first (push [literal ", " nil nil] values))
                 (setq first nil)
                 (dolist (item (emmet2-stylesheet--wrap argument state)) (push item values))))
             (push [literal ")" nil nil] values))
            (_ (push token values))))))
    (nreverse values)))

(defun emmet2-stylesheet--resolve-raw (node raw)
  "Replace NODE with RAW snippet tokens, filling fields from explicit values."
  (let ((offset 0) (input (car (emmet2-stylesheet--node-values node))) values)
    (while (string-match "\\${\\([0-9]+\\)\\(:[^}]+\\)?}" raw offset)
      (let ((beg (match-beginning 0)) (end (match-end 0))
            (index (string-to-number (match-string 1 raw))) (default (match-string 2 raw)))
        (unless (= offset beg) (push (vector 'literal (substring raw offset beg) nil nil) values))
        (push (or (pop input) (vector 'field (cons index (if default (substring default 1) "")) nil nil)) values)
        (setq offset end)))
    (when (< offset (length raw)) (push (vector 'literal (substring raw offset) nil nil) values))
    (setf (emmet2-stylesheet--node-name node) nil
          (emmet2-stylesheet--node-values node) (list (nreverse values)))))

(defun emmet2-stylesheet--resolve (node)
  "Resolve call-owned NODE against immutable snippets and value rules."
  (let* ((name (emmet2-stylesheet--node-name node))
         (values (emmet2-stylesheet--node-values node))
         (single (and (= (length values) 1) (= (length (car values)) 1) (caar values)))
         (gradient (and single (eq (aref single 0) 'function) (equal (car (aref single 1)) "lg"))))
    (cond
     ((or gradient (equal name "lg"))
      (setf (emmet2-stylesheet--node-name node) "background-image"
            (emmet2-stylesheet--node-values node)
            (list (list (vector 'function
                                (cons "linear-gradient" (if gradient (cdr (aref single 1))
                                                          (list (list [field (0 . "") nil nil])))) nil nil)))))
     (name
      (when-let* ((snippet (emmet2-fuzzy-find name (gethash (aref (downcase name) 0) emmet2-stylesheet--snippets)
                                             nil t #'emmet2-stylesheet--snippet-key)))
        (if-let* ((raw (emmet2-stylesheet--snippet-raw snippet)))
            (emmet2-stylesheet--resolve-raw node raw)
          (let* ((tail (emmet2-stylesheet--unmatched name (emmet2-stylesheet--snippet-key snippet)))
                 (keyword (and tail (not values) (emmet2-stylesheet--keyword tail snippet))))
            ;; An unmatched suffix with explicit values leaves the original node.
            (when (or (null tail) keyword)
              (when keyword (setq values (list (list keyword))))
              (setf (emmet2-stylesheet--node-name node) (emmet2-stylesheet--snippet-property snippet))
              (if values
                  (setq values
                        (mapcar
                         (lambda (fragment)
                           (mapcar
                            (lambda (token)
                              (pcase (aref token 0)
                                ('literal (or (emmet2-stylesheet--keyword (aref token 1) snippet) token))
                                ('function
                                 (let* ((value (aref token 1)) (match (emmet2-stylesheet--keyword (car value) snippet)))
                                   (if (and match (eq (aref match 0) 'function))
                                       (vector 'function (cons (car (aref match 1))
                                                               (append (cdr value) (nthcdr (length (cdr value)) (cdr (aref match 1))))) nil nil)
                                     token)))
                                (_ token))) fragment)) values))
                (let* ((choices (emmet2-stylesheet--snippet-choices snippet)) (default (car choices)))
                  (setq values (if (or (= (length choices) 1) (emmet2-stylesheet--has-field-p default))
                                   (copy-tree default t) (mapcar #'emmet2-stylesheet--wrap default)))))
              (setf (emmet2-stylesheet--node-values node) values)))))))
    (when (emmet2-stylesheet--node-name node)
      (dolist (fragment (emmet2-stylesheet--node-values node))
        (dolist (token fragment)
          (when (eq (aref token 0) 'number)
            (let* ((value (aref token 1)) (unit (aref value 1)))
              (aset value 1
                    (cond ((not (equal unit "")) (or (cdr (assoc unit '(("e" . "em") ("p" . "%") ("x" . "ex") ("r" . "rem")))) unit))
                          ((or (= (aref value 0) 0)
                               (member (emmet2-stylesheet--node-name node)
                                       '("z-index" "line-height" "opacity" "font-weight" "zoom" "flex" "flex-grow" "flex-shrink"))) "")
                          ((string-search "." (aref value 2)) "rem") (t "px"))))))))
    node))

(defun emmet2-stylesheet--push (out text &optional lines)
  "Append TEXT to OUT, processing newlines when LINES is non-nil."
  (when lines
    (setq text (replace-regexp-in-string "\r\n\\|[\r\n]" (concat "\n" (emmet2-stylesheet--output-base-indent out)) text t t)))
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
       ;; copy-tree duplicates AST containers, not strings.  A returned field
       ;; must not expose a mutable string from the immutable snippet table.
       (let ((start (emmet2-stylesheet--output-offset out)) (default (copy-sequence (cdr value))))
         (emmet2-stylesheet--push out default)
         (push (list start (emmet2-stylesheet--output-offset out) (car value) default)
               (emmet2-stylesheet--output-fields out))))
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

(defun emmet2-stylesheet--format (node base-indent)
  "Format NODE using BASE-INDENT, giving its fields independent group scope."
  (let ((out (emmet2-stylesheet--output base-indent))
        (name (emmet2-stylesheet--node-name node)) (values (emmet2-stylesheet--node-values node)))
    (if name
        (progn
          (emmet2-stylesheet--push out (concat name ": ") t)
          (if values
              (let ((first t))
                (dolist (fragment values)
                  (unless first (emmet2-stylesheet--push out ", "))
                  (setq first nil)
                  (emmet2-stylesheet--emit-value out fragment)))
            (emmet2-stylesheet--emit-token out [field (0 . "") nil nil])))
      (dolist (fragment values)
        (dolist (token fragment) (emmet2-stylesheet--emit-token out token))))
    (when (emmet2-stylesheet--node-important node)
      (emmet2-stylesheet--push out (if (or name values) " !important" "!important")))
    (when name (emmet2-stylesheet--push out ";"))
    (let* ((fields (nreverse (emmet2-stylesheet--output-fields out)))
           (sorted (cl-stable-sort (copy-sequence fields)
                                   (lambda (a b) (< (if (or (null (nth 2 a)) (eq (nth 2 a) 0)) 1.0e+INF (nth 2 a))
                                                     (if (or (null (nth 2 b)) (eq (nth 2 b) 0)) 1.0e+INF (nth 2 b))))))
           (groups (make-hash-table :test #'equal)) (next 0))
      (dolist (field sorted)
        (let* ((index (nth 2 field)) (key (cons index (nth 3 field)))
               (group (and (not (eq index 0)) (gethash key groups))))
          (unless group (setq group (cl-incf next)) (puthash key group groups))
          (setcar (nthcdr 2 field) group)))
      (emmet2-result-create (apply #'concat (nreverse (emmet2-stylesheet--output-parts out))) fields))))

(cl-defun emmet2-engine-stylesheet-expand (abbreviation &key (preset 'stylesheet) (indent "\t") (base-indent ""))
  "Expand stylesheet ABBREVIATION to a canonical result.
PRESET must be stylesheet.  INDENT and BASE-INDENT follow the common engine
contract; the pinned CSS formatter preserves literal snippet tabs."
  (unless (and (stringp abbreviation) (eq preset 'stylesheet) (stringp indent) (stringp base-indent))
    (signal 'emmet2-error '("Invalid stylesheet abbreviation, preset or indentation")))
  (emmet2-engine-with-expansion
    (let ((nodes (emmet2-stylesheet--parse abbreviation)) results (first t))
      (dolist (node nodes)
        (emmet2-engine--check-deadline)
        (unless first (push (emmet2-result-create (concat "\n" base-indent)) results))
        (setq first nil)
        (push (emmet2-stylesheet--format (emmet2-stylesheet--resolve node) base-indent) results))
      (apply #'emmet2-result-concat (nreverse results)))))

(provide 'emmet2-engine-stylesheet)
;;; emmet2-engine-stylesheet.el ends here
