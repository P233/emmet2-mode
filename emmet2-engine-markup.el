;;; emmet2-engine-markup.el --- Native markup expansion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; S6 implementation, called directly by its tests until both native engines
;; pass acceptance.  The editor still uses the Node backend.
;; Grammar, snippet resolution and HTML formatting follow vendored Emmet 2.4.11
;; (vendor/emmet-LICENSE).  All mutable trees and output belong to one call.
;; This first slice covers the complete S6.0 path, not the full markup grammar.

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

(cl-defstruct (emmet2-markup--scanner (:constructor emmet2-markup--scanner (text)))
  text (pos 0))
(cl-defstruct (emmet2-markup--node (:constructor emmet2-markup--node))
  name attributes value children repeat group self-closing)
(cl-defstruct (emmet2-markup--attribute (:constructor emmet2-markup--attribute))
  name value kind implied boolean)

(defun emmet2-markup--peek (scanner)
  "Return the next character of SCANNER, or nil."
  (let ((pos (emmet2-markup--scanner-pos scanner)) (text (emmet2-markup--scanner-text scanner)))
    (and (< pos (length text)) (aref text pos))))

(defun emmet2-markup--eat (scanner character)
  "Consume CHARACTER from SCANNER when present."
  (when (eq (emmet2-markup--peek scanner) character)
    (cl-incf (emmet2-markup--scanner-pos scanner)) t))

