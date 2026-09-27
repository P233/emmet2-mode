;;; emmet2-engine-markup.el --- Native markup expansion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; S6 implementation, called directly by its tests until both native engines
;; pass acceptance.  The editor still uses the Node backend.
;; Grammar, snippet resolution and HTML formatting follow vendored Emmet 2.4.11
;; (vendor/emmet-LICENSE).  All mutable trees and output belong to one call.
;; Project JSX transforms and seeded lorem remain subsequent S6 slices.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'seq)
(require 'emmet2-engine)

(defconst emmet2-markup--data-directory
  (expand-file-name "data/emmet" (file-name-directory (or load-file-name buffer-file-name))))

(defun emmet2-markup--read-data (name)
  "Read packaged JSON NAME during module initialization."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name emmet2-markup--data-directory))
    (json-parse-buffer)))

(defconst emmet2-markup--snippets
  (let ((table (make-hash-table :test #'equal)))
    (maphash (lambda (names value)
               (dolist (name (split-string names "|")) (puthash name value table)))
             (emmet2-markup--read-data "html.json"))
    table))
(defconst emmet2-markup--variables (emmet2-markup--read-data "variables.json"))
(defconst emmet2-markup--inline
  '("a" "abbr" "acronym" "applet" "b" "basefont" "bdo" "big" "br" "button"
    "cite" "code" "del" "dfn" "em" "font" "i" "iframe" "img" "input" "ins"
    "kbd" "label" "map" "object" "q" "s" "samp" "select" "small" "span"
    "strike" "strong" "sub" "sup" "textarea" "tt" "u" "var"))
(defconst emmet2-markup--implicit
  '(("p" . "span") ("ul" . "li") ("ol" . "li") ("table" . "tr") ("tr" . "td")
    ("tbody" . "tr") ("thead" . "tr") ("tfoot" . "tr") ("colgroup" . "col")
    ("select" . "option") ("optgroup" . "option") ("audio" . "source")
    ("video" . "source") ("object" . "param") ("map" . "area")))
(defconst emmet2-markup--booleans
  '("contenteditable" "seamless" "async" "autofocus" "autoplay" "checked" "controls"
    "defer" "disabled" "formnovalidate" "hidden" "ismap" "loop" "multiple" "muted"
    "novalidate" "readonly" "required" "reversed" "selected" "typemustmatch"))
(defconst emmet2-markup--format-space
  "[\t-\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]"
  "ECMAScript whitespace used by the pinned HTML formatter.")

(cl-defstruct (emmet2-markup--scanner (:constructor emmet2-markup--scanner (tokens jsx)))
  tokens jsx)
(cl-defstruct (emmet2-markup--node (:constructor emmet2-markup--node))
  name attributes attributes-present value children repeat group self-closing)
(cl-defstruct (emmet2-markup--attribute (:constructor emmet2-markup--attribute))
  name value kind implied boolean multiple)
(cl-defstruct (emmet2-markup--repeat (:constructor emmet2-markup--repeat (count implicit)))
  count implicit (index 0))
(cl-defstruct (emmet2-markup--conversion (:constructor emmet2-markup--conversion))
  repeaters inserted)

