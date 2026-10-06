;;; emmet2-context-css.el --- CSS abbreviation and value positions -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Find CSS abbreviation and value positions.  In `css-base-mode' buffers,
;; `syntax-ppss' supplies the lexical state; embedded CSS from web-mode is
;; parsed within its part bounds using its dialect's syntax table.  Buffers with
;; `emmet2-context-provider', such as scss2-mode, never reach this adapter.

;;; Code:

(require 'cl-lib)
(require 'emmet2-engine)
(require 'emmet2-extract)
(require 'emmet2-css-search)

;; Copies of css-mode's tables, since loading css-mode for them also loads eww, shr and SMIE.
(defconst emmet2-context-css--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?/ ". 14" table)
    (modify-syntax-entry ?* ". 23b" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\' "\"" table)
    (pcase-dolist (`(,open . ,close) '((?{ . ?}) (?\( . ?\)) (?\[ . ?\])))
      (modify-syntax-entry open (string ?\( close) table)
      (modify-syntax-entry close (string ?\) open) table))
    (dolist (char '(?@ ?# ?. ?-))
      (modify-syntax-entry char "_" table))
    (dolist (char '(?! ?$ ?% ?& ?+ ?, ?< ?> ?= ??))
      (modify-syntax-entry char "." table))
    table)
  "Syntax table for CSS embedded in another host.")

(defconst emmet2-context-css--scss-syntax-table
  (let ((table (make-syntax-table emmet2-context-css--syntax-table)))
    (modify-syntax-entry ?/ ". 124" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?% "_" table)
    table)
  "Syntax table for SCSS and Less embedded in another host.")

(defun emmet2-context-css--state (region position)
  "Return CSS REGION's lexical state at POSITION.
Native CSS uses `css-base-mode' syntax state.  Embedded hosts need a bounded
parse because their major mode does not supply CSS syntax at buffer level."
  (save-excursion
    (if (not (nth 5 region)) (syntax-ppss position)
      ;; web-mode's comment properties would mislead the parse; use only the dialect's syntax table.
      (let ((parse-sexp-lookup-properties nil))
        (with-syntax-table (if (memq (nth 4 region) '(scss less))
                               emmet2-context-css--scss-syntax-table
                             emmet2-context-css--syntax-table)
          (parse-partial-sexp (nth 1 region) position))))))

(defun emmet2-context-css--position (region beg state)
  "Return the position kind of CSS REGION at BEG, given its lexical STATE.
The kind is string, comment, paren-args, brackets, value, at-rule-prelude,
selector or declaration-start."
  (let ((start (nth 1 region)) (attribute (nth 3 region)))
    (cl-flet ((code-p (position) (not (nth 8 (emmet2-context-css--state region position)))))
      (cond
       ((nth 3 state) 'string)
       ((or (nth 4 state)
            (save-excursion (goto-char beg) (looking-at "/[/*]"))) 'comment)
       ((and (nth 1 state) (eq (char-after (nth 1 state)) ?\()) 'paren-args)
       ((and (nth 1 state) (eq (char-after (nth 1 state)) ?\[)) 'brackets)
       ;; Sass interpolation, as in .a-#{$x}, belongs to its enclosing text.
       ((and (nth 1 state) (eq (char-after (nth 1 state)) ?{) (eq (char-before (nth 1 state)) ?#)) 'value)
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
                                 ;; Only */ or a line with // can end a comment here; avoid parsing a large web part from START.
                                 (or (eq (char-before previous) ?/)
                                     (save-excursion (search-backward "//" (line-beginning-position) t)))
                                 (emmet2-context-css--state
                                  region
                                  ;; Inspect inside a closing */, but after both slashes of an empty // comment.
                                  (if (and (eq (char-before previous) ?/)
                                           (eq (char-before (1- previous)) ?*))
                                      (1- previous) previous)))))
                (if (nth 4 before) (setq previous (nth 8 before)) (setq done t)))))
          (if (or (memq (char-before previous) '(?{ ?\; ?}))
                  (and attribute (= previous start)))
              'declaration-start 'value)))))))

(defun emmet2-context-css--selector-pseudo-p (abbreviation)
  "Whether CSS ABBREVIATION has an unambiguous selector prefix and pseudo.
Bare names need a known element, as in button:hv.  Classes, attributes and
compound or list prefixes already distinguish the input from a property."
  (when-let* ((colon (emmet2-extract-css-pseudo abbreviation)))
    (let ((prefix (substring abbreviation 0 colon)))
      (or (member prefix '("" "_"))
          (not (string-match-p "\\`[-[:alnum:]_]+\\'" prefix))
          (emmet2-css-search-element-p prefix)))))

