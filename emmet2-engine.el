;;; emmet2-engine.el --- Expansion results, errors and deadline -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A canonical result is the plist from `emmet2-result-create': text, fields
;; as (BEG END GROUP DEFAULT) with zero-based character offsets, and the
;; initial cursor.  Groups are positive; markup insertion adds the final exit
;; itself.  The result helpers accept only canonical results.  Call-owned data
;; is created for one expansion and never escapes it except through the
;; returned result.  No function mutates its inputs or reads editor state.

;;; Code:

(require 'cl-lib)

(define-error 'emmet2-error "Emmet expansion failed")
(define-error 'emmet2-parse-error "Invalid Emmet abbreviation" 'emmet2-error)
(define-error 'emmet2-backend-error "Emmet backend failed" 'emmet2-error)
(define-error 'emmet2-result-error "Invalid Emmet result" 'emmet2-error)

(defvar emmet2-engine--deadline nil "Dynamically scoped deadline for one expansion.")
(defvar emmet2-engine--timeout 1.0 "Seconds allowed for a complete expansion.")

(defun emmet2-engine--check-deadline ()
  "Reject an expired expansion deadline."
  (when (and emmet2-engine--deadline (>= (float-time) emmet2-engine--deadline))
    (signal 'emmet2-backend-error '("Expansion deadline exceeded"))))

(defmacro emmet2-engine-with-expansion (&rest body)
  "Run BODY within one shared expansion deadline and return its value.
Nested uses inherit the outermost deadline, `emmet2-engine--timeout' seconds
after it starts.  Signal `emmet2-backend-error' when the deadline has passed
on entry, on exit or at a check inside BODY."
  (declare (indent 0) (debug t))
  `(let ((emmet2-engine--deadline
          (or emmet2-engine--deadline (+ (float-time) emmet2-engine--timeout))))
     (emmet2-engine--check-deadline)
     (prog1 (progn ,@body) (emmet2-engine--check-deadline))))

