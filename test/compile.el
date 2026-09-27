;;; compile.el --- Compile implemented rewrite files without artifacts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'bytecomp)

(let* ((directory (make-temp-file "emmet2-byte-compile-" t))
       (byte-compile-error-on-warn t)
       (byte-compile-dest-file-function
        (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") directory))))
  (unwind-protect
      (dolist (file '("emmet2-preview.el" "test/emmet2-preview-test.el" "emmet2-capf.el" "test/emmet2-capf-test.el" "emmet2-insert.el" "emmet2-mode.el" "test/emmet2-insert-test.el" "test/editor-bytecode.el" "test/emmet2-extensions-markup-test.el" "emmet2-extensions.el" "test/emmet2-extensions-css-test.el"
                      "emmet2-fuzzy.el" "test/emmet2-fuzzy-test.el" "emmet2-context.el" "test/emmet2-context-test.el" "emmet2-extract.el" "emmet2-engine.el" "emmet2-engine-node.el"
                      "test/bootstrap.el" "test/compile.el" "test/install.el" "test/bench-context.el" "test/bench-completion.el" "test/emmet2-context-lexical-test.el"
                      "test/emmet2-capf-contract-test.el" "test/emmet2-extract-test.el"
                      "test/emmet2-host-contract-test.el" "test/emmet2-engine-test.el"
                      "test/emmet2-engine-node-test.el" "emmet2-engine-markup.el"
                      "emmet2-engine-stylesheet.el" "test/emmet2-engine-stylesheet-test.el"
                      "test/emmet2-engine-markup-test.el" "test/emmet2-lorem-contract.el" "test/bench-markup.el"
                      "test/emmet2-test.el" "test/emmet2-markup-integration-test.el" "test/backend-integration.el"
                      "test/emmet2-core-contract.el" "test/emmet2-stylesheet-integration-test.el"))
        (unless (byte-compile-file (expand-file-name file emmet2-test-root))
          (error "Byte compilation failed: %s" file)))
    (delete-directory directory t)))

;;; compile.el ends here
