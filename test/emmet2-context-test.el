;;; emmet2-context-test.el --- Context ownership contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-context)
(require 'web-mode)

(defmacro emmet2-test-with-js-context (&rest body)
  "Run BODY in a real TSX mode buffer with the minor-mode enable flag."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (insert "const A = () => (<main>ul>li</main>);")
     (tsx-ts-mode)
     (setq-local emmet2-mode t)
     (goto-char (point-min)) (search-forward "ul>li")
     ,@body))

(ert-deftest emmet2-context-cold-auto-and-explicit-initialization ()
  (emmet2-test-with-js-context
    (should-not (emmet2-context-analyze t))
    (should-not (emmet2-context--parsers))
    (let* ((owner (emmet2-context--owner)) (timer (emmet2-context--state-timer owner)))
      (should (timerp timer))
      (emmet2-context-start)
      (should (eq timer (emmet2-context--state-timer owner)))
      (should (equal (plist-get (emmet2-context-analyze) :abbr) "ul>li"))
      (should (= (length (emmet2-context--parsers)) 1))
      (let ((parser (car (emmet2-context--parsers))))
        (dotimes (_ 3)
          (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li"))
          (should (eq (car (emmet2-context--parsers)) parser)))))))

(ert-deftest emmet2-context-warmup-stop-and-stale-callback ()
  (emmet2-test-with-js-context
    (let ((mode-parsers (treesit-parser-list)))
      (emmet2-context-start)
      (let* ((owner (emmet2-context--owner)) (timer (emmet2-context--state-timer owner)))
        (cancel-timer timer)
        (emmet2-context--warm (current-buffer) owner)
        (should-not (emmet2-context--state-timer owner))
        (should (emmet2-context-analyze t))
        (emmet2-context-start)
        (setq timer (emmet2-context--state-timer owner))
        (emmet2-context-stop)
        (should-not (memq timer timer-idle-list))
        (should-not (emmet2-context--parsers))
        (should (equal (treesit-parser-list) mode-parsers))
        (emmet2-context-start)
        (let ((replacement (emmet2-context--owner)))
          (emmet2-context--warm (current-buffer) owner)
          (should (eq (emmet2-context--owner) replacement))
          (should-not (emmet2-context--parsers)))
        (emmet2-context-stop)
        (emmet2-context-stop)))))

(ert-deftest emmet2-context-disable-major-change-and-kill-cleanup ()
  (emmet2-test-with-js-context
    (emmet2-context-start)
    (let ((owner (emmet2-context--owner)))
      (setq-local emmet2-mode nil)
      (cancel-timer (emmet2-context--state-timer owner))
      (emmet2-context--warm (current-buffer) owner)
      (should-not (emmet2-context--parsers)))
    (emmet2-context-analyze)
    (emmet2-context-start)
    (let* ((owner (emmet2-context--owner)) (timer (emmet2-context--state-timer owner)))
      (fundamental-mode)
      (should-not (memq timer timer-idle-list))
      (should-not emmet2-context--state)
      (should-not (treesit-parser-list nil nil (emmet2-context--state-tag owner)))))
  (let ((buffer (generate-new-buffer " *emmet2-kill*")) owner timer)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert "const A = () => (<main>ul>li</main>);")
            (tsx-ts-mode) (setq-local emmet2-mode t)
            (emmet2-context-start)
            (setq owner (emmet2-context--owner) timer (emmet2-context--state-timer owner)))
          (kill-buffer buffer)
          (should-not (memq timer timer-idle-list))
          (emmet2-context--warm buffer owner))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emmet2-context-language-inventory-and-view-isolation ()
  (emmet2-test-with-js-context
    (dolist (language '(tsx javascript typescript tsx javascript typescript))
      (emmet2-context--parser language t))
    (should (= (length (emmet2-context--parsers)) 3))
    (let* ((base (current-buffer)) (owner (emmet2-context--owner))
           (parsers (emmet2-context--parsers))
           (view (clone-indirect-buffer " *emmet2-view*" nil)))
      (unwind-protect
          (with-current-buffer view
            (should-not (emmet2-context--owner))
            (should-not (emmet2-context--parsers))
            (emmet2-context-analyze)
            (should (= (length (emmet2-context--parsers)) 1))
            (should-not (eq (emmet2-context--state-tag (emmet2-context--owner))
                            (emmet2-context--state-tag owner)))
            (emmet2-context-stop)
            (should (equal (with-current-buffer base (emmet2-context--parsers)) parsers)))
        (when (buffer-live-p view) (kill-buffer view))))))

