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

(ert-deftest emmet2-extract-authored-tags-are-boundaries ()
  (dolist (case '(("<p>ul>li│</p>" "ul>li") ("<div><b>x</b>ul>li│</div>" "ul>li")
                  ("<br/>ul>li│" "ul>li") ("<Icon onClick={() => go()} />ul>li│" "ul>li")
                  ("<a title=\"x>y\">ul>li│</a>" "ul>li") ("</>ul>li│" "ul>li")
                  ("div{<b>x</b>}│" "div{<b>x</b>}") ("<di│v>" nil)))
    (ert-info ((car case))
      (with-temp-buffer
        (insert (car case)) (goto-char (point-min)) (search-forward "│") (delete-char -1)
        (should (equal (plist-get (emmet2-extract (point-min) (point-max)) :abbr) (cadr case)))))))

(ert-deftest emmet2-extract-incomplete-groups-use-region-limit ()
  (with-temp-buffer
    (insert "a{unfinished")
    (should (equal (plist-get (emmet2-extract 1 (point-max)) :abbr)
                   "a{unfinished"))))

(ert-deftest emmet2-extract-css-comments-bound-abbreviations ()
  (dolist (case '((".a{/* c */m10│}" "m10")
                  (".a{/* c\n c */m10│}" "m10")
                  (".a{m10│/* c */}" "m10")
                  (".a{/*m10│*/}" nil)
                  (".a{ct['/* literal */']│}" "ct['/* literal */']")
                  (".a{p[calc(1px /* c */ + 2px)]│}" "p[calc(1px /* c */ + 2px)]")))
    (ert-info ((car case))
      (with-temp-buffer
        (insert (car case)) (search-backward "│") (delete-char 1)
        (should (equal (plist-get (emmet2-extract (point-min) (point-max) 'css) :abbr)
                       (cadr case)))))))

(ert-deftest emmet2-extract-css-comment-delimiters-respect-region-end ()
  (dolist (input '("/* comment */m10" "*/m10"))
    (with-temp-buffer
      (insert input) (goto-char 2)
      (let ((result (emmet2-extract 1 2 'css)))
        (should (equal (plist-get result :abbr) (substring input 0 1)))
        (should (= (plist-get result :end) 2))
        (should (= (point) 2))))))

(ert-deftest emmet2-extract-css-trailing-comma-is-part-of-the-abbreviation ()
  (dolist (source '(".a{m10,│}" ".a{ta,│ }" ".a{m10,p20,│"
                    ".a{p[calc(1px,2px)],│}"))
    (with-temp-buffer
      (insert source) (search-backward "│") (delete-char 1)
      (let ((result (emmet2-extract (point-min) (point-max) 'css)))
        (should (string-suffix-p "," (plist-get result :abbr)))
        (should (= (plist-get result :end) (point))))))
  ;; In JavaScript a trailing comma belongs to the enclosing object or call.
  (with-temp-buffer
    (insert "m10,")
    (should-not (emmet2-extract (point-min) (point-max)))
    (backward-char)
    (should (equal (plist-get (emmet2-extract (point-min) (point-max)) :abbr) "m10"))))

(ert-deftest emmet2-extract-css-selector-boundaries-are-structural ()
  (dolist (case '((".a,:hv" ":hv") (".a, :hv" ":hv")
                  ("button[data-label='a:b']:hv" ":hv")
                  (".a:hover[data-label='a:b']:hv" ":hv")
                  (".a:hover.active:fo" ":fo")
                  (".a\\:active:hv" ":hv")
                  ("&:not(.a,:focus) > .b:hv:be" ":hv:be")
                  (".a[data-label='a:b']" nil) ("p[https://example.org]" nil)
                  (".a[data-label='unfinished]:hv" nil) (".a:has(.b" nil)
                  (".a:has(.b]:hv" nil) (".a:hover .b" nil)))
    (let ((colon (emmet2-extract-css-pseudo (car case))))
      (should (equal (and colon (substring (car case) colon)) (cadr case)))))
  (with-temp-buffer
    (insert ".outer {\n  .a, .b[data-x='a:b'] > .c:hv   { color: red; }\n}")
    (search-backward ":hv") (forward-char 3)
    (let ((position (point)) (source (buffer-string))
          (result (emmet2-extract (point-min) (point-max) 'css-selector)))
      (should (equal (plist-get result :abbr) ".a, .b[data-x='a:b'] > .c:hv"))
      (should (= (plist-get result :end) position))
      (should (= (point) position))
      (should (equal (buffer-string) source)))))

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
