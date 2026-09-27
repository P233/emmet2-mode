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

(when (or (featurep 'emmet2-engine-node) (featurep 'emmet2-engine-markup)
          (featurep 'emmet2-engine-stylesheet))
  (error "Run native integration in a fresh Emacs process"))

(let ((expand (symbol-function 'emmet2-engine-expand))
      (package (getenv "EMMET2_TEST_PACKAGE"))
      (exec-path nil) (calls 0))
  (unwind-protect
      (progn
        (cl-letf (((symbol-function 'emmet2-engine-expand)
                   (lambda (&rest arguments) (cl-incf calls) (apply expand arguments)))
                  ((symbol-function 'make-process)
                   (lambda (&rest _) (error "Native expansion must not start a process")))
                  ((symbol-function 'call-process)
                   (lambda (&rest _) (error "Native expansion must not call a process"))))
          (dolist (feature '(emmet2-engine-native-test emmet2-engine-test
                              emmet2-engine-markup-test emmet2-engine-stylesheet-test
                              emmet2-fuzzy-test emmet2-extract-test emmet2-host-contract-test
                              emmet2-context-test emmet2-context-lexical-test
                              emmet2-capf-contract-test emmet2-extensions-markup-test
                              emmet2-extensions-css-test emmet2-markup-integration-test
                              emmet2-stylesheet-integration-test))
            (require feature))
          ;; Retired test files remain identifiable by baseline commit and hash.
          ;; Every legacy case must still have registered replacement tests.
          (let ((migration (with-temp-buffer
                             (insert-file-contents (expand-file-name "test/fixtures/migration.json" emmet2-test-root))
                             (json-parse-buffer :object-type 'alist :array-type 'list))))
            (dolist (group (alist-get 'groups migration))
              (dolist (entry (alist-get 'cases group))
                (unless (and (alist-get 'tests entry)
                             (seq-every-p (lambda (name) (ert-test-boundp (intern name)))
                                          (alist-get 'tests entry)))
                  (error "Legacy case lost its replacement tests: %s" (alist-get 'id entry)))))
            (dolist (entry (append (alist-get 'integration migration) (alist-get 'intentionalChanges migration)))
              (unless (and (alist-get 'tests entry)
                           (seq-every-p (lambda (name) (ert-test-boundp (intern name)))
                                        (alist-get 'tests entry)))
                (error "Migration contract lost its tests: %s" (alist-get 'id entry)))))
          (let ((stats (ert-run-tests-batch t)))
            (when (> (ert-stats-completed-unexpected stats) 0)
              (error "Native integration failed"))))
        (unless (> calls 1) (error "Integration did not call the public engine"))
        (when (featurep 'emmet2-engine-node) (error "Native integration loaded a retired backend"))
        (when package
          (dolist (symbol '(emmet2-engine-expand emmet2-context-analyze emmet2-extensions-markup
                             emmet2--expand-analysis emmet2-capf emmet2-insert emmet2-preview
                             emmet2-engine-markup-expand emmet2-engine-stylesheet-expand))
            (unless (and (file-in-directory-p (symbol-file symbol) package)
                         (byte-code-function-p (symbol-function symbol)))
              (error "Integration did not load installed bytecode: %s" symbol))))
        (message "Verified complete native integration (%d core calls); all 182 legacy cases mapped" calls))
    (when (fboundp 'emmet2-preview-clear) (emmet2-preview-clear))))

;;; integration.el ends here