(ert-deftest emmet2-context-missing-grammar-preserves-source ()
  (emmet2-test-with-js-context
    (let ((source (buffer-string)) (position (point)))
      (cl-letf (((symbol-function 'treesit-language-available-p) (lambda (&rest _) nil)))
        (should-not (emmet2-context-analyze t))
        (should-not (emmet2-context--prepare))
        (should (equal (cdr (should-error (emmet2-context-analyze) :type 'emmet2-error))
                       '("Missing tree-sitter grammar: tsx"))))
      (should (equal (buffer-string) source))
      (should (= (point) position))
      (should-not (emmet2-context--parsers)))))

(ert-deftest emmet2-context-original-comments-strings-and-regex-stay-forbidden ()
  (dolist (source '("function A() { return //ul>li│\n}"
                     "const x = createTheme({/*m10│*/});"
                     "function A() { return /ul>li/│; }"
                     "function A() { return `ul>li│`; }"
                     "function A() { return 'ul>li│'; }"))
    (with-temp-buffer
      (insert source) (goto-char (point-min)) (search-forward "│") (delete-char -1)
      (let ((position (point)))
        (tsx-ts-mode) (goto-char position)
        (emmet2-context--prepare)
        (should-not (emmet2-context-analyze t))
        (should-not (emmet2-context-analyze))))))

(ert-deftest emmet2-context-incremental-source-and-web-part-switches ()
  (emmet2-test-with-js-context
    (emmet2-context--prepare)
    (let ((parser (car (emmet2-context--parsers))))
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li"))
      (insert "*3")
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li*3"))
      (delete-char -2)
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li"))
      (should (eq parser (car (emmet2-context--parsers))))))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/emmet2-context.html")
    (insert "<script>const a = createTheme({x: {m10}});</script>\n<p>outside</p>\n<script>const b = StyleSheet.create({x: {p10}});</script>")
    (web-mode)
    (goto-char (point-min)) (search-forward "m10")
    (emmet2-context--prepare)
    (let ((parser (car (emmet2-context--parsers))))
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "m10"))
      (search-forward "p10")
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "p10"))
      (should (eq parser (car (emmet2-context--parsers)))))))

(ert-deftest emmet2-context-empty-and-narrowed-regions ()
  (with-temp-buffer
    (tsx-ts-mode)
    (should-not (emmet2-context-analyze))
    (should-not (emmet2-context-analyze t)))
  (emmet2-test-with-js-context
    (let ((position (point)))
      (save-restriction
        (narrow-to-region position position)
        (should-not (emmet2-context-analyze)))
      (should (equal (plist-get (emmet2-context-analyze) :abbr) "ul>li"))
      (should (= position (point))))))

(ert-deftest emmet2-context-killing-base-cleans-indirect-resources ()
  (let ((base (generate-new-buffer " *emmet2-base*")) view timers)
    (unwind-protect
        (progn
          (with-current-buffer base
            (insert "const A = () => (<main>ul>li</main>);")
            (tsx-ts-mode) (setq-local emmet2-mode t)
            (emmet2-context--prepare) (emmet2-context-start)
            (push (emmet2-context--state-timer (emmet2-context--owner)) timers)
            (setq view (clone-indirect-buffer " *emmet2-kill-view*" nil)))
          (with-current-buffer view
            (emmet2-context--prepare) (emmet2-context-start)
            (push (emmet2-context--state-timer (emmet2-context--owner)) timers))
          (kill-buffer base)
          (should-not (buffer-live-p view))
          (dolist (timer timers) (should-not (memq timer timer-idle-list))))
      (when (buffer-live-p view) (kill-buffer view))
      (when (buffer-live-p base) (kill-buffer base)))))

(ert-deftest emmet2-context-raw-quotes-retain-css-owner ()
  (with-temp-buffer
    (insert "const A = () => (<main style={{ct['hi 👋']}}/>);")
    (tsx-ts-mode)
    (goto-char (point-min)) (search-forward "hi")
    (let ((result (emmet2-context-analyze)))
      (should (eq (plist-get result :lang) 'css-in-js))
      (should (equal (plist-get result :abbr) "ct['hi 👋']")))))

(provide 'emmet2-context-test)
;;; emmet2-context-test.el ends here
