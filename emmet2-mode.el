(require 'deno-bridge)

(defconst emmet2-backend-path (concat (file-name-directory load-file-name) "src/index.ts"))
(deno-bridge-start "emmet2" emmet2-backend-path)

(defvar emmet2-file-extension "")
(defvar emmet2-markup-varient nil)
(defvar emmet2-css-modules-object "css")
(defvar emmet2-class-names-constructor "clsx")

(defun emmet2-after-hook ()
  (make-local-variable 'emmet2-file-extension)
  (make-local-variable 'emmet2-markup-varient)
  (make-local-variable 'emmet2-css-modules-object)
  (make-local-variable 'emmet2-class-names-constructor)
  (setq emmet2-file-extension (file-name-extension buffer-file-name)))

(defun emmet2-check-in-between (open close)
  (let ((backward-open (save-excursion (re-search-backward open nil t)))
        (backward-close (save-excursion (re-search-backward close nil t)))
        (forward-open (save-excursion (re-search-forward open nil t)))
        (forward-close (save-excursion (re-search-forward close nil t)))) 
    (and backward-open forward-close
         (or (not backward-close) (> backward-open backward-close))
         (or (not forward-open) (< forward-close forward-open)))))

(defun emmet2-detect-css-in-markup ()
  (or
   (emmet2-check-in-between "style=[\"']" "[^=][\"']")
   (emmet2-check-in-between "<style" "</style>")))

(defun emmet2-detect-expand-lang ()
  (cond ((member emmet2-file-extension '("scss" "css")) "css")
        ((emmet2-detect-css-in-markup) "css")
        ((stringp emmet2-markup-varient) emmet2-markup-varient)
        ((member emmet2-file-extension '("tsx" "jsx")) "jsx")
        (t "html")))

(defun emmet2-expand-css ()
  (when (thing-at-point-looking-at "@?[a-zA-Z0-9_#.:(+,)$!-]+")
    (let* ((bounds-beginning (match-beginning 0))
           (bounds-end (match-end 0))
           (abbr (buffer-substring-no-properties bounds-beginning bounds-end)))
      (delete-region bounds-beginning bounds-end)
      (deno-bridge-call "emmet2" "css" abbr bounds-beginning))))

(defun emmet2-expand-markup (lang)
  (when (thing-at-point-looking-at "^[[:space:]]*\\(.+\\)$")
    (let* ((bounds-beginning (match-beginning 1))
           (bounds-end (match-end 1))
           (abbr (buffer-substring-no-properties bounds-beginning bounds-end)))
      (delete-region bounds-beginning bounds-end)
      (deno-bridge-call "emmet2" lang abbr bounds-beginning emmet2-css-modules-object emmet2-class-names-constructor))))

(defun emmet2-expand ()
  (interactive)
  (let ((lang (emmet2-detect-expand-lang)))
    (if (string-equal lang "css")
        (emmet2-expand-css)
      (emmet2-expand-markup lang))))

(defun emmet2-insert (snippet bounds-beginning reposition)
  (insert snippet)
  (indent-region bounds-beginning (point))
  (when reposition
    (re-search-backward "|" bounds-beginning t)
    (delete-char 1)))

;;;###autoload
(define-minor-mode emmet2-mode
  "Minor mode for expanding emmet html and css abbreviations with opinionated enhancements."
  :lighter " emmet2"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-j") 'emmet2-expand)
            map)
  :after-hook (emmet2-after-hook))


(provide 'emmet2-mode)
