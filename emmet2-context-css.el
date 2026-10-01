;;; emmet2-context-css.el --- CSS abbreviation host positions -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Built-in css-base-mode supplies lexical syntax through syntax-ppss.  Embedded CSS
;; uses the explicit web part bounds and dialect.  External hosts such as
;; scss2 supply a confirmed analysis and do not enter this adapter.

;;; Code:

(require 'cl-lib)
(require 'css-mode)
(require 'emmet2-engine)
(require 'emmet2-extract)
(require 'emmet2-css-search)

(defun emmet2-context-css--state (region position)
  "Return CSS REGION's lexical state at POSITION.
Native CSS uses `css-base-mode' syntax state.  Embedded hosts need a bounded
parse because their major mode does not supply CSS syntax at buffer level."
  (save-excursion
    (if (not (nth 5 region)) (syntax-ppss position)
      ;; web-mode has its own comment properties; the bounded CSS parse must
      ;; use only the dialect's syntax table, including Sass line comments.
      (let ((parse-sexp-lookup-properties nil))
        (with-syntax-table (if (memq (nth 4 region) '(scss less))
                               scss-mode-syntax-table css-mode-syntax-table)
          (parse-partial-sexp (nth 1 region) position))))))

(defun emmet2-context-css--position (region beg state)
  "Classify CSS REGION at BEG using its lexical STATE."
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
                                 ;; Only */ or a line holding // can end a comment here;
                                 ;; parsing from START is costly in large web parts.
                                 (or (eq (char-before previous) ?/)
                                     (save-excursion (search-backward "//" (line-beginning-position) t)))
                                 (emmet2-context-css--state
                                  region
                                  ;; Inspect inside a closing */, but after both
                                  ;; slashes of an empty // line comment.
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
  "Confirm CSS CANDIDATE at POSITION for an AUTOMATIC request.
A bare property value stays with the host.  Only embedded hosts can opt into
manual custom-element selectors; built-in CSS always uses AUTOMATIC here."
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
      ;; An explicitly admitted unknown name with a pseudo is a selector,
      ;; although its lexical spelling first resembled a declaration value.
      (if (eq position 'value) 'selector position))))

(defun emmet2-context-css-analyze (region automatic)
  "Analyze CSS REGION using its host's position authority.
REGION is (css START END ATTRIBUTE DIALECT EMBEDDED).  EMBEDDED selects the
bounded parse; otherwise `css-base-mode' supplies the lexical state.
AUTOMATIC affects embedded hosts only.  Built-in CSS has one admission rule
for both manual and automatic completion."
  (pcase-let* ((`(,_ ,start ,end ,_attribute ,syntax ,embedded) region)
               (candidate (emmet2-extract start end 'css)))
    (when candidate
      (cl-labels ((position (input)
                    (let ((beg (plist-get input :beg)))
                      (emmet2-context-css--position region beg (emmet2-context-css--state region beg)))))
        (let* ((role (position candidate))
               (selector (emmet2-extract-css-pseudo (plist-get candidate :abbr))))
          (when (and selector (memq role '(selector declaration-start value)))
            (when-let* ((header (emmet2-extract start end 'css-selector))
                        (pseudo (emmet2-extract-css-pseudo (plist-get header :abbr)))
                        (_ (< (+ (plist-get header :beg) pseudo) (plist-get candidate :end))))
              (setq candidate header role (position header))))
          (setq role (emmet2-context-css--allowed candidate role (or (not embedded) automatic)))
          (when role
            (append candidate
                    (list :lang 'css :syntax (if (eq syntax 'scss) 'scss 'css) :position role))))))))

(defun emmet2-context-css-value ()
  "Return a declaration value's bounds and property using CSS Base syntax.
Strings, comments, selectors and function arguments are
left to their existing providers.  Scan only the current declaration."
  (when (derived-mode-p 'css-base-mode)
    (save-excursion
      (let* ((position (point)) (state (syntax-ppss)) (block (nth 1 state)))
        (when (and block (eq (char-after block) ?{)
                   (not (eq (char-before block) ?#)) (not (nth 8 state)))
          (let* ((end (progn (skip-chars-forward "[:alnum:]_-") (point)))
                 (begin (progn (goto-char position) (skip-chars-backward "[:alnum:]_-") (point)))
                 (start (1+ block)) (depth (car state)) property at-rule)
            ;; A delimiter inside a comment, string or function is not a
            ;; declaration boundary.  syntax-ppss preserves CSS/SCSS syntax.
            (while (and (re-search-backward "[;}]" block t)
                        (let ((syntax (save-excursion (syntax-ppss (1+ (point))))))
                          (if (and (= (car syntax) depth) (not (nth 8 syntax)))
                              (progn (setq start (1+ (point))) nil)
                            t))))
            (goto-char block)
            (skip-chars-backward "^{};")
            (forward-comment (point-max))
            (when (looking-at "@[[:alpha:]-]+")
              (setq at-rule (downcase (match-string-no-properties 0))))
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
