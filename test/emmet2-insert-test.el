;;; emmet2-insert-test.el --- Real editor insertion contracts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
(require 'ert)
(require 'emmet2-mode)
(require 'emmet2-capf-contract-test)
(require 'yasnippet)
(require 'web-mode)
(require 'typescript-ts-mode)

(defmacro emmet2-test-with-insertion (yas &rest body)
  "Run BODY with a markup source abbreviation and optional YAS fields."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert "abbr")
     (emmet2-test--with-yasnippet ,yas
       (let ((this-command 'emmet2-test-command) (last-command nil)
             (snapshot (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang markup))))
         ,@body))))

(ert-deftest emmet2-insert-plain-and-yas-share-text-and-cursor ()
  (dolist (yas '(nil t))
    (emmet2-test-with-insertion yas
      (let ((result (emmet2-result-create "😀 x x!" '((2 3 1 "x") (4 5 1 "x")))))
        (emmet2-insert snapshot result)
        (should (equal (buffer-string) (plist-get result :text)))
        (should (= (point) (+ 1 (plist-get result :cursor))))
        (when yas
          (insert "link")
          (yas-next-field)
          (should (equal (buffer-string) "😀 link link!"))
          (should (= (point) (point-max)))
          (run-hooks 'post-command-hook)
          (should-not (yas-active-snippets)))))))

(ert-deftest emmet2-insert-installed-yasnippet-is-enabled-for-markup-fields ()
  (emmet2-test-with-insertion nil
    (emmet2-insert snapshot (emmet2-extensions-markup "a"))
    (should (looking-at "\"></a>\\'"))
    (should-not yas-minor-mode))
  (with-temp-buffer
    (insert "abbr")
    (emmet2-insert (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang markup)) (emmet2-result-create "x"))
    (should-not yas-minor-mode)
    (erase-buffer) (insert "abbr")
    (emmet2-insert (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang markup))
                   (emmet2-extensions-markup "a"))
    (should yas-minor-mode)
    (insert "u") (yas-next-field) (insert "t") (yas-next-field)
    (should (equal (buffer-string) "<a href=\"u\">t</a>"))
    (should (= (point) (point-max)))))

(ert-deftest emmet2-insert-yas-activation-failure-rolls-back-source ()
  (dolist (undo '(nil t))
    (dolist (action '(text point error))
      (with-temp-buffer
        (insert "abbr")
        (when undo (buffer-enable-undo))
        (let ((snapshot (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang markup)))
              (yas-minor-mode-hook
               (list (lambda ()
                       (if (eq action 'point) (goto-char 1) (insert "changed"))
                       (when (eq action 'error) (error "Yas activation failed"))))))
          (should-error (emmet2-insert snapshot (emmet2-result-create "x" '((0 1 1 "x")))))
          (should (equal (buffer-string) "abbr"))
          (should (= (point) 5))
          (should-not (yas-active-snippets))
          (unless undo (should (eq buffer-undo-list t))))))))

(ert-deftest emmet2-insert-yas-failure-restores-the-source-buffer ()
  (dolist (undo '(nil t))
    (dolist (hook '(yas-minor-mode-hook yas-before-expand-snippet-hook))
      (with-temp-buffer
        (insert "unrelated") (goto-char 2)
        (let ((other (current-buffer)))
          (with-temp-buffer
            (insert "abbr")
            (when undo (buffer-enable-undo))
            (let ((origin (current-buffer))
                  (snapshot (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang markup))))
              (cl-progv (list hook)
                  (list (list (lambda ()
                                (insert "changed") (goto-char 1)
                                (set-buffer other)
                                (error "Yas hook changed buffer"))))
                (should-error
                 (emmet2-insert snapshot (emmet2-result-create "x" '((0 1 1 "x"))))))
              (should (eq (current-buffer) origin))
              (should (equal (buffer-string) "abbr"))
              (should (= (point) 5))
              (unless undo (should (eq buffer-undo-list t)))
              (with-current-buffer other
                (should (equal (buffer-string) "unrelated"))
                (should (= (point) 2))))))))))

(ert-deftest emmet2-insert-css-starts-no-snippet-with-yasnippet ()
  ;; An active field would highlight typed values and send TAB past the semicolon.
  (dolist (abbreviation '("d" "c+bg" "bgilg" "posa"))
    (ert-info (abbreviation)
      (with-temp-buffer
        (insert "abbr") (yas-minor-mode 1)
        (let ((result (emmet2-extensions-css abbreviation)))
          (emmet2-insert (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang css)) result)
          (should (equal (buffer-string) (plist-get result :text)))
          (should (= (point) (1+ (plist-get result :cursor))))
          (should-not (yas-active-snippets))
          (should-not mark-active))))))

(ert-deftest emmet2-insert-css-newline-acceptance-and-undo ()
  (dolist (mode '(css-mode scss-mode))
    (dolist (accept '(emmet2-test--complete-first emmet2-expand-at-point))
      (with-temp-buffer
        (funcall mode) (insert ".a {\n  m10\n}")
        (goto-char 1) (search-forward "m10")
        (buffer-enable-undo)
        (funcall accept)
        (should (equal (buffer-string) ".a {\n  margin: 10px;\n  \n}"))
        (should (looking-at "\n}"))
        (should (= (current-column) 2))
        (undo-only 1)
        (should (equal (buffer-string) ".a {\n  m10\n}"))))))

(ert-deftest emmet2-insert-css-newline-reuses-only-the-next-blank-line ()
  (dolist (case '((".a {\n  m10│" ".a {\n  margin: 10px;\n  │")
                  (".a {\n  m10│\n" ".a {\n  margin: 10px;\n  │")
                  (".a {\n  m10│\n\n}" ".a {\n  margin: 10px;\n  │\n}")
                  (".a {\n  m10│\n \t \n}" ".a {\n  margin: 10px;\n  │\n}")
                  (".a {\n  m10│\n\n\n}" ".a {\n  margin: 10px;\n  │\n\n}")
                  (".a {\n  m10│\n  color: red;\n\n}"
                   ".a {\n  margin: 10px;\n  │\n  color: red;\n\n}")
                  (".a {\n  m10│\n  /* next */\n}"
                   ".a {\n  margin: 10px;\n  │\n  /* next */\n}")
                  (".a {\n  m10│ \t\n}" ".a {\n  margin: 10px;\n  │\n}")
                  (".a {\n\tm10│\n}" ".a {\n\tmargin: 10px;\n\t│\n}")
                  (".a {\nm10│\n}" ".a {\nmargin: 10px;\n│\n}")
                  (".a {\n  m10+p20│\n}"
                   ".a {\n  margin: 10px;\n  padding: 20px;\n  │\n}")))
    (ert-info ((car case))
      (with-temp-buffer
        (css-mode) (setq-local indent-tabs-mode nil)
        (insert (car case)) (goto-char 1) (search-forward "│") (delete-char -1)
        (emmet2-test--complete-first)
        (insert "│")
        (should (equal (buffer-string) (cadr case)))))))

(ert-deftest emmet2-insert-css-newline-preserves-fields-and-shared-lines ()
  (dolist (case '((".a {\n  m│\n}" ".a {\n  margin: │;\n}")
                  (".a {\n  w[calc()]│\n}" ".a {\n  width: calc(│);\n}")
                  (".a {\n  m10+p│\n}" ".a {\n  margin: 10px;\n  padding: │;\n}")
                  (".a { m10│\n}" ".a { margin: 10px;│\n}")
                  (".a {\n  m10│ }" ".a {\n  margin: 10px;│ }")
                  (".a {\n  m10│ /* note */\n}" ".a {\n  margin: 10px;│ /* note */\n}")
                  (".a {\n  m10│ // note\n}" ".a {\n  margin: 10px;│ // note\n}")
                  (".a {\n  m10│// note\n}" ".a {\n  margin: 10px;│// note\n}")))
    (ert-info ((car case))
      (with-temp-buffer
        (scss-mode) (setq-local indent-tabs-mode nil)
        (insert (car case)) (goto-char 1) (search-forward "│") (delete-char -1)
        (emmet2-test--complete-first)
        (insert "│")
        (should (equal (buffer-string) (cadr case)))))))

(ert-deftest emmet2-insert-css-replaces-a-following-semicolon ()
  (dolist (case '((".a { m10│; }" ".a { margin: 10px;│ }")
                  (".a {\n  m10│;\n}" ".a {\n  margin: 10px;│\n}")
                  (".a {\n  m10+p20│;\n}" ".a {\n  margin: 10px;\n  padding: 20px;│\n}")
                  (".a { m│; }" ".a { margin: │; }")
                  (".a { m10│ ; }" ".a { margin: 10px;│ ; }")))
    (dolist (mode '(css-mode scss-mode))
      (dolist (accept '(emmet2-test--complete-first emmet2-expand-at-point))
        (ert-info ((format "%s %s %S" mode accept (car case)))
          (with-temp-buffer
            (funcall mode) (setq-local indent-tabs-mode nil)
            (insert (car case)) (goto-char 1) (search-forward "│") (delete-char -1)
            (let ((source (buffer-string)))
              (buffer-enable-undo)
              (funcall accept)
              (should (equal (concat (buffer-substring-no-properties (point-min) (point)) "│"
                                     (buffer-substring-no-properties (point) (point-max)))
                             (cadr case)))
              (undo-only 1)
              (should (equal (buffer-string) source)))))))))

(ert-deftest emmet2-insert-css-newline-excludes-embedded-styles ()
  (dolist (source '("<div style=\"\n  m10│\n\"></div>"
                    "<style>\n.a {\n  m10│\n}\n</style>"
                    "const A = <div style={{\n  m10│\n}} />;"))
    (with-temp-buffer
      (insert source) (goto-char 1) (search-forward "│") (delete-char -1)
      (let ((position (point)))
        (if (string-prefix-p "const" source) (tsx-ts-mode) (web-mode))
        (goto-char position))
      (let* ((analysis (emmet2-context-analyze))
             (snapshot (emmet2-insert-snapshot analysis))
             (result (emmet2-expand-analysis analysis))
             (before (buffer-string)) (beg (plist-get analysis :beg))
             (end (plist-get analysis :end)))
        (emmet2-insert snapshot result)
        (should (equal (buffer-string) (concat (substring before 0 (1- beg))
                                              (plist-get result :text) (substring before (1- end)))))
        (should (= (point) (+ beg (plist-get result :cursor))))))))

(ert-deftest emmet2-insert-css-newline-can-be-disabled-at-acceptance ()
  (with-temp-buffer
    (css-mode) (insert ".a {\n  m10\n}") (goto-char 1) (search-forward "m10")
    (pcase-let* ((`(,_beg ,_end ,table . ,props) (emmet2-capf))
                (candidate (car (all-completions "m10" table))))
      (setq-local emmet2-css-auto-newline nil)
      (funcall (plist-get props :exit-function) candidate 'finished)
      (should (equal (buffer-string) ".a {\n  margin: 10px;\n}"))
      (should (looking-at "\n}"))
      (should (= (current-column) 15)))))

(ert-deftest emmet2-insert-css-newline-does-not-split-hidden-text ()
  (dolist (source '(".a { m10\n}" ".a {\n  m10 }" ".a {\n  m10\n \n}"))
    (with-temp-buffer
      (css-mode) (insert source) (goto-char 1) (search-forward "m10")
      (let* ((end (point)) (beg (- end 3))
             (analysis (list :beg beg :end end :abbr "m10" :lang 'css :position 'declaration-start))
             (snapshot (emmet2-insert-snapshot analysis)))
        (narrow-to-region beg end)
        (emmet2-insert snapshot (emmet2-extensions-css "m10"))
        (should (equal (buffer-string) "margin: 10px;"))
        (widen)
        (should (equal (buffer-string) (replace-regexp-in-string "m10" "margin: 10px;" source)))))))

(ert-deftest emmet2-insert-css-newline-failure-restores-source-and-point ()
  (dolist (undo '(nil t))
    (with-temp-buffer
      (css-mode) (insert ".a {\n  m10\n}") (goto-char 1) (search-forward "m10")
      (when undo (buffer-enable-undo))
      (let* ((before (buffer-string)) (position (point)) failed
             (after-change-functions
              (list (lambda (&rest _)
                      (when (and (not failed) (> (count-lines (point-min) (point-max)) 3))
                        (setq failed t) (error "Continuation hook failed"))))))
        (should-error (emmet2-test--complete-first))
        (should failed)
        (should (equal (buffer-string) before))
        (should (= (point) position))
        (unless undo (should (eq buffer-undo-list t)))))))

(defvar emmet2-test-evaluated nil)
(ert-deftest emmet2-insert-literals-never-evaluate ()
  (let ((literal "😀 \\ $ ${9:x} ` (setq emmet2-test-evaluated t) ` { } \\` \\\\}")
        (emmet2-test-evaluated nil))
    (emmet2-test-with-insertion t
      (emmet2-insert snapshot
                     (emmet2-result-create (concat literal "|" literal "|")
                                           (list (list (1+ (length literal))
                                                       (1+ (* 2 (length literal))) 1 literal))))
      (should-not emmet2-test-evaluated)
      (should (equal (buffer-string) (concat literal "|" literal "|")))
      (should (= (point) (+ 2 (length literal)))))))

(ert-deftest emmet2-insert-boundary-fields-preserve-text ()
  (dolist (fields '(((0 1 2 "x") (0 0 1 "")) ((0 0 1 "") (0 0 2 ""))
                    ((0 1 1 "x") (1 1 2 ""))))
    (emmet2-test-with-insertion t
      (let ((result (emmet2-result-create "x;" fields)))
        (emmet2-insert snapshot result)
        (should (equal (buffer-string) "x;"))
        (should (= (point) (1+ (plist-get result :cursor))))
        (insert "A") (yas-next-field) (insert "B") (yas-next-field)
        (should (equal (buffer-string) (if (equal fields '((0 0 1 "") (0 0 2 ""))) "ABx;" "AB;")))))))

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

(ert-deftest emmet2-complete-real-layout-and-no-second-indentation ()
  (dolist (mode '(web-mode tsx-ts-mode))
    (with-temp-buffer
      (setq buffer-file-name (if (eq mode 'tsx-ts-mode) "/tmp/example.tsx" "/tmp/example.html"))
      (insert (if (eq mode 'tsx-ts-mode) "const A = (<main>ul>li*2</main>);" "<main>ul>li*2</main>"))
      (funcall mode) (setq-local indent-tabs-mode nil)
      (goto-char (point-min)) (search-forward "li*")
      (let* ((analysis (emmet2-context-analyze)) (beg (plist-get analysis :beg))
             (end (plist-get analysis :end)) (original (buffer-string))
             (expected (emmet2-expand-analysis analysis)))
        (cl-letf (((symbol-function 'indent-region) (lambda (&rest _) (error "Second indentation"))))
          (emmet2-test--complete-first))
        (should (equal (buffer-string) (concat (substring original 0 (1- beg))
                                              (plist-get expected :text) (substring original (1- end)))))
        (should (= (point) (+ beg (plist-get expected :cursor))))))))

(ert-deftest emmet2-complete-options-and-nonfile-buffers ()
  (with-temp-buffer
    (let ((emmet2-markup-variant "solid") (emmet2-css-modules-object "style")
          (emmet2-class-names-constructor "classnames"))
      (insert "div.a.b") (emmet2-mode 1) (emmet2-test--complete-first)
      (should (equal (buffer-string) "<div class={classnames(style.a, style.b)}></div>"))
      (should-not (emmet2-context-js--owner)) (emmet2-mode -1) (should-not (emmet2-context-js--owner))))
  (with-temp-buffer
    (let ((emmet2-markup-variant "solid"))
      (insert "_div.a.b") (emmet2-test--complete-first)
      (should (equal (buffer-string) "<div class=\"a b\"></div>"))))
  (dolist (option '(emmet2-css-modules-object emmet2-class-names-constructor))
    (should (funcall (get option 'safe-local-variable) "project.reference")))
  (dolist (style '(plain css-modules))
    (should (funcall (get 'emmet2-jsx-class-style 'safe-local-variable) style)))
  (should-not (funcall (get 'emmet2-jsx-class-style 'safe-local-variable) 'arbitrary))
  (should (funcall (get 'emmet2-markup-variant 'safe-local-variable) "solid"))
  (should-not (funcall (get 'emmet2-markup-variant 'safe-local-variable) "arbitrary")))

(ert-deftest emmet2-complete-without-choices-preserves-source ()
  ;; A failed expansion offers no choice; completion reports nothing to insert.
  (with-temp-buffer
    (insert "p")
    (cl-letf (((symbol-function 'emmet2-expand-analysis)
               (lambda (_) (signal 'emmet2-backend-error '("bad %s 100%")))))
      (should-error (emmet2-test--complete-first) :type 'user-error))
    (should (equal (buffer-string) "p")))
  (with-temp-buffer
    (insert "const a = 'div';") (js-mode) (goto-char 13)
    (should-error (emmet2-test--complete-first) :type 'user-error)
    (should (equal (buffer-string) "const a = 'div';"))))

(ert-deftest emmet2-insert-yas-before-hook-cannot-change-the-source ()
  (emmet2-test-with-insertion t
    (let ((yas-before-expand-snippet-hook (list (lambda () (insert "changed")))))
      (should-error (emmet2-insert snapshot (emmet2-result-create "x" '((0 1 1 "x"))))
                    :type 'emmet2-error))
    (should (equal (buffer-string) "abbr"))
    (should-not (yas-active-snippets))))

(ert-deftest emmet2-complete-preserves-literal-tabs-and-emoji ()
  (with-temp-buffer
    (insert "p{😀a\tb}") (setq-local indent-tabs-mode nil)
    (emmet2-test--complete-first)
    (should (equal (buffer-string) "<p>😀a\tb</p>"))))

(ert-deftest emmet2-mode-lifecycle-and-lazy-backend ()
  (with-temp-buffer
    (insert "const A=(<main>ul>li*2</main>);") (tsx-ts-mode)
    (emmet2-mode 1)
    (let* ((owner (emmet2-context-js--owner)) (timer (emmet2-context-js--state-timer owner)))
      (emmet2-mode 1)
      (should (eq owner (emmet2-context-js--owner)))
      (should (eq timer (emmet2-context-js--state-timer owner)))
      (goto-char (point-min)) (search-forward "li*") (emmet2-test--complete-first)
      (should (emmet2-context-js--parsers))
      (let ((host-parsers (treesit-parser-list)))
        (emmet2-mode -1)
        (should (equal host-parsers (treesit-parser-list)))
        (should-not (emmet2-context-js--owner))
        (should-not (memq timer timer-idle-list))))
    (emmet2-mode 1) (text-mode) (should-not (emmet2-context-js--owner)))
  (with-temp-buffer
    (emmet2-mode 1)
    (emmet2-mode-unload-function)
    (should-not emmet2-mode)
    (should-not (emmet2-context-js--owner)))
  (should-not (featurep 'deno-bridge))
  ;; Direct expansion is an explicit command; the mode binds no key to it.
  (should-not (lookup-key emmet2-mode-map (kbd "C-j")))
  (should-not (fboundp 'emmet2-expand)))

(ert-deftest emmet2-expand-at-point-uses-first-choice-and-one-undo ()
  (dolist (case '((css-mode ".a{ta}" "ta") (text-mode "ul>li*2" "li*")))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (cadr case)) (funcall (car case)) (buffer-enable-undo)
        (goto-char 1) (search-forward (nth 2 case))
        (let* ((analysis (emmet2-context-analyze)) (beg (plist-get analysis :beg))
               (end (plist-get analysis :end)) (before (buffer-string))
               (expected (emmet2-expand-analysis analysis)))
          (undo-boundary)
          (emmet2-expand-at-point)
          (should (equal (buffer-string) (concat (substring before 0 (1- beg))
                                                (plist-get expected :text) (substring before (1- end)))))
          (should (= (point) (+ beg (plist-get expected :cursor))))
          (undo-only 1)
          (should (equal (buffer-string) before))))))
  (with-temp-buffer
    (insert "const a = 'div';") (js-mode) (goto-char 13)
    (should-error (emmet2-expand-at-point) :type 'user-error)
    (should (equal (buffer-string) "const a = 'div';")))
  ;; Like its first completion choice, direct expansion consumes a pending separator.
  (dolist (input '("m10," "m10+"))
    (with-temp-buffer
      (css-mode) (insert ".a{" input "}") (backward-char)
      (emmet2-expand-at-point)
      (should (equal (buffer-string) ".a{margin: 10px;}"))))
  ;; Built-in CSS uses the admission of `emmet2-complete'; unknown names never expand.
  (dolist (input '("xyz" "-webkit-transition"))
    (with-temp-buffer
      (css-mode) (insert ".a{" input "}") (backward-char)
      (should-error (emmet2-expand-at-point) :type 'user-error)
      (should (equal (buffer-string) (concat ".a{" input "}")))))
  (with-temp-buffer
    (insert "p") (setq buffer-read-only t)
    (should-error (emmet2-expand-at-point) :type 'user-error)
    (should (equal (buffer-string) "p"))))

(ert-deftest emmet2-complete-yas-real-hosts-preserve-rendered-result ()
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
        (let* ((this-command 'emmet2-complete)
               (analysis (emmet2-context-analyze)) (beg (plist-get analysis :beg))
               (end (plist-get analysis :end)) (before (buffer-string))
               (result (emmet2-expand-analysis analysis)))
          (should analysis)
          (emmet2-test--complete-first)
          (should (equal (buffer-string) (concat (substring before 0 (1- beg))
                                                (plist-get result :text) (substring before (1- end)))))
          (should (= (point) (+ beg (plist-get result :cursor))))
          (if (and (eq (plist-get analysis :lang) 'markup) (plist-get result :fields))
              (progn
                (should (yas-active-snippets))
                (yas-exit-all-snippets)
                (should (= (point) (+ beg (length (plist-get result :text))))))
            (should-not (yas-active-snippets))))))))

(ert-deftest emmet2-mode-unload-cleans-command-created-context ()
  (with-temp-buffer
    (insert "p") (emmet2-test--complete-first)
    ;; Explicit JS analysis may allocate resources without minor mode enabled.
    (erase-buffer) (insert "const A=(<main>p</main>);") (tsx-ts-mode)
    (goto-char 20) (emmet2-context-analyze)
    (should (emmet2-context-js--owner))
    (emmet2-mode-unload-function)
    (should-not (emmet2-context-js--owner))))

(ert-deftest emmet2-insert-keeps-user-hooks-and-settings ()
  (with-temp-buffer
    (insert "<main>ul>li*2</main>") (web-mode) (yas-minor-mode 1)
    (goto-char 1) (search-forward "li*2")
    (let ((called 0) (yas-indent-line 'auto) (yas-wrap-around-region t)
          (this-command 'emmet2-complete))
      (add-hook 'yas-after-exit-snippet-hook (lambda () (cl-incf called)) nil t)
      (let ((hooks (copy-sequence yas-after-exit-snippet-hook)) (fold case-fold-search))
        (emmet2-test--complete-first)
        (let ((rendered (buffer-string)))
          (yas-exit-all-snippets)
          (should (equal (buffer-string) rendered)))
        (should (= called 1))
        (should (equal hooks yas-after-exit-snippet-hook))
        (should (eq yas-indent-line 'auto))
        (should yas-wrap-around-region)
        (should (eq fold case-fold-search))))))

(ert-deftest emmet2-complete-missing-grammar-and-cancellation-leave-source ()
  (with-temp-buffer
    (insert "const A=(<main>ul>li*2</main>);") (js-mode)
    (goto-char 1) (search-forward "li*")
    (let ((before (buffer-string)) (position (point)))
      (cl-letf (((symbol-function 'treesit-language-available-p) (lambda (_) nil)))
        (should-error (emmet2-test--complete-first) :type 'user-error))
      (should (equal before (buffer-string))) (should (= position (point)))))
  (with-temp-buffer
    (insert "p")
    (cl-letf (((symbol-function 'emmet2-expand-analysis) (lambda (_) (signal 'quit nil))))
      (should (eq (condition-case nil (progn (emmet2-test--complete-first) nil) (quit 'quit)) 'quit)))
    (should (equal (buffer-string) "p"))))

(ert-deftest emmet2-insert-stacked-yas-undo-preserves-parent ()
  (with-temp-buffer
    (yas-minor-mode 1) (buffer-enable-undo)
    (let ((this-command 'emmet2-complete))
      (yas-expand-snippet "${1:abbr} ($1)$0" nil nil '((yas-indent-line nil)))
      (undo-boundary)
      (let ((before (buffer-string)) (parent (car (yas-active-snippets)))
            (snapshot (emmet2-insert-snapshot '(:beg 1 :end 5 :abbr "abbr" :lang markup))))
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
