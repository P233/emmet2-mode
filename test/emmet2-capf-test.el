;;; emmet2-capf-test.el --- Completion safety and lifecycle -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-capf-contract-test)
(require 'typescript-ts-mode)

(ert-deftest emmet2-capf-confidence-and-host-gates ()
  (dolist (case '((web-mode "div│" nil) (web-mode "custom-element│" nil)
                  (web-mode "a:link│" nil) (web-mode "!│" t)
                  (web-mode "ul>li*2│" t) (web-mode "div.card│" t)
                  (web-mode "<div title='ul>li*2│'></div>" nil)
                  (web-mode "<!-- ul>li*2│ -->" nil)
                  (css-mode ".a{margin│}" nil) (css-mode ".a{m│}" nil)
                  (css-mode ".a{m1│}" t) (css-mode ".a{mA│}" t)
                  (css-mode ".a{c#fff│}" t) (css-mode ".a{p!│}" t)
                  (css-mode ".a{p[1px]│}" t) (css-mode ".a{p(1 + 2)│}" t)
                  (css-mode ".a{m,p│}" t) (css-mode ".a{c+bg│}" t)
                  (css-mode ".a{color: m1│}" nil) (css-mode ".card│" nil)
                  (css-mode "@│" nil) (css-mode "@md│" t)
                  (css-mode ":│" nil) (css-mode "_:hv│" t)
                  (css-mode "::b│" t) (css-mode "@media m1│" nil)
                  (fundamental-mode "ul>li*2│" nil)
                  (tsx-ts-mode "const A=(<main>ul>li*2│</main>);" t)
                  (tsx-ts-mode "const A=(<main>{items.ma│}</main>);" nil)
                  (tsx-ts-mode "const A=()=>ul>li*2│;" nil)
                  (tsx-ts-mode "const A=(<main style={{m10│}} />);" t)))
    (ert-info ((format "%S" case))
      (with-temp-buffer
        (insert (nth 1 case))
        (search-backward "│") (delete-char 1)
        (let ((position (point)))
          (funcall (car case)) (goto-char position)
          (emmet2-context--prepare)
          (should (eq (not (null (emmet2-capf))) (nth 2 case))))))))

