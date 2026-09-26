;;; emmet2-extract.el --- Bounded abbreviation extraction -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Scan a host-owned region without consulting mode or parser state.  This
;; module alone computes abbreviation bounds; it never changes the buffer.

;;; Code:

(require 'cl-lib)

(defun emmet2-extract (region-beg region-end)
  "Return (:beg BEG :end END :abbr TEXT) at point within the given region.
REGION-BEG and REGION-END constrain host syntax.  Only the current line is
scanned.  Balanced groups include spaces and quotes; unmatched host closing
delimiters are excluded.  Point can be anywhere in the token, including its
start and end.  Return nil outside a token."
  (let ((position (point))
        (begin (max region-beg (line-beginning-position)))
        (limit (min region-end (line-end-position))))
    (when (<= begin position limit)
      (save-excursion
        (goto-char begin)
        (let (token stack quote escaped result)
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
                 ((or (memq character '(?\s ?\t ?\n ?\r ?\; ?= ?< ?\" ?\' ?` ?} ?\] ?\)))
                      (and (eq character ?,)
                           (or (= (1+ (point)) limit)
                               (memq (char-after (1+ (point))) '(?\s ?\t ?} ?\))))))
                  (finish))
                 (t (unless token (setq token (point))))))
              (unless result (forward-char)))
            (unless result (finish)))
          result)))))

(provide 'emmet2-extract)
;;; emmet2-extract.el ends here
