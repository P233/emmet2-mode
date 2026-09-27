;;; backend-integration.el --- Independent complete backend acceptance -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Native acceptance uses the production entry; only Node gets a test override.
;; Retire the reference backend and its override in S8.
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'cl-lib)
(require 'ert)
(let ((package (getenv "EMMET2_TEST_PACKAGE")))
  (when package
    (unless (and (file-name-absolute-p package) (file-directory-p package))
      (error "EMMET2_TEST_PACKAGE must name an installed package directory"))
    (setq load-path (cons (file-name-as-directory package) (delete emmet2-test-root load-path)))))
(require 'emmet2-engine)
(autoload 'emmet2-engine-node-expand "emmet2-engine-node")
(declare-function emmet2-node-stop "emmet2-engine-node" (&optional process))
(declare-function emmet2-preview-clear "emmet2-preview")
(declare-function emmet2-core-test--check "emmet2-core-contract" (expand))
(declare-function emmet2-lorem-test--run "emmet2-lorem-contract" (expand))

(ert-deftest emmet2-backend-complete-core-oracle ()
  (emmet2-core-test--check #'emmet2-engine-expand))

(ert-deftest emmet2-backend-lorem-structural-contract ()
  (emmet2-lorem-test--run #'emmet2-engine-expand))

(cl-defun emmet2-test--node-expand (abbreviation &key (preset 'html) (indent "\t") (base-indent "") jsx)
  "Adapt the temporary Node reference for independent differential tests."
  (emmet2-engine-with-expansion
    (emmet2-engine-node-expand abbreviation preset indent base-indent jsx)))

(let* ((backend (getenv "EMMET2_TEST_BACKEND"))
       (native (equal backend "native"))
       (package (getenv "EMMET2_TEST_PACKAGE")))
  (unless (member backend '("node" "native"))
    (error "Set EMMET2_TEST_BACKEND to node or native"))
  (require 'emmet2-core-contract)
  (require 'emmet2-lorem-contract)
  (when (or (featurep 'emmet2-engine-node) (featurep 'emmet2-engine-markup) (featurep 'emmet2-engine-stylesheet))
    (error "Run each backend in a fresh Emacs process"))
  (when native (require 'emmet2-engine-native-test))
  (require 'emmet2-engine-test)
  (require 'emmet2-fuzzy-test)
  (require 'emmet2-extract-test)
  (require 'emmet2-host-contract-test)
  (require 'emmet2-context-test)
  (require 'emmet2-context-lexical-test)
  (require 'emmet2-extensions-markup-test)
  (require 'emmet2-extensions-css-test)
  (require 'emmet2-markup-integration-test)
  (require 'emmet2-stylesheet-integration-test)
  (let ((expand (if native (symbol-function 'emmet2-engine-expand) #'emmet2-test--node-expand))
        (start-process (symbol-function 'make-process))
        (call-process (symbol-function 'call-process))
        (exec-path (unless native exec-path)) (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'emmet2-engine-expand)
                   (lambda (&rest arguments) (cl-incf calls) (apply expand arguments)))
                  ((symbol-function 'make-process)
                   (lambda (&rest arguments)
                     (when native (error "Native expansion must not start a process"))
                     (apply start-process arguments)))
                  ((symbol-function 'call-process)
                   (lambda (&rest arguments)
                     (when native (error "Native expansion must not call a process"))
                     (apply call-process arguments))))
          (let ((stats (ert-run-tests-batch t)))
            (when (> (ert-stats-completed-unexpected stats) 0)
              (error "Backend integration failed: %s" backend)))
          (unless (> calls 1) (error "Integration did not call the selected engine"))
          (when (if native (featurep 'emmet2-engine-node)
                  (or (not (featurep 'emmet2-engine-node)) (featurep 'emmet2-engine-markup)
                      (featurep 'emmet2-engine-stylesheet)))
            (error "Integration escaped its selected backend"))
          (message "Verified isolated %s complete integration (%d core calls)" backend calls))
      (when (fboundp 'emmet2-node-stop) (emmet2-node-stop))
      (emmet2-preview-clear)))
  (when package
    (dolist (symbol (append '(emmet2-engine-expand emmet2-context-analyze emmet2-extensions-markup
                             emmet2--expand-analysis emmet2-capf emmet2-insert emmet2-preview)
                           (and native '(emmet2-engine-markup-expand emmet2-engine-stylesheet-expand))))
      (unless (and (file-in-directory-p (symbol-file symbol) package)
                   (byte-code-function-p (symbol-function symbol)))
        (error "Integration did not load installed bytecode: %s" symbol)))))

;;; backend-integration.el ends here
