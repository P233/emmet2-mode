;;; editor-bytecode.el --- Run editor contracts against bytecode -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Compilation-only checks cannot exercise calls which become bytecode
;; primitives or the optional yas adapter against compiled dependencies.
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'bytecomp)

(let* ((directory (make-temp-file "emmet2-editor-bytecode-" t))
       (byte-compile-dest-file-function
        (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") directory))))
  (unwind-protect
      (progn
        ;; Runtime resources resolve next to the compiled package files.
        ;; This is a test copy, not acceptance of a package manager's recipe.
        (dolist (name '("data" "vendor"))
          (copy-directory (expand-file-name name emmet2-test-root) (expand-file-name name directory)))
        (dolist (name (directory-files emmet2-test-root nil "\\.mjs\\'"))
          (copy-file (expand-file-name name emmet2-test-root) (expand-file-name name directory)))
        (dolist (name '("yasnippet" "web-mode" "corfu" "corfu-auto" "corfu-popupinfo"))
          ;; Locked third-party code has existing warnings; report them.
          ;; The project's warning-as-error policy remains below and in compile.el.
          (let ((byte-compile-error-on-warn nil))
            (unless (byte-compile-file (locate-library name))
              (error "Dependency compilation failed: %s" name)))
          (load (expand-file-name (concat name ".elc") directory) nil t))
        (let ((byte-compile-error-on-warn t))
          (dolist (name '("emmet2-engine" "emmet2-engine-node" "emmet2-fuzzy" "emmet2-extensions"
                          "emmet2-extract" "emmet2-context" "emmet2-insert" "emmet2-mode" "emmet2-preview" "emmet2-capf"))
            (unless (byte-compile-file (expand-file-name (concat name ".el") emmet2-test-root))
              (error "Project compilation failed: %s" name))
            (load (expand-file-name (concat name ".elc") directory) nil t)))
        (unless (and (byte-code-function-p (symbol-function 'emmet2-insert))
                     (byte-code-function-p (symbol-function 'emmet2-capf))
                     (byte-code-function-p (symbol-function 'corfu--in-region-1))
                     (byte-code-function-p (symbol-function 'yas-expand-snippet))
                     (byte-code-function-p (symbol-function 'web-mode-scan)))
          (error "Editor checks require byte-compiled paths"))
        (load (expand-file-name "test/emmet2-insert-test.el" emmet2-test-root) nil t)
        (load (expand-file-name "test/emmet2-capf-test.el" emmet2-test-root) nil t)
        (load (expand-file-name "test/emmet2-preview-test.el" emmet2-test-root) nil t)
        (let ((stats (ert-run-tests-batch t)))
          (when (> (ert-stats-completed-unexpected stats) 0)
            (error "Unexpected editor test result"))))
    (when (fboundp 'emmet2-node-stop) (emmet2-node-stop))
    (delete-directory directory t)))

;;; editor-bytecode.el ends here
