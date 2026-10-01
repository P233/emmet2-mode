# Library and host APIs

Use these interfaces to integrate Emmet expansion or CSS completion into another
package. For installation and everyday editing, see [README.md](README.md).

## Choose an entry point

| Need | Entry point |
| --- | --- |
| Complete a property name, a value of a known property, or a pseudo name | `emmet2-css-data-query` |
| Rank names gathered by the host, including local Sass symbols | `emmet2-fuzzy-filter` |
| Interpret compact CSS property/value abbreviations | `emmet2-css-search` |
| Expand an abbreviation without an editor buffer | `emmet2-extensions-css` or `emmet2-extensions-markup` |
| Offer live Emmet choices with the existing UI and acceptance behavior | A context provider plus `emmet2-capf` / `emmet2-complete` |
| Implement a synchronous direct-expansion command | Context analysis, insertion snapshot, `emmet2-expand-analysis`, then `emmet2-insert` |

The interfaces documented here are public; names containing `--` are internal.
The declaration/render helpers, `emmet2-css-completions` and
`emmet2-expand-choices` connect package modules. Their opaque declaration and
batch representations are internal and are not part of the host API.

## Query names and property-specific values

Query CSS metadata without a buffer or minor mode:

```elisp
(require 'emmet2-css-data)
(emmet2-css-data-query 'property :query "ins")
(emmet2-css-data-query 'value :property "display" :query "ib")
(emmet2-css-data-query 'property :at-rule "@font-face" :query "src")
(emmet2-css-data-query 'value :property "font-display" :at-rule "@font-face" :query "sw")
(emmet2-css-data-query 'pseudo :query "before")
(emmet2-css-data-query 'at-rule :query "media" :vendor t)

;; Extract just the best name; queries otherwise retain documentation.
(caar (emmet2-css-data-query 'value :property "display" :query "ib"))
;; => "inline-block"
```

Signature: `(emmet2-css-data-query KIND &key query property at-rule vendor)`.
Kinds are `property`, `value`, `at-rule` and `pseudo`; results are ranked
`(NAME . DOCUMENTATION)` pairs. Empty/omitted `:query` returns all names;
`:vendor t` includes vendor names. `:at-rule` adds descriptors such as
`@font-face`'s `src` alongside ordinary properties.

Values share compact search's keyword sets, plus restriction-derived functions.
Ordinary and unknown properties include `inherit` and `var()`; descriptors use
their enclosing `:at-rule` without ordinary property defaults or CSS-wide values.
Lists and pairs are fresh, strings are shared read-only, and documentation may
be nil.

The host supplies context, adds scoped symbols and restricts legal candidates.
For `display: fl`, query values for `display` and replace only `fl`; for `m10`,
use expansion. An analysis's `:property` identifies context, not value completion.

## Rank host names or search compact CSS

```elisp
(require 'emmet2-fuzzy)

(emmet2-fuzzy-filter "bg" '("border" "background-color" "background"))
;; => ("background" "background-color")

;; The optional KEY function lets a host retain its own candidate payloads.
(emmet2-fuzzy-filter "ib"
                    '(("inline-block" . "CSS value") ("none" . "CSS value"))
                    #'car)
;; => (("inline-block" . "CSS value"))

(plist-get (emmet2-fuzzy-match "bgc" "background-color") :positions)
;; => (0 4 11)
```

`emmet2-fuzzy-match` returns nil or a plist with `:score` and zero-based `:positions`.
Matching is case-insensitive and ordered; stronger matches rank first and ties
keep input order. `emmet2-fuzzy-filter` preserves input items. Completion uses
full-query matching; optional partial matching is a separate utility.

```elisp
(require 'emmet2-css-search)

;; LIMIT and BARE are positional optional arguments here, not keyword arguments.
(car (emmet2-css-search "tac" 3))
;; => ("text-align" . "center")

(emmet2-css-search "ins" 5 t) ; BARE requests property names without value splits.
(emmet2-css-search-values "display" "ib" 3)
;; => ("inline-block")
```

`emmet2-css-search` returns `(PROPERTY . KEYWORD)` pairs, with nil for a bare
property and a default limit of ten. Use the extension API for complete syntax,
including units, brackets, functions and property lists.
The optional fourth argument to either search function selects an enclosing
at-rule, admitting its descriptors and their values.
Search and expansion share a one-second deadline; expiry signals
`emmet2-backend-error`.

## Expand strings and consume canonical results

