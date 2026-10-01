;;; byte-compile.el --- Check independent compilation without artifacts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'bytecomp)

(if-let* ((file (getenv "EMMET2_COMPILE_FILE")))
    (let* ((directory (make-temp-file "emmet2-byte-compile-" t))
           (byte-compile-error-on-warn t)
           (byte-compile-dest-file-function
            (lambda (source) (expand-file-name (concat (file-name-nondirectory source) "c") directory))))
      (unwind-protect
          (unless (byte-compile-file file)
            (error "Byte compilation failed: %s" file))
        (delete-directory directory t)))
  ;; A previous file's requires and declarations must not conceal a missing
  ;; dependency. Discover files instead of maintaining a parallel module list.
  (let ((runner load-file-name)
        (emacs (expand-file-name invocation-name invocation-directory))
        (files (append (directory-files emmet2-test-root t "\\`emmet2-.*\\.el\\'")
                       (directory-files (expand-file-name "test" emmet2-test-root) t "\\.el\\'")))
        failed)
    (dolist (file files)
      (let ((process-environment (cons (concat "EMMET2_COMPILE_FILE=" file) process-environment)))
        (with-temp-buffer
          (unless (zerop (call-process
                          emacs nil (current-buffer) t "--batch" "-Q"
                          "--eval" (prin1-to-string
                                    `(setq native-comp-enable-subr-trampolines
                                           ,(bound-and-true-p native-comp-enable-subr-trampolines)))
                          "-l" runner))
            (princ (buffer-string))
            (push file failed)))))
    (when failed (error "Independent byte compilation failed: %S" (nreverse failed)))
    (princ (format "Independently compiled %d libraries and test runners\n" (length files)))))

;;; byte-compile.el ends here
