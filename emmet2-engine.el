;;; emmet2-engine.el --- Pure expansion result contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Offsets count characters, not bytes or buffer positions.  Only positive
;; groups are editable fields; insertion creates the final exit separately.
;; Callers pass canonical results to transformations.  No function mutates its
;; inputs or reads editor state.

;;; Code:

(require 'cl-lib)

(define-error 'emmet2-error "Emmet expansion failed")
(define-error 'emmet2-parse-error "Invalid Emmet abbreviation" 'emmet2-error)
(define-error 'emmet2-backend-error "Emmet backend failed" 'emmet2-error)
(define-error 'emmet2-result-error "Invalid Emmet result" 'emmet2-error)

(defvar emmet2-engine--deadline nil "Dynamically scoped deadline for one expansion.")
(defvar emmet2-engine--timeout 1.0 "Seconds allowed for a complete Node expansion.")

(defun emmet2-engine--check-deadline ()
  "Reject an expired expansion deadline."
  (when (and emmet2-engine--deadline (>= (float-time) emmet2-engine--deadline))
    (signal 'emmet2-backend-error '("Expansion deadline exceeded"))))

(defmacro emmet2-engine-with-expansion (&rest body)
  "Run BODY within one shared expansion deadline, including nested core calls."
  (declare (indent 0) (debug t))
  `(let ((emmet2-engine--deadline
          (or emmet2-engine--deadline (+ (float-time) emmet2-engine--timeout))))
     (emmet2-engine--check-deadline)
     (prog1 (progn ,@body) (emmet2-engine--check-deadline))))

(autoload 'emmet2-engine-node-expand "emmet2-engine-node")

(cl-defun emmet2-engine-expand (abbreviation &key (preset 'html) (indent "\t") (base-indent "") jsx)
  "Expand ABBREVIATION with PRESET and the internal rendering parameters.
PRESET is html, jsx or stylesheet.  INDENT and BASE-INDENT are literal strings.
JSX is nil or the internal structured JSX extension options.
Return a canonical result.  The Node backend is temporary until S6/S7 pass."
  (unless (and (stringp abbreviation) (memq preset '(html jsx stylesheet))
               (stringp indent) (stringp base-indent))
    (signal 'emmet2-error '("Invalid abbreviation, preset or indentation")))
  (emmet2-engine-with-expansion
    (emmet2-engine-node-expand abbreviation preset indent base-indent jsx)))

(defun emmet2-result-create (text &optional fields)
  "Create a canonical result from TEXT and FIELDS.
Each field is (BEG END INDEX PLACEHOLDER), using zero-based character offsets.
Preserve mirrors and group priority, renumber groups densely from one, sort
fields stably by position and derive the initial cursor.  Reject overlapping
fields, conflicting mirror defaults or offsets inconsistent with TEXT."
  (unless (and (stringp text) (or (null fields) (proper-list-p fields)))
    (signal 'emmet2-result-error '("Expected text and a proper field list")))
  (let ((defaults (make-hash-table :test #'eql))
        (indices (make-hash-table :test #'eql))
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
  "Concatenate canonical RESULTS, keeping each result's groups independent."
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
when no group is replaced; surviving source groups keep their relative order."
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
