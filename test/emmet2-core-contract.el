;;; emmet2-core-contract.el --- Backend-independent oracle assertions -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'json)
(require 'emmet2-engine)

(defun emmet2-core-test--json (path)
  "Read JSON PATH relative to the repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path emmet2-test-root))
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(defun emmet2-core-test--check (expand)
  "Check all frozen core results and errors through EXPAND."
  (let ((inputs (emmet2-core-test--json "test/fixtures/core-inputs.json"))
        (expected (make-hash-table :test #'equal)) (checked 0))
    (dolist (entry (append (emmet2-core-test--json "test/fixtures/oracle/markup.json")
                          (emmet2-core-test--json "test/fixtures/oracle/stylesheet.json")))
      (puthash (alist-get 'id entry) entry expected))
    (dolist (input inputs)
      (let* ((id (alist-get 'id input)) (entry (gethash id expected))
             (wanted (alist-get 'result entry)) (failure (alist-get 'error entry))
             (jsx (alist-get 'jsx input))
             (arguments (list (alist-get 'abbreviation input)
                              :preset (intern (alist-get 'preset input))
                              :indent (or (alist-get 'indent input) "\t")
                              :base-indent (or (alist-get 'baseIndent input) "")
                              :jsx (and jsx (list :classAttribute (alist-get 'classAttribute jsx)
                                                 :cssModulesObject (alist-get 'cssModulesObject jsx)
                                                 :classConstructor (alist-get 'classConstructor jsx))))))
        (ert-info (id)
          (should entry)
          (if failure
              (let ((error (should-error (apply expand arguments) :type 'emmet2-parse-error)))
                (should (equal (cdr error) (list (alist-get 'message failure) (alist-get 'position failure)))))
            (should (equal (apply expand arguments)
                           (list :text (alist-get 'text wanted) :fields (alist-get 'fields wanted)
                                 :cursor (alist-get 'cursor wanted))))))
        (cl-incf checked)))
    (should (= checked (hash-table-count expected)))
    (should (> checked 0))))

(provide 'emmet2-core-contract)
;;; emmet2-core-contract.el ends here
