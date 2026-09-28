;;; emmet2-stylesheet-integration-test.el --- CSS through editor boundaries -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-markup-integration-test)
(require 'css-mode)

(ert-deftest emmet2-stylesheet-command-completion-preview-and-yas ()
  (emmet2-integration-test--flows
   '((css-mode ".a{c+bg│}" nil "color: ;\n   background: ;")
     (css-mode ".a{tac│}" nil "text-align: center;")
     (css-mode ".a{dn│}" nil "display: none;")
     (scss-mode ".a{db│}" nil "display: block;")
     (css-mode ".a{posr│}" nil "position: relative;")
     (css-mode ".a{posa│}" nil "position: absolute;\n   z-index: ;")
     (css-mode ".a{wf│}" nil "width: 100%;")
     (web-mode "<style>.a{tac│}</style>" nil "text-align: center;")
     (web-mode "<div style=\"tac│\"></div>" nil "text-align: center;")
     (tsx-ts-mode "const A=(<main style={{tac│}} />);" nil "textAlign: \"center\"")
     (scss-mode ".a{m10+p.5│}" nil "margin: 10px;\n   padding: 0.5rem;")
     (web-mode "<style>.a{bd+c│}</style>" nil "border: ;\n          color: ;")
     (web-mode "<div style=\"m+p│\"></div>" nil "margin: ;\n            padding: ;")
     (tsx-ts-mode "const A=(<main style={{c+bg│}} />);" nil "color: , background: ")
     (tsx-ts-mode "const A=(<main style={{ct['😀']+m│}} />);" nil "content: \"'😀'\", margin: ")
     (js-mode "const styles=StyleSheet.create({card:{m10+p.5│}});" nil "margin: 10, padding: \"0.5rem\"")
     (web-mode "<script>const styles=StyleSheet.create({card:{c+bg│}});</script>" nil "color: , background: "))))

(ert-deftest emmet2-stylesheet-at-rules-follow-host-syntax ()
  (dolist (case '((css-mode "@i│" "@import url();") (css-mode "@us│" "@us")
                  (scss-mode "@us│" "@use \"\";")
                  (web-mode "<style>@im│</style>" "<style>@import url();</style>")
                  (web-mode "<style lang=\"scss\">@us│</style>" "<style lang=\"scss\">@use \"\";</style>")
                  (web-mode "<style lang=\"less\">@us│</style>" "<style lang=\"less\">@us</style>")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (nth 1 case)) (search-backward "│") (delete-char 1)
        (let ((position (point))) (funcall (car case)) (goto-char position))
        (emmet2-mode 1)
        (emmet2-expand)
        (should (equal (buffer-string) (nth 2 case)))))))

(ert-deftest emmet2-stylesheet-property-prefix-offers-completion ()
  (with-temp-buffer
    (insert "<style>.a{bd}</style>") (search-backward "bd") (forward-char 2)
    (let ((position (point))) (web-mode) (goto-char position))
    (emmet2-mode 1)
    (let* ((data (emmet2-capf)) (props (nthcdr 3 data))
           (candidates (all-completions "bd" (nth 2 data)))
           (labels (mapcar #'cadr (funcall (plist-get props :affixation-function) candidates))))
      (should (member "border: ;" labels))
      (should (member "border-color: ;" labels)))
    (emmet2-expand)
    (should (equal (buffer-string) "<style>.a{border: ;}</style>"))))

(ert-deftest emmet2-stylesheet-unspaced-values-stay-with-host-completion ()
  (dolist (case '((css-mode ".a{display:fl│}")
                  (scss-mode ".a{--accent:re│}")
                  (web-mode "<div style='display:fl│'></div>")))
    (with-temp-buffer
      (insert (cadr case)) (funcall (car case))
      (search-backward "│") (delete-char 1) (emmet2-mode 1)
      (let ((source (buffer-string)) (position (point)))
        (should-not (emmet2-capf))
        (should-error (emmet2-complete) :type 'user-error)
        (should (equal source (buffer-string)))
        (should (= position (point))))))
  (with-temp-buffer
    (insert ".a{button:hv}") (css-mode) (backward-char)
    (emmet2-expand)
    (should (string-prefix-p ".a{button:hover {" (buffer-string)))))

(ert-deftest emmet2-stylesheet-core-fields-edit-independently-through-yas ()
  ;; Bypass opinionated default removal to verify the actual core's mirrored
  ;; and conflicting defaults through the existing insertion owner.
  (emmet2-test-with-insertion t
    (let ((result (emmet2-engine-expand "p${2:😀}-${1:x}-${2:😀}-${1:y}+m${1:z}" :preset 'stylesheet)))
      (emmet2-insert snapshot result)
      (insert "first") (yas-next-field)
      (insert "second") (yas-next-field)
      (insert "pair") (yas-next-field)
      (insert "last") (yas-next-field)
      (should (equal (buffer-string) "padding: pair first pair second;\nmargin: last;"))
      (should (= (point) (point-max)))
      (run-hooks 'post-command-hook)
      (should-not (yas-active-snippets)))))

(provide 'emmet2-stylesheet-integration-test)
;;; emmet2-stylesheet-integration-test.el ends here
