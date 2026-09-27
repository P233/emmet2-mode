;;; emmet2-engine-node-test.el --- Real process protocol contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-engine-node)
(require 'emmet2-lorem-contract)
(require 'emmet2-core-contract)

(ert-deftest emmet2-node-lorem-structural-contract ()
  (emmet2-node-stop)
  (unwind-protect (emmet2-lorem-test--run #'emmet2-engine-expand)
    (emmet2-node-stop)))

(defmacro emmet2-test--with-node-fixture (&rest body)
  "Execute BODY with the fault fixture and no preexisting process."
  (declare (indent 0) (debug t))
  `(progn
     (emmet2-node-stop)
     (let ((emmet2-node--server-file (expand-file-name "test/node-fixture.mjs" emmet2-test-root)))
       (unwind-protect (progn ,@body) (emmet2-node-stop)))))

(ert-deftest emmet2-node-core-oracle ()
  (emmet2-node-stop)
  (unwind-protect (emmet2-core-test--check #'emmet2-engine-expand)
    (emmet2-node-stop)))

(ert-deftest emmet2-node-handwritten-fields-and-permissive-input ()
  (emmet2-node-stop)
  (unwind-protect
      (progn
        (should (equal (emmet2-engine-expand "c+bg" :preset 'stylesheet)
                       '(:text "color: #000;\nbackground: #000;"
                               :fields ((7 11 1 "#000") (25 29 2 "#000")) :cursor 7)))
        (should (equal (plist-get (emmet2-engine-expand "div{😀}") :text) "<div>😀</div>"))
        (should (equal (emmet2-engine-expand "p${9007199254740992:x}-${9007199254740993:x}" :preset 'stylesheet)
                       '(:text "padding: x x;" :fields ((9 10 1 "x") (11 12 1 "x")) :cursor 9)))
        (should (stringp (plist-get (emmet2-engine-expand "a{") :text)))
        (should (stringp (plist-get (emmet2-engine-expand "ul>") :text)))
        (should-error (emmet2-engine-expand "tn[all 0.3s]" :preset 'stylesheet) :type 'emmet2-parse-error)
        ;; The pinned CSS parser cannot attach a position after consuming a
        ;; delimiter-only input; preserve backend-error instead of inventing one.
        (dolist (input '(":" "-" "," ":-" "+:"))
          (should (equal (should-error (emmet2-engine-expand input :preset 'stylesheet) :type 'emmet2-backend-error)
                         '(emmet2-backend-error "Unexpected token"))))
        (should (equal (emmet2-engine-expand ":+" :preset 'stylesheet) '(:text "" :fields nil :cursor 0))))
    (emmet2-node-stop)))

(ert-deftest emmet2-node-real-token-parser-errors-reuse-process ()
  (emmet2-node-stop)
  (unwind-protect
      (progn
        (emmet2-engine-expand "div")
        (let ((process emmet2-node--process))
          (dolist (case '(("div{😀})" "Unexpected character" 6)
                          ("div.\\😀" "Unexpected character" 5)
                          ("div[title=\"x]" "Unclosed quote" 10)
                          ("div[=x]" "Unexpected \"Operator\" token" 4)))
            (should (equal (cdr (should-error (emmet2-engine-expand (car case)) :type 'emmet2-parse-error))
                           (cdr case)))
            (should (eq process emmet2-node--process)))
          (should (equal (plist-get (emmet2-engine-expand "p{after}") :text) "<p>after</p>"))
          (should (eq process emmet2-node--process))))
    (emmet2-node-stop)))

(ert-deftest emmet2-node-fragmented-utf8-and-parse-error-reuse ()
  (emmet2-test--with-node-fixture
    (should (equal (emmet2-engine-expand "SPLIT")
                   '(:text "😀\ue000" :fields ((1 2 1 "\ue000")) :cursor 1)))
    (let ((process emmet2-node--process))
      (should (equal (cdr (should-error (emmet2-engine-expand "PARSE_ERROR") :type 'emmet2-parse-error))
                     '("100% literal %s" 2)))
      (should (eq process emmet2-node--process))
      (should (equal (plist-get (emmet2-engine-expand "SECOND") :text) "SECOND"))
      (should (equal (cdr (should-error (emmet2-engine-expand "BACKEND_ERROR") :type 'emmet2-backend-error))
                     '("100% literal %s")))
      (should-not emmet2-node--process))))

(ert-deftest emmet2-node-failures-dispose-before-next-request ()
  (dolist (abbreviation '("FIRST" "PARTIAL" "INVALID" "WRONG_ID" "BAD_FIELDS"
                          "NULL_FIELDS" "MISSING_FIELDS" "BOTH" "BAD_CURSOR" "BACKEND_ERROR" "EXIT"))
    (ert-info (abbreviation)
      (emmet2-test--with-node-fixture
        (let ((emmet2-engine--timeout 0.2))
          (should-error (emmet2-engine-expand abbreviation) :type 'emmet2-backend-error))
        (should-not emmet2-node--process)
        (should-not (cl-find-if (lambda (buffer) (string-prefix-p " *emmet2-node-stderr" (buffer-name buffer)))
                               (buffer-list)))
        (should (equal (plist-get (emmet2-engine-expand "SECOND") :text) "SECOND"))))))

(ert-deftest emmet2-node-nonlocal-exit-and-quit-dispose ()
  (dolist (kind '(no-input quit))
    (emmet2-test--with-node-fixture
      (let (process cancelled)
        (cl-letf (((symbol-function 'accept-process-output)
                   (lambda (&rest _)
                     (setq process emmet2-node--process)
                     (if (eq kind 'quit) (signal 'quit nil) (throw 'no-input 'cancelled)))))
          (if (eq kind 'quit)
              (condition-case nil (emmet2-engine-expand "FIRST") (quit (setq cancelled t)))
            (setq cancelled (eq (catch 'no-input (emmet2-engine-expand "FIRST")) 'cancelled))))
        (should cancelled)
        (should process)
        (should-not (process-live-p process))
        (should-not emmet2-node--process)
        (should (equal (plist-get (emmet2-engine-expand "SECOND") :text) "SECOND"))))))

(ert-deftest emmet2-node-one-deadline-covers-multiple-calls ()
  (emmet2-test--with-node-fixture
    (emmet2-engine-expand "READY")
    (let ((emmet2-engine--timeout 0.35) first-completed)
      (should-error
       (emmet2-engine-with-expansion
         (emmet2-engine-expand "SLOW")
         (setq first-completed t)
         (emmet2-engine-expand "SLOW"))
       :type 'emmet2-backend-error)
      (should first-completed)
      (should-not emmet2-node--process)
      (should (equal (plist-get (emmet2-engine-expand "SECOND") :text) "SECOND")))))

(ert-deftest emmet2-node-deadline-includes-startup ()
  (emmet2-test--with-node-fixture
    (let ((original (symbol-function 'make-process))
          (emmet2-engine--timeout 0.02) process)
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest arguments)
                   (setq process (apply original arguments))
                   (sleep-for 0.04)
                   process)))
        (should-error (emmet2-engine-expand "FIRST") :type 'emmet2-backend-error))
      (should process)
      (should-not (process-live-p process))
      (should-not emmet2-node--process))))

(ert-deftest emmet2-node-cross-buffer-and-reentrant-call ()
  (emmet2-test--with-node-fixture
    (with-temp-buffer (should (equal (plist-get (emmet2-engine-expand "ONE") :text) "ONE")))
    (let ((process emmet2-node--process) (original (symbol-function 'accept-process-output)) attempted)
      (cl-letf (((symbol-function 'accept-process-output)
                 (lambda (&rest arguments)
                   (unless attempted
                     (setq attempted t)
                     (with-temp-buffer
                       (should-error (emmet2-engine-expand "NESTED") :type 'emmet2-backend-error)))
                   (apply original arguments))))
        (with-temp-buffer (should (equal (plist-get (emmet2-engine-expand "SLOW") :text) "SLOW"))))
      (should attempted)
      (should (eq process emmet2-node--process)))))

(ert-deftest emmet2-node-idle-death ()
  (emmet2-test--with-node-fixture
    (emmet2-engine-expand "ONE")
    (let ((process emmet2-node--process))
      (delete-process process)
      (should (equal (plist-get (emmet2-engine-expand "TWO") :text) "TWO"))
      (should-not (eq process emmet2-node--process)))))

(ert-deftest emmet2-node-feature-unload-reload ()
  (emmet2-node-stop)
  (unwind-protect
      (progn
        (emmet2-engine-expand "div")
        (let ((process emmet2-node--process) (stderr (process-get emmet2-node--process 'emmet2-stderr)))
          (unload-feature 'emmet2-engine-node t)
          (should-not (process-live-p process))
          (should-not (buffer-live-p stderr)))
        (should (equal (plist-get (emmet2-engine-expand "span") :text) "<span></span>")))
    (require 'emmet2-engine-node)
    (emmet2-node-stop)))

(ert-deftest emmet2-node-stale-filter-cannot-touch-replacement ()
  (emmet2-test--with-node-fixture
    (emmet2-engine-expand "READY")
    (let ((process emmet2-node--process) (emmet2-engine--timeout 0.1))
      (should-error (emmet2-engine-expand "FIRST") :type 'emmet2-backend-error)
      (should-not (process-live-p process))
      (should (equal (plist-get (emmet2-engine-expand "SECOND") :text) "SECOND"))
      (let ((replacement emmet2-node--process))
        (emmet2-node--filter process "old queued output\n")
        (should (eq replacement emmet2-node--process))
        (should (equal (plist-get (emmet2-engine-expand "THIRD") :text) "THIRD"))))))

(ert-deftest emmet2-node-missing-executable-leaves-no-process ()
  (emmet2-test--with-node-fixture
    (let ((exec-path nil))
      (should-error (emmet2-engine-expand "FIRST") :type 'emmet2-backend-error))
    (should-not emmet2-node--process)
    (should-not (cl-find-if (lambda (process)
                             (and (process-live-p process)
                                  (string-prefix-p "emmet2-node" (process-name process))))
                           (process-list)))
    (should-not (cl-find-if (lambda (buffer) (string-prefix-p " *emmet2-node-stderr" (buffer-name buffer)))
                           (buffer-list)))))

(provide 'emmet2-engine-node-test)
;;; emmet2-engine-node-test.el ends here
