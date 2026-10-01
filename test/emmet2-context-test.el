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

(ert-deftest emmet2-context-revision-covers-analysis-inputs ()
  (dolist (change (list (lambda () (insert "x")) (lambda () (backward-char))
                        (lambda () (narrow-to-region (1+ (point-min)) (point-max)))
                        (lambda () (setq-local web-mode-engine "php"))
                        (lambda () (setq-local web-mode-content-type "css"))
                        (lambda () (setq-local emmet2-mode t)) (lambda () (css-mode))))
    (with-temp-buffer
      (insert "<style>.a{m10}</style>") (web-mode) (search-backward "}</style>")
      (let ((revision (emmet2-context-revision)))
        ;; Rescanning changes text properties only; analysis flushes such scans.
        (web-mode-buffer-scan)
        (should (equal revision (emmet2-context-revision)))
        (funcall change)
        (should-not (equal revision (emmet2-context-revision)))))))

(ert-deftest emmet2-context-cold-auto-and-explicit-initialization ()
  (emmet2-test-with-js-context
    (should-not (emmet2-context-analyze t))
    (should-not (emmet2-context-js--parsers))
    (let* ((owner (emmet2-context-js--owner)) (timer (emmet2-context-js--state-timer owner)))
      (should (timerp timer))
      (emmet2-context-start)
      (should (eq timer (emmet2-context-js--state-timer owner)))
      (should (equal (plist-get (emmet2-context-analyze) :abbr) "ul>li"))
      (should (= (length (emmet2-context-js--parsers)) 2))
      (let ((parsers (emmet2-context-js--parsers)))
        (dotimes (_ 3)
          (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li"))
          (should (equal (emmet2-context-js--parsers) parsers)))))))

(ert-deftest emmet2-context-warmup-stop-and-stale-callback ()
  (emmet2-test-with-js-context
    (let ((mode-parsers (treesit-parser-list)))
      (emmet2-context-start)
      (let* ((owner (emmet2-context-js--owner)) (timer (emmet2-context-js--state-timer owner)))
        (cancel-timer timer)
        (emmet2-context-js--warm (current-buffer) owner)
        (should-not (emmet2-context-js--state-timer owner))
        (should (emmet2-context-analyze t))
        (emmet2-context-start)
        (setq timer (emmet2-context-js--state-timer owner))
        (emmet2-context-stop)
        (should-not (memq timer timer-idle-list))
        (should-not (emmet2-context-js--parsers))
        (should (equal (treesit-parser-list) mode-parsers))
        (emmet2-context-start)
        (let ((replacement (emmet2-context-js--owner)))
          (emmet2-context-js--warm (current-buffer) owner)
          (should (eq (emmet2-context-js--owner) replacement))
          (should-not (emmet2-context-js--parsers)))
        (emmet2-context-stop)
        (emmet2-context-stop)))))

(ert-deftest emmet2-context-disable-major-change-and-kill-cleanup ()
  (emmet2-test-with-js-context
    (emmet2-context-start)
    (let ((owner (emmet2-context-js--owner)))
      (setq-local emmet2-mode nil)
      (cancel-timer (emmet2-context-js--state-timer owner))
      (emmet2-context-js--warm (current-buffer) owner)
      (should-not (emmet2-context-js--parsers)))
    (emmet2-context-analyze)
    (emmet2-context-start)
    (let* ((owner (emmet2-context-js--owner)) (timer (emmet2-context-js--state-timer owner)))
      (fundamental-mode)
      (should-not (memq timer timer-idle-list))
      (should-not emmet2-context-js--state)
      (should-not (treesit-parser-list nil nil (emmet2-context-js--state-tag owner)))))
  (let ((buffer (generate-new-buffer " *emmet2-kill*")) owner timer)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert "const A = () => (<main>ul>li</main>);")
            (tsx-ts-mode) (setq-local emmet2-mode t)
            (emmet2-context-start)
            (setq owner (emmet2-context-js--owner) timer (emmet2-context-js--state-timer owner)))
          (kill-buffer buffer)
          (should-not (memq timer timer-idle-list))
          (emmet2-context-js--warm buffer owner))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emmet2-context-language-inventory-and-view-isolation ()
  (emmet2-test-with-js-context
    (dolist (language '(tsx javascript typescript tsx javascript typescript))
      (emmet2-context-js--parser language t)
      (emmet2-context-js--parser language t t))
    (should (= (length (emmet2-context-js--parsers)) 6))
    (let* ((base (current-buffer)) (owner (emmet2-context-js--owner))
           (parsers (emmet2-context-js--parsers))
           (view (clone-indirect-buffer " *emmet2-view*" nil)))
      (unwind-protect
          (with-current-buffer view
            (should-not (emmet2-context-js--owner))
            (should-not (emmet2-context-js--parsers))
            (emmet2-context-analyze)
            (should (= (length (emmet2-context-js--parsers)) 2))
            (should-not (eq (emmet2-context-js--state-tag (emmet2-context-js--owner))
                            (emmet2-context-js--state-tag owner)))
            (emmet2-context-stop)
            (should (equal (with-current-buffer base (emmet2-context-js--parsers)) parsers)))
        (when (buffer-live-p view) (kill-buffer view))))))

