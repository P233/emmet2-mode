;;; emmet2-extensions.el --- Pure project expansion rules -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This layer owns opinionated syntax, default removal and output transforms.
;; It neither reads nor writes editor state.  One deadline covers all core calls.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emmet2-engine)
(require 'emmet2-fuzzy)

(defconst emmet2-extensions--data-directory
  (expand-file-name "data" (file-name-directory (or load-file-name buffer-file-name))))

(defun emmet2-extensions--read-data (name)
  "Read packaged JSON data NAME once when this module loads."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name emmet2-extensions--data-directory))
    (json-parse-buffer :array-type 'list)))

(defconst emmet2-extensions--names (emmet2-extensions--read-data "css-names.json"))
(defconst emmet2-extensions--overrides (emmet2-extensions--read-data "css-overrides.json"))

(defun emmet2-extensions--split (text separators)
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

(defun emmet2-extensions--clear-defaults (result)
  "Remove RESULT defaults and normalize its first whitespace run.
RESULT is one property: coalesce fields that collapse to the same position
only here, before concatenating properties.  Preserve mirrors elsewhere."
  (let ((text (plist-get result :text)) (start 0) (offset 0) chunks fields)
    (dolist (field (plist-get result :fields))
      (pcase-let ((`(,beg ,end ,index ,_) field))
        (when (>= beg start)
          (push (substring text start beg) chunks)
          (cl-incf offset (- beg start)))
        (push (list offset offset index "") fields)
        (setq start (max start end))))
    (setq text (apply #'concat (nreverse (cons (substring text start) chunks)))
          fields (nreverse fields))
    (when (string-match "[ \t\r\n]+" text)
      (let* ((beg (match-beginning 0)) (end (match-end 0)) (delta (- 1 (- end beg))))
        (setq text (concat (substring text 0 beg) " " (substring text end)))
        (dolist (field fields)
          (let* ((old (car field))
                 (pos (cond ((<= old beg) old) ((<= old end) (1+ beg)) (t (+ old delta)))))
            (setcar field pos) (setcar (cdr field) pos)))))
    (let ((groups (make-hash-table :test #'eql)) unique)
      (cl-labels ((group (index)
                    (while (gethash index groups) (setq index (gethash index groups)))
                    index))
        (dolist (field fields)
          (if (and unique (= (caar unique) (car field)))
              (let ((a (group (nth 2 (car unique)))) (b (group (nth 2 field))))
                ;; Merge identities too, so mirrors at another position survive.
                (unless (= a b) (puthash (max a b) (min a b) groups)))
            (push field unique)))
        (dolist (field unique) (setcar (nthcdr 2 field) (group (nth 2 field)))))
      (emmet2-result-create text (nreverse unique)))))

(defun emmet2-extensions--aliases (token)
  "Expand one TOKEN into property abbreviations before calling the core."
  (let ((case-fold-search nil))
    (cond
     ((string-match "\\`\\(pos[af]\\)\\(.*\\)\\'" token)
      (list (match-string 1 token) (concat "z" (match-string 2 token))))
     ((string-prefix-p "all" token)
      (mapcar (lambda (name) (concat name (substring token 3))) '("t" "r" "b" "l")))
     ((string-match "\\`fw\\([0-9]\\)\\(!?\\)\\'" token)
      (list (concat "fw" (match-string 1 token) "00" (match-string 2 token))))
     ((string-match "\\`\\(ma\\|mi\\)?\\([wh]\\)f\\(!?\\)\\'" token)
      (list (concat (match-string 1 token) (match-string 2 token) "100p" (match-string 3 token))))
     (t (list token)))))

(defun emmet2-extensions--property (token)
  "Expand TOKEN and apply the sole CSS default cleanup."
  (let* ((case-fold-search nil)
         (important (string-suffix-p "!" token))
         (body (if important (substring token 0 -1) token)) name suffix value)
    (when (string-match "\\`-?[a-z]+" body)
      (setq name (match-string 0 body) suffix (substring body (match-end 0))))
    (cond
     ((and suffix (string-prefix-p "[" suffix) (string-suffix-p "]" suffix))
      (setq value (substring suffix 1 -1)))
     ((and suffix (string-match-p "\\`--[a-zA-Z0-9_-]+\\'" suffix))
      (setq value (mapconcat (lambda (part) (concat "var(--" part ")"))
                             (split-string suffix "--" t) " ")))
     ((and suffix (string-match-p
                   "\\`\\(?:(-?\\(?:[0-9]+\\(?:\\.[0-9]*\\)?\\|\\.[0-9]+\\))\\)+\\'" suffix))
      (setq value (if (equal name "fz") (concat "ms" suffix)
                    (mapconcat (lambda (arg) (if (equal arg "0") "0" (concat "rhythm(" arg ")")))
                               (split-string suffix "[()]" t) " ")))))
    (if value
        (let* ((core (emmet2-engine-expand name :preset 'stylesheet))
               (text (plist-get core :text)))
          (unless (string-match ": " text)
            (signal 'emmet2-parse-error (list "Expected a CSS property" 0)))
          ;; An explicit value replaces the complete core value, including every
          ;; default field and wrapper.  No boundary field from the core survives.
          (emmet2-result-create
           (concat (substring text 0 (match-end 0)) value (if important " !important;" ";"))))
      (when (string-match "\\`-?[a-z]+\\([A-Z]\\)" token)
        (setq token (replace-match (concat ":" (downcase (match-string 1 token))) t t token 1)))
      (emmet2-extensions--clear-defaults (emmet2-engine-expand token :preset 'stylesheet)))))

(defun emmet2-extensions--map-chars (result transform)
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

(defun emmet2-extensions--escape-js (ch)
  "Encode CH inside a JavaScript double-quoted string without evaluation."
  (pcase ch
    (?\" "\\\"") (?\\ "\\\\") (?\n "\\n") (?\r "\\r") (?\t "\\t")
    ((or #x2028 #x2029) (format "\\u%04x" ch))
    (_ (if (< ch 32) (format "\\u%04x" ch) (char-to-string ch)))))

(defun emmet2-extensions--identifier-p (text)
  "Whether TEXT can be emitted as a conservative JavaScript identifier."
  (let ((case-fold-search nil))
    (string-match-p "\\`[a-zA-Z_$][a-zA-Z0-9_$]*\\'" text)))

(defun emmet2-extensions--js-property (result)
  "Convert one CSS property RESULT to a JavaScript member, retaining its fields."
  (let* ((text (plist-get result :text)) key start finish)
    (unless (and (string-match ": " text) (string-suffix-p ";" text))
      (signal 'emmet2-parse-error '("Expected a declaration for CSS-in-JS" 0)))
    (setq start (match-end 0) finish (1- (length text)) key (substring text 0 (match-beginning 0)))
    (unless (string-prefix-p "--" key)
      (setq key (replace-regexp-in-string "-[a-z]" (lambda (part) (upcase (substring part 1))) key t t))
      (when (string-prefix-p "Ms" key) (setq key (concat "ms" (substring key 2)))))
    (unless (emmet2-extensions--identifier-p key) (setq key (json-serialize key)))
    (let* ((value (emmet2-result-create
                   (substring text start finish)
                   (mapcar (lambda (field)
                             (pcase-let ((`(,beg ,end ,index ,placeholder) field))
                               (list (- beg start) (- end start) index placeholder)))
                           (plist-get result :fields))))
           (raw (plist-get value :text)))
      (cond
       ((string-match-p "\\`-?[0-9]+\\(?:\\.[0-9]*\\)?\\(?:px\\)?\\'" raw)
        (when (string-suffix-p "px" raw)
          (setq value (emmet2-result-splice value (- (length raw) 2) (length raw)
                                          (emmet2-result-create "")))))
       ((not (string-empty-p raw))
        (setq value (emmet2-result-concat
                     (emmet2-result-create "\"")
                     (emmet2-extensions--map-chars value #'emmet2-extensions--escape-js)
                     (emmet2-result-create "\"")))))
      (emmet2-result-concat (emmet2-result-create (concat key ": ")) value))))

(defun emmet2-extensions--bare-name (name)
  "Remove the syntactic prefix of pseudo or at-rule NAME for fuzzy scoring."
  (string-trim-left name "[:@]+"))

(defun emmet2-extensions--resolve (abbreviation names alias-key)
  "Resolve ABBREVIATION by ALIAS-KEY overrides first, then fuzzy-match NAMES."
  (let ((alias (gethash abbreviation (gethash alias-key emmet2-extensions--overrides))))
    (or (and (member alias names) alias)
        (emmet2-fuzzy-find (emmet2-extensions--bare-name abbreviation) names nil nil
                          #'emmet2-extensions--bare-name)
        abbreviation)))

(defun emmet2-extensions--render-template (result indent base-indent)
  "Render authored template RESULT with INDENT and BASE-INDENT."
  (emmet2-extensions--map-chars
   result (lambda (ch) (cond ((= ch ?\t) indent) ((= ch ?\n) (concat "\n" base-indent))
                              (t (char-to-string ch))))))

(defun emmet2-extensions--at-rule (abbreviation indent base-indent)
  "Expand ABBREVIATION using names and local templates with INDENT and BASE-INDENT."
  (let* ((templates (gethash "atRuleTemplates" emmet2-extensions--overrides))
         (names (sort (delete-dups (append (gethash "atRules" emmet2-extensions--names)
                                           (hash-table-keys templates))) #'string<))
         (name (emmet2-extensions--resolve abbreviation names "atRuleAliases"))
         (template (gethash name templates)))
    (if template
        (let ((cursor (gethash "cursor" template)))
          (emmet2-extensions--render-template
           (emmet2-result-create (gethash "text" template) (list (list cursor cursor 1 "")))
           indent base-indent))
      (emmet2-result-create (concat name (if (member name names) " " ""))))))

(defun emmet2-extensions--pseudo-chain (text)
  "Expand a TEXT chain of pseudo selectors, including nested functional arguments."
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
              (setq name (emmet2-extensions--resolve
                          name (gethash "pseudoFunctions" emmet2-extensions--overrides) "pseudoAliases"))
              (dolist (argument (emmet2-extensions--split (substring text start (1- pos)) '(?,)))
                (setq argument (string-trim argument))
                (cond ((string-prefix-p ":" argument)
                       (setq argument (emmet2-extensions--pseudo-chain argument)))
                      ((string-match "\\`[+>~]" argument)
                       (setq argument (concat (substring argument 0 1) " "
                                              (string-trim-left (substring argument 1))))))
                (push (concat name "(" argument ")") pieces)))
          (push (emmet2-extensions--resolve name (gethash "pseudos" emmet2-extensions--names)
                                            "pseudoAliases") pieces))))
    (apply #'concat (nreverse pieces))))

(defun emmet2-extensions--selector (abbreviation indent base-indent)
  "Expand selector ABBREVIATION with INDENT and BASE-INDENT."
  (let* ((colon (string-match ":" abbreviation)) (prefix (substring abbreviation 0 colon))
         (selector (concat (cond ((equal prefix "_") "") ((equal prefix "") "&") (t prefix))
                           (emmet2-extensions--pseudo-chain (substring abbreviation colon))))
         (text (concat selector " {\n\t\n}")) (cursor (+ (length selector) 4)))
    (emmet2-extensions--render-template (emmet2-result-create text (list (list cursor cursor 1 "")))
                                       indent base-indent)))

(cl-defun emmet2-extensions-css (abbreviation &key css-in-js (indent "\t") (base-indent ""))
  "Expand CSS ABBREVIATION to a canonical result.
CSS-IN-JS requests object member syntax.  INDENT and BASE-INDENT are literal
rendering strings.  Generated layout uses them; literal raw text is preserved."
  (emmet2-engine-with-expansion
    (let ((case-fold-search nil))
      (cond
       ((and (not css-in-js) (string-prefix-p "@" abbreviation))
        (emmet2-extensions--at-rule abbreviation indent base-indent))
       ((and (not css-in-js) (string-match-p "\\`[a-zA-Z0-9_.#-]*:" abbreviation))
        (emmet2-extensions--selector abbreviation indent base-indent))
       (t
        (let (parts)
          (dolist (token (emmet2-extensions--split abbreviation '(?+ ?,)))
            (when (string-empty-p token) (signal 'emmet2-parse-error '("Empty CSS property" 0)))
            (dolist (property (emmet2-extensions--aliases token))
              (emmet2-engine--check-deadline)
              (when parts (push (emmet2-result-create (if css-in-js ", " (concat "\n" base-indent))) parts))
              (let ((result (emmet2-extensions--property property)))
                (push (if css-in-js (emmet2-extensions--js-property result) result) parts))))
          (apply #'emmet2-result-concat (nreverse parts))))))))

(provide 'emmet2-extensions)
;;; emmet2-extensions.el ends here
