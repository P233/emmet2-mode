;;; emmet2-css-search-test.el --- CSS search contracts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'emmet2-css-search)

(defun emmet2-css-search-test--corpus ()
  "Read the frozen search expectations."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "test/fixtures/css-search-corpus.json" emmet2-test-root))
    (json-parse-buffer :array-type 'list)))

(defun emmet2-css-search-test--rank (case)
  "Return the rank of CASE's (QUERY PROPERTY [KEYWORD]) choice, or nil."
  (cl-loop for choice in (emmet2-css-search (nth 0 case) 30) for rank from 1
           when (equal choice (cons (nth 1 case) (nth 2 case))) return rank))

(defun emmet2-css-search-test--count (cases limit)
  "Count CASES whose expected choice ranks within LIMIT."
  (cl-count-if (lambda (case) (let ((rank (emmet2-css-search-test--rank case))) (and rank (<= rank limit))))
               cases))

(ert-deftest emmet2-css-search-accuracy-gates ()
  ;; Gates hold the measured quality; retune only against this corpus (CONTRIBUTING.md).
  ;; Seven Emmet value presets such as cr and qen are intentionally absent.
  (let ((corpus (emmet2-css-search-test--corpus)))
    (dolist (gate '(("user" 1 4) ("frequent" 1 53) ("compounds" 1 54) ("compounds" 3 58)
                    ("inherited" 3 12) ("aliases" 1 170) ("aliases" 3 197)))
      (ert-info ((format "%S" gate))
        (should (>= (emmet2-css-search-test--count (gethash (car gate) corpus) (nth 1 gate))
                    (nth 2 gate))))))
  ;; A complete name ranks first.  Single SVG letters such as d are
  ;; abbreviations of common properties instead.
  (maphash (lambda (name property)
             (when (and (emmet2-css-search--property-prior property) (> (length name) 1))
               (ert-info (name) (should (equal (car (emmet2-css-search name)) (cons name nil))))))
           emmet2-css-search--canonical))

