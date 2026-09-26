;;; emmet2-fuzzy-test.el --- Scoring contract tests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-fuzzy)

(ert-deftest emmet2-fuzzy-upstream-scoring ()
  ;; Independent arithmetic anchors for the published algorithm, including
  ;; its repeated-character position reuse and unmatched suffix semantics.
  (dolist (case '(("" "" nil 1) ("" "x" nil 0) ("a" "" nil 0)
                  ("a" "b" nil 0) ("AB" "ab" nil 1)
                  ("abd" "abcde" nil 0.55) ("abd" "abc-de" nil 0.5)
                  ("ab" "abc" nil 0.6666666666666666)
                  ("ax" "ab" nil 0) ("ax" "ab" t 0.3333333333333333)
                  ("abcx" "abc" nil 0) ("abcx" "abc" t 0.75)
                  ("abb" "abc" nil 1.1666666666666667)))
    (pcase-let ((`(,a ,b ,partial ,expected) case))
      (should (< (abs (- (emmet2-fuzzy-score a b partial) expected)) 1e-12)))))

(ert-deftest emmet2-fuzzy-selection-contract ()
  (should (equal (emmet2-fuzzy-find "ab" '("abc" "abd")) "abd"))
  (should (equal (emmet2-fuzzy-find "ab" '("AB" "ab")) "AB"))
  (should-not (emmet2-fuzzy-find "ab" '("abc") 0.7))
  (should-not (emmet2-fuzzy-find "x" '("abc")))
  (should (equal (emmet2-fuzzy-find "abcx" '("abc") 0.7 t) "abc"))
  (should (equal (emmet2-fuzzy-find "ab" '(("abc" . 1) ("abd" . 2)) nil nil #'car)
                 '("abd" . 2))))

(provide 'emmet2-fuzzy-test)
;;; emmet2-fuzzy-test.el ends here
