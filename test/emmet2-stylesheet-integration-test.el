;;; emmet2-stylesheet-integration-test.el --- CSS through editor boundaries -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-markup-integration-test)
(require 'css-mode)

(ert-deftest emmet2-stylesheet-command-completion-preview-and-yas ()
  (emmet2-integration-test--flows
   '((css-mode ".a{c+bg│}" nil "color: ;\n   background: ;")
     (css-ts-mode ".a{c+bg│}" nil "color: ;\n   background: ;")
     (less-css-mode ".a{c+bg│}" nil "color: ;\n   background: ;")
     (css-mode ".a{tac│}" nil "text-align: center;")
     (css-mode ".a{dn│}" nil "display: none;")
     (scss-mode ".a{db│}" nil "display: block;")
     (css-mode ".a{posr│}" nil "position: relative;")
     (css-mode ".a{posa│}" nil "position: absolute;\n   z-index: ;")
     (css-mode ".a{wf│}" nil "width: 100%;")
     (css-mode ".a{bgilg│}" nil "background-image: linear-gradient();")
     (scss-mode ".a{p$gutter│}" nil "padding: $gutter;")
     (web-mode "<style lang=\"scss\">.a{m$a,p$b│}</style>" nil "margin: $a;\n                      padding: $b;")
     (tsx-ts-mode "const A=(<main style={{bgilg│}} />);" nil "backgroundImage: \"linear-gradient()\"")
     (web-mode "<style>.a{tac│}</style>" nil "text-align: center;")
     (web-mode "<div style=\"tac│\"></div>" nil "text-align: center;")
     (tsx-ts-mode "const A=(<main style={{tac│}} />);" nil "textAlign: \"center\"")
     (scss-mode ".a{m10+p.5│}" nil "margin: 10px;\n   padding: 0.5rem;")
     (web-mode "<style>.a{bd+c│}</style>" nil "border: ;\n          color: ;")
     (web-mode "<div style=\"m+p│\"></div>" nil "margin: ;\n            padding: ;")
     (tsx-ts-mode "const A=(<main style={{c+bg│}} />);" nil "color: , background: ")
     (tsx-ts-mode "const A=(<main style={{ct['😀']+m│}} />);" nil "content: \"'😀'\", margin: ")
     (js-mode "const styles=StyleSheet.create({card:{m10+p.5│}});" nil "margin: 10, padding: \"0.5rem\"")
     (js-ts-mode "const styles=StyleSheet.create({card:{m10+p.5│}});" nil "margin: 10, padding: \"0.5rem\"")
     (typescript-ts-mode "const styles=createTheme({card:{c+bg│}});" nil "color: , background: ")
     (web-mode "<script>const styles=StyleSheet.create({card:{c+bg│}});</script>" nil "color: , background: "))))

(ert-deftest emmet2-stylesheet-at-rules-follow-host-syntax ()
  (dolist (case '((css-mode "@i│" "@import ") (css-mode "@us│" "@us")
                  (scss-mode "@us│" "@use \"\";")
                  (web-mode "<style>@im│</style>" "<style>@import </style>")
                  (web-mode "<style lang=\"scss\">@us│</style>" "<style lang=\"scss\">@use \"\";</style>")
                  (web-mode "<style lang=\"less\">@us│</style>" "<style lang=\"less\">@us</style>")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (nth 1 case)) (search-backward "│") (delete-char 1)
        (let ((position (point))) (funcall (car case)) (goto-char position))
        (emmet2-mode 1)
        (emmet2-test--complete-first)
        (should (equal (buffer-string) (nth 2 case)))))))

