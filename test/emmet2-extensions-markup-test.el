;;; emmet2-extensions-markup-test.el --- Markup extension contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-extensions)

;; Legacy fixtures exercise their original, explicitly configured names.
(dolist (entry (with-temp-buffer
                 (insert-file-contents (expand-file-name "test/fixtures/markup-legacy.json" emmet2-test-root))
                 (json-parse-buffer :object-type 'alist :array-type 'list :false-object nil)))
  (let* ((solid (alist-get 'solid entry))
         ;; The frozen fixtures expect invalid empty JSX expressions for these
         ;; three cases; expansion gives editable empty keys instead.
         (expected (pcase (alist-get 'id entry)
                     ("markup-007" "<div className={css[\"\"]}></div>")
                     ("markup-015" "<ABC className={css[\"\"]} />")
                     ("markup-016" "<div class={style[\"\"]}></div>")
                     (_ (alist-get 'text entry))))
         (args (list (alist-get 'abbreviation entry) :jsx (alist-get 'jsx entry)
                     :variant (and solid "solid") :css-modules-object (if solid "style" "css")
                     :class-names-constructor (if solid "classnames" "clsx"))))
    (eval `(ert-deftest ,(intern (concat "emmet2-markup-legacy-" (alist-get 'id entry))) ()
             (should (equal (plist-get (apply #'emmet2-extensions-markup ',args) :text)
                            ,expected))) t)))

(ert-deftest emmet2-markup-extension-fields-and-unicode ()
  (should (equal (emmet2-extensions-markup "." :jsx t)
                 '(:text "<div className={styles[\"\"]}></div>" :fields ((24 24 1 "") (28 28 2 "")) :cursor 24)))
  (should (equal (emmet2-extensions-markup "div{😀}+div[class='😸']" :jsx t)
                 '(:text "<div>😀</div>\n<div className={styles[\"😸\"]}></div>"
                         :fields ((42 42 1 "")) :cursor 42)))
  (should (equal (emmet2-extensions-markup "div{${1:x} ${1:x}}")
                 '(:text "<div>x x</div>" :fields ((5 6 1 "x") (7 8 1 "x")) :cursor 5)))
  (should (equal (emmet2-extensions-markup "[class='${1:a} ${1:a}']" :jsx t)
                 '(:text "<div className={clsx(styles.a, styles.a)}></div>"
                         :fields ((28 29 1 "a") (38 39 1 "a") (42 42 2 "")) :cursor 28))))

(ert-deftest emmet2-markup-extension-escapes-class-keys ()
  (dolist (pair '(("[class='a\"b']" . "<div className={styles[\"a\\\"b\"]}></div>")
                   ("[class='a\\\\b']" . "<div className={styles[\"a\\\\b\"]}></div>")
                   (".foo-bar" . "<div className={styles[\"foo-bar\"]}></div>")
                   ("[class='a\" title=\"b']" . "<div className={clsx(styles[\"a\\\"\"], styles[\"title=\\\"b\"])}></div>")))
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

(ert-deftest emmet2-markup-extension-hyphenated-class-regression ()
  (should (equal (emmet2-extensions-markup ".btn-primary" :jsx t)
                 '(:text "<div className={styles[\"btn-primary\"]}></div>"
                         :fields ((39 39 1 "")) :cursor 39)))
  (should (equal (emmet2-extensions-markup ".btn-primary" :jsx t :variant "solid")
                 '(:text "<div class={styles[\"btn-primary\"]}></div>"
                         :fields ((35 35 1 "")) :cursor 35))))

(ert-deftest emmet2-markup-dialects-own-attribute-mappings ()
  (should (equal (plist-get (emmet2-extensions-markup "label.a[for=field]" :jsx t) :text)
                 "<label htmlFor=\"field\" className={styles.a}></label>"))
  (should (equal (plist-get (emmet2-extensions-markup "label.a[for=field]" :jsx t :variant "solid") :text)
                 "<label for=\"field\" class={styles.a}></label>"))
  (should (equal (plist-get (emmet2-engine-expand "label[for=field]" :preset 'jsx) :text)
                 "<label htmlFor=\"field\"></label>")))

(ert-deftest emmet2-markup-underscore-and-plain-style-keep-class-strings ()
  (should (equal (emmet2-extensions-markup "_.card.active" :jsx t)
                 '(:text "<div className=\"card active\"></div>" :fields ((29 29 1 "")) :cursor 29)))
  (should (equal (plist-get (emmet2-extensions-markup "_Button.primary/" :jsx t) :text)
                 "<Button className=\"primary\" />"))
  (should (equal (plist-get (emmet2-extensions-markup "_label.a[for=x]" :jsx t :variant "solid") :text)
                 "<label for=\"x\" class=\"a\"></label>"))
  (should (equal (plist-get (emmet2-extensions-markup "_ul>li.x") :text) "<ul>\n\t<li class=\"x\"></li>\n</ul>"))
  (should (equal (plist-get (emmet2-extensions-markup ".a.b" :jsx t :class-style 'plain) :text)
                 "<div className=\"a b\"></div>"))
  (should (equal (emmet2-extensions-markup "." :jsx t :class-style 'plain)
                 '(:text "<div className=\"\"></div>" :fields ((16 16 1 "") (18 18 2 "")) :cursor 16)))
  (should-error (emmet2-extensions-markup ".a" :jsx t :class-style 'tailwind) :type 'emmet2-error))

(ert-deftest emmet2-markup-class-inputs-have-domain-errors ()
  (dolist (option '(:css-modules-object :class-names-constructor))
    (dolist (value '("" " \t\n" nil))
      (should-error (apply #'emmet2-extensions-markup ".a.b" :jsx t (list option value))
                    :type 'emmet2-error)))
  (dolist (character '(#x3fff80 #xd800 #x110000))
    (should-error (emmet2-extensions-markup (concat "[class=\"" (string character) "\"]") :jsx t)
                  :type 'emmet2-error)))

(provide 'emmet2-extensions-markup-test)
;;; emmet2-extensions-markup-test.el ends here
