;;; emmet2-extract-test.el --- Bounded extraction tests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-extract)

(ert-deftest emmet2-extract-positions-and-host-delimiters ()
  (dolist (abbreviation '("ul>li*3" "div{hello world}" "(a+b)*2" "a[href='a b']"
                          "p[1px 2px]" "m1,p2" ":not(.a,.b)" "p(calc(1 + 2))"
                          "p{don't (stop [now]}" "p{one {two} three}"
                          "div{😀}" "ul>"))
    (with-temp-buffer
      (insert "  " abbreviation ");}")
      (cl-loop for position from 3 to (+ 3 (length abbreviation)) do
               (goto-char position)
               (let ((result (emmet2-extract (point-min) (point-max))))
                 (should (equal (plist-get result :abbr) abbreviation))
                 (should (= (plist-get result :beg) 3))
                 (should (= (plist-get result :end) (+ 3 (length abbreviation)))))))))

(ert-deftest emmet2-extract-incomplete-groups-use-region-limit ()
  (with-temp-buffer
    (insert "a{unfinished")
    (should (equal (plist-get (emmet2-extract 1 (point-max)) :abbr)
                   "a{unfinished"))))

(ert-deftest emmet2-extract-honors-region-and-point ()
  (with-temp-buffer
    (insert "prefixul>li</main>")
    (goto-char 11)
    (should (equal (emmet2-extract 7 (point-max))
                   '(:beg 7 :end 12 :abbr "ul>li")))
    (goto-char 6)
    (should-not (emmet2-extract 7 (point-max))))
  (with-temp-buffer
    (insert "a  b")
    (goto-char 3)
    (should-not (emmet2-extract (point-min) (point-max)))))

(provide 'emmet2-extract-test)
;;; emmet2-extract-test.el ends here
