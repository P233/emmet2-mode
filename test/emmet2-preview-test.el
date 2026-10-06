;;; emmet2-preview-test.el --- Preview ownership and integration -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-capf-contract-test)
(require 'emmet2-preview)
(require 'corfu-popupinfo)
(require 'typescript-ts-mode)

(defun emmet2-test--root-render (analysis)
  "Render ANALYSIS at column zero, independently of the CAPF display projection."
  (let ((indent (make-string (emmet2-insert--indent-width analysis) ?\s)))
    (cl-letf (((symbol-function 'emmet2-insert-render-options)
               (lambda (_) (list :indent indent :base-indent ""))))
      (plist-get (emmet2-expand-analysis analysis) :text))))

(ert-deftest emmet2-preview-three-buffers-exact-text-and-fontification ()
  (emmet2-preview-clear)
  (unwind-protect
      (with-temp-buffer
        (insert "source")
        (let ((tick (buffer-chars-modified-tick)) (source (current-buffer))
              (cases '((html html-mode "<main class=\"card\">界😀</main>")
                       (jsx js-jsx-mode "<main className={styles.card}>界😀</main>")
                       (css emmet2-preview-css-mode "margin: 10px;\ncolor: #fff;"))))
          (dolist (case cases)
            (let* ((text (nth 2 case)) (buffer (emmet2-preview text (car case))))
              (should (eq buffer (emmet2-preview text (car case))))
              (with-current-buffer buffer
                (should (eq major-mode (cadr case)))
                (should (equal (buffer-substring-no-properties (point-min) (point-max)) text))
                (should (text-property-not-all (point-min) (point-max) 'face nil))
                (should (= (point) (point-min)))
                (should buffer-read-only)
                (should (eq buffer-undo-list t))
                (should-not (buffer-modified-p))
                (should-not buffer-file-name))))
          (should (= (length emmet2-preview--buffers) 3))
          (dotimes (_ 10)
            (dolist (case cases)
              (let ((buffer (emmet2-preview "" (car case))))
                (should (string-empty-p (with-current-buffer buffer (buffer-string))))
                (should (eq buffer (emmet2-preview (nth 2 case) (car case)))))))
          (should (= (length emmet2-preview--buffers) 3))
          (should (eq (current-buffer) source))
          (should (equal (buffer-string) "source"))
          (should (= (point) 7))
          (should (= tick (buffer-chars-modified-tick)))))
    (emmet2-preview-clear)))

(ert-deftest emmet2-preview-colors-css-like-css-mode ()
  (emmet2-preview-clear)
  (unwind-protect
      (with-current-buffer
          (emmet2-preview (concat "-webkit-margin: 10px;\n@include $gutter;\ncolor: #fff !important;\n"
                                  "background: #0000ff80;\nborder: 1px solid Red;\ncolor: $red;\n"
                                  "content: \"#abc white\";\nfill: #12345; /* #def black */")
                          'css)
        (cl-flet ((face (text) (goto-char (point-min)) (search-forward text)
                        (get-text-property (match-beginning 0) 'face)))
          (should (eq (face "-webkit-margin") 'font-lock-keyword-face))
          (should (eq (face "@include") 'font-lock-builtin-face))
          (should (eq (face "$gutter") 'font-lock-variable-name-face))
          (should (eq (face "!important") 'font-lock-builtin-face))
          (should (equal (plist-get (face "#fff") :background) "#fff"))
          (should (equal (plist-get (face "#0000ff80") :background) "#0000ff"))
          (should (equal (downcase (plist-get (face "Red") :background)) "#ff0000"))
          (should (eq (face "color: $red") 'font-lock-keyword-face))
          (should (eq (face "$red") 'font-lock-variable-name-face))
          (dolist (text '("#abc" "white" "#12345" "#def" "black"))
            (ert-info (text) (should-not (plist-get (face text) :background))))
          (should-not (face "10px"))))
    (emmet2-preview-clear)))

(ert-deftest emmet2-preview-isolates-mode-hooks ()
  (emmet2-preview-clear)
  (let* ((trap (list (lambda () (ert-fail "Preview must not run user mode hooks"))))
         (change-major-mode-hook trap) (change-major-mode-after-body-hook trap)
         (after-change-major-mode-hook trap)
         (prog-mode-hook trap) (text-mode-hook trap) (sgml-mode-hook trap)
         (html-mode-hook trap) (js-mode-hook trap) (js-jsx-mode-hook trap)
         (emmet2-preview-css-mode-hook trap))
    (unwind-protect
        (dolist (syntax '(html jsx css))
          (with-current-buffer (emmet2-preview "test" syntax)
            (should-not delayed-mode-hooks)
            (should-not delayed-after-hook-functions)
            (should-not emmet2-mode)
            (should-not (memq #'emmet2-capf completion-at-point-functions))))
      (emmet2-preview-clear))))

(ert-deftest emmet2-preview-deletion-rebuild-and-unload ()
  (emmet2-preview-clear)
  (let ((unrelated (generate-new-buffer " *emmet2-unrelated-test*")))
    (unwind-protect
        (progn
          (let ((first (emmet2-preview "<p/>" 'html)))
            (kill-buffer first)
            (let ((second (emmet2-preview "<p/>" 'html)))
              (should (buffer-live-p second)) (should-not (eq first second))
              (should (= (length emmet2-preview--buffers) 1))))
          (let ((buffers (mapcar (lambda (syntax) (emmet2-preview "text" syntax)) '(html jsx css))))
            (dolist (buffer buffers)
              (with-current-buffer buffer (setq-local kill-buffer-query-functions '(ignore))))
            (emmet2-mode-unload-function)
            (should-not emmet2-preview--buffers)
            (should-not (seq-some #'buffer-live-p buffers)))
          (let ((buffer (emmet2-preview "color: red;" 'css)))
            (emmet2-preview-unload-function)
            (should-not (buffer-live-p buffer)))
          (should (buffer-live-p unrelated)))
      (emmet2-preview-clear)
      (kill-buffer unrelated))))

(ert-deftest emmet2-preview-initialization-failure-does-not-leak ()
  (emmet2-preview-clear)
  (let ((before (buffer-list)))
    (cl-letf (((symbol-function 'html-mode) (lambda () (error "Initialization failed"))))
      (should-error (emmet2-preview "<p/>" 'html)))
    (should-not emmet2-preview--buffers)
    (should (equal (buffer-list) before))
    (should-error (emmet2-preview "text" 'unsupported))
    (should (equal (buffer-list) before))))

(ert-deftest emmet2-preview-capf-shares-final-result-and-syntax ()
  (emmet2-preview-clear)
  (unwind-protect
      (dolist (case '((web-mode "div.card│" nil html-mode)
                      (web-mode "div.card│" "solid" js-jsx-mode)
                      (web-mode "ul>li*2│" nil html-mode)
                      (web-mode "ul>li*2│" "solid" js-jsx-mode)
                      (css-mode ".a{m10+p20│}" nil emmet2-preview-css-mode)
                      (tsx-ts-mode "const A=(<main>div.card│</main>);" nil js-jsx-mode)
                      (tsx-ts-mode "const A=(<main>ul>li.item$*5>a{Link $}│</main>);" nil js-jsx-mode)
                      (tsx-ts-mode "const A=(<main style={{m10│}} />);" nil js-jsx-mode)))
        (with-temp-buffer
          (insert (nth 1 case)) (search-backward "│") (delete-char 1)
          (let ((position (point)))
            (funcall (car case)) (goto-char position)
            (setq-local emmet2-markup-variant (nth 2 case))
            (emmet2-context-js-prepare)
            (let* ((analysis (emmet2-context-analyze))
                   (text (plist-get (emmet2-expand-analysis analysis) :text))
                   (preview (emmet2-test--root-render analysis))
                   (abbr (plist-get analysis :abbr))
                   (expand (symbol-function 'emmet2-capf--choices)) (calls 0)
                   (data (emmet2-capf)) (table (nth 2 data))
                   (props (nthcdr 3 data)) (doc (plist-get props :company-doc-buffer)))
              (cl-letf (((symbol-function 'emmet2-capf--choices)
                         (lambda (&rest args) (cl-incf calls) (apply expand args))))
                ;; CSS offers ranked alternatives; the first is the expansion.
                (should (cl-every (lambda (candidate) (equal candidate abbr)) (all-completions abbr table)))
                (let ((expanded calls) (buffer (funcall doc abbr)))
                  (should (eq buffer (funcall doc abbr)))
                  (if (string-match-p "\n" text)
                      (with-current-buffer buffer
                        (should (eq major-mode (nth 3 case)))
                        (should (equal (buffer-substring-no-properties (point-min) (point-max)) preview)))
                    (should-not buffer))
                  ;; Display, preview and acceptance share one prepared batch.
                  (should (= expanded 1))
                  (should-not (funcall doc "unrelated"))
                  (funcall (plist-get props :exit-function) abbr 'finished)
                  (should (= calls expanded)))
                (should (equal (buffer-substring-no-properties
                                (plist-get analysis :beg) (+ (plist-get analysis :beg) (length text))) text))
                (should-not (funcall doc abbr)))))))
    (emmet2-preview-clear)))

(ert-deftest emmet2-preview-real-popupinfo-documentation-path ()
  (emmet2-preview-clear)
  (unwind-protect
      (should-not
       (cadr
        (emmet2-test--completion-session
         '(basic partial-completion) nil nil nil nil nil nil nil nil nil
         (lambda ()
           (let ((text (corfu-popupinfo--get-documentation "ul>li*3")))
             (should (string-prefix-p "<ul>" text))
             (should (text-property-not-all 0 (length text) 'face nil text))
             (should (equal (buffer-string) "ul>li*3")))))))
    (emmet2-preview-clear)))

(ert-deftest emmet2-preview-capf-removes-source-column-and-keeps-structural-indent ()
  (unwind-protect
      (dolist (case '((web-mode "<main>ul>li*2│</main>" 2 nil 8
                                "<ul>\n  <li></li>\n  <li></li>\n</ul>")
                      (web-mode "\tul>li*2│" 4 t 4
                                "<ul>\n    <li></li>\n    <li></li>\n</ul>")
                      (css-mode ".a{m10+p20│}" 2 nil 8
                                "margin: 10px;\npadding: 20px;")
                      (scss-mode ".a{@el│}" 2 nil 8
                                 "@else {\n  \n}")
                      (scss-mode "\t@el│" 4 t 4
                                 "@else {\n    \n}")))
        (ert-info ((cadr case))
          (with-temp-buffer
            (insert (cadr case)) (funcall (car case))
            (search-backward "│") (delete-char 1)
            (setq-local web-mode-markup-indent-offset (nth 2 case)
                        css-indent-offset (nth 2 case)
                        indent-tabs-mode (nth 3 case) tab-width (nth 4 case))
            (let* ((source (buffer-string)) (tick (buffer-chars-modified-tick))
                   (data (emmet2-capf)) (props (nthcdr 3 data))
                   (candidate (car (all-completions
                                    (buffer-substring-no-properties (car data) (cadr data))
                                    (nth 2 data)))))
              (with-current-buffer (funcall (plist-get props :company-doc-buffer) candidate)
                (should (equal (buffer-substring-no-properties (point-min) (point-max))
                               (nth 5 case))))
              (should (equal (buffer-string) source))
              (should (= (buffer-chars-modified-tick) tick))))))
    (emmet2-preview-clear)))

(provide 'emmet2-preview-test)
;;; emmet2-preview-test.el ends here
