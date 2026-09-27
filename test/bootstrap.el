;;; bootstrap.el --- Isolated native rewrite test dependencies -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'json)
(require 'treesit)

;; Emacs 31 can offer to download mode grammars.  Only explicit setup may
;; download; every locked grammar must already exist in the isolated directory.
(when (boundp 'treesit-auto-install-grammar)
  (set 'treesit-auto-install-grammar nil))

(when (version< emacs-version "30")
  (error "Native rewrite tests require Emacs 30 or later"))

(defconst emmet2-test-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))

(let* ((directory (or (getenv "EMMET2_TEST_DEPS")
                      (error "Set EMMET2_TEST_DEPS; see CONTRIBUTING.md")))
       (dependencies
        (with-temp-buffer
          (insert-file-contents (expand-file-name "test/dependencies.json" emmet2-test-root))
          (json-parse-buffer :object-type 'alist))))
  (dolist (package (alist-get 'packages dependencies))
    (let* ((name (symbol-name (car package)))
           (revision (alist-get 'revision (cdr package)))
           (path (expand-file-name (concat name "-" revision) directory)))
      (unless (file-directory-p path)
        (error "Missing test dependency: %s" path))
      (add-to-list 'load-path path)
      (when (file-directory-p (expand-file-name "extensions" path))
        (add-to-list 'load-path (expand-file-name "extensions" path)))))
  (setq treesit-extra-load-path (list (expand-file-name "grammars" directory)))
  (dolist (grammar (alist-get 'grammars dependencies))
    (let ((language (car grammar)))
      ;; Do not accidentally pass by falling back to the user's/system grammar.
      (unless (file-exists-p
               (expand-file-name
		(format "grammars/libtree-sitter-%s.%s" language
			(if (eq system-type 'darwin) "dylib" "so")) directory))
	(error "Missing isolated test grammar: %s; rerun test/setup.mjs" language))
      (unless (treesit-language-available-p language)
	(error "Missing test grammar: %s; rerun test/setup.mjs" language)))))

(add-to-list 'load-path emmet2-test-root)
(add-to-list 'load-path (expand-file-name "test" emmet2-test-root))
(provide 'emmet2-test-bootstrap)
;;; bootstrap.el ends here
