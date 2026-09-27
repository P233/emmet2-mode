;;; emmet2-capf-contract-test.el --- Completion integration contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'corfu)
(require 'corfu-auto)

(require 'emmet2-capf)
(require 'web-mode)

;; Private Corfu calls inspect the pinned frontend; production uses public APIs.
(defmacro emmet2-test--with-capf (text &rest body)
  "Run BODY in a web buffer with TEXT and a real production capf."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text) (web-mode) (emmet2-mode 1)
     (setq-local indent-tabs-mode nil)
     (let ((table (nth 2 (emmet2-capf)))) (ignore table) ,@body)))

(ert-deftest emmet2-contract-table-is-original-text ()
  (emmet2-test--with-capf "ul>li*3"
    (should (equal (all-completions "ul>li*3" table) '("ul>li*3")))
    (should (test-completion "ul>li*3" table))
    (should (equal (try-completion "ul>li*3" table) "ul>li*3"))
    (should-not (try-completion "ul>li*3" table (lambda (_) nil)))
    (should-not (all-completions "other" table))
    (should-not (test-completion "other" table))))

(ert-deftest emmet2-contract-effective-styles-determine-exactness ()
  (dolist (configuration
           '(((basic partial-completion emacs22) nil cons)
             ((partial-completion basic) nil t)
             ((partial-completion) nil t)
             ((basic partial-completion emacs22)
              ((emmet2 (styles partial-completion))) t)))
    (pcase-let ((`(,completion-styles ,completion-category-overrides ,expected)
                 configuration)
                (completion-category-defaults nil))
      (emmet2-test--with-capf "ul>li*3"
        (let ((result (completion-try-completion "ul>li*3" table nil 7)))
          (if (eq expected 'cons)
              (should (equal result '("ul>li*3" . 7)))
            (should (eq result t))))))))

(defun emmet2-test--completion-session (styles overrides exact automatic
                                            &optional abbreviation prefix accept
                                            preselect middle command action)
  "Exercise real analysis, Node, insertion and Corfu, replacing only drawing.
STYLES, OVERRIDES, EXACT and AUTOMATIC select the configuration.
ABBREVIATION defaults to ul>li*3.  PREFIX is the user's auto threshold.
ACCEPT accepts the selected candidate; otherwise cancel.  PRESELECT, MIDDLE
and COMMAND select the frontend policy, starting point and manual entry.
ACTION runs after presentation instead of ordinary acceptance."
  (with-temp-buffer
    (let* ((input (or abbreviation "ul>li*3"))
           (css (equal input "m1"))
           (before (if css (concat ".a{" input "}") input))
           (completion-styles styles)
           (completion-category-defaults nil)
           (completion-category-overrides overrides)
           (completion-cycle-threshold nil)
           (completion-in-region-function #'corfu--in-region-1)
           (corfu-on-exact-match exact)
           (corfu-auto-prefix (or prefix 3))
           (corfu-auto-trigger nil)
           (corfu-preview-current nil)
           (corfu-preselect (or preselect 'valid))
           (last-command-event ?x)
           shown status selected accepted)
      (insert before)
      (if css (css-mode) (web-mode))
      (emmet2-mode 1)
      (setq-local indent-tabs-mode nil)
      (goto-char (if css (1- (point-max)) (point-max)))
      (when middle (backward-char 3))
      (let* ((analysis (emmet2-context-analyze))
             (expected (emmet2--expand-analysis analysis))
             (expand (symbol-function 'emmet2-insert)))
        (cl-letf (((symbol-function 'corfu--candidates-popup)
                   (lambda (&rest _) (setq shown t)))
                  ((symbol-function 'corfu--popup-hide) #'ignore)
                  ((symbol-function 'corfu--protect) #'funcall)
                  ((symbol-function 'emmet2-insert)
                   (lambda (snapshot result)
                     (setq accepted t status 'finished)
                     (funcall expand snapshot result))))
          (unwind-protect
              (progn
                (if automatic
                    (corfu-auto--complete-deferred)
                  (funcall (or command #'completion-at-point))
                  (when completion-in-region-mode (corfu--exhibit)))
                (setq selected corfu--index)
                (if action (funcall action)
                  (when (and accept completion-in-region-mode) (corfu-insert)))
                (when completion-in-region-mode (corfu-quit))
                (unless action
                  (should (equal (buffer-string)
                                 (if accepted
                                     (concat (substring before 0 (1- (plist-get analysis :beg)))
                                             (plist-get expected :text)
                                             (substring before (1- (plist-get analysis :end))))
                                   before)))
                  (when accepted
                    (should (= (point) (+ (plist-get analysis :beg) (plist-get expected :cursor))))))
                (list shown status selected))
            (when completion-in-region-mode (corfu-quit))))))))

(ert-deftest emmet2-contract-corfu-configuration-matrix ()
  (dolist (style '(((basic partial-completion emacs22) nil cons)
                   ((partial-completion basic) nil t)
                   ((partial-completion) nil t)
                   ((basic partial-completion emacs22)
                    ((emmet2 (styles partial-completion))) t)))
    (pcase-let ((`(,styles ,overrides ,try-result) style))
      (dolist (exact '(nil show insert quit))
        (dolist (automatic '(nil t))
          (let* ((popup (or (eq try-result 'cons) (eq exact 'show)))
                 (result (emmet2-test--completion-session styles overrides exact automatic)))
            (should (eq (car result) popup))
            (should (eq (cadr result) (and (not automatic) (not popup) 'finished)))
            (when popup (should (= (nth 2 result) 0)))))))))

(ert-deftest emmet2-contract-auto-prefix-and-explicit-acceptance ()
  (let ((styles '(basic partial-completion emacs22)))
    (should-not (car (emmet2-test--completion-session styles nil nil t "m1" 3)))
    (should (car (emmet2-test--completion-session styles nil nil nil "m1" 3)))
    (should (eq (cadr (emmet2-test--completion-session styles nil nil t nil nil t))
                'finished))
    (should-not (cadr (emmet2-test--completion-session styles nil nil t)))))

(provide 'emmet2-capf-contract-test)
;;; emmet2-capf-contract-test.el ends here
