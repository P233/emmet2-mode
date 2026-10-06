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

Only the functions, variables and errors documented here are public. Every
other name is internal and may change, including names containing `--`, the
engine and result helpers (`emmet2-engine-*`, `emmet2-result-*`),
`emmet2-css-completions`, `emmet2-expand-choices`, the `emmet2-context-css-*`,
`emmet2-context-js-*` and `emmet2-context-web-*` adapters, and helpers such as
`emmet2-extensions-css-kind`, `emmet2-css-search-value-names` and
`emmet2-fuzzy-find`.

| Function | Arguments |
| --- | --- |
| `emmet2-css-data-query` | `(KIND &key query property at-rule vendor)` |
| `emmet2-css-search` | `(QUERY &optional LIMIT BARE AT-RULE)` |
| `emmet2-css-search-values` | `(PROPERTY QUERY &optional LIMIT AT-RULE)` |
| `emmet2-fuzzy-match` | `(QUERY CANDIDATE &optional PARTIAL)` |
| `emmet2-fuzzy-filter` | `(QUERY CANDIDATES &optional KEY)` |
| `emmet2-extensions-css` | `(ABBREVIATION &key css-in-js (syntax 'scss) (indent "\t") (base-indent "") at-rule scale-functions)` |
| `emmet2-extensions-css-choices` | `(ABBREVIATION &key css-in-js (syntax 'scss) (limit 10) at-rule scale-functions)` |
| `emmet2-extensions-markup` | `(ABBREVIATION &key jsx variant (class-style 'css-modules) (css-modules-object "styles") (class-names-constructor "clsx") (indent "\t") (base-indent ""))` |
| `emmet2-extract` | `(REGION-BEG REGION-END &optional SYNTAX)`; SYNTAX is nil, `css` or `css-selector` |
| `emmet2-context-analyze` | `(&optional AUTOMATIC)` |
| `emmet2-expand-analysis` | `(ANALYSIS)` |
| `emmet2-insert-render-options` | `(ANALYSIS)`, returning `(:indent STRING :base-indent STRING)` |
| `emmet2-insert-snapshot` | `(ANALYSIS)` |
| `emmet2-insert` | `(SNAPSHOT RESULT)` |
| `emmet2-preview` | `(TEXT SYNTAX)` |
| `emmet2-completion-capf` | `(BEGIN END ENTRIES &key (category 'emmet2-value) (identity #'identity) (fuzzy t) annotation prefix)` |

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
`:vendor t` includes vendor names. `:at-rule "@font-face"` (with the `@`, in any
case) adds descriptors such as `src` alongside ordinary properties. An unknown
kind signals an error.

Values share compact search's keyword sets, plus restriction-derived functions.
Ordinary and unknown properties include the CSS-wide keywords, `var()` and
`env()`; descriptors use their enclosing `:at-rule`, with `env()` but without
CSS-wide keywords, `var()` or a same-named property's values.
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
keep input order. `emmet2-fuzzy-filter` keeps the input items and matches the
whole query. Pass non-nil PARTIAL to `emmet2-fuzzy-match` to accept a matched
query prefix at a lower score; completion does not use it.

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
Each search, expansion or choice request must finish within one second;
otherwise it signals `emmet2-backend-error`.

## Expand strings and consume results

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
`:variant "solid"` writes `class`; it and the class options apply only with
`:jsx t`.

`emmet2-extensions-css` writes SCSS values such as `p(1)` as Sass calls only when
`:scale-functions` maps the property, as in `emmet2-css-scale-functions`;
otherwise they are parse errors. `emmet2-expand-analysis` passes the
corresponding user options. Property names, the final pseudo, at-rule names,
and top-level value words and units outside the CSS data also signal
`emmet2-parse-error`. Bracketed values such as `ff[Inter]`, function arguments
such as `w-calc(10qq)`, and unknown earlier pseudos such as `:global` in
`:global(.a):hv` keep their spelling. `emmet2-extensions-css-choices` accepts
the same `:scale-functions` and returns only choices that expand; its first
choice is what `emmet2-extensions-css` expands.

