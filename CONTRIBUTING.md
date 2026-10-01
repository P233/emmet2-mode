# Development

The installed package is pure Emacs Lisp. Hosts share the native markup and CSS
expansion pipelines; commands, completion and previews receive canonical results.
[ARCHITECTURE.md](ARCHITECTURE.md) maps the modules and both CSS entry paths. There is no runtime backend selector, external process or fallback.
Node is used only for development setup, lint and the independent offline oracle.

## Ownership and public contracts

- `emmet2-context` routes hosts and validates their confirmed bounds. The CSS
  adapter uses CSS Base syntax state; the Web adapter scans and routes its own
  HTML, CSS and JS parts and owns bounded scan evidence;
  the JSX adapter owns parsers, warmup and unit markers. Their cleanup is separate.
  `emmet2-extract` computes abbreviation bounds within host limits.
  An external `emmet2-context-provider` owns its own syntax and confirmed bounds,
  with no fallback to built-in classification when it declines.
- `emmet2-engine` owns the canonical result and shared expansion deadline. Native
  cores return text, positive editable-field groups and an initial cursor, using
  zero-based character offsets and half-open field intervals. They never read or
  write an editor buffer. Loaded snippet and search index data is read-only;
  ASTs, output, random state and name resolution belong to the current call.
- `emmet2-css-search` owns CSS property and keyword ranking over the compact
  pinned index and the single immutable authored override catalog. CSS expansion
  reads templates from that same catalog through `emmet2-css-search-override`. Completion choices and CSS
  expansion both use it; the stylesheet core receives canonical property names
  and never guesses one. Scores are fixnums, and each query owns its tables.
- Markup preserves mirrors. CSS fields belong to one parsed property; identical
  upstream numbers in different properties are independent. Upstream zero is an
  editable field. Conflicting defaults form independent groups so mirrors cannot
  silently overwrite authored text.
- `emmet2-css` owns CSS programs, resolved property readings, completion choices,
  fragment splitting and declaration separators. The stylesheet engine parses
  authored values once and renders CSS or JavaScript directly from declarations,
  including empty defaults, escaping and field grouping. CAPF receives explicit
  labels and full results; it does not reconstruct CSS syntax or layout.
  `emmet2-extensions` keeps the public expansion entries. Project JSX class
  conversion runs on the markup AST before formatting. A rendered class value
  cannot safely be recovered by regex.
- `emmet2-expand` owns project options and translates confirmed analysis plus
  buffer layout into pure language requests. It is buffer-aware; `emmet2-mode`
  only registers completion and coordinates resource lifetime.
- `emmet2-insert` is the only source-text writer. It checks buffer, mode, tick,
  point, visible bounds and original text, then uses one atomic undo group.
  Layout derives from mode width and the abbreviation's display column before
  insertion; there is no subsequent `indent-region` pass.
- `emmet2-capf` owns the current immutable input snapshot and its lazy expansion
  choices per completion table. A table query can advance this revision while
  typing at the same anchor in the same confirmed host. Candidate text remains
  the typed abbreviation; text properties identify distinct canonical results.
  Each choice also owns its current-fragment menu label and complete preview,
  supplied by the language and prepared once for display in the current input
  revision. The next revision can reuse canonical results from the immediately
  preceding candidate set, with fresh choice identities and display projections.
  The table also retains one confirmed-prefix result while that prefix is unchanged.
  Both reuse paths remain under the table's context and render-settings guards.
  Frontends query a table many times per keystroke; the table classifies the
  host again only when `emmet2-context-revision` changes. The context module
  owns that revision, which lists every input of an analysis besides its owned
  caches; add a new input there, never a second cache in the table.
  A table also captures its context provider's identity and rejects replacement
  or removal before querying, previewing or accepting its previous candidates.
  Presentation never
  changes insertion text or field offsets.
  Only a current `finished` callback inserts; metadata and frontend prefix checks
  do not expand. Results are deduplicated and share one expansion budget. A failed
  table offers no choice and cannot revive after a later query. A new request
  may create a new table. Initial analysis and every lazy callback share the
  automatic/explicit error policy; quit propagates and debug errors stay visible.
  No global expansion cache, source-restoration state or frontend configuration
  mutation is allowed.
