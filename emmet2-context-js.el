;;; emmet2-context-js.el --- JSX and CSS-in-JS context with tree-sitter -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Find JSX markup and CSS-in-JS objects with tree-sitter.  Each buffer keeps
;; two parsers per language: one reads the source, the other the projection,
;; which is the source with the abbreviation reduced to one identifier
;; character, so the surrounding syntax can be checked without it.  Markers
;; remember the unit, the smallest closed statement or JSX element around
;; point, which limits later parsing.  An idle timer warms the parsers for
;; automatic completion.  web-mode supplies the bounds of script parts.

;;; Code:

(require 'cl-lib)
(require 'treesit)
(require 'emmet2-engine)
(require 'emmet2-extract)
(require 'emmet2-context-web)

(defvar emmet2-mode)
(defvar emmet2-context-provider)

(defcustom emmet2-css-in-js-functions '("StyleSheet.create" "createTheme")
  "Functions whose object arguments hold CSS-in-JS declarations.
Write each callee as it appears in source, such as \"css\" or \"stylex.create\"."
  :type '(repeat string) :safe #'list-of-strings-p :group 'emmet2)

(defcustom emmet2-css-in-js-attributes '("style")
  "JSX attributes whose object values hold CSS-in-JS declarations, such as \"sx\"."
  :type '(repeat string) :safe #'list-of-strings-p :group 'emmet2)

(cl-defstruct (emmet2-context-js--state (:constructor emmet2-context-js--state-create))
  buffer (tag (make-symbol "emmet2"))
  (projection-tag (make-symbol "emmet2-projection")) timer units tick)
(defvar-local emmet2-context-js--state nil)

(defconst emmet2-context-js--queries
  (when (treesit-available-p)
    (mapcar
     (lambda (language)
       (list language
             (treesit-query-compile language
                                    '([(object) (pair) (return_statement) (arrow_function)
                                       (parenthesized_expression)] @host))
             (unless (eq language 'typescript)
               (treesit-query-compile language '([(jsx_opening_element) (jsx_expression)] @host)))
             (unless (eq language 'typescript)
               (treesit-query-compile language '([(jsx_expression) (object)] @expression)))
             (treesit-query-compile language '((ERROR (regex_pattern) @pattern)))))
     '(tsx javascript typescript)))
  "Compiled tree-sitter queries per language: (LANGUAGE HOST JSX OBJECT REGEX).
HOST captures enclosing objects, pairs, returns and arrow functions; JSX
captures JSX opening tags and expressions; OBJECT captures JSX expressions
and objects; REGEX captures regex patterns inside errors.  The typescript
entry has no JSX or OBJECT query.  Compilation is lazy, and the queries hold
no buffer state.")

(defun emmet2-context-js--owner (&optional create)
  "Return this buffer's context owner, allocating it when CREATE is non-nil.
Indirect buffers copy local variables but share their base's parser storage;
verify owner identity and give each view its own tag, without shared cleanup."
  (if (and (emmet2-context-js--state-p emmet2-context-js--state)
           (eq (emmet2-context-js--state-buffer emmet2-context-js--state) (current-buffer)))
      emmet2-context-js--state
    (when create
      (setq emmet2-context-js--state
            (emmet2-context-js--state-create :buffer (current-buffer) :tick (buffer-chars-modified-tick)))
      (add-hook 'kill-buffer-hook #'emmet2-context-js-stop nil t)
      (add-hook 'change-major-mode-hook #'emmet2-context-js-stop nil t)
      (add-hook 'before-change-functions #'emmet2-context-js--before-change nil t)
      (add-hook 'after-change-functions #'emmet2-context-js--after-change nil t)
      emmet2-context-js--state)))

(defun emmet2-context-js--forget-units (owner &optional language)
  "Detach OWNER's unit markers, optionally for only LANGUAGE."
  (setf (emmet2-context-js--state-units owner)
        (cl-delete-if
         (lambda (entry)
           (when (or (not language) (eq (car entry) language))
             (set-marker (cadr entry) nil) (set-marker (caddr entry) nil)
             t))
         (emmet2-context-js--state-units owner))))

(defun emmet2-context-js--remember-unit (owner language bounds)
  "Replace OWNER's LANGUAGE unit with marker-backed BOUNDS."
  (emmet2-context-js--forget-units owner language)
  (push (list language (copy-marker (car bounds)) (copy-marker (cdr bounds) t))
        (emmet2-context-js--state-units owner)))

(defun emmet2-context-js--check-tick (owner)
  "Invalidate OWNER after an edit that bypassed this view's hooks.
Return non-nil when the remembered units were stale."
  (unless (eql (emmet2-context-js--state-tick owner) (buffer-chars-modified-tick))
    (emmet2-context-js--forget-units owner)
    (setf (emmet2-context-js--state-tick owner) (buffer-chars-modified-tick))))

(defun emmet2-context-js--before-change (beg end)
  "Invalidate units crossed by the edit at BEG..END."
  (when-let* ((owner (emmet2-context-js--owner)))
    (emmet2-context-js--check-tick owner)
    (dolist (entry (copy-sequence (emmet2-context-js--state-units owner)))
      (unless (and (< (marker-position (cadr entry)) beg)
                   (< end (marker-position (caddr entry))))
        (emmet2-context-js--forget-units owner (car entry))))))

(defun emmet2-context-js--after-change (_beg _end _length)
  "Record an ordinary edit after markers have followed the change."
  (when-let* ((owner (emmet2-context-js--owner)))
    (setf (emmet2-context-js--state-tick owner) (buffer-chars-modified-tick))))

(defun emmet2-context-js--parsers ()
  "Return only parsers belonging to this buffer's context owner."
  (when (treesit-available-p)
    (when-let* ((owner (emmet2-context-js--owner)))
      (append (treesit-parser-list nil nil (emmet2-context-js--state-tag owner))
              (treesit-parser-list nil nil (emmet2-context-js--state-projection-tag owner))))))

(defun emmet2-context-js-stop ()
  "Cancel this buffer's warmup and delete only its owned parsers."
  (when-let* ((owner (emmet2-context-js--owner)))
    (when-let* ((timer (emmet2-context-js--state-timer owner))) (cancel-timer timer))
    (emmet2-context-js--forget-units owner)
    (dolist (parser (emmet2-context-js--parsers)) (treesit-parser-delete parser)))
  (setq emmet2-context-js--state nil)
  (remove-hook 'kill-buffer-hook #'emmet2-context-js-stop t)
  (remove-hook 'change-major-mode-hook #'emmet2-context-js-stop t)
  (remove-hook 'before-change-functions #'emmet2-context-js--before-change t)
  (remove-hook 'after-change-functions #'emmet2-context-js--after-change t))

(defun emmet2-context-js--parser (language initialize &optional projection)
  "Return the owned LANGUAGE parser.
INITIALIZE permits creation or a missing-grammar error.  PROJECTION selects
the second tree; keeping each input view stable avoids full reparses."
  (let* ((owner (emmet2-context-js--owner))
         (tag (when owner (if projection (emmet2-context-js--state-projection-tag owner)
                            (emmet2-context-js--state-tag owner))))
         (parser (when (and tag (treesit-available-p))
                   (car (treesit-parser-list nil language tag)))))
    (or parser
        (when initialize
          (unless (and (treesit-available-p) (treesit-language-available-p language))
            (signal 'emmet2-error (list (format "Missing tree-sitter grammar: %s" language))))
          (setq owner (emmet2-context-js--owner t))
          (treesit-parser-create language nil nil
                                 (if projection (emmet2-context-js--state-projection-tag owner)
                                   (emmet2-context-js--state-tag owner)))))))

(defun emmet2-context-js-revision ()
  "Return the user options that select CSS-in-JS hosts."
  (list emmet2-css-in-js-functions emmet2-css-in-js-attributes))

(defun emmet2-context-js-region ()
  "Return (LANGUAGE BEG END) for a supported JS host at point, or nil."
  (if (derived-mode-p 'web-mode)
      (let ((region (emmet2-context-web-region)))
        (when (memq (car region) '(javascript typescript tsx)) region))
    (when-let* ((language (cond ((derived-mode-p 'tsx-ts-mode) 'tsx)
                                ((derived-mode-p 'typescript-ts-mode) 'typescript)
                                ((derived-mode-p 'js-mode 'js-ts-mode) 'javascript))))
      (list language (point-min) (point-max)))))

(defun emmet2-context-js-prepare ()
  "Create and parse this buffer's JS parsers for the region at point.
Also compile the queries, so automatic analysis finds everything ready.
Return the source parser, or nil without a JS region or grammar.
`emmet2-context-js-start' runs this from an idle timer."
  (save-restriction
    (widen)
    (when-let* ((region (emmet2-context-js-region)))
      (pcase-let ((`(,language ,beg ,end) region))
        (when (and (treesit-available-p) (treesit-language-available-p language))
          (dolist (query (cdr (assq language emmet2-context-js--queries)))
            (when query (treesit-query-compile language query t)))
          (let* ((parser (emmet2-context-js--parser language t))
                 (unit (emmet2-context-js--unit language beg end parser t))
                 (projection (emmet2-context-js--parser language t t)))
            (treesit-parser-set-included-ranges projection (list (cons (car unit) (cdr unit))))
            (treesit-parser-root-node projection))
          (emmet2-context-js--parser language nil))))))

(defun emmet2-context-js--closed-unit-p (node start end)
  "Whether NODE spans START..END as a closed statement or JSX element.
Require a real terminal delimiter or, for semicolon-free code, a real last
token ending its line; never tree-sitter error recovery.  Internal errors can
be the abbreviation itself; projection checks the remaining syntax."
  (let ((child (and (equal (treesit-node-type node) "expression_statement")
                    (treesit-node-child node 0 t))))
    ;; A JSX unit parsed alone is wrapped in an unterminated statement.
    (when (member (treesit-node-type child) '("jsx_element" "jsx_self_closing_element"))
      (setq node child)))
  (and node
       (= (treesit-node-start node) start) (= (treesit-node-end node) end)
       (member (treesit-node-type node)
               '("lexical_declaration" "variable_declaration" "function_declaration"
                 "class_declaration" "export_statement" "expression_statement"
                 "jsx_element" "jsx_self_closing_element"))
       (let ((last (treesit-node-child
                    (or (treesit-node-child-by-field-name node "declaration") node) -1)))
         (when (member (treesit-node-type last) '("statement_block" "class_body" "jsx_closing_element"))
           (setq last (treesit-node-child last -1)))
         (and last (not (treesit-node-check last 'missing))
              (or (member (treesit-node-type last) '(";" "}" ">" "/>"))
                  ;; Tree-sitter's automatic semicolon is a hidden zero-width token.
                  (save-excursion (goto-char end) (skip-chars-forward " \t") (eolp)))))))

(defun emmet2-context-js--tree-unit (parser position)
  "Return (START . END) of the closed unit around POSITION in PARSER, or nil.
The unit is the nearest JSX element or top-level statement, and it must have
no syntax errors."
  (let* ((root (treesit-parser-root-node parser))
         (node (treesit-node-on position (min (point-max) (1+ position)) parser t)))
    (while (and (treesit-node-parent node)
                (not (treesit-node-eq (treesit-node-parent node) root))
                (not (and (member (treesit-node-type node) '("jsx_element" "jsx_self_closing_element"))
                          (not (treesit-node-check node 'has-error)))))
      (setq node (treesit-node-parent node)))
    (when (and (not (treesit-node-check node 'has-error))
               (emmet2-context-js--closed-unit-p node (treesit-node-start node) (treesit-node-end node)))
      (cons (treesit-node-start node) (treesit-node-end node)))))

(defun emmet2-context-js--unit (language start end parser initialize)
  "Return the remembered LANGUAGE unit around point within START..END.
Restrict PARSER to that unit.  Without one, non-nil INITIALIZE uses all of
START..END; only a valid projection later narrows it."
  (let* ((owner (emmet2-context-js--owner t)) entry bounds)
    (emmet2-context-js--check-tick owner)
    (setq entry (assq language (emmet2-context-js--state-units owner)))
    (when entry
      (setq bounds (cons (marker-position (cadr entry)) (marker-position (caddr entry))))
      (unless (<= start (car bounds) (point) (cdr bounds) end)
        (emmet2-context-js--forget-units owner language)
        (setq bounds nil)))
    (when bounds
      (treesit-parser-set-included-ranges parser (list bounds)))
    (when (and (not bounds) initialize)
      (treesit-parser-set-included-ranges parser (list (cons start end)))
      (setq bounds (cons start end))
      (emmet2-context-js--remember-unit owner language bounds)
      (treesit-parser-root-node parser))
    bounds))

(defun emmet2-context-js--warm (buffer owner)
  "Warm BUFFER only while OWNER still belongs to an enabled mode."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (eq (emmet2-context-js--owner) owner)
        (setf (emmet2-context-js--state-timer owner) nil)
        (when (and (bound-and-true-p emmet2-mode) (not emmet2-context-provider))
          (emmet2-context-js-prepare))))))

(defun emmet2-context-js-start ()
  "Schedule one buffer-owned idle warmup.
Repeated invocations do not add timers.  External and lexical-only hosts
need no JS owner, edit hooks or idle work."
  (when (and (not emmet2-context-provider)
             (derived-mode-p 'web-mode 'js-mode 'js-ts-mode 'tsx-ts-mode 'typescript-ts-mode))
    (let ((owner (emmet2-context-js--owner t)))
      (unless (emmet2-context-js--state-timer owner)
        (setf (emmet2-context-js--state-timer owner)
              (run-with-idle-timer 0.1 nil #'emmet2-context-js--warm (current-buffer) owner))))))

(defun emmet2-context-js--host-region (parser start end language)
  "Return (LEFT . RIGHT), the part of this line where an abbreviation may lie.
PARSER's tree of START..END and LANGUAGE's queries move LEFT past enclosing
syntax; the extractor still decides the exact bounds."
  (let ((left (max start (line-beginning-position)))
        (right (min end (line-end-position)))
        (position (point)))
    (dolist (node (treesit-query-capture
                   parser (nth 1 (assq language emmet2-context-js--queries))
                   left right t))
      (when (and (<= (treesit-node-start node) position)
                 (or (<= position (treesit-node-end node))
                     ;; m10+p.5 may close its object early with a MISSING }; keep that real opening boundary.
                     (and (equal (treesit-node-type node) "object")
                          (let ((last (treesit-node-child node -1)))
                            (and (equal (treesit-node-type last) "}")
                                 (treesit-node-check last 'missing))))))
        (pcase (treesit-node-type node)
          ("pair"
           ;; Keep authored keys and colons; this lower bound is checked again in the projection.
           (when (emmet2-context-js--css-owner-p node t)
             (let ((value (treesit-node-child-by-field-name node "value")))
               (when (and value (<= (treesit-node-start value) position))
                 (setq left (max left (treesit-node-start value)))))))
          ("object"
           (let ((begin (treesit-node-start node)))
             ;; Broken JSX such as a{Link $} can recover as an object under ERROR; keep the attached text.
             (unless (and (not (eq language 'typescript))
                          (equal (treesit-node-type (treesit-node-parent node)) "ERROR")
                          (not (memq (char-before begin)
                                     '(nil ?> ?\s ?\t ?\n ?{ ?= ?\( ?\[ ?: ?,))))
               (setq left (max left (1+ begin))))))
          ((or "arrow_function" "return_statement")
           (let ((body (if (equal (treesit-node-type node) "arrow_function")
                           (treesit-node-child-by-field-name node "body")
                         (treesit-node-child node 0 t))))
             (when (and body (<= (treesit-node-start body) position))
               (setq left (max left (treesit-node-start body))))))
          ("parenthesized_expression"
           (when (member (treesit-node-type (treesit-node-parent node))
                         '("arrow_function" "return_statement"))
             (setq left (max left (1+ (treesit-node-start node)))))))))
    (unless (eq language 'typescript)
      (dolist (node (treesit-query-capture
                     parser (nth 2 (assq language emmet2-context-js--queries))
                     (line-beginning-position) right t))
        (pcase (treesit-node-type node)
          ("jsx_opening_element"
           (when (<= (treesit-node-end node) position)
             (setq left (max left (treesit-node-end node)))))
          ("jsx_expression"
           (let ((begin (treesit-node-start node)))
             ;; A brace attached to the abbreviation is Emmet text; a leading JSX brace stays outside.
             (when (and (<= begin position (treesit-node-end node))
                        (or (= begin start)
                            (memq (char-before begin) '(?> ?\s ?\t ?\n ?{ ?=))))
               (setq left (max left (1+ begin)))))))))
    (cons left right)))

(defun emmet2-context-js--css-owner-p (node &optional allow-errors)
  "Whether NODE lies in an object of a configured CSS-in-JS host.
Hosts are the JSX attributes in `emmet2-css-in-js-attributes' and the calls
in `emmet2-css-in-js-functions'.  Non-nil ALLOW-ERRORS accepts objects with
syntax errors, for bounds in the source tree only."
  (let ((parent (treesit-node-parent node)) result done)
    (while (and parent (not done))
      (pcase (treesit-node-type parent)
        ((or "object" "pair")
         (when (and (not allow-errors) (treesit-node-check parent 'has-error)) (setq done t)))
        ("jsx_expression"
         (let ((attribute (treesit-node-parent parent)))
           (setq result
                 (and (equal (treesit-node-type attribute) "jsx_attribute")
                      (member (treesit-node-text (treesit-node-child attribute 0 t) t)
                              emmet2-css-in-js-attributes))
                 done t)))
        ("arguments"
         (let* ((call (treesit-node-parent parent))
                (function (treesit-node-child-by-field-name call "function")))
           (setq result (and function
                             (member (treesit-node-text function t)
                                     emmet2-css-in-js-functions))
                 done t)))
        (_ (setq done t)))
      (setq parent (treesit-node-parent parent)))
    (and result t)))

(defun emmet2-context-js--projected (parser anchor automatic)
  "Return markup, css-in-js or nil for the projected node at ANCHOR in PARSER.
Non-nil AUTOMATIC rejects a bare identifier returned from a function, which
explicit requests treat as markup."
  (let* ((node (treesit-node-on anchor (1+ anchor) parser t))
         (parent (treesit-node-parent node)))
    (pcase (treesit-node-type node)
      ("jsx_text"
       (when (and (equal (treesit-node-type parent) "jsx_element")
                  (not (treesit-node-check parent 'has-error)))
         'markup))
      ("shorthand_property_identifier"
       (when (emmet2-context-js--css-owner-p node) 'css-in-js))
      ("identifier"
       (while (equal (treesit-node-type parent) "parenthesized_expression")
         (setq node parent parent (treesit-node-parent parent)))
       (when (and (not automatic)
                  (or (equal (treesit-node-type parent) "return_statement")
                      (and (equal (treesit-node-type parent) "arrow_function")
                           (treesit-node-eq node (treesit-node-child-by-field-name parent "body")))))
         'markup)))))

(defun emmet2-context-js--ambiguous-text-p (parser beg end language)
  "Whether PARSER projection at BEG..END would erase a JSX expression.
Detect expressions after plain text, and expressions starting at or after
point, which the typed abbreviation merely touches.  Include objects produced
by error recovery, which carry the same ambiguity.  LANGUAGE without JSX
cannot have this ambiguity.  The explicit command may interpret tag{text} as
Emmet; automatic completion must leave it alone."
  (unless (eq language 'typescript)
    (cl-some
     (lambda (node)
       (let ((brace (treesit-node-start node)))
         (and (< beg brace end)
              (or (>= brace (point))
                  (string-match-p "\\`[[:alnum:]_-]+\\'"
                                  (buffer-substring-no-properties beg brace))))))
     (treesit-query-capture parser (nth 3 (assq language emmet2-context-js--queries)) beg end t))))

(defun emmet2-context-js--forbidden-origin-p (parser beg)
  "Return non-nil for BEG inside a host string, comment or regex in PARSER."
  (let ((node (treesit-node-on beg (1+ beg) parser t)) found)
    (while (and node (not found))
      (when (member (treesit-node-type node) '("string" "template_string" "comment" "regex"))
        (setq found t))
      (setq node (treesit-node-parent node)))
    (or found
        ;; An unterminated /* can parse as a regex ending at a later JSX slash; treat it as a comment.
        (and (treesit-node-check (treesit-parser-root-node parser) 'has-error)
             (cl-some
              (lambda (pattern)
                (let ((start (treesit-node-start pattern)))
                  (and (eq (char-before start) ?/) (eq (char-after start) ?*)
                       (< start beg)
                       (not (save-excursion
                              (goto-char start) (search-forward "*/" beg t))))))
              (treesit-query-capture
               parser (nth 4 (assq (treesit-parser-language parser) emmet2-context-js--queries))
               nil beg t))))))

(defun emmet2-context-js-analyze (region automatic)
  "Return the JSX or CSS-in-JS abbreviation context at point in REGION.
REGION is (LANGUAGE START END).  Return nil when the position does not
allow expansion.  Non-nil AUTOMATIC uses only parsers that are already
warm, scheduling warmup otherwise, and skips text that could be a JSX
expression.  With nil AUTOMATIC, missing parsers are created, and a missing
grammar signals `emmet2-error'."
  (pcase-let* ((`(,language ,start ,end) region)
               (parser (emmet2-context-js--parser language (not automatic)))
               (projection (emmet2-context-js--parser language (not automatic) t))
               (unit (when parser (emmet2-context-js--unit language start end parser (not automatic)))))
    (if (not (and unit projection))
        (progn
          (when (bound-and-true-p emmet2-mode) (emmet2-context-js-start))
          nil)
      (let ((bounded (not (equal unit (cons start end)))))
        (setq start (car unit) end (cdr unit))
        (pcase-let* ((`(,left . ,right) (emmet2-context-js--host-region parser start end language))
                     (candidate (emmet2-extract left right))
                     (beg (plist-get candidate :beg)) (finish (plist-get candidate :end)))
          (when (and candidate (< beg finish)
                     (not (emmet2-context-js--forbidden-origin-p parser beg))
                     (not (and automatic (emmet2-context-js--ambiguous-text-p parser beg finish language))))
            (let ((anchor (save-excursion
                            (goto-char beg)
                            (if (re-search-forward "[A-Za-z_]" finish t) (1- (point))
                              ;; A bare . or # names a class or id of an implicit div, but only in
                              ;; JSX text; checking the source tree first avoids reparsing for JS.
                              (and (memq (char-after beg) '(?. ?#))
                                   (equal (treesit-node-type (treesit-node-at beg parser)) "jsx_text")
                                   beg)))))
              (when anchor
                (treesit-parser-set-included-ranges
                 projection (delq nil (list (and (< start beg) (cons start beg))
                                            (cons anchor (1+ anchor))
                                            (and (< finish end) (cons finish end)))))
                (if (and bounded
                         (let ((root (treesit-parser-root-node projection)))
                           (not (and (not (treesit-node-check root 'has-error))
                                     (= (treesit-node-child-count root t) 1)
                                     (emmet2-context-js--closed-unit-p
                                      (treesit-node-child root 0 t) start end)))))
                    (progn
                      ;; Retry once with the whole region, so unrelated syntax errors cannot hide a valid position.
                      (emmet2-context-js--remember-unit
                       (emmet2-context-js--owner) language (cons (nth 1 region) (nth 2 region)))
                      (emmet2-context-js-analyze region automatic))
                  (progn
                    (when-let* ((refined (emmet2-context-js--tree-unit projection anchor)))
                      (unless (equal refined unit)
                        (emmet2-context-js--remember-unit (emmet2-context-js--owner) language refined)))
                    (when-let* ((context (emmet2-context-js--projected projection anchor automatic)))
                      (append candidate (list :lang context :syntax 'jsx
                                              :position (if (eq context 'css-in-js)
                                                            'declaration-start 'markup))))))))))))))

(provide 'emmet2-context-js)
;;; emmet2-context-js.el ends here
