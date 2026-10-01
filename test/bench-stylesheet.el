;;; bench-stylesheet.el --- Measure the complete native CSS path -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Load bootstrap.el first.  EMMET2_BENCH_OUTPUT must name a new file.

(require 'cl-lib)
(require 'json)
(require 'bytecomp)
(defvar emmet2-test-root)
(declare-function emmet2-css-search "emmet2-css-search" (query &optional limit bare))
(declare-function emmet2-extensions-css "emmet2-css" (abbreviation &rest options))
(declare-function emmet2-extensions-css-choices "emmet2-css" (abbreviation &rest options))
(declare-function emmet2-engine-stylesheet-expand "emmet2-engine-stylesheet" (abbreviation &rest options))

(defconst emmet2-stylesheet-bench--cases
  (append
   (mapcar (lambda (query) (list (concat "search:" query) #'emmet2-css-search query))
           '("m" "c" "bg" "ins" "bgc" "dib" "jcsb" "trfo" "whsnw" "posa" "gtc" "bdrs"))
   (mapcar (lambda (input) (list (concat "choices:" input) #'emmet2-extensions-css-choices input))
           '("ta" "ins32" "t-a" "w--sidebar-width" "posa" "button:hv"))
   (mapcar (lambda (input) (list (concat "expand:" input) #'emmet2-extensions-css input))
           '("m10+p5+bd1#2s+posa+dib+fz16" "ins32" "tac" "c+bg"))
   ;; The same six properties with canonical names measure the core alone.
   (list (list "core:six-canonical" #'emmet2-engine-stylesheet-expand
               "margin10+padding5+border1#2s+position-absolute+display-flex+font-size16")))
  "Search, completion-choice, expansion and core stages with representative input.")

(defun emmet2-stylesheet-bench--command (program &rest args)
  "Return successful metadata PROGRAM output for ARGS."
  (with-temp-buffer
    (unless (zerop (apply #'process-file program nil t nil args)) (error "Metadata failed: %s" program))
    (string-trim (buffer-string))))

(defun emmet2-stylesheet-bench--hashes ()
  "Hash measured sources, data, lock and harness."
  (vconcat
   (mapcar (lambda (file)
             (with-temp-buffer
               (insert-file-contents-literally (expand-file-name file emmet2-test-root))
               (list :file file :sha256 (secure-hash 'sha256 (current-buffer)))))
           '("emmet2-engine.el" "emmet2-fuzzy.el" "emmet2-css-search.el" "emmet2-extract.el" "emmet2-engine-stylesheet.el"
             "emmet2-css.el" "emmet2-extensions.el" "data/css-index.json" "data/css-overrides.json" "data/css-source.json"
             "test/bootstrap.el" "test/bench-stylesheet.el" "test/dependencies.json"))))

(defun emmet2-stylesheet-bench--sample (case expected)
  "Time CASE's complete operation; verify its result equals EXPECTED afterward."
  (let* ((start (current-time)) (gcs gcs-done) (gc-time gc-elapsed)
         (result (funcall (nth 1 case) (nth 2 case)))
         ;; Capture counters before duration/sample allocation can trigger GC.
         (end-gcs gcs-done) (end-gc-time gc-elapsed) (end (current-time))
         (sample (vector (* 1000 (float-time (time-subtract end start)))
                         (- end-gcs gcs) (- end-gc-time gc-time))))
    (unless (equal result expected) (error "Benchmark output differs: %s" (car case)))
    sample))

(defun emmet2-stylesheet-bench--summary (samples)
  "Summarize SAMPLES, retaining every GC and other slow operation."
  (let ((sorted (sort (mapcar (lambda (sample) (aref sample 0)) samples) #'<)))
    (list :count (length samples) :p50-ms (nth (1- (ceiling (* 0.50 (length samples)))) sorted)
          :p99-ms (nth (1- (ceiling (* 0.99 (length samples)))) sorted) :max-ms (car (last sorted))
          :gc-count (cl-loop for sample across samples sum (aref sample 1))
          :gc-seconds (cl-loop for sample across samples sum (aref sample 2)))))

(defun emmet2-stylesheet-bench--run ()
  "Measure the CSS search, choices and expansion through isolated bytecode."
  (let* ((output (getenv "EMMET2_BENCH_OUTPUT"))
         (hashes (emmet2-stylesheet-bench--hashes))
         (directory (make-temp-file "emmet2-stylesheet-bytecode-" t))
         (files '("emmet2-engine" "emmet2-fuzzy" "emmet2-css-search" "emmet2-extract" "emmet2-engine-stylesheet" "emmet2-css" "emmet2-extensions"))
         (byte-compile-error-on-warn t)
         (byte-compile-dest-file-function
          (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") directory)))
         (gc-cons-threshold 800000) (gc-cons-percentage 1.0)
         (coding-system-for-write 'utf-8-unix)
         rows load-ms)
    (unwind-protect
        (progn
          (unless (and output (file-name-absolute-p output) (not (file-exists-p output)))
            (error "EMMET2_BENCH_OUTPUT must be a new absolute file"))
          (when (or (featurep 'emmet2-css-search) (featurep 'emmet2-engine-stylesheet))
            (error "Run the native CSS benchmark in a fresh process"))
          (copy-directory (expand-file-name "data" emmet2-test-root) (expand-file-name "data" directory))
          (dolist (file files)
            (unless (byte-compile-file (expand-file-name (concat file ".el") emmet2-test-root))
              (error "Compilation failed: %s" file)))
          (let ((start (current-time)))
            (dolist (file files) (load (expand-file-name (concat file ".elc") directory) nil t t))
            (setq load-ms (* 1000 (float-time (time-subtract (current-time) start)))))
          (dolist (function '(emmet2-css-search emmet2-extract-css-pseudo emmet2-extensions-css-choices emmet2-extensions-css
                              emmet2-engine-stylesheet-expand))
            (unless (and (byte-code-function-p (symbol-function function))
                         (file-in-directory-p (symbol-file function) directory))
              (error "Measured function is not isolated bytecode: %s" function)))
          (let ((exec-path nil))
            (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "Unexpected native process"))))
              (setq rows (vconcat
                          (mapcar (lambda (case)
                                    ;; The cold call includes first use of the loaded index.
                                    (let* ((start (current-time))
                                           (expected (funcall (nth 1 case) (nth 2 case)))
                                           (cold (* 1000 (float-time (time-subtract (current-time) start)))))
                                      (list :id (car case) :input (nth 2 case) :cold-ms cold :expected expected
                                            :warmup (make-vector 100 nil) :samples (make-vector 1000 nil))))
                                  emmet2-stylesheet-bench--cases)))
              (dotimes (round 1100)
                (dotimes (offset (length rows))
                  (let* ((index (mod (+ round offset) (length rows))) (row (aref rows index)))
                    (aset (plist-get row (if (< round 100) :warmup :samples))
                          (if (< round 100) round (- round 100))
                          (emmet2-stylesheet-bench--sample (nth index emmet2-stylesheet-bench--cases)
                                                           (plist-get row :expected))))))))
          (dotimes (i (length rows))
            (let* ((row (aref rows i)) (summary (emmet2-stylesheet-bench--summary (plist-get row :samples))))
              (message "%-36s p50 %.3f  p99 %.3f  max %.3f ms" (plist-get row :id)
                       (plist-get summary :p50-ms) (plist-get summary :p99-ms) (plist-get summary :max-ms))
              (setf (aref rows i) (append (cl-loop for (key value) on row by #'cddr
                                                   unless (eq key :expected) append (list key value))
                                          (list :summary summary)))))
          (unless (equal hashes (emmet2-stylesheet-bench--hashes)) (error "Source changed during measurement"))
          (with-temp-buffer
            (insert (json-serialize
                     (list :revision (emmet2-stylesheet-bench--command "git" "rev-parse" "HEAD")
                           :status (emmet2-stylesheet-bench--command "git" "status" "--porcelain=v1")
                           :emacs emacs-version :configuration system-configuration-options
                           :system system-configuration :os (emmet2-stylesheet-bench--command "uname" "-a")
                           :cpu (emmet2-stylesheet-bench--command "sysctl" "-n" "machdep.cpu.brand_string")
                           :backend "elisp-bytecode" :gc-threshold gc-cons-threshold :gc-percentage gc-cons-percentage
                           :module-load-ms load-ms :hashes hashes :cases rows)))
            (write-region (point-min) (point-max) output nil 'silent nil 'excl))
          (message "Native CSS samples written: %s" output))
      (delete-directory directory t))))

(emmet2-stylesheet-bench--run)
;;; bench-stylesheet.el ends here
