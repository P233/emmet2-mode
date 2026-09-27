;;; emmet2-lorem-contract.el --- Backend-independent lorem assertions -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)

(defun emmet2-lorem-test--json (path)
  "Read test JSON PATH independently of either engine."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path emmet2-test-root))
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(defun emmet2-lorem-test--entries (sentence vocabulary)
  "Read SENTENCE as vocabulary entries, preserving multiword phrases."
  (let ((text (downcase (string-trim (replace-regexp-in-string "," "" sentence)))) entries)
    (while (not (string-empty-p text))
      (let ((word (cl-find-if (lambda (word) (or (equal text word) (string-prefix-p (concat word " ") text)))
                              vocabulary)))
        (should word)
        (push word entries)
        (setq text (string-trim-left (substring text (length word))))))
    (nreverse entries)))

(defun emmet2-lorem-test--paragraph (text contract)
  "Check paragraph TEXT against independently authored structural CONTRACT."
  (let* ((language (alist-get 'language contract))
         (filename (cdr (assoc language '(("latin" . "latin") ("ru" . "russian") ("sp" . "spanish")))))
         (dictionary (emmet2-lorem-test--json (format "data/emmet/lorem/%s.json" filename)))
         (common (alist-get 'common dictionary))
         (vocabulary (sort (delete-dups (append (copy-sequence common) (copy-sequence (alist-get 'words dictionary))))
                           (lambda (a b) (> (length a) (length b)))))
         (sentences (split-string text "[.!?]" t " +"))
         (entries (mapcar (lambda (sentence) (emmet2-lorem-test--entries sentence vocabulary)) sentences))
         (count (apply #'+ (mapcar #'length entries))))
    (should (string-match-p "[.!?]\\'" text))
    (should-not (string-match-p "[.!?][.!?]\\|, *[.!?]\\|  " text))
    (dolist (sentence sentences)
      (should (equal (substring sentence 0 1) (upcase (substring sentence 0 1)))))
    (pcase-let ((`(,min ,max) (alist-get 'count contract)))
      (should (<= min count max)))
    (if (equal (alist-get 'opening contract) "common")
        (progn
          (should (equal (car entries) (seq-take common (min count (length common)))))
          (should (eq (aref text (string-match "[.!?]" text)) ?.)))
      (should-not (equal (caar entries) (car common))))
    (dolist (sentence entries)
      (should (= (length sentence) (length (delete-dups (copy-sequence sentence))))))))

(defun emmet2-lorem-test--check-result (fixture result)
  "Check RESULT against structural FIXTURE without calling either engine."
  (ert-info ((format "%s %s" (alist-get 'id fixture) (alist-get 'abbreviation fixture)))
      (let* ((text (plist-get result :text))
             (parts (split-string (alist-get 'template fixture) "~"))
             (contracts (alist-get 'paragraphs fixture))
             (fields (plist-get result :fields))
             (position (length (car parts))))
        (should (string-prefix-p (pop parts) text))
        (should (= (length parts) (length contracts)))
        (cl-mapc
         (lambda (suffix contract)
           (let ((end (if (string-empty-p suffix) (length text) (string-search suffix text position))))
             (should end)
             (emmet2-lorem-test--paragraph (substring text position end) contract)
             (setq position (+ end (length suffix)))))
         parts contracts)
        (should (= position (length text)))
        (should (equal (mapcar (lambda (field) (nth 3 field)) fields) (alist-get 'fields fixture)))
        (dolist (field fields)
          (should (equal (substring text (nth 0 field) (nth 1 field)) (nth 3 field))))
        (should (= (plist-get result :cursor) (if fields (caar fields) (length text)))))))

(defun emmet2-lorem-test--run (expand)
  "Run the same structural fixtures through independently chosen EXPAND."
  (dolist (fixture (emmet2-lorem-test--json "test/fixtures/lorem.json"))
    (emmet2-lorem-test--check-result
     fixture (funcall expand (alist-get 'abbreviation fixture)
                      :preset (intern (or (alist-get 'preset fixture) "html"))
                      :indent (or (alist-get 'indent fixture) "\t")
                      :base-indent (or (alist-get 'baseIndent fixture) "")))))

(provide 'emmet2-lorem-contract)
;;; emmet2-lorem-contract.el ends here
