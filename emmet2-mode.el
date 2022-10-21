(require 'deno-bridge)

(defconst emmet2-backend-path (concat (file-name-directory load-file-name) "src/index.ts"))
(deno-bridge-start "emmet2" emmet2-backend-path)
;; (deno-bridge-exit)

(defvar emmet2-target-lang "css"
  "Emmet2 abbreviations target language.")

(defun emmet2-expand-css ()
  (when (thing-at-point-looking-at "[a-zA-Z0-9_#.:(+,)$!-]+")
    (let* ((bounds-beginning (match-beginning 0))
           (bounds-end (match-end 0))
           (abbr (buffer-substring-no-properties bounds-beginning bounds-end)))
      (delete-region bounds-beginning bounds-end)
      (deno-bridge-call "emmet2" "css" abbr bounds-beginning))))

(defun emmet2-expand-html ()
  (when (thing-at-point-looking-at "[a-zA-Z0-9_#./>~+-]+")
    (let* ((bounds-beginning (match-beginning 0))
           (bounds-end (match-end 0))
           (abbr (buffer-substring-no-properties bounds-beginning bounds-end)))
      (delete-region bounds-beginning bounds-end)
      (deno-bridge-call "emmet2" "html" abbr bounds-beginning))))

(defun emmet2-expand ()
  (interactive)
  (if (string-equal emmet2-target-lang "css")
      (emmet2-expand-css)
    (emmet2-expand-html)))

;;;###autoload
(define-minor-mode emmet2-mode
  "Minor mode for expanding emmet html and css abbreviations with opinionated enhancements."
  :lighter " emmet2"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-j") 'emmet2-expand)
            map)
  (make-local-variable 'emmet2-target-lang))
