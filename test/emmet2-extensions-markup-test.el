;;; emmet2-extensions-markup-test.el --- Markup extension contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-extensions)

(dolist (entry (with-temp-buffer
                 (insert-file-contents (expand-file-name "test/fixtures/markup-legacy.json" emmet2-test-root))
                 (json-parse-buffer :object-type 'alist :array-type 'list :false-object nil)))
  (let* ((solid (alist-get 'solid entry))
         (args (list (alist-get 'abbreviation entry) :jsx (alist-get 'jsx entry)
                     :variant (and solid "solid") :css-modules-object (if solid "style" "css")
                     :class-names-constructor (if solid "classnames" "clsx"))))
    (eval `(ert-deftest ,(intern (concat "emmet2-markup-legacy-" (alist-get 'id entry))) ()
             (should (equal (plist-get (apply #'emmet2-extensions-markup ',args) :text)
                            ,(alist-get 'text entry)))) t)))

(ert-deftest emmet2-markup-extension-fields-and-unicode ()
  (should (equal (emmet2-extensions-markup "." :jsx t)
                 '(:text "<div className={}></div>" :fields ((16 16 1 "") (18 18 2 "")) :cursor 16)))
  (should (equal (emmet2-extensions-markup "div{😀}+div[class='😸']" :jsx t)
                 '(:text "<div>😀</div>\n<div className={css[\"😸\"]}></div>"
                         :fields ((39 39 1 "")) :cursor 39)))
  (should (equal (emmet2-extensions-markup "div{${1:x} ${1:x}}")
                 '(:text "<div>x x</div>" :fields ((5 6 1 "x") (7 8 1 "x")) :cursor 5)))
  (should (equal (emmet2-extensions-markup "[class='${1:a} ${1:a}']" :jsx t)
                 '(:text "<div className={clsx(css.a, css.a)}></div>"
                         :fields ((25 26 1 "a") (32 33 1 "a") (36 36 2 "")) :cursor 25))))

(ert-deftest emmet2-markup-extension-escapes-class-keys ()
  (dolist (pair '(("[class='a\"b']" . "<div className={css[\"a\\\"b\"]}></div>")
                   ("[class='a\\\\b']" . "<div className={css[\"a\\\\b\"]}></div>")
                   (".foo-bar" . "<div className={css[\"foo-bar\"]}></div>")
                   ("[class='a\" title=\"b']" . "<div className={clsx(css[\"a\\\"\"], css[\"title=\\\"b\"])}></div>")))
    (ert-info ((car pair))
      (should (equal (plist-get (emmet2-extensions-markup (car pair) :jsx t) :text) (cdr pair)))))
  (should (equal (plist-get (emmet2-extensions-markup "[class={foo}]" :jsx t :variant "solid") :text)
                 "<div class={foo}></div>"))
  (should (equal (plist-get (emmet2-extensions-markup "[classList={foo}]" :jsx t :variant "solid") :text)
                 "<div classList={foo}></div>")))

(ert-deftest emmet2-markup-extension-options-layout-and-source ()
  (with-temp-buffer
    (insert "source") (goto-char 3)
    (let ((tick (buffer-chars-modified-tick)))
      (should (equal (emmet2-extensions-markup "div>.a.b" :jsx t :variant "solid"
                                              :css-modules-object "styles.module"
                                              :class-names-constructor "helpers.cx"
                                              :indent "  " :base-indent "    ")
                     '(:text "<div>\n      <div class={helpers.cx(styles.module.a, styles.module.b)}></div>\n    </div>"
                             :fields ((70 70 1 "")) :cursor 70)))
      (should (= tick (buffer-chars-modified-tick)))
      (should (= (point) 3))
      (should (equal (buffer-string) "source")))))

(provide 'emmet2-extensions-markup-test)
;;; emmet2-extensions-markup-test.el ends here
