;;; emmet2-context-web.el --- HTML and embedded-language boundaries -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; web-mode tokenizes the buffer and marks parts, tags and attributes; this
;; adapter reads those properties to find the language region at point.  It
;; flushes web-mode's pending scan first and, after one typed character in a
;; CSS rule, rescans only that rule.  It creates no parser and does not
;; extract the abbreviation.

;;; Code:

(require 'cl-lib)

(defvar web-mode-change-beg)
(defvar web-mode-change-end)
(defvar web-mode-content-type)
(defvar web-mode-engine)
(declare-function web-mode-scan "web-mode")
(declare-function web-mode-scan-region "web-mode")
(declare-function web-mode-css-rule-current "web-mode")
(declare-function web-mode-language-at-pos "web-mode")
(declare-function web-mode-part-beginning-position "web-mode")
(declare-function web-mode-attribute-beginning-position "web-mode")
(declare-function web-mode-tag-beginning-position "web-mode")
(declare-function web-mode-attribute-next-position "web-mode")

(cl-defstruct (emmet2-context-web--state (:constructor emmet2-context-web--state-create))
  buffer tick insertion)
(defvar-local emmet2-context-web--state nil)

(defun emmet2-context-web--owner (&optional create)
  "Return this buffer's web scan owner, allocating it when CREATE is non-nil."
  (if (and (emmet2-context-web--state-p emmet2-context-web--state)
           (eq (emmet2-context-web--state-buffer emmet2-context-web--state) (current-buffer)))
      emmet2-context-web--state
    (when create
      (setq emmet2-context-web--state
            (emmet2-context-web--state-create :buffer (current-buffer) :tick (buffer-chars-modified-tick)))
      (add-hook 'kill-buffer-hook #'emmet2-context-web-stop nil t)
      (add-hook 'change-major-mode-hook #'emmet2-context-web-stop nil t)
      (add-hook 'before-change-functions #'emmet2-context-web--before-change nil t)
      (add-hook 'after-change-functions #'emmet2-context-web--after-change nil t)
      emmet2-context-web--state)))

(defun emmet2-context-web--check-tick (owner)
  "Discard OWNER's pending scan if another view bypassed its edit hooks.
Return non-nil when it did."
  (unless (eql (emmet2-context-web--state-tick owner) (buffer-chars-modified-tick))
    (emmet2-context-web--forget-insertion owner)
    (setf (emmet2-context-web--state-tick owner) (buffer-chars-modified-tick))))

(defun emmet2-context-web--before-change (beg end)
  "Remember a possible single CSS insertion at BEG..END."
  (when-let* ((owner (emmet2-context-web--owner)))
    (unless (emmet2-context-web--check-tick owner)
      (emmet2-context-web--remember-insertion owner beg end))))

(defun emmet2-context-web--after-change (beg end length)
  "Record the edit at BEG..END replacing LENGTH characters.
Markers already follow valid interior changes."
  (when-let* ((owner (emmet2-context-web--owner)))
    (when-let* ((entry (emmet2-context-web--state-insertion owner)))
      (if (and (zerop length) (= beg (car entry)) (= end (1+ beg))
               (= (buffer-chars-modified-tick) (nth 4 entry))
               (let ((char (char-after beg)))
                 (or (<= ?a char ?z) (<= ?A char ?Z) (<= ?0 char ?9) (memq char '(?_ ?-)))))
          (setcar (cdr entry) end)
        (emmet2-context-web--forget-insertion owner)))
    (setf (emmet2-context-web--state-tick owner) (buffer-chars-modified-tick))))

(defun emmet2-context-web-stop ()
  "Release this buffer's pending scan markers and edit hooks."
  (when-let* ((owner (emmet2-context-web--owner)))
    (emmet2-context-web--forget-insertion owner))
  (setq emmet2-context-web--state nil)
  (remove-hook 'kill-buffer-hook #'emmet2-context-web-stop t)
  (remove-hook 'change-major-mode-hook #'emmet2-context-web-stop t)
  (remove-hook 'before-change-functions #'emmet2-context-web--before-change t)
  (remove-hook 'after-change-functions #'emmet2-context-web--after-change t))

(defun emmet2-context-web-revision ()
  "Return the non-text settings used by web-mode region discovery."
  (list web-mode-engine web-mode-content-type buffer-file-name))

(defun emmet2-context-web--forget-insertion (owner)
  "Release OWNER's single pending CSS scan extent."
  (when-let* ((entry (emmet2-context-web--state-insertion owner)))
    (set-marker (nth 2 entry) nil) (set-marker (nth 3 entry) nil)
    (setf (emmet2-context-web--state-insertion owner) nil)))

(defun emmet2-context-web--remember-insertion (owner beg end)
  "Remember in OWNER a scanned CSS rule before insertion at BEG..END.
The one pending entry is (EDIT-BEG EDIT-END RULE-BEG RULE-END EXPECTED-TICK).
EDIT-END is filled only after a single ordinary character was inserted."
  (emmet2-context-web--forget-insertion owner)
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
                (setf (emmet2-context-web--state-insertion owner)
                      (list beg nil (copy-marker (car rule)) (copy-marker (cdr rule) t)
                            (1+ (buffer-modified-tick))))))))))))

