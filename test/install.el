;;; install.el --- Exercise an actual isolated straight installation -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;; EMMET2_INSTALL_ROOT must name a new absolute directory.  Keep the resulting
;; installation and report for inspection; never use or rebuild a user's setup.
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'ert)

(defvar straight-base-dir)
(defvar straight-recipe-repositories)
(defvar straight-check-for-modifications)
(declare-function straight-use-package "straight" (recipe &optional no-clone no-build cause interactive))

(defun emmet2-install--git (directory &rest arguments)
  "Run Git ARGUMENTS in DIRECTORY and return its output."
  (with-temp-buffer
    (unless (zerop (apply #'process-file "git" nil t nil "-C" directory arguments))
      (error "Installation Git command failed: %s" (buffer-string)))
    (string-trim-right (buffer-string))))

(let* ((destination (or (getenv "EMMET2_INSTALL_ROOT") (error "Set EMMET2_INSTALL_ROOT")))
       (source emmet2-test-root)
       (revision (emmet2-install--git source "rev-parse" "HEAD"))
       (straight-source (locate-library "straight"))
       (locked
        (with-temp-buffer
          (insert-file-contents (expand-file-name "test/dependencies.json" source))
          (json-parse-buffer :object-type 'alist)))
       (straight-revision (alist-get 'revision (alist-get 'straight.el (alist-get 'packages locked))))
       (resources
        (seq-filter
         (lambda (name) (or (string-match-p "\\`[^/]+\\.el\\'" name)
                            (string-prefix-p "data/" name)))
         (split-string (emmet2-install--git source "ls-files" "-z") "\0" t))))
  (unless (and (file-name-absolute-p destination) (not (file-exists-p destination)))
    (error "Installation destination must be new and absolute: %s" destination))
  (unless (and straight-source
               (equal straight-revision
                      (emmet2-install--git (file-name-directory straight-source) "rev-parse" "HEAD"))
               (string-empty-p (emmet2-install--git (file-name-directory straight-source) "status" "--porcelain")))
    (error "Installation requires the clean locked straight.el checkout"))
  (when (seq-some (lambda (feature) (string-prefix-p "emmet2-" (symbol-name feature)))
                  (remq 'emmet2-test-bootstrap features))
    (error "Run installation in a fresh Emacs process"))
  (make-directory destination t)
  (let* ((user-emacs-directory (file-name-as-directory destination))
         (straight-base-dir user-emacs-directory)
         (straight-recipe-repositories nil)
         (straight-check-for-modifications nil)
         (package-directory (expand-file-name "straight/build/emmet2-mode" destination))
         (repository (expand-file-name "straight/repos/emmet2-mode" destination))
         (binary-directory (expand-file-name "bin" destination)))
    ;; Remove the source fallback before compilation can require other modules.
    ;; Tests remain available from the source tree's separate test directory.
    (setq load-path (delete source load-path))
    ;; Load the pinned source; straight.el's bootstrap would compile it in place.
    (load (expand-file-name "straight.el" (file-name-directory straight-source)) nil t t)
    ;; Only the fetch source differs from README: it clones the reviewed local
    ;; commit instead of GitHub.  The file recipe is exact.
    (straight-use-package
     `(emmet2-mode :type git :repo ,source :local-repo "emmet2-mode"
                   :files (:defaults "data")))
    (unless (and (equal revision (emmet2-install--git source "rev-parse" "HEAD"))
                 (equal revision (emmet2-install--git repository "rev-parse" "HEAD")))
      (error "Installation source revision changed"))
    (dolist (name resources)
      (unless (file-exists-p (expand-file-name name package-directory))
        (error "Recipe omitted resource: %s" name)))
    (dolist (name (seq-filter (lambda (name) (string-match-p "\\`[^/]+\\.el\\'" name)) resources))
      (let ((library (locate-library (file-name-sans-extension name))))
        (unless (and library (file-in-directory-p library package-directory))
          (error "Runtime library escaped the installed package: %s" library))))
    (when (or (directory-files-recursively package-directory "\\.\\(?:mjs\\|ts\\)\\'")
              (file-exists-p (expand-file-name "emmet2-engine-node.el" package-directory))
              (file-exists-p (expand-file-name "test" package-directory)))
      (error "Installed package contains development or retired runtime files"))
    ;; Git is needed to build the package, never to expand an abbreviation.
    ;; Runtime checks have an empty executable path and reject process creation.
    (make-directory binary-directory)
    (setq exec-path nil)
    (setenv "PATH" binary-directory)
    (when (seq-some #'executable-find '("node" "deno" "npm" "git"))
      (error "Runtime PATH isolation failed"))
    (require 'emmet2-mode)
    (unless (byte-code-function-p (symbol-function 'emmet2-expand-analysis))
      (error "The actual package installation must be byte-compiled"))
    (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "Installed runtime must not start a process")))
              ((symbol-function 'call-process) (lambda (&rest _) (error "Installed runtime must not call a process"))))
      (load (expand-file-name "test/emmet2-insert-test.el" source) nil t)
      (load (expand-file-name "test/emmet2-capf-test.el" source) nil t)
      (require 'emmet2-value-test)
      (load (expand-file-name "test/emmet2-preview-test.el" source) nil t)
      (require 'emmet2-engine-native-test)
      (let ((stats (ert-run-tests-batch t)))
        (when (> (ert-stats-completed-unexpected stats) 0)
          (error "Installed editor/completion checks failed"))
        (when (featurep 'emmet2-engine-node) (error "Installed runtime loaded Node"))
        (dolist (entry load-history)
          (when (and (stringp (car entry))
                     (string-match-p "/emmet2-[^/]+\\.elc?\\'" (car entry))
                     (not (file-in-directory-p (car entry) (expand-file-name "test" source)))
                     (not (file-in-directory-p (car entry) destination)))
            (error "Loaded runtime escaped the installation: %s" (car entry))))
        (with-temp-file (expand-file-name "acceptance.json" destination)
          (insert (json-serialize
                   `(:revision ,revision :emacs ,emacs-version :straight ,straight-revision
                     :packageDirectory ,package-directory :externalRuntime :false
                     :resourceCount ,(length resources)
                     :tests ,(ert-stats-completed-expected stats) :runtimePath ,(getenv "PATH")))))))
    (message "Verified installed package: %s" package-directory)))

;;; install.el ends here
