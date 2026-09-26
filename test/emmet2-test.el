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
     (load (expand-file-name "test/emmet2-context-test.el" emmet2-test-root) nil t))
    ("results"
     (load (expand-file-name "test/emmet2-engine-test.el" emmet2-test-root) nil t))
    ("markup-extensions"
     (load (expand-file-name "test/emmet2-extensions-markup-test.el" emmet2-test-root) nil t))
    ("css-extensions"
     (load (expand-file-name "test/emmet2-extensions-css-test.el" emmet2-test-root) nil t))
    ("fuzzy"
     (load (expand-file-name "test/emmet2-fuzzy-test.el" emmet2-test-root) nil t))
    ("node"
     (load (expand-file-name "test/emmet2-engine-node-test.el" emmet2-test-root) nil t))
    (_ (error "Suite %s is not implemented; available: contracts, results, node, fuzzy, css-extensions, markup-extensions" suite)))
  (message "Implemented %s tests only; native engines and editor integration are not implemented" suite))

;;; emmet2-test.el ends here
