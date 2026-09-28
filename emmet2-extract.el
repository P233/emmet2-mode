;;; emmet2-extract.el --- Bounded abbreviation extraction -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Scan a host-owned region without consulting mode or parser state.  This
;; module alone computes abbreviation bounds; it never changes the buffer.

;;; Code:

(require 'cl-lib)

(defconst emmet2-extract--tag
  (concat "</?\\(?:[A-Za-z][-A-Za-z0-9:._]*"
          "\\(?:[ \t]+\\(?:[^<>\"'{}]\\|\"[^\"]*\"\\|'[^']*'\\|{[^{}]*}\\)*\\)?\\)?/?>")
  "An authored HTML or JSX tag, whose name and `>' are never Emmet syntax.")

(defun emmet2-extract--tag-end ()
  "Return the end of an authored tag starting at point, or nil."
  (save-match-data (when (looking-at emmet2-extract--tag) (match-end 0))))

(defun emmet2-extract (region-beg region-end &optional syntax)
  "Return (:beg BEG :end END :abbr TEXT) at point within the given region.
REGION-BEG and REGION-END constrain host syntax.  Only the current line is
scanned.  Balanced groups include spaces and quotes; unmatched host closing
delimiters and authored tags are excluded.  Point can be anywhere in the
token, including its start and end.  Return nil outside a token.  SYNTAX
`css' treats comments and top-level or unmatched closing braces as host
boundaries and retains property-separating commas, including a pending one;
balanced raw groups retain their contents."
  (let ((position (point))
        (begin (max region-beg (line-beginning-position)))
        (limit (min region-end (line-end-position))))
    (when (<= begin position limit)
      (save-excursion
        (goto-char begin)
        (let (token stack quote escaped result tag-end)
          (cl-labels ((finish ()
                        (when (and token (<= token position (point)))
                          (setq result (list :beg token :end (point)
                                             :abbr (buffer-substring-no-properties
                                                    token (point)))))
                        (setq token nil stack nil quote nil escaped nil)))
            (while (and (< (point) limit) (not result))
              (let ((character (char-after)))
                (cond
                 (escaped (setq escaped nil))
                 ((and token (eq character ?\\)) (setq escaped t))
                 (quote (when (eq character quote) (setq quote nil)))
                 ((and (eq syntax 'css)
                       (or (and (not stack) (eq character ?{))
                           (and (eq character ?}) (not (eq (car stack) ?})))))
                  (finish))
                 ((and stack (not (eq (car stack) ?}))
                       (memq character '(?\" ?\')))
                  (setq quote character))
                 ((and stack (eq character (car stack))) (pop stack))
                 ((eq (car stack) ?})
                  ;; Quotes, brackets and parentheses in Emmet text are
                  ;; literal.  Only braces nest (escapes were handled above).
                  (when (eq character ?{) (push ?} stack)))
                 ((memq character '(?\[ ?\( ?{))
                  ;; An initial { belongs to the host.  Emmet text attaches to
                  ;; a tag/token, while [] and () can begin an abbreviation.
                  (if (and (eq character ?{) (not token))
                      nil
                    (unless token (setq token (point)))
                    (push (pcase character (?\[ ?\]) (?\( ?\)) (_ ?})) stack)))
                 (stack nil)
                 ((and (eq syntax 'css) (< (1+ (point)) limit) (looking-at "/\\*"))
                  (finish)
                  (unless result
                    (forward-char 2)
                    (goto-char (1- (or (search-forward "*/" limit t) limit)))))
                 ((and (eq syntax 'css) (< (1+ (point)) limit) (looking-at "\\*/"))
                  ;; The current line may begin inside a multiline comment.
                  (finish)
                  (unless result (forward-char)))
                 ((and (eq character ?<) (setq tag-end (emmet2-extract--tag-end)))
                  (finish)
                  (unless result (goto-char (1- (min limit tag-end)))))
                 ((or (memq character '(?\s ?\t ?\n ?\r ?\; ?= ?< ?\" ?\' ?` ?} ?\] ?\)))
                      (and (not (eq syntax 'css)) (eq character ?,)
                           (or (= (1+ (point)) limit)
                               (memq (char-after (1+ (point))) '(?\s ?\t ?} ?\))))))
                  (finish))
                 (t (unless token (setq token (point))))))
              (unless result (forward-char)))
            (unless result (finish)))
          result)))))

(provide 'emmet2-extract)
;;; emmet2-extract.el ends here
