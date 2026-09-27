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

(cl-defstruct (emmet2-bench--case (:constructor emmet2-bench--case-create))
  buffer report)

(defun emmet2-bench--sample (spec edit changed)
  "Time one complete operation for SPEC, then verify it outside the clock.
EDIT is nil, `typing', or `programmatic'; CHANGED selects insertion or deletion."
  (let ((t0 (current-time)) (gcs gcs-done) (gc-time gc-elapsed) result end-gcs end-gc-time end sample)
    (when edit
      (if changed
          (if (eq edit 'typing)
              (let ((last-command-event ?1)) (self-insert-command 1))
            (insert "1"))
        (delete-char -1)))
    (setq result (emmet2-context-analyze t)
          end-gcs gcs-done end-gc-time gc-elapsed end (current-time)
          sample (vector (* 1000 (float-time (time-subtract end t0)))
                         (- end-gcs gcs) (- end-gc-time gc-time)))
    (emmet2-bench--verify result spec changed)
    sample))

(defun emmet2-bench--summary (samples warmup-gcs warmup-gc-time edit)
  "Summarize SAMPLES for EDIT, with separately accumulated warmup GC deltas."
  (let ((sorted (sort (mapcar (lambda (entry) (aref entry 0)) samples) #'<)))
    (list :path (pcase edit ('typing "typing-and-analyze")
                          ('programmatic "programmatic-edit-and-analyze") (_ "analyze"))
          :warmups 100 :count (length samples)
          :p50-ms (nth (1- (ceiling (* 0.50 (length samples)))) sorted)
          :p99-ms (nth (1- (ceiling (* 0.99 (length samples)))) sorted)
          :max-ms (car (last sorted))
          ;; Only this fixture's timed operations count, not other buffers,
          ;; verification, or storage between interleaved samples.
          :gc-count (cl-loop for sample across samples sum (aref sample 1))
          :gc-seconds (cl-loop for sample across samples sum (aref sample 2))
          :warmup-gc-count warmup-gcs :warmup-gc-seconds warmup-gc-time
          :sample-columns ["milliseconds" "gc-count" "gc-seconds"] :samples samples)))

(defun emmet2-bench--path (cases edit)
  "Interleave EDIT across CASES, rotating the first buffer every round."
  (let* ((count (length cases))
         (samples (vconcat (mapcar (lambda (_) (make-vector 10000 nil)) cases)))
         (warmup-gcs (make-vector count 0)) (warmup-gc-time (make-vector count 0.0))
         (entries (vconcat cases)))
    (dotimes (i 10100)
      (dotimes (j count)
        (let* ((index (% (+ i j) count))
               (entry (aref entries index))
               (spec (plist-get (emmet2-bench--case-report entry) :fixture))
               (sample (with-current-buffer (emmet2-bench--case-buffer entry)
                         (emmet2-bench--sample spec edit (and edit (zerop (% i 2)))))))
          (if (< i 100)
              (progn
                (cl-incf (aref warmup-gcs index) (aref sample 1))
                (cl-incf (aref warmup-gc-time index) (aref sample 2)))
            (aset (aref samples index) (- i 100) sample)))))
    (dotimes (i count)
      (let* ((entry (aref entries i)) (report (emmet2-bench--case-report entry))
             (path (emmet2-bench--summary (aref samples i) (aref warmup-gcs i)
                                         (aref warmup-gc-time i) edit)))
        (setf (emmet2-bench--case-report entry)
              (plist-put report :paths (append (plist-get report :paths) (list path))))))))

(defun emmet2-bench--group (kind dimensions filter)
  "Measure KIND at DIMENSIONS together; FILTER selects diagnostic cases only.
At most five owned buffers survive until this group finishes, even on failure."
  (let (cases)
    (unwind-protect
        (progn
          (dolist (size dimensions)
            (let ((name (if (eq kind 'web-large-style) "web-large-style-135kb"
                          (if (zerop (car size)) (format "%s-%d" kind (cadr size))
                            (format "%s-%d-%d" kind (car size) (cadr size))))))
              (when (or (not filter) (string-match-p filter name))
                (let ((entry (emmet2-bench--case-create :buffer (generate-new-buffer " *emmet2-bench*"))))
                  (push entry cases)
                  (with-current-buffer (emmet2-bench--case-buffer entry)
                    ;; Match the original with-temp-buffer fixture lifecycle.
                    (buffer-disable-undo)
                    (let* ((spec (emmet2-bench--fixture kind (car size) (cadr size)))
                           (gcs gcs-done) (gc-time gc-elapsed) (t0 (current-time))
                           (result (emmet2-context-analyze))
                           (end-gcs gcs-done) (end-gc-time gc-elapsed) (end (current-time))
                           (cold-ms (* 1000 (float-time (time-subtract end t0))))
                           (cold-gcs (- end-gcs gcs)) (cold-gc-time (- end-gc-time gc-time)))
                      (emmet2-bench--verify result spec)
                      (setf (emmet2-bench--case-report entry)
                            (list :name name :fixture spec :cold-ms cold-ms
                                  :cold-gc-count cold-gcs :cold-gc-seconds cold-gc-time))))))))
          (setq cases (nreverse cases))
          (when cases
            (dolist (edit '(nil typing programmatic)) (emmet2-bench--path cases edit)))
          (mapcar (lambda (entry)
                    (let* ((report (emmet2-bench--case-report entry)) (paths (plist-get report :paths)))
                      (message "%s read p99 %.3f ms; typing %.3f ms; programmatic %.3f ms; cold %.3f ms"
                               (plist-get report :name) (plist-get (nth 0 paths) :p99-ms)
                               (plist-get (nth 1 paths) :p99-ms) (plist-get (nth 2 paths) :p99-ms)
                               (plist-get report :cold-ms))
                      (plist-put report :paths (vconcat paths)))) cases))
      (dolist (entry cases) (kill-buffer (emmet2-bench--case-buffer entry))))))

(defun emmet2-bench-context ()
  "Run the S3 matrix and write raw samples to EMMET2_BENCH_OUTPUT."
  (let ((output (or (getenv "EMMET2_BENCH_OUTPUT") (error "Set EMMET2_BENCH_OUTPUT")))
        (filter (getenv "EMMET2_BENCH_FILTER")) cases)
    (when (file-exists-p output) (error "Refusing to overwrite %s" output))
    (dolist (kind '(tsx-markup tsx-style tsx-negative css web-css web-markup web-large-style))
      (setq cases
            (append cases
                    (emmet2-bench--group
                     kind (cond ((memq kind '(tsx-markup tsx-style tsx-negative))
                                 '((56 500) (56 5000) (56 20000) (306 5000) (1006 5000)))
                                ((eq kind 'web-large-style) '((0 0)))
                                (t '((0 500) (0 20000)))) filter))))
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
                     :sampling "same-kind sizes interleaved; first buffer rotates each round"
                     :gc-cons-threshold gc-cons-threshold :gc-cons-percentage gc-cons-percentage
                     :cases (vconcat cases))))
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