(defun emmet2-context-css--allowed (candidate position automatic)
  "Return the position at which CSS CANDIDATE may expand, or nil.
POSITION is CANDIDATE's lexical position.  A declaration value such as
display:fl stays with the host, except that nil AUTOMATIC admits an unknown
name with a pseudo, such as my-el:hv, as a selector.  Built-in CSS always
passes non-nil AUTOMATIC."
  (let* ((abbreviation (plist-get candidate :abbr))
         (selector (emmet2-extract-css-pseudo abbreviation))
         (declaration (and (eq position 'declaration-start)
                           (not (string-prefix-p "_:" abbreviation))
                           (string-match "\\`\\([-[:alpha:]_$][-[:alnum:]_$]*\\):\\(?:[^:]\\|\\'\\)" abbreviation)
                           (let ((name (match-string 1 abbreviation)))
                             (unless (emmet2-css-search-element-p name) name)))))
    (when declaration (setq position 'value))
    (when (and (not (and declaration (or (string-prefix-p "-" declaration)
                                         (emmet2-css-search-property-p declaration))))
               (pcase position
                 ('declaration-start t)
                 ('selector (or (string-match-p "\\`[@_]" abbreviation)
                                (and selector (or (not automatic)
                                                  (emmet2-context-css--selector-pseudo-p abbreviation)))))
                 ('value (and declaration (not automatic)))))
      ;; An explicitly requested unknown name with a pseudo is a selector, not a declaration.
      (if (eq position 'value) 'selector position))))

(defun emmet2-context-css--at-rule (region block)
  "Return the lowercase at-rule whose prelude opens the brace at BLOCK, or nil.
REGION supplies the lexical state and bounds the scan, as embedded CSS begins
inside another language.  Delimiters inside comments do not end the prelude."
  (save-excursion
    (goto-char block)
    (let (delimiter)
      (while (and (setq delimiter (re-search-backward "[{};]" (nth 1 region) t))
                  (nth 8 (emmet2-context-css--state region delimiter))))
      (goto-char (if delimiter (1+ delimiter) (nth 1 region)))
      (forward-comment (point-max))
      (when (looking-at "@[[:alpha:]-]+")
        (downcase (match-string-no-properties 0))))))

(defun emmet2-context-css-analyze (region automatic)
  "Return the CSS abbreviation context at point in REGION, or nil.
REGION is (css START END ATTRIBUTE DIALECT EMBEDDED), as returned by
`emmet2-context-web-region' or built for `css-base-mode'.  EMBEDDED selects
a parse bounded by START; otherwise `syntax-ppss' supplies the lexical
state.  AUTOMATIC matters for embedded CSS only, where nil also admits an
unknown name with a pseudo as a selector; built-in CSS uses one rule for
both kinds of request."
  (pcase-let* ((`(,_ ,start ,end ,_attribute ,syntax ,embedded) region)
               (candidate (emmet2-extract start end 'css)))
    (when candidate
      (cl-labels ((state (input) (emmet2-context-css--state region (plist-get input :beg)))
                  (position (input state) (emmet2-context-css--position region (plist-get input :beg) state)))
        (let* ((state (state candidate))
               (role (position candidate state))
               (selector (emmet2-extract-css-pseudo (plist-get candidate :abbr))))
          (when (and selector (memq role '(selector declaration-start value)))
            (when-let* ((header (emmet2-extract start end 'css-selector))
                        (pseudo (emmet2-extract-css-pseudo (plist-get header :abbr)))
                        (_ (< (+ (plist-get header :beg) pseudo) (plist-get candidate :end))))
              (setq candidate header state (state header) role (position header state))))
          (setq role (emmet2-context-css--allowed candidate role (or (not embedded) automatic)))
          (when role
            ;; Declarations inside an at-rule such as @font-face use its descriptors.
            (let* ((block (and (eq role 'declaration-start) (nth 1 state)))
                   (at-rule (and block (eq (char-after block) ?{)
                                 (emmet2-context-css--at-rule region block))))
              (append candidate
                      (list :lang 'css :syntax (if (eq syntax 'scss) 'scss 'css) :position role)
                      (and at-rule (list :at-rule at-rule))))))))))

(defun emmet2-context-css-value ()
  "Return the value word at point in a CSS Base declaration, or nil.
The value is a plist (:beg BEG :end END :property NAME :at-rule AT-RULE) for
the word around point, which may be empty, after the colon of a known
property.  Return nil inside strings, comments, selectors and function
arguments, and outside `css-base-mode'.  Only the current declaration is
scanned."
  (when (derived-mode-p 'css-base-mode)
    (save-excursion
      (let* ((position (point)) (state (syntax-ppss)) (block (nth 1 state)))
        (when (and block (eq (char-after block) ?{)
                   (not (eq (char-before block) ?#)) (not (nth 8 state)))
          (let* ((end (progn (skip-chars-forward "[:alnum:]_-") (point)))
                 (begin (progn (goto-char position) (skip-chars-backward "[:alnum:]_-") (point)))
                 (start (1+ block)) (depth (car state)) property at-rule)
            ;; Delimiters in comments, strings or functions do not end the declaration.
            (while (and (re-search-backward "[;}]" block t)
                        (let ((syntax (save-excursion (syntax-ppss (1+ (point))))))
                          (if (and (= (car syntax) depth) (not (nth 8 syntax)))
                              (progn (setq start (1+ (point))) nil)
                            t))))
            (setq at-rule (emmet2-context-css--at-rule (list 'css (point-min)) block))
            (goto-char start) (forward-comment (point-max))
            (when (looking-at "[[:alpha:]_-][[:alnum:]_-]*")
              (setq property (downcase (match-string-no-properties 0)))
              (goto-char (match-end 0)) (forward-comment (point-max))
              (when (and (eq (char-after) ?:) (< (point) begin)
                         (emmet2-css-search-property-p property at-rule)
                         ;; Do not replace a suffix of a literal or Sass name.
                         (not (memq (char-before begin) '(?$ ?# ?\\ ?. ?%)))
                         (or (= begin end)
                             (string-match-p "\\`[[:alpha:]_-]"
                                             (buffer-substring-no-properties begin end))))
                (list :beg begin :end end :property property :at-rule at-rule)))))))))

(provide 'emmet2-context-css)
;;; emmet2-context-css.el ends here
