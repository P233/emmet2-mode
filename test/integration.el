;;; integration.el --- Complete native package acceptance -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'ert)
(let ((package (getenv "EMMET2_TEST_PACKAGE")))
  (when package
    (unless (and (file-name-absolute-p package) (file-directory-p package))
      (error "EMMET2_TEST_PACKAGE must name an installed package directory"))
    (setq load-path (cons (file-name-as-directory package) (delete emmet2-test-root load-path)))))
(require 'emmet2-engine)
(require 'emmet2-core-contract)
(require 'emmet2-lorem-contract)
(declare-function emmet2-preview-clear "emmet2-preview")

(ert-deftest emmet2-integration-complete-core-oracle ()
  (emmet2-core-test--check #'emmet2-engine-expand))

(ert-deftest emmet2-integration-lorem-structural-contract ()
  (emmet2-lorem-test--run #'emmet2-engine-expand))

(when (or (featurep 'emmet2-engine-markup) (featurep 'emmet2-engine-stylesheet))
  (error "Run native integration in a fresh Emacs process"))

;; emmet2 never loads css-mode, even for embedded styles or CSS previews; only the tests below do.
(require 'emmet2-mode)
(require 'emmet2-preview)
(require 'web-mode)
(dolist (style '("<style>" "<style lang=\"scss\">"))
  (with-temp-buffer
    (insert style ".a { m10+p10 }</style>")
    (web-mode)
    (search-backward "+p10")
    (forward-char 4)
    (unless (eq (plist-get (emmet2-context-analyze) :lang) 'css)
      (error "Integration did not analyze an embedded style"))))
(emmet2-preview "margin: 10px;\npadding: 10px;" 'css)
(when (featurep 'css-mode)
  (error "emmet2 loaded css-mode"))
(emmet2-preview-clear)

(let ((expand (symbol-function 'emmet2-engine-expand))
      (package (getenv "EMMET2_TEST_PACKAGE"))
      (calls 0))
  (unwind-protect
      (progn
        (emmet2-test-without-processes "Native expansion must not use a process"
          (cl-letf (((symbol-function 'emmet2-engine-expand)
                     (lambda (&rest arguments) (cl-incf calls) (apply expand arguments))))
            ;; Every suite runs here, so a new test file cannot be left out.
            (dolist (file (directory-files (expand-file-name "test" emmet2-test-root) nil "\\`emmet2-.*-test\\.el\\'"))
              (require (intern (file-name-base file))))
            (let ((stats (ert-run-tests-batch t)))
              (when (> (ert-stats-completed-unexpected stats) 0)
                (error "Native integration failed")))))
        (unless (> calls 1) (error "Integration did not call the public engine"))
        (when package
          (dolist (symbol '(emmet2-engine-expand emmet2-context-analyze emmet2-extensions-markup
                             emmet2-expand-analysis emmet2-capf emmet2-corfu--rows emmet2-insert emmet2-preview
                             emmet2-engine-markup-expand emmet2-engine-stylesheet-expand))
            (unless (and (file-in-directory-p (symbol-file symbol) package)
                         (byte-code-function-p (symbol-function symbol)))
              (error "Integration did not load installed bytecode: %s" symbol))))
        (message "Verified complete native integration (%d core calls)" calls))
    (when (fboundp 'emmet2-preview-clear) (emmet2-preview-clear))))

;;; integration.el ends here
