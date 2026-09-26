;;; emmet2-engine-node.el --- Temporary single-request Node channel -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; INTERIM since 2026-09-26, until S6/S7 pass complete Elisp suites.
;; One session process, one in-flight request, no queue or in-request retries.
;; A request's filter state belongs to its process, never to a source buffer.

;;; Code:

(require 'json)
(require 'emmet2-engine)

(defvar emmet2-node--server-file
  (expand-file-name "emmet2-node-server.mjs" (file-name-directory load-file-name)))
(defvar emmet2-node--process nil)
(defvar emmet2-node--busy nil)

(cl-defstruct (emmet2-node--request (:constructor emmet2-node--request-create))
  id chunks response failure)

(defun emmet2-node-stop (&optional process)
  "Dispose of the owned Node PROCESS and its diagnostic buffer.
With no argument, stop the current session process."
  (when-let* ((process (or process emmet2-node--process)))
    (when (eq process emmet2-node--process) (setq emmet2-node--process nil))
    (set-process-filter process #'ignore)
    (set-process-sentinel process #'ignore)
    (when (process-live-p process) (delete-process process))
    (when-let* ((stderr (process-get process 'emmet2-stderr))
                ((buffer-live-p stderr)))
      (when-let* ((pipe (get-buffer-process stderr))) (delete-process pipe))
      (kill-buffer stderr))))

(defun emmet2-node--fail (process message)
  "Reject PROCESS's current request with MESSAGE, then dispose of the channel."
  (when-let* ((request (process-get process 'emmet2-request)))
    (setf (emmet2-node--request-failure request) message))
  (emmet2-node-stop process))

(defun emmet2-node--filter (process chunk)
  "Accumulate one complete JSON line from PROCESS's CHUNK."
  (let ((request (process-get process 'emmet2-request)))
    (cond
     ((or (null request) (emmet2-node--request-response request))
      (emmet2-node--fail process "Unexpected output outside a pending response"))
     ((string-search "\n" chunk)
      (let ((newline (string-search "\n" chunk)))
        (if (/= newline (1- (length chunk)))
            (emmet2-node--fail process "Unexpected data after response line")
          (push (substring chunk 0 newline) (emmet2-node--request-chunks request))
          (setf (emmet2-node--request-response request)
                (apply #'concat (nreverse (emmet2-node--request-chunks request)))
                (emmet2-node--request-chunks request) nil))))
     (t (push chunk (emmet2-node--request-chunks request))))))

(defun emmet2-node--sentinel (process event)
  "Record incomplete PROCESS termination described by EVENT."
  (unless (process-live-p process)
    (when-let* ((request (process-get process 'emmet2-request))
                ((null (emmet2-node--request-response request))))
      (let* ((stderr (process-get process 'emmet2-stderr))
             (diagnostic (when (buffer-live-p stderr)
                           (with-current-buffer stderr
                             (string-trim (buffer-substring-no-properties
                                           (max (point-min) (- (point-max) 4096)) (point-max)))))))
        (setf (emmet2-node--request-failure request)
              (concat "Node exited: " (string-trim event)
                      (when (and diagnostic (not (string-empty-p diagnostic)))
                        (concat ": " diagnostic))))))
    (emmet2-node-stop process)))

(defun emmet2-node--start ()
  "Return the session process, starting it locally on demand."
  (unless (process-live-p emmet2-node--process)
    (emmet2-node-stop)
    (let ((stderr (generate-new-buffer " *emmet2-node-stderr*"))
          (default-directory (file-name-directory emmet2-node--server-file))
          process)
      (unwind-protect
          (progn
            (setq process
                  (make-process :name "emmet2-node" :buffer nil
                                :command (list "node" emmet2-node--server-file)
                                :connection-type 'pipe :coding 'utf-8-unix :noquery t
                                :filter #'emmet2-node--filter :sentinel #'emmet2-node--sentinel
                                :stderr stderr))
            (process-put process 'emmet2-stderr stderr)
            (setq emmet2-node--process process))
        (unless process (kill-buffer stderr)))))
  emmet2-node--process)

(defun emmet2-node--decode (line id abbreviation)
  "Validate response LINE for ID and ABBREVIATION at the IPC boundary.
Return (result . RESULT) or (parse MESSAGE POSITION); protocol faults signal."
  (condition-case error
      (let* ((response (json-parse-string line :object-type 'alist :array-type 'list
                                         :null-object :null :false-object :false))
             (has-result (assq 'result response))
             (has-error (assq 'error response))
             (result (alist-get 'result response))
             (failure (alist-get 'error response)))
        (unless (and (eql (alist-get 'id response) id) (not (eq (not has-result) (not has-error))))
          (error "Invalid response envelope or request ID"))
        (if has-result
            (let ((canonical (progn
                               (unless (and (assq 'text result) (assq 'fields result) (assq 'cursor result))
                                 (error "Missing result fields"))
                               (emmet2-result-create (alist-get 'text result) (alist-get 'fields result)))))
              (unless (and (equal (plist-get canonical :fields) (alist-get 'fields result))
                           (eql (plist-get canonical :cursor) (alist-get 'cursor result)))
                (error "Noncanonical fields or cursor"))
              (cons 'result canonical))
          (let ((kind (alist-get 'kind failure)) (message (alist-get 'message failure))
                (position (alist-get 'position failure)))
            (unless (stringp message) (error "Invalid error message"))
            (cond
             ((equal kind "backend") (signal 'emmet2-backend-error (list message)))
             ((and (equal kind "parse") (integerp position) (<= 0 position (length abbreviation)))
              (list 'parse message position))
             (t (error "Invalid error kind or position"))))))
    (emmet2-backend-error (signal (car error) (cdr error)))
    (error (signal 'emmet2-backend-error (list (concat "Invalid Node response: " (error-message-string error)))))))

(defun emmet2-engine-node-expand (abbreviation preset indent base-indent)
  "Expand ABBREVIATION using PRESET, INDENT and BASE-INDENT over owned stdio.
Called by `emmet2-engine-expand' with an active expansion deadline."
  (when emmet2-node--busy (signal 'emmet2-backend-error '("Reentrant Node expansion")))
  (let ((emmet2-node--busy t) process request complete)
    (unwind-protect
        (condition-case error
            (progn
              (emmet2-engine--check-deadline)
              (setq process (emmet2-node--start))
              (let ((id (1+ (or (process-get process 'emmet2-sequence) 0))))
                (process-put process 'emmet2-sequence id)
                (setq request (emmet2-node--request-create :id id))
                (process-put process 'emmet2-request request)
                (emmet2-engine--check-deadline)
                (process-send-string
                 process (concat (json-serialize
                                  `(:id ,id :abbreviation ,abbreviation :preset ,(symbol-name preset)
                                        :indent ,indent :baseIndent ,base-indent)) "\n"))
                (while (and (not (emmet2-node--request-response request))
                            (not (emmet2-node--request-failure request)))
                  (emmet2-engine--check-deadline)
                  (unless (process-live-p process)
                    (signal 'emmet2-backend-error '("Node exited before completing the response")))
                  (accept-process-output process (max 0 (min 0.05 (- emmet2-engine--deadline (float-time)))))))
              (when-let* ((failure (emmet2-node--request-failure request)))
                (signal 'emmet2-backend-error (list failure)))
              (let ((decoded (emmet2-node--decode (emmet2-node--request-response request)
                                                 (emmet2-node--request-id request) abbreviation)))
                (emmet2-engine--check-deadline)
                (setq complete t)
                (if (eq (car decoded) 'parse)
                    (signal 'emmet2-parse-error (cdr decoded))
                  (cdr decoded))))
          (emmet2-error (signal (car error) (cdr error)))
          (error (signal 'emmet2-backend-error (list (error-message-string error)))))
      (when process
        (process-put process 'emmet2-request nil)
        (unless complete (emmet2-node-stop process))))))

(defun emmet2-engine-node-unload-function ()
  "Stop the temporary backend when unloading this feature."
  (emmet2-node-stop)
  (remove-hook 'kill-emacs-hook #'emmet2-node-stop)
  nil)

(add-hook 'kill-emacs-hook #'emmet2-node-stop)
(provide 'emmet2-engine-node)
;;; emmet2-engine-node.el ends here
