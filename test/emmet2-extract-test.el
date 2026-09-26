;;; emmet2-extract-test.el --- Bounded extraction tests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-extract)
(require 'emmet2-context)

(dolist (entry (with-temp-buffer
                 (insert-file-contents (expand-file-name "test/fixtures/extract-legacy.json" emmet2-test-root))
                 (json-parse-buffer :object-type 'alist :array-type 'list :false-object nil)))
  (let ((abbreviation (alist-get 'abbreviation entry)) (accepted (alist-get 'accepted entry)))
    (eval `(ert-deftest ,(intern (concat "emmet2-extract-legacy-" (alist-get 'id entry))) ()
             (with-temp-buffer
               (insert "  " ,abbreviation ";")
               (cl-loop for position from 3 to ,(+ 3 (length abbreviation)) do
                        (goto-char position)
                        (let ((result (emmet2-context-analyze)))
                          (if ,accepted
                              (should (equal (cl-subseq result 0 6)
                                             '(:beg 3 :end ,(+ 3 (length abbreviation)) :abbr ,abbreviation)))
                            (should-not result)))))) t)))

(ert-deftest emmet2-extract-legacy-markup-001-to-003 ()
  (dolist (fixture '(("lorem span" 6 6)
                     ("atnoeuh otnoeuh span utnehu" 20 16)
                     ("atnoeuh otnoeuh span utnehu span" 31 28)))
    (with-temp-buffer
      (insert (nth 0 fixture))
      ;; Legacy fixtures use zero-based JavaScript character offsets.
      (goto-char (1+ (nth 1 fixture)))
      (let ((result (emmet2-context-analyze)))
        (should (equal (plist-get result :abbr) "span"))
        (should (= (plist-get result :beg) (1+ (nth 2 fixture))))))))

(ert-deftest emmet2-extract-legacy-markup-019-map-host ()
  (with-temp-buffer
    (insert "const A = () => (<main>{team.map(i => div)}</main>);")
    (tsx-ts-mode)
    (goto-char (point-min)) (search-forward "=> div") (backward-char 2)
    (should (equal (plist-get (emmet2-context-analyze) :abbr) "div"))
    (should-not (emmet2-context-analyze t))))

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
