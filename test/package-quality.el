;;; package-quality.el --- Check every installed Lisp library -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'package-lint)
(require 'checkdoc)

(let ((package-lint-main-file (expand-file-name "emmet2-mode.el" emmet2-test-root))
      (files (directory-files emmet2-test-root t "\\.el\\'"))
      failures)
  (dolist (file files)
    (with-temp-buffer
      (insert-file-contents file)
      (setq buffer-file-name file)
      (emacs-lisp-mode)
      (dolist (diagnostic (package-lint-buffer))
        (push (list (file-name-nondirectory file) 'package-lint diagnostic) failures))
      (let ((checkdoc-create-error-function
             (lambda (text start _end &optional _unfixable)
               (push (list (file-name-nondirectory file) 'checkdoc
                           (line-number-at-pos start) text) failures)
               nil)))
        (checkdoc-current-buffer t))))
  (dolist (failure (nreverse failures)) (message "%S" failure))
  (when failures (error "Package quality checks failed"))
  (message "Verified package-lint and checkdoc for %d runtime libraries" (length files)))

;;; package-quality.el ends here
