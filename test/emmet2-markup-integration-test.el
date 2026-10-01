;;; emmet2-markup-integration-test.el --- Markup through editor boundaries -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-insert-test)
(require 'emmet2-capf-test)
(require 'emmet2-preview-test)

(defun emmet2-integration-test--flows (cases &optional manual-only)
  "Verify completion, preview, yas and undo for host CASES.
MANUAL-ONLY covers hosts which support explicit markup requests only."
  (unwind-protect
      (dolist (case cases)
        (dolist (yas '(nil t))
          (dolist (completion (if manual-only '(nil) '(nil t)))
            (ert-info ((format "%S yas=%s completion=%s" case yas completion))
              (with-temp-buffer
                (insert (nth 1 case)) (search-backward "│") (delete-char 1)
                (let ((position (point)))
                  (setq buffer-file-name
                        (pcase (car case) ('web-mode "/tmp/emmet2.html")
                               ('css-mode "/tmp/emmet2.css") ('scss-mode "/tmp/emmet2.scss")
                               (_ "/tmp/emmet2.tsx")))
                  (funcall (car case)) (goto-char position))
                (setq-local indent-tabs-mode nil emmet2-markup-variant (nth 2 case))
                (emmet2-mode 1)
                (emmet2-test--with-yasnippet yas
                  (buffer-enable-undo)
                  (let* ((this-command 'emmet2-complete)
                         (analysis (emmet2-context-analyze)) (abbr (plist-get analysis :abbr))
                         (beg (plist-get analysis :beg)) (end (plist-get analysis :end))
                         (before (buffer-string)) (result (emmet2-expand-analysis analysis))
                         (preview (emmet2-test--root-render analysis))
                         (expand (symbol-function 'emmet2-capf--choices)) (calls 0)
                         (yas-indent-line 'auto) (yas-wrap-around-region t) (exits 0))
                    (when (nth 3 case) (should (equal (plist-get result :text) (nth 3 case))))
                    (add-hook 'yas-after-exit-snippet-hook (lambda () (cl-incf exits)) nil t)
                    (let ((hooks (copy-sequence yas-after-exit-snippet-hook)))
                      (cl-letf (((symbol-function 'emmet2-capf--choices)
                                 (lambda (&rest args) (cl-incf calls) (apply expand args)))
                                ((symbol-function 'indent-region) (lambda (&rest _) (error "Second indentation"))))
                        (if (not completion) (emmet2-test--complete-first)
                          (let* ((data (emmet2-capf)) (props (nthcdr 3 data)))
                            (should data)
                            (let* ((candidates (all-completions abbr (nth 2 data)))
                                   (candidate (car candidates)) (expanded calls)
                                   (document (funcall (plist-get props :company-doc-buffer) candidate)))
                              (should candidates)
                              (should (cl-every (lambda (item) (equal item abbr)) candidates))
                              (if (string-match-p "\n" (plist-get result :text))
                                  (with-current-buffer document
                                    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                                                   preview)))
                                (should-not document))
                              (funcall (plist-get props :exit-function) candidate 'finished)
                              (should (= calls expanded)))))
                        ;; One batch serves the first choice and its preview/acceptance.
                        (unless completion (should (= calls 1))))
                      (should (equal (buffer-string) (concat (substring before 0 (1- beg))
                                                             (plist-get result :text) (substring before (1- end)))))
                      (should (= (point) (+ beg (plist-get result :cursor))))
                      (when (and yas (plist-get result :fields))
                        (should (yas-active-snippets))
                        (yas-exit-all-snippets)
                        (should (= exits 1))
                        (should (= (point) (+ beg (length (plist-get result :text))))))
                      (should (eq yas-indent-line 'auto))
                      (should yas-wrap-around-region)
                      (should (equal hooks yas-after-exit-snippet-hook))
                      (undo-only 1)
                      (should (equal (buffer-string) before))
                      (should-not (yas-active-snippets))))))))))
    (emmet2-preview-clear)))

(ert-deftest emmet2-markup-command-completion-preview-and-yas ()
  (emmet2-integration-test--flows
   '((web-mode "<main>ul>li│*2</main>" nil)
     (web-mode "<main>.card>span{${1:😀} ${1:😀}}│</main>" "solid")
     (tsx-ts-mode "const A=(<main>ul>li│*2</main>);" nil)
     (tsx-ts-mode "const A=(<main>.abc/│</main>);" nil "<div className={styles.abc} />")
     (tsx-ts-mode "const A=(<main>.abc.xyz/│</main>);" nil "<div className={clsx(styles.abc, styles.xyz)} />")
     (tsx-ts-mode "const A=(<main>.abc.xyz/│</main>);" "solid" "<div class={clsx(styles.abc, styles.xyz)} />")
     (tsx-ts-mode "const A=(<main>.card>span{${1:😀} ${1:😀}}│</main>);" "solid")
     (js-mode "const A=(<main>.card│</main>);" nil)
     (web-mode "<main>p>lorem5+span{${1:😀}}│</main>" nil))))

(ert-deftest emmet2-markup-underscore-class-flows ()
  (emmet2-integration-test--flows
   '((tsx-ts-mode "const A=(<main>_.abc.xyz/│</main>);" nil "<div className=\"abc xyz\" />")
     (tsx-ts-mode "const A=(<main>_.abc.xyz/│</main>);" "solid" "<div class=\"abc xyz\" />")
     (web-mode "<main>_ul>li.x│</main>" nil))))

(ert-deftest emmet2-markup-manual-hosts-preserve-fields-and-undo ()
  (emmet2-integration-test--flows
   '((html-mode "<main>ul>li│*2</main>" nil)
     (html-mode "a│" nil "<a href=\"\"></a>")
     (fundamental-mode "ul>li│*2" nil))
   t))

(provide 'emmet2-markup-integration-test)
;;; emmet2-markup-integration-test.el ends here