- `emmet2-preview` owns at most three lazy, read-only, non-file buffers. Built-in
  HTML/JSX/CSS modes fontify final text without extra grammars. Creation isolates
  user mode hooks. Failed initialization, module unload and package unload clear
  owned buffers; ordinary kill hooks still run. There is no timer or result cache.
- `emmet2-corfu` owns two category-scoped display advices, installed idempotently
  when CAPF offers an Emmet table, without loading or enabling Corfu. Labels move
  from the affix to the main display column; the unchanged candidate still owns
  acceptance. The popup anchor lives only in the completion session's properties.
  Adapter or package unload removes the advice. Timing, thresholds and width
  remain user settings; non-Emmet categories pass through unchanged.

`emmet2-engine-expand` accepts `:preset` (`html`, `jsx`, `stylesheet`), literal
`:indent`/`:base-indent`, structured `:jsx` settings and integer `:seed`. Seed
defaults to zero and its low 32 bits drive call-local lorem generation; CSS ignores
its value. Invalid seed types fail for every preset. Global random state is never
read or modified. `emmet2-engine-with-expansion` gives nested calls one shared
one-second deadline, including lazy loading and transforms. Extensions wrap the
whole operation so multiple CSS properties do not each receive a new budget.
Parse errors preserve their message/character position; other failures use
`emmet2-error` subtypes. Failures and cancellation must leave source unchanged.

The optional yas adapter safely escapes literal body/default text and synthesizes
its own final `$0`. As in Eglot, an installed yasnippet is used for any result
with fields: insertion enables `yas-minor-mode` on demand, because snippet
fields depend on its post-command handler. Tests simulate an absent yasnippet
with `emmet2-test--with-yasnippet`. A module-owned advice suppresses yas's EOF protection newline
only within an Emmet snippet; unloading the insert module removes it. Only
web-mode's built-in reindent exit hook is excluded for these snippets. Other user
hooks and settings remain intact. Plain insertion uses the same text and initial
cursor; one undo restores the abbreviation.

## Extension and host boundaries

`emmet2-css-data-query` is the buffer-independent metadata boundary for hosts.
It returns fresh `(NAME . DOCUMENTATION)` pairs for `property`, `value`,
`at-rule` or `pseudo`; callers explicitly supply `:property`, `:at-rule`,
`:query` and `:vendor`. Strings in the pairs are shared read-only metadata.
No mode, parser, completion frontend, source-buffer state or query cache is
owned by this library. `emmet2-fuzzy-filter` ranks arbitrary host candidate
lists using the same matcher while preserving input items and stable ties.
Hosts own syntax, replacement ranges, Sass scopes, local symbols and insertion.
Semantic hosts may use `emmet2-completion-capf` for the shared name table,
matching style and empty-function acceptance. CSS Base's value adapter and
scss2 use it; scss2 supplies its spelling identity and scoped Sass candidates.
Function acceptance only moves point inside inserted empty parentheses.
Hosts own subsequent navigation; the frontend owns insertion and undo.
The full metadata is loaded only when the query library is required. Value
queries reuse the compact index's own and shared keyword sets, retaining full
metadata documentation and restriction-derived functions. Expansion loads only
the compact search index. `emmet2-css-search-value-names` exposes this membership
without scores; `emmet2-css-search-property-p` optionally admits descriptors for
an at-rule. Consumers do not read private search entries.

