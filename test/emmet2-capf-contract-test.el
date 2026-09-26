;;; emmet2-capf-contract-test.el --- Completion feasibility contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'corfu)
(require 'corfu-auto)

;; S0 probe only: S5 must run these same scenarios against the actual Emmet capf.
;; Private Corfu calls here inspect the pinned frontend; production may not use them.
(defun emmet2-test--table (abbreviation)
  "Return the proposed single-candidate table for ABBREVIATION."
  (lambda (string predicate action)
    (cond
     ((eq action 'metadata) '(metadata (category . emmet2)))
     ((and (null action) (equal string abbreviation)
           (test-completion string (list abbreviation) predicate)) string)
     (t (complete-with-action action (list abbreviation) string predicate)))))

(ert-deftest emmet2-contract-table-is-original-text ()
  (let ((table (emmet2-test--table "ul>li*3")))
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
      (let ((result (completion-try-completion
                     "ul>li*3" (emmet2-test--table "ul>li*3") nil 7)))
        (if (eq expected 'cons)
            (should (equal result '("ul>li*3" . 7)))
          (should (eq result t)))))))

(defun emmet2-test--completion-session (styles overrides exact automatic
                                            &optional abbreviation prefix accept)
  "Probe real completion control flow, replacing only UI drawing.
STYLES, OVERRIDES, EXACT and AUTOMATIC select the configuration.
ABBREVIATION defaults to ul>li*3.  PREFIX is the user's auto threshold.
ACCEPT accepts the selected candidate; otherwise the probe cancels it."
  (with-temp-buffer
    (let* ((input (or abbreviation "ul>li*3"))
           (table (emmet2-test--table input))
           (completion-styles styles)
           (completion-category-defaults nil)
           (completion-category-overrides overrides)
           (completion-cycle-threshold nil)
           (completion-in-region-function #'corfu--in-region-1)
           (corfu-on-exact-match exact)
           (corfu-auto-prefix (or prefix 3))
           (corfu-auto-trigger nil)
           (corfu-preview-current nil)
           (corfu-preselect 'valid)
           (last-command-event ?x)
           shown status selected
           (completion-at-point-functions
            (list (lambda ()
                    (list (point-min) (point-max) table :exclusive 'no
                          :exit-function (lambda (candidate result)
                                           (should (equal candidate input))
                                           (setq status result)))))))
      (insert input)
      (cl-letf (((symbol-function 'corfu--candidates-popup)
                 (lambda (&rest _) (setq shown t)))
                ((symbol-function 'corfu--popup-hide) #'ignore)
                ;; Surface internal errors as ERT failures instead of debug UI.
                ((symbol-function 'corfu--protect) #'funcall))
        (unwind-protect
            (progn
              (if automatic
                  (corfu-auto--complete-deferred)
                (completion-at-point)
                (when completion-in-region-mode (corfu--exhibit)))
              (setq selected corfu--index)
              (when (and accept completion-in-region-mode) (corfu-insert))
              (when completion-in-region-mode (corfu-quit))
              (should (equal (buffer-string) input))
              (list shown status selected))
          (when completion-in-region-mode (corfu-quit)))))))

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
