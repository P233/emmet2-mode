;;; emmet2-value-test.el --- CSS value completion contracts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-capf-test)
(require 'emmet2-css-value)
(require 'emmet2-completion)

(ert-deftest emmet2-value-name-identities-belong-to-one-table ()
  (with-temp-buffer
    (insert "token")
    (let* ((entries (cl-loop for i below 1000 collect (list (format "token_%d" i))))
           (calls 0)
           (data (emmet2-completion-capf
                  1 (point) (lambda () entries) :fuzzy nil
                  :identity (lambda (name)
                              (when (string-match-p "[0-9]" name) (cl-incf calls))
                              (string-replace "_" "-" name))))
           (table (nth 2 data)))
      (completion-metadata "token" table nil)
      (should (zerop calls))
      (should (= (length (all-completions "token" table)) 1000))
      (should (zerop calls))
      (dotimes (_ 3)
        (let ((all (completion-all-completions "token-" table nil 6)))
          (setcdr (last all) nil)
          (should (equal all (mapcar #'car entries))))
        (should (equal (completion-try-completion "token" table nil 5) '("token_" . 6))))
      (should (= calls 1000)))))

(ert-deftest emmet2-value-name-matching-keeps-dynamic-filters ()
  (with-temp-buffer
    (insert "blue")
    (let* ((data (emmet2-completion-capf
                  1 (point) '(("blue_token") ("blue-tone")) :fuzzy nil
                  :identity (lambda (name) (string-replace "_" "-" name))))
           (table (nth 2 data)))
      (cl-labels ((names (&optional predicate)
                    (let ((all (completion-all-completions "blue-" table predicate 5)))
                      (when all (setcdr (last all) nil)) all)))
        (should (equal (names) '("blue_token" "blue-tone")))
        (should (equal (names (lambda (name) (equal name "blue_token"))) '("blue_token")))
        (let ((completion-regexp-list '("tone$")))
          (should (equal (names) '("blue-tone"))))
        (let ((completion-regexp-list '("token$")))
          (should (equal (names) '("blue_token"))))
        (should (equal (names) '("blue_token" "blue-tone")))
        ;; The literal table protocol still uses insertion spellings.
        (should (equal (all-completions "blue_" table) '("blue_token")))))))

(ert-deftest emmet2-value-name-cache-keeps-wrapped-table-protocol ()
  (with-temp-buffer
    (insert "blue")
    (let* ((base (nth 2 (emmet2-completion-capf
                        1 (point) '(("blue_token") ("blue-tone")) :fuzzy nil
                        :identity (lambda (name) (string-replace "_" "-" name)))))
           (filtered (apply-partially #'completion-table-with-predicate base
                                      (lambda (name) (equal name "blue-tone")) t))
           (merged (completion-table-merge base '("blue-extra"))))
      (cl-labels ((names (table)
                    (let ((all (completion-all-completions "blue-" table nil 5)))
                      (when all (setcdr (last all) nil)) all)))
        ;; Warm the original table before asking wrappers that forward its metadata.
        (should (equal (names base) '("blue_token" "blue-tone")))
        (should (equal (names filtered) '("blue-tone")))
        (should (equal (completion-try-completion "blue-" filtered nil 5) '("blue-tone" . 9)))
        (should (equal (names merged) '("blue_token" "blue-tone" "blue-extra")))
        (should (equal (names base) '("blue_token" "blue-tone")))))))

(ert-deftest emmet2-value-name-cache-keeps-category-identity-override ()
  (with-temp-buffer
    (insert "foo")
    (let ((table (nth 2 (emmet2-completion-capf 1 (point) '(("FOO")) :fuzzy nil))))
      (should-not (completion-all-completions "foo" table nil 3))
      (let ((completion-category-overrides '((emmet2-value (emmet2-identity . downcase)))))
        (let ((all (completion-all-completions "foo" table nil 3)))
          (when all (setcdr (last all) nil))
          (should (equal all '("FOO"))))
        (should (equal (completion-try-completion "foo" table nil 3) '("FOO" . 3))))
      (should-not (completion-all-completions "foo" table nil 3)))))

(ert-deftest emmet2-value-name-identities-retry-interruption ()
  (with-temp-buffer
    (insert "a")
    (let* ((collections 0) (interrupt t)
           (data (emmet2-completion-capf
                  1 (point) (lambda () (cl-incf collections) '(("alpha") ("amber")))
                  :fuzzy nil
                  :identity (lambda (name)
                              (when (and interrupt (equal name "amber"))
                                (setq interrupt nil)
                                (throw throw-on-input t))
                              name)))
           (table (nth 2 data)))
      (should (eq (while-no-input (completion-all-completions "a" table nil 1)) t))
      (let ((all (completion-all-completions "a" table nil 1)))
        (setcdr (last all) nil)
        (should (equal all '("alpha" "amber"))))
      (should (= collections 1)))))

(ert-deftest emmet2-value-lazy-entries-are-collected-once ()
  (with-temp-buffer
    (insert "cal")
    (let* ((calls 0)
           (data (emmet2-completion-capf
                  1 (point) (lambda () (cl-incf calls) '(("calc()" . "Calculate")))))
           (table (nth 2 data)) (props (nthcdr 3 data)))
      (should (zerop calls))
      (should (eq (completion-metadata-get (completion-metadata "cal" table nil) 'category)
                  'emmet2-value))
      (should (zerop calls))
      (should (equal (all-completions "cal" table) '("calc()")))
      (should (equal (funcall (plist-get props :company-docsig) "calc()") "Calculate"))
      (should (test-completion "calc()" table))
      (should (= calls 1))
      (delete-region (point-min) (point-max)) (insert "calc()")
      (funcall (plist-get props :exit-function) "calc()" 'finished)
      (should (eq (char-after) ?\))))))

(ert-deftest emmet2-value-lazy-entries-retry-interruption-and-retain-empty-results ()
  (with-temp-buffer
    (insert "x")
    (let* ((calls 0)
           (data (emmet2-completion-capf
                  1 (point) (lambda ()
                              (cl-incf calls)
                              (when (= calls 1) (throw throw-on-input t))
                              nil)))
           (table (nth 2 data)))
      (should (eq (while-no-input (all-completions "x" table)) t))
      (should (= calls 1))
      (should-not (all-completions "x" table))
      (should-not (all-completions "x" table))
      (should (= calls 2)))))

(ert-deftest emmet2-value-lazy-entries-do-not-read-another-source ()
  (dolist (change '(buffer mode text point restriction))
    (with-temp-buffer
      (insert " cal")
      (let* ((calls 0)
             (data (emmet2-completion-capf
                    2 (point) (lambda () (cl-incf calls) '(("calc()")))))
             (table (nth 2 data)))
        (pcase change
          ('mode (text-mode))
          ('text (delete-char -1) (insert "l"))
          ('point (backward-char))
          ('restriction (narrow-to-region 2 (point-max))))
        (if (eq change 'buffer)
            (with-temp-buffer (insert " cal") (should-not (all-completions "cal" table)))
          (should-not (all-completions "cal" table)))
        (should (zerop calls))))))

(ert-deftest emmet2-value-lazy-entries-preserve-existing-call ()
  (with-temp-buffer
    (insert "cal(1rem)") (goto-char 4)
    (let* ((data (emmet2-completion-capf 1 4 (lambda () '(("calc()")))))
           (table (nth 2 data)))
      (should (equal (all-completions "cal" table) '("calc")))
      (insert "c")
      (funcall (plist-get (nthcdr 3 data) :exit-function) "calc" 'finished)
      (should (equal (buffer-string) "calc(1rem)"))
      (should (eq (char-after) ?\()))))

(defmacro emmet2-value-test--with (mode source &rest body)
  "Run BODY in MODE with SOURCE's | marking point and a real Corfu frontend."
  (declare (indent 2) (debug t))
  `(save-window-excursion
     (with-temp-buffer
       (set-window-buffer (selected-window) (current-buffer))
       (funcall ,mode)
       (insert ,source) (goto-char (point-min)) (search-forward "|") (delete-char -1)
       (emmet2-mode 1) (buffer-enable-undo)
       (let ((corfu-auto-prefix 1) (corfu-auto-trigger nil)
             (corfu-on-exact-match 'show) (corfu-preview-current nil)
             (last-command-event ?f))
         (cl-letf (((symbol-function 'corfu--popup-show) #'ignore)
                   ((symbol-function 'corfu--popup-hide) #'ignore)
                   ((symbol-function 'corfu--protect) #'funcall))
           (unwind-protect (progn ,@body)
             (when completion-in-region-mode (corfu-quit))))))))

(ert-deftest emmet2-value-automatic-initials-and-undo ()
  (dolist (mode '(css-mode scss-mode css-ts-mode))
    (emmet2-value-test--with mode ".a { display: if|; }"
                             (corfu-auto--complete-deferred)
                             (should (member "inline-flex" corfu--candidates))
                             (corfu--goto (cl-position "inline-flex" corfu--candidates :test #'equal))
                             (corfu-insert)
                             (undo-boundary)
                             (should (equal (buffer-string) ".a { display: inline-flex; }"))
                             (undo-only 1)
                             (should (equal (buffer-string) ".a { display: if; }")))))

(ert-deftest emmet2-value-sole-fuzzy-match-completes ()
  ;; wp is not a prefix of swap, yet swap is the only match.
  (with-temp-buffer
    (css-mode) (insert "@font-face { font-display: wp; }") (search-backward ";")
    (emmet2-mode 1)
    (completion-at-point)
    (should (equal (buffer-string) "@font-face { font-display: swap; }"))
    (should (looking-at ";"))))

(ert-deftest emmet2-value-sole-match-replaces-the-whole-field ()
  ;; Text after point matched inside the candidate is not appended again.
  (with-temp-buffer
    (css-mode) (insert "@font-face { font-display: wa; }") (search-backward "a;")
    (emmet2-mode 1)
    (completion-at-point)
    (should (equal (buffer-string) "@font-face { font-display: swap; }"))))

(ert-deftest emmet2-value-falls-through-when-nothing-matches ()
  ;; A project value unknown to the CSS data reaches the next source.
  (with-temp-buffer
    (css-mode) (insert ".a { color: zzbrand; }") (search-backward ";")
    (emmet2-mode 1)
    ;; A project source placed after Emmet's value completion, as Eglot would be.
    (add-hook 'completion-at-point-functions
              (lambda () (list (- (point) 7) (point) '("zzbrand-primary"))) -55 t)
    (completion-at-point)
    (should (equal (buffer-string) ".a { color: zzbrand-primary; }"))))

(ert-deftest emmet2-value-function-cursor-and-undo-without-snippet-fields ()
  (dolist (yas '(nil t))
    (emmet2-value-test--with #'css-mode ".a { width: cal|; }"
      (emmet2-test--with-yasnippet yas
        (corfu-auto--complete-deferred)
        (corfu--goto (cl-position "calc()" corfu--candidates :test #'equal))
        (corfu-insert)
        (should (equal (buffer-string) ".a { width: calc(); }"))
        (should (looking-at ");"))
        (should-not mark-active)
        (should-not (yas-active-snippets))
        (undo-boundary) (undo-only 1)
        (should (equal (buffer-string) ".a { width: cal; }"))))))

(ert-deftest emmet2-value-context-keeps-property-and-token-bounds ()
  (dolist (source '(".a { display:if|; }"
                    ".a { display /* : x; */ : if|; }"
                    ".a { color: red; display: if|; }"
                    ".a { content: \";\"; display: if|; }"
                    ".a { .b { color: red; } display: if|; }"
                    ".a { display: block if|; }"))
    (emmet2-value-test--with #'css-mode source
                             (let* ((capf (emmet2-css-value-capf))
                                    (names (completion-all-completions "if" (nth 2 capf) nil 2)))
                               (should capf)
                               (should (equal (buffer-substring-no-properties (car capf) (cadr capf)) "if"))
                               (setcdr (last names) nil)
                               (should (member "inline-flex" names))
                               (should-not (member "red" names))))))

(ert-deftest emmet2-value-context-declines-non-value-input ()
  (dolist (source '(".a:if| {}" ".a { dis| }" ".a { &:if| {} }"
                    ".a { /* display: if|; */ }" ".a { content: \"if|\"; }"
                    ".a { width: calc(if|); }" ".a { width: var(--if|); }"
                    ".a { color: #if|; }" ".a { width: $if|; }"
                    ".a { width: 10p|; }" ".a { width: 1.|; }"
                    ".a { width: theme.if|; }"))
    (emmet2-value-test--with #'css-mode source
                             (should-not (emmet2-css-value-capf)))))

(ert-deftest emmet2-value-existing-call-keeps-arguments ()
  (emmet2-value-test--with #'css-mode ".a { width: cal|c(100% - 1rem); }"
                           (corfu-auto--complete-deferred)
                           (should (member "calc" corfu--candidates))
                           (should-not (member "calc()" corfu--candidates))
                           (corfu--goto (cl-position "calc" corfu--candidates :test #'equal))
                           (corfu-insert)
                           (should (equal (buffer-string) ".a { width: calc(100% - 1rem); }"))))

(ert-deftest emmet2-value-cancel-and-unfinished-do-not-insert-fields ()
  (emmet2-value-test--with #'css-mode ".a { width: cal|; }"
                           (let* ((capf (emmet2-css-value-capf))
                                  (exit (plist-get (nthcdr 3 capf) :exit-function)))
                             (funcall exit "calc()" 'sole)
                             (funcall exit "calc()" 'finished)
                             (should (equal (buffer-string) ".a { width: cal; }"))
                             (corfu-auto--complete-deferred) (corfu-quit)
                             (should (equal (buffer-string) ".a { width: cal; }"))
      (should-not (yas-active-snippets)))))

(ert-deftest emmet2-value-provider-ownership-and-mode-lifetime ()
  (emmet2-value-test--with #'css-mode ".a { display: if|; }"
                           (should (memq #'emmet2-css-value-capf completion-at-point-functions))
                           (let ((emmet2-context-provider (list :analyze #'ignore :revision #'ignore)))
                             (should-not (emmet2-css-value-capf)))
                           (emmet2-mode -1)
                           (should-not (memq #'emmet2-css-value-capf completion-at-point-functions))
                           (should (memq #'css-completion-at-point completion-at-point-functions))))

(provide 'emmet2-value-test)
;;; emmet2-value-test.el ends here
