;;; bench-completion.el --- Measure complete installed editor flows -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Load bootstrap.el first.  EMMET2_BENCH_PACKAGE is an actual installation;
;; EMMET2_BENCH_OUTPUT must be new.  Optional FILTER is diagnostic only.
(require 'cl-lib)
(require 'json)
(require 'web-mode)
(require 'typescript-ts-mode)
(require 'corfu)
(require 'corfu-popupinfo)
(require 'yasnippet)
(defvar emmet2-test-root)
(declare-function emmet2-expand "emmet2-mode" ())
(declare-function emmet2-mode "emmet2-mode" (&optional arg))
(declare-function emmet2-context--prepare "emmet2-context" ())
(declare-function emmet2-context-analyze "emmet2-context" (&optional automatic))
(declare-function emmet2-insert-render-options "emmet2-insert" (analysis))
(declare-function emmet2-preview-clear "emmet2-preview" ())

(defun emmet2-flow--command (program &rest arguments)
  "Return output from successful PROGRAM with ARGUMENTS."
  (with-temp-buffer
    (unless (zerop (apply #'process-file program nil t nil arguments))
      (error "Metadata command failed: %s" program))
    (string-trim (buffer-string))))

(defun emmet2-flow--hash (file)
  "Return the SHA256 of FILE."
  (with-temp-buffer (insert-file-contents-literally file) (secure-hash 'sha256 (current-buffer))))

(defun emmet2-flow--sources ()
  "Hash measured project source, resources, lock and harness."
  (vconcat
   (mapcar (lambda (name) (list :file name :sha256 (emmet2-flow--hash (expand-file-name name emmet2-test-root))))
           (append (directory-files emmet2-test-root nil "\\.el\\'")
                   '("test/bench-completion.el" "test/bootstrap.el" "test/dependencies.json")
                   (mapcar (lambda (file) (file-relative-name file emmet2-test-root))
                           (directory-files-recursively (expand-file-name "data" emmet2-test-root) "."))))))

(defun emmet2-flow--time (function)
  "Call FUNCTION and return [milliseconds gc-count gc-seconds]."
  (let ((start (current-time)) (gcs gcs-done) (gc-time gc-elapsed))
    (funcall function)
    (vector (* 1000 (float-time (time-subtract (current-time) start)))
            (- gcs-done gcs) (- gc-elapsed gc-time))))

(defun emmet2-flow--summary (samples)
  "Summarize raw triple SAMPLES, retaining every GC sample."
  (let ((sorted (sort (mapcar (lambda (sample) (aref sample 0)) samples) #'<)))
    (list :count (length samples) :p50-ms (nth (1- (ceiling (* 0.50 (length samples)))) sorted)
          :p99-ms (nth (1- (ceiling (* 0.99 (length samples)))) sorted) :max-ms (car (last sorted))
          :gc-count (cl-loop for sample across samples sum (aref sample 1))
          :gc-seconds (cl-loop for sample across samples sum (aref sample 2)))))

(defun emmet2-flow--completion (abbreviation multiline)
  "Measure real Corfu completion of ABBREVIATION, except screen drawing.
MULTILINE determines whether the selected result should offer documentation.
Return six triples: total, request, annotation, doc, repeated doc, accept."
  (let ((completion-styles '(basic partial-completion emacs22))
        (completion-category-defaults nil) (completion-category-overrides nil)
        (completion-cycle-threshold nil) (completion-in-region-function #'corfu--in-region-1)
        (corfu-on-exact-match nil) (corfu-preselect 'valid) (corfu-preview-current nil)
        request annotation doc repeated accept total shown document repeated-document)
    (cl-letf (((symbol-function 'corfu--popup-show) (lambda (&rest _) (setq shown t)))
              ((symbol-function 'corfu--popup-hide) #'ignore)
              ((symbol-function 'corfu--protect) #'funcall))
      (unwind-protect
          (setq total
                (emmet2-flow--time
                 (lambda ()
                   (setq request (emmet2-flow--time #'completion-at-point)
                         annotation (emmet2-flow--time #'corfu--exhibit)
                         doc (emmet2-flow--time (lambda () (setq document (corfu-popupinfo--get-documentation abbreviation))))
                         repeated (emmet2-flow--time (lambda () (setq repeated-document (corfu-popupinfo--get-documentation abbreviation))))
                         accept (emmet2-flow--time #'corfu-insert)))))
        (when completion-in-region-mode (corfu-quit))))
    (unless (and shown (if multiline (and (stringp document) (not (string-empty-p document)))
                        (null document))
                 (equal document repeated-document))
      (error "Benchmark skipped annotation or documentation"))
    (vector total request annotation doc repeated accept)))

(defun emmet2-flow--fixture (name mode source)
  "Measure NAME in MODE containing SOURCE with one point marker."
  (with-temp-buffer
    (insert source) (goto-char (point-min)) (search-forward "│") (delete-char -1)
    (let* ((position (point)) (original (buffer-string))
           (mode-time (emmet2-flow--time (lambda () (funcall mode))))
           (paths '(command completion completion-yas))
           (samples (vconcat (mapcar (lambda (_) (make-vector 1000 nil)) paths)))
           (warmups (vconcat (mapcar (lambda (_) (make-vector 100 nil)) paths)))
           (cold nil) expected cursor analysis abbreviation beg end output-end)
      (setq-local indent-tabs-mode nil)
      (buffer-enable-undo)
      (goto-char position) (emmet2-mode 1)
      (let ((preparation (emmet2-flow--time #'emmet2-context--prepare)))
        ;; First use includes lazy engine loading; later fixtures share loaded
        ;; Lisp/data/modes.  These cold samples do not include Emacs startup.
        (emmet2-preview-clear)
        (setq analysis (emmet2-context-analyze t)
              abbreviation (plist-get analysis :abbr) beg (plist-get analysis :beg) end (plist-get analysis :end))
        (unless analysis (error "Fixture has no confirmed automatic context: %s" name))
        (push (cons 'command (emmet2-flow--time #'emmet2-expand)) cold)
        (setq expected (buffer-string) cursor (point)
              output-end (+ end (- (length expected) (length original))))
        (unless (and (not (equal original expected)) (<= beg cursor output-end))
          (error "Fixture did not expand: %s" name))
        (cl-labels
            ((reset ()
               (when (bound-and-true-p yas-minor-mode) (yas-exit-all-snippets))
               (goto-char beg) (delete-region beg output-end) (insert abbreviation) (goto-char position)
               ;; Exclude accumulated edit history; field creation itself stays timed.
               (setq buffer-undo-list nil))
             (verify ()
               (unless (and (equal (buffer-string) expected) (= (point) cursor))
                 (error "Benchmark changed output/cursor: %s" name)))
             (run (path)
               (let ((sample (if (eq path 'command) (vector (emmet2-flow--time #'emmet2-expand))
                               (emmet2-flow--completion
                                abbreviation (string-match-p "\n" (substring expected (1- beg) (1- output-end)))))))
                 (when (and (eq path 'completion-yas) (< cursor output-end)
                            (not (yas-active-snippets)))
                   (error "Benchmark skipped editable fields: %s" name))
                 sample)))
          (reset)
          (emmet2-preview-clear)
          (push (cons 'completion (run 'completion)) cold)
          (verify) (reset)
          (yas-minor-mode 1)
          (push (cons 'completion-yas (run 'completion-yas)) cold)
          (verify) (reset) (yas-minor-mode -1)
          ;; Interleave paths and rotate the first path each round.
          (dotimes (i 1100)
            (dotimes (j (length paths))
              (let* ((index (% (+ i j) (length paths))) (path (nth index paths)) sample)
                (yas-minor-mode (if (eq path 'completion-yas) 1 -1))
                (setq sample (run path))
                (verify) (reset)
                (aset (aref (if (< i 100) warmups samples) index) (if (< i 100) i (- i 100)) sample))))
          (let ((reports
                 (cl-loop for path in paths for index from 0
                          for raw = (aref samples index)
                          collect
                          (list :path path :warmups (aref warmups index) :samples raw
                                :stages (vconcat
                                         (cl-loop for stage in (if (eq path 'command) '(total)
                                                                 '(total request annotation documentation documentation-repeat accept))
                                                  for column from 0
                                                  collect (append (list :stage stage) (emmet2-flow--summary
                                                                       (vconcat (mapcar (lambda (row) (aref row column)) raw))))))))))
            (message "%s: command p99 %.3f; completion %.3f; yas %.3f ms" name
                     (plist-get (aref (plist-get (nth 0 reports) :stages) 0) :p99-ms)
                     (plist-get (aref (plist-get (nth 1 reports) :stages) 0) :p99-ms)
                     (plist-get (aref (plist-get (nth 2 reports) :stages) 0) :p99-ms))
            (list :name name :mode mode :bytes (string-bytes original)
                  :source-sha256 (secure-hash 'sha256 original) :output-sha256 (secure-hash 'sha256 expected)
                  :abbreviation abbreviation :render-options (emmet2-insert-render-options analysis)
                  :mode-init mode-time :context-preparation preparation :cold (nreverse cold)
                  :paths (vconcat reports))))))))

(let* ((package (or (getenv "EMMET2_BENCH_PACKAGE") (error "Set EMMET2_BENCH_PACKAGE")))
       (output (or (getenv "EMMET2_BENCH_OUTPUT") (error "Set EMMET2_BENCH_OUTPUT")))
       (filter (getenv "EMMET2_BENCH_FILTER"))
       (sources (emmet2-flow--sources))
       (six "m10+p5+bd1#2s+posa+dib+fz16")
       (fixtures `(("web-list" web-mode "<main>\n  ul>li.item$*5>a{Link $}│\n</main>")
                   ("web-card" web-mode "div.card>(header>h2{Title})+section>p*3│")
                   ("tsx-list" tsx-ts-mode "const A=(<main>ul>li.item$*5>a{Link $}│</main>);")
                   ("css-one" css-mode ".a { m10│ }")
                   ("css-six" css-mode ,(concat ".a { " six "│ }"))
                   ("css-fields" css-mode ".a { c+bg+bd│ }")
                   ("tsx-style-six" tsx-ts-mode ,(concat "const A=(<main style={{" six "│}} />);"))
                   ("web-large-style-six" web-mode
                    ,(concat "<style>" (apply #'concat (make-list 2300 ".a { margin: 0; padding: 12px; content: \"x\"; /* filler */ }\n"))
                             ".last { " six "│ }</style>")))) reports)
  (when (file-exists-p output) (error "Refusing to overwrite %s" output))
  (seq-doseq (entry sources)
    (let ((name (plist-get entry :file)))
      (unless (string-prefix-p "test/" name)
        (unless (equal (plist-get entry :sha256) (emmet2-flow--hash (expand-file-name name package)))
          (error "Installed source differs from current runtime: %s" name)))))
  (setq load-path (cons package (delete emmet2-test-root load-path)))
  (require 'emmet2-mode) (require 'emmet2-capf) (require 'emmet2-preview)
  (dolist (function '(emmet2-expand emmet2-capf emmet2-preview emmet2-context-analyze emmet2-engine-expand))
    (unless (and (byte-code-function-p (symbol-function function))
                 (file-in-directory-p (symbol-file function 'defun) package))
      (error "Measured function is not installed bytecode: %s" function)))
  (unwind-protect
      (progn
        (let ((exec-path nil))
          (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "Native flow must not start a process")))
                    ((symbol-function 'call-process) (lambda (&rest _) (error "Native flow must not call a process"))))
            (dolist (fixture fixtures)
              (when (or (not filter) (string-match-p filter (car fixture)))
                (push (apply #'emmet2-flow--fixture fixture) reports)))))
        (when (featurep 'emmet2-engine-node) (error "Measured flow loaded Node"))
        (unless reports (error "No matching fixture"))
        (unless (equal sources (emmet2-flow--sources)) (error "Measured sources changed"))
        (with-temp-file output
          (insert (json-encode
                   (list :revision (emmet2-flow--command "git" "rev-parse" "HEAD")
                         :dirty (emmet2-flow--command "git" "status" "--short") :source-sha256 sources
                         :emacs emacs-version :configuration system-configuration
                         :configure-options system-configuration-options
                         :system (emmet2-flow--command "uname" "-srm")
                         :cpu (if (eq system-type 'darwin)
                                  (emmet2-flow--command "sysctl" "-n" "machdep.cpu.brand_string")
                                (emmet2-flow--command "uname" "-m"))
                         :package package
                         :backend "native Elisp" :project-compilation "bytecode"
                         :optional-packages "locked source; built-in modes from this Emacs build"
                         :display "real Corfu control, annotation formatting and popupinfo; screen drawing replaced"
                         :gc-cons-threshold gc-cons-threshold :gc-cons-percentage gc-cons-percentage
                         :filter filter :sample-columns ["milliseconds" "gc-count" "gc-seconds"]
                         :cases (vconcat (nreverse reports)))))
          (insert "\n")))
    (emmet2-preview-clear)))

;;; bench-completion.el ends here
