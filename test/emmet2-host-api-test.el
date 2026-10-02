;;; emmet2-host-api-test.el --- External host completion contracts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'emmet2-capf-test)
(require 'emmet2-css-data)

(defun emmet2-host-test--analysis (_automatic)
  "Confirm the stylesheet fragment in an external-host test fixture."
  (when-let* ((fragment (emmet2-extract (point-min) (point-max) 'css)))
    (append fragment '(:lang css :syntax scss :position declaration-start
                             :indent-width 2))))

(defmacro emmet2-host-test--with-completion (input &rest body)
  "Run BODY with INPUT through a host provider, without a built-in CSS mode."
  (declare (indent 1) (debug t))
  `(emmet2-test--with-css-completion ,input
     (emmet2-mode -1)
     (fundamental-mode)
     (setq-local emmet2-context-provider
                 (list :analyze #'emmet2-host-test--analysis :revision #'ignore))
     (emmet2-mode 1)
     (should-not (emmet2-context-js--owner))
     ,@body))

(ert-deftest emmet2-host-provider-is-the-only-context-authority ()
  (with-temp-buffer
    (insert "m10")
    (let (requests)
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (automatic)
                                   (push automatic requests)
                                   '(:beg 1 :end 4 :abbr "untrusted" :lang css :syntax scss
                                          :position declaration-start :indent-width 3))
                        :revision #'ignore))
      (cl-letf (((symbol-function 'emmet2-context-js-region)
                 (lambda () (error "The built-in host classifier must not run"))))
        (should (equal (plist-get (emmet2-context-analyze t) :abbr) "m10"))
        (should (equal (plist-get (emmet2-context-analyze) :syntax) 'scss))
        (should (equal requests '(nil t)))
        (setq-local emmet2-context-provider (list :analyze #'ignore :revision #'ignore))
        (should-not (emmet2-capf))
        (should-error (emmet2-complete) :type 'user-error)))))

(ert-deftest emmet2-host-command-requests-context-once ()
  (with-temp-buffer
    (insert "m10")
    (let (requests requested)
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (automatic)
                                   (push automatic requests)
                                   (emmet2-host-test--analysis automatic))
                        :revision #'ignore))
      (let ((completion-in-region-function
             (lambda (beg end table &optional predicate)
               (should (= beg 1)) (should (= end 4))
               (should (all-completions "m10" table predicate))
               (setq requested t))))
        (emmet2-complete))
      (should requested)
      (should (equal requests '(nil)))
      (should (equal (buffer-string) "m10")))))

(ert-deftest emmet2-host-provider-validates-ranges-and-render-context ()
  (with-temp-buffer
    (insert "xx m10 yy") (goto-char 7)
    (let ((analysis '(:beg 4 :end 7 :lang css :syntax scss :position declaration-start)))
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (_) analysis) :revision #'ignore))
      (should (equal (plist-get (emmet2-context-analyze t) :abbr) "m10"))
      (save-restriction
        (narrow-to-region 5 8)
        (should-not (emmet2-context-analyze t)))
      (dolist (range '((4 4) (4 99) (8 9)))
        (setq analysis (append (list :beg (car range) :end (cadr range))
                               '(:lang css :syntax scss :position declaration-start)))
        (should-not (emmet2-context-analyze t)))
      (dolist (invalid '((:beg "4" :end 7 :lang css :syntax scss :position declaration-start)
                         (:beg 4 :end 7 :lang css :syntax unknown :position declaration-start)
                         (:beg 4 :end 7 :lang css :syntax scss :position value)))
        (setq analysis invalid)
        (should-error (emmet2-context-analyze t) :type 'emmet2-error))
      (setq-local emmet2-context-provider (list :analyze #'ignore))
      (should-error (emmet2-context-analyze) :type 'emmet2-error))))

(ert-deftest emmet2-host-descriptor-context-reaches-choices-and-expansion ()
  (dolist (lang '(css css-in-js))
    (with-temp-buffer
      (insert "sr")
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (_) (list :beg 1 :end 3 :lang lang
                                                   :syntax (if (eq lang 'css) 'css 'jsx)
                                                   :position 'declaration-start :at-rule "@font-face"))
                        :revision #'ignore))
      (let* ((analysis (emmet2-context-analyze t))
             (direct (emmet2-expand-analysis analysis))
             (capf (emmet2-capf))
             (rows (funcall (plist-get (nthcdr 3 capf) :affixation-function)
                            (all-completions "sr" (nth 2 capf)))))
        (should (equal (plist-get direct :text) (if (eq lang 'css) "src: ;" "src: ")))
        (should (equal (cadar rows) (plist-get direct :text)))))))

(ert-deftest emmet2-host-public-expansion-preserves-layout-fields-and-source ()
  (emmet2-host-test--with-completion "@el"
    (let* ((analysis (emmet2-context-analyze))
           (snapshot (emmet2-insert-snapshot analysis))
           (result (emmet2-expand-analysis analysis)))
      (should (equal (buffer-string) ".a{@el}"))
      (should (equal (plist-get result :text) "@else {\n     \n   }"))
      (should (= (length (plist-get result :fields)) 1))
      (emmet2-insert snapshot result)
      (should (equal (buffer-substring (line-beginning-position) (point)) "     "))
      (should (looking-at "\n"))
      (undo-boundary) (undo)
      (should (equal (buffer-string) ".a{@el}"))
      (setq analysis (plist-put analysis :indent-width 0))
      (should (equal (plist-get (emmet2-insert-render-options analysis) :indent) ""))
      (should (equal (plist-get (emmet2-expand-analysis analysis) :text) "@else {\n   \n   }"))
      (setq analysis (plist-put analysis :indent-width -1))
      (should-error (emmet2-insert-render-options analysis) :type 'emmet2-error)
      ;; An explicit nil width is optional, like an omitted key.
      (let ((omitted (copy-sequence analysis)))
        (cl-remf omitted :indent-width)
        (should (equal (emmet2-insert-render-options (plist-put analysis :indent-width nil))
                       (emmet2-insert-render-options omitted)))))))

(ert-deftest emmet2-host-dispatcher-works-without-the-minor-mode ()
  (emmet2-host-test--with-completion "m10"
    (emmet2-mode -1)
    (let* ((hooks completion-at-point-functions)
           (data (emmet2-capf)) (props (nthcdr 3 data))
           (candidate (car (all-completions "m10" (nth 2 data)))))
      (funcall (plist-get props :exit-function) candidate 'finished)
      (should (equal (buffer-string) ".a{margin: 10px;}"))
      (should-not emmet2-mode)
      (should-not (emmet2-context-js--owner))
      (should (eq hooks completion-at-point-functions)))))

(ert-deftest emmet2-host-provider-completes-selectors-without-rule-bodies ()
  (dolist (case '(("button::be" "button::before") ("&:af" "&::after") ("::part" "::part()")))
    (with-temp-buffer
      (insert (car case))
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (_)
                                   (list :beg (point-min) :end (point-max)
                                         :lang 'css :syntax 'scss :position 'selector))
                        :revision #'ignore))
      (let ((result (emmet2-expand-analysis (emmet2-context-analyze))))
        (should (equal (plist-get result :text) (cadr case)))
        (should (equal result (emmet2-extensions-css (car case))))))))

(ert-deftest emmet2-host-completion-shares-auto-explicit-preview-and-acceptance ()
  (dolist (explicit '(nil t))
    (emmet2-host-test--with-completion "::b"
      (if explicit
          (let ((completion-in-region-function #'corfu--in-region-1))
            (emmet2-complete) (corfu--exhibit))
        (corfu-auto--complete-deferred))
      (let ((table (nth 2 completion-in-region--data)))
        (insert "e")
        (let ((this-command 'self-insert-command)) (corfu--post-command))
        (should (eq table (nth 2 completion-in-region--data)))
        (should (equal (cadar (cdr (corfu--affixate corfu--candidates))) "::before"))
        (should-not (corfu-popupinfo--get-documentation (car corfu--candidates)))
        (corfu-insert)
        (should (equal (buffer-string) ".a{::before}"))
        (should (looking-at "}"))))))

(ert-deftest emmet2-host-css-fields-start-no-snippet ()
  ;; An active field would highlight typed values and send TAB past the semicolon.
  (emmet2-host-test--with-completion "c"
    (emmet2-test--with-yasnippet t
      (let ((completion-in-region-function #'corfu--in-region-1))
        (emmet2-complete) (corfu--exhibit))
      (corfu-insert)
      (should (equal (buffer-string) ".a{color: ;}"))
      (should (looking-at ";"))
      (should-not (yas-active-snippets))
      (should-not mark-active))))

(ert-deftest emmet2-host-provider-classifies-once-per-revision-and-reuses-prefix ()
  (emmet2-host-test--with-completion "ovh,ta"
    (let ((calls 0) (version 0) expanded
          (expand (symbol-function 'emmet2-css--expand-abbreviation)))
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (automatic)
                                   (cl-incf calls) (emmet2-host-test--analysis automatic))
                        :revision (lambda () version)))
      (cl-letf (((symbol-function 'emmet2-css--expand-abbreviation)
                 (lambda (abbreviation &rest args)
                   (push abbreviation expanded) (apply expand abbreviation args))))
        (let* ((data (emmet2-capf)) (table (nth 2 data)) (props (nthcdr 3 data))
               (candidates (all-completions "ovh,ta" table)))
          (dotimes (_ 3)
            (all-completions "ovh,ta" table)
            (funcall (plist-get props :affixation-function) candidates)
            (funcall (plist-get props :company-doc-buffer) (car candidates)))
          (should (= calls 1))
          (cl-incf version)
          (all-completions "ovh,ta" table)
          (should (= calls 2))
          (insert "c")
          (let* ((candidate (car (all-completions "ovh,tac" table)))
                 (preview (funcall (plist-get props :company-doc-buffer) candidate)))
            (should (= calls 3))
            (should (= (cl-count "ovh" expanded :test #'equal) 1))
            (should (equal (with-current-buffer preview (buffer-string))
                           "overflow: hidden;\ntext-align: center;"))
            (funcall (plist-get props :exit-function) (car candidates) 'finished)
            (should (equal (buffer-string) ".a{ovh,tac}"))
            (funcall (plist-get props :exit-function) candidate 'finished)
            (should (equal (buffer-string) ".a{overflow: hidden;\n   text-align: center;}"))))))))

(ert-deftest emmet2-host-provider-changes-reject-stale-candidates ()
  (dolist (change '(deny dialect indent property rule provider remove))
    (emmet2-host-test--with-completion "ovh,ta"
      (let ((allowed t) (dialect 'scss) (width 2) property rule)
        (setq-local emmet2-context-provider
                    (list :analyze (lambda (automatic)
                                     (when allowed
                                       (append (list :syntax dialect :indent-width width
                                                     :property property :at-rule rule)
                                               (emmet2-host-test--analysis automatic))))
                          :revision (lambda () (list allowed dialect width property rule))))
        (let* ((data (emmet2-capf)) (table (nth 2 data)) (props (nthcdr 3 data))
               (candidate (car (all-completions "ovh,ta" table))))
          (should candidate)
          (pcase change
            ('deny (setq allowed nil)) ('dialect (setq dialect 'css))
            ('indent (setq width 4)) ('property (setq property "display"))
            ('rule (setq rule "@font-face"))
            ('provider (setq-local emmet2-context-provider (copy-sequence emmet2-context-provider)))
            ('remove (setq-local emmet2-context-provider nil)))
          (should-not (funcall (plist-get props :company-doc-buffer) candidate))
          (should-not (all-completions "ovh,ta" table))
          (funcall (plist-get props :exit-function) candidate 'finished)
          (should (equal (buffer-string) ".a{ovh,ta}")))))))

(ert-deftest emmet2-host-choice-search-shares-the-expansion-budget ()
  (emmet2-host-test--with-completion "m10"
    (let ((clock 100.0) (expanded 0)
          (time-function (symbol-function 'float-time))
          (choices-function (symbol-function 'emmet2-css-search))
          (expand-function (symbol-function 'emmet2-engine-stylesheet-render)))
      (cl-letf (((symbol-function 'float-time)
                 (lambda (&optional time) (if time (funcall time-function time) clock)))
                ((symbol-function 'emmet2-css-search)
                 (lambda (&rest args)
                   (prog1 (apply choices-function args) (setq clock (+ clock 2.0)))))
                ((symbol-function 'emmet2-engine-stylesheet-render)
                 (lambda (&rest args) (cl-incf expanded) (apply expand-function args))))
        (let ((data (emmet2-capf)))
          (should data)
          (should-not (all-completions "m10" (nth 2 data)))
          (should (= expanded 0))
          (should (equal (buffer-string) ".a{m10}")))))))

(ert-deftest emmet2-host-long-literal-choice-preserves-display-and-source ()
  (let* ((value (make-string 4090 ?a)) (input (concat "m[" value "]")))
    (emmet2-host-test--with-completion input
      (let* ((data (emmet2-capf))
             (candidates (all-completions input (nth 2 data)))
             (rows (funcall (plist-get (nthcdr 3 data) :affixation-function) candidates)))
        (should rows)
        (should (equal (substring-no-properties (cadar rows)) (concat "margin: " value ";")))
        (should (equal (buffer-string) (concat ".a{" input "}")))))))

(ert-deftest emmet2-host-css-provider-and-builtin-share-expansion-results ()
  (dolist (abbreviation '("m10" "m10+p.5" "bg[none]" "m--gutter" "p1-2" "posa10"
                          "ct['']" "ins32"))
    (ert-info (abbreviation)
      (with-temp-buffer
        (insert ".a { " abbreviation " }") (css-mode) (backward-char 2)
        (let* ((analysis (emmet2-context-analyze t))
               (direct (emmet2-expand-analysis analysis))
               (builtin (emmet2-capf))
               (results (lambda (capf)
                          (mapcar (lambda (choice)
                                    (plist-get (get-text-property 0 'emmet2--choice choice) :result))
                                  (all-completions abbreviation (nth 2 capf)))))
               (expected (funcall results builtin)))
          (should (equal direct (car expected)))
          (setq-local emmet2-context-provider
                      (list :analyze (lambda (_automatic) analysis) :revision (lambda () 'host)))
          (cl-letf (((symbol-function 'emmet2-context-css-analyze)
                     (lambda (&rest _) (error "The external host owns CSS context"))))
            (should (equal (funcall results (emmet2-capf)) expected))
            (should (equal (emmet2-expand-analysis (emmet2-context-analyze)) direct))))))))

(ert-deftest emmet2-host-unitless-values-share-direct-and-completion-output ()
  (dolist (case '(("order1" "order: 1;" "order: 1")
                  ("column-count2" "column-count: 2;" "columnCount: 2")
                  ("grid-row-start2" "grid-row-start: 2;" "gridRowStart: 2")
                  ("fill-opacity.5" "fill-opacity: 0.5;" "fillOpacity: 0.5")))
    (pcase-dolist (`(,mode ,lang ,syntax) '((css-mode css css) (scss-mode css scss)
                                            (fundamental-mode css scss) (fundamental-mode css-in-js jsx)))
      (ert-info ((format "%S %S" mode case))
        (with-temp-buffer
          (funcall mode) (insert ".a { " (car case) " }") (backward-char 2)
          (when (eq mode 'fundamental-mode)
            (setq-local emmet2-context-provider
                        (list :analyze (lambda (_)
                                         (list :beg 6 :end (- (point-max) 2) :lang lang
                                               :syntax syntax :position 'declaration-start))
                              :revision #'ignore)))
          (let* ((source (buffer-string))
                 (expected (if (eq lang 'css-in-js) (caddr case) (cadr case)))
                 (analysis (emmet2-context-analyze t))
                 (capf (emmet2-capf)) (props (nthcdr 3 capf))
                 (choice (car (all-completions (car case) (nth 2 capf)))))
            (should (equal (plist-get (emmet2-expand-analysis analysis) :text) expected))
            (should (equal (cadar (funcall (plist-get props :affixation-function) (list choice))) expected))
            (buffer-enable-undo)
            (funcall (plist-get props :exit-function) choice 'finished)
            (should (equal (buffer-string) (concat ".a { " expected " }")))
            (undo-boundary) (undo)
            (should (equal (buffer-string) source))))))))

(ert-deftest emmet2-host-errors-have-editor-boundaries ()
  (dolist (stage '(:analyze :revision))
    (with-temp-buffer
      (insert "m10")
      (let ((debug-on-error nil))
        (setq-local emmet2-context-provider
                    (list :analyze #'emmet2-host-test--analysis :revision #'ignore))
        (setq-local emmet2-context-provider
                    (plist-put emmet2-context-provider stage (lambda (&rest _) (error "host unavailable"))))
        (should-not (emmet2-capf))
        (let ((failure (should-error (emmet2-complete) :type 'user-error)))
          (should (string-match-p "host unavailable" (error-message-string failure))))))))

(ert-deftest emmet2-host-lazy-failure-invalidates-the-entire-table ()
  (dolist (stage '(table affix preview exit))
    (dolist (explicit '(nil t))
      (emmet2-host-test--with-completion "ovh,ta"
        (let ((failed nil) (calls 0) (debug-on-error nil)
              (emmet2-capf--explicit explicit))
          (setq-local emmet2-context-provider
                      (list :analyze #'emmet2-host-test--analysis
                            :revision (lambda () (cl-incf calls)
                                        (when failed (error "revision unavailable")))))
          (let* ((data (emmet2-capf)) (table (nth 2 data)) (props (nthcdr 3 data))
                 (candidate (car (all-completions "ovh,ta" table)))
                 (callback (lambda ()
                             (pcase stage
                               ('table (all-completions "ovh,ta" table))
                               ('affix (funcall (plist-get props :affixation-function) (list candidate)))
                               ('preview (funcall (plist-get props :company-doc-buffer) candidate))
                               ('exit (funcall (plist-get props :exit-function) candidate 'finished))))))
            (should candidate)
            (setq failed t)
            (if (or explicit (eq stage 'exit))
                (should-error (funcall callback) :type 'user-error)
              (should-not (funcall callback)))
            (setq failed nil)
            (let ((count calls))
              (should-not (all-completions "ovh,ta" table))
              (should-not (funcall (plist-get props :company-doc-buffer) candidate))
              (funcall (plist-get props :exit-function) candidate 'finished)
              (should (= calls count)))
            (should (equal (buffer-string) ".a{ovh,ta}"))
            (should (all-completions "ovh,ta" (nth 2 (emmet2-capf))))))))))

(ert-deftest emmet2-host-render-and-preview-errors-expire-the-table ()
  (dolist (stage '(emmet2-expand-choices emmet2-preview emmet2-insert))
    (emmet2-host-test--with-completion "ovh,ta"
      (let* ((debug-on-error nil) (data (emmet2-capf)) (table (nth 2 data))
             (props (nthcdr 3 data))
             (candidate (unless (eq stage 'emmet2-expand-choices)
                          (car (all-completions "ovh,ta" table)))))
        (cl-letf (((symbol-function stage) (lambda (&rest _) (error "callback unavailable"))))
          (pcase stage
            ('emmet2-expand-choices (should-not (all-completions "ovh,ta" table)))
            ('emmet2-preview (should-not (funcall (plist-get props :company-doc-buffer) candidate)))
            ('emmet2-insert (should-error (funcall (plist-get props :exit-function) candidate 'finished)
                                          :type 'user-error))))
        (should-not (all-completions "ovh,ta" table))
        (should (equal (buffer-string) ".a{ovh,ta}"))))))

(ert-deftest emmet2-host-cancellation-propagates-and-invalidates ()
  (emmet2-host-test--with-completion "m10"
    (let* ((debug-on-error nil) (data (emmet2-capf)) (table (nth 2 data)))
      (cl-letf (((symbol-function 'emmet2-expand-choices) (lambda (&rest _) (signal 'quit nil))))
        (should (eq (condition-case nil (all-completions "m10" table) (quit 'cancelled)) 'cancelled)))
      (should-not (all-completions "m10" table))
      (should (equal (buffer-string) ".a{m10}")))))

(ert-deftest emmet2-host-callback-views-are-restored ()
  (with-temp-buffer
    (insert "xx m10 yy") (goto-char 7)
    (narrow-to-region 4 8)
    (setq-local emmet2-context-provider
                (list :analyze (lambda (_) (widen) (goto-char 1)
                                 '(:beg 4 :end 7 :lang css :syntax scss :position declaration-start))
                      :revision (lambda () (widen) (goto-char 1) 'ready)))
    (should (equal (plist-get (emmet2-context-analyze) :abbr) "m10"))
    (should (emmet2-context-revision))
    (should (equal (list (point) (point-min) (point-max)) '(7 4 8)))))

(ert-deftest emmet2-host-all-contexts-share-the-visible-view-boundary ()
  (with-temp-buffer
    (insert "xx m10 yy") (goto-char 7) (narrow-to-region 4 8)
    (dolist (provided '(nil t))
      (let ((result (list :beg 4 :end 7 :lang 'css :syntax 'scss :position 'declaration-start)))
        (setq-local emmet2-context-provider
                    (and provided (list :analyze (lambda (_) result) :revision #'ignore)))
        (cl-letf (((symbol-function 'emmet2-context-js-region) (lambda () '(javascript 1 10)))
                  ((symbol-function 'emmet2-context-js-analyze) (lambda (&rest _) result)))
          (should (equal (plist-get (emmet2-context-analyze) :abbr) "m10"))
          (setq result (plist-put result :beg 3))
          (should-not (emmet2-context-analyze))
          (setq result (plist-put result :beg 4))
          (setq result (plist-put result :indent-width -1))
          (should-error (emmet2-context-analyze) :type 'emmet2-error))))))

(ert-deftest emmet2-host-debugging-keeps-the-original-error ()
  (with-temp-buffer
    (let ((debug-on-error t) observed)
      (setq-local emmet2-context-provider
                  (list :analyze (lambda (_) (signal 'arith-error '("provider"))) :revision #'ignore))
      (should (catch 'emmet-debug
                (let ((debugger (lambda (&rest args)
                                  (setq observed args)
                                  (throw 'emmet-debug t))))
                  (emmet2-capf))))
      (should (equal observed '(error (arith-error "provider")))))))

(ert-deftest emmet2-host-change-during-batch-render-rejects-all-candidates ()
  (emmet2-host-test--with-completion "m10"
    (let* ((data (emmet2-capf)) (table (nth 2 data)) (called 0)
           (expand (symbol-function 'emmet2-expand-choices)))
      (cl-letf (((symbol-function 'emmet2-expand-choices)
                 (lambda (&rest arguments)
                   (cl-incf called)
                   (prog1 (apply expand arguments)
                     (save-excursion (goto-char (point-max)) (insert " "))))))
        (should-not (all-completions "m10" table)))
      (should (= called 1))
      (should-not (all-completions "m10" table))
      (should (equal (buffer-string) ".a{m10} ")))))

(ert-deftest emmet2-host-css-js-rendering-ignores-search-case-settings ()
  ;; Rendering must not inherit editor search settings.  A raw uppercase PX
  ;; value stays a string; treating it as a scalar would insert invalid JS.
  (dolist (fold '(nil t))
    (dolist (case '(("p[10PX]" . "padding: \"10PX\"")
                    ("p[10px]" . "padding: 10")
                    ("p[010px]" . "padding: \"010px\"")))
      (with-temp-buffer
        (setq-local case-fold-search fold)
        (insert (car case))
        (setq-local emmet2-context-provider
                    (list :analyze (lambda (_)
                                     (list :beg (point-min) :end (point-max)
                                           :lang 'css-in-js :syntax 'jsx
                                           :position 'declaration-start))
                          :revision #'ignore))
        (let* ((data (emmet2-capf)) (props (nthcdr 3 data))
               (choice (car (all-completions (car case) (nth 2 data)))))
          (should choice)
          (should (equal (plist-get (emmet2-expand-analysis (emmet2-context-analyze)) :text)
                         (cdr case)))
          (should (equal (cadar (funcall (plist-get props :affixation-function) (list choice)))
                         (cdr case)))
          (funcall (plist-get props :exit-function) choice 'finished)
          (should (equal (buffer-string) (cdr case))))))))

(provide 'emmet2-host-api-test)
;;; emmet2-host-api-test.el ends here