```elisp
(require 'emmet2-extensions)

(emmet2-extensions-css-choices "ta" :syntax 'scss :limit 3)
;; => ("text-align" "text-align[center]" "top[auto]")

(emmet2-extensions-css "sr" :syntax 'css :at-rule "@font-face")
;; => (:text "src: ;" :fields ((5 5 1 "")) :cursor 5)

(emmet2-extensions-css "m10,ta" :syntax 'scss
                       :indent "  " :base-indent "")
;; => (:text "margin: 10px;\ntext-align: ;"
;;     :fields ((26 26 1 "")) :cursor 26)

(emmet2-extensions-css "button::be" :syntax 'css)
;; => (:text "button::before" :fields nil :cursor 14)

;; Pure markup expansion is available through the same result contract.
(emmet2-extensions-markup "ul>li*2" :indent "  ")

(plist-get (emmet2-extensions-markup ".a.b" :jsx t) :text)
;; => "<div className={clsx(styles.a, styles.b)}></div>"
(plist-get (emmet2-extensions-markup "_.a.b" :jsx t) :text)
;; => "<div className=\"a b\"></div>"
```

`emmet2-extensions-markup` references JSX classes as `:css-modules-object` members
joined by `:class-names-constructor` (`:class-style 'css-modules`, the default).
`:class-style 'plain`, or a leading `_` in the abbreviation, keeps them a string.

Choices are independently expandable strings for one property, pseudo chain or
at-rule. Returned strings may contain a separator preserving an otherwise ambiguous
property/value boundary; treat them as opaque expandable choices. The CSS pipeline
builds choices for lists such as `ovh,ta`; pure expansion accepts
the whole list. Set `:syntax 'css` or `'scss` explicitly (default: `scss`), and
`:css-in-js t` for object members. `:indent` and `:base-indent` are literal strings.
SCSS means brace-based syntax, not indentation-based `.sass` or Sass analysis.
Both CSS entry points accept `:at-rule` to select the enclosing rule's
descriptors. Pass the same context when expanding a returned choice;
`emmet2-expand-analysis` and CAPF already forward a host analysis's `:at-rule`.

| Key | Meaning |
| --- | --- |
| `:text` | Complete insertion text, already formatted; no snippet transport syntax. |
| `:fields` | A list of `(BEG END GROUP DEFAULT)` entries. Positions are zero-based character offsets in `:text`, with an exclusive `END`; equal positive groups are mirrors. Empty fields can have `BEG = END`. |
| `:cursor` | Zero-based initial cursor offset in `:text`; normally the first editable field, or the end when no fields exist. |

Offsets count characters, not bytes; `emmet2-insert` maps them to buffer
positions and optional yasnippet fields. Do not reformat `:text` independently.

## Host completion interface

