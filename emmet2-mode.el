(require 'deno-bridge)

(defconst emmet2-backend-path (concat (file-name-directory (buffer-file-name)) "src/index.ts"))
(deno-bridge-start "emmet2" emmet2-backend-path)
;; (deno-bridge-exit)

(defconst html-abbr-regex "") ;; #page>div.logo+ul#navigation>li*5>a{Item $}
(defconst css-abbr-regex "[a-z0-9+!]+")

(defun emmet2-expand ()
  (interactive)
  (when (thing-at-point-looking-at css-abbr-regex)
    (let* ((bounds-beginning (match-beginning 0))
           (bounds-end (match-end 0))
           (abbr (buffer-substring-no-properties bounds-beginning bounds-end)))
      (delete-region bounds-beginning bounds-end)
      (deno-bridge-call "emmet2" "expand-css" abbr))))
