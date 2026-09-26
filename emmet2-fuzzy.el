;;; emmet2-fuzzy.el --- Emmet fuzzy matching -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Algorithm derived from Emmet 2.4.11 (MIT); see NOTICE and vendor/emmet-LICENSE.

;;; Commentary:
;; Preserve upstream scoring, partial matching and later-item tie breaks.
;; Syntax-specific prefixes and aliases belong to the caller.

;;; Code:

(require 'cl-lib)

(defun emmet2-fuzzy-score (abbreviation candidate &optional partial)
  "Score ABBREVIATION against CANDIDATE, allowing an unmatched suffix if PARTIAL."
  (let* ((a (downcase abbreviation)) (b (downcase candidate))
         (a-len (length a)) (b-len (length b)))
    (cond
     ((equal a b) 1.0)
     ((or (zerop a-len) (zerop b-len) (/= (aref a 0) (aref b 0))
          (and (not partial) (> a-len b-len))) 0.0)
     (t
      (let* ((maximum (max a-len b-len)) (delta (abs (- a-len b-len)))
             (score maximum) (i 1) (j 1) failed)
        (while (and (< i a-len) (not failed))
          (let (found acronym)
            (while (and (< j b-len) (not found))
              (if (= (aref a i) (aref b j))
                  (setq found t score (+ score (- maximum (if acronym i j))))
                (setq acronym (= (aref b j) ?-) j (1+ j))))
            ;; Upstream intentionally reuses the matched candidate position.
            (if found (cl-incf i) (setq failed t))))
        (if (and failed (not partial)) 0.0
          (/ (* score (/ (float i) maximum))
             (/ (- (* maximum (1+ maximum)) (* delta (1+ delta))) 2.0))))))))

(defun emmet2-fuzzy-find (abbreviation candidates &optional min-score partial key)
  "Find the best CANDIDATES item for ABBREVIATION, or nil.
MIN-SCORE defaults to zero.  PARTIAL allows an unmatched abbreviation suffix.
KEY, when non-nil, extracts the string to score from each item.  Exact hits
return immediately; equal nonzero scores prefer the later item."
  (let ((maximum 0.0) best)
    (catch 'exact
      (dolist (candidate candidates)
        (let ((score (emmet2-fuzzy-score abbreviation
                                         (if key (funcall key candidate) candidate) partial)))
          (when (= score 1) (throw 'exact candidate))
          (when (and (> score 0) (>= score maximum))
            (setq maximum score best candidate))))
      (and (>= maximum (or min-score 0)) best))))

(provide 'emmet2-fuzzy)
;;; emmet2-fuzzy.el ends here
