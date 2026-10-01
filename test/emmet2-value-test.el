;;; emmet2-value-test.el --- CSS value completion contracts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-capf-test)
(require 'emmet2-css-value)

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
