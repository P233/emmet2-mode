;;; emmet2-engine-stylesheet-test.el --- Native CSS contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-engine-stylesheet)

(ert-deftest emmet2-stylesheet-completion-prefixes-and-keywords ()
  (dolist (name '("m" "mt" "mr" "mb" "ml" "maw"))
    (should (member name (emmet2-engine-stylesheet-completions "m"))))
  (dolist (prefix '("ta" "tac" "ta[c"))
    (should (member "ta[center]" (emmet2-engine-stylesheet-completions prefix))))
  (dolist (name '("d[inline]" "d[inline-block]" "d[inline-flex]"))
    (should (member name (emmet2-engine-stylesheet-completions "di"))))
  (should (member "bg[none]" (emmet2-engine-stylesheet-completions "bg")))
  (should-not (cl-some (lambda (name) (string-match-p ":" name))
                       (emmet2-engine-stylesheet-completions "bg")))
  (dolist (prefix '("" "unknownword" "m10" "margin" "color:re"))
    (should-not (emmet2-engine-stylesheet-completions prefix))))

(defun emmet2-stylesheet-test--json (path)
  "Read JSON PATH relative to the repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path emmet2-test-root))
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(defun emmet2-stylesheet-test--cases ()
  "Return all frozen stylesheet input and result contracts."
  (let ((inputs (emmet2-stylesheet-test--json "test/fixtures/core-inputs.json")))
    (mapcar
     (lambda (entry)
       (let* ((id (alist-get 'id entry))
              (input (cl-find id inputs :key (lambda (x) (alist-get 'id x)) :test #'equal))
              (result (alist-get 'result entry)) (failure (alist-get 'error entry)))
         (unless (and input (equal (alist-get 'preset input) "stylesheet") (or result failure))
           (error "Missing stylesheet oracle: %s" id))
         (list id (list (alist-get 'abbreviation input) :preset 'stylesheet
                        :indent (or (alist-get 'indent input) "\t")
                        :base-indent (or (alist-get 'baseIndent input) ""))
               (if failure (list 'emmet2-parse-error (alist-get 'message failure) (alist-get 'position failure))
                 (list :text (alist-get 'text result) :fields (alist-get 'fields result)
                       :cursor (alist-get 'cursor result))))))
     (emmet2-stylesheet-test--json "test/fixtures/oracle/stylesheet.json"))))

(ert-deftest emmet2-stylesheet-current-core-oracle ()
  (let ((cases (emmet2-stylesheet-test--cases)))
    (should (= (length cases) 447))
    (dolist (case cases)
      (ert-info ((car case))
        (should (equal (condition-case err (apply #'emmet2-engine-stylesheet-expand (nth 1 case))
                         (emmet2-parse-error err)) (nth 2 case)))))))

(ert-deftest emmet2-stylesheet-independent-fields-and-unicode ()
  (dolist (case '(("c+bg" (:text "color: #000;\nbackground: #000;"
                               :fields ((7 11 1 "#000") (25 29 2 "#000")) :cursor 7))
                  ("p${2:😀}-${1:x}-${2:😀}-${1:y}+m${1:z}"
                   (:text "padding: 😀 x 😀 y;\nmargin: z;"
                          :fields ((9 10 3 "😀") (11 12 1 "x") (13 14 3 "😀") (15 16 2 "y") (26 27 4 "z")) :cursor 11))
                  ("m${0}${0}" (:text "margin: ;" :fields ((8 8 1 "") (8 8 2 "")) :cursor 8))
                  ("p${9007199254740992:x}-${9007199254740993:x}"
                   (:text "padding: x x;" :fields ((9 10 1 "x") (11 12 1 "x")) :cursor 9))))
    (ert-info ((car case))
      (should (equal (emmet2-engine-stylesheet-expand (car case)) (cadr case))))))

(ert-deftest emmet2-stylesheet-six-property-contract ()
  (should (equal (emmet2-engine-stylesheet-expand "m10+p5+bd1#2s+posa+dib+fz16")
                 '(:text "margin: 10px;\npadding: 5px;\nborder: 1px #222 solid;\nposition: absolute;\ndisplay: inline-block;\nfont-size: 16px;"
                         :fields nil :cursor 111))))

(ert-deftest emmet2-stylesheet-js-numeric-rounding ()
  (dolist (case '(("m-0.0" . "margin: 0;")
                  ("m.03125" . "margin: 0.0313rem;")
                  ("m-.03125" . "margin: -0.0313rem;")
                  ("m-.00001" . "margin: -0rem;")
                  ("m1000000000000000000000" . "margin: 1e+21px;")
                  ;; The pinned formatter trims trailing exponent zeroes too.
                  ("m1000000000000000000000000000000" . "margin: 1e+3px;")))
    (should (equal (plist-get (emmet2-engine-stylesheet-expand (car case)) :text) (cdr case)))))

(ert-deftest emmet2-stylesheet-errors-retain-reference-boundary ()
  ;; These upstream failures lack a position and are not parse-error goldens.
  (dolist (input '(":" "-" "," ":-" "+:"))
    (should (equal (should-error (emmet2-engine-stylesheet-expand input) :type 'emmet2-backend-error)
                   '(emmet2-backend-error "Unexpected token"))))
  (should (equal (emmet2-engine-stylesheet-expand ":+") '(:text "" :fields nil :cursor 0)))
  (dolist (case '(("ct\"😀\"+m)" "Unexpected bracket" 7)
                  ("ct\"😀\"+m[" "Unexpected character" 7)
                  ("ct\"😀\"+m10 " "Unexpected token" 9)))
    (should (equal (cdr (should-error (emmet2-engine-stylesheet-expand (car case)) :type 'emmet2-parse-error))
                   (cdr case)))))

(ert-deftest emmet2-stylesheet-index-preserves-fuzzy-order ()
  (let (all)
    (maphash (lambda (_ bucket) (setq all (append bucket all))) emmet2-stylesheet--snippets)
    (setq all (sort all (lambda (a b) (string< (emmet2-stylesheet--snippet-key a)
                                              (emmet2-stylesheet--snippet-key b)))))
    (dolist (name '("@" "m" "p" "c" "b" "t" "f" "a" "poa" "bxz" "zzz" "M" "DIB" "trf" "margin" "auto"))
      (should (eq (emmet2-fuzzy-find name all nil t #'emmet2-stylesheet--snippet-key)
                  (emmet2-fuzzy-find name (gethash (aref (downcase name) 0) emmet2-stylesheet--snippets)
                                     nil t #'emmet2-stylesheet--snippet-key))))))

(ert-deftest emmet2-stylesheet-snippets-remain-immutable ()
  (let ((before (prin1-to-string emmet2-stylesheet--snippets))
        (input "animtf:cubic-bezier(1,2)+m.5+lg(#f,#0)") first)
    (setq first (emmet2-engine-stylesheet-expand input))
    (dolist (abbreviation '("bd" "animtf" "@ff" "c+bg" "p$a$b$c" "tf:scale3d(1,2,3)"))
      (emmet2-engine-stylesheet-expand abbreviation))
    (let* ((result (emmet2-engine-stylesheet-expand "bd"))
           (default (nth 3 (car (plist-get result :fields)))))
      (aset default 0 ?X)
      (should (equal (plist-get (emmet2-engine-stylesheet-expand "bd") :text) "border: 1px solid #000;")))
    (should (equal first (emmet2-engine-stylesheet-expand input)))
    (should (equal before (prin1-to-string emmet2-stylesheet--snippets)))))

(ert-deftest emmet2-stylesheet-pure-and-deadline-bound ()
  (let ((exec-path nil))
    (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "Unexpected process")))
              ((symbol-function 'insert-file-contents) (lambda (&rest _) (error "Unexpected file read"))))
      (with-temp-buffer
        (insert "unchanged") (goto-char 3)
        (let ((tick (buffer-chars-modified-tick)))
          (emmet2-engine-stylesheet-expand "m10+p.5+bd1#2s+posa+dib+fz16")
          (should (equal (buffer-string) "unchanged"))
          (should (= (point) 3))
          (should (= tick (buffer-chars-modified-tick)))))))
  (let ((emmet2-engine--deadline 0))
    (should-error (emmet2-engine-stylesheet-expand "m") :type 'emmet2-backend-error))
  (let ((emmet2-engine--timeout 0.001))
    (should-error (emmet2-engine-stylesheet-expand (apply #'concat (make-list 20000 "m+")))
                  :type 'emmet2-backend-error))
  (dolist (arguments '((nil) ("m" :preset html) ("m" :indent nil) ("m" :base-indent 2)))
    (should-error (apply #'emmet2-engine-stylesheet-expand arguments) :type 'emmet2-error)))

(provide 'emmet2-engine-stylesheet-test)
;;; emmet2-engine-stylesheet-test.el ends here