(defun emmet2-context-web-scan ()
  "Flush web-mode's pending scan, rescanning only a remembered CSS rule if valid.
Tokenization belongs to `web-mode'.  Acknowledge its pending range only after a
successful scan of that exact edit; preserve it on errors."
  (let ((owner (emmet2-context-web--owner)))
    (when owner (emmet2-context-web--check-tick owner))
    (let ((entry (when owner (emmet2-context-web--state-insertion owner))))
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
        (when owner (emmet2-context-web--forget-insertion owner))))))

(defun emmet2-context-web--attribute (position)
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

(defun emmet2-context-web-region ()
  "Return (KIND BEG END ATTRIBUTE DIALECT EMBEDDED) at point, or nil.
Flush web-mode's pending scan before reading any boundary.  KIND is markup,
css, javascript, typescript or tsx.  CSS adds ATTRIBUTE, non-nil inside a
style attribute value, DIALECT, which is css, scss or less, and non-nil
EMBEDDED.  Markup and JS need only their bounds."
  (emmet2-context-web-scan)
  (let* ((pos (max (point-min) (1- (point))))
         ;; Point just before a closing tag ends the preceding part, in every embedded language.
         (part-pos (if (get-text-property (point) 'part-side) (point) pos))
         (whole (member web-mode-content-type '("jsx" "javascript" "typescript" "css")))
         (language (if whole web-mode-content-type (web-mode-language-at-pos part-pos)))
         (attribute (unless whole (emmet2-context-web--attribute (point)))))
    (cond
     ((and (not whole) (eq (get-text-property pos 'tag-type) 'comment)) nil)
     ((consp attribute)
      (when (equal (car attribute) "style")
        (list 'css (nth 1 attribute) (nth 2 attribute) t 'css t)))
     ((and (not whole)
           (or attribute (and (get-text-property pos 'tag-type)
                              (not (get-text-property pos 'tag-end))))) nil)
     ((member language '("css" "javascript" "typescript" "jsx" "tsx"))
      (when-let* ((start (if whole (point-min) (web-mode-part-beginning-position part-pos)))
                  (end (if whole (point-max)
                         (next-single-property-change part-pos 'part-side nil (point-max))))
                  (_ (<= start (point) end)))
        (if (equal language "css")
            (progn
              (emmet2-context-web--owner t)
              (list 'css start end nil
                    (pcase (if whole (file-name-extension (or buffer-file-name ""))
                             (emmet2-context-web--style-lang start))
                      ("scss" 'scss) ("less" 'less) (_ 'css)) t))
          (list (pcase language ("typescript" 'typescript) ((or "jsx" "tsx") 'tsx) (_ 'javascript))
                start end))))
     ((member language '("" "html"))
      (let ((start (if (get-text-property pos 'tag-end) (1+ pos)
                     (previous-single-property-change (point) 'tag-end nil (line-beginning-position))))
            (end (if (get-text-property (point) 'tag-beg) (point)
                   (next-single-property-change (point) 'tag-beg nil (line-end-position)))))
        ;; Template blocks belong to the host and bound markup extraction.
        (list 'markup
              (if (and (> (point) start) (get-text-property pos 'block-side)) (point)
                (previous-single-property-change (point) 'block-side nil start))
              (if (get-text-property (point) 'block-side) (point)
                (next-single-property-change (point) 'block-side nil end)) nil))))))

(defun emmet2-context-web--style-lang (start)
  "Return the lowercase lang of the web style part starting at START, or nil."
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
        language))))

(provide 'emmet2-context-web)
;;; emmet2-context-web.el ends here
