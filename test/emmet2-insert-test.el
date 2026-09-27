;;; emmet2-insert-test.el --- Real editor insertion contracts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'emmet2-mode)
(require 'yasnippet)
(require 'web-mode)
(require 'typescript-ts-mode)

(defmacro emmet2-test-with-insertion (yas &rest body)
  "Run BODY with source abbreviation and optional YAS fields."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert "abbr")
     (when ,yas (yas-minor-mode 1))
     (let ((this-command 'emmet2-test-command) (last-command nil)
           (snapshot (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr"))))
       ,@body)))

(ert-deftest emmet2-insert-plain-and-yas-share-text-and-cursor ()
  (dolist (yas '(nil t))
    (emmet2-test-with-insertion yas
      (let ((result (emmet2-result-create "😀 x x" '((2 3 1 "x") (4 5 1 "x")))))
        (emmet2-insert snapshot result)
        (should (equal (buffer-string) (plist-get result :text)))
        (should (= (point) (+ 1 (plist-get result :cursor))))
        (when yas
          (insert "link")
          (yas-next-field)
          (should (equal (buffer-string) "😀 link link"))
          (should (= (point) (point-max)))
          (run-hooks 'post-command-hook)
          (should-not (yas-active-snippets)))))))

(ert-deftest emmet2-insert-css-fields-tab-and-final-exit ()
  (dolist (abbreviation '("c+bg" "m+p" "bd"))
    (emmet2-test-with-insertion t
      (let* ((result (emmet2-extensions-css abbreviation))
             (count (if (equal abbreviation "bd") 1 2)))
        (emmet2-insert snapshot result)
        (dotimes (i count)
          (insert (number-to-string (1+ i)))
          (yas-next-field))
        (should (equal (buffer-string)
                       (pcase abbreviation ("bd" "border: 1;")
                              ("c+bg" "color: 1;\nbackground: 2;")
                              (_ "margin: 1;\npadding: 2;"))))
        (should (= (point) (point-max)))))))

(defvar emmet2-test-evaluated nil)
(ert-deftest emmet2-insert-literals-never-evaluate ()
  (let ((literal "😀 \\ $ ${9:x} ` (setq emmet2-test-evaluated t) ` { } \\` \\\\}")
        (emmet2-test-evaluated nil))
    (emmet2-test-with-insertion t
      (emmet2-insert snapshot
                     (emmet2-result-create (concat literal "|" literal)
                                           (list (list (1+ (length literal))
                                                       (1+ (* 2 (length literal))) 1 literal))))
      (should-not emmet2-test-evaluated)
      (should (equal (buffer-string) (concat literal "|" literal)))
      (should (= (point) (+ 2 (length literal)))))))

(ert-deftest emmet2-insert-boundary-fields-preserve-text ()
  (dolist (fields '(((0 1 2 "x") (0 0 1 "")) ((0 0 1 "") (0 0 2 ""))
                    ((0 1 1 "x") (1 1 2 ""))))
    (emmet2-test-with-insertion t
      (let ((result (emmet2-result-create "x" fields)))
        (emmet2-insert snapshot result)
        (should (equal (buffer-string) "x"))
        (should (= (point) (1+ (plist-get result :cursor))))
        (insert "A") (yas-next-field) (insert "B") (yas-next-field)
        (should (equal (buffer-string) (if (equal fields '((0 0 1 "") (0 0 2 ""))) "ABx" "AB")))))))

(ert-deftest emmet2-insert-one-undo-restores-source ()
  (dolist (yas '(nil t))
    (emmet2-test-with-insertion yas
      (buffer-enable-undo)
      (emmet2-insert snapshot (emmet2-result-create "<p>x</p>" '((3 4 1 "x"))))
      (undo-only 1)
      (should (equal (buffer-string) "abbr"))
      (should-not (yas-active-snippets)))))

(ert-deftest emmet2-insert-failure-rolls-back-text-point-and-fields ()
  (dolist (yas '(nil t))
    (emmet2-test-with-insertion yas
      (let* ((original (symbol-function 'yas-expand-snippet)) failed
             (after-change-functions
              (if yas after-change-functions
                (cons (lambda (beg end _length)
                        (when (and (> end beg) (not failed))
                          (setq failed t) (error "insertion hook failed"))) after-change-functions))))
        (cl-letf (((symbol-function 'yas-expand-snippet)
                   (lambda (&rest args) (apply original args) (error "insertion failed"))))
          (should-error (emmet2-insert snapshot (emmet2-result-create "<p>x</p>" '((3 4 1 "x")))))))
      (should (equal (buffer-string) "abbr"))
      (should (= (point) 5))
      (should-not (yas-active-snippets)))))

(ert-deftest emmet2-insert-rejects-stale-snapshots ()
  (dolist (change '(source other-position point mode narrow))
    (emmet2-test-with-insertion nil
      (pcase change
        ('source (delete-char -1) (insert "x"))
        ('other-position (save-excursion (goto-char 1) (insert "other ")))
        ('point (goto-char 1))
        ('mode (text-mode))
        ('narrow (narrow-to-region 2 5)))
      (let ((before (buffer-string)) (position (point)))
        (should-error (emmet2-insert snapshot (emmet2-result-create "new")) :type 'emmet2-error)
        (should (equal before (buffer-string))) (should (= position (point))))))
  (emmet2-test-with-insertion nil
    (with-temp-buffer
      (insert "abbr")
      (should-error (emmet2-insert snapshot (emmet2-result-create "new")) :type 'emmet2-error)
      (should (equal (buffer-string) "abbr")))))

(ert-deftest emmet2-insert-respects-read-only-and-disabled-undo ()
  (emmet2-test-with-insertion nil
    (let ((buffer-read-only t))
      (should-error (emmet2-insert snapshot (emmet2-result-create "new")) :type 'buffer-read-only))
    (should (equal (buffer-string) "abbr"))
    (should (eq buffer-undo-list t))))

(ert-deftest emmet2-render-respects-mode-width-display-column-and-tabs ()
  (dolist (mode '(css-mode web-mode tsx-ts-mode))
    (with-temp-buffer
      (setq buffer-file-name (if (eq mode 'tsx-ts-mode) "/tmp/example.tsx" "/tmp/example.html"))
      (insert "\t界 m10") (funcall mode)
      (setq-local tab-width 8 indent-tabs-mode t)
      (set (make-local-variable (pcase mode ('css-mode 'css-indent-offset)
                                      ('web-mode 'web-mode-css-indent-offset)
                                      (_ (if (boundp 'typescript-ts-indent-offset)
                                             'typescript-ts-indent-offset 'typescript-ts-mode-indent-offset)))) 4)
      (goto-char (point-min)) (search-forward "m10")
      (let* ((beg (- (point) 3)) (before (buffer-string)) (position (point))
             (options (emmet2-insert-render-options (list :beg beg :lang 'css :syntax 'css))))
        (should (equal options '(:indent "    " :base-indent "\t   ")))
        (should (= position (point))) (should (equal before (buffer-string)))))))

(ert-deftest emmet2-expand-real-layout-and-no-second-indentation ()
  (dolist (mode '(web-mode tsx-ts-mode))
    (with-temp-buffer
      (setq buffer-file-name (if (eq mode 'tsx-ts-mode) "/tmp/example.tsx" "/tmp/example.html"))
      (insert (if (eq mode 'tsx-ts-mode) "const A = (<main>ul>li*2</main>);" "<main>ul>li*2</main>"))
      (funcall mode) (setq-local indent-tabs-mode nil)
      (goto-char (point-min)) (search-forward "li*")
      (let* ((analysis (emmet2-context-analyze)) (beg (plist-get analysis :beg))
             (end (plist-get analysis :end)) (original (buffer-string))
             (expected (emmet2--expand-analysis analysis)))
        (cl-letf (((symbol-function 'indent-region) (lambda (&rest _) (error "Second indentation"))))
          (emmet2-expand))
        (should (equal (buffer-string) (concat (substring original 0 (1- beg))
                                              (plist-get expected :text) (substring original (1- end)))))
        (should (= (point) (+ beg (plist-get expected :cursor))))))))

(ert-deftest emmet2-expand-options-and-nonfile-buffers ()
  (with-temp-buffer
    (let ((emmet2-markup-variant "solid") (emmet2-css-modules-object "style")
          (emmet2-class-names-constructor "classnames"))
      (insert "div.a.b") (emmet2-mode 1) (emmet2-expand)
      (should (equal (buffer-string) "<div class={classnames(style.a, style.b)}></div>"))
      (should (emmet2-context--owner)) (emmet2-mode -1) (should-not (emmet2-context--owner))))
  (dolist (option '(emmet2-css-modules-object emmet2-class-names-constructor))
    (should (funcall (get option 'safe-local-variable) "project.reference")))
  (should (funcall (get 'emmet2-markup-variant 'safe-local-variable) "solid"))
  (should-not (funcall (get 'emmet2-markup-variant 'safe-local-variable) "arbitrary")))

(ert-deftest emmet2-expand-errors-preserve-source-and-literal-percent ()
  (with-temp-buffer
    (insert "p")
    (cl-letf (((symbol-function 'emmet2--expand-analysis)
               (lambda (_) (signal 'emmet2-backend-error '("bad %s 100%")))))
      (let ((error-data (should-error (emmet2-expand) :type 'user-error)))
        (should (string-match-p "bad %s 100%" (cadr error-data)))))
    (should (equal (buffer-string) "p")))
  (with-temp-buffer
    (insert "const a = 'div';") (js-mode) (goto-char 13)
    (should-error (emmet2-expand) :type 'user-error)
    (should (equal (buffer-string) "const a = 'div';"))))

(ert-deftest emmet2-insert-yas-eof-navigation-and-advice-isolation ()
  (emmet2-test-with-insertion t
    (emmet2-insert snapshot (emmet2-result-create "x y" '((0 1 1 "x") (2 3 2 "y"))))
    (insert "one") (yas-next-field)
    (should (equal (buffer-string) "one y"))
    (insert "two") (yas-next-field) (run-hooks 'post-command-hook)
    (should (equal (buffer-string) "one two"))
    (should (= (point) (point-max)))
    (should-not (yas-active-snippets)))
  ;; Ordinary yas snippets retain their own newline policy.
  (with-temp-buffer
    (yas-minor-mode 1) (yas-expand-snippet "${1:x}$0")
    (should (equal (buffer-string) "x\n")))
  (emmet2-insert-unload-function)
  (should-not (advice-member-p #'emmet2-insert--yas-protect-text
                               'yas--make-move-field-protection-overlays)))

(ert-deftest emmet2-insert-yas-before-hook-cannot-change-the-source ()
  (emmet2-test-with-insertion t
    (let ((yas-before-expand-snippet-hook (list (lambda () (insert "changed")))))
      (should-error (emmet2-insert snapshot (emmet2-result-create "x" '((0 1 1 "x"))))
                    :type 'emmet2-error))
    (should (equal (buffer-string) "abbr"))
    (should-not (yas-active-snippets))))

(ert-deftest emmet2-insert-literal-yas-guard-is-preserved ()
  (emmet2-test-with-insertion t
    (let* ((text "YASESCAPE96PROTECTGUARD ${1:x}")
           (result (emmet2-result-create text (list (list 0 (length text) 1 text)))))
      (emmet2-insert snapshot result)
      (should (equal (buffer-string) text)))))

(ert-deftest emmet2-expand-preserves-literal-tabs-and-emoji ()
  (with-temp-buffer
    (insert "p{😀a\tb}") (setq-local indent-tabs-mode nil)
    (emmet2-expand)
    (should (equal (buffer-string) "<p>😀a\tb</p>"))))

(ert-deftest emmet2-mode-lifecycle-and-lazy-backend ()
  (with-temp-buffer
    (insert "const A=(<main>ul>li*2</main>);") (tsx-ts-mode)
    (emmet2-mode 1)
    (let* ((owner (emmet2-context--owner)) (timer (emmet2-context--state-timer owner)))
      (emmet2-mode 1)
      (should (eq owner (emmet2-context--owner)))
      (should (eq timer (emmet2-context--state-timer owner)))
      (goto-char (point-min)) (search-forward "li*") (emmet2-expand)
      (should (emmet2-context--parsers))
      (let ((host-parsers (treesit-parser-list)))
        (emmet2-mode -1)
        (should (equal host-parsers (treesit-parser-list)))
        (should-not (emmet2-context--owner))
        (should-not (memq timer timer-idle-list))))
    (emmet2-mode 1) (text-mode) (should-not (emmet2-context--owner)))
  (with-temp-buffer
    (emmet2-mode 1)
    (emmet2-mode-unload-function)
    (should-not emmet2-mode)
    (should-not (emmet2-context--owner)))
  (should-not (featurep 'deno-bridge))
  (should (eq (lookup-key emmet2-mode-map (kbd "C-j")) #'emmet2-expand)))

(ert-deftest emmet2-expand-yas-real-hosts-preserve-rendered-result ()
  (dolist (case '((css-mode ".a { m│+p }")
                  (scss-mode ".a { @me│dia }")
                  (web-mode "<style>.a { c│+bg }</style>")
                  (web-mode "<main>ul>li│*2</main>")
                  (tsx-ts-mode "const A=(<main>ul>li│*2</main>);")
                  (tsx-ts-mode "const A=(<main style={{m│+p}} />);")
                  (js-mode "const s=StyleSheet.create({m│+p});")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (cadr case)) (goto-char 1) (search-forward "│") (delete-char -1)
        (let ((position (point)))
          (setq buffer-file-name (if (eq (car case) 'tsx-ts-mode) "/tmp/example.tsx" "/tmp/example.html"))
          (funcall (car case)) (goto-char position))
        (setq-local indent-tabs-mode nil)
        (emmet2-mode 1) (yas-minor-mode 1)
        (let* ((this-command 'emmet2-expand)
               (analysis (emmet2-context-analyze)) (beg (plist-get analysis :beg))
               (end (plist-get analysis :end)) (before (buffer-string))
               (result (emmet2--expand-analysis analysis)))
          (should analysis)
          (emmet2-expand)
          (should (equal (buffer-string) (concat (substring before 0 (1- beg))
                                                (plist-get result :text) (substring before (1- end)))))
          (should (= (point) (+ beg (plist-get result :cursor))))
          (when (plist-get result :fields)
            (should (yas-active-snippets))
            (yas-exit-all-snippets)
            (should (= (point) (+ beg (length (plist-get result :text)))))))))))

(ert-deftest emmet2-insert-guard-escapes-roundtrip-case-and-mirrors ()
  (dolist (character '(92 96 34 39 36 125 123 40 41 89))
    (dolist (format '("YASESCAPE%dPROTECTGUARD" "yasescape%dprotectguard" "\\YASESCAPE%dPROTECTGUARD"))
      (emmet2-test-with-insertion t
        (let* ((literal (format format character)) (length (length literal))
               (text (concat literal " " literal "!")))
          (emmet2-insert snapshot (emmet2-result-create text (list (list 0 length 1 literal)
                                                                  (list (1+ length) (1+ (* 2 length)) 1 literal))))
          (should (equal (buffer-string) text))
          (insert "changed")
          (should (equal (buffer-string) "changed changed!")))))))

(ert-deftest emmet2-mode-unload-cleans-command-created-context ()
  (with-temp-buffer
    (insert "p") (emmet2-expand)
    ;; Explicit JS analysis may allocate resources without minor mode enabled.
    (erase-buffer) (insert "const A=(<main>p</main>);") (tsx-ts-mode)
    (goto-char 20) (emmet2-context-analyze)
    (should (emmet2-context--owner))
    (emmet2-mode-unload-function)
    (should-not (emmet2-context--owner))))

(ert-deftest emmet2-insert-keeps-user-hooks-and-settings ()
  (with-temp-buffer
    (insert "<style>.a { m+p }</style>") (web-mode) (yas-minor-mode 1)
    (goto-char 1) (search-forward "m+p")
    (let ((called 0) (yas-indent-line 'auto) (yas-wrap-around-region t)
          (this-command 'emmet2-expand))
      (add-hook 'yas-after-exit-snippet-hook (lambda () (cl-incf called)) nil t)
      (let ((hooks (copy-sequence yas-after-exit-snippet-hook)) (fold case-fold-search))
        (emmet2-expand)
        (let ((rendered (buffer-string)))
          (yas-exit-all-snippets)
          (should (equal (buffer-string) rendered)))
        (should (= called 1))
        (should (equal hooks yas-after-exit-snippet-hook))
        (should (eq yas-indent-line 'auto))
        (should yas-wrap-around-region)
        (should (eq fold case-fold-search))))))

(ert-deftest emmet2-expand-missing-grammar-and-cancellation-leave-source ()
  (with-temp-buffer
    (insert "const A=(<main>ul>li*2</main>);") (js-mode)
    (goto-char 1) (search-forward "li*")
    (let ((before (buffer-string)) (position (point)))
      (cl-letf (((symbol-function 'treesit-language-available-p) (lambda (_) nil)))
        (should-error (emmet2-expand) :type 'user-error))
      (should (equal before (buffer-string))) (should (= position (point)))))
  (with-temp-buffer
    (insert "p")
    (cl-letf (((symbol-function 'emmet2--expand-analysis) (lambda (_) (signal 'quit nil))))
      (should (eq (condition-case nil (progn (emmet2-expand) nil) (quit 'quit)) 'quit)))
    (should (equal (buffer-string) "p"))))

(ert-deftest emmet2-insert-stacked-yas-undo-preserves-parent ()
  (with-temp-buffer
    (yas-minor-mode 1) (buffer-enable-undo)
    (let ((this-command 'emmet2-expand))
      (yas-expand-snippet "${1:abbr} ($1)$0" nil nil '((yas-indent-line nil)))
      (undo-boundary)
      (let ((before (buffer-string)) (parent (car (yas-active-snippets)))
            (snapshot (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr"))))
        (emmet2-insert snapshot (emmet2-result-create "<p>x</p>" '((3 4 1 "x"))))
        (should (= (length (yas-active-snippets)) 2))
        (undo-only 1)
        (should (equal (buffer-string) before))
        (should (equal (yas-active-snippets) (list parent)))))))

(ert-deftest emmet2-render-js-object-and-jsx-use-their-own-width ()
  (with-temp-buffer
    (js-mode)
    (let ((js-indent-level 4) (js-jsx-indent-level 2) (indent-tabs-mode nil))
      (should (equal (plist-get (emmet2-insert-render-options '(:beg 1 :lang css-in-js)) :indent) "    "))
      (should (equal (plist-get (emmet2-insert-render-options '(:beg 1 :lang markup :syntax jsx)) :indent) "  ")))))

(provide 'emmet2-insert-test)
;;; emmet2-insert-test.el ends here
