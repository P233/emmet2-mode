;;; emmet2-fuzzy-test.el --- Project search contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-fuzzy)

(ert-deftest emmet2-fuzzy-ordered-characters-and-positions ()
  (dolist (case '(("ins" "inset" (0 1 2))
                  ("IS" "inline-size" (0 7))
                  ("size" "inline-size" (7 8 9 10))
                  ("bb" "a-bb" (2 3))
                  ("aa" "a-aa" (0 2))
                  ("😀c" "😀abc" (0 3))
                  ("ЯБ" "яблоко" (0 1)) ("iя" "IЯx" (0 1))))
    (let* ((query (nth 0 case)) (candidate (nth 1 case))
           (match (emmet2-fuzzy-match query candidate)))
      (should (equal (plist-get match :positions) (nth 2 case)))
      (should (< 0 (plist-get match :score) 1))))
  (dolist (case '(("" "") ("" "x") ("a" "") ("abb" "abc")
                  ("ba" "ab") ("xyz" "inset")))
    (should-not (emmet2-fuzzy-match (car case) (cadr case)))))

(ert-deftest emmet2-fuzzy-ranking-and-stable-ties ()
  (let ((query "is") (ordered '("is" "isolation" "inline-size" "border-island" "inset")))
    (should (equal (emmet2-fuzzy-filter query (reverse ordered)) ordered)))
  (should (= (plist-get (emmet2-fuzzy-match "AB" "ab") :score) 1.0))
  (should (equal (emmet2-fuzzy-filter "ab" '("abc" "abd")) '("abc" "abd")))
  (should (equal (emmet2-fuzzy-filter "ab" '("AB" "ab")) '("AB" "ab"))))

(ert-deftest emmet2-fuzzy-partial-is-explicit-and-never-reuses-characters ()
  (should-not (emmet2-fuzzy-match "ovh" "ov"))
  (should (equal (plist-get (emmet2-fuzzy-match "ovh" "ov" t) :positions) '(0 1)))
  (should (< 0 (plist-get (emmet2-fuzzy-match "ovh" "ov" t) :score) 1))
  (should (equal (plist-get (emmet2-fuzzy-match "abb" "abc" t) :positions) '(0 1))))

(ert-deftest emmet2-fuzzy-filter-keeps-input-and-requires-complete-query ()
  (let* ((items '(("inset" . 1) ("inline-size" . 2) ("insert" . 3)))
         (before (copy-tree items)))
    (should (equal (mapcar #'car (emmet2-fuzzy-filter "ins" items #'car))
                   '("inset" "insert" "inline-size")))
    (should-not (emmet2-fuzzy-filter "insetzz" items #'car))
    (should (equal items before))
    (should (equal items (emmet2-fuzzy-filter "" items #'car)))
    (should-not (eq items (emmet2-fuzzy-filter "" items #'car)))))

(ert-deftest emmet2-fuzzy-long-literal-match-keeps-only-viable-columns ()
  (let* ((tail (make-string 4095 ?A))
         (query (concat "m" tail)) (candidate (concat "m: " tail ";"))
         (before (nth 2 (memory-use-counts)))
         (positions (plist-get (emmet2-fuzzy-match query candidate) :positions)))
    (should (equal positions (cons 0 (number-sequence 3 (+ 2 (length tail))))))
    ;; About 20,000 vector cells; a full query-by-candidate matrix would take 16.8 million.
    (should (< (- (nth 2 (memory-use-counts)) before) 200000))))

(ert-deftest emmet2-fuzzy-positions-index-candidates-that-lowercase-longer ()
  ;; String downcasing turns İ into two characters.
  (dolist (candidate '("İstanbul" "İSTANBUL"))
    (ert-info (candidate)
      (should (equal (plist-get (emmet2-fuzzy-match "al" candidate) :positions) '(3 7)))
      (should (equal (plist-get (emmet2-fuzzy-match "AL" candidate t) :positions) '(3 7)))))
  (should (equal (emmet2-fuzzy-filter "al" '("İstanbul" "alpha")) '("alpha" "İstanbul"))))

(ert-deftest emmet2-fuzzy-highlight-marks-each-contiguous-run-once ()
  (let ((label (copy-sequence "abcdefg")))
    (should (eq (emmet2-fuzzy--highlight '(0 1 2 5) label) label))
    (should (equal (object-intervals label)
                   '((0 3 (face completions-common-part)) (3 5 nil)
                     (5 6 (face completions-common-part)) (6 7 nil))))))

(provide 'emmet2-fuzzy-test)
;;; emmet2-fuzzy-test.el ends here
