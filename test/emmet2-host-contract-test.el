;;; emmet2-host-contract-test.el --- Host feasibility contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'treesit)
(require 'web-mode)
(require 'emmet2-extract)

;; S0 feasibility only.  S3 must replace this test helper with the production
;; context owner while retaining the same real-point fixtures.  No known
;; abbreviation bounds are passed to the helper, and it never edits source.
(defun emmet2-test--host-region (parser start end language)
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

(defun emmet2-test--css-owner-p (node)
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

(defun emmet2-test--projected-context (parser anchor automatic)
  "Classify PARSER at retained ANCHOR; AUTOMATIC disallows root JS expressions."
  (let* ((node (treesit-node-on anchor (1+ anchor) parser t))
         (parent (treesit-node-parent node)))
    (pcase (treesit-node-type node)
      ("jsx_text"
       (when (and (equal (treesit-node-type parent) "jsx_element")
                  (not (treesit-node-check parent 'has-error)))
         'markup))
      ("shorthand_property_identifier"
       (when (emmet2-test--css-owner-p node) 'css-in-js))
      ("identifier"
       (while (equal (treesit-node-type parent) "parenthesized_expression")
         (setq node parent parent (treesit-node-parent parent)))
       (when (and (not automatic)
                  (or (equal (treesit-node-type parent) "return_statement")
                      (and (equal (treesit-node-type parent) "arrow_function")
                           (treesit-node-eq node (treesit-node-child-by-field-name parent "body")))))
         'markup)))))

(defun emmet2-test--ambiguous-text-p (parser beg end language)
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

(defun emmet2-test--analyze-host (automatic)
  "Run the minimal region/extract/confirm chain at point.
AUTOMATIC selects completion rather than the explicit command."
  (let ((start (point-min)) (end (point-max)) (language 'tsx))
    (cond
     ((derived-mode-p 'web-mode)
      (when web-mode-change-beg (web-mode-scan))
      (let ((part (web-mode-language-at-pos)))
        (setq language (if (string= part "typescript") 'typescript 'tsx))
        (unless (member web-mode-content-type '("jsx" "javascript" "typescript"))
          (setq start (web-mode-part-beginning-position)
                end (web-mode-part-end-position)))))
     ((derived-mode-p 'typescript-ts-mode) (setq language 'typescript))
     ((derived-mode-p 'js-mode 'js-ts-mode) (setq language 'javascript)))
    (when (and start end)
      (let ((parser (treesit-parser-create language nil nil 'emmet2-contract)))
        (unwind-protect
            (progn
              (treesit-parser-set-included-ranges parser (list (cons start end)))
              (pcase-let* ((`(,left . ,right)
                            (emmet2-test--host-region parser start end language))
                           (candidate (emmet2-extract left right))
                           (beg (plist-get candidate :beg))
                           (finish (plist-get candidate :end)))
                (when (and candidate
                           (not (and automatic
                                     (emmet2-test--ambiguous-text-p parser beg finish language))))
                  (let ((anchor (save-excursion
                                  (goto-char beg)
                                  (when (re-search-forward "[A-Za-z_]" finish t)
                                    (1- (point))))))
                    (when anchor
                      (treesit-parser-set-included-ranges
                       parser (delq nil (list (and (< start beg) (cons start beg))
                                              (cons anchor (1+ anchor))
                                              (and (< finish end) (cons finish end)))))
                      (let ((context (emmet2-test--projected-context parser anchor automatic)))
                        (when context (append candidate (list :lang context)))))))))
          (treesit-parser-delete parser))))))

(defconst emmet2-test-host-cases
  '((tight "const A = () => (<main>ul>li*3│</main>);" markup "ul>li*3")
    (middle "const A = () => (<main>ul>│li*3</main>);" markup "ul>li*3")
    (text "const A = () => (<main>div{hello│ world}</main>);" markup "div{hello world}" manual)
    (text-punctuation "const A = () => (<main>p{don't│ [stop}</main>);" markup "p{don't [stop}" manual)
    (text-ambiguity "const A = () => (<main>Hello{items.ma│}</main>);" nil nil)
    (text-ambiguity-end "const A = () => (<main>Hello{items.ma}│</main>);" nil nil)
    (text-explicit "const A = () => (<main>p{hello│}</main>);" markup "p{hello}" manual)
    (expression "const A = () => (<main>{items.ma│}</main>);" nil nil)
    (expression-before-close "const A = () => (<main>{items.ma}│</main>);" nil nil)
    (attribute "const A = () => (<main title='ul>li│'/>);" nil nil)
    (style "const A = () => (<main style={{m1,p│2}}/>);" css-in-js "m1,p2")
    (raw "const A = () => (<main style={{p[1px│ 2px]}}/>);" css-in-js "p[1px 2px]")
    (other-attribute "const A = () => (<main other={{m10│}}/>);" nil nil)
    (computed-style "const A = () => (<main style={compute({m10│})}/>);" nil nil)
    (nested-computation "const s = createTheme({x: compute({m10│})});" nil nil)
    (style-value "const A = () => (<main style={{color: m10│}}/>);" nil nil)
    (malformed-style "const A = () => (<main style={{m10│/>);" nil nil)
    (stylesheet "const s = StyleSheet.create({x: {m1│0}});" css-in-js "m10")
    (theme "const s = createTheme({x: {p1│0}});" css-in-js "p10")
    (ordinary-call "const s = makeStyles({x: {m10│}});" nil nil)
    (ordinary-object "const s = {x: {m10│}};" nil nil)
    (string "const s = 'ul>li│';" nil nil)
    (comment "// ul>li│" nil nil)
    (root-auto "function A() { return ul>li│; }" nil nil)
    (root-manual "function A() { return ul>li│; }" markup "ul>li" manual)
    (map-auto "const A = items.map(x => ul>li│);" nil nil)
    (map-manual "const A = items.map(x => ul>li│);" markup "ul>li" manual)))

(ert-deftest emmet2-contract-host-jsx-real-point ()
  (dolist (configuration '((tsx-ts-mode . "tsx") (web-mode . "tsx") (web-mode . "jsx")))
    (pcase-let ((`(,mode . ,extension) configuration))
      (dolist (fixture emmet2-test-host-cases)
	(pcase-let ((`(,name ,source ,language ,abbreviation . ,options) fixture))
          (ert-info ((format "%s %s %s" mode extension name))
            (with-temp-buffer
              (setq buffer-file-name (concat "/tmp/emmet2-contract." extension))
              (insert source)
              (goto-char (point-min)) (search-forward "│") (delete-char -1)
              (let ((position (point)))
		(funcall mode)
		(goto-char position)
		(let* ((original (buffer-string))
                       (result (emmet2-test--analyze-host (not (memq 'manual options)))))
                  (should (equal (plist-get result :lang) language))
                  (should (equal (plist-get result :abbr) abbreviation))
                  (should (equal (buffer-string) original))
                  (should (= (point) position))
                  (should-not (cl-find 'emmet2-contract (treesit-parser-list)
                                       :key #'treesit-parser-tag)))))))))))

(ert-deftest emmet2-contract-host-script-owners ()
  (dolist (mode '(js-mode js-ts-mode typescript-ts-mode web-mode))
    (dolist (call '("StyleSheet.create" "createTheme" "ordinary"))
      (ert-info ((format "%s %s" mode call))
        (with-temp-buffer
          (setq buffer-file-name "/tmp/emmet2-contract.html")
          (when (eq mode 'web-mode) (insert "<script>\n"))
          (insert (format "const s = %s({x: {p[1px 2px]}});" call))
          (when (eq mode 'web-mode) (insert "\n</script>"))
          (funcall mode)
          (goto-char (point-min)) (search-forward "1px")
          (let ((result (emmet2-test--analyze-host t)))
            (if (equal call "ordinary")
                (should-not result)
              (should (eq (plist-get result :lang) 'css-in-js))
              (should (equal (plist-get result :abbr) "p[1px 2px]")))))))))

(provide 'emmet2-host-contract-test)
;;; emmet2-host-contract-test.el ends here