(ert-deftest emmet2-capf-lazy-single-result-and-annotation ()
  (emmet2-test--with-capf "p{界😀abcdefghijklmnop}*5"
    (let* ((expand (symbol-function 'emmet2--expand-analysis)) (calls 0)
           (data (emmet2-capf)) (table (nth 2 data)) (props (nthcdr 3 data))
           (abbr (buffer-string)))
      (cl-letf (((symbol-function 'emmet2--expand-analysis)
                 (lambda (analysis) (cl-incf calls) (funcall expand analysis))))
        (should (eq (completion-metadata-get (completion-metadata abbr table nil) 'category) 'emmet2))
        (should (= calls 0))
        (should (equal (all-completions abbr table) (list abbr)))
        (should (test-completion abbr table))
        (should (equal (try-completion abbr table) abbr))
        (let ((annotation (funcall (plist-get props :annotation-function) abbr)))
          (should (<= (string-width annotation) 62))
          (should-not (string-match-p "[\n\t]" annotation))
          (should (string-match-p "界😀" annotation)))
        (should (eq (funcall (plist-get props :company-kind) abbr) 'snippet))
        (should-not (plist-member props :company-prefix-length))
        (should (= calls 1))
        (should (equal (buffer-string) abbr))))))

(ert-deftest emmet2-capf-rejects-every-stale-source ()
  (dolist (change '(text outside delete-restore point mode narrow disabled options indent host buffer))
    (ert-info ((format "%s" change))
      (emmet2-test--with-capf "<main>ul>li*2</main>"
        (goto-char 14)
        (let* ((data (emmet2-capf)) (table (nth 2 data))
               (exit (plist-get (nthcdr 3 data) :exit-function))
               (abbr "ul>li*2"))
          (should (equal (all-completions abbr table) (list abbr)))
          (pcase change
            ('text (insert "3"))
            ('outside (save-excursion (goto-char (point-min)) (insert "x")))
            ('delete-restore (delete-char -1) (insert "2"))
            ('point (backward-char))
            ('mode (text-mode))
            ('narrow (narrow-to-region 8 14))
            ('disabled (emmet2-mode -1))
            ('options (setq-local emmet2-markup-variant "solid"))
            ('indent (setq-local web-mode-markup-indent-offset 9))
            ('host
             (let ((tick (buffer-chars-modified-tick)))
               (setq-local web-mode-content-type "jsx")
               (should (= tick (buffer-chars-modified-tick))))))
          (cl-flet ((reject ()
                      (let ((before (buffer-string)) (position (point)))
                        (should-not (all-completions abbr table))
                        (funcall exit abbr 'finished)
                        (should (equal (buffer-string) before))
                        (should (= position (point))))))
            (if (eq change 'buffer)
                (with-temp-buffer (insert "<main>ul>li*2</main>") (web-mode) (goto-char 14) (reject))
              (reject))))))))

(ert-deftest emmet2-capf-exit-status-and-candidate-guard ()
  (dolist (status '(exact sole nil cancelled))
    (emmet2-test--with-capf "ul>li*3"
      (let ((exit (plist-get (nthcdr 3 (emmet2-capf)) :exit-function)))
        (funcall exit "ul>li*3" status)
        (funcall exit "div.card" 'finished)
        (should (equal (buffer-string) "ul>li*3"))))))

(ert-deftest emmet2-capf-backend-failure-and-source-change ()
  (dolist (failure '(parse quit backend source))
    (emmet2-test--with-capf "ul>li*3"
      (cl-letf (((symbol-function 'emmet2--expand-analysis)
                 (lambda (_)
                   (pcase failure
                     ('parse (signal 'emmet2-parse-error '("invalid" 0)))
                     ('quit (signal 'quit nil))
                     ('backend (signal 'emmet2-backend-error '("failure")))
                     ('source (insert "4") (emmet2-result-create "unsafe"))))))
        (pcase failure
          ('quit (should (eq (condition-case nil (all-completions "ul>li*3" table)
                               (quit 'cancelled)) 'cancelled)))
          ('backend (should-error (all-completions "ul>li*3" table) :type 'emmet2-backend-error))
          (_ (should-not (all-completions "ul>li*3" table))))
        (should (equal (buffer-string) (if (eq failure 'source) "ul>li*34" "ul>li*3")))))))

(ert-deftest emmet2-capf-mode-registration-and-command-isolation ()
  (let ((global completion-at-point-functions))
    (with-temp-buffer
      (insert "div") (web-mode)
      (let ((other (lambda () (error "Other capf must not run"))))
        (setq-local completion-at-point-functions (list other))
        (emmet2-mode 1) (emmet2-mode 1)
        (should (equal completion-at-point-functions (list #'emmet2-capf other)))
        (should-error (emmet2-complete) :type 'user-error)
        (should (equal completion-at-point-functions (list #'emmet2-capf other)))
        (emmet2-mode -1)
        (should (equal completion-at-point-functions (list other)))))
    (should (equal completion-at-point-functions global))))

(ert-deftest emmet2-capf-explicit-command-warms-but-keeps-host-gate ()
  (with-temp-buffer
    (insert "const A=(<main>ul>li*2</main>);") (tsx-ts-mode) (search-backward "</main>")
    (let ((completion-in-region-function (lambda (_beg _end table &optional _pred)
                                           (should (test-completion "ul>li*2" table)) t)))
      (should-not (emmet2-capf))
      (emmet2-complete)
      (should (emmet2-capf))))
  (with-temp-buffer
    (insert "const A=()=>ul>li*2;") (tsx-ts-mode) (backward-char)
    (should-error (emmet2-complete) :type 'user-error))
  (with-temp-buffer
    (insert "const A=(<main>ul>li*2</main>);") (tsx-ts-mode) (search-backward "</main>")
    (cl-letf (((symbol-function 'treesit-language-available-p) (lambda (&rest _) nil)))
      (should-not (emmet2-capf))
      (should-error (emmet2-complete) :type 'user-error))))

(ert-deftest emmet2-capf-corfu-acceptance-matrix-and-middle-point ()
  (dolist (configuration '(((basic partial-completion emacs22) nil)
                           ((partial-completion basic) nil)
                           ((partial-completion) nil)
                           ((basic partial-completion emacs22) ((emmet2 (styles partial-completion))))))
    (dolist (exact '(nil show insert quit))
      (dolist (command '(completion-at-point emmet2-complete))
        (dolist (middle '(nil t))
          (should (eq (cadr (emmet2-test--completion-session
                            (car configuration) (cadr configuration) exact nil nil nil t nil middle command))
                      'finished)))))))

(ert-deftest emmet2-capf-corfu-prompt-and-selection ()
  (dolist (select '(nil t))
    (let ((result
           (emmet2-test--completion-session
            '(basic partial-completion) nil nil nil nil nil nil 'prompt nil nil
            (lambda ()
              (should (= corfu--index -1))
              (when select (corfu-next))
              (corfu-insert)
              (should (equal (buffer-string)
                             (if select "<ul>\n    <li></li>\n    <li></li>\n    <li></li>\n</ul>" "ul>li*3")))))))
      (should (eq (cadr result) (and select 'finished))))))

(ert-deftest emmet2-capf-corfu-typing-and-movement-end-old-session ()
  (dolist (action '(insert delete move))
    (let ((result
           (emmet2-test--completion-session
            '(basic partial-completion) nil nil nil nil nil nil nil nil nil
            (lambda ()
              (pcase action ('insert (insert "4")) ('delete (delete-char -1)) ('move (backward-char)))
              (let ((before (buffer-string)))
                (let ((this-command (if (eq action 'move) 'backward-char 'self-insert-command)))
                  (corfu--post-command))
                (should-not completion-in-region-mode)
                (should (equal (buffer-string) before)))))))
      (should-not (cadr result)))))

(ert-deftest emmet2-capf-corfu-buffer-switch-and-killed-source ()
  (should-not
   (cadr
    (emmet2-test--completion-session
     '(basic partial-completion) nil nil nil nil nil nil nil nil nil
     (lambda ()
       (let ((source (current-buffer)))
         (with-temp-buffer
           (insert "other buffer")
           ;; Corfu's post-command observer sees the actual buffer change.
           (corfu--post-command)
           (should-not completion-in-region-mode)
           (should (equal (buffer-string) "other buffer")))
         (should (equal (with-current-buffer source (buffer-string)) "ul>li*3")))))))
  (let (captured-table exit)
    (emmet2-test--with-capf "ul>li*3"
      (let ((data (emmet2-capf)))
        (setq captured-table (nth 2 data) exit (plist-get (nthcdr 3 data) :exit-function))))
    (should (functionp captured-table))
    (with-temp-buffer
      (insert "ul>li*3")
      (should-not (all-completions "ul>li*3" captured-table))
      (funcall exit "ul>li*3" 'finished)
      (should (equal (buffer-string) "ul>li*3")))))

(ert-deftest emmet2-capf-auto-threshold-does-not-expand ()
  (with-temp-buffer
    (insert ".a{m1}") (css-mode) (backward-char) (emmet2-mode 1)
    (let ((corfu-auto-prefix 3) (corfu-auto-trigger nil) (last-command-event ?1))
      (cl-letf (((symbol-function 'emmet2--expand-analysis)
                 (lambda (_) (ert-fail "Below-threshold candidate must stay lazy")))
                ((symbol-function 'corfu--protect) #'funcall))
        (corfu-auto--complete-deferred)
        (should-not completion-in-region-mode)
        (should (equal (buffer-string) ".a{m1}"))))))

(ert-deftest emmet2-capf-frontend-free-acceptance-and-undo ()
  (emmet2-test--with-capf "ul>li*3"
    (buffer-enable-undo)
    (let ((completion-styles '(partial-completion))
          (completion-category-defaults nil) (completion-category-overrides nil)
          (completion-in-region-function #'completion--in-region)
          (completion-cycle-threshold nil))
      (completion-at-point)
      (should (string-prefix-p "<ul>" (buffer-string)))
      (undo 1)
      (should (equal (buffer-string) "ul>li*3")))))

(ert-deftest emmet2-capf-read-only-and-invalid-syntax ()
  (emmet2-test--with-capf "ul>li*3"
    (setq buffer-read-only t)
    (should-not (emmet2-capf)))
  (with-temp-buffer
    (insert ".a{p(1}") (css-mode) (backward-char)
    (let ((table (nth 2 (emmet2-capf))))
      (should table)
      (should-not (all-completions "p(1" table)))))

(provide 'emmet2-capf-test)
;;; emmet2-capf-test.el ends here
