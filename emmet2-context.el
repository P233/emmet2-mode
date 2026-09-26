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
(defvar web-mode-content-type)
(declare-function web-mode-scan "web-mode")
(declare-function web-mode-language-at-pos "web-mode")
(declare-function web-mode-part-beginning-position "web-mode")
(declare-function web-mode-part-end-position "web-mode")
(declare-function web-mode-attribute-beginning-position "web-mode")

(cl-defstruct (emmet2-context--state (:constructor emmet2-context--state-create))
  buffer (tag (make-symbol "emmet2")) timer)
(defvar-local emmet2-context--state nil)

(defun emmet2-context--owner (&optional create)
  "Return this buffer's context owner, allocating it when CREATE is non-nil.
Indirect buffers copy local variables but share their base's parser storage;
verify owner identity and give each view its own tag, without shared cleanup."
  (if (and (emmet2-context--state-p emmet2-context--state)
           (eq (emmet2-context--state-buffer emmet2-context--state) (current-buffer)))
      emmet2-context--state
    (when create
      (setq emmet2-context--state (emmet2-context--state-create :buffer (current-buffer)))
      (add-hook 'kill-buffer-hook #'emmet2-context-stop nil t)
      (add-hook 'change-major-mode-hook #'emmet2-context-stop nil t)
      emmet2-context--state)))

(defun emmet2-context--parsers ()
  "Return only parsers belonging to this buffer's context owner."
  (when (treesit-available-p)
    (when-let* ((owner (emmet2-context--owner)))
      (treesit-parser-list nil nil (emmet2-context--state-tag owner)))))

(defun emmet2-context-stop ()
  "Cancel this buffer's warmup and delete only its owned parsers."
  (when-let* ((owner (emmet2-context--owner)))
    (when-let* ((timer (emmet2-context--state-timer owner))) (cancel-timer timer))
    (dolist (parser (emmet2-context--parsers)) (treesit-parser-delete parser)))
  (setq emmet2-context--state nil)
  (remove-hook 'kill-buffer-hook #'emmet2-context-stop t)
  (remove-hook 'change-major-mode-hook #'emmet2-context-stop t))