(autoload 'emmet2-engine-markup-expand "emmet2-engine-markup")
(autoload 'emmet2-engine-stylesheet-expand "emmet2-engine-stylesheet")

(defun emmet2-engine-js-character (character)
  "Return CHARACTER escaped for a JavaScript double-quoted string.
Signal `emmet2-error' for Emacs raw bytes and surrogate code points, which
are not Unicode scalar values."
  (unless (and (<= 0 character #x10ffff) (not (<= #xd800 character #xdfff)))
    (signal 'emmet2-error '("JavaScript output requires Unicode scalar characters")))
  (pcase character
    (?\" "\\\"") (?\\ "\\\\") (?\n "\\n") (?\r "\\r") (?\t "\\t")
    (?\b "\\b") (?\f "\\f")
    ((or #x2028 #x2029) (format "\\u%04x" character))
    (_ (if (< character 32) (format "\\u%04x" character) (char-to-string character)))))

(cl-defun emmet2-engine-expand (abbreviation &key (preset 'html) (indent "\t") (base-indent "") jsx (seed 0) at-rule)
  "Expand ABBREVIATION with PRESET and return a canonical result.
PRESET is html, the default, jsx or stylesheet.  INDENT, a tab by default,
is one nesting level and BASE-INDENT, empty by default, starts every new
line; stylesheet output ignores INDENT.  JSX is nil or, with PRESET jsx, a
plist with :classAttribute \"className\" or \"class\" and optional
:cssModulesObject and :classConstructor strings.  AT-RULE selects descriptor
values for the stylesheet preset.  SEED is an integer for call-local lorem
generation, normalized to 32 bits; it has no effect on stylesheet expansion.
Signal `emmet2-error' for invalid arguments, `emmet2-parse-error' for an
invalid abbreviation and `emmet2-backend-error' when the deadline expires."
  (unless (and (stringp abbreviation) (memq preset '(html jsx stylesheet))
               (stringp indent) (stringp base-indent))
    (signal 'emmet2-error '("Invalid abbreviation, preset or indentation")))
  (unless (integerp seed) (signal 'emmet2-error '("Lorem seed must be an integer")))
  (emmet2-engine-with-expansion
    (if (eq preset 'stylesheet)
        (progn
          (when jsx (signal 'emmet2-error '("JSX options require markup")))
          (emmet2-engine-stylesheet-expand abbreviation :preset preset :indent indent :base-indent base-indent
                                           :at-rule at-rule))
      (emmet2-engine-markup-expand abbreviation :preset preset :indent indent :base-indent base-indent
                                   :jsx jsx :seed seed))))

(defun emmet2-result-create (text &optional fields)
  "Create a canonical result from TEXT and FIELDS.
Each field is (BEG END GROUP DEFAULT): zero-based character offsets into
TEXT, a positive GROUP, and DEFAULT equal to TEXT between BEG and END.
Preserve mirrors and group order, renumber groups densely from one, sort
fields stably by position and derive the initial cursor.  Return
\(:text TEXT :fields FIELDS :cursor CURSOR).  Signal `emmet2-result-error'
for overlapping fields, conflicting mirror defaults or fields inconsistent
with TEXT."
  (unless (and (stringp text) (or (null fields) (proper-list-p fields)))
    (signal 'emmet2-result-error '("Expected text and a proper field list")))
  ;; Size the tables to the field count, usually one, so filling them never grows them.
  (let* ((capacity (max 1 (length fields)))
         (defaults (make-hash-table :test #'eql :size capacity))
         (indices (make-hash-table :test #'eql :size capacity))
         groups (previous-beg 0) (previous-end 0) (next 0) ordered cursor)
    (dolist (field fields)
      (unless (eql (proper-list-p field) 4)
        (signal 'emmet2-result-error '("Expected a four-element field")))
      (pcase-let ((`(,beg ,end ,index ,placeholder) field))
        (unless (and (integerp beg) (integerp end) (integerp index) (> index 0)
                     (<= 0 beg end (length text)) (stringp placeholder)
                     (equal placeholder (substring text beg end)))
          (signal 'emmet2-result-error (list "Invalid field bounds or default" field)))
        (let ((previous (gethash index defaults 'missing)))
          (if (eq previous 'missing)
              (progn (puthash index placeholder defaults) (push index groups))
            (unless (equal previous placeholder)
              (signal 'emmet2-result-error '("Conflicting mirror defaults")))))))
    (dolist (index (sort groups #'<)) (puthash index (cl-incf next) indices))
    (dolist (field (sort (copy-sequence fields) (lambda (a b) (< (car a) (car b)))))
      (pcase-let ((`(,beg ,end ,index ,placeholder) field))
        (when (and (< beg previous-end)
                   (or (< beg end) (> beg previous-beg)))
          (signal 'emmet2-result-error '("Overlapping fields")))
        (when (< beg end) (setq previous-beg beg previous-end end))
        (let ((normalized (gethash index indices)))
          (when (and (= normalized 1) (null cursor)) (setq cursor beg))
          (push (list beg end normalized placeholder) ordered))))
    (list :text text :fields (nreverse ordered) :cursor (or cursor (length text)))))

(defun emmet2-result--group-count (result)
  "Return the number of groups in canonical RESULT."
  (let ((count 0))
    (dolist (field (plist-get result :fields) count)
      (setq count (max count (nth 2 field))))))

(defun emmet2-result-concat (&rest results)
  "Concatenate canonical RESULTS into a new canonical result.
Each result keeps its own groups, numbered after those of earlier RESULTS."
  (let ((offset 0) (groups 0) texts fields)
    (dolist (result results)
      (push (plist-get result :text) texts)
      (dolist (field (plist-get result :fields))
        (pcase-let ((`(,beg ,end ,index ,placeholder) field))
          (push (list (+ offset beg) (+ offset end) (+ groups index) placeholder) fields)))
      (cl-incf offset (length (plist-get result :text)))
      (cl-incf groups (emmet2-result--group-count result)))
    (emmet2-result-create (apply #'concat (nreverse texts)) (nreverse fields))))

(defun emmet2-result-splice (result beg end replacement)
  "Replace RESULT's half-open range BEG..END with canonical REPLACEMENT.
Remove fields fully covered by the range and reject partial overlaps.  Empty
fields at END survive and shift; for insertion, fields at BEG follow the new
text.  New groups precede the first replaced group, or the next field's group
when no group is replaced; surviving source groups keep their relative order.
Return a new canonical result.  Signal `emmet2-result-error' for a range
outside RESULT or a partial field overlap."
  (let* ((text (plist-get result :text))
         (inserted (plist-get replacement :text))
         (groups (emmet2-result--group-count replacement))
         delta before after removed next fields)
    (unless (and (integerp beg) (integerp end) (<= 0 beg end (length text)))
      (signal 'emmet2-result-error '("Splice is outside the result")))
    (setq delta (- (length inserted) (- end beg)))
    (dolist (field (plist-get result :fields))
      (pcase-let ((`(,start ,finish ,index ,placeholder) field))
        (cond
         ((if (= start finish) (< start beg) (<= finish beg)) (push field before))
         ((>= start end)
          (unless next (setq next index))
          (push (list (+ start delta) (+ finish delta) index placeholder) after))
         ((and (>= start beg) (<= finish end))
          (setq removed (min (or removed index) index)))
         (t (signal 'emmet2-result-error '("Splice partially overlaps a field"))))))
    (let ((first (or removed next (1+ (emmet2-result--group-count result)))))
      (cl-labels ((source-field (field)
                    (pcase-let ((`(,start ,finish ,index ,placeholder) field))
                      (list start finish (if (>= index first) (+ index groups) index)
                            placeholder))))
        (setq fields (mapcar #'source-field (nreverse before)))
        (setq fields
              (nconc fields
                     (mapcar (lambda (field)
                               (pcase-let ((`(,start ,finish ,index ,placeholder) field))
                                 (list (+ beg start) (+ beg finish) (+ first index -1) placeholder)))
                             (plist-get replacement :fields))
                     (mapcar #'source-field (nreverse after))))))
    (emmet2-result-create
     (concat (substring text 0 beg) inserted (substring text end)) fields)))

(provide 'emmet2-engine)
;;; emmet2-engine.el ends here
