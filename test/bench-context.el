;;; bench-context.el --- Reproducible complete context benchmark -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Run with the locked bootstrap, e.g.:
;; EMMET2_BENCH_OUTPUT=/tmp/context-31-1.json emacs --batch -Q -L . \
;;   -l test/bootstrap.el -l test/bench-context.el
;; Repeat in three fresh processes.  Optional EMMET2_BENCH_FILTER selects names
;; for diagnosis only; acceptance requires every fixture.  Normal GC is retained.

(require 'cl-lib)
(require 'bytecomp)
(require 'json)
(require 'web-mode)
(require 'typescript-ts-mode)
(declare-function emmet2-context-analyze "emmet2-context")
(defvar emmet2-test-root)
(defvar emmet2-mode)
(defvar emmet2-bench--sources)

(defun emmet2-bench--source-hashes ()
  "Identify the exact measured source and harness."
  (vconcat
   (mapcar
    (lambda (name)
      (list :file name :sha256
            (with-temp-buffer
              (insert-file-contents-literally (expand-file-name name emmet2-test-root))
              (secure-hash 'sha256 (current-buffer)))))
    '("emmet2-context.el" "emmet2-extract.el" "emmet2-engine.el"
      "test/bootstrap.el" "test/bench-context.el"))))

(defun emmet2-bench--command (program &rest args)
  "Capture successful PROGRAM output with ARGS."
  (with-temp-buffer
    (unless (zerop (apply #'call-process program nil t nil args))
      (error "Failed benchmark metadata command: %s" program))
    (string-trim (buffer-string))))

(defun emmet2-bench--fixture (kind statement-lines file-lines)
  "Insert KIND with STATEMENT-LINES and FILE-LINES; return its specification."
  (let ((tsx (memq kind '(tsx-markup tsx-style tsx-negative))) part-bytes)
    (if tsx
        (progn
          (dotimes (i (- file-lines statement-lines))
            (insert (format "const padding%d = %d;\n" i i)))
          (insert "const A = (\n  <main>\n")
          (dotimes (i (- statement-lines 6))
            (insert (format "    <div>{items[%d]}</div>\n" i)))
          (insert (pcase kind
                    ('tsx-style "    <section style={{m10│}} />\n")
                    ('tsx-negative "    <section>{items.ma│}</section>\n")
                    (_ "    <section>ul>li*3│</section>\n")))
          (insert "\n  </main>\n);\n"))
      (dotimes (i (if (eq kind 'web-large-style) 0 (- file-lines 1)))
        (insert (if (eq kind 'css)
                    (format ".b%d { margin: 0; }\n" i)
                  (format "<p>row %d</p>\n" i))))
      (insert
       (pcase kind
         ('css ".last{m10│}\n")
         ('web-markup "<main>ul>li*3│</main>\n")
         ('web-css "<style>.last{m10│}</style>\n")
         ('web-large-style
          (let* ((target (* 135 1024))
                 (line ".b { padding: 12px 24px; margin: 0 auto; content: \"x\"; /* c */ }\n")
                 (ending ".last{\n  m10│\n}\n")
                 (count (/ (- target (1- (length ending)) 5) (length line)))
                 (body (apply #'concat (make-list count line)))
                 (padding (- target (length body) (1- (length ending)) 5)))
            (setq part-bytes target)
            (concat "<style>" body "/*" (make-string padding ?x) "*/\n" ending "</style>\n"))))))
    (goto-char (point-min)) (search-forward "│") (delete-char -1)
    (let ((position (point))
          (mode (cond (tsx 'tsx-ts-mode) ((eq kind 'css) 'css-mode) (t 'web-mode)))
          (source (buffer-string)) (t0 (current-time)))
      (setq buffer-file-name (if tsx "/tmp/emmet2-benchmark.tsx" "/tmp/emmet2-benchmark.html"))
      (funcall mode)
      (setq-local emmet2-mode t)
      (goto-char position)
      (list :mode mode :mode-init-ms (* 1000 (float-time (time-subtract (current-time) t0)))
            :kind kind :statement-lines statement-lines
            :lines (count-lines (point-min) (point-max)) :bytes (string-bytes source)
            :sha256 (secure-hash 'sha256 source) :part-bytes part-bytes
            :expected-lang (pcase kind ('tsx-style 'css-in-js) ('tsx-negative nil)
                                  ((or 'css 'web-css 'web-large-style) 'css) (_ 'markup))
            :abbr (pcase kind ('tsx-negative nil) ((or 'tsx-markup 'web-markup) "ul>li*3") (_ "m10"))))))

(defun emmet2-bench--verify (result spec &optional changed)
  "Assert RESULT matches SPEC; CHANGED has one digit appended to the token."
  (unless (and (eq (plist-get result :lang) (plist-get spec :expected-lang))
               (equal (plist-get result :abbr)
                      (when-let* ((abbr (plist-get spec :abbr)))
                        (if changed (concat abbr "1") abbr))))
    (error "Wrong benchmark result: %S expected %S changed %S" result spec changed)))

(defun emmet2-bench--samples (spec edit)
  "Measure SPEC for 100 warmups and 1000 operations.
EDIT is nil, `typing', or `programmatic'; both edit paths include change hooks."
  (let ((samples (make-vector 1000 nil)) (initial-gcs gcs-done)
        (initial-gc-time gc-elapsed) measurement-gcs measurement-gc-time)
    (dotimes (i 1100)
      (when (= i 100) (setq measurement-gcs gcs-done measurement-gc-time gc-elapsed))
      (let ((t0 (current-time)) (gcs gcs-done) (gc-time gc-elapsed)
            (changed (and edit (zerop (% i 2)))) result)
        (when edit
          (if changed
              (if (eq edit 'typing)
                  (let ((last-command-event ?1)) (self-insert-command 1))
                (insert "1"))
            (delete-char -1)))
        (setq result (emmet2-context-analyze t))
        (when (>= i 100)
          (aset samples (- i 100)
                (vector (* 1000 (float-time (time-subtract (current-time) t0)))
                        (- gcs-done gcs) (- gc-elapsed gc-time))))
        (emmet2-bench--verify result spec changed)))
    (let ((sorted (sort (mapcar (lambda (entry) (aref entry 0)) samples) #'<)))
      (list :path (pcase edit ('typing "typing-and-analyze")
                                ('programmatic "programmatic-edit-and-analyze") (_ "analyze"))
            :warmups 100 :count 1000
            :p50-ms (nth 499 sorted) :p99-ms (nth 989 sorted) :max-ms (car (last sorted))
            :gc-count (- gcs-done measurement-gcs) :gc-seconds (- gc-elapsed measurement-gc-time)
            :warmup-gc-count (- measurement-gcs initial-gcs)
            :warmup-gc-seconds (- measurement-gc-time initial-gc-time)
            :sample-columns ["milliseconds" "gc-count" "gc-seconds"] :samples samples))))

(defun emmet2-bench--run (name kind statement-lines file-lines)
  "Measure one NAME fixture of KIND with STATEMENT-LINES and FILE-LINES."
  (with-temp-buffer
    (let* ((spec (emmet2-bench--fixture kind statement-lines file-lines))
           (gcs gcs-done) (gc-time gc-elapsed) (t0 (current-time))
           (result (emmet2-context-analyze))
           (cold-ms (* 1000 (float-time (time-subtract (current-time) t0))))
           (cold-gcs (- gcs-done gcs)) (cold-gc-time (- gc-elapsed gc-time)))
      (emmet2-bench--verify result spec)
      (let* ((read (emmet2-bench--samples spec nil))
             (typing (emmet2-bench--samples spec 'typing))
             (edit (emmet2-bench--samples spec 'programmatic)))
        (message "%s read p99 %.3f ms; typing %.3f ms; programmatic %.3f ms; cold %.3f ms"
                 name (plist-get read :p99-ms) (plist-get typing :p99-ms)
                 (plist-get edit :p99-ms) cold-ms)
        (list :name name :fixture spec :cold-ms cold-ms :cold-gc-count cold-gcs
              :cold-gc-seconds cold-gc-time :paths (vector read typing edit))))))

(defun emmet2-bench-context ()
  "Run the S3 matrix and write raw samples to EMMET2_BENCH_OUTPUT."
  (let ((output (or (getenv "EMMET2_BENCH_OUTPUT") (error "Set EMMET2_BENCH_OUTPUT")))
        (filter (getenv "EMMET2_BENCH_FILTER")) cases)
    (when (file-exists-p output) (error "Refusing to overwrite %s" output))
    (cl-labels ((run (name kind statement-lines file-lines)
                  (when (or (not filter) (string-match-p filter name))
                    (push (emmet2-bench--run name kind statement-lines file-lines) cases))))
      (dolist (dimensions '((56 500) (56 5000) (56 20000) (306 5000) (1006 5000)))
        (dolist (kind '(tsx-markup tsx-style tsx-negative))
          (run (format "%s-%s-%s" kind (car dimensions) (cadr dimensions))
               kind (car dimensions) (cadr dimensions))))
      (dolist (size '(500 20000))
        (dolist (kind '(css web-css web-markup))
          (run (format "%s-%d" kind size) kind 0 size)))
      (run "web-large-style-135kb" 'web-large-style 0 0))
    (unless cases (error "Benchmark filter matched no fixtures"))
    (unless (equal emmet2-bench--sources (emmet2-bench--source-hashes))
      (error "Measured sources changed during the benchmark; refusing mixed evidence"))
    (with-temp-file output
      (insert (json-encode
               (list :revision (emmet2-bench--command "git" "rev-parse" "HEAD")
                     :dirty (emmet2-bench--command "git" "status" "--short")
                     :dependency-lock-sha256
                     (with-temp-buffer
                       (insert-file-contents-literally (expand-file-name "test/dependencies.json" emmet2-test-root))
                       (secure-hash 'sha256 (current-buffer)))
                     :source-sha256 emmet2-bench--sources
                     :emacs emacs-version :configuration system-configuration
                     :configure-options system-configuration-options
                     :system (emmet2-bench--command "uname" "-srm")
                     :cpu (if (eq system-type 'darwin)
                              (emmet2-bench--command "sysctl" "-n" "machdep.cpu.brand_string")
                            (emmet2-bench--command "uname" "-m"))
                     :backend "context only; no expansion backend or rendering"
                     :web-mode-compilation (if (byte-code-function-p (symbol-function 'web-mode-scan))
                                               "bytecode" "source")
                     :compilation "bytecode" :filter filter
                     :gc-cons-threshold gc-cons-threshold :gc-cons-percentage gc-cons-percentage
                     :cases (vconcat (nreverse cases)))))
      (insert "\n"))))

;; Compile only the measured production path into an owned temporary directory.
;; Load dependencies in order so no source definition remains on the hot path.
(let* ((emmet2-bench--sources (emmet2-bench--source-hashes))
       (directory (make-temp-file "emmet2-context-bytecode-" t))
       (byte-compile-error-on-warn t)
       (byte-compile-dest-file-function
        (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") directory))))
  (unwind-protect
      (progn
        (dolist (name '("emmet2-engine.el" "emmet2-extract.el" "emmet2-context.el"))
          (unless (byte-compile-file (expand-file-name name emmet2-test-root))
            (error "Failed to byte compile %s" name))
          (load (expand-file-name (concat name "c") directory) nil t))
        (unless (byte-code-function-p (symbol-function 'emmet2-context-analyze))
          (error "Context is not byte compiled"))
        (emmet2-bench-context))
    (delete-directory directory t)))

;;; bench-context.el ends here