(defun emmet2-context--parser (language initialize)
  "Return the owned LANGUAGE parser.
INITIALIZE permits creation or a missing-grammar error."
  (let ((parser (cl-find language (emmet2-context--parsers) :key #'treesit-parser-language)))
    (or parser
        (when initialize
          (unless (and (treesit-available-p) (treesit-language-available-p language))
            (signal 'emmet2-error (list (format "Missing tree-sitter grammar: %s" language))))
          (treesit-parser-create language nil nil
                                 (emmet2-context--state-tag (emmet2-context--owner t)))))))

(defun emmet2-context--js-region ()
  "Return (LANGUAGE BEG END) for a supported JS host at point, or nil."
  (let ((start (point-min)) (end (point-max)) language)
    (cond
     ((derived-mode-p 'web-mode)
      (when web-mode-change-beg (web-mode-scan))
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
    (when (derived-mode-p 'web-mode) (widen))
    (when-let* ((region (emmet2-context--js-region)))
      (pcase-let ((`(,language ,beg ,end) region))
        (when (and (treesit-available-p) (treesit-language-available-p language))
          (let ((parser (emmet2-context--parser language t)))
            (treesit-parser-set-included-ranges parser (list (cons beg end)))
            (treesit-parser-root-node parser)
            parser))))))

(defun emmet2-context--warm (buffer owner)
  "Warm BUFFER only while OWNER still belongs to an enabled mode."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (eq (emmet2-context--owner) owner)
        (setf (emmet2-context--state-timer owner) nil)
        (when (bound-and-true-p emmet2-mode) (emmet2-context--prepare))))))

(defun emmet2-context-start ()
  "Schedule one buffer-owned idle warmup; repeated calls do not add timers."
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
                   parser '([(object) (return_statement) (arrow_function)
                             (parenthesized_expression)] @host)
                   left right t))
      (when (<= (treesit-node-start node) position (treesit-node-end node))
        (pcase (treesit-node-type node)
          ("object" (setq left (max left (1+ (treesit-node-start node)))))
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
                     parser '([(jsx_opening_element) (jsx_expression)] @host)
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

(defun emmet2-context--css-owner-p (node)
  "Whether shorthand property NODE belongs to a supported CSS host."
  (let ((parent (treesit-node-parent node)) result done)
    (while (and parent (not done))
      (pcase (treesit-node-type parent)
        ((or "object" "pair")
         (when (treesit-node-check parent 'has-error) (setq done t)))
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
  "Whether projecting BEG..END would erase a JSX expression after plain text.
LANGUAGE without JSX cannot have this ambiguity.  The explicit command may
interpret tag{text} as Emmet; automatic completion must leave it alone."
  (unless (eq language 'typescript)
    (cl-some
     (lambda (node)
       (let ((brace (treesit-node-start node)))
         (and (< beg brace end)
              (string-match-p "\\`[[:alnum:]_-]+\\'"
                              (buffer-substring-no-properties beg brace)))))
     (treesit-query-capture parser '((jsx_expression) @expression) beg end t))))

(defun emmet2-context--forbidden-origin-p (parser beg)
  "Whether candidate BEG starts in a host string, comment or regex in PARSER."
  (let ((node (treesit-node-on beg (1+ beg) parser t)) found)
    (while (and node (not found))
      (when (member (treesit-node-type node) '("string" "template_string" "comment" "regex"))
        (setq found t))
      (setq node (treesit-node-parent node)))
    found))

(defun emmet2-context--analyze-js (region automatic)
  "Analyze JS REGION; AUTOMATIC requires a warmed parser and trusted position."
  (pcase-let* ((`(,language ,start ,end) region)
               (parser (emmet2-context--parser language (not automatic))))
    (if (not parser)
        (progn
          (when (bound-and-true-p emmet2-mode) (emmet2-context-start))
          nil)
      (treesit-parser-set-included-ranges parser (list (cons start end)))
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
               parser (delq nil (list (and (< start beg) (cons start beg))
                                      (cons anchor (1+ anchor))
                                      (and (< finish end) (cons finish end)))))
              (when-let* ((context (emmet2-context--projected parser anchor automatic)))
                (append candidate (list :lang context :syntax 'jsx
                                        :position (if (eq context 'css-in-js)
                                                      'declaration-start 'markup)))))))))))

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
The JS region probe has already flushed pending web-mode scanning."
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
        ;; web-mode's end helper returns the last character at a part's end,
        ;; but a boundary elsewhere.  The property change is always exclusive.
        (list 'css start (next-single-property-change part-pos 'part-side nil (point-max)) nil)))
     ((member language '("" "html"))
      (list 'markup
            (if (get-text-property pos 'tag-end) (1+ pos)
              (previous-single-property-change (point) 'tag-end nil (line-beginning-position)))
            (if (get-text-property (point) 'tag-beg) (point)
              (next-single-property-change (point) 'tag-beg nil (line-end-position))) nil)))))

(defun emmet2-context--css-position (start beg attribute state)
  "Classify CSS at BEG using parse STATE from START; ATTRIBUTE has no selectors."
  (cond
   ((nth 3 state) 'string)
   ((or (nth 4 state)
        (save-excursion (goto-char beg) (looking-at "/[/*]"))) 'comment)
   ((and (nth 1 state) (eq (char-after (nth 1 state)) ?\()) 'paren-args)
   ((and (nth 1 state) (eq (char-after (nth 1 state)) ?\[)) 'brackets)
   ((save-excursion
      (goto-char beg)
      (let ((limit (save-excursion (skip-chars-backward "^{};\n" start) (point))))
        (re-search-backward "@[[:alpha:]-]+[ \t]+" limit t)))
    'at-rule-prelude)
   ((and (null (nth 1 state)) (not attribute)) 'selector)
   (t
    (let ((previous (save-excursion (goto-char beg) (skip-chars-backward " \t\n" start) (point))))
      (if (or (memq (char-before previous) '(?{ ?\; ?}))
              (and attribute (= previous start)))
          'declaration-start 'value)))))

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
        (let* ((state (save-excursion
                        (if (derived-mode-p 'web-mode)
                            (with-syntax-table css-mode-syntax-table
                              (parse-partial-sexp start beg))
                          (syntax-ppss beg))))
               (position (emmet2-context--css-position start beg attribute state)))
          (when (and (not (memq position '(string comment)))
                     (or (not automatic)
                         (eq position 'declaration-start)
                         (and (eq position 'selector)
                              (string-match-p "\\`[@_:]" (plist-get candidate :abbr)))))
            (append candidate (list :lang 'css :syntax 'css :position position))))))))

(defun emmet2-context-analyze (&optional automatic)
  "Return a confirmed abbreviation at point, or nil.
AUTOMATIC requires trusted positions and warmed JS parsers.  Explicit calls
initialize required grammars and allow manual markup in other major modes."
  (save-match-data
    (let ((visible-start (point-min)) (visible-end (point-max)))
      (save-restriction
        ;; web-mode pending scan ranges refer to the full host document.
        ;; Restore that view for classification, never for candidate acceptance.
        (when (derived-mode-p 'web-mode) (widen))
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