`emmet2-extensions-css-choices` takes one property, pseudo chain or at-rule
and returns nil for a list such as `ovh,ta`; `emmet2-extensions-css` expands
the whole list, and editor completion offers choices for its last item.
Returned strings may contain a separator that keeps an otherwise ambiguous
property/value boundary; treat them as opaque and pass each one back with the
same `:syntax`, `:css-in-js`, `:at-rule` and `:scale-functions`. Set
`:syntax 'css` or `'scss` explicitly (default: `scss`), and `:css-in-js t` for
object members. `:indent` (a tab by default) and `:base-indent` are literal
strings.
SCSS means brace-based syntax, not indentation-based `.sass` or Sass analysis.
Both CSS entry points accept `:at-rule` to select the enclosing rule's
descriptors. Pass the same context when expanding a returned choice;
`emmet2-expand-analysis` and CAPF already forward a host analysis's `:at-rule`.

Both expansion functions return a result plist with these keys; treat it as
read-only:

| Key | Meaning |
| --- | --- |
| `:text` | Complete insertion text, already formatted; no snippet transport syntax. |
| `:fields` | A list of `(BEG END GROUP DEFAULT)` entries. Positions are zero-based character offsets in `:text`, with an exclusive `END`; equal positive groups are mirrors. Empty fields can have `BEG = END`. |
| `:cursor` | Zero-based initial cursor offset in `:text`: the start of group 1's first field, or the end when no fields exist. |

Offsets count characters, not bytes; `emmet2-insert` maps them to buffer
positions. Markup fields become yasnippet fields when it is installed; CSS and
CSS-in-JS results place point at `:cursor` without creating snippets. The
editor may then continue on the next line under `emmet2-css-auto-newline`, as
described below. Pure results and previews contain no continuation line. Do
not reformat `:text` independently.

## Host completion interface

