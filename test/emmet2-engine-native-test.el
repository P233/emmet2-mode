;;; emmet2-engine-native-test.el --- Public native entry contracts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-engine)

(ert-deftest emmet2-native-entry-presets-and-layout ()
  (should (equal (emmet2-engine-expand "div>span" :indent "  " :base-indent " ")
                 '(:text "<div><span></span></div>" :fields ((11 11 1 "")) :cursor 11)))
  (should (equal (emmet2-engine-expand "color+background" :preset 'stylesheet :base-indent "  ")
                 '(:text "color: ;\n  background: ;" :fields ((7 7 1 "") (23 23 2 "")) :cursor 7)))
  (should (equal (emmet2-engine-expand ".btn-primary" :preset 'jsx
                                      :jsx '(:classAttribute "className" :cssModulesObject "css" :classConstructor ""))
                 '(:text "<div className={css[\"btn-primary\"]}></div>"
                         :fields ((36 36 1 "")) :cursor 36))))

(ert-deftest emmet2-native-entry-seed-is-call-local ()
  (cl-letf (((symbol-function 'random) (lambda (&rest _) (error "Do not use global random"))))
    (let ((first (emmet2-engine-expand "lorem30")))
      (should (equal first (emmet2-engine-expand "lorem30" :seed 0)))
      (should (equal first (emmet2-engine-expand "lorem30" :seed (expt 2 32))))
      (should-not (equal first (emmet2-engine-expand "lorem30" :seed 1)))
      (should (equal first (emmet2-engine-expand "lorem30")))
      (should (equal (emmet2-engine-expand "lorem30" :seed -1)
                     (emmet2-engine-expand "lorem30" :seed #xffffffff)))
      (should (equal (emmet2-engine-expand "m10" :preset 'stylesheet :seed 42)
                     (emmet2-engine-expand "m10" :preset 'stylesheet))))))

(ert-deftest emmet2-native-entry-invalid-options ()
  (dolist (arguments '((nil) ("div" :preset unknown) ("div" :indent nil)
                       ("div" :base-indent 1) ("div" :seed 1.0)
                       ("m" :preset stylesheet :seed nil)
                       ("m" :preset stylesheet :jsx t)
                       ("div" :jsx t) ("div" :preset jsx :jsx (:classAttribute "bad"))))
    (should-error (apply #'emmet2-engine-expand arguments) :type 'emmet2-error)))

(ert-deftest emmet2-native-entry-preserves-enclosing-deadline ()
  (dolist (preset '(html jsx stylesheet))
    (let ((emmet2-engine--deadline 0))
      (should-error (emmet2-engine-expand "a" :preset preset) :type 'emmet2-backend-error)
      (should (= emmet2-engine--deadline 0))))
  (should (equal (plist-get (emmet2-engine-expand "div{after}") :text) "<div>after</div>")))

(ert-deftest emmet2-native-entry-handwritten-fields-and-permissive-input ()
  (should (equal (emmet2-engine-expand "color+background" :preset 'stylesheet)
                 '(:text "color: ;\nbackground: ;" :fields ((7 7 1 "") (21 21 2 "")) :cursor 7)))
  (should (equal (plist-get (emmet2-engine-expand "div{😀}") :text) "<div>😀</div>"))
  (should (equal (emmet2-engine-expand "padding${9007199254740992:x}-${9007199254740993:x}" :preset 'stylesheet)
                 '(:text "padding: x x;" :fields ((9 10 1 "x") (11 12 1 "x")) :cursor 9)))
  (should (stringp (plist-get (emmet2-engine-expand "a{") :text)))
  (should (stringp (plist-get (emmet2-engine-expand "ul>") :text)))
  ;; Raw values belong to the extension layer; the core tokenizer rejects them.
  (should-error (emmet2-engine-expand "top[all 0.3s]" :preset 'stylesheet) :type 'emmet2-parse-error)
  ;; The pinned CSS parser cannot attach a position after consuming a
  ;; delimiter-only input; preserve backend-error instead of inventing one.
  (dolist (input '(":" "-" "," ":-" "+:"))
    (should (equal (should-error (emmet2-engine-expand input :preset 'stylesheet) :type 'emmet2-backend-error)
                   '(emmet2-backend-error "Unexpected token"))))
  (should (equal (emmet2-engine-expand ":+" :preset 'stylesheet) '(:text "" :fields nil :cursor 0))))

(provide 'emmet2-engine-native-test)
;;; emmet2-engine-native-test.el ends here
