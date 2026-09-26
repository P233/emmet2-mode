;;; compile.el --- Compile implemented rewrite files without artifacts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'bytecomp)

(let* ((directory (make-temp-file "emmet2-byte-compile-" t))
       (byte-compile-error-on-warn t)
       (byte-compile-dest-file-function
        (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") directory))))
  (unwind-protect
      (dolist (file '("emmet2-extract.el" "emmet2-engine.el" "test/bootstrap.el" "test/compile.el"
                      "test/emmet2-capf-contract-test.el" "test/emmet2-extract-test.el"
                      "test/emmet2-host-contract-test.el" "test/emmet2-engine-test.el"
                      "test/emmet2-test.el"))
        (unless (byte-compile-file (expand-file-name file emmet2-test-root))
          (error "Byte compilation failed: %s" file)))
    (delete-directory directory t)))

;;; compile.el ends here
