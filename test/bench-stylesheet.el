;;; bench-stylesheet.el --- Measure the complete native CSS path -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Load bootstrap.el first.  EMMET2_BENCH_OUTPUT must name a new file.

(require 'cl-lib)
(require 'json)
(require 'bytecomp)
(defvar emmet2-test-root)
(declare-function emmet2-engine-stylesheet-expand "emmet2-engine-stylesheet")
(declare-function emmet2-stylesheet-test--cases "emmet2-engine-stylesheet-test" ())

(defun emmet2-stylesheet-bench--command (program &rest args)
  "Return successful metadata PROGRAM output for ARGS."
  (with-temp-buffer
    (unless (zerop (apply #'process-file program nil t nil args)) (error "Metadata failed: %s" program))
    (string-trim (buffer-string))))

(defun emmet2-stylesheet-bench--hashes ()
  "Hash measured sources, fixture contracts, data, lock and harness."
  (vconcat
   (mapcar (lambda (file)
             (with-temp-buffer
               (insert-file-contents-literally (expand-file-name file emmet2-test-root))
               (list :file file :sha256 (secure-hash 'sha256 (current-buffer)))))
           '("emmet2-engine.el" "emmet2-engine-stylesheet.el" "emmet2-fuzzy.el" "data/emmet/css.json"
             "test/emmet2-engine-stylesheet-test.el" "test/fixtures/core-inputs.json"
             "test/fixtures/oracle/stylesheet.json" "vendor/emmet-source.json"
             "test/bootstrap.el" "test/bench-stylesheet.el" "test/dependencies.json"))))

(defun emmet2-stylesheet-bench--sample (case)
  "Time the complete expansion in CASE; verify the full result afterward."
  (let* ((start (current-time)) (gcs gcs-done) (gc-time gc-elapsed)
         (result (apply #'emmet2-engine-stylesheet-expand (nth 1 case)))
         ;; Capture counters before duration/sample allocation can trigger GC.
         (end-gcs gcs-done) (end-gc-time gc-elapsed) (end (current-time))
         (sample (vector (* 1000 (float-time (time-subtract end start)))
                         (- end-gcs gcs) (- end-gc-time gc-time))))
    (unless (equal result (nth 2 case)) (error "Benchmark output differs: %s" (car case)))
    sample))

(defun emmet2-stylesheet-bench--summary (samples)
  "Summarize SAMPLES, retaining every GC and other slow operation."
  (let ((sorted (sort (mapcar (lambda (sample) (aref sample 0)) samples) #'<)))
    (list :count (length samples) :p50-ms (nth (1- (ceiling (* 0.50 (length samples)))) sorted)
          :p99-ms (nth (1- (ceiling (* 0.99 (length samples)))) sorted) :max-ms (car (last sorted))
          :gc-count (cl-loop for sample across samples sum (aref sample 1))
          :gc-seconds (cl-loop for sample across samples sum (aref sample 2)))))

(defun emmet2-stylesheet-bench--run ()
  "Measure S7 CSS through isolated bytecode with fixed oracle inputs."
  (let* ((output (getenv "EMMET2_BENCH_OUTPUT"))
         (hashes (emmet2-stylesheet-bench--hashes))
         (directory (make-temp-file "emmet2-stylesheet-bytecode-" t))
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
          (when (or (featurep 'emmet2-engine-node) (featurep 'emmet2-engine-stylesheet))
            (error "Run the native CSS benchmark in a fresh process"))
          (copy-directory (expand-file-name "data" emmet2-test-root) (expand-file-name "data" directory))
          (dolist (file '("emmet2-engine.el" "emmet2-fuzzy.el" "emmet2-engine-stylesheet.el"))
            (unless (byte-compile-file (expand-file-name file emmet2-test-root)) (error "Compilation failed: %s" file)))
          (let ((start (current-time)))
            (dolist (file '("emmet2-engine.elc" "emmet2-fuzzy.elc" "emmet2-engine-stylesheet.elc"))
              (load (expand-file-name file directory) nil t t))
            (setq load-ms (* 1000 (float-time (time-subtract (current-time) start)))))
          (dolist (function '(emmet2-engine-stylesheet-expand emmet2-result-create emmet2-fuzzy-find))
            (unless (and (byte-code-function-p (symbol-function function))
                         (file-in-directory-p (symbol-file function) directory))
              (error "Measured function is not isolated bytecode: %s" function)))
          (load (expand-file-name "test/emmet2-engine-stylesheet-test.el" emmet2-test-root) nil t)
          (let* ((all (emmet2-stylesheet-test--cases))
                 (ids '("stylesheet-contract-10" "stylesheet-contract-01" "stylesheet-contract-06"
                        "stylesheet-contract-09" "stylesheet-contract-11" "stylesheet-native-067"
                        "stylesheet-native-070" "stylesheet-native-072" "stylesheet-native-097"
                        "stylesheet-native-109" "stylesheet-native-176" "stylesheet-native-178"))
                 (cases (mapcar (lambda (id) (or (assoc id all) (error "Missing fixture: %s" id))) ids))
                 (exec-path nil))
            (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "Unexpected native process"))))
              (setq rows (vconcat
                          (mapcar (lambda (case)
                                    (list :id (car case) :arguments
                                          (vconcat (mapcar (lambda (arg) (if (symbolp arg) (symbol-name arg) arg)) (nth 1 case)))
                                          :cold (emmet2-stylesheet-bench--sample case)
                                          :expected (let ((result (nth 2 case)))
                                                      (list :text (plist-get result :text) :cursor (plist-get result :cursor)
                                                            :fields (vconcat (mapcar #'vconcat (plist-get result :fields)))))
                                          :warmup (make-vector 100 nil) :samples (make-vector 1000 nil))) cases)))
              ;; Recheck every success/error contract outside the clocks, after
              ;; cold samples and before warming the selected measurement rows.
              (unless (= (length all) 447) (error "Incomplete CSS corpus"))
              (dolist (case all)
                (unless (equal (condition-case err (apply #'emmet2-engine-stylesheet-expand (nth 1 case))
                                 (emmet2-parse-error err)) (nth 2 case))
                  (error "CSS oracle differs: %s" (car case))))
              (dotimes (round 1100)
                (dotimes (offset (length cases))
                  (let* ((index (mod (+ round offset) (length cases))) (row (aref rows index)))
                    (aset (plist-get row (if (< round 100) :warmup :samples))
                          (if (< round 100) round (- round 100))
                          (emmet2-stylesheet-bench--sample (nth index cases)))))))
            (dotimes (i (length rows))
              (let ((row (aref rows i)))
                (setf (aref rows i) (append row (list :summary (emmet2-stylesheet-bench--summary (plist-get row :samples))))))))
          (when (featurep 'emmet2-engine-node) (error "Node loaded into native CSS benchmark"))
          (unless (equal hashes (emmet2-stylesheet-bench--hashes)) (error "Source changed during measurement"))
          (with-temp-buffer
            (insert (json-serialize
                     (list :revision (emmet2-stylesheet-bench--command "git" "rev-parse" "HEAD")
                           :status (emmet2-stylesheet-bench--command "git" "status" "--porcelain=v1")
                           :emacs emacs-version :configuration system-configuration-options
                           :system system-configuration :os (emmet2-stylesheet-bench--command "uname" "-a")
                           :cpu (emmet2-stylesheet-bench--command "sysctl" "-n" "machdep.cpu.brand_string")
                           :backend "elisp-bytecode" :gc-threshold gc-cons-threshold :gc-percentage gc-cons-percentage
                           :module-load-ms load-ms :oracle-count 447 :hashes hashes :fixtures rows)))
            (write-region (point-min) (point-max) output nil 'silent nil 'excl))
          (message "Native CSS samples written: %s" output))
      (delete-directory directory t))))

(emmet2-stylesheet-bench--run)
;;; bench-stylesheet.el ends here