(ert-deftest emmet2-css-search-words-aliases-and-values ()
  (dolist (case '(("m" "margin" nil) ("d" "display" nil) ("r" "right" nil) ("ins" "inset" nil) ("inset-b" "inset-block" nil)
                  ("bg" "background" nil) ("bgc" "background-color" nil) ("bdrs" "border-radius" nil)
                  ("fz" "font-size" nil) ("mA" "margin" "auto") ("dIB" "display" "inline-block")
                  ("tac" "text-align" "center") ("dib" "display" "inline-block")
                  ("bdn" "border" "none") ("whsnw" "white-space" "nowrap") ("dN" "display" "none")
                  ("mbs" "margin-block-start" nil)
                  ;; Documented differences from Emmet's font-style and border-right.
                  ("fs" "font-size" nil) ("bdr" "border-radius" nil)))
    (ert-info ((car case))
      (should (equal (car (emmet2-css-search (car case))) (cons (nth 1 case) (nth 2 case))))))
  ;; A later word can begin the query.
  (should (member '("inline-size" . nil) (emmet2-css-search "size"))))

(ert-deftest emmet2-css-search-alias-claims-and-choices ()
  ;; An authored word alias claims its own word's letters only.
  (should-not (member '("background" . nil) (emmet2-css-search "bgr")))
  (should (equal (car (emmet2-css-search "rsz")) '("resize" . nil)))
  ;; A property alias ranks first without hiding other properties.
  (let ((choices (emmet2-css-search "fz")))
    (should (equal (car choices) '("font-size" . nil))))
  ;; An explicit value boundary never offers a bare property.
  (should (cl-every #'cdr (emmet2-css-search "mA")))
  (should (<= (length (emmet2-css-search "m")) 10))
  (should (= (length (emmet2-css-search "m" 3)) 3))
  ;; The single-choice path keeps the same ranking without sorting.
  (dolist (query '("m" "d" "b" "ta" "tac" "mA" "ins" "bdrs" "fz" "size"))
    (dolist (bare '(nil t))
      (should (equal (emmet2-css-search query 1 bare) (seq-take (emmet2-css-search query 10 bare) 1))))))

(ert-deftest emmet2-css-search-rejects-unaligned-and-non-queries ()
  (dolist (query '("" "zzzz" "unknownword" "m10" "#fff" "-m" "m_" "1m"))
    (ert-info (query) (should-not (emmet2-css-search query))))
  (should-not (emmet2-css-search "m" 0))
  (should-not (emmet2-css-search-values "top" "a" 0))
  (should-not (emmet2-css-search-values "margin" ""))
  (should-not (emmet2-css-search-values "not-a-property" "a")))

(ert-deftest emmet2-css-search-values-include-inherited-sets ()
  (dolist (case '(("border" "s" "solid") ("top" "a" "auto") ("border" "t" "thin")
                  ("white-space" "nw" "nowrap") ("justify-content" "sb" "space-between")
                  ("color" "tr" "transparent") ("margin" "i" "inherit")))
    (ert-info ((format "%S" case))
      (should (equal (car (emmet2-css-search-values (car case) (nth 1 case) 1)) (nth 2 case)))))
  ;; Rarely written sets, such as system colors, stay reachable below others.
  (should (equal (car (emmet2-css-search "cCanvas")) '("color" . "Canvas")))
  (should-not (member '("color" . "LinkText") (emmet2-css-search "cl" 3)))
  ;; Deprecated types and function arguments are not values of the property.
  (should-not (member "InfoText" (emmet2-css-search-values "color" "inf" 30)))
  (should-not (member "auto-fill" (emmet2-css-search-values "grid-template-columns" "af" 30)))
  (should (equal (emmet2-css-search-keywords "text-align")
                 '("center" "end" "justify" "left" "right" "start" "match-parent")))
  (should-not (cl-some (lambda (keyword) (string-suffix-p "()" keyword))
                       (emmet2-css-search-keywords "grid-template-columns"))))

(ert-deftest emmet2-css-search-membership-and-fresh-results ()
  (should (emmet2-css-search-property-p "margin"))
  ;; Obsolete properties stay canonical names but are never offered.
  (should (emmet2-css-search-property-p "box-flex-group"))
  (should-not (assoc "box-flex-group" (emmet2-css-search "box-flex-group")))
  (should-not (emmet2-css-search-property-p "d:n"))
  (should (emmet2-css-search-element-p "button"))
  (should-not (emmet2-css-search-element-p "margin"))
  (should (member "@media" (emmet2-css-search-at-rules)))
  (should (member ":hover" (emmet2-css-search-pseudos)))
  (let ((first (emmet2-css-search "ta")))
    (setcar (car first) "mutated")
    (should (equal (car (emmet2-css-search "ta")) '("text-align" . nil))))
  (let ((names (emmet2-css-search-property-names)))
    (setcar names "mutated")
    (should-not (member "mutated" (emmet2-css-search-property-names)))))

(ert-deftest emmet2-css-search-structs-replace-generated-property-entries ()
  ;; Only the structs keep properties and descriptors after load.
  (should (equal (sort (hash-table-keys emmet2-css-search--index) #'string<)
                 '("atRules" "elements" "pseudos" "sets" "wide")))
  (let ((names (emmet2-css-search-property-names t)))
    (should (equal names (sort (copy-sequence names) #'string<)))
    (should (equal (cl-remove-if-not (lambda (name) (gethash name emmet2-css-search--canonical)) names)
                   (emmet2-css-search-property-names)))
    (should (member "font-display" names))
    (should-not (member "font-display" (emmet2-css-search-property-names)))))

(ert-deftest emmet2-css-search-rejects-impossible-length-before-scratch-allocation ()
  (let ((input (concat "m" (make-string 4096 ?A))))
    (cl-letf (((symbol-function 'emmet2-css-search--prepare)
               (lambda (_) (ert-fail "An impossible query must not allocate segment tables"))))
      (should-not (emmet2-css-search input))
      (should-not (emmet2-css-search-values "margin" input)))))

(ert-deftest emmet2-css-search-honors-the-expansion-deadline ()
  (let ((emmet2-engine--deadline 0))
    (should-error (emmet2-css-search "mA") :type 'emmet2-backend-error)
    (should-error (emmet2-css-search-values "border" "s") :type 'emmet2-backend-error)))

(ert-deftest emmet2-css-search-metadata-accessors-hide-index-entries ()
  (should (emmet2-css-search-property-p "color"))
  (should-not (emmet2-css-search-property-p "font-display"))
  (should (emmet2-css-search-property-p "font-display" "@FONT-FACE"))
  (should-not (emmet2-css-search-property-p "font-display" "@media"))
  (let ((names (emmet2-css-search-value-names "font-display" "@font-face")))
    (should (member "swap" names))
    (should-not (member "inherit" names))
    (setcar names "caller-owned")
    (should-not (member "caller-owned" (emmet2-css-search-value-names "font-display" "@font-face"))))
  (should-not (member "swap" (emmet2-css-search-value-names "font-display"))))

(ert-deftest emmet2-css-search-descriptors-exclude-css-wide-keywords ()
  (dolist (case '(("inherits" "@property") ("font-display" "@font-face")
                  ("font-style" "@font-face")))
    (should-not (member "inherit" (emmet2-css-search-value-names (car case) (cadr case))))
    (should-not (member "inherit" (emmet2-css-search-values (car case) "i" 30 (cadr case)))))
  (should-not (member '("inherits" . "inherit") (emmet2-css-search "inheritsI" 30 nil "@property")))
  (should-not (member '("inherits" . "initial") (emmet2-css-search "inheritsI" 30 nil "@property")))
  (should-not (member '("font-style" . "inherit") (emmet2-css-search "font-styleI" 30 nil "@font-face")))
  (should (member '("font-style" . "italic") (emmet2-css-search "font-styleI" 30 nil "@font-face")))
  (should (member '("font-style" . "inherit") (emmet2-css-search "font-styleI" 30)))
  (should (equal (emmet2-css-search-values "inherits" "t" 10 "@property") '("true")))
  (should (member "italic" (emmet2-css-search-values "font-style" "i" 10 "@font-face")))
  (should (member "inherit" (emmet2-css-search-values "font-style" "i" 30))))

(provide 'emmet2-css-search-test)
;;; emmet2-css-search-test.el ends here
