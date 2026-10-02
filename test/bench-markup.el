;;; bench-markup.el --- Measure the complete native markup path -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Load bootstrap.el first.  EMMET2_BENCH_OUTPUT must name a new file.
(require 'cl-lib)
(require 'json)
(require 'bytecomp)
(defvar emmet2-test-root)
(declare-function emmet2-engine-markup-expand "emmet2-engine-markup")
(declare-function emmet2-markup-test--cases "emmet2-engine-markup-test" (&optional ids))
(declare-function emmet2-lorem-test--json "emmet2-lorem-contract" (path))
(declare-function emmet2-lorem-test--check-result "emmet2-lorem-contract" (fixture result))

(defun emmet2-markup-bench--command (program &rest args)
  "Return successful metadata PROGRAM output for ARGS."
  (with-temp-buffer
    (unless (zerop (apply #'process-file program nil t nil args)) (error "Metadata failed: %s" program))
    (string-trim (buffer-string))))

(defun emmet2-markup-bench--hashes ()
  "Hash all measured sources, fixtures, data, lock and harness."
  (vconcat
   (mapcar (lambda (file)
             (with-temp-buffer
               (insert-file-contents-literally (expand-file-name file emmet2-test-root))
               (list :file file :sha256 (secure-hash 'sha256 (current-buffer)))))
           '("emmet2-engine.el" "emmet2-engine-markup.el" "data/emmet/html.json" "data/emmet/variables.json"
             "data/emmet/lorem/latin.json" "data/emmet/lorem/russian.json" "data/emmet/lorem/spanish.json"
             "test/emmet2-engine-markup-test.el" "test/fixtures/core-inputs.json"
             "test/emmet2-lorem-contract.el" "test/fixtures/lorem.json" "data/emmet/source.json"
             "test/fixtures/oracle/markup.json" "test/bench-markup.el" "test/dependencies.json"))))

(defun emmet2-markup-bench--sample (case)
  "Time the full expansion in CASE, then verify its result.
Lorem's first result must pass structural checks before becoming this run's
reference for all later complete-result comparisons."
  (let* ((start (current-time)) (gcs gcs-done) (gc-time gc-elapsed)
         (result (apply #'emmet2-engine-markup-expand (nth 1 case)))
         ;; Snapshot GC before allocating the duration/sample representation.
         ;; Its bookkeeping must not charge a later collection to this call.
         (end-gcs gcs-done) (end-gc-time gc-elapsed) (end (current-time))
         (sample (vector (* 1000 (float-time (time-subtract end start)))
                         (- end-gcs gcs) (- end-gc-time gc-time))))
    (when (functionp (nth 2 case))
      (funcall (nth 2 case) result)
      (setf (nth 2 case) result))
    (unless (equal result (nth 2 case)) (error "Benchmark output differs: %s" (car case)))
    sample))

(defun emmet2-markup-bench--summary (samples)
  "Summarize raw SAMPLES without removing GC or other slow operations."
  (let ((sorted (sort (mapcar (lambda (sample) (aref sample 0)) samples) #'<)))
    (list :count (length samples) :p50-ms (nth (1- (ceiling (* 0.50 (length samples)))) sorted)
          :p99-ms (nth (1- (ceiling (* 0.99 (length samples)))) sorted) :max-ms (car (last sorted))
          :gc-count (cl-loop for sample across samples sum (aref sample 1))
          :gc-seconds (cl-loop for sample across samples sum (aref sample 2)))))

(defun emmet2-markup-bench--run ()
  "Compile isolated bytecode and measure the complete markup fixture set."
  (let* ((output (getenv "EMMET2_BENCH_OUTPUT"))
         (hashes (emmet2-markup-bench--hashes))
         (directory (make-temp-file "emmet2-markup-bytecode-" t))
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
          (copy-directory (expand-file-name "data" emmet2-test-root) (expand-file-name "data" directory))
          (dolist (file '("emmet2-engine.el" "emmet2-engine-markup.el"))
            (unless (byte-compile-file (expand-file-name file emmet2-test-root)) (error "Compilation failed: %s" file)))
          (let ((start (current-time)))
            (dolist (file '("emmet2-engine.elc" "emmet2-engine-markup.elc"))
              (load (expand-file-name file directory) nil t t))
            (setq load-ms (* 1000 (float-time (time-subtract (current-time) start)))))
          (dolist (function '(emmet2-engine-markup-expand emmet2-result-create))
            (unless (and (byte-code-function-p (symbol-function function))
                         (file-in-directory-p (symbol-file function) directory))
              (error "Measured function is not isolated bytecode: %s" function)))
          (load (expand-file-name "test/emmet2-engine-markup-test.el" emmet2-test-root) nil t)
          (when (featurep 'emmet2-engine-node) (error "Node loaded into native benchmark"))
          (let* ((ids '("html-contract-01" "html-contract-02" "html-contract-03" "html-snippet:!"
                        "html-contract-04" "jsx-contract-03" "jsx-contract-04" "html-contract-14" "html-contract-10"
                        "jsx-project-007" "jsx-project-038" "jsx-project-084"))
                 (lorem (emmet2-lorem-test--json "test/fixtures/lorem.json"))
                 (cases (append (emmet2-markup-test--cases ids)
                                (mapcar (lambda (id)
                                          (let ((fixture (or (cl-find id lorem :key (lambda (row) (alist-get 'id row)) :test #'equal)
                                                             (error "Missing lorem fixture: %s" id))))
                                            (list id (list (alist-get 'abbreviation fixture) :preset 'html
                                                           :indent "\t" :base-indent "" :seed 42)
                                                  (apply-partially #'emmet2-lorem-test--check-result fixture))))
                                        '("lorem-006" "lorem-012" "lorem-015"))))
                 ;; No external runtime can participate in the measured path.
                 (exec-path nil))
            (setq rows (vconcat (mapcar (lambda (case)
                                         (list :id (car case) :arguments
                                               (vconcat (mapcar (lambda (arg) (if (symbolp arg) (symbol-name arg) arg)) (nth 1 case)))
                                               :cold (emmet2-markup-bench--sample case)
                                               :expected (let ((result (nth 2 case)))
                                                           (list :text (plist-get result :text) :cursor (plist-get result :cursor)
                                                                 :fields (vconcat (mapcar #'vconcat (plist-get result :fields)))))
                                               :warmup (make-vector 100 nil) :samples (make-vector 1000 nil))) cases)))
            (dotimes (round 1100)
              (dotimes (offset (length cases))
                (let* ((index (mod (+ round offset) (length cases))) (row (aref rows index)))
                  (aset (plist-get row (if (< round 100) :warmup :samples))
                        (if (< round 100) round (- round 100))
                        (emmet2-markup-bench--sample (nth index cases))))))
            (dotimes (i (length rows))
              (let ((row (aref rows i)))
                (setf (aref rows i) (append row (list :summary (emmet2-markup-bench--summary (plist-get row :samples))))))))
          (unless (equal hashes (emmet2-markup-bench--hashes)) (error "Source changed during measurement"))
          (with-temp-buffer
            (insert (json-serialize
                     (list :revision (emmet2-markup-bench--command "git" "rev-parse" "HEAD")
                           :status (emmet2-markup-bench--command "git" "status" "--porcelain=v1")
                           :emacs emacs-version :configuration system-configuration-options
                           :system system-configuration :os (emmet2-markup-bench--command "uname" "-a")
                           :cpu (emmet2-markup-bench--command "sysctl" "-n" "machdep.cpu.brand_string")
                           :backend "elisp-bytecode" :gc-threshold gc-cons-threshold :gc-percentage gc-cons-percentage
                           :module-load-ms load-ms :hashes hashes :fixtures rows)))
            (write-region (point-min) (point-max) output nil 'silent nil 'excl))
          (message "Native markup samples written: %s" output))
      (delete-directory directory t))))

(emmet2-markup-bench--run)
;;; bench-markup.el ends here
