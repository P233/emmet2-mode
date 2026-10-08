;;; bench-completion.el --- Measure complete installed editor flows -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Load bootstrap.el first.  EMMET2_BENCH_PACKAGE names an installed package
;; directory and EMMET2_BENCH_OUTPUT a new file.  EMMET2_BENCH_FILTER is
;; diagnostic only.
(require 'cl-lib)
(require 'json)
(require 'web-mode)
(require 'css-mode)
(require 'typescript-ts-mode)
(require 'corfu)
(require 'corfu-popupinfo)
(require 'yasnippet)
(defvar emmet2-test-root)
(declare-function emmet2-expand-analysis "emmet2-expand" (analysis))
(declare-function emmet2-mode "emmet2-mode" (&optional arg))
(declare-function emmet2-complete "emmet2-capf" ())
(declare-function emmet2-context-js-prepare "emmet2-context-js" ())
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
    ;; Sample allocation must not add GC outside the measured operation.
    (let ((end-gcs gcs-done) (end-gc-time gc-elapsed) (end (current-time)))
      (vector (* 1000 (float-time (time-subtract end start)))
              (- end-gcs gcs) (- end-gc-time gc-time)))))

(defun emmet2-flow--summary (samples)
  "Summarize raw triple SAMPLES, retaining every GC sample."
  (let ((sorted (sort (mapcar (lambda (sample) (aref sample 0)) samples) #'<)))
    (list :count (length samples) :p50-ms (nth (1- (ceiling (* 0.50 (length samples)))) sorted)
          :p99-ms (nth (1- (ceiling (* 0.99 (length samples)))) sorted) :max-ms (car (last sorted))
          :gc-count (cl-loop for sample across samples sum (aref sample 1))
          :gc-seconds (cl-loop for sample across samples sum (aref sample 2)))))

(defmacro emmet2-flow--without-yasnippet (&rest body)
  "Run BODY as if yasnippet were not installed, so insertion stays plain."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'yas-minor-mode) nil)) ,@body))

(defun emmet2-flow--completion (abbreviation multiline &optional explicit)
  "Measure real Corfu completion of ABBREVIATION, except screen drawing.
MULTILINE determines whether the selected result should offer documentation.
EXPLICIT requests completion through `emmet2-complete'.
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
                   (setq request (emmet2-flow--time (if explicit #'emmet2-complete #'completion-at-point))
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

(defun emmet2-flow--fixture (name mode source &optional explicit)
  "Measure NAME in MODE containing SOURCE with one point marker.
EXPLICIT selects the manual request, including unsupported automatic hosts."
  (with-temp-buffer
    (insert source) (goto-char (point-min)) (search-forward "│") (delete-char -1)
    (let* ((position (point)) (original (buffer-string))
           (mode-time (emmet2-flow--time (lambda () (funcall mode))))
           (paths '(completion completion-yas))
           (samples (vconcat (mapcar (lambda (_) (make-vector 1000 nil)) paths)))
           (warmups (vconcat (mapcar (lambda (_) (make-vector 100 nil)) paths)))
           (cold nil) expected cursor analysis abbreviation beg end output-end multiline)
      (setq-local indent-tabs-mode nil)
      (buffer-enable-undo)
      (goto-char position) (emmet2-mode 1)
      (let ((preparation (emmet2-flow--time #'emmet2-context-js-prepare)))
        ;; Cold completion follows this context/expansion preflight.  It does
        ;; not measure first engine/data loading or Emacs startup.
        (emmet2-preview-clear)
        (setq analysis (emmet2-context-analyze (not explicit))
              abbreviation (plist-get analysis :abbr) beg (plist-get analysis :beg) end (plist-get analysis :end))
        (unless analysis (error "Fixture has no confirmed context: %s" name))
        ;; The accepted first choice is the expansion of the abbreviation itself.
        (setq multiline (string-match-p "\n" (plist-get (emmet2-expand-analysis analysis) :text)))
        (push (cons 'completion (emmet2-flow--without-yasnippet
                                 (emmet2-flow--completion abbreviation multiline explicit)))
              cold)
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
               (let ((sample (if (eq path 'completion-yas)
                                 (emmet2-flow--completion abbreviation multiline explicit)
                               (emmet2-flow--without-yasnippet
                                (emmet2-flow--completion abbreviation multiline explicit)))))
                 ;; Only markup starts snippet fields; CSS inserts plain text.
                 (when (and (eq path 'completion-yas) (< cursor output-end)
                            (eq (eq (plist-get analysis :lang) 'markup) (null (yas-active-snippets))))
                   (error "Benchmark editable fields differ from the language: %s" name))
                 sample)))
          (reset)
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
                                         (cl-loop for stage in '(total request annotation documentation
                                                                        documentation-repeat accept)
                                                  for column from 0
                                                  collect (append (list :stage stage) (emmet2-flow--summary
                                                                       (vconcat (mapcar (lambda (row) (aref row column)) raw))))))))))
            (message "%s: completion p99 %.3f; yas %.3f ms" name
                     (plist-get (aref (plist-get (nth 0 reports) :stages) 0) :p99-ms)
                     (plist-get (aref (plist-get (nth 1 reports) :stages) 0) :p99-ms))
            (list :name name :mode mode :request (if explicit 'emmet2-complete 'completion-at-point)
                  :bytes (string-bytes original)
                  :source-sha256 (secure-hash 'sha256 original) :output-sha256 (secure-hash 'sha256 expected)
                  :abbreviation abbreviation :render-options (emmet2-insert-render-options analysis)
                  :mode-init mode-time :context-preparation preparation :cold (nreverse cold)
                  :paths (vconcat reports))))))))

(defun emmet2-flow--live-fixture (name mode source)
  "Measure typing and deleting within one Corfu session in NAME, MODE, SOURCE."
  (save-window-excursion
    (with-temp-buffer
      (insert source) (search-backward "│") (delete-char 1)
      (let ((position (point))) (funcall mode) (goto-char position))
      (setq-local indent-tabs-mode nil)
      (set-window-buffer (selected-window) (current-buffer))
      (emmet2-mode 1) (emmet2-context-js-prepare)
      (let ((completion-styles '(basic partial-completion emacs22))
            (completion-category-defaults nil) (completion-category-overrides nil)
            (completion-cycle-threshold nil) (completion-in-region-function #'corfu--in-region-1)
            (corfu-on-exact-match nil) (corfu-preselect 'valid) (corfu-preview-current nil)
            (warmups (vector (make-vector 100 nil) (make-vector 100 nil)))
            (samples (vector (make-vector 1000 nil) (make-vector 1000 nil))) cold)
        (cl-letf (((symbol-function 'corfu--popup-show) #'ignore)
                  ((symbol-function 'corfu--popup-hide) #'ignore)
                  ((symbol-function 'corfu--protect) #'funcall))
          (unwind-protect
              (progn
                (setq cold (emmet2-flow--time (lambda () (completion-at-point) (corfu--exhibit))))
                (let ((table (nth 2 completion-in-region--data)))
                  (dotimes (i 1100)
                    (dotimes (edit 2)
                      (let ((sample
                             (emmet2-flow--time
                              (lambda ()
                                (if (zerop edit)
                                    (let ((last-command-event ?a)) (self-insert-command 1))
                                  (delete-char -1))
                                (let ((this-command (if (zerop edit) 'self-insert-command
                                                      'backward-delete-char-untabify)))
                                  (corfu--post-command))
                                (corfu--exhibit)))))
                        (unless (and completion-in-region-mode
                                     (eq table (nth 2 completion-in-region--data))
                                     (= corfu--total 10)
                                     (cl-every (lambda (candidate)
                                                 (equal candidate (if (zerop edit) "ovh,ta" "ovh,t")))
                                               corfu--candidates))
                          (error "Live edit lost or reused stale choices: %s" name))
                        (aset (aref (if (< i 100) warmups samples) edit)
                              (if (< i 100) i (- i 100)) sample))))))
            (when completion-in-region-mode (corfu-quit))))
        (let ((paths (cl-loop for path in '(type-a delete-a) for i from 0
                              collect (append (list :path path :warmups (aref warmups i)
                                                    :samples (aref samples i))
                                              (emmet2-flow--summary (aref samples i))))))
          (message "%s: typing p99 %.3f; deletion %.3f ms" name
                   (plist-get (nth 0 paths) :p99-ms) (plist-get (nth 1 paths) :p99-ms))
          (list :name name :mode mode :source-sha256 (secure-hash 'sha256 source)
                :cold cold :paths (vconcat paths)))))))

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
                   ("css-choices" css-mode ".a { ta│ }")
                   ("css-confirmed-choices" css-mode ".a { ovh,t│ }")
                   ("css-ts-fields" css-ts-mode ".a { c+bg│ }")
                   ("scss-variable" scss-mode ".a { p$gutter│ }")
                   ("less-fields" less-css-mode ".a { c+bg│ }")
                   ("web-inline-fields" web-mode "<div style=\"c+bg│\"></div>")
                   ("js-style-six" js-mode ,(concat "const styles=StyleSheet.create({card:{" six "│}});"))
                   ("js-ts-style-six" js-ts-mode ,(concat "const styles=StyleSheet.create({card:{" six "│}});"))
                   ("ts-style-fields" typescript-ts-mode "const styles=createTheme({card:{c+bg│}});")
                   ("html-manual-list" html-mode "<main>ul>li.item$*5>a{Link $}│</main>" t)
                   ("tsx-style-six" tsx-ts-mode ,(concat "const A=(<main style={{" six "│}} />);"))
                   ("web-large-style-six" web-mode
                    ,(concat "<style>" (apply #'concat (make-list 2300 ".a { margin: 0; padding: 12px; content: \"x\"; /* filler */ }\n"))
                             ".last { " six "│ }</style>"))))
       (live-fixtures '(("live-css" css-mode ".a { ovh,t│ }")
                        ("live-css-ts" css-ts-mode ".a { ovh,t│ }")
                        ("live-web-inline" web-mode "<div style=\"ovh,t│\"></div>")
                        ("live-tsx-style" tsx-ts-mode "const A=(<main style={{ovh,t│}} />);")))
       reports live-reports)
  (when (file-exists-p output) (error "Refusing to overwrite %s" output))
  (seq-doseq (entry sources)
    (let ((name (plist-get entry :file)))
      (unless (string-prefix-p "test/" name)
        (unless (equal (plist-get entry :sha256) (emmet2-flow--hash (expand-file-name name package)))
          (error "Installed source differs from current runtime: %s" name)))))
  (setq load-path (cons package (delete emmet2-test-root load-path)))
  (require 'emmet2-mode) (require 'emmet2-capf) (require 'emmet2-preview)
  (dolist (function '(emmet2-complete emmet2-capf emmet2-preview emmet2-context-analyze emmet2-engine-expand
                      emmet2-css-search))
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
                (push (apply #'emmet2-flow--fixture fixture) reports)))
            (dolist (fixture live-fixtures)
              (when (or (not filter) (string-match-p filter (car fixture)))
                (push (apply #'emmet2-flow--live-fixture fixture) live-reports)))))
        (when (featurep 'emmet2-engine-node) (error "Measured flow loaded Node"))
        (unless (or reports live-reports) (error "No matching fixture"))
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
                         :cases (vconcat (nreverse reports))
                         :live-cases (vconcat (nreverse live-reports)))))
          (insert "\n")))
    (emmet2-preview-clear)))

;;; bench-completion.el ends here