Set buffer-local `emmet2-context-provider` before enabling `emmet2-mode`, or call
`emmet2-capf` from the host's dispatcher without enabling the mode, as
[scss2-mode does](README.md#better-with-scss2-mode). The host supplies parser
context and bounds; Emmet supplies choices, preview and validated insertion. No `css-mode`
inheritance, extra parser or frontend configuration is required. See the
[runnable example](#runnable-provider-example) below.

`:analyze` receives `automatic`: non-nil for automatic, nil for explicit requests.
Return nil to decline, with **no fallback** to built-in detection; otherwise
return a plist:

| Key | Host contract |
| --- | --- |
| `:beg`, `:end` | Nonempty, fully visible replacement range in absolute integer positions. `:end` is exclusive; point may lie anywhere from `:beg` through `:end`. A CSS or CSS-in-JS result ending in `;` also replaces a `;` right at `:end`, so the declaration keeps one terminator. |
| `:lang`, `:syntax` | `css` with `css` or `scss`; `css-in-js` with `jsx`; `markup` with `html` or `jsx`. |
| `:position` | `declaration-start` or `selector` for CSS; `declaration-start` for CSS-in-JS; `markup` for markup. |
| `:indent-width` | Optional nonnegative integer number of columns. Overrides built-in mode width; tabs and base indentation still follow buffer settings. |
| `:at-rule` | Optional enclosing rule with its `@`, such as `"@font-face"`; CSS expansion then offers its descriptors. Changing it invalidates open completion tables. |
| `:property` | Optional property name, used only to tell contexts apart; changing it invalidates open completion tables. Property-specific value candidates come from `emmet2-css-data-query`, not abbreviation expansion. |

Emmet derives `:abbr` from source. Confirm the whole range, including a prefix
such as `ovh,` in `ovh,ta`; `emmet2-extract` can help within a confirmed region.
Decline values, comments and forbidden syntax even for explicit requests;
automatic CAPF also checks abbreviation confidence. Emmet restores point and
narrowing and match data after either callback. An empty range, a range outside
the original visible region or one that excludes point makes the analysis nil;
other malformed values signal `emmet2-error`.

`:revision` takes no arguments and returns a cheap, immutable `equal`-comparable
token covering extra inputs such as dialect, settings and parser generation.
Emmet already tracks source tick, point, visible bounds, major mode and `emmet2-mode`.
Both callbacks are read-only; revision must stay stable until inputs change and
must not parse. Unchanged revisions reuse the analysis within a table and from
the buffer's last completed choice batch. Reuse also requires the same provider
identity and automatic/explicit request policy; declined analyses are not cached.

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
`emmet2-completion-capf`. It returns completion data for a CAPF function to
return, with fuzzy matching, documentation and an acceptance callback for empty
functions such as `calc()`. The data is exclusive: return nil from your CAPF
when no entry fits. Acceptance
only moves point inside the inserted parentheses; it creates no snippet fields.
Existing call arguments remain intact. Hosts own subsequent TAB navigation.

For expensive discovery, `ENTRIES` may instead be a zero-argument function.
Metadata and completion-boundary queries do not call it. The first candidate
query collects entries once for that table, including an empty result. Discovery
must be read-only and runs only in the original buffer, mode, text revision,
point and restriction. Interrupted collection can be retried; a new table runs
discovery again. Lists are prepared immediately. Because the table is exclusive,
an empty collection still keeps later completion functions, such as dabbrev,
from running; pass a list when declining matters.

The default category is `emmet2-value`, using the `emmet2-name` style. Optional
`:category`, `:identity` and `:fuzzy` preserve a host's name semantics and user
style overrides; `:annotation` and `:prefix` supply frontend hints. `:identity`
and `:fuzzy` take effect only under the `emmet2-name` style, which is the
default for `emmet2-value`; a host passing its own `:category` must give it the
`emmet2-name` style, as in
`(add-to-list 'completion-category-defaults '(my-category (styles emmet2-name)))`.
The host
still owns context, bounds and candidate discovery, including its failures: an
error from a function `ENTRIES` propagates to the completion frontend. The
frontend owns text replacement and its undo group; acceptance changes only point.

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

Run `M-x emmet2-expand-at-point`, or `M-x emmet2-complete` and accept
`::before`, to replace `::be`, leaving point after the name. Disabling `my-emmet-demo-enabled` invalidates displayed candidates.

## Synchronous expansion, preview and insertion

| Operation | Interface |
| --- | --- |
| Confirm current host context | `emmet2-context-analyze`; `emmet2-context-revision` describes its inputs. |
| Expand a confirmed context | `emmet2-expand-analysis`; returns the first completion choice's result, with the same buffer layout. |
| Format from host/buffer settings | `emmet2-insert-render-options`, including the host's `:indent-width`. |
| Preview final text | `emmet2-preview` with output syntax `css`, `html` or `jsx`. |
| Accept synchronously | Capture `emmet2-insert-snapshot` before expansion, then call `emmet2-insert` with the result. |

The `emmet2-expand` library (emmet2-expand.el, unrelated to the removed 0.2
command) provides buffer-aware expansion and the project options. Requiring
`emmet2-mode` also loads this API; a host can instead require
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

Capture the snapshot **before** expansion so `emmet2-insert` rejects the result
if the source changed in between; never reuse an old result with a newly
captured snapshot. Use
`emmet2-capf` for live/deferred choices and its context, render and identity checks.

Layout uses source column, optional `:indent-width` and buffer tab settings.
Pure expansion uses caller-supplied indentation strings.

`emmet2-css-auto-newline` defaults to `t` and is read at insertion time. In
`css-base-mode` derivatives, an analysis with `:lang css` and
`:position declaration-start` can continue on the next line when its source
abbreviation occupies a line by itself and its result has no fields, ends in
a semicolon and places `:cursor` at the end. Insertion reuses the immediately
following blank line or creates one before existing text, copying the source
line's indentation. Hidden continuation text outside a narrowed region is
left alone. This shares expansion's atomic undo group; setting the option to
`nil` preserves the result's cursor position. Embedded styles and semantic
value completion do not use this behavior.

`emmet2-preview` returns a shared read-only buffer for the host to display. The
next preview of the same syntax reuses it, so display it but do not modify or
keep it. Use `css` for CSS/SCSS, or `html`/`jsx` for markup:

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