(ert-deftest emmet2-context-missing-grammar-preserves-source ()
  (emmet2-test-with-js-context
    (let ((source (buffer-string)) (position (point)))
      (cl-letf (((symbol-function 'treesit-language-available-p) (lambda (&rest _) nil)))
        (should-not (emmet2-context-analyze t))
        (should-not (emmet2-context-js-prepare))
        (should (equal (cdr (should-error (emmet2-context-analyze) :type 'emmet2-error))
                       '("Missing tree-sitter grammar: tsx"))))
      (should (equal (buffer-string) source))
      (should (= (point) position))
      (should-not (emmet2-context-js--parsers)))))

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
        (emmet2-context-js-prepare)
        (should-not (emmet2-context-analyze t))
        (should-not (emmet2-context-analyze))))))

(ert-deftest emmet2-context-incremental-source-and-web-part-switches ()
  (emmet2-test-with-js-context
    (emmet2-context-js-prepare)
    (let ((parser (car (emmet2-context-js--parsers))))
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li"))
      (insert "*3")
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li*3"))
      (delete-char -2)
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li"))
      (should (eq parser (car (emmet2-context-js--parsers))))))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/emmet2-context.html")
    (insert "<script>const a = createTheme({x: {m10}});</script>\n<p>outside</p>\n<script>const b = StyleSheet.create({x: {p10}});</script>")
    (web-mode)
    (goto-char (point-min)) (search-forward "m10")
    (emmet2-context-js-prepare)
    (let ((parser (car (emmet2-context-js--parsers))))
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "m10"))
      (search-forward "p10")
      (should-not (emmet2-context-analyze t))
      (emmet2-context-js-prepare)
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "p10"))
      (should (eq parser (car (emmet2-context-js--parsers)))))))

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
            (emmet2-context-js-prepare) (emmet2-context-start)
            (push (emmet2-context-js--state-timer (emmet2-context-js--owner)) timers)
            (setq view (clone-indirect-buffer " *emmet2-kill-view*" nil)))
          (with-current-buffer view
            (emmet2-context-js-prepare) (emmet2-context-start)
            (push (emmet2-context-js--state-timer (emmet2-context-js--owner)) timers))
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

