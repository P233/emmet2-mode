;;; emmet2-test.el --- Stage-scoped ERT entry point -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'ert)

(let ((suite (or (getenv "EMMET2_TEST_SUITE") "contracts")))
  (unless (equal suite "contracts")
    (error "Suite %s is not implemented; available: contracts" suite))
  (load (expand-file-name "test/emmet2-capf-contract-test.el" emmet2-test-root) nil t)
  (load (expand-file-name "test/emmet2-extract-test.el" emmet2-test-root) nil t)
  (load (expand-file-name "test/emmet2-host-contract-test.el" emmet2-test-root) nil t)
  (message "S0 contract probes only; native engines and editor integration are not implemented"))

;;; emmet2-test.el ends here