`emmet2-context-provider` is one buffer-local, immutable descriptor containing
`:analyze` and `:revision` callbacks. It has buffer/host lifetime and no result
cache, timer or parser ownership in Emmet. Install it before enabling the minor
mode to skip Emmet's parser warmup; a host dispatcher can also use `emmet2-capf`
without enabling the mode. `:analyze` receives the automatic/explicit flag,
returns nil to decline or confirms a typed range and render context. The adapter
validates supported language/position pairs and visible integer bounds, derives
the abbreviation from source, and copies the plist without changing host state.
Optional `:indent-width` overrides built-in mode width through the existing renderer.
`:revision` is a cheap immutable token covering every extra analysis dependency;
source tick, point, narrowing and modes remain centrally tracked. A changed
token triggers reanalysis, while changed property/at-rule identities end a live
session. Hosts must not mutate a published descriptor or token. Invalid contracts
signal `emmet2-error`; refusal or an invisible/empty range returns nil.

`emmet2-expand-analysis` is the public canonical expansion path for a confirmed
analysis in the buffer-aware `emmet2-expand` facade. CAPF uses its batch entry
so resolved choices reach the renderer without another search or parse. Synchronous direct callers take an insertion snapshot
before expansion and use `emmet2-insert`; deferred choices use the shared CAPF
for context/settings/candidate revalidation. See the [host interface](API.md#host-completion-interface)
for the complete contract. Tests use an independent host without a CSS major mode;
they do not depend on scss2 or claim its integration has already been migrated.

`emmet2-extensions-css` accepts `:css-in-js`, `:syntax`, `:indent` and
`:base-indent`. Context reports `:syntax` `scss` for `scss-mode` and
`<style lang="scss">` and standalone `.scss` files in web-mode, otherwise `css`; the extension default is `scss`.
A balanced scanner splits only top-level comma/plus separators. Authored aliases
such as `posa` and `all` produce property readings. Search resolves other compact
names before parsing their authored values; known property identities are retained
through rendering. `emmet2-extensions-css-choices` projects programs to independently
expandable strings for external callers. Internal completion uses declarations and
explicit fragment labels, never these strings as a second semantic input.

Field defaults, whitespace omission, coincident fields and independent property
groups are handled while rendering. Raw/rhythm/ms/var values remain literal tokens.
CSS-in-JS chooses numbers, quoted values and keys from the declaration structure;
escaping and field offsets are emitted together, without inspecting CSS output.

Pseudo/at-rule lookup applies authored aliases before fuzzy matching, retaining
the initial-letter guard for implicit expansion. `emmet2-fuzzy` is project-owned:
every query character consumes a distinct candidate position, exact names and
prefixes rank first, word initials receive priority, and consecutive characters
and smaller gaps improve the remaining matches. Ties keep the first input item.
Matches return both scores and character positions; the same matcher supplies
menu highlighting and host candidate ranking. No fuzzy cache is needed.
Unknown at-rules stay literal; templates change only authored layout, leaving
literal tabs untouched. Empty alias tables retain the fuzzy fallback. Plain
`css` resolves names among CSS at-rules, directly or through an authored alias,
without Sass templates. Only `:not` spreads comma arguments into chained calls.
Pseudo completion expands selector names and editable function arguments only.
It preserves authored prefixes and adds no rule bodies or declarations.

`emmet2-css-search` aligns query segments with the words of a property and,
for compact queries, of one keyword value. A segment is a whole word, a word
prefix, a skeleton that keeps a word's letters in order from its initial, or an
authored word alias; an alias claims its letters for its own word. Each
unmatched, skipped inner or skipped leading word lowers the score. The pinned
relevance of the property and the size of the keyword's value set add a prior,
so popularity decides short queries while longer queries follow their words.
Small sets that are valid but rarely written, such as system colors, take a low
fixed prior instead; explicit queries such as `cCanvas` still reach them.
Property aliases and complete names rank first without hiding other choices.
Values combine a property's own keywords, keywords reachable through its
syntax and CSS-wide keywords; function arguments and deprecated types are not
values. Obsolete properties stay canonical names but are never offered. The
frozen corpus in `test/fixtures/css-search-corpus.json` and its gates in
`emmet2-css-search-test.el` guard ranking changes; retune parameters only
against that corpus.

`emmet2-extensions-markup` accepts `:jsx`, `:variant`, `:css-modules-object`,
`:class-names-constructor`, `:indent` and `:base-indent`. Literal class names use
dot access for identifiers and escaped bracket access otherwise. Fields preserve
priority, mirrors and multiword expression spans. Whitespace-only fields remain
separate arguments. Authored class expressions are renamed for React/Solid without
interpretation. Project reference strings are emitted as source, never evaluated.

CSS/SCSS context uses `syntax-ppss`; web-mode owns its pending scanner, attribute
markers, part ranges and engine blocks, which bound markup text. Its style parts
parse with CSS syntax, or SCSS syntax for `lang` `scss` or `less`.
JS/TS/JSX requires the matching pinned tree-sitter grammar.
CSS classification starts at the extracted abbreviation, including when point is
inside a balanced raw value. Comments and strings are forbidden. Automatic analysis
also excludes values, at-rule preludes, ordinary selectors and unrelated script
expressions. A bare name and single colon at a declaration start belong to a
value position even without whitespace, unless the name is a known HTML element,
as in `button:hv`; automatic top-level selectors need `@`, `_`, a leading colon,
or a structural selector prefix or known element with a pseudo part. Explicit completion skips
confidence checks only outside built-in CSS: CSS accepts declaration starts, at-rule names and
selectors with a pseudo part, and never values, at-rule preludes, arguments or
Sass interpolation. A known, custom or vendor property before the colon leaves
the value to the host; an embedded host may permit a requested custom element.
Built-in CSS uses the automatic position policy for explicit requests too. Every
`css-base-mode` descendant, including `css-ts-mode`, is a CSS host.
Unknown major modes retain manual markup only. Missing grammars give capf nil and an explicit
completion diagnostic; HTML/CSS paths do not need additional grammars.

`emmet2-extract-css-pseudo` is the shared, buffer-independent boundary scan for
the trailing pseudo chain. Context, expansion classification and menu labels
use it instead of separate selector regular expressions. It skips escaped
colons, balanced attributes and function arguments, retaining authored selector
lists and combinators as a literal prefix. The `css-selector` extraction mode
recovers spaced headers on the current line within the host range. The host
then classifies that header from its start, so `color: .card:hv` stays a value.
Property lists such as `ovh,ta` retain their independent comma handling and
prefix reuse; selectors never enter that property-list path.

Narrowed web buffers temporarily expose the full host to its scanner and restore
narrowing afterward; accepted abbreviations must remain entirely visible. TSX error
recovery must retain complete attached Emmet text while keeping ordinary object
and expression exclusions. Astro expressions not identified by the pinned web-mode
scanner retain the documented host limitation; do not weaken the JS grammar gate.

Candidate queries, display batches, previews and acceptance recheck source and
host. Source changes invalidate the previous revision. Only candidate queries
can replace it when the abbreviation changes at the same source anchor, in the
same host and with the same settings. Switching mode/settings, narrowing away,
disabling the mode or leaving the original point/end invalidate the current
revision. Acceptance never advances a revision, and an old choice identity
cannot select a new revision's result.
Corfu accepts identical text without changing the character tick and can move
point to END; acceptance takes a fresh strict insertion snapshot. This preserves
single-writer insertion, editable fields and one-step undo for every choice.
Frontends that rewrite identical text and change the tick are rejected.
`emmet2-complete` temporarily selects only Emmet capf and invokes
`completion-at-point`, following the same pattern as Cape interactive CAPFs.
Built-in CSS uses the automatic admission rules. Other hosts retain explicit
analysis and confidence bypass, including cold JSX initialization and manual
markup. The session keeps that analysis policy while the input changes. The
frontend owns popup and sole-match acceptance; Emmet never chooses the first
candidate itself. There is no separate expansion command or default key.
Mode enable/disable owns local registration at depth -50. Corfu styles/category/
exact-match policies are described below; optional mode setup is in README.
Batch drawing replacements are never evidence of real GUI interaction.

## Completion behavior

Each menu label renders the current fragment, folding line breaks and indentation
into spaces. It applies `completions-common-part` to the positions returned by
the same project matcher for the abbreviation's word characters in the label.
An alias with no literal correspondence remains unhighlighted. Only the display
copy hides the typed candidate; acceptance keeps its original text and choice
identity. There is no provider label or expansion annotation. Only multiline
complete results supply documentation to `corfu-popupinfo-mode`, even if their
current fragment alone is one line. Their preview text
removes the renderer's source-column prefix from subsequent lines and expands
leading tabs using the source width. HTML/JSX and nested CSS keep relative
indentation; ordinary CSS declarations align at column zero. The canonical
insertion result retains its original layout and fields.

CSS completion builds at most `emmet2-capf--limit` (ten) choices for the last
property, selector or at-rule, from `emmet2-extensions-css-choices`; the first
equals the abbreviation's own expansion. When the query begins the best bare
property, up to half of the list offers that property's own keywords. A value
suffix such as `32` or `--gap` is carried to every property choice, so `ins32`
offers `inset: 32px;` and `inset-block: 32px;`. Hyphenated letters either
continue a name, as in `inset-b`, or are keyword values, as in `t-a`; the
reading whose values the best property accepts ranks first. Selectors rank the
final simple pseudo; at-rules rank names. An unmatched query offers nothing
rather than a fabricated property. Equivalent canonical results are
deduplicated. Complete names longer than one letter bypass the search; single
letters such as `d` and `r` abbreviate common properties despite SVG names.
Confidence asks for one choice; a single-choice search keeps only its best
candidate. Bare markup words in text, declaration values and unconfirmed host
positions remain with other providers; a known HTML element alone on its line
is offered. In SCSS, a Sass variable after a property, as in `m$gutter`, is a
signal, including the incomplete prefixes `p$` and `p$-`. A bare `$name` stays
with the host's variable completion; plain CSS and CSS-in-JS leave `$` to
explicit requests.

Compound CSS completion enumerates the last property through the language-owned
`emmet2-css-completions` batch. `emmet2-css-completion-parts` remains a public
string projection of the same balanced fragment splitter. A single trailing top-level comma
or plus after a property requests the preceding choices against a fresh snapshot
that includes the separator.
CSS-in-JS allows this for plus; a trailing comma belongs to the JavaScript host.
Acceptance consumes the separator; old candidate identities still cannot insert.
The confirmed prefix is everything before the last top-level comma or plus. Once the last
property is nonempty, its menu label omits that prefix without a marker, while
documentation preserves the complete result.  The table retains only its
current confirmed prefix and canonical result, so typing `ovh,ta` then `ovh,tac`,
or `m10+p5+b` then `m10+p5+bo`, neither searches nor expands the prefix again.
Editing or removing the prefix replaces or clears this slot; leaving the valid
context or changing render settings invalidates the table. When both sides use
the extension's property-list syntax, each full candidate reuses that canonical
prefix result and concatenates only its last property, preserving independent
field groups; property lists expand each property independently, so the
concatenation equals the whole expansion.
Selectors and at-rules retain whole-expression expansion. Each revision also
reuses complete canonical results for exact abbreviation keys from the
immediately preceding materialized choices. Only that preceding set survives a
transition; there is no accumulating or global result cache. Fresh choice
objects prevent old callbacks from inserting after an input round trip. Menu
labels, highlights and root-aligned previews are prepared once per choice per
revision, including reused results; display queries perform no expansion or
indentation pass. Affixation returns a copy of each label so frontend text
properties cannot change the stored projection.  Expansion remains strict about
empty properties, and JavaScript host commas and commas inside values retain
their existing meaning.

Corfu preserves candidates differing only in text properties, as for overloaded
LSP methods. Other frontends may merge these choices or strip identity properties;
they can still accept the default result. The optional `emmet2-corfu` adapter
uses Corfu's private formatting and popup entry points only for Emmet display;
candidate identity and acceptance stay in CAPF. Presentation tests exercise the
pinned Corfu's matching, affixation, acceptance and adapter cleanup.

Automatic presentation respects Corfu's prefix, delay and trigger settings.
With `basic` first, the exact candidate can remain visible for `nil`, `show`,
`insert` and `quit` policies. With `partial-completion` first, alone, or selected
by an `emmet2` category override, automatic completion skips it unless the
persistent `corfu-on-exact-match` is `show`; manual completion may expand directly.
The package changes none of these settings. With `corfu-preselect` set to
`prompt`, select the candidate before accepting it; accepting the prompt does
not expand. Valid edits refresh the table in place; leaving the context ends it.

## Data, oracle and migration authority

`data/emmet/source.json` pins Emmet 2.4.11's archive, source commit and individual
SHA-256 hashes. `test/vendor/emmet-2.4.11.mjs`, HTML snippet JSON and lorem
dictionaries are copied verbatim. The source contains 155 HTML snippets and 5
variables; resolved alias counts can differ. Emmet's CSS snippets are retired:
the project searches CSS data instead. `data/emmet/LICENSE` ships with the
native port and data; `data/COPYING` carries the project GPL license. Do not substitute newer upstream files or edit generated
vendor code. Version/hash changes need a separately reviewed data upgrade.

`test/oracle/adapter.mjs` and `test/oracle/jsx.mjs` are independent development
references for markup. The Node tests retain hand-written field, Unicode,
error, JSX, generator and CSS data checks. The generator consumes explicit
`core-inputs.json` cases; it never infers expectations from arbitrary source
strings. The 526 fixed markup cases include errors. Stylesheet output is
project-owned since the CSS snippets were retired, so neither the adapter nor
the oracle compares CSS with Emmet. `--check` regenerates in
memory and compares contents plus complete inventory without writing. Extra files
fail; nothing is silently deleted. Intentional input/contract changes require
reviewing both output files. These fixtures are not exhaustive upstream coverage.
Lorem uses 42 structural cases and five native seeds instead of random text goldens.
With authored aliases disabled, `@fa` resolves to `@font-face` rather than
`@forward`.

`data/css-source.json` pins VS Code Custom Data (CSS and HTML) and MDN data's
CSS type syntaxes by commit, hashes, schema and input counts.
`node test/update-web-data.mjs` is an explicit networked maintenance step; it
verifies all inputs before writing the full `css-data.json` metadata, the
compact `css-index.json` search index and both upstream licenses. The files are
generated together; tests verify the index against the metadata. The full
snapshot has 888 property/descriptor records including vendor entries, named
values, restrictions and documentation. The index contains 579 ordinary
properties with relevance, obsolete status, own keywords and the shared value
sets reachable through property and type references, plus the CSS-wide
keywords, 19 at-rules, 117 pseudos and 116 HTML elements. A shared set stores
only its own keywords once. Vendor names, descriptor-only entries, function
arguments and deprecated types are excluded. An `atRule` association does not
exclude ordinary use: the generator also admits entries whose source reference
identifies an ordinary CSS property. The shared query library uses this same
membership; descriptor-only entries are admitted for the supplied at-rule.
This snapshot remains pinned and offline at runtime; updating data does not
automatically add grammar support.
`css-overrides.json` alone owns authored aliases, functions and SCSS templates;
its word and property aliases belong to the search and the others to the
extension layer. The generator never writes it. Review upstream names and local
targets together.

`test/fixtures/migration.json` retains the exact baseline identities, file hashes
and replacement test IDs for all 182 old cases: 93 CSS, 19 markup and 70 regex.
Baseline files remain available at commit `3f9ddc6`; the old TS/Deno implementation
and runners have been removed. The complete native runner rejects missing
replacement tests before running them. Text expectations, extraction boundaries,
field behavior and editor integration remain separate contracts. No skipped suite
or changed expected output counts as migration evidence. Intentional changes
(first editable field, separate CSS stops, safe-context gating, Emacs 30 minimum,
plain CSS at-rules, pseudo-function lists, completion-first CSS) are recorded
in that ledger and README. `CHANGELOG.md` states every user-visible change for
users; list breaking changes first, with the configuration they must edit.

## Setup and validation

Use the versions in `test/dependencies.json`: Node 24.21.0; GNU Emacs 30.2/31.1;
pinned Corfu, compat, web-mode, yasnippet, straight.el, package-lint and five
grammars. `test/setup.mjs` creates isolated checkouts and compiles grammars. It
rejects changed checkouts and never modifies a daily Emacs installation. Bootstrap
disables grammar auto-download and fails for missing locked dependencies.

```sh
rtk proxy npm ci --ignore-scripts --no-audit --no-fund
rtk proxy node test/setup.mjs /tmp/emmet2-test-deps
rtk proxy npm run lint
rtk proxy npm test
rtk proxy npm run oracle:check
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps emacs --batch -Q -L . -l test/byte-compile.el
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps emacs --batch -Q -L . -l test/package-quality.el
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps emacs --batch -Q -L . -l test/integration.el
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps emacs --batch -Q -L . -l test/editor-bytecode.el
```

Repeat Elisp checks with both pinned Emacs builds. Scoped development suites remain
available through `EMMET2_TEST_SUITE`: contracts, results, native, markup-spike,
stylesheet, markup-extensions, css-extensions, fuzzy, editor and completion. Invoke
`test/emmet2-test.el -f ert-run-tests-batch-and-exit` after selecting one.
The full integration runner includes all of these contracts, compares the full
canonical core results and rejects synchronous/asynchronous process creation with
an empty `exec-path`. The bytecode runner exercises real compiled editor and
optional dependencies; a copied payload is not a package-manager installation.

Compilation treats project warnings as errors. Fixed third-party warnings remain
visible. `package-quality.el` checks every runtime library with package-lint and
checkdoc; all diagnostics fail. The compiler runner is named `byte-compile.el` to
avoid shadowing Emacs's built-in `compile.el`. ESLint recommended rules and
`prefer-const` replace the retired Deno lint step. Only immutable third-party
vendor output and ignored working plans are excluded. For meaningful JS edits,
query ESLint MCP and file-scoped Wallaby first; no Wallaby data is inconclusive,
so use the Node runner for module-load, process and filesystem behavior.

CI uses the same commands on Ubuntu 24.04. `test/build-emacs.mjs` verifies official
GNU release archive hashes and builds a private static tree-sitter 0.25.10, avoiding
the removed system 0.27 API. It needs Git, Make, C tooling, tar/xz, pkg-config and
terminal development headers; it never installs into system libraries. Build
directories must be new, and failures preserve `build.log`. The oracle additionally
runs in a Linux network namespace with no network and Node's read-only filesystem
permission. Node's permission flag alone is not claimed to deny networking.

## Actual installation

After a reviewed commit, install that exact HEAD in a new directory:

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_INSTALL_ROOT=/tmp/emmet2-install-new emacs --batch -Q -l test/install.el
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_PACKAGE=/tmp/emmet2-install-new/straight/build/emmet2-mode emacs --batch -Q -l test/integration.el
```

The runner uses pinned straight.el and README's `:files (:defaults "data")`
recipe. Only the fetch source differs: it clones reviewed local HEAD. It removes
source fallback before compilation, verifies revision, all runtime/data/license
resources and installed bytecode, and rejects development JS/TS or test payloads.
The runtime phase has an empty executable path and rejects processes. Its
`acceptance.json` records the precise SHA, versions, resource/test counts and
runtime isolation. Existing destinations are rejected and successful artifacts
remain for inspection. The second command reruns all contracts against installed
bytecode. No daily user configuration is loaded or changed. Node used to build
test dependencies or verify the oracle is not a runtime package dependency.

## Review, performance and acceptance evidence

For each feature, identify its owning subsystem and check the architecture before
implementation; then test, measure affected hot paths and review the final diff.
Before adding state or synchronization, justify why the existing owner or a derived
value cannot serve the requirement. Keep working plans consistent with implemented
behavior. Commits, pushes, merges and publication require their own authorization;
a successful local check does not authorize them.

Performance protocol, exact inputs, budgets and reproduction commands live in
[test/PERFORMANCE.md](test/PERFORMANCE.md). Measure bytecode on the fixed machine,
normal GC and independent processes; retain raw samples, maxima, warmups, failures,
source hashes and complete output validation. Parser-only timing cannot establish
whole-flow performance. Screen painting, input latency and Eglot behavior require
real GUI evidence; do not infer them from batch measurements.

The [2026-09-28 search review](test/performance-search-2026-09-28.md) records the
data-driven matcher, bounded completion reuse and current measurements. It keeps
the remaining broad-candidate and S7 tail-latency limits explicit; the older
performance reports do not establish acceptance for the new search implementation.

Historical reports remain tied to their original revisions:

| Evidence | Recorded scope |
|---|---|
| [Context](test/performance-context-2026-09-27.md) | Full analysis chain and later TSX regression checks |
| [Editor](test/performance-editor-2026-09-27.md) | Former Node default; complete command/Corfu/yas paths with drawing replaced |
| [Markup](test/performance-markup-2026-09-27.md) | Complete native core, JSX and seeded lorem |
| [Stylesheet](test/performance-stylesheet-2026-09-27.md) | Complete native CSS, including six-property p99 budget |

Detailed historical S0–S7.4 checkpoints remain in the
[pre-retirement development ledger](https://github.com/P233/emmet2-mode/blob/cebefeb5248feff3558a1781f5464a7693dd68e6/CONTRIBUTING.md).
They are historical evidence, not current development commands. At `cebefeb`, both
versions passed native source/installed 257 tests (1699 public calls), reference
253 tests (1674 calls), 75 bytecode and 52 actual-install checks. Hosted
[run 36319117967](https://github.com/P233/emmet2-mode/actions/runs/36319117967)
passed all jobs. New revisions require their own applicable validation.

Real web-mode/TSX+Eglot/Corfu/yas functional GUI acceptance passed on Emacs 31.1
through user-operated checks on 2026-09-27. The user confirmed the completion
matrix, session invalidation, fields, host boundaries and final edge cases.
The [acceptance record](test/gui-acceptance-2026-09-27.md) distinguishes the
isolated installed-bytecode session from the final daily-configuration checks.
Computer Use still could not read Emacs; this is user-reported manual evidence,
not automated GUI success, screenshot evidence, GUI timing or Emacs 30 GUI coverage.

S8 local checkpoint (2026-09-27): Emacs 30.2/31.1 each passed 277 complete native
checks / 1711 public core calls, 76 bytecode checks, warning-free project compilation
and package-lint/checkdoc across all 11 runtime libraries. All 257 S7.4 integration
identities survive in the unified runner; all 182 baseline mappings and 973 oracle
inputs/results remain unchanged. The bundle/license relocation preserves bytes.
All 23 Node development tests, ESLint MCP and CLI lint, oracle checks with read-only
permissions, and actionlint passed. Wallaby returned no data. Linux network
isolation and the revised exact-commit installation remain post-commit CI/installation
gates at that checkpoint; the later manual GUI result is recorded separately
above. No new performance improvement is claimed.

The [2026-09-30 architecture measurements](test/performance-architecture-2026-09-30.md)
record the refactor's frozen A/B comparison and remaining acceptance work.
Correctness passes do not close its two failed Web performance gates or GUI gap.
