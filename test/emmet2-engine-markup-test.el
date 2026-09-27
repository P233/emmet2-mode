;;; emmet2-engine-markup-test.el --- Native markup spike contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-engine-markup)
(require 'emmet2-lorem-contract)

(ert-deftest emmet2-markup-lorem-structural-contract ()
  (dolist (seed '(0 1 -1 1073741824 4294967295))
    (ert-info ((format "seed %s" seed))
      (emmet2-lorem-test--run
       (lambda (&rest arguments) (apply #'emmet2-engine-markup-expand (append arguments (list :seed seed))))))))

(ert-deftest emmet2-markup-lorem-seed-is-local-and-repeatable ()
  (let* ((input "ul>lorem40*3") (before (copy-sequence input))
         (data (prin1-to-string emmet2-markup--vocabularies))
         (first (emmet2-engine-markup-expand input :seed 42)))
    (cl-letf (((symbol-function 'random) (lambda (&rest _) (error "Global random must not be used"))))
      (should-not (equal first (emmet2-engine-markup-expand input :seed 43)))
      (emmet2-engine-markup-expand "loremru100")
      (should (equal first (emmet2-engine-markup-expand input :seed 42)))
      (should (equal first (emmet2-engine-markup-expand input :seed (+ 42 (expt 2 32))))))
    (should (equal input before))
    (should (equal data (prin1-to-string emmet2-markup--vocabularies))))
  (dolist (seed '(nil t "1" 1.0))
    (should-error (emmet2-engine-markup-expand "lorem" :seed seed) :type 'emmet2-error))
  (let ((emmet2-engine--timeout 0.01))
    (should-error
     (emmet2-engine-with-expansion
       (emmet2-markup--lorem-paragraph (cdar emmet2-markup--vocabularies) 1000000 t (list 0)))
     :type 'emmet2-backend-error))
  (should (equal (emmet2-engine-markup-expand "lipsum4")
                 '(:text "<lipsum4></lipsum4>" :fields ((9 9 1 "")) :cursor 9))))

(defun emmet2-markup-test--json (path)
  "Read JSON PATH relative to the repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path emmet2-test-root))
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(defconst emmet2-markup-test--ids
  (append '("html-snippet:!")
          (mapcar (lambda (i) (format "html-contract-%02d" i)) (number-sequence 1 18))
          (mapcar (lambda (i) (format "jsx-contract-%02d" i)) (number-sequence 1 5))
          '("markup-indent")
          (mapcar (lambda (i) (format "markup-spike-%02d" i)) (number-sequence 1 15))))

(defun emmet2-markup-test--cases (&optional ids)
  "Return selected IDS, or spike inputs, and their frozen oracle results."
  (let ((inputs (emmet2-markup-test--json "test/fixtures/core-inputs.json"))
        (oracle (emmet2-markup-test--json "test/fixtures/oracle/markup.json")))
    (mapcar
     (lambda (id)
       (let* ((input (cl-find id inputs :key (lambda (x) (alist-get 'id x)) :test #'equal))
              (expected (cl-find id oracle :key (lambda (x) (alist-get 'id x)) :test #'equal))
              (result (alist-get 'result expected)) (failure (alist-get 'error expected)))
         (unless (and input (or result failure)) (error "Missing spike oracle: %s" id))
         (list id (list (alist-get 'abbreviation input)
                        :preset (intern (alist-get 'preset input))
                        :indent (or (alist-get 'indent input) "\t")
                        :base-indent (or (alist-get 'baseIndent input) "")
                        :jsx (when-let* ((jsx (alist-get 'jsx input)))
                               (list :classAttribute (alist-get 'classAttribute jsx)
                                     :cssModulesObject (alist-get 'cssModulesObject jsx)
                                     :classConstructor (alist-get 'classConstructor jsx))))
               (if failure (list 'emmet2-parse-error (alist-get 'message failure) (alist-get 'position failure))
                 (list :text (alist-get 'text result) :fields (alist-get 'fields result)
                       :cursor (alist-get 'cursor result)))))) (or ids emmet2-markup-test--ids))))

(ert-deftest emmet2-markup-current-core-oracle ()
  ;; This corpus covers all shipped aliases, but is not the full grammar suite.
  (let* ((oracle (emmet2-markup-test--json "test/fixtures/oracle/markup.json"))
         (cases (emmet2-markup-test--cases (mapcar (lambda (entry) (alist-get 'id entry)) oracle))))
    (should (= (length cases) 526))
    (dolist (case cases)
      (ert-info ((car case))
        (should (equal (condition-case err (apply #'emmet2-engine-markup-expand (nth 1 case))
                         (emmet2-parse-error err)) (nth 2 case)))))))

(ert-deftest emmet2-markup-spike-oracle ()
  (dolist (case (emmet2-markup-test--cases))
    (ert-info ((car case))
      (if (eq (car (nth 2 case)) 'emmet2-parse-error)
          (should (equal (should-error (apply #'emmet2-engine-markup-expand (nth 1 case)) :type 'emmet2-parse-error)
                         (nth 2 case)))
        (should (equal (apply #'emmet2-engine-markup-expand (nth 1 case)) (nth 2 case)))))))

(ert-deftest emmet2-markup-conversion-does-not-mutate-shared-syntax ()
  (dolist (input '("(ul>li.item$*2>a[title=${1:x}])*2"
                   "(p>{foo}>div)*2"
                   "div{<se\\ction>${1:text}</section>}"
                   "div>{${0} \\ suffix}>p*2"
                   "(ul>li.i$@^*2)*2"
                   "(div*>a)+p*"
                   "div[data-${1:name}=x]"
                   "div[class='${1:a\"b} ${1:😀}']>span.a.b"))
    (dolist (jsx '(nil (:classAttribute "className" :cssModulesObject "css" :classConstructor "clsx")))
      (let* ((syntax (emmet2-markup--parse input (not (null jsx))))
           (before (prin1-to-string syntax))
           (first (emmet2-markup--convert syntax))
           (converted (prin1-to-string first))
             (out (emmet2-markup--output "\t" "" (not (null jsx)))))
        (setq first (emmet2-markup--resolve first (make-hash-table :test #'equal) nil (not (null jsx))))
        (emmet2-markup--transform first nil (plist-get jsx :classAttribute) jsx)
        (emmet2-markup--emit out first)
        (should (equal (prin1-to-string syntax) before))
        (should (equal (prin1-to-string (emmet2-markup--convert syntax)) converted))))))

(ert-deftest emmet2-markup-jsx-options-and-character-offsets ()
  (let* ((jsx (list :classAttribute "className" :cssModulesObject "css" :classConstructor "clsx"))
         (before (prin1-to-string jsx))
         (input "[class=\"😀\"]") (source (copy-sequence input)))
    (should (equal (emmet2-engine-markup-expand input :preset 'jsx :jsx jsx)
                   '(:text "<div className={css[\"😀\"]}></div>" :fields ((26 26 1 "")) :cursor 26)))
    (with-temp-buffer
      (insert "source") (goto-char 3)
      (let ((tick (buffer-chars-modified-tick)))
        (emmet2-engine-markup-expand ".a.b>span{${1:😀}}" :preset 'jsx :jsx jsx :indent "  " :base-indent "    ")
        (should (equal (buffer-string) "source"))
        (should (= (point) 3))
        (should (= tick (buffer-chars-modified-tick)))))
    (should (equal (prin1-to-string jsx) before))
    (should (equal input source))
    (should-error (emmet2-engine-markup-expand ".a" :jsx jsx) :type 'emmet2-error))
  (dolist (jsx '(t "class" (:classAttribute . "class")
                  (:classAttribute "unknown" :cssModulesObject "css" :classConstructor "clsx")
                  (:classAttribute "className" :cssModulesObject nil :classConstructor "clsx")
                  (:classAttribute "className" :cssModulesObject "css" :classConstructor 1)))
    (should-error (emmet2-engine-markup-expand ".a" :preset 'jsx :jsx jsx) :type 'emmet2-error)))

(ert-deftest emmet2-markup-fields-have-token-scope-and-character-offsets ()
  (should (equal (emmet2-engine-markup-expand "div{${1:a\nb}}")
                 '(:text "<div>a\nb</div>" :fields ((5 8 1 "a\nb")) :cursor 5)))
  (should (equal (emmet2-engine-markup-expand "div{${}}")
                 '(:text "<div></div>" :fields nil :cursor 11)))
  (should (equal (emmet2-engine-markup-expand "div{${2}${1}}")
                 '(:text "<div></div>" :fields ((5 5 2 "") (5 5 1 "")) :cursor 5)))
  (should (equal (emmet2-engine-markup-expand "div{😀 ${2:b} ${1:😸} ${1:😸} ${1:x}}")
                 '(:text "<div>😀 b 😸 😸 x</div>"
                         :fields ((7 8 3 "b") (9 10 1 "😸") (11 12 1 "😸") (13 14 2 "x")) :cursor 9)))
  (should (equal (emmet2-engine-markup-expand "div{${1:x}}+span{${1:x}}")
                 '(:text "<div>x</div>\n<span>x</span>"
                         :fields ((5 6 1 "x") (19 20 2 "x")) :cursor 5))))

(ert-deftest emmet2-markup-formatter-is-independent-of-search-settings ()
  (dolist (case-fold-search '(nil t))
    (should (equal (emmet2-engine-markup-expand "div{<SECTION>raw</SECTION>}")
                   (emmet2-result-create "<div>\n\t<SECTION>raw</SECTION>\n</div>" nil)))
    ;; JavaScript's tag regexp is ASCII; Emacs case folding also matches K to K.
    (should (equal (emmet2-engine-markup-expand "div{<K>raw</K>}")
                   (emmet2-result-create "<div><K>raw</K></div>" nil)))))

(ert-deftest emmet2-markup-inputs-data-and-editor-state-are-unchanged ()
  (let* ((input "ul>li.item$*2>a{😀 ${1:x}}") (original (copy-sequence input))
         (data (json-serialize emmet2-markup--snippets))
         (first (emmet2-engine-markup-expand input)))
    (with-temp-buffer
      (insert "unchanged") (goto-char 3)
      (let ((tick (buffer-chars-modified-tick)))
        (emmet2-engine-markup-expand "!" :preset 'jsx :indent "  " :base-indent "    ")
        (should (equal (emmet2-engine-markup-expand input) first))
        (should (equal (buffer-string) "unchanged"))
        (should (= (point) 3))
        (should (= (buffer-chars-modified-tick) tick))))
    (should (equal input original))
    (should (equal (json-serialize emmet2-markup--snippets) data))))

(ert-deftest emmet2-markup-errors-and-shared-deadline ()
  (dolist (case '(("div{${1" "Expecting }" 7) ("div@" "Unexpected character" 3)
                  ("div{${1x}}" "Expecting }" 7) ("div{${#}}" "Expecting }" 6)
                  ("div{😀}+€" "Unexpected character" 7)))
    (should (equal (cdr (should-error (emmet2-engine-markup-expand (car case)) :type 'emmet2-parse-error))
                   (cdr case))))
  (let ((emmet2-engine--deadline 1))
    (should-error (emmet2-engine-markup-expand "li*100000") :type 'emmet2-backend-error)))

(ert-deftest emmet2-markup-pinned-conversion-error-does-not-leak-state ()
  ;; Upstream tokenizes a leading * inside text as a repeater, then fails in
  ;; stringify.  Preserve the backend-error distinction outside parse goldens.
  (let ((before (emmet2-engine-markup-expand "ul>li.i$*")))
    (should (equal (should-error (emmet2-engine-markup-expand "div{*2}") :type 'emmet2-backend-error)
                   '(emmet2-backend-error "Unknown token Repeater")))
    (should (equal (emmet2-engine-markup-expand "ul>li.i$*") before))))

;;; emmet2-engine-markup-test.el ends here
