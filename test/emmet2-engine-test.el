;;; emmet2-engine-test.el --- Result transformation contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'json)
(require 'emmet2-engine)

(ert-deftest emmet2-result-character-offsets-and-mirrors ()
  (should (equal (emmet2-result-create "😀 x x" '((4 5 9 "x") (2 3 9 "x") (1 1 3 "")))
                 '(:text "😀 x x" :fields ((1 1 1 "") (2 3 2 "x") (4 5 2 "x")) :cursor 1)))
  (should (equal (emmet2-result-create "😀") '(:text "😀" :fields nil :cursor 1)))
  (should (equal (emmet2-result-create "x" '((0 1 2 "x") (0 0 1 "")))
                 '(:text "x" :fields ((0 1 2 "x") (0 0 1 "")) :cursor 0)))
  (should (= (plist-get (emmet2-result-create "x" '((0 1 1 "x"))) :cursor) 0)))

(ert-deftest emmet2-result-rejects-invalid-fields ()
  (dolist (fields '(((0 2 1 "x")) ((0 1 0 "x")) ((0 1 1 "y"))
                    ((0 1 1 "x") (1 1 1 "")) ((0 1 1 "x") (0 1 2 "x"))
                    ((0 1 1 "x" extra)) ((0 . 1))))
    (should-error (emmet2-result-create "x" fields) :type 'emmet2-result-error)))

(ert-deftest emmet2-result-concat-isolates-groups-without-mutation ()
  (let* ((a (emmet2-result-create "x x" '((0 1 1 "x") (2 3 1 "x"))))
         (b (emmet2-result-create "😀" '((1 1 1 ""))))
         (original (copy-tree (list a b))))
    (should (equal (emmet2-result-concat a b)
                   '(:text "x x😀" :fields ((0 1 1 "x") (2 3 1 "x") (4 4 2 "")) :cursor 0)))
    (should (equal (list a b) original))
    (should (equal (emmet2-result-concat) '(:text "" :fields nil :cursor 0)))))

(ert-deftest emmet2-result-canonical-oracle-shapes ()
  (dolist (file '("markup.json"))
    (let ((checked 0)
          (cases (with-temp-buffer
                   (insert-file-contents (expand-file-name (concat "test/fixtures/oracle/" file)
                                                          emmet2-test-root))
                   (json-parse-buffer :object-type 'alist :array-type 'list))))
      (dolist (entry cases)
        (when-let* ((result (alist-get 'result entry)))
          (cl-incf checked)
          (ert-info ((alist-get 'id entry))
            (let ((canonical (emmet2-result-create (alist-get 'text result) (alist-get 'fields result))))
              (should (equal (plist-get canonical :fields) (alist-get 'fields result)))
              (should (equal (plist-get canonical :cursor) (alist-get 'cursor result)))))))
      (should (> checked 0)))))

(provide 'emmet2-engine-test)
;;; emmet2-engine-test.el ends here