Set buffer-local `emmet2-context-provider` before enabling `emmet2-mode`, or call
`emmet2-capf` from the host's dispatcher without enabling the mode, as
[scss2 does](README.md#supported-modes). The host supplies parser context and bounds;
Emmet supplies choices, preview and validated insertion. No `css-mode`
inheritance, extra parser or frontend configuration is required. See the
[runnable example](#runnable-provider-example) below.

A host that owns value navigation can set `:field-navigation host` in the
provider plist. The insertion snapshot captures this policy: Emmet keeps the
canonical text and initial cursor but does not activate yasnippet fields.

`:analyze` receives `automatic`: non-nil for automatic, nil for explicit requests.
Return nil to decline, with **no fallback** to built-in detection; otherwise
return a fresh plist:

| Key | Host contract |
| --- | --- |
| `:beg`, `:end` | Nonempty, fully visible replacement range in absolute integer positions. `:end` is exclusive; point may lie anywhere from `:beg` through `:end`. |
| `:lang`, `:syntax` | `css` with `css` or `scss`; `css-in-js` with `jsx`; `markup` with `html` or `jsx`. |
| `:position` | `declaration-start` or `selector` for CSS; `declaration-start` for CSS-in-JS; `markup` for markup. |
| `:indent-width` | Optional nonnegative integer number of columns. Overrides built-in mode width; tabs and base indentation still follow buffer settings. |
| `:property`, `:at-rule` | Optional context identities; changing either ends the old session. Property-specific value candidates come from `emmet2-css-data-query`, not abbreviation expansion. |

Emmet derives `:abbr` from source. Confirm the whole range, including a prefix
such as `ovh,` in `ovh,ta`; `emmet2-extract` can help within a confirmed region.
Decline values, comments and forbidden syntax even for explicit requests;
automatic CAPF also checks abbreviation confidence. Emmet restores point and
narrowing and match data after either callback and rejects ranges outside the
original visible region.

`:revision` takes no arguments and returns a cheap, immutable `equal`-comparable
token covering extra inputs such as dialect, settings and parser generation.
Emmet already tracks source tick, point, visible bounds, major mode and `emmet2-mode`.
Both callbacks are read-only; revision must stay stable until inputs change and
must not parse. Unchanged revisions reuse the analysis.

Direct context APIs signal invalid contracts. Automatic CAPF errors invalidate
that table and offer no match; `emmet2-complete` and acceptance report the error.
Cancellation propagates, and `debug-on-error` retains the original debugger.

Replace the provider plist rather than mutating it; replacement/removal
invalidates old tables. Major-mode changes clear it. To disable expansion,
return nil from `:analyze` and change the revision; setting the provider itself
to nil restores built-in detection. Disabling `emmet2-mode` removes its CAPF
hook but leaves the host-owned provider usable by an independent dispatcher.

## Semantic name completion

Hosts can pass confirmed bounds and `(NAME . DOCUMENTATION)` pairs to
`emmet2-completion-capf`. It returns a CAPF with fuzzy matching, documentation
and an acceptance callback for empty functions such as `calc()`. Acceptance
only moves point inside the inserted parentheses; it creates no snippet fields.
Existing call arguments remain intact. Hosts own subsequent TAB navigation.

The default category is `emmet2-value`, using the `emmet2-name` style. Optional
`:category`, `:identity` and `:fuzzy` preserve a host's name semantics and user
style overrides; `:annotation` and `:prefix` supply frontend hints. The host
still owns context, bounds and candidate discovery. The frontend owns text
replacement and its undo group; acceptance changes only point.

## Runnable provider example

This demo accepts a whole-buffer pseudo abbreviation. Production hosts must
replace its string check with syntax analysis.

```elisp
(require 'emmet2-mode)

(defvar-local my-emmet-demo-enabled t)

(defun my-emmet-demo-context (_automatic)
  (when (and my-emmet-demo-enabled
             (string-match-p "\\`::?[[:alpha:]-]+\\'"
                             (buffer-substring-no-properties
                              (point-min) (point-max))))
    (list :beg (point-min) :end (point-max)
          :lang 'css :syntax 'scss :position 'selector)))

(defun my-emmet-demo-revision ()
  my-emmet-demo-enabled)

(switch-to-buffer (generate-new-buffer "*Emmet provider demo*"))
(fundamental-mode)
(insert "::be")
(setq-local emmet2-context-provider
            (list :analyze #'my-emmet-demo-context
                  :revision #'my-emmet-demo-revision))
(emmet2-mode 1)
```

Run `M-x emmet2-complete` and accept `::before` to replace `::be`, leaving point
after the name. Disabling `my-emmet-demo-enabled` invalidates displayed candidates.

## Synchronous expansion, preview and insertion

| Operation | Interface |
| --- | --- |
| Confirm current host context | `emmet2-context-analyze`; `emmet2-context-revision` describes its inputs. |
| Expand a confirmed context | `emmet2-expand-analysis`; shares the exact expansion and buffer layout used by completion. |
| Format from host/buffer settings | `emmet2-insert-render-options`, including the host's `:indent-width`. |
| Preview final text | `emmet2-preview` with output syntax `css`, `html` or `jsx`. |
| Accept synchronously | Capture `emmet2-insert-snapshot` before expansion, then call `emmet2-insert` with the canonical result. |

`emmet2-expand` owns buffer-aware expansion and project options. Requiring
`emmet2-mode` continues to make this API available; a host can instead require
`emmet2-context` and `emmet2-expand` without loading minor-mode registration.

For a direct command:

```elisp
(require 'emmet2-mode)

(defun my-expand-emmet-at-point ()
  "Expand synchronously using the registered host or built-in context."
  (interactive)
  (let* ((analysis (or (emmet2-context-analyze)
                       (user-error "No Emmet abbreviation at point")))
         (snapshot (emmet2-insert-snapshot analysis))
         (result (emmet2-expand-analysis analysis)))
    (emmet2-insert snapshot result)))
```

Capture the snapshot **before** expansion. This preserves fields, cursor and
atomic undo; never reuse an old result with a newly captured snapshot. Use
`emmet2-capf` for live/deferred choices and its context, render and identity checks.

Layout uses source column, optional `:indent-width` and buffer tab settings.
Pure expansion uses caller-supplied indentation strings.

`emmet2-preview` returns a read-only buffer for the host to display. Use `css`
for CSS/SCSS, or `html`/`jsx` for markup:

```elisp
(require 'emmet2-extensions)
(require 'emmet2-preview)

(let ((result (emmet2-extensions-css "m10,p.5" :syntax 'css)))
  (emmet2-preview (plist-get result :text) 'css))
```

Expansion failures signal `emmet2-error` or a subtype; declined context returns
nil. Stale snapshots are rejected before editing. Direct commands should report
errors without partial insertion. Data queries need no snapshot.

See [ARCHITECTURE.md](ARCHITECTURE.md) for module ownership and
[CONTRIBUTING.md](CONTRIBUTING.md) for development and tests.