(defun emmet2-markup--error (scanner message &optional position)
  "Signal a parse error with MESSAGE at POSITION in SCANNER."
  (signal 'emmet2-parse-error (list message (or position (emmet2-markup--scanner-pos scanner)))))

(defun emmet2-markup--tokens (text offset)
  "Tokenize a value TEXT starting at source OFFSET.
Strings are literal text, conses are (INDEX . DEFAULT) fields, and vectors
hold numbering width, direction, base and parent depth until conversion."
  (let ((pos 0) (start 0) parts)
    (cl-labels ((flush ()
                 (when (< start pos) (push (substring text start pos) parts))))
      (while (< pos (length text))
        (let ((ch (aref text pos)))
          (cond
           ((eq ch ?\\)
            (flush)
            (cl-incf pos)
            (when (< pos (length text))
              (push (substring text pos (1+ pos)) parts) (cl-incf pos))
            (setq start pos))
           ((eq ch ?$)
            (flush)
            (cl-incf pos)
            (cond
             ((and (< pos (length text)) (eq (aref text pos) ?\{))
              (let ((begin (cl-incf pos)) (depth 1))
                (while (and (< pos (length text)) (> depth 0))
                  (pcase (aref text pos) (?\{ (cl-incf depth)) (?\} (cl-decf depth)))
                  (when (> depth 0) (cl-incf pos)))
                (unless (= depth 0)
                  (signal 'emmet2-parse-error (list "Expecting }" (+ offset pos))))
                (let ((content (substring text begin pos)))
                  (cond
                   ((string-match "\\`[0-9]+" content)
                    (let ((end (match-end 0)))
                      (unless (or (= end (length content)) (eq (aref content end) ?:))
                        (signal 'emmet2-parse-error (list "Expecting }" (+ offset begin end))))
                      (push (cons (string-to-number (substring content 0 end))
                                  (if (= end (length content)) "" (substring content (1+ end)))) parts)))
                   ((or (string-empty-p content) (string-match-p "\\`[a-zA-Z]" content))
                    (push (gethash content emmet2-markup--variables content) parts))
                   (t (signal 'emmet2-parse-error (list "Expecting }" (+ offset begin))))))
                (cl-incf pos)))
             ((and (< pos (length text)) (eq (aref text pos) ?#))
              (cl-incf pos))
             (t
              (let ((width 1) (base 1) (parent 0) reverse)
                (while (and (< pos (length text)) (eq (aref text pos) ?$))
                  (cl-incf width) (cl-incf pos))
                (when (and (< pos (length text)) (eq (aref text pos) ?@))
                  (cl-incf pos)
                  (while (and (< pos (length text)) (eq (aref text pos) ?^))
                    (cl-incf parent) (cl-incf pos))
                  (when (and (< pos (length text)) (eq (aref text pos) ?-))
                    (setq reverse t) (cl-incf pos))
                  (let ((begin pos))
                    (while (and (< pos (length text)) (<= ?0 (aref text pos) ?9)) (cl-incf pos))
                    (when (> pos begin) (setq base (string-to-number (substring text begin pos))))))
                (push (vector width reverse base parent) parts))))
            (setq start pos))
           (t (cl-incf pos)))))
      (flush))
    (or (nreverse parts) '(""))))

(defun emmet2-markup--literal (scanner &optional attribute)
  "Consume a literal from SCANNER, allowing ATTRIBUTE punctuation if requested."
  (let* ((start (emmet2-markup--scanner-pos scanner))
         (text (emmet2-markup--scanner-text scanner)) (pos start) (depth 0) done)
    (while (and (< pos (length text)) (not done))
      (let ((ch (aref text pos)))
        (cond
         ((eq ch ?\\) (setq pos (min (length text) (+ pos 2))))
         ((or (> depth 0) (and attribute (eq ch ?\{)))
          (pcase ch (?\{ (cl-incf depth)) (?\} (cl-decf depth)))
          (cl-incf pos))
         ((or (memq ch '(?\s ?\t ?\n ?\r ?\] ?\[ ?\( ?\) ?\{ ?\} ?\" ?\'))
              (and attribute (eq ch ?=))
              (and (not attribute) (memq ch '(?> ?+ ?^ ?. ?# ?* ?/ ?=))))
          ;; Number modifiers contain ^ after @, and fractional utility classes
          ;; may contain / between digits.
          (if (and (not attribute)
                   (or (and (eq ch ?^) (> pos start) (memq (aref text (1- pos)) '(?@ ?^)))
                       (and (eq ch ?/) (> pos start) (< (1+ pos) (length text))
                            (<= ?0 (aref text (1- pos)) ?9) (<= ?0 (aref text (1+ pos)) ?9))))
              (cl-incf pos)
            (setq done t)))
         ((or attribute (<= ?a ch ?z) (<= ?A ch ?Z) (<= ?0 ch ?9)
              (memq ch '(?_ ?- ?: ?! ?$)) (<= #xa0 ch #xff)
              (and (eq ch ?@) (> pos start) (eq (aref text (1- pos)) ?$)))
          (cl-incf pos))
         (t (setq done t)))))
    (setf (emmet2-markup--scanner-pos scanner) pos)
    (when (> pos start) (emmet2-markup--tokens (substring text start pos) start))))

(defun emmet2-markup--text (scanner)
  "Consume brace-delimited text from SCANNER, retaining nested braces."
  (when (emmet2-markup--eat scanner ?\{)
    (let* ((start (emmet2-markup--scanner-pos scanner))
           (text (emmet2-markup--scanner-text scanner)) (pos start) (depth 1))
      (while (and (< pos (length text)) (> depth 0))
        (let ((ch (aref text pos)))
          (cond
           ((eq ch ?\\) (setq pos (min (length text) (+ pos 2))))
           (t (pcase ch (?\{ (cl-incf depth)) (?\} (cl-decf depth)))
              (when (> depth 0) (cl-incf pos))))))
      (setf (emmet2-markup--scanner-pos scanner) (if (= depth 0) (1+ pos) pos))
      (emmet2-markup--tokens (substring text start pos) start))))

(defun emmet2-markup--quoted (scanner)
  "Consume a quoted value from SCANNER."
  (let* ((quote (emmet2-markup--peek scanner))
         (open (emmet2-markup--scanner-pos scanner))
         (start (cl-incf (emmet2-markup--scanner-pos scanner)))
         (text (emmet2-markup--scanner-text scanner)))
    (while (and (emmet2-markup--peek scanner) (not (eq (emmet2-markup--peek scanner) quote)))
      (when (emmet2-markup--eat scanner ?\\)
        (unless (emmet2-markup--peek scanner) (emmet2-markup--error scanner "Unclosed quote" open)))
      (cl-incf (emmet2-markup--scanner-pos scanner)))
    (let ((end (emmet2-markup--scanner-pos scanner)))
      (unless (emmet2-markup--eat scanner quote) (emmet2-markup--error scanner "Unclosed quote" open))
      (emmet2-markup--tokens (substring text start end) start))))

(defun emmet2-markup--attributes (scanner)
  "Read an attribute set from SCANNER after its opening bracket."
  (let (attributes)
    (while (and (emmet2-markup--peek scanner) (not (eq (emmet2-markup--peek scanner) ?\])))
      (if (memq (emmet2-markup--peek scanner) '(?\s ?\t ?\r ?\n))
          (cl-incf (emmet2-markup--scanner-pos scanner))
        (let ((name (emmet2-markup--literal scanner t)) value kind)
          (unless name
            (emmet2-markup--error scanner (if (eq (emmet2-markup--peek scanner) ?=)
                                              "Unexpected \"Operator\" token" "Unexpected character")))
          (when (emmet2-markup--eat scanner ?=)
            (cond
             ((memq (emmet2-markup--peek scanner) '(?\" ?\'))
              (setq kind 'quoted value (emmet2-markup--quoted scanner)))
             ((eq (emmet2-markup--peek scanner) ?\{)
              (setq kind 'expression value (emmet2-markup--text scanner)))
             (t (setq value (emmet2-markup--literal scanner t)))))
          (push (emmet2-markup--attribute :name name :value value :kind kind) attributes))))
    (emmet2-markup--eat scanner ?\])
    (nreverse attributes)))

(defun emmet2-markup--repeat (scanner)
  "Consume a repetition count from SCANNER, defaulting to one."
  (when (emmet2-markup--eat scanner ?*)
    (let ((start (emmet2-markup--scanner-pos scanner)))
      (while (let ((ch (emmet2-markup--peek scanner))) (and ch (<= ?0 ch ?9)))
        (cl-incf (emmet2-markup--scanner-pos scanner)))
      (max 1 (string-to-number (substring (emmet2-markup--scanner-text scanner)
                                          start (emmet2-markup--scanner-pos scanner)))))))

(defun emmet2-markup--element (scanner)
  "Read one element or group from SCANNER."
  (if (emmet2-markup--eat scanner ?\()
      (let ((node (emmet2-markup--statements scanner)))
        (emmet2-markup--eat scanner ?\))
        (setf (emmet2-markup--node-repeat node) (emmet2-markup--repeat scanner))
        node)
    (let ((start (emmet2-markup--scanner-pos scanner))
          (node (emmet2-markup--node :name (emmet2-markup--literal scanner))) done)
      (while (not done)
        (pcase (emmet2-markup--peek scanner)
          ((or ?. ?#)
           (let* ((name (if (emmet2-markup--eat scanner ?.) "class"
                          (emmet2-markup--eat scanner ?#) "id"))
                  (value (emmet2-markup--literal scanner)))
             (push (emmet2-markup--attribute :name (list name) :value value)
                   (emmet2-markup--node-attributes node))))
          (?\[ (cl-incf (emmet2-markup--scanner-pos scanner))
               (dolist (attr (emmet2-markup--attributes scanner))
                 (push attr (emmet2-markup--node-attributes node))))
          (?\{ (if (emmet2-markup--node-value node) (setq done t)
                 (setf (emmet2-markup--node-value node) (emmet2-markup--text scanner))))
          (?* (if (or (= start (emmet2-markup--scanner-pos scanner))
                      (emmet2-markup--node-repeat node))
                  (setq done t)
                (setf (emmet2-markup--node-repeat node) (emmet2-markup--repeat scanner))))
          (?/ (if (= start (emmet2-markup--scanner-pos scanner)) (setq done t)
                (cl-incf (emmet2-markup--scanner-pos scanner))
                (setf (emmet2-markup--node-self-closing node) t
                      (emmet2-markup--node-repeat node)
                      (or (emmet2-markup--repeat scanner) (emmet2-markup--node-repeat node)))
                (setq done t)))
          (_ (setq done t))))
      (setf (emmet2-markup--node-attributes node) (nreverse (emmet2-markup--node-attributes node)))
      (and (> (emmet2-markup--scanner-pos scanner) start) node))))

(defun emmet2-markup--statements (scanner)
  "Read a sequence of elements and child/sibling/climb operators from SCANNER."
  (let* ((root (emmet2-markup--node :group t)) (parent root) stack node)
    (while (setq node (emmet2-markup--element scanner))
      (push node (emmet2-markup--node-children parent))
      (cond
       ((emmet2-markup--eat scanner ?>) (push parent stack) (setq parent node))
       ((emmet2-markup--eat scanner ?+))
       ((emmet2-markup--eat scanner ?^)
        (when stack (setq parent (pop stack)))
        (while (emmet2-markup--eat scanner ?^) (when stack (setq parent (pop stack)))))))
    root))

(defun emmet2-markup--parse (text)
  "Parse markup abbreviation TEXT."
  (let* ((scanner (emmet2-markup--scanner text))
         (root (emmet2-markup--statements scanner)))
    (when (emmet2-markup--peek scanner) (emmet2-markup--error scanner "Unexpected character"))
    root))

(defun emmet2-markup--convert-value (tokens repeaters)
  "Resolve TOKENS with innermost-first REPEATERS and coalesce literal text.
Return fresh list cells so conversion never modifies shared syntax."
  (let (result literals)
    (cl-labels ((flush ()
                 (when literals
                   (push (apply #'concat (nreverse literals)) result)
                   (setq literals nil))))
      (dolist (token tokens)
        (when (vectorp token)
          (let* ((repeat (car repeaters))
                 (parent (and repeaters (nth (min (aref token 3) (1- (length repeaters))) repeaters)))
                 (value (if repeat
                            (+ (aref token 2) (if (aref token 1) (- (cdr repeat) (car repeat) 1) (car repeat)))
                          1)))
            (when (and parent (not (eq parent repeat))) (cl-incf value (* (cdr repeat) (car parent))))
            (setq token (format (concat "%0" (number-to-string (aref token 0)) "d") value))))
        (if (stringp token) (push token literals)
          (flush)
          (push token result)))
      (flush))
    (nreverse result)))

(defun emmet2-markup--convert (node &optional repeaters)
  "Convert parsed NODE into fresh nodes, unrolling with REPEATERS."
  (let ((count (or (emmet2-markup--node-repeat node) 1)) result)
    (dotimes (index count)
      (emmet2-engine--check-deadline)
      (let* ((context (if (emmet2-markup--node-repeat node) (cons (cons index count) repeaters) repeaters))
             (children (mapcan (lambda (child) (emmet2-markup--convert child context))
                               (reverse (emmet2-markup--node-children node)))))
        (if (emmet2-markup--node-group node)
            (dolist (child children) (push child result))
          (let ((copy (copy-emmet2-markup--node node)))
            (setf (emmet2-markup--node-name copy)
                  (when (emmet2-markup--node-name node)
                    (apply #'concat (emmet2-markup--convert-value (emmet2-markup--node-name node) context)))
                  (emmet2-markup--node-value copy)
                  (emmet2-markup--convert-value (emmet2-markup--node-value node) context)
                  (emmet2-markup--node-children copy) children
                  (emmet2-markup--node-attributes copy)
                  (mapcar
                   (lambda (attr)
                     (let* ((copy (copy-emmet2-markup--attribute attr))
                            (name (apply #'concat (emmet2-markup--convert-value (emmet2-markup--attribute-name attr) context)))
                            (implied (string-prefix-p "!" name)) (boolean (string-suffix-p "." name)))
                       (setf (emmet2-markup--attribute-name copy)
                             (substring name (if implied 1 0) (if boolean -1 nil))
                             (emmet2-markup--attribute-implied copy) implied
                             (emmet2-markup--attribute-boolean copy) boolean
                             (emmet2-markup--attribute-value copy)
                             (emmet2-markup--convert-value (emmet2-markup--attribute-value attr) context))
                       copy)) (emmet2-markup--node-attributes node)))
            (push copy result)
            ;; Text without a field cannot wrap children: conversion places
            ;; them after the text in the same parent, before formatting.
            (when (and (not (emmet2-markup--node-name copy))
                       (not (emmet2-markup--node-attributes copy))
                       (emmet2-markup--node-value copy)
                       (not (cl-some #'consp (emmet2-markup--node-value copy))))
              (setf (emmet2-markup--node-children copy) nil)
              (dolist (child children) (push child result)))))))
    (nreverse result)))

(defun emmet2-markup--resolve (nodes parsed &optional stack)
  "Resolve call-owned NODES with the request-local PARSED table and cycle STACK.
Only snippet syntax trees are shared within this call; conversion creates
fresh nodes before resolution or transformation can change them."
  (mapcan
   (lambda (node)
     (let ((snippet (gethash (emmet2-markup--node-name node) emmet2-markup--snippets)))
       (if (and snippet (not (member snippet stack)))
           (let* ((syntax (or (gethash snippet parsed)
                              (puthash snippet (emmet2-markup--parse snippet) parsed)))
                  (resolved (emmet2-markup--resolve
                             (emmet2-markup--convert syntax) parsed (cons snippet stack)))
                  (deepest (car (last resolved))))
             (dolist (top resolved)
               (setf (emmet2-markup--node-attributes top)
                     (append (emmet2-markup--node-attributes top) (emmet2-markup--node-attributes node)))
               (when (emmet2-markup--node-value node)
                 (setf (emmet2-markup--node-value top) (emmet2-markup--node-value node)))
               (when (emmet2-markup--node-self-closing node)
                 (setf (emmet2-markup--node-self-closing top) t)))
             (while (emmet2-markup--node-children deepest)
               (setq deepest (car (last (emmet2-markup--node-children deepest)))))
             (setf (emmet2-markup--node-children deepest)
                   (emmet2-markup--resolve (emmet2-markup--node-children node) parsed stack))
             resolved)
         (setf (emmet2-markup--node-children node)
               (emmet2-markup--resolve (emmet2-markup--node-children node) parsed stack))
         (list node)))) nodes))

(defun emmet2-markup--merge-attributes (attributes)
  "Return merged copies of ATTRIBUTES, keeping first position and last value."
  (let (result)
    (dolist (attr attributes)
      (let* ((name (emmet2-markup--attribute-name attr))
             (previous (cl-find name result :key #'emmet2-markup--attribute-name :test #'equal)))
        (if (not previous) (push (copy-emmet2-markup--attribute attr) result)
          (let ((value (emmet2-markup--attribute-value attr)))
            (setf (emmet2-markup--attribute-value previous)
                  (if (equal name "class")
                      (append (emmet2-markup--attribute-value previous)
                              (and (emmet2-markup--attribute-value previous) value '(" ")) value)
                    value)
                  (emmet2-markup--attribute-implied previous)
                  (and (emmet2-markup--attribute-implied previous) (emmet2-markup--attribute-implied attr))
                  (emmet2-markup--attribute-boolean previous)
                  (or (emmet2-markup--attribute-boolean previous) (emmet2-markup--attribute-boolean attr))
                  (emmet2-markup--attribute-kind previous)
                  (if (eq (emmet2-markup--attribute-kind previous) 'expression) 'expression
                    (emmet2-markup--attribute-kind attr)))))))
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
    (when (and (null (emmet2-markup--node-name node)) (emmet2-markup--node-attributes node))
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
              (and (emmet2-markup--node-value node) (not (emmet2-markup--node-attributes node))))))

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
        (expression (eq (emmet2-markup--attribute-kind attr) 'expression)))
    (when (and name (or (not (emmet2-markup--attribute-implied attr))
                       (emmet2-markup--attribute-kind attr) value))
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
           (nodes (emmet2-markup--resolve (emmet2-markup--convert (emmet2-markup--parse abbreviation))
                                           (make-hash-table :test #'equal)))
           (out (emmet2-markup--output indent base-indent jsx)))
      (emmet2-markup--transform nodes)
      (emmet2-markup--emit out nodes)
      (emmet2-markup--result out))))

(provide 'emmet2-engine-markup)
;;; emmet2-engine-markup.el ends here
