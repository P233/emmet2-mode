;;; emmet2-css-data.el --- Buffer-independent CSS metadata queries -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Answer CSS name and value queries from data/css-data.json, which carries
;; documentation.  Callers pass the kind of name, the property and the
;; enclosing at-rule; nothing here reads a buffer or enables a mode.  Value
;; lists merge this file's documented values with the keyword sets that
;; expansion reads from data/css-index.json through emmet2-css-search.  Both
;; files are generated together by test/update-web-data.mjs from pinned sources.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emmet2-fuzzy)
(require 'emmet2-css-search)

(defconst emmet2-css-data--data
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "data/css-data.json"
                       (file-name-directory (or load-file-name buffer-file-name))))
    (let ((data (json-parse-buffer :object-type 'alist :array-type 'list))
          (strings (make-hash-table :test #'equal)))
      ;; Keep the source file's browser support, references and syntax metadata
      ;; on disk.  Completion needs only names, documentation and value scope.
      (cl-labels
          ((share (object) (emmet2-css-search--share object strings))
           (entry (item)
             (let ((description (alist-get 'description item)))
               (list (share (assq 'name item))
                     (cons 'description
                           (share (if (stringp description) description
                                    (alist-get 'value description)))))))
           (property (item)
             (append (entry item)
                     (list (share (assq 'atRule item)) (share (assq 'restrictions item))
                           (cons 'values (mapcar #'entry (alist-get 'values item)))))))
        (list (cons 'properties (mapcar #'property (alist-get 'properties data)))
              (cons 'atDirectives (mapcar #'entry (alist-get 'atDirectives data)))
              (cons 'pseudoClasses (mapcar #'entry (alist-get 'pseudoClasses data)))
              (cons 'pseudoElements (mapcar #'entry (alist-get 'pseudoElements data)))))))
  "Immutable CSS completion metadata loaded once with this library.
Fields unused by completion are discarded after reading the source file.
Equal strings are shared and read-only.")

(defun emmet2-css-data--property-available-p (entry at-rule)
  "Whether property ENTRY is ordinary or a descriptor admitted by AT-RULE."
  (or (not (alist-get 'atRule entry))
      (emmet2-css-search-property-p (alist-get 'name entry))
      (equal (alist-get 'atRule entry) at-rule)))

(defun emmet2-css-data--entry (entry)
  "Return a (NAME . DOCUMENTATION) pair for metadata ENTRY."
  (let ((description (alist-get 'description entry)))
    (cons (alist-get 'name entry)
          (if (stringp description) description (alist-get 'value description)))))

(defun emmet2-css-data--values (property at-rule)
  "Return CSS values for PROPERTY within AT-RULE, without host symbols."
  (let* ((property (downcase (or property "")))
         (entry (cl-find-if
                 (lambda (item)
                   (and (equal (alist-get 'name item) property)
                        (emmet2-css-data--property-available-p item at-rule)))
                 (alist-get 'properties emmet2-css-data--data)))
         (restrictions (alist-get 'restrictions entry))
         (values (mapcar #'emmet2-css-data--entry (alist-get 'values entry)))
         (extra (emmet2-css-search-value-names (and entry property) at-rule)))
    (when (cl-intersection restrictions '("length" "percentage" "number" "integer" "angle" "time") :test #'equal)
      (setq extra (append '("0" "calc()" "min()" "max()" "clamp()") extra)))
    ;; Vendor or obsolete properties may lack indexed values; descriptors must not borrow property defaults.
    (unless (alist-get 'atRule entry)
      (when (member "color" restrictions)
        (setq extra (append (emmet2-css-search-value-names "color") extra)))
      (when (member "image" restrictions)
        (setq extra (append (emmet2-css-search-value-names "background-image") extra))))
    (when (cl-intersection restrictions '("image" "url") :test #'equal)
      (push "url()" extra))
    (append values (mapcar (lambda (name) (cons name nil)) extra))))

(cl-defun emmet2-css-data-query (kind &key (query "") property at-rule vendor)
  "Return (NAME . DOCUMENTATION) candidates for CSS KIND matching QUERY.
KIND is `property', `value', `at-rule' or `pseudo'; any other value signals
an error.  PROPERTY selects the values; an unknown PROPERTY gets the
CSS-wide keywords, var() and env().  AT-RULE, a name such as \"@font-face\"
in any case, admits that rule's descriptors and their values.  VENDOR also
admits vendor names, which are otherwise omitted.  QUERY uses
`emmet2-fuzzy-match'; an empty QUERY, the default, returns all candidates in
name order.  Exact and stronger matches rank first with stable name-order
ties.  DOCUMENTATION may be nil.

All context is explicit: no buffer, parser, mode or completion frontend is
required.  Returned lists and pairs are fresh; name and documentation strings
are shared, read-only metadata.  No query results are retained."
  (let* ((rule (and at-rule (downcase at-rule)))
         (entries
          (pcase kind
            ('property
             (mapcar #'emmet2-css-data--entry
                     (cl-remove-if-not
                      (lambda (entry) (emmet2-css-data--property-available-p entry rule))
                      (alist-get 'properties emmet2-css-data--data))))
            ('value (emmet2-css-data--values property rule))
            ('at-rule (mapcar #'emmet2-css-data--entry (alist-get 'atDirectives emmet2-css-data--data)))
            ('pseudo (mapcar #'emmet2-css-data--entry
                             (append (alist-get 'pseudoClasses emmet2-css-data--data)
                                     (alist-get 'pseudoElements emmet2-css-data--data))))
            (_ (error "Unknown CSS candidate kind: %S" kind))))
         (seen (make-hash-table :test #'equal)) unique)
    (dolist (entry entries)
      (let ((name (car entry)))
        (when (and (not (gethash name seen))
                   (or vendor (not (string-match-p "\\`[:@]*-" name))))
          (puthash name t seen)
          (push entry unique))))
    (emmet2-fuzzy-filter query (sort unique (lambda (a b) (string< (car a) (car b)))) #'car)))

(provide 'emmet2-css-data)
;;; emmet2-css-data.el ends here
