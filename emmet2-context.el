;;; emmet2-context.el --- Host classification and parser ownership -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; The extractor alone chooses bounds.  This module first obtains host limits,
;; then confirms the candidate without erasing its enclosing host structure.
;; Parser inventories are derived from Emacs, never mirrored in a second cache.

;;; Code:

(require 'cl-lib)
(require 'treesit)
(require 'css-mode)
(require 'emmet2-engine)
(require 'emmet2-extract)

(defvar emmet2-mode)
(defvar web-mode-change-beg)
(defvar web-mode-change-end)
(defvar web-mode-content-type)
(defvar web-mode-engine)
(declare-function web-mode-scan "web-mode")
(declare-function web-mode-scan-region "web-mode")
(declare-function web-mode-css-rule-current "web-mode")
(declare-function web-mode-language-at-pos "web-mode")
(declare-function web-mode-part-beginning-position "web-mode")
(declare-function web-mode-part-end-position "web-mode")
(declare-function web-mode-attribute-beginning-position "web-mode")
(declare-function web-mode-tag-beginning-position "web-mode")
(declare-function web-mode-attribute-next-position "web-mode")

(cl-defstruct (emmet2-context--state (:constructor emmet2-context--state-create))
  buffer (tag (make-symbol "emmet2"))
  (projection-tag (make-symbol "emmet2-projection")) timer units tick web-insertion)
(defvar-local emmet2-context--state nil)

(defconst emmet2-context--queries
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
  "Ten fixed queries, lazily compiled for their grammars.
They have module lifetime and no source-dependent invalidation.  Parser trees
remain buffer owned; these queries retain no analysis results or source nodes.")

(defun emmet2-context--owner (&optional create)
  "Return this buffer's context owner, allocating it when CREATE is non-nil.
Indirect buffers copy local variables but share their base's parser storage;
verify owner identity and give each view its own tag, without shared cleanup."
  (if (and (emmet2-context--state-p emmet2-context--state)
           (eq (emmet2-context--state-buffer emmet2-context--state) (current-buffer)))
      emmet2-context--state
    (when create
      (setq emmet2-context--state
            (emmet2-context--state-create :buffer (current-buffer) :tick (buffer-chars-modified-tick)))
      (add-hook 'kill-buffer-hook #'emmet2-context-stop nil t)
      (add-hook 'change-major-mode-hook #'emmet2-context-stop nil t)
      (add-hook 'before-change-functions #'emmet2-context--before-change nil t)
      (add-hook 'after-change-functions #'emmet2-context--after-change nil t)
      emmet2-context--state)))

(defun emmet2-context--forget-units (owner &optional language)
  "Detach OWNER's unit markers, optionally for only LANGUAGE."
  (setf (emmet2-context--state-units owner)
        (cl-delete-if
         (lambda (entry)
           (when (or (not language) (eq (car entry) language))
             (set-marker (cadr entry) nil) (set-marker (caddr entry) nil)
             t))
         (emmet2-context--state-units owner))))

(defun emmet2-context--remember-unit (owner language bounds)
  "Replace OWNER's LANGUAGE unit with marker-backed BOUNDS."
  (emmet2-context--forget-units owner language)
  (push (list language (copy-marker (car bounds)) (copy-marker (cdr bounds) t))
        (emmet2-context--state-units owner)))

(defun emmet2-context--check-tick (owner)
  "Invalidate OWNER after an edit that bypassed this view's hooks.
Return non-nil when evidence was stale."
  (unless (eql (emmet2-context--state-tick owner) (buffer-chars-modified-tick))
    (emmet2-context--forget-units owner)
    (emmet2-context--forget-web-insertion owner)
    (setf (emmet2-context--state-tick owner) (buffer-chars-modified-tick))))

(defun emmet2-context--forget-web-insertion (owner)
  "Release OWNER's single pending CSS scan extent."
  (when-let* ((entry (emmet2-context--state-web-insertion owner)))
    (set-marker (nth 2 entry) nil) (set-marker (nth 3 entry) nil)
    (setf (emmet2-context--state-web-insertion owner) nil)))

(defun emmet2-context--remember-web-insertion (owner beg end)
  "Remember in OWNER a scanned CSS rule before insertion at BEG..END.
The one pending entry is (EDIT-BEG EDIT-END RULE-BEG RULE-END EXPECTED-TICK).
EDIT-END is filled only after a single ordinary character was inserted."
  (emmet2-context--forget-web-insertion owner)
  (when (and (= beg end) (derived-mode-p 'web-mode)
             (equal web-mode-engine "none") (equal web-mode-content-type "html")
             (not web-mode-change-beg))
    (save-match-data
      (save-excursion
        (save-restriction
          (widen)
          (when (and (> beg (point-min))
                     (eq (get-text-property beg 'part-side) 'css)
                     (eq (get-text-property (1- beg) 'part-side) 'css))
            (let ((rule (web-mode-css-rule-current beg)))
              (when (and (car rule) (cdr rule) (< (car rule) beg (cdr rule))
                         ;; Completing an existing </sty...> could end a part.
                         (not (progn (goto-char (car rule))
                                     (re-search-forward "[<>]" (cdr rule) t))))
                (setf (emmet2-context--state-web-insertion owner)
                      (list beg nil (copy-marker (car rule)) (copy-marker (cdr rule) t)
                            (1+ (buffer-modified-tick))))))))))))

(defun emmet2-context--before-change (beg end)
  "Invalidate affected units and remember a possible insertion at BEG..END."
  (when-let* ((owner (emmet2-context--owner)))
    (unless (emmet2-context--check-tick owner)
      (emmet2-context--remember-web-insertion owner beg end))
    (dolist (entry (copy-sequence (emmet2-context--state-units owner)))
      (unless (and (< (marker-position (cadr entry)) beg)
                   (< end (marker-position (caddr entry))))
        (emmet2-context--forget-units owner (car entry))))))

(defun emmet2-context--after-change (beg end length)
  "Record the edit at BEG..END replacing LENGTH characters.
Markers already follow valid interior changes."
  (when-let* ((owner (emmet2-context--owner)))
    (when-let* ((entry (emmet2-context--state-web-insertion owner)))
      (if (and (zerop length) (= beg (car entry)) (= end (1+ beg))
               (= (buffer-chars-modified-tick) (nth 4 entry))
               (let ((char (char-after beg)))
                 (or (<= ?a char ?z) (<= ?A char ?Z) (<= ?0 char ?9) (memq char '(?_ ?-)))))
          (setcar (cdr entry) end)
        (emmet2-context--forget-web-insertion owner)))
    (setf (emmet2-context--state-tick owner) (buffer-chars-modified-tick))))

(defun emmet2-context--scan-web ()
  "Flush web-mode's pending scan, using proven CSS insertion bounds if valid.
Tokenization belongs to `web-mode'.  Acknowledge its pending range only after a
successful scan of that exact edit; preserve it on errors."
  (let ((owner (emmet2-context--owner)))
    (when owner (emmet2-context--check-tick owner))
    (let ((entry (when owner (emmet2-context--state-web-insertion owner))))
      (unwind-protect
          (when web-mode-change-beg
            (if (and entry (equal web-mode-engine "none") (equal web-mode-content-type "html")
                     (eql web-mode-change-beg (car entry))
                     (eql web-mode-change-end (cadr entry)))
                (progn
                  (web-mode-scan-region (marker-position (nth 2 entry))
                                        (marker-position (nth 3 entry)) "css")
                  (setq web-mode-change-beg nil web-mode-change-end nil))
              (web-mode-scan)))
        (when owner (emmet2-context--forget-web-insertion owner))))))

(defun emmet2-context--parsers ()
  "Return only parsers belonging to this buffer's context owner."
  (when (treesit-available-p)
    (when-let* ((owner (emmet2-context--owner)))
      (append (treesit-parser-list nil nil (emmet2-context--state-tag owner))
              (treesit-parser-list nil nil (emmet2-context--state-projection-tag owner))))))

(defun emmet2-context-stop ()
  "Cancel this buffer's warmup and delete only its owned parsers."
  (when-let* ((owner (emmet2-context--owner)))
    (when-let* ((timer (emmet2-context--state-timer owner))) (cancel-timer timer))
    (emmet2-context--forget-units owner)
    (emmet2-context--forget-web-insertion owner)
    (dolist (parser (emmet2-context--parsers)) (treesit-parser-delete parser)))
  (setq emmet2-context--state nil)
  (remove-hook 'kill-buffer-hook #'emmet2-context-stop t)
  (remove-hook 'change-major-mode-hook #'emmet2-context-stop t)
  (remove-hook 'before-change-functions #'emmet2-context--before-change t)
  (remove-hook 'after-change-functions #'emmet2-context--after-change t))

(defun emmet2-context--parser (language initialize &optional projection)
  "Return the owned LANGUAGE parser.
INITIALIZE permits creation or a missing-grammar error.  PROJECTION selects
the second tree; keeping each input view stable avoids full reparses."
  (let* ((owner (emmet2-context--owner))
         (tag (when owner (if projection (emmet2-context--state-projection-tag owner)
                            (emmet2-context--state-tag owner))))
         (parser (when (and tag (treesit-available-p))
                   (car (treesit-parser-list nil language tag)))))
    (or parser
        (when initialize
          (unless (and (treesit-available-p) (treesit-language-available-p language))
            (signal 'emmet2-error (list (format "Missing tree-sitter grammar: %s" language))))
          (setq owner (emmet2-context--owner t))
          (treesit-parser-create language nil nil
                                 (if projection (emmet2-context--state-projection-tag owner)
                                   (emmet2-context--state-tag owner)))))))

(defun emmet2-context--js-region ()
  "Return (LANGUAGE BEG END) for a supported JS host at point, or nil."
  (let ((start (point-min)) (end (point-max)) language)
    (cond
     ((derived-mode-p 'web-mode)
      (emmet2-context--scan-web)
      (let ((part (web-mode-language-at-pos)))
        (setq language (cond ((equal part "typescript") 'typescript)
                             ((member part '("jsx" "tsx")) 'tsx)
                             ((equal part "javascript") 'javascript)))
        (when (equal web-mode-content-type "jsx") (setq language 'tsx))
        (unless (member web-mode-content-type '("jsx" "javascript" "typescript"))
          (setq start (web-mode-part-beginning-position) end (web-mode-part-end-position)))))
     ((derived-mode-p 'tsx-ts-mode) (setq language 'tsx))
     ((derived-mode-p 'typescript-ts-mode) (setq language 'typescript))
     ((derived-mode-p 'js-mode 'js-ts-mode) (setq language 'javascript)))
    (when (and language start end (<= start (point) end))
      (list language (max start (point-min)) (min end (point-max))))))

(defun emmet2-context--prepare ()
  "Prepare the current JS region during idle time.
Return its parser when the grammar is available."
  (save-restriction
    (widen)
    (when-let* ((region (emmet2-context--js-region)))
      (pcase-let ((`(,language ,beg ,end) region))
        (when (and (treesit-available-p) (treesit-language-available-p language))
          (dolist (query (cdr (assq language emmet2-context--queries)))
            (when query (treesit-query-compile language query t)))
          (let* ((parser (emmet2-context--parser language t))
                 (unit (emmet2-context--unit language beg end parser t))
                 (projection (emmet2-context--parser language t t)))
            (treesit-parser-set-included-ranges projection (list (cons (car unit) (cdr unit))))
            (treesit-parser-root-node projection))
          (emmet2-context--parser language nil))))))

(defun emmet2-context--closed-unit-p (node start end)
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

(defun emmet2-context--tree-unit (parser position)
  "Find a closed unit containing POSITION in PARSER.
Require complete valid projected syntax; select the nearest JSX element or
top-level declaration.  Full-host analysis established the original identity."
  (let* ((root (treesit-parser-root-node parser))
         (node (treesit-node-on position (min (point-max) (1+ position)) parser t)))
    (while (and (treesit-node-parent node)
                (not (treesit-node-eq (treesit-node-parent node) root))
                (not (and (member (treesit-node-type node) '("jsx_element" "jsx_self_closing_element"))
                          (not (treesit-node-check node 'has-error)))))
      (setq node (treesit-node-parent node)))
    (when (and (not (treesit-node-check node 'has-error))
               (emmet2-context--closed-unit-p node (treesit-node-start node) (treesit-node-end node)))
      (cons (treesit-node-start node) (treesit-node-end node)))))

(defun emmet2-context--unit (language start end parser initialize)
  "Return confirmed LANGUAGE unit bounds within START..END for PARSER.
INITIALIZE permits full-host discovery.  Only a later confirmed projection
can replace the full host with a smaller unit."
  (let* ((owner (emmet2-context--owner t)) entry bounds)
    (emmet2-context--check-tick owner)
    (setq entry (assq language (emmet2-context--state-units owner)))
    (when entry
      (setq bounds (cons (marker-position (cadr entry)) (marker-position (caddr entry))))
      (unless (<= start (car bounds) (point) (cdr bounds) end)
        (emmet2-context--forget-units owner language)
        (setq bounds nil)))
    (when bounds
      (treesit-parser-set-included-ranges parser (list bounds)))
    (when (and (not bounds) initialize)
      (treesit-parser-set-included-ranges parser (list (cons start end)))
      (setq bounds (cons start end))
      (emmet2-context--remember-unit owner language bounds)
      (treesit-parser-set-included-ranges parser (list bounds))
      (treesit-parser-root-node parser))
    bounds))

(defun emmet2-context--warm (buffer owner)
  "Warm BUFFER only while OWNER still belongs to an enabled mode."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (eq (emmet2-context--owner) owner)
        (setf (emmet2-context--state-timer owner) nil)
        (when (bound-and-true-p emmet2-mode) (emmet2-context--prepare))))))

(defun emmet2-context-start ()
  "Schedule one buffer-owned idle warmup.
Repeated invocations do not add timers."
  (let ((owner (emmet2-context--owner t)))
    (unless (emmet2-context--state-timer owner)
      (setf (emmet2-context--state-timer owner)
            (run-with-idle-timer 0.1 nil #'emmet2-context--warm (current-buffer) owner)))))

(defun emmet2-context--host-region (parser start end language)
  "Constrain a candidate using PARSER's original host syntax in START..END.
LANGUAGE selects the query vocabulary.  Bounds still belong to the extractor."
  (let ((left (max start (line-beginning-position)))
        (right (min end (line-end-position)))
        (position (point)))
    (dolist (node (treesit-query-capture
                   parser (nth 1 (assq language emmet2-context--queries))
                   left right t))
      (when (and (<= (treesit-node-start node) position)
                 (or (<= position (treesit-node-end node))
                     ;; `m10+p.5' may close its containing object early with
                     ;; a MISSING }.  Retain that real opening boundary; the
                     ;; extractor and projection still verify the candidate
                     ;; and complete surrounding host before accepting it.
                     (and (equal (treesit-node-type node) "object")
                          (let ((last (treesit-node-child node -1)))
                            (and (equal (treesit-node-type last) "}")
                                 (treesit-node-check last 'missing))))))
        (pcase (treesit-node-type node)
          ("pair"
           ;; Keep authored CSS-in-JS keys and colons in the projection.  The
           ;; original abbreviation may damage this tree, but this only sets
           ;; a lower bound; projected ownership still requires valid syntax.
           (when (emmet2-context--css-owner-p node t)
             (let ((value (treesit-node-child-by-field-name node "value")))
               (when (and value (<= (treesit-node-start value) position))
                 (setq left (max left (treesit-node-start value)))))))
          ("object"
           (let ((begin (treesit-node-start node)))
             ;; Broken JSX such as a{Link $} can recover as an object under
             ;; ERROR.  Do not cut off attached Emmet text before projection
             ;; can prove its host.  Real objects retain their boundary.
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
                     parser (nth 2 (assq language emmet2-context--queries))
                     (line-beginning-position) right t))
        (pcase (treesit-node-type node)
          ("jsx_opening_element"
           (when (<= (treesit-node-end node) position)
             (setq left (max left (treesit-node-end node)))))
          ("jsx_expression"
           (let ((begin (treesit-node-start node)))
             ;; A brace attached to an abbreviation is Emmet text; a leading
             ;; host brace remains outside the extracted candidate.
             (when (and (<= begin position (treesit-node-end node))
                        (or (= begin start)
                            (memq (char-before begin) '(?> ?\s ?\t ?\n ?{ ?=))))
               (setq left (max left (1+ begin)))))))))
    (cons left right)))

(defun emmet2-context--css-owner-p (node &optional allow-errors)
  "Whether property NODE belongs to a supported CSS host.
ALLOW-ERRORS is only for original-tree bounds.
Projected acceptance still requires valid syntax."
  (let ((parent (treesit-node-parent node)) result done)
    (while (and parent (not done))
      (pcase (treesit-node-type parent)
        ((or "object" "pair")
         (when (and (not allow-errors) (treesit-node-check parent 'has-error)) (setq done t)))
        ("jsx_expression"
         (let ((attribute (treesit-node-parent parent)))
           (setq result
                 (and (equal (treesit-node-type attribute) "jsx_attribute")
                      (equal (treesit-node-text (treesit-node-child attribute 0 t) t)
                             "style"))
                 done t)))
        ("arguments"
         (let* ((call (treesit-node-parent parent))
                (function (treesit-node-child-by-field-name call "function")))
           (setq result (and function
                             (member (treesit-node-text function t)
                                     '("StyleSheet.create" "createTheme")))
                 done t)))
        (_ (setq done t)))
      (setq parent (treesit-node-parent parent)))
    (and result t)))

(defun emmet2-context--projected (parser anchor automatic)
  "Classify PARSER at retained ANCHOR.
AUTOMATIC disallows root JS expressions."
  (let* ((node (treesit-node-on anchor (1+ anchor) parser t))
         (parent (treesit-node-parent node)))
    (pcase (treesit-node-type node)
      ("jsx_text"
       (when (and (equal (treesit-node-type parent) "jsx_element")
                  (not (treesit-node-check parent 'has-error)))
         'markup))
      ("shorthand_property_identifier"
       (when (emmet2-context--css-owner-p node) 'css-in-js))
      ("identifier"
       (while (equal (treesit-node-type parent) "parenthesized_expression")
         (setq node parent parent (treesit-node-parent parent)))
       (when (and (not automatic)
                  (or (equal (treesit-node-type parent) "return_statement")
                      (and (equal (treesit-node-type parent) "arrow_function")
                           (treesit-node-eq node (treesit-node-child-by-field-name parent "body")))))
         'markup)))))

(defun emmet2-context--ambiguous-text-p (parser beg end language)
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
     (treesit-query-capture parser (nth 3 (assq language emmet2-context--queries)) beg end t))))

(defun emmet2-context--forbidden-origin-p (parser beg)
  "Return non-nil for BEG inside a host string, comment or regex in PARSER."
  (let ((node (treesit-node-on beg (1+ beg) parser t)) found)
    (while (and node (not found))
      (when (member (treesit-node-type node) '("string" "template_string" "comment" "regex"))
        (setq found t))
      (setq node (treesit-node-parent node)))
    (or found
        ;; An unterminated /* may recover as an invalid regular expression,
        ;; ending at a later JSX tag's slash.  Never project away that evidence.
        (and (treesit-node-check (treesit-parser-root-node parser) 'has-error)
             (cl-some
              (lambda (pattern)
                (let ((start (treesit-node-start pattern)))
                  (and (eq (char-before start) ?/) (eq (char-after start) ?*)
                       (< start beg)
                       (not (save-excursion
                              (goto-char start) (search-forward "*/" beg t))))))
              (treesit-query-capture
               parser (nth 4 (assq (treesit-parser-language parser) emmet2-context--queries))
               nil beg t))))))

(defun emmet2-context--analyze-js (region automatic)
  "Analyze JS REGION; AUTOMATIC requires a warmed parser and trusted position."
  (pcase-let* ((`(,language ,start ,end) region)
               (parser (emmet2-context--parser language (not automatic)))
               (projection (emmet2-context--parser language (not automatic) t))
               (unit (when parser (emmet2-context--unit language start end parser (not automatic)))))
    (if (not (and unit projection))
        (progn
          (when (bound-and-true-p emmet2-mode) (emmet2-context-start))
          nil)
      (let ((bounded (not (equal unit (cons start end)))))
        (setq start (car unit) end (cdr unit))
        (pcase-let* ((`(,left . ,right) (emmet2-context--host-region parser start end language))
                     (candidate (emmet2-extract left right))
                     (beg (plist-get candidate :beg)) (finish (plist-get candidate :end)))
          (when (and candidate (< beg finish)
                     (not (emmet2-context--forbidden-origin-p parser beg))
                     (not (and automatic (emmet2-context--ambiguous-text-p parser beg finish language))))
            (let ((anchor (save-excursion
                            (goto-char beg)
                            (when (re-search-forward "[A-Za-z_]" finish t) (1- (point))))))
              (when anchor
                (treesit-parser-set-included-ranges
                 projection (delq nil (list (and (< start beg) (cons start beg))
                                            (cons anchor (1+ anchor))
                                            (and (< finish end) (cons finish end)))))
                (if (and bounded
                         (let ((root (treesit-parser-root-node projection)))
                           (not (and (not (treesit-node-check root 'has-error))
                                     (= (treesit-node-child-count root t) 1)
                                     (emmet2-context--closed-unit-p
                                      (treesit-node-child root 0 t) start end)))))
                    (progn
                      ;; Retry once with the complete host.  Unrelated syntax
                      ;; errors must not suppress an otherwise valid position.
                      (emmet2-context--remember-unit
                       (emmet2-context--owner) language (cons (nth 1 region) (nth 2 region)))
                      (emmet2-context--analyze-js region automatic))
                  (progn
                    (when-let* ((refined (emmet2-context--tree-unit projection anchor)))
                      (unless (equal refined unit)
                        (emmet2-context--remember-unit (emmet2-context--owner) language refined)))
                    (when-let* ((context (emmet2-context--projected projection anchor automatic)))
                      (append candidate (list :lang context :syntax 'jsx
                                              :position (if (eq context 'css-in-js)
                                                            'declaration-start 'markup))))))))))))))

(defun emmet2-context--web-attribute (position)
  "Return (NAME BEG END) of a quoted value at POSITION, `name', or nil."
  (let ((pos (max (point-min) (1- position))))
    (when-let* ((beg (web-mode-attribute-beginning-position pos)))
      (save-excursion
        (goto-char beg)
        (if (and (looking-at "\\([[:alnum:]:@_.-]+\\)[ \t\n]*=[ \t\n]*\\([\"']\\)")
                 (>= position (match-end 0)))
            (let ((name (downcase (match-string-no-properties 1)))
                  (quote (match-string-no-properties 2)) (start (match-end 0)))
              (goto-char start)
              (let ((end (if (search-forward quote nil t) (1- (point)) (point-max))))
                (if (<= position end) (list name start end) 'name)))
          'name)))))

(defun emmet2-context--web-region ()
  "Return (KIND BEG END ATTRIBUTE) for web HTML/CSS at point, or nil.
The JS region probe has already flushed pending `web-mode' scanning."
  (let* ((pos (max (point-min) (1- (point))))
         (part-pos (if (get-text-property (point) 'part-side) (point) pos))
         (attribute (emmet2-context--web-attribute (point)))
         (language (web-mode-language-at-pos part-pos)))
    (cond
     ((eq (get-text-property pos 'tag-type) 'comment) nil)
     ((consp attribute)
      (when (equal (car attribute) "style")
        (list 'css (nth 1 attribute) (nth 2 attribute) t)))
     ((or attribute
          (and (get-text-property pos 'tag-type)
               (not (get-text-property pos 'tag-end)))) nil)
     ((equal language "css")
      (when-let* ((start (web-mode-part-beginning-position part-pos)))
        (emmet2-context--owner t)
        ;; web-mode's end helper returns the last character at a part's end,
        ;; but a boundary elsewhere.  The property change is always exclusive.
        (list 'css start (next-single-property-change part-pos 'part-side nil (point-max)) nil)))
     ((member language '("" "html"))
      (let ((start (if (get-text-property pos 'tag-end) (1+ pos)
                     (previous-single-property-change (point) 'tag-end nil (line-beginning-position))))
            (end (if (get-text-property (point) 'tag-beg) (point)
                   (next-single-property-change (point) 'tag-beg nil (line-end-position)))))
        ;; Template engine blocks such as {% endif %} or {{ msg }} are host
        ;; syntax; attached braces must not become Emmet text.
        (list 'markup
              (if (and (> (point) start) (get-text-property pos 'block-side)) (point)
                (previous-single-property-change (point) 'block-side nil start))
              (if (get-text-property (point) 'block-side) (point)
                (next-single-property-change (point) 'block-side nil end))
              nil))))))

(defun emmet2-context--web-style-lang (start attribute)
  "Return the lowercase lang of the web style part starting at START, or nil.
ATTRIBUTE hosts are style attributes, which are always plain CSS."
  (unless attribute
    (save-excursion
      (save-match-data
        (let ((position (and (> start (point-min))
                             (web-mode-tag-beginning-position (1- start))))
              (case-fold-search t) language)
          (when (and position (equal (get-text-property position 'tag-name) "style"))
            ;; Attribute markers exclude data-lang and text inside another value.
            (while (and (not language)
                        (setq position (web-mode-attribute-next-position position start)))
              (goto-char position)
              (when (looking-at
                     "lang[ \t\n\r\f]*=[ \t\n\r\f]*\\(?:\"\\([^\"]*\\)\"\\|'\\([^']*\\)'\\|\\([^ \t\n\r\f>]+\\)\\)")
                (setq language (downcase (or (match-string-no-properties 1)
                                             (match-string-no-properties 2)
                                             (match-string-no-properties 3)))))))
          language)))))

(defun emmet2-context--css-state (start position attribute)
  "Return the lexical CSS state at POSITION in a host starting at START.
Web hosts parse with CSS syntax, or SCSS syntax for a style part declaring
lang=\"scss\" or lang=\"less\"; ATTRIBUTE hosts are plain CSS."
  (save-excursion
    (if (derived-mode-p 'web-mode)
        ;; web-mode marks block comments with one-character delimiters.  Mixing
        ;; those properties with SCSS's newline comment ending closes them early.
        (let ((parse-sexp-lookup-properties nil))
          (with-syntax-table
              (if (member (emmet2-context--web-style-lang start attribute) '("scss" "less"))
                  scss-mode-syntax-table css-mode-syntax-table)
            (parse-partial-sexp start position)))
      (syntax-ppss position))))

(defun emmet2-context--css-position (start beg attribute state)
  "Classify CSS at BEG using parse STATE from START; ATTRIBUTE has no selectors."
  (cl-flet ((code-p (position) (not (nth 8 (emmet2-context--css-state start position attribute)))))
    (cond
     ((nth 3 state) 'string)
     ((or (nth 4 state)
          (save-excursion (goto-char beg) (looking-at "/[/*]"))) 'comment)
     ((and (nth 1 state) (eq (char-after (nth 1 state)) ?\()) 'paren-args)
     ((and (nth 1 state) (eq (char-after (nth 1 state)) ?\[)) 'brackets)
     ((save-excursion
        (goto-char beg)
        (let ((limit (save-excursion (skip-chars-backward "^{};\n" start) (point))) found)
          (while (and (not found) (re-search-backward "@[[:alpha:]-]+[ \t]+" limit t))
            (setq found (code-p (point))))
          found))
      'at-rule-prelude)
     ((and (null (nth 1 state)) (not attribute)) 'selector)
     (t
      (let ((previous beg) done)
        ;; Comments between declarations do not change the insertion position.
        (save-excursion
          (while (not done)
            (goto-char previous)
            (skip-chars-backward " \t\n\r\f" start)
            (setq previous (point))
            (let ((before (and (> previous start)
                               ;; Only */ or a line holding // can end a comment here;
                               ;; parsing from START is costly in large web parts.
                               (or (eq (char-before previous) ?/)
                                   (save-excursion (search-backward "//" (line-beginning-position) t)))
                               (emmet2-context--css-state
                                start
                                ;; Inspect inside a closing */, but after both
                                ;; slashes of an empty // line comment.
                                (if (and (eq (char-before previous) ?/)
                                         (eq (char-before (1- previous)) ?*))
                                    (1- previous) previous)
                                attribute))))
              (if (nth 4 before) (setq previous (nth 8 before)) (setq done t)))))
        (if (or (memq (char-before previous) '(?{ ?\; ?}))
                (and attribute (= previous start)))
            'declaration-start 'value))))))

(defun emmet2-context--analyze-lexical (region automatic)
  "Analyze a CSS/markup REGION with only the host's lexical syntax.
AUTOMATIC limits CSS completion to declared insertion positions."
  (pcase-let* ((`(,kind ,start ,end ,attribute) region)
               (candidate (emmet2-extract (max start (point-min)) (min end (point-max))
                                          (when (eq kind 'css) 'css)))
               (beg (plist-get candidate :beg)))
    (when candidate
      (if (eq kind 'markup)
          (unless (equal (plist-get candidate :abbr) "()")
            (append candidate '(:lang markup :syntax html :position markup)))
        (let* ((state (emmet2-context--css-state start beg attribute))
               (position (emmet2-context--css-position start beg attribute state)))
          ;; Without whitespace, the extractor retains the property and colon.
          ;; A bare name followed by one colon is a declaration here; explicit
          ;; commands may still interpret it as an Emmet type/pseudo selector.
          (when (and (eq position 'declaration-start)
                     (not (string-prefix-p "_:" (plist-get candidate :abbr)))
                     (string-match-p "\\`[-[:alpha:]_$][-[:alnum:]_$]*:\\(?:[^:]\\|\\'\\)"
                                     (plist-get candidate :abbr)))
            (setq position 'value))
          (when (and (not (memq position '(string comment)))
                     (or (not automatic)
                         (eq position 'declaration-start)
                         (and (eq position 'selector)
                              (string-match-p "\\`[@_:]" (plist-get candidate :abbr)))))
            (append candidate
                    (list :lang 'css
                          :syntax (if (if (derived-mode-p 'web-mode)
                                          (equal (emmet2-context--web-style-lang start attribute) "scss")
                                        (derived-mode-p 'scss-mode))
                                      'scss 'css)
                          :position position))))))))

(defun emmet2-context-analyze (&optional automatic)
  "Return a confirmed abbreviation at point, or nil.
AUTOMATIC requires trusted positions and warmed JS parsers.  Explicit calls
initialize required grammars and allow manual markup in other major modes."
  (save-match-data
    (let ((visible-start (point-min)) (visible-end (point-max)))
      (save-restriction
        ;; Host syntax must include hidden enclosing constructs.  Restore that
        ;; view for classification, never for candidate acceptance.
        (widen)
        (let ((result
               (if-let* ((region (emmet2-context--js-region)))
                   (emmet2-context--analyze-js region automatic)
                 (when-let* ((region
                               (cond
                                ((derived-mode-p 'web-mode) (emmet2-context--web-region))
                                ((derived-mode-p 'css-mode) (list 'css (point-min) (point-max) nil))
                                ((not automatic) (list 'markup (point-min) (point-max) nil)))))
                   (emmet2-context--analyze-lexical region automatic)))))
          (when (and result (<= visible-start (plist-get result :beg))
                     (<= (plist-get result :end) visible-end))
            result))))))

(provide 'emmet2-context)
;;; emmet2-context.el ends here
