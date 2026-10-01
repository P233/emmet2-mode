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

(defun emmet2-extract-css-pseudo (text)
  "Return the index of the trailing pseudo chain in CSS TEXT, or nil.
Ignore escaped colons and colons inside attributes or function arguments.
Selector lists and combinators start a new compound; its authored prefix
stays literal.  This identifies syntax, not whether the host permits it."
  (when (string-search ":" text)
    (catch 'invalid
      (let ((i 0) pseudo stack quote escaped)
        (while (< i (length text))
          (let ((ch (aref text i)))
            (cond
             (escaped (setq escaped nil))
             ((eq ch ?\\) (setq escaped t))
             (quote (when (eq ch quote) (setq quote nil)))
             ((and stack (memq ch '(?\" ?\'))) (setq quote ch))
             ((eq ch ?\[) (unless stack (setq pseudo nil)) (push ?\] stack))
             ((eq ch ?\()
              (unless (or stack pseudo) (throw 'invalid nil))
              (push ?\) stack))
             ((memq ch '(?\] ?\)))
              (unless (eq ch (pop stack)) (throw 'invalid nil)))
             (stack nil)
             ((eq ch ?:) (unless pseudo (setq pseudo i)))
             ((memq ch '(?\s ?\t ?, ?> ?+ ?~ ?| ?. ?#)) (setq pseudo nil))
             ((or (<= ?a ch ?z) (<= ?A ch ?Z) (<= ?0 ch ?9) (>= ch 128)
                  (memq ch '(?_ ?- ?& ?*))) nil)
             (t (throw 'invalid nil))))
          (setq i (1+ i)))
        (unless (or stack quote escaped) pseudo)))))

(defun emmet2-extract (region-beg region-end &optional syntax)
  "Return (:beg BEG :end END :abbr TEXT) at point within the given region.
REGION-BEG and REGION-END constrain host syntax.  Only the current line is
scanned.  Balanced groups include spaces and quotes; unmatched host closing
delimiters and authored tags are excluded.  Point can be anywhere in the
token, including its start and end.  Return nil outside a token.  SYNTAX
`css' treats comments and top-level or unmatched closing braces as host
boundaries and retains property-separating commas, including a pending one;
balanced raw groups retain their contents.  `css-selector' also retains
spaces between selector compounds, excluding trailing whitespace."
  (let ((position (point))
        (begin (max region-beg (line-beginning-position)))
        (limit (min region-end (line-end-position)))
        (css (memq syntax '(css css-selector))))
    (when (<= begin position limit)
      (save-excursion
        (goto-char begin)
        (let (token stack quote escaped result tag-end)
          (cl-labels ((finish ()
                        (when token
                          (let ((end (if (eq syntax 'css-selector)
                                         (save-excursion (skip-chars-backward " \t" token) (point))
                                       (point))))
                            (when (<= token position end)
                              (setq result (list :beg token :end end
                                                 :abbr (buffer-substring-no-properties token end))))))
                        (setq token nil stack nil quote nil escaped nil)))
            (while (and (< (point) limit) (not result))
              (let ((character (char-after)))
                (cond
                 (escaped (setq escaped nil))
                 ((and token (eq character ?\\)) (setq escaped t))
                 (quote (when (eq character quote) (setq quote nil)))
                 ((and css
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
                 ((and css (< (1+ (point)) limit) (looking-at "/\\*"))
                  (finish)
                  (unless result
                    (forward-char 2)
                    (goto-char (1- (or (search-forward "*/" limit t) limit)))))
                 ((and css (< (1+ (point)) limit) (looking-at "\\*/"))
                  ;; The current line may begin inside a multiline comment.
                  (finish)
                  (unless result (forward-char)))
                 ((and (eq character ?<) (setq tag-end (emmet2-extract--tag-end)))
                  (finish)
                  (unless result (goto-char (1- (min limit tag-end)))))
                 ((and (eq syntax 'css-selector) (memq character '(?\s ?\t))) nil)
                 ((or (memq character '(?\s ?\t ?\n ?\r ?\; ?= ?< ?\" ?\' ?` ?} ?\] ?\)))
                      (and (not css) (eq character ?,)
                           (or (= (1+ (point)) limit)
                               (memq (char-after (1+ (point))) '(?\s ?\t ?} ?\))))))
                  (finish))
                 (t (unless token (setq token (point))))))
              (unless result (forward-char)))
            (unless result (finish)))
          result)))))

(provide 'emmet2-extract)
;;; emmet2-extract.el ends here
