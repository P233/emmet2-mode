;;; emmet2-css-value.el --- Value completion in CSS Base hosts -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; CSS Base supplies syntax state.  Tree-sitter hosts keep their own context
;; authority and call the same semantic completion library with confirmed data.

;;; Code:
(require 'emmet2-context)
(declare-function emmet2-css-data-query "emmet2-css-data" (kind &rest arguments))
(declare-function emmet2-completion-capf "emmet2-completion" (begin end entries &rest arguments))

(defun emmet2-css-value-capf ()
  "Offer shared CSS values at a CSS Base declaration's value position."
  (when-let* ((_ (not emmet2-context-provider))
              (context (emmet2-context-css-value)))
    (require 'emmet2-css-data)
    (require 'emmet2-completion)
    (emmet2-completion-capf
     (plist-get context :beg) (plist-get context :end)
     (emmet2-css-data-query 'value :property (plist-get context :property)
                            :at-rule (plist-get context :at-rule) :vendor t)
     :annotation (concat "  " (plist-get context :property)))))

(provide 'emmet2-css-value)
;;; emmet2-css-value.el ends here
