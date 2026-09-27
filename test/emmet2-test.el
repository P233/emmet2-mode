;;; emmet2-test.el --- Stage-scoped ERT entry point -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'ert)

(let ((suite (or (getenv "EMMET2_TEST_SUITE") "contracts")))
  (pcase suite
    ("contracts"
     (load (expand-file-name "test/emmet2-capf-contract-test.el" emmet2-test-root) nil t)
     (load (expand-file-name "test/emmet2-extract-test.el" emmet2-test-root) nil t)
     (load (expand-file-name "test/emmet2-host-contract-test.el" emmet2-test-root) nil t)
     (load (expand-file-name "test/emmet2-context-test.el" emmet2-test-root) nil t)
     (load (expand-file-name "test/emmet2-context-lexical-test.el" emmet2-test-root) nil t))
    ("completion"
     (load (expand-file-name "test/emmet2-capf-contract-test.el" emmet2-test-root) nil t)
     (load (expand-file-name "test/emmet2-capf-test.el" emmet2-test-root) nil t)
     (load (expand-file-name "test/emmet2-preview-test.el" emmet2-test-root) nil t))
    ("editor"
     (load (expand-file-name "test/emmet2-insert-test.el" emmet2-test-root) nil t))
    ("results"
     (load (expand-file-name "test/emmet2-engine-test.el" emmet2-test-root) nil t))
    ("native"
     (require 'emmet2-engine-native-test))
    ("markup-spike"
     (load (expand-file-name "test/emmet2-engine-markup-test.el" emmet2-test-root) nil t))
    ("stylesheet"
     (load (expand-file-name "test/emmet2-engine-stylesheet-test.el" emmet2-test-root) nil t))
    ("markup-extensions"
     (load (expand-file-name "test/emmet2-extensions-markup-test.el" emmet2-test-root) nil t))
    ("css-extensions"
     (load (expand-file-name "test/emmet2-extensions-css-test.el" emmet2-test-root) nil t))
    ("fuzzy"
     (load (expand-file-name "test/emmet2-fuzzy-test.el" emmet2-test-root) nil t))
    ("node"
     (load (expand-file-name "test/emmet2-engine-node-test.el" emmet2-test-root) nil t))
    (_ (error "Suite %s is not implemented; available: completion, editor, contracts, results, native, markup-spike, stylesheet, node, fuzzy, css-extensions, markup-extensions" suite)))
  (message "Selected %s suite" suite))

;;; emmet2-test.el ends here