(ert-deftest emmet2-context-source-and-projection-stay-independent ()
  (emmet2-test-with-js-context
    (emmet2-context-js-prepare)
    (let ((source (emmet2-context-js--parser 'tsx nil))
          (projection (emmet2-context-js--parser 'tsx nil t)))
      (should-not (eq source projection))
      (emmet2-context-analyze t)
      (should (= (length (treesit-parser-included-ranges source)) 1))
      (should (= (length (treesit-parser-included-ranges projection)) 3))
      (should (equal (treesit-node-text (treesit-parser-root-node source) t)
                     (buffer-string)))
      (insert "*3")
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li*3"))
      (should (eq source (emmet2-context-js--parser 'tsx nil)))
      (should (eq projection (emmet2-context-js--parser 'tsx nil t))))))

(defmacro emmet2-test-with-bounded-unit (&rest body)
  "Run BODY at a JSX abbreviation between unrelated declarations."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (insert "const before = 1;\nconst A = (<main>ul>li*3</main>);\nconst after = 2;\n")
     (tsx-ts-mode) (setq-local emmet2-mode t)
     (goto-char (point-min)) (search-forward "ul>li*3")
     (should (emmet2-context-analyze))
     ,@body))

(ert-deftest emmet2-context-unit-is-local-through-abbreviation-errors ()
  (emmet2-test-with-bounded-unit
    (let* ((owner (emmet2-context-js--owner))
           (unit (assq 'tsx (emmet2-context-js--state-units owner))))
      (should (> (marker-position (cadr unit)) (point-min)))
      (should (< (marker-position (caddr unit)) (point-max)))
      (should (treesit-node-check
               (treesit-parser-root-node (emmet2-context-js--parser 'tsx nil)) 'has-error))
      (insert "1")
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li*31"))
      (should (eq unit (assq 'tsx (emmet2-context-js--state-units owner))))
      (emmet2-context-stop)
      (should-not (marker-buffer (cadr unit)))
      (should-not (marker-buffer (caddr unit)))
      (should-not (memq #'emmet2-context-js--before-change before-change-functions))
      (should-not (memq #'emmet2-context-js--after-change after-change-functions)))))

(ert-deftest emmet2-context-unit-is-local-for-exported-and-semicolon-free-statements ()
  (dolist (statement '("export const styles = StyleSheet.create({x: {m10}});"
                       "export function f() { StyleSheet.create({x: {m10}}); }"
                       "StyleSheet.create({x: {m10}});"
                       "const styles = StyleSheet.create({x: {m10}})"
                       "export const styles = StyleSheet.create({x: {m10}})"))
    (ert-info (statement)
      (with-temp-buffer
        (insert "const before = 1\n" statement "\nconst after = 2\n")
        (tsx-ts-mode)
        (goto-char (point-min)) (search-forward "m10")
        (should (eq (plist-get (emmet2-context-analyze) :lang) 'css-in-js))
        (let ((unit (assq 'tsx (emmet2-context-js--state-units (emmet2-context-js--owner)))))
          (should (equal (buffer-substring-no-properties (cadr unit) (caddr unit)) statement))
          (insert "1")
          (should (equal (plist-get (emmet2-context-analyze t) :abbr) "m101"))
          (should (eq unit (assq 'tsx (emmet2-context-js--state-units (emmet2-context-js--owner))))))))))

(ert-deftest emmet2-context-unit-boundary-and-outside-edits-invalidate ()
  (dolist (where '(start end outside))
    (emmet2-test-with-bounded-unit
      (let* ((owner (emmet2-context-js--owner))
             (unit (assq 'tsx (emmet2-context-js--state-units owner)))
             (position (copy-marker (point))))
        (goto-char (pcase where ('start (cadr unit)) ('end (caddr unit)) (_ (point-min))))
        (insert (if (eq where 'outside) "/*" " "))
        (when (eq where 'outside) (save-excursion (goto-char (point-max)) (insert "*/")))
        (goto-char position) (set-marker position nil)
        (should-not (marker-buffer (cadr unit)))
        (should-not (emmet2-context-analyze t))
        (if (eq where 'outside)
            (should-not (emmet2-context-analyze))
          (should (emmet2-context-analyze)))))))

(ert-deftest emmet2-context-unit-unobserved-edits-invalidate ()
  (dolist (path '(inhibited indirect))
    (emmet2-test-with-bounded-unit
      (let ((unit (assq 'tsx (emmet2-context-js--state-units (emmet2-context-js--owner)))))
        (if (eq path 'inhibited)
            (let ((inhibit-modification-hooks t))
              (save-excursion (goto-char (point-min)) (insert "/*") (goto-char (point-max)) (insert "*/")))
          (let ((view (clone-indirect-buffer " *emmet2-unit-view*" nil)))
            (unwind-protect
                (with-current-buffer view (goto-char (point-min)) (insert "/*") (goto-char (point-max)) (insert "*/"))
              (kill-buffer view))))
        (should-not (emmet2-context-analyze t))
        (should-not (marker-buffer (cadr unit)))
        (should-not (emmet2-context-analyze))))))

(ert-deftest emmet2-context-unit-damaged-structure-matches-full-host ()
  (dolist (damage '("/*" "`" "'" "<!--" "{" "//"))
    (emmet2-test-with-bounded-unit
      (save-excursion
        (goto-char (point-min)) (search-forward "(<main>")
        (backward-char (length "<main>")) (insert damage))
      (let ((incremental (emmet2-context-analyze)))
        (emmet2-context-stop)
        (should (equal incremental (emmet2-context-analyze)))))))

(ert-deftest emmet2-context-unit-switch-requires-new-evidence ()
  (emmet2-test-with-bounded-unit
    (let ((old (assq 'tsx (emmet2-context-js--state-units (emmet2-context-js--owner)))))
      (goto-char (point-max)) (search-backward "after")
      (should-not (emmet2-context-analyze t))
      (should-not (marker-buffer (cadr old)))
      (emmet2-context-js-prepare)
      (should-not (emmet2-context-analyze t))
      (should (= (length (emmet2-context-js--state-units (emmet2-context-js--owner))) 1)))))

(ert-deftest emmet2-context-unit-unrelated-errors-preserve-valid-position ()
  (with-temp-buffer
    (insert "const before = 1;\nconst A = (<main><p bad={foo+}/><section>ul>li*3</section></main>);\n")
    (tsx-ts-mode)
    (goto-char (point-min)) (search-forward "ul>li*3")
    (should (equal (plist-get (emmet2-context-analyze) :abbr) "ul>li*3"))
    (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li*3"))
    (insert "1")
    (should (equal (plist-get (emmet2-context-analyze t) :abbr) "ul>li*31"))))

(ert-deftest emmet2-context-open-comment-cannot-recover-as-jsx ()
  (dolist (mode '(tsx-ts-mode web-mode))
    (with-temp-buffer
      (insert "/* const before = 1;\nconst A = (<main>ul>li*3</main>);\nconst after = 2;")
      (setq buffer-file-name "/tmp/emmet2-comment.tsx")
      (funcall mode)
      (goto-char (point-min)) (search-forward "ul>li*3")
      (emmet2-context-js-prepare)
      (should-not (emmet2-context-analyze t))
      (should-not (emmet2-context-analyze))))
  (emmet2-test-with-bounded-unit
    (save-excursion (goto-char (point-min)) (insert "/*"))
    (should-not (emmet2-context-analyze t))
    (should-not (emmet2-context-analyze))))

(ert-deftest emmet2-context-unit-interior-owner-and-host-edits-recheck ()
  (with-temp-buffer
    (insert "const before = 1;\nconst A = (<section style={{m10}}/>);\nconst after = 2;")
    (tsx-ts-mode)
    (goto-char (point-min)) (search-forward "m10")
    (should (eq (plist-get (emmet2-context-analyze) :lang) 'css-in-js))
    (let ((unit (assq 'tsx (emmet2-context-js--state-units (emmet2-context-js--owner)))))
      (should (equal (buffer-substring-no-properties (cadr unit) (caddr unit))
                     "<section style={{m10}}/>"))
      (save-excursion (search-backward "style") (delete-char 5) (insert "title"))
      (should-not (emmet2-context-analyze t))
      (should (marker-buffer (cadr unit)))
      (save-excursion (search-backward "title") (delete-char 5) (insert "style"))
      (should (eq (plist-get (emmet2-context-analyze t) :lang) 'css-in-js))))
  (emmet2-test-with-bounded-unit
    (save-excursion (search-backward "ul>li*3") (insert "{"))
    (should-not (emmet2-context-analyze t))
    (should-not (emmet2-context-analyze))
    (save-excursion (search-backward "{ul>li*3") (delete-char 1))
    (should (equal (plist-get (emmet2-context-analyze) :abbr) "ul>li*3"))))

(provide 'emmet2-context-test)
;;; emmet2-context-test.el ends here
