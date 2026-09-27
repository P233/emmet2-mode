;;; emmet2-stylesheet-integration-test.el --- CSS through editor boundaries -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-markup-integration-test)
(require 'css-mode)

(ert-deftest emmet2-stylesheet-command-completion-preview-and-yas ()
  (emmet2-integration-test--flows
   '((css-mode ".a{c+bg│}" nil "color: ;\n   background: ;")
     (scss-mode ".a{m10+p.5│}" nil "margin: 10px;\n   padding: 0.5rem;")
     (web-mode "<style>.a{bd+c│}</style>" nil "border: ;\n          color: ;")
     (web-mode "<div style=\"m+p│\"></div>" nil "margin: ;\n            padding: ;")
     (tsx-ts-mode "const A=(<main style={{c+bg│}} />);" nil "color: , background: ")
     (tsx-ts-mode "const A=(<main style={{ct['😀']+m│}} />);" nil "content: \"'😀'\", margin: ")
     (js-mode "const styles=StyleSheet.create({card:{m10+p.5│}});" nil "margin: 10, padding: \"0.5rem\"")
     (web-mode "<script>const styles=StyleSheet.create({card:{c+bg│}});</script>" nil "color: , background: "))))

(ert-deftest emmet2-stylesheet-bare-property-remains-command-only ()
  (with-temp-buffer
    (insert "<style>.a{bd}</style>") (search-backward "bd") (forward-char 2)
    (let ((position (point))) (web-mode) (goto-char position))
    (emmet2-mode 1)
    (should-not (emmet2-capf))
    (emmet2-expand)
    (should (equal (buffer-string) "<style>.a{border: ;}</style>"))))

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
