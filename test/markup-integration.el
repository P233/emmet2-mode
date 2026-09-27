;;; markup-integration.el --- Independent S6 backend acceptance -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Test-only dispatch: the installed editor keeps its normal Node entry.
;; Retire this override after S7 switches the complete native engine.
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'cl-lib)
(require 'ert)
(declare-function emmet2-engine-markup-expand "emmet2-engine-markup")
(declare-function emmet2-node-stop "emmet2-engine-node" (&optional process))
(declare-function emmet2-preview-clear "emmet2-preview")

(let* ((backend (getenv "EMMET2_MARKUP_BACKEND"))
       (native (equal backend "native"))
       (package (getenv "EMMET2_MARKUP_PACKAGE"))
       ;; These six existing tests expand CSS, including two mixed-host loops.
       ;; They still run unchanged in the complete Node suites.  The dedicated
       ;; markup host test supplies the missing markup preview/yas paths here.
       (css-tests '(emmet2-insert-css-fields-tab-and-final-exit
                    emmet2-contract-auto-prefix-and-explicit-acceptance
                    emmet2-capf-read-only-and-invalid-syntax
                    emmet2-expand-yas-real-hosts-preserve-rendered-result
                    emmet2-insert-keeps-user-hooks-and-settings
                    emmet2-preview-capf-shares-final-result-and-syntax))
       (selector `(not (member ,@css-tests))))
  (unless (member backend '("node" "native"))
    (error "Set EMMET2_MARKUP_BACKEND to node or native"))
  (when package
    (unless (and (file-name-absolute-p package) (file-directory-p package))
      (error "EMMET2_MARKUP_PACKAGE must name an installed package directory"))
    (setq load-path (cons (file-name-as-directory package) (delete emmet2-test-root load-path))))
  (require 'emmet2-engine)
  (when (or (featurep 'emmet2-engine-node) (featurep 'emmet2-engine-markup))
    (error "Run each backend in a fresh Emacs process"))
  (when native (require 'emmet2-engine-markup))
  (require 'emmet2-extensions-markup-test)
  (require 'emmet2-markup-integration-test)
  (when package
    (dolist (symbol (append '(emmet2-engine-expand emmet2-context-analyze emmet2-extensions-markup
                             emmet2--expand-analysis emmet2-capf emmet2-insert emmet2-preview)
                           (and native '(emmet2-engine-markup-expand))))
      (unless (and (file-in-directory-p (symbol-file symbol) package)
                   (byte-code-function-p (symbol-function symbol)))
        (error "Integration did not load installed bytecode: %s" symbol))))
  (dolist (name css-tests)
    (unless (ert-test-boundp name) (error "Stale CSS scope entry: %s" name)))
  (let ((expand (if native #'emmet2-engine-markup-expand (symbol-function 'emmet2-engine-expand)))
        (start-process (symbol-function 'make-process))
        (exec-path (unless native exec-path)) (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'emmet2-engine-expand)
                   (lambda (&rest arguments) (cl-incf calls) (apply expand arguments)))
                  ((symbol-function 'make-process)
                   (lambda (&rest arguments)
                     (when native (error "Native markup must not start a process"))
                     (apply start-process arguments))))
          (when native
            (should-error (emmet2-engine-expand "m" :preset 'stylesheet) :type 'emmet2-error))
          (let ((stats (ert-run-tests-batch selector)))
            (when (> (ert-stats-completed-unexpected stats) 0)
              (error "Markup integration failed: %s" backend)))
          (unless (> calls 1) (error "Integration did not call the selected engine"))
          (when (if native (featurep 'emmet2-engine-node)
                  (or (not (featurep 'emmet2-engine-node)) (featurep 'emmet2-engine-markup)))
            (error "Integration escaped its selected backend"))
          (message "Verified isolated %s markup integration (%d core calls)" backend calls))
      (when (fboundp 'emmet2-node-stop) (emmet2-node-stop))
      (emmet2-preview-clear))))

;;; markup-integration.el ends here