(ert-deftest emmet2-stylesheet-property-prefix-offers-completion ()
  (with-temp-buffer
    (insert "<style>.a{bd}</style>") (search-backward "bd") (forward-char 2)
    (let ((position (point))) (web-mode) (goto-char position))
    (emmet2-mode 1)
    (let* ((data (emmet2-capf)) (props (nthcdr 3 data))
           (candidates (all-completions "bd" (nth 2 data)))
           (labels (mapcar #'cadr (funcall (plist-get props :affixation-function) candidates))))
      (should (equal (car labels) "border: ;"))
      (should (member "border-color: ;" labels)))
    (emmet2-test--complete-first)
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
        ;; A property's value stays with the host even on request.
        (should-error (emmet2-complete) :type 'user-error)
        (should (equal source (buffer-string)))
        (should (= position (point))))))
  ;; A known element makes the same shape a nested selector choice.  Manual
  ;; built-in CSS requests no longer reinterpret an ambiguous property value.
  (dolist (case '(("button:hv" nil ".a{button:hover}") ("my-card:hv" t ".a{my-card:hover}")))
    (with-temp-buffer
      (insert ".a{" (car case) "}") (css-mode) (backward-char) (emmet2-mode 1)
      (should (eq (null (emmet2-capf)) (nth 1 case)))
      (if (nth 1 case)
          (let ((source (buffer-string)))
            (should-error (emmet2-complete) :type 'user-error)
            (should (equal source (buffer-string))))
        (emmet2-test--complete-first)
        (should (string-prefix-p (nth 2 case) (buffer-string)))))))

(ert-deftest emmet2-stylesheet-css-ts-mode-is-a-css-host ()
  ;; css-ts-mode shares css-base-mode with css-mode but is not derived from it.
  ;; Exercise the real parser and the mode's no-grammar fallback independently.
  (dolist (grammar '(t nil))
    (dolist (case '((".a{m10│}" t ".a{margin: 10px;}") ("m10│" nil nil) ("@md│" t nil)))
      (ert-info ((format "CSS grammar: %S, source: %s" grammar (car case)))
        (with-temp-buffer
          (if grammar
              (progn
                (css-ts-mode)
                (should (seq-some (lambda (parser) (eq (treesit-parser-language parser) 'css))
                                  (treesit-parser-list))))
            (cl-letf (((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
              (css-ts-mode))
            (should-not (treesit-parser-list)))
          (insert (car case)) (search-backward "│") (delete-char 1) (emmet2-mode 1)
          (should (eq (null (emmet2-capf)) (null (nth 1 case))))
          (when (nth 2 case)
            (emmet2-test--complete-first)
            (should (equal (buffer-string) (nth 2 case)))))))))

(ert-deftest emmet2-stylesheet-requests-need-an-insertable-position ()
  ;; A request skips confidence checks, never syntax.
  (dolist (case '((css-mode "m10│") (css-mode ".card│") (css-mode "button│")
                  (scss-mode "$primary: re│") (scss-mode ".a { @include bre│; }")
                  (scss-mode ".a { width: math.div(10px, 2│) }") (scss-mode ".a { @extend %bt│; }")
                  (scss-mode ".a-#{$x│} { }") (css-mode ".a { color: re│ }")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (cadr case)) (funcall (car case)) (search-backward "│") (delete-char 1) (emmet2-mode 1)
        (let ((source (buffer-string)))
          (should-error (emmet2-complete) :type 'user-error)
          (should (equal (buffer-string) source))))))
  (dolist (case '((css-mode ".a { m10│ }" ".a { margin: 10px; }") (css-mode "button:hv│" "button:hover")
                  (css-mode "@md│" "@media ") (scss-mode "%btn { m10│ }" "%btn { margin: 10px; }")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (cadr case)) (funcall (car case)) (search-backward "│") (delete-char 1) (emmet2-mode 1)
        (emmet2-test--complete-first)
        (should (string-prefix-p (nth 2 case) (buffer-string)))))))

(ert-deftest emmet2-stylesheet-pseudos-complete-without-rule-bodies ()
  (dolist (mode '(css-mode css-ts-mode scss-mode less-css-mode))
    (emmet2-integration-test--flows
     (mapcar (lambda (case) (cons mode case))
             '((".a::be│" nil ".a::before")
               (".a::af│" nil ".a::after")
               (".a::selection│" nil ".a::selection")
               (".a::part│" nil ".a::part()")
               (".a {\n  &::be│\n}" nil "&::before")
               (".a {\n  &::af│\n}" nil "&::after")))))
  (emmet2-integration-test--flows
   '((web-mode "<style>.a::be│</style>" nil ".a::before")
     (web-mode "<style lang=\"scss\">.a { &::af│ }</style>" nil "&::after")
     (web-mode "<style>.a::part│</style>" nil ".a::part()"))))

(ert-deftest emmet2-stylesheet-selector-boundaries-share-completion-rules ()
  (dolist (mode '(css-mode scss-mode))
    (emmet2-integration-test--flows
     (mapcar (lambda (case) (cons mode case))
             '((".a,:hv│" nil ".a,:hover")
               (".a, :hv│" nil ".a, :hover")
               (".card[disabled]:hv│" nil ".card[disabled]:hover")
               ("button[data-label='a:b']:hv│" nil "button[data-label='a:b']:hover")
               (".card>.child:hv│" nil ".card>.child:hover")
               (".card > .child:hv│" nil ".card > .child:hover")
               (".outer {\n  .a,:hv│\n}" nil ".a,:hover")
               (".outer {\n  .a, :hv│\n}" nil ".a, :hover")
               (".outer {\n  .card[disabled]:hv│\n}" nil ".card[disabled]:hover")
               (".outer {\n  .card > .child:hv│\n}" nil ".card > .child:hover")
               (".outer {\n  &:not(.a,.b)>.child:hv│\n}" nil "&:not(.a,.b)>.child:hover"))))))

(ert-deftest emmet2-stylesheet-selector-prefix-cannot-reclassify-a-value ()
  (dolist (mode '(css-mode css-ts-mode scss-mode less-css-mode))
    (dolist (source '(".a { color:red .card:hv│ }"
                      ".a { color: .card[disabled]:hv│ }"
                      ".a { --value: .card>.child:hv│ }"
                      ".a { content: ':hv│' }"
                      ".a { @include mixin(.card:hv│); }"))
      (with-temp-buffer
        (funcall mode) (insert source) (search-backward "│") (delete-char 1)
        (emmet2-mode 1)
        (should-not (emmet2-capf))
        (should-error (emmet2-complete) :type 'user-error)))))

(ert-deftest emmet2-stylesheet-pseudo-completion-preserves-authored-tail ()
  (dolist (case '((css-mode ".a::be│ { color: red; }" ".a::before│ { color: red; }")
                  (css-mode ".a::be│ { content: attr(data-label); }" ".a::before│ { content: attr(data-label); }")
                  (css-mode ".a::be│\n{}" ".a::before│\n{}")
                  (scss-mode ".a { &::be│ {} }" ".a { &::before│ {} }")
                  (css-mode ".a:hv│ .child {}" ".a:hover│ .child {}")
                  (css-mode ".a:hv│ .child:focus {}" ".a:hover│ .child:focus {}")
                  (css-mode ".a::be│ .child:hv {}" ".a::before│ .child:hv {}")
                  (web-mode "<style>.a::be│ {}</style>" "<style>.a::before│ {}</style>")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (nth 1 case)) (search-backward "│") (delete-char 1)
        (let ((position (point))) (funcall (car case)) (goto-char position))
        (emmet2-mode 1)
        (emmet2-test--complete-first)
        (should (equal (concat (buffer-substring (point-min) (point)) "│"
                               (buffer-substring (point) (point-max)))
                       (nth 2 case)))))))

(ert-deftest emmet2-stylesheet-core-fields-edit-independently-through-yas ()
  ;; Bypass opinionated default removal to verify the actual core's mirrored
  ;; and conflicting defaults through the existing insertion owner.
  (emmet2-test-with-insertion t
    (let ((result (emmet2-engine-expand "padding${2:😀}-${1:x}-${2:😀}-${1:y}+margin${1:z}" :preset 'stylesheet)))
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