(defun emmet2-markup--tokenize (text)
  "Tokenize all of TEXT before parsing, preserving lexical error precedence.
Tokens are [TYPE VALUE CHARACTER-POSITION].  Context affects literal scanning;
fields, repeaters and whitespace have precedence at every token boundary."
  (let ((pos 0) (size (length text)) (quote 0) (attribute 0) (expression 0) tokens)
    (cl-labels
        ((peek (&optional offset) (and (< (+ pos (or offset 0)) size) (aref text (+ pos (or offset 0)))))
         (eat (ch) (when (eq (peek) ch) (cl-incf pos) t))
         (digit (ch) (and ch (<= ?0 ch ?9)))
         (alpha (ch) (and ch (or (<= ?a ch ?z) (<= ?A ch ?Z))))
         (space (ch) (memq ch '(?\s ?\t ?\r ?\n #xa0)))
         (operator (ch) (memq ch '(?> ?+ ?^ ?. ?# ?= ?/)))
         (bracket (ch) (memq ch '(?\( ?\) ?\[ ?\] ?\{ ?\})))
         (fail (at) (signal 'emmet2-parse-error (list "Expecting }" at)))
         (placeholder ()
           (let ((start pos) stack done)
             (while (and (< pos size) (not done))
               (cond ((eat ?\{) (push pos stack))
                     ((eq (peek) ?\}) (if stack (progn (pop stack) (cl-incf pos)) (setq done t)))
                     (t (cl-incf pos))))
             (when stack (fail (car stack)))
             (substring text start pos)))
         (literal ()
           (let ((start pos) (depth expression) (segment pos) parts done)
             (while (and (< pos size) (not done))
               (let ((ch (peek)))
                 (cond
                  ((eq ch ?\\)
                   (push (substring text segment pos) parts)
                   (cl-incf pos)
                   (setq segment pos)
                   (when (and (peek) (> (peek) #xffff) (= quote 0) (= expression 0) (= attribute 0))
                     (signal 'emmet2-parse-error (list "Unexpected character" pos)))
                   (when (< pos size) (cl-incf pos)))
                  ((and (eq ch ?/) (= quote 0) (= expression 0) (= attribute 0)
                        (> pos 0) (digit (aref text (1- pos))) (digit (peek 1)))
                   (cl-incf pos))
                  ((or (eq ch quote) (eq ch ?$)
                       (and (operator ch) (= quote 0) (= expression 0)
                            (or (= attribute 0) (eq ch ?=))))
                   (setq done t))
                  ((/= depth 0)
                   (cond ((eq ch ?\{) (cl-incf expression) (cl-incf pos))
                         ((eq ch ?\}) (if (> expression depth)
                                            (progn (cl-decf expression) (cl-incf pos))
                                          (setq done t)))
                         (t (cl-incf pos))))
                  ((and (= quote 0)
                        (or (and (= attribute 0)
                                 (not (or (alpha ch) (digit ch) (memq ch '(196 214 220 228 246 252))
                                          (memq ch '(?_ ?- ?: ?!)))))
                            (space ch) (memq ch '(?\" ?\')) (bracket ch)
                            (and (eq ch ?*) (= attribute 0))))
                   (setq done t))
                  (t (cl-incf pos)))))
             (when (> pos start)
               (push (substring text segment pos) parts)
               (apply #'concat (nreverse parts))))))
      (while (< pos size)
        (emmet2-engine--check-deadline)
        (let ((start pos) (ch (peek)) type value)
          (cond
           ((and (or (/= attribute 0) (/= expression 0)) (eq ch ?$) (eq (peek 1) ?\{))
            (cl-incf pos 2)
            (let ((begin pos) index (default ""))
              (cond
               ((digit (peek))
                (while (digit (peek)) (cl-incf pos))
                (setq index (string-to-number (substring text begin pos)))
                (when (eat ?:) (setq default (placeholder))))
               ((alpha (peek)) (setq default (placeholder))))
              (unless (eat ?\}) (fail pos))
              (setq type (if index 'field 'literal)
                    value (if index (cons index default) (gethash default emmet2-markup--variables default)))))
           ((and (eq ch ?$) (eq (peek 1) ?#))
            (cl-incf pos 2) (setq type 'placeholder))
           ((eq ch ?$)
            (while (eat ?$))
            (let ((width (- pos start)) (base 1) (parent 0) reverse)
              (when (eat ?@)
                (while (eat ?^) (cl-incf parent))
                (setq reverse (eat ?-))
                (let ((begin pos))
                  (while (digit (peek)) (cl-incf pos))
                  (when (> pos begin) (setq base (string-to-number (substring text begin pos))))))
              (setq type 'number value (vector width reverse base parent))))
           ((eat ?*)
            (let ((begin pos))
              (while (digit (peek)) (cl-incf pos))
              (setq type 'repeat value (emmet2-markup--repeat
                                       (if (= begin pos) 1 (string-to-number (substring text begin pos)))
                                       (= begin pos)))))
           ((space ch)
            (while (space (peek)) (cl-incf pos))
            (setq type 'space value (substring text start pos)))
           ((setq value (literal)) (setq type 'literal))
           ((operator ch) (cl-incf pos) (setq type 'operator value ch))
           ((memq ch '(?\" ?\'))
            (cl-incf pos) (setq type 'quote value ch quote (if (= quote ch) 0 ch)))
           ((bracket ch)
            (cl-incf pos) (setq type 'bracket value ch)
            (pcase ch (?\[ (cl-incf attribute)) (?\] (cl-decf attribute))
                   (?\{ (cl-incf expression)) (?\} (cl-decf expression))))
           (t (signal 'emmet2-parse-error (list "Unexpected character" pos))))
          (push (vector type value start) tokens))))
    (nreverse tokens)))

(defun emmet2-markup--peek (scanner)
  "Return SCANNER's next token."
  (car (emmet2-markup--scanner-tokens scanner)))

(defun emmet2-markup--token-p (token type &optional value)
  "Whether TOKEN has TYPE and optional VALUE."
  (and token (eq (aref token 0) type) (or (null value) (eq (aref token 1) value))))

(defun emmet2-markup--eat (scanner type &optional value)
  "Consume and return the next token of TYPE and optional VALUE in SCANNER."
  (when (emmet2-markup--token-p (emmet2-markup--peek scanner) type value)
    (pop (emmet2-markup--scanner-tokens scanner))))

(defun emmet2-markup--error (scanner message &optional token)
  "Signal MESSAGE at TOKEN, or SCANNER's next token."
  (signal 'emmet2-parse-error (list message (aref (or token (emmet2-markup--peek scanner)) 2))))

(defun emmet2-markup--value (tokens)
  "Convert parsed TOKENS into literal, field, numbering and placeholder values."
  (or (mapcar (lambda (token)
                (pcase (aref token 0)
                  ('placeholder 'placeholder)
                  ('repeat 'repeater)
                  ((or 'operator 'quote 'bracket)
                   ;; The pinned upstream stringifier emits } for a group close.
                   (char-to-string (if (eq (aref token 1) ?\)) ?\} (aref token 1))))
                  (_ (aref token 1)))) tokens)
      '("")))

(defun emmet2-markup--literal (scanner &optional brackets)
  "Consume literal tokens from SCANNER, allowing balanced BRACKETS."
  (let ((depth (make-hash-table :test #'eq)) result done)
    (while (and (emmet2-markup--peek scanner) (not done))
      (let* ((token (emmet2-markup--peek scanner)) (type (aref token 0)) (ch (aref token 1))
             (key (and (eq type 'bracket) (pcase ch ((or ?\[ ?\]) 'attribute)
                                                        ((or ?\{ ?\}) 'expression) (_ 'group))))
             (open (memq ch '(?\[ ?\{ ?\())))
        (cond
         ((> (gethash 'expression depth 0) 0)
          (when (eq key 'expression) (puthash key (+ (gethash key depth) (if open 1 -1)) depth)))
         ((memq type '(quote operator space repeat)) (setq done t))
         (key
          (if (and brackets (or open (> (gethash key depth 0) 0)))
              (puthash key (+ (gethash key depth 0) (if open 1 -1)) depth)
            (setq done t))))
        (unless done (push (pop (emmet2-markup--scanner-tokens scanner)) result))))
    (nreverse result)))

(defun emmet2-markup--quoted (scanner)
  "Consume quoted tokens from SCANNER, retaining both quote tokens."
  (when-let* ((open (emmet2-markup--eat scanner 'quote)))
    (let ((result (list open)) closed)
      (while (and (emmet2-markup--peek scanner) (not closed))
        (let ((token (pop (emmet2-markup--scanner-tokens scanner))))
          (push token result)
          (setq closed (emmet2-markup--token-p token 'quote (aref open 1)))))
      (unless closed (emmet2-markup--error scanner "Unclosed quote" open))
      (nreverse result))))

(defun emmet2-markup--text (scanner)
  "Consume brace-delimited text from SCANNER, allowing an omitted close."
  (when (emmet2-markup--eat scanner 'bracket ?\{)
    (let ((depth 0) result done)
      (while (and (emmet2-markup--peek scanner) (not done))
        (let ((token (pop (emmet2-markup--scanner-tokens scanner))))
          (cond ((emmet2-markup--token-p token 'bracket ?\{) (cl-incf depth))
                ((emmet2-markup--token-p token 'bracket ?\})
                 (if (= depth 0) (setq done t) (cl-decf depth))))
          (unless done (push token result))))
      (emmet2-markup--value (nreverse result)))))

(defun emmet2-markup--attributes (scanner)
  "Read attributes from SCANNER after an opening bracket."
  (let (attributes name value kind)
    (while (and (emmet2-markup--peek scanner) (not (emmet2-markup--eat scanner 'bracket ?\])))
      (setq name nil value nil kind nil)
      (cond
       ((setq value (emmet2-markup--quoted scanner)))
       ((setq name (emmet2-markup--literal scanner t))
        (when (emmet2-markup--eat scanner 'operator ?=)
          (setq value (or (emmet2-markup--quoted scanner) (emmet2-markup--literal scanner t)))))
       ((emmet2-markup--eat scanner 'space))
       (t (emmet2-markup--error scanner
                               (format "Unexpected \"%s\" token"
                                       (pcase (aref (emmet2-markup--peek scanner) 0)
                                         ('repeat "Repeater") ('operator "Operator")
                                         ('bracket "Bracket") (_ "Literal"))))))
      (when (or name value)
        (cond
         ((emmet2-markup--token-p (car value) 'quote)
          (setq kind 'quoted value (butlast (cdr value))))
         ((emmet2-markup--token-p (car value) 'bracket ?\{)
          (setq kind 'expression value (cdr value))
          (when (emmet2-markup--token-p (car (last value)) 'bracket ?\}) (setq value (butlast value)))))
        (push (emmet2-markup--attribute :name (and name (emmet2-markup--value name))
                                        :value (and (or value kind) (emmet2-markup--value value)) :kind kind)
              attributes)))
    (nreverse attributes)))

(defun emmet2-markup--element (scanner)
  "Consume one markup element from SCANNER."
  (let ((start (emmet2-markup--scanner-tokens scanner)) name
        (node (emmet2-markup--node)) done)
    (when (and (emmet2-markup--scanner-jsx scanner)
               (emmet2-markup--token-p (emmet2-markup--peek scanner) 'literal)
               (string-match-p "\\`[A-Z]" (aref (emmet2-markup--peek scanner) 1)))
      (push (pop (emmet2-markup--scanner-tokens scanner)) name)
      (while (let ((next (emmet2-markup--scanner-tokens scanner)))
               (and (emmet2-markup--token-p (car next) 'operator ?.)
                    (emmet2-markup--token-p (cadr next) 'literal)
                    (string-match-p "\\`[A-Z]" (aref (cadr next) 1))))
        (push (pop (emmet2-markup--scanner-tokens scanner)) name)
        (push (pop (emmet2-markup--scanner-tokens scanner)) name)))
    (while (memq (and (emmet2-markup--peek scanner) (aref (emmet2-markup--peek scanner) 0))
                 '(literal number placeholder))
      (push (pop (emmet2-markup--scanner-tokens scanner)) name))
    (when name (setf (emmet2-markup--node-name node) (emmet2-markup--value (nreverse name))))
    (while (and (emmet2-markup--peek scanner) (not done))
      (let* ((token (emmet2-markup--peek scanner)) (ch (aref token 1)))
        (cond
         ((and (not (emmet2-markup--node-repeat node))
               (not (eq start (emmet2-markup--scanner-tokens scanner)))
               (emmet2-markup--eat scanner 'repeat))
          (setf (emmet2-markup--node-repeat node) ch))
         ((and (not (emmet2-markup--node-value node)) (emmet2-markup--token-p token 'bracket ?\{))
          (setf (emmet2-markup--node-value node) (emmet2-markup--text scanner)))
         ((and (eq (aref token 0) 'operator) (memq ch '(?. ?#)))
          (pop (emmet2-markup--scanner-tokens scanner))
          (let ((count 1) value kind)
            (while (emmet2-markup--eat scanner 'operator ch) (cl-incf count))
            (if (and (emmet2-markup--scanner-jsx scanner)
                     (emmet2-markup--token-p (emmet2-markup--peek scanner) 'bracket ?\{))
                (setq value (emmet2-markup--text scanner) kind 'expression)
              (when-let* ((tokens (emmet2-markup--literal scanner))) (setq value (emmet2-markup--value tokens))))
            (push (emmet2-markup--attribute :name (list (if (eq ch ?.) "class" "id"))
                                            :value value :kind kind :multiple (> count 1))
                  (emmet2-markup--node-attributes node))
            (setf (emmet2-markup--node-attributes-present node) t)))
         ((emmet2-markup--eat scanner 'bracket ?\[)
          (setf (emmet2-markup--node-attributes-present node) t)
          (dolist (attr (emmet2-markup--attributes scanner)) (push attr (emmet2-markup--node-attributes node))))
         (t
          (when (and (not (eq start (emmet2-markup--scanner-tokens scanner)))
                     (emmet2-markup--eat scanner 'operator ?/))
            (setf (emmet2-markup--node-self-closing node) t)
            (unless (emmet2-markup--node-repeat node)
              (when-let* ((repeat (emmet2-markup--eat scanner 'repeat)))
                (setf (emmet2-markup--node-repeat node) (aref repeat 1)))))
          (setq done t)))))
    (setf (emmet2-markup--node-attributes node) (nreverse (emmet2-markup--node-attributes node)))
    (and (not (eq start (emmet2-markup--scanner-tokens scanner))) node)))

(defun emmet2-markup--statements (scanner)
  "Read child, sibling, climb and grouped statements from SCANNER."
  (let* ((root (emmet2-markup--node :group t)) (parent root) stack node)
    (while (setq node
                 (or (emmet2-markup--element scanner)
                     (when (emmet2-markup--eat scanner 'bracket ?\()
                       (let ((group (emmet2-markup--statements scanner))
                             (close (pop (emmet2-markup--scanner-tokens scanner))))
                         (when (emmet2-markup--token-p close 'bracket ?\))
                           (when-let* ((repeat (emmet2-markup--eat scanner 'repeat)))
                             (setf (emmet2-markup--node-repeat group) (aref repeat 1))))
                         group))))
      (push node (emmet2-markup--node-children parent))
      (cond
       ((emmet2-markup--eat scanner 'operator ?>) (push parent stack) (setq parent node))
       ((emmet2-markup--eat scanner 'operator ?+))
       ((emmet2-markup--eat scanner 'operator ?^)
        (when stack (setq parent (pop stack)))
        (while (emmet2-markup--eat scanner 'operator ?^) (when stack (setq parent (pop stack)))))))
    root))

(defun emmet2-markup--parse (text &optional jsx)
  "Parse markup TEXT with JSX component and expression shorthand when JSX."
  (let* ((case-fold-search nil)
         (scanner (emmet2-markup--scanner (emmet2-markup--tokenize text) jsx))
         (root (emmet2-markup--statements scanner)))
    (when (emmet2-markup--peek scanner) (emmet2-markup--error scanner "Unexpected character"))
    root))

(defun emmet2-markup--convert-value (tokens state)
  "Resolve TOKENS with call-owned conversion STATE and coalesce literals.
Return fresh list cells so conversion never modifies shared syntax."
  (let ((repeaters (emmet2-markup--conversion-repeaters state)) result literals)
    (cl-labels ((flush ()
                 (when literals
                   (push (apply #'concat (nreverse literals)) result)
                   (setq literals nil))))
      (dolist (token tokens)
        (cond
         ((eq token 'repeater) (signal 'emmet2-backend-error '("Unknown token Repeater")))
         ((eq token 'placeholder)
          (setf (emmet2-markup--conversion-inserted state) t)
          (setq token ""))
         ((vectorp token)
          (let* ((repeat (car repeaters))
                 (parent (and repeaters (nth (min (aref token 3) (1- (length repeaters))) repeaters)))
                 (value (if repeat
                            (+ (aref token 2)
                               (if (aref token 1)
                                   (- (emmet2-markup--repeat-count repeat) (emmet2-markup--repeat-index repeat) 1)
                                 (emmet2-markup--repeat-index repeat)))
                          1)))
            (when (and parent (not (eq parent repeat)))
              (cl-incf value (* (emmet2-markup--repeat-count repeat) (emmet2-markup--repeat-index parent))))
            (setq token (format (concat "%0" (number-to-string (aref token 0)) "d") value)))))
        (if (stringp token) (push token literals)
          (flush)
          (push token result)))
      (flush))
    (nreverse result)))

(defun emmet2-markup--convert-attribute (attr state)
  "Copy syntax ATTR and resolve its name/value in STATE."
  (let* ((copy (copy-emmet2-markup--attribute attr))
         (name (emmet2-markup--convert-name (emmet2-markup--attribute-name attr) state))
         (implied (and name (string-prefix-p "!" name)))
         (boolean (and name (string-suffix-p "." name))))
    (setf (emmet2-markup--attribute-name copy)
          (and name (substring name (if implied 1 0) (if boolean -1 nil)))
          (emmet2-markup--attribute-implied copy) implied
          (emmet2-markup--attribute-boolean copy) boolean
          (emmet2-markup--attribute-value copy)
          (emmet2-markup--convert-value (emmet2-markup--attribute-value attr) state))
    copy))

(defun emmet2-markup--convert-name (tokens state)
  "Resolve name TOKENS in STATE; fields in names are literal TextMate syntax."
  (let ((name (mapconcat (lambda (token)
                           (if (consp token)
                               (if (string-empty-p (cdr token)) (format "${%d" (car token))
                                 (format "${%d:%s}" (car token) (cdr token)))
                             token))
                         (emmet2-markup--convert-value tokens state))))
    (unless (string-empty-p name) name)))

(defun emmet2-markup--convert-element (node state repeat)
  "Create fresh nodes for syntax NODE using STATE and this iteration's REPEAT."
  (let ((copy (copy-emmet2-markup--node node)) children)
    ;; Preserve upstream visitation order: name/value, children, attributes.
    ;; A placeholder anywhere in that order affects subsequent implicit wraps.
    (setf (emmet2-markup--node-name copy)
          (emmet2-markup--convert-name (emmet2-markup--node-name node) state)
          (emmet2-markup--node-value copy)
          (emmet2-markup--convert-value (emmet2-markup--node-value node) state)
          (emmet2-markup--node-repeat copy) repeat)
    (setq children (mapcan (lambda (child) (emmet2-markup--convert child state))
                            (reverse (emmet2-markup--node-children node))))
    (setf (emmet2-markup--node-attributes copy)
          (mapcar (lambda (attr) (emmet2-markup--convert-attribute attr state))
                  (emmet2-markup--node-attributes node)))
    (if (and (not (emmet2-markup--node-name copy))
             (not (emmet2-markup--node-attributes-present copy))
             (emmet2-markup--node-value copy)
             (not (cl-some #'consp (emmet2-markup--node-value copy))))
        (progn (setf (emmet2-markup--node-children copy) nil) (cons copy children))
      (setf (emmet2-markup--node-children copy) children)
      (list copy))))

(defun emmet2-markup--convert (node &optional state)
  "Unroll parsed NODE into owned nodes, sharing STATE within this conversion."
  (let* ((state (or state (emmet2-markup--conversion)))
         (syntax-repeat (emmet2-markup--node-repeat node))
         (count (if syntax-repeat (max 1 (emmet2-markup--repeat-count syntax-repeat)) 1)) result)
    (dotimes (index count)
      (emmet2-engine--check-deadline)
      (let ((repeat (and syntax-repeat (copy-emmet2-markup--repeat syntax-repeat))) items)
        (when repeat
          (setf (emmet2-markup--repeat-count repeat) count
                (emmet2-markup--repeat-index repeat) index)
          (push repeat (emmet2-markup--conversion-repeaters state)))
        (if (emmet2-markup--node-group node)
            (progn
              (setq items (mapcan (lambda (child) (emmet2-markup--convert child state))
                                   (reverse (emmet2-markup--node-children node))))
              (when repeat
                (dolist (item items)
                  (unless (emmet2-markup--node-repeat item)
                    (setf (emmet2-markup--node-repeat item) (copy-emmet2-markup--repeat repeat))))))
          (setq items (emmet2-markup--convert-element node state repeat)))
        (when (and repeat (emmet2-markup--repeat-implicit repeat)
                   (not (emmet2-markup--conversion-inserted state)))
          (let ((deepest (car (last items))))
            (while (and deepest (emmet2-markup--node-children deepest))
              (setq deepest (car (last (emmet2-markup--node-children deepest)))))
            (when deepest
              (unless (stringp (car (last (emmet2-markup--node-value deepest))))
                (setf (emmet2-markup--node-value deepest)
                      (append (emmet2-markup--node-value deepest) '("")))))))
        (dolist (item items) (push item result))
        (when repeat (pop (emmet2-markup--conversion-repeaters state)))))
    (when (and syntax-repeat (emmet2-markup--repeat-implicit syntax-repeat))
      (setf (emmet2-markup--conversion-inserted state) t))
    (nreverse result)))

(defun emmet2-markup--resolve (nodes parsed &optional stack jsx)
  "Resolve call-owned NODES with the request-local PARSED table and cycle STACK.
Only snippet syntax trees are shared within this call; conversion creates
fresh nodes before resolution or transformation can change them."
  (mapcan
   (lambda (node)
     (let ((snippet (gethash (emmet2-markup--node-name node) emmet2-markup--snippets)))
       (if (and snippet (not (member snippet stack)))
           (let* ((syntax (or (gethash snippet parsed)
                              (puthash snippet (emmet2-markup--parse snippet jsx) parsed)))
                  (resolved (emmet2-markup--resolve
                             (emmet2-markup--convert syntax) parsed (cons snippet stack) jsx))
                  (deepest (car (last resolved))))
             (dolist (top resolved)
               (setf (emmet2-markup--node-attributes top)
                     (append (emmet2-markup--node-attributes top) (emmet2-markup--node-attributes node))
                     (emmet2-markup--node-attributes-present top)
                     (or (emmet2-markup--node-attributes-present top) (emmet2-markup--node-attributes-present node)))
               (when (emmet2-markup--node-repeat node)
                 (setf (emmet2-markup--node-repeat top) (copy-emmet2-markup--repeat (emmet2-markup--node-repeat node))))
               (when (emmet2-markup--node-value node)
                 (setf (emmet2-markup--node-value top) (emmet2-markup--node-value node)))
               (when (emmet2-markup--node-self-closing node)
                 (setf (emmet2-markup--node-self-closing top) t)))
             (while (emmet2-markup--node-children deepest)
               (setq deepest (car (last (emmet2-markup--node-children deepest)))))
             (setf (emmet2-markup--node-children deepest)
                   (emmet2-markup--resolve (emmet2-markup--node-children node) parsed stack jsx))
             resolved)
         (setf (emmet2-markup--node-children node)
               (emmet2-markup--resolve (emmet2-markup--node-children node) parsed stack jsx))
         (list node)))) nodes))

(defun emmet2-markup--merge-attributes (attributes)
  "Return merged copies of ATTRIBUTES, keeping first position and last value."
  (let (result)
    (dolist (attr attributes)
      (let* ((name (emmet2-markup--attribute-name attr))
             (previous (cl-find name result :key #'emmet2-markup--attribute-name :test #'equal)))
        (if (or (not name) (not previous)) (push (copy-emmet2-markup--attribute attr) result)
          (let ((value (emmet2-markup--attribute-value attr)))
            (if (equal name "class")
                (setf (emmet2-markup--attribute-value previous)
                      (append (emmet2-markup--attribute-value previous)
                              (and (emmet2-markup--attribute-value previous) value
                                   (not (equal (emmet2-markup--attribute-value previous) '(""))) '(" ")) value))
              (setf (emmet2-markup--attribute-value previous) value
                  (emmet2-markup--attribute-implied previous)
                  (or (emmet2-markup--attribute-implied previous) (emmet2-markup--attribute-implied attr))
                  (emmet2-markup--attribute-boolean previous)
                  (or (emmet2-markup--attribute-boolean previous) (emmet2-markup--attribute-boolean attr))
                  (emmet2-markup--attribute-kind previous)
                  (if (eq (emmet2-markup--attribute-kind previous) 'expression) 'expression
                    (emmet2-markup--attribute-kind attr))))))))
    (nreverse result)))

(defun emmet2-markup--empty-attribute-p (attr)
  "Whether ATTR has no value or a single empty field."
  (let ((value (emmet2-markup--attribute-value attr)))
    (or (null value) (and (= (length value) 1) (consp (car value)) (equal (cdar value) "")))))

(defun emmet2-markup--find-input (nodes)
  "Find the first input or textarea in NODES, depth first."
  (cl-loop for node in nodes
           thereis (if (member (emmet2-markup--node-name node) '("input" "textarea")) node
                     (emmet2-markup--find-input (emmet2-markup--node-children node)))))

(defun emmet2-markup--transform (nodes &optional parent-name)
  "Resolve implicit tags, attributes and label associations in NODES."
  (dolist (node nodes)
    (when (and (null (emmet2-markup--node-name node)) (emmet2-markup--node-attributes-present node))
      (setf (emmet2-markup--node-name node)
            (or (cdr (assoc parent-name emmet2-markup--implicit))
                (if (member parent-name emmet2-markup--inline) "span" "div"))))
    (setf (emmet2-markup--node-attributes node)
          (emmet2-markup--merge-attributes (emmet2-markup--node-attributes node)))
    (when (equal (emmet2-markup--node-name node) "label")
      (when-let* ((input (emmet2-markup--find-input (emmet2-markup--node-children node))))
        (dolist (pair (list (cons node "for") (cons input "id")))
          (setf (emmet2-markup--node-attributes (car pair))
                (cl-remove-if (lambda (attr) (and (equal (emmet2-markup--attribute-name attr) (cdr pair))
                                                  (emmet2-markup--empty-attribute-p attr)))
                              (emmet2-markup--node-attributes (car pair)))))))
    (emmet2-markup--transform (emmet2-markup--node-children node)
                             (downcase (or (emmet2-markup--node-name node) "")))))

(cl-defstruct (emmet2-markup--output (:constructor emmet2-markup--output (indent base-indent jsx)))
  indent base-indent jsx parts fields (offset 0) (field 1) (level 0) (line 0))

(defun emmet2-markup--push (out text)
  "Append literal TEXT to OUT, counting characters."
  (push text (emmet2-markup--output-parts out))
  (cl-incf (emmet2-markup--output-offset out) (length text)))

(defun emmet2-markup--newline (out &optional level)
  "Append a formatted newline at LEVEL to OUT."
  (emmet2-markup--push out (concat "\n" (emmet2-markup--output-base-indent out)))
  (cl-incf (emmet2-markup--output-line out))
  (dotimes (_ (max 0 (or level (emmet2-markup--output-level out))))
    (emmet2-markup--push out (emmet2-markup--output-indent out))))

(defun emmet2-markup--string (out text)
  "Append TEXT to OUT, formatting embedded newlines."
  (let ((start 0))
    (while (string-match "\r\n\\|[\r\n]" text start)
      (emmet2-markup--push out (substring text start (match-beginning 0)))
      (setq start (match-end 0))
      (emmet2-markup--newline out))
    (emmet2-markup--push out (substring text start))))

(defun emmet2-markup--emit-tokens (out tokens)
  "Emit TOKENS and their fields into OUT within one numbering scope."
  (let ((largest -1))
    (dolist (token tokens)
      (if (stringp token) (emmet2-markup--string out token)
        (let ((offset (emmet2-markup--output-offset out)) (placeholder (cdr token)))
          (push (list offset (+ offset (length placeholder))
                      (+ (emmet2-markup--output-field out) (car token)) placeholder)
                (emmet2-markup--output-fields out))
          (emmet2-markup--push out placeholder)
          (setq largest (max largest (car token))))))
    (cl-incf (emmet2-markup--output-field out) (1+ largest))))

(defun emmet2-markup--inline-p (node)
  "Whether NODE is an inline element or text snippet."
  (and node (if (emmet2-markup--node-name node)
                (member (downcase (emmet2-markup--node-name node)) emmet2-markup--inline)
              (and (emmet2-markup--node-value node) (not (emmet2-markup--node-attributes-present node))))))

(defun emmet2-markup--format-p (node index siblings parent)
  "Whether NODE at INDEX in SIBLINGS under PARENT starts on a new line."
  (cond
   ((and (= index 0) (not parent)) nil)
   ((and parent (not (emmet2-markup--node-name parent)) (= (length siblings) 1)) nil)
   ((and (not (emmet2-markup--node-name node))
         (or (and (> index 0) (not (emmet2-markup--node-name (nth (1- index) siblings))))
             (and (< (1+ index) (length siblings)) (not (emmet2-markup--node-name (nth (1+ index) siblings))))
             (cl-some (lambda (v) (and (stringp v) (string-match-p "[\r\n]" v))) (emmet2-markup--node-value node))
             (and (cl-some #'consp (emmet2-markup--node-value node)) (emmet2-markup--node-children node)))) t)
   ((not (emmet2-markup--inline-p node)) t)
   (t
    (or (if (= index 0) (cl-some (lambda (n) (not (emmet2-markup--inline-p n))) siblings)
          (not (emmet2-markup--inline-p (nth (1- index) siblings))))
        (let ((before (1- index)) (after (1+ index)) (count 1))
          (while (and (>= before 0) (emmet2-markup--inline-p (nth before siblings)))
            (cl-incf count) (cl-decf before))
          (while (and (< after (length siblings)) (emmet2-markup--inline-p (nth after siblings)))
            (cl-incf count) (cl-incf after))
          (>= count 3))
        (cl-loop for child in (emmet2-markup--node-children node) for i from 0
                 thereis (emmet2-markup--format-p child i (emmet2-markup--node-children node) parent))))))

(defun emmet2-markup--emit-attribute (out attr)
  "Emit ATTR into OUT, assigning fields after layout."
  (let ((name (emmet2-markup--attribute-name attr))
        (value (emmet2-markup--attribute-value attr))
        (expression (or (eq (emmet2-markup--attribute-kind attr) 'expression)
                        (and (emmet2-markup--output-jsx out) (emmet2-markup--attribute-multiple attr)))))
    (when (and name (not (string-empty-p name)) (or (not (emmet2-markup--attribute-implied attr))
                       (emmet2-markup--attribute-kind attr) (and value (not (equal value '(""))))))
      (when (and (emmet2-markup--output-jsx out) (equal name "class")) (setq name "classList"))
      (unless value
        (setq value (if (or (emmet2-markup--attribute-boolean attr) (member (downcase name) emmet2-markup--booleans))
                        (list name) '((0 . "")))))
      (emmet2-markup--push out (concat " " name "=" (if expression "{" "\"")))
      (emmet2-markup--emit-tokens out value)
      (emmet2-markup--push out (if expression "}" "\"")))))

(defun emmet2-markup--block-value-p (value)
  "Whether VALUE starts with a literal block tag, as in the HTML formatter."
  (let ((case-fold-search nil))
    (and (stringp (car value))
         (string-match (concat "\\`<\\([a-zA-Z0-9_:-]+\\)\\(?:>\\|" emmet2-markup--format-space "\\)")
                       (car value))
         (not (member (downcase (match-string 1 (car value))) emmet2-markup--inline)))))

(defun emmet2-markup--emit (out nodes &optional parent)
  "Format resolved NODES under PARENT into OUT."
  (cl-loop
   for node in nodes for index from 0
   do
   (let* ((name (emmet2-markup--node-name node))
          (value (emmet2-markup--node-value node))
          (children (emmet2-markup--node-children node))
          (format (emmet2-markup--format-p node index nodes parent))
          (indent (if (and parent (emmet2-markup--node-name parent)
                           (not (equal (emmet2-markup--node-name parent) "html"))) 1 0)))
     (cl-incf (emmet2-markup--output-level out) indent)
     (when format (emmet2-markup--newline out))
     (when name
       (emmet2-markup--push out (concat "<" name))
       (dolist (attr (emmet2-markup--node-attributes node)) (emmet2-markup--emit-attribute out attr)))
     (if (and name (emmet2-markup--node-self-closing node) (not value) (not children))
         (emmet2-markup--push out (if (emmet2-markup--output-jsx out) " />" ">"))
       (when name (emmet2-markup--push out ">"))
       (if (and value children (cl-some #'consp value))
           (let ((split (cl-position-if #'consp value)))
             (emmet2-markup--emit-tokens out (seq-take value split))
             (let ((line (emmet2-markup--output-line out)) (suffix (nthcdr (1+ split) value)))
               (emmet2-markup--emit out children node)
               (when (and (/= line (emmet2-markup--output-line out)) (stringp (car suffix)))
                 (emmet2-markup--string out (string-trim-left (car suffix) (concat emmet2-markup--format-space "+")))
                 (setq suffix (cdr suffix)))
               (emmet2-markup--emit-tokens out suffix)))
         (when value
           (let ((inner (and name (or (emmet2-markup--block-value-p value)
                                     (cl-some (lambda (v) (and (stringp v) (string-match-p "[\r\n]" v))) value)))))
             (when inner (cl-incf (emmet2-markup--output-level out)) (emmet2-markup--newline out))
             (emmet2-markup--emit-tokens out value)
             (when inner (cl-decf (emmet2-markup--output-level out)) (emmet2-markup--newline out))))
         (emmet2-markup--emit out children node)
         (when (and name (not value) (not children))
           (when (equal name "body") (cl-incf (emmet2-markup--output-level out)) (emmet2-markup--newline out))
           (emmet2-markup--emit-tokens out '((0 . "")))
           (when (equal name "body") (cl-decf (emmet2-markup--output-level out)) (emmet2-markup--newline out))))
       (when name (emmet2-markup--push out (concat "</" name ">"))))
     (when (and format (= index (1- (length nodes))) parent)
       (emmet2-markup--newline out (- (emmet2-markup--output-level out)
                                    (if (emmet2-markup--node-name parent) 1 0))))
     (cl-decf (emmet2-markup--output-level out) indent))))

(defun emmet2-markup--result (out)
  "Return canonical OUT, splitting conflicting defaults within each field index."
  (let ((groups (make-hash-table :test #'equal)) (next 0)
        (fields (nreverse (emmet2-markup--output-fields out))))
    (dolist (field (cl-stable-sort (copy-sequence fields)
                                  (lambda (a b) (< (nth 2 a) (nth 2 b)))))
      (let ((key (cons (nth 2 field) (nth 3 field))))
        (unless (gethash key groups) (puthash key (cl-incf next) groups))))
    ;; Preserve emission order for empty fields sharing a character offset.
    (dolist (field fields)
      (setcar (nthcdr 2 field) (gethash (cons (nth 2 field) (nth 3 field)) groups)))
    (emmet2-result-create (apply #'concat (nreverse (emmet2-markup--output-parts out)))
                          fields)))

(cl-defun emmet2-engine-markup-expand (abbreviation &key (preset 'html) (indent "\t") (base-indent ""))
  "Expand ABBREVIATION through the native markup pipeline.
PRESET is html or jsx.  INDENT and BASE-INDENT affect layout before fields.
This S6.0 entry is independent of the editor's temporary Node backend."
  (unless (and (stringp abbreviation) (memq preset '(html jsx)) (stringp indent) (stringp base-indent))
    (signal 'emmet2-error '("Invalid markup abbreviation, preset or indentation")))
  (emmet2-engine-with-expansion
    (let* ((jsx (eq preset 'jsx))
           (nodes (emmet2-markup--resolve (emmet2-markup--convert (emmet2-markup--parse abbreviation jsx))
                                           (make-hash-table :test #'equal) nil jsx))
           (out (emmet2-markup--output indent base-indent jsx)))
      (emmet2-markup--transform nodes)
      (emmet2-markup--emit out nodes)
      (emmet2-markup--result out))))

(provide 'emmet2-engine-markup)
;;; emmet2-engine-markup.el ends here
