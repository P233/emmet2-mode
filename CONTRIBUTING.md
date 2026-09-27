# Development and native rewrite

The installed mode still uses the original Deno bridge. The native rewrite is
in progress; vendoring data does not switch the runtime or change user behavior.
Do not use the new design as evidence that a milestone has shipped.

## Baseline and migration

The starting revision is `3f9ddc6`. On 2026-09-26, Deno 2.9.7 passed all existing
tasks: 93 CSS, 19 markup and 70 regex cases. These tasks intentionally use the
existing `--no-check` setting; this is test evidence, not a type-check claim.

```sh
rtk proxy deno task test:css
rtk proxy deno task test:markup
rtk proxy deno task test:regex
```

`test/fixtures/migration.json` maps every baseline test by source, ordinal ID,
name and line. Duplicate test names are separate cases. `tests: []` means no
replacement has passed yet. Fill it with concrete new test IDs only after
running those tests. Preserve the baseline identity when the old files retire.
The integration and intentional-change lists cover contracts that the 182
pure-function tests cannot establish, including README examples, host modes,
project options, insertion, packaging and resource lifetimes.

Do not turn the regex suite into a core expansion oracle. Migrate its extraction
and extension behavior to the layer that owns it. Record intentional behavior
changes explicitly; do not silently change expected output or count skipped
tests as migrated coverage.

## Ownership and contracts

- `emmet2-context` owns host classification and source-buffer parser lifetimes;
  `emmet2-extract` alone computes abbreviation bounds.
- The pure engine returns text, positive editable-field groups and an initial
  cursor, using zero-based character offsets and half-open field intervals.
  It never reads or writes an editor buffer.
- Markup preserves real mirror groups. CSS fields belong to one parsed property;
  identical upstream numbers in different properties are independent. Upstream
  zero is an editable field, not the final snippet exit. If one upstream number
  has different default texts, those defaults form independent groups so that
  snippet insertion cannot silently overwrite the authored text.
- Extensions own opinionated syntax and all transformations of text and fields,
  including removal of CSS defaults. No later layer repeats this cleanup.
- `emmet2-insert` is the only active source-text writer. It checks source/range/
  content, inserts atomically, encodes literal snippet text safely and creates
  the final yas exit at the end. Without yas, it uses the same initial cursor.
- Completion candidates contain the original abbreviation; annotation and docs
  contain the expansion. Only a valid `finished` callback expands. The selected
  custom try semantics can bypass Corfu's exact insert/quit policies; test the
  effective styles/category settings instead of guessing from `basic` membership.
  Do not mutate the user's completion settings or add label-recovery state.

The Node backend is temporary: one process and one request, with a deadline for
the whole expansion. Cancellation before a complete response destroys that
process. S7 must prove the complete Elisp backend before Node runtime files and
their protocol tests are retired. The offline development oracle may still use
Node after the package runtime becomes pure Elisp.

## Data and test authority

`vendor/emmet-source.json` pins the npm 2.4.11 archive and matching source commit.
The archive integrity was verified before extraction. The bundle and JSON files
are copied verbatim, never formatted or edited. In particular, the earlier
research checkout was newer than the published package; it is not the oracle.
The pinned raw files contain 155 HTML snippets, 249 CSS snippets and 5 variables.
Aliases can produce a different number of resolved keys.

The vendor directory is excluded from Deno lint because it is unmodified
third-party generated code. Hand-authored source and tooling remain checked.
Use a separate explicit upgrade to change vendor versions, checksums or fixtures.

The S0 reference tools use Node 24.21.0 (including `import.meta.main`) and need
no network or node_modules:

```sh
rtk proxy node --test test/oracle/adapter.test.mjs
rtk proxy node --test test/oracle/gen.test.mjs
rtk proxy node test/oracle/gen.mjs --check
rtk proxy deno lint emmet2-engine-node.mjs test/oracle
```

`emmet2-engine-node.mjs` is the fixed-version output adapter; it has no process
or editor state. The Node protocol server imports this same normalization
path. The installed mode has not switched to this module yet.

`core-inputs.json` contains an explicit input list: every pinned HTML/CSS alias,
plus hand-selected markup, JSX, fields, Unicode, formatting and error cases.
It is a starting corpus, not a claim of complete upstream feature coverage.
Larger parser/formatter and lorem structural suites are still required before
the S6/S7 engines can be accepted. Do not infer test cases by scanning arbitrary
source string literals during generation.

After an intentional input or contract change, run the same generator without
`--check` and review both JSON outputs. Check mode regenerates in memory and
compares contents and the entire output file list without writing. Unexpected
files fail; the generator never deletes them automatically.

Hand-written field, Unicode and error assertions must pass before generated
goldens are accepted. The core oracle, extension behavior and editor integration
remain separate suites; a shared adapter cannot be its own only correctness
proof. Clean CI and the remainder of the S0 gate are still pending.

## Isolated Emacs contract tests

`test/dependencies.json` records exact package/grammar revisions, official Emacs
30.2/31.1 release tags and source archive hashes. Initial probes used the locally
installed 31.1 reporting `fac6532`; that revision was not available from the
upstream mirror, so reproducible builds use the official release archives.
Test setup requires Node, Git and a C compiler on macOS or Linux.
It downloads into an explicit directory outside the working tree and compiles
the locked grammars there. jsdoc is needed by the pinned Emacs 31 `js-ts-mode`
itself; Emmet's context analysis uses javascript, typescript and tsx only.
Setup refuses to replace modified dependency checkouts.
It does not install into the user's Emacs configuration.

```sh
rtk proxy node test/setup.mjs /tmp/emmet2-test-deps
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

Run setup after changing the lock. `EMMET2_TEST_SUITE` selects `contracts` (the
default), `editor`, `completion`, `results`, `node`, `fuzzy`, `css-extensions`
or `markup-extensions`; unknown suites fail explicitly. Missing
packages or local grammars fail bootstrap instead of skipping integration or
falling back to a grammar in the user's configuration.

The four Corfu tests exercise its pinned completion control flow with only
popup drawing replaced. They cover the original candidate, effective styles
and category override, all four exact-match policies, automatic/manual entry,
prefix threshold, cancellation and explicit acceptance.
S5 now runs these same cases through production context, Node and insertion;
the S0 table implementation has been deleted. This is batch integration evidence,
not GUI acceptance. Private Corfu calls remain confined to tests; production
uses the public completion API and never changes completion settings.

The host probe calls the bounded `emmet2-extract` scanner with real buffer point,
then confirms context using a tagged tree-sitter parser. It keeps one identifier
character from the candidate in the parser's included ranges; deleting the
entire candidate loses expression structure. The original host braces remain
outside the candidate. Tests exercise TSX and web-mode JSX/TSX, raw values,
middle positions, named CSS calls in JS/TS/web script, root/map manual entry,
and negative expression/attribute/object/call/string/comment cases. Source and
point must remain unchanged, and the probe deletes its parser even on failure.

JSX `Hello{items.ma}` is ambiguous with Emmet `tag{text}`. Automatic completion
leaves a plain prefix plus JSX expression alone, including immediately after
the closing brace. The explicit command may expand `tag{text}`; a bare JSX
expression is still rejected. This confidence boundary preserves existing
manual text expansion without treating valid JSX expressions as abbreviations.

The original 93 host paths now call `emmet2-context.el`; the test-only classifier
has been removed. The production JS/TS/JSX path derives its parser inventory
from Emacs. Each buffer view owns distinct `emmet2` and `emmet2-projection` tags, one
source/projection parser pair per supported grammar (six parsers at most),
and one pending idle timer. A literal shared tag would
be unsafe because indirect buffers share base-buffer parser storage. Default
`treesit-parser-list` also hides tagged parsers, so all ownership checks and
cleanup use the explicit tag. Major-mode parsers and other views are preserved.

Automatic analysis uses warmed parsers; a cold call schedules idle preparation
and returns nil. Explicit analysis initializes on demand and names a missing
grammar. Original comments, strings and regexes are rejected before projection.
Source edits reuse separate source/projection trees and ten fixed compiled
queries. Initial analysis uses the complete host. A valid projection can retain
the nearest complete JSX element or closed top-level declaration as a local
unit. Each grammar retains at most one marker pair; no abbreviation, result or
source node is cached. Edits touching or outside the unit, cursor/part switches,
and modifications from another indirect view invalidate it. Character ticks
also detect edits with modification hooks inhibited. Automatic analysis waits
for idle preparation after invalidation; explicit analysis initializes on demand.
Every local projection must still parse as one complete, error-free unit or
retry once against the full host. Unterminated block comments recovered as
invalid regex syntax remain forbidden. Stop, major-mode change and kill detach
markers, remove hooks and cancel resources; stale callbacks cannot act on a
replacement owner.

Local S3.0 evidence (2026-09-27): the 93 paths and ten ownership/context tests
pass on pinned GNU Emacs 30.2/31.1, including missing grammars, empty/narrowed
buffers, indirect-buffer isolation and base-buffer destruction. Compilation
with warnings as errors passes. Idle callbacks are driven deterministically
in ERT; GUI idle scheduling, HTML/CSS adapters, full extraction migration and
the complete performance gates remain open. The bounded scanner has no mode
or parser state. These developer APIs are not yet connected to the minor mode.

`emmet2-engine.el` owns the pure canonical result and error types. Its constructor
validates character offsets/defaults, preserves mirror priority, renumbers groups
and derives cursor. `emmet2-result-concat` isolates groups between results;
`emmet2-result-splice` rebuilds covered fields, shifts surviving boundary fields
and rejects partial overlap. Neither mutates inputs. New splice groups precede
the first replaced group (or next field group); surviving groups keep their
relative order. CSS-specific default removal and coalescing remain S2 work.

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=results emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

Six result tests cover Unicode, mirrors, invalid intervals, concat isolation,
splice boundaries and all successful committed oracle result shapes. They do
not execute an Elisp engine or the Node protocol.

## Temporary Node API

`emmet2-engine-expand` accepts an abbreviation, a preset symbol (`html`, `jsx`
or `stylesheet`), and literal `:indent`/`:base-indent` strings. It returns the
canonical result. `emmet2-engine-with-expansion` gives a group of core calls one
shared one-second deadline, including startup, decoding and result transforms.
S2 must wrap an entire extension expansion so multiple properties do not each
receive a fresh second. The installed minor mode still uses the old bridge;
this developer API does not switch editor commands or add insertion yet.

The channel owns one process and one pending request. Reply fragments are
attached to their originating process, validated by request ID and result
schema, then converted at the boundary. Timeout, quit, nonlocal cancellation,
incomplete exit and protocol/backend failure dispose of the process and its
diagnostic buffer. The next call starts a new process; no current call retries.
A complete parse error signals `emmet2-parse-error` with `(MESSAGE POSITION)`
and leaves a valid process reusable. Backend faults use `emmet2-backend-error`.
The server preserves the original parse diagnostic in the JSON error payload.
Stopping/unloading the backend and exiting Emacs clean up its owned resources.

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=node emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

This suite compares all 494 core oracle cases across the real process boundary
and has independent field/Unicode/error assertions. Its fault process covers
partial/malformed replies, invalid fields/IDs, split UTF-8, request/idle death,
shared startup/multiple-call deadlines, missing Node, cross-buffer reentry,
quit/nonlocal unwinding, stale filter isolation and actual feature unload/reload.
Keyboard input cancellation is simulated in ERT; real editor interactions remain
part of S4/S5 acceptance. `test/node-fixture.mjs` is only a fault injector.

## Build and CI

`test/build-emacs.mjs` builds the pinned GNU release archive and a private static
tree-sitter 0.25.10. The latter avoids the removed API in system tree-sitter 0.27
that prevents Emacs 30 from compiling. It requires Git, Make, a C toolchain,
tar/xz, pkg-config and terminal development headers; CI installs those on
Ubuntu 24.04. It does not run `make install` or change system libraries.
The build directory must not exist; failed builds keep `build.log` for diagnosis.

```sh
rtk proxy node test/build-emacs.mjs 30.2 /tmp/emmet2-build-30
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps /tmp/emmet2-build-30/emacs/src/emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps /tmp/emmet2-build-30/emacs/src/emacs --batch -Q -L . -l test/compile.el
```

Repeat with `31.1` and a separate new build directory. `test/compile.el` compiles
only implemented rewrite files, treats warnings as errors and deletes its own
temporary `.elc` output. It does not compile/load the old Deno mode as though it
were the new implementation. Extend its explicit list with each module.

`.github/workflows/test.yml` pins action SHAs and reads runtime versions from the
lock. It runs the two Emacs builds, stage-scoped ERT, byte compilation, oracle
tests/check, scoped tooling lint and the original Deno baseline. Oracle check
also runs under Deno with network access denied. CI has read-only repository
permissions, does not publish, and does not install npm packages.
Hosted execution remains unverified until a pushed commit actually runs there;
local checks and workflow lint do not establish hosted CI acceptance.

Fixed-machine performance gates and reporting requirements live in
[test/PERFORMANCE.md](test/PERFORMANCE.md). Timing is not asserted in CI.

## Review and milestones

For each independently validated slice:

1. Inspect the complete uncommitted implementation with `mode=primary`, fix
   confirmed issues, perform its residual scan and follow up as required.
2. Run the read-only final review. Commit only the reviewed implementation with
   normal hooks; preserve unrelated working-tree changes. Do not push.
3. After the commit, re-evaluate the next slice against the actual contracts,
   measurements and remaining risks. Update the execution plan before proceeding.

S0 establishes the pinned oracle and context/completion probes. S1 adds the
temporary Node API; S2 the extensions; S3 host analysis; S4 insertion and the
runtime switch; S5 completion, preview and actual M1 installation. S6/S7 supply
and validate the native engines before M2. S8 retires temporary runtime and test
entry points and verifies the final installed package.

MCP gaps must remain explicit. Wallaby returned no data for the three legacy
test files during baseline capture; the repository Deno tasks supplied evidence.
Both GNU Emacs 30.2 and 31.1 were built from the locked archives with the build
script on macOS. All 9 S0 ERT tests and warning-free byte compilation passed on
both. Node 24.21.0 passed 12 adapter/generator tests and the 494-case offline
oracle check. The workflow passes actionlint. Hosted Linux CI, GUI flows,
installed-package checks and native performance are not yet validated.
ESLint MCP has no configuration in this Deno repository. A scoped Deno lint
check of unchanged `src/index.ts` reports the existing inline-URL import under
Deno 2.9.7's `no-import-prefix` rule. Do not weaken that rule or rewrite the old
bridge merely to admit the vendored data; migrate its runtime in S4/S8.

Performance checks use fixed inputs, bytecode, normal GC, at least 100 warmups
and 1,000 samples per group, repeated three times. Report cold time, p50/p99/max
and GC costs. Do not put machine-specific timing assertions in ERT or infer
whole-flow performance from parser or matching microbenchmarks.

## CSS extension data and fuzzy matching

`data/css-source.json` locks vscode-custom-data to one commit, SHA-256 hashes,
schema and exact raw counts. Run `node data/update-web-data.mjs` only as an
explicit networked maintenance step. It verifies all inputs before writing
`css-names.json` and the upstream license. Generated names are sorted, deduplicated
and omit vendor prefixes. The pinned data contains 19 at-rules and 117 pseudos.
An upgrade must review the manifest, generated diff and local functional names.
`css-overrides.json` alone owns pseudo functions, aliases and SCSS templates
(literal text plus cursor offset); generation never writes it or legacy data.

`emmet2-fuzzy.el` ports the published Emmet algorithm, including candidate
position reuse, partial suffixes, early exact hits and later nonzero tie wins.
The caller owns syntax prefixes and alias priority. S2 extensions and S7 core
resolution share this module; no fuzzy cache or additional state is introduced.
This does not yet switch the installed runtime or mark legacy cases migrated.

```sh
rtk proxy node --test test/css-data.test.mjs
rtk proxy deno lint data/update-web-data.mjs test/css-data.test.mjs
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=fuzzy emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

Local S2 data evidence (2026-09-26): pinned regeneration ran twice with identical
outputs and unchanged override/legacy files; all alias and function targets
exist in the pinned names or local templates. Two generator tests and two fuzzy
ERT tests passed; warnings-as-errors compilation passed on both pinned GNU
30.2/31.1 builds. Scoped Deno lint and actionlint passed. ESLint MCP has no
project config and Wallaby reports no data, so these results use the documented
Node/ERT/lint fallbacks. Hosted Linux CI and extension integration remain open.

## CSS extensions

`emmet2-extensions-css` accepts one abbreviation plus `:css-in-js`, `:indent`
and `:base-indent`. It wraps the entire expansion in one deadline. A balanced
scanner splits only top-level comma/plus separators. Aliases feed individual
property expansions; default removal and first-whitespace normalization happen
once per property, before concatenation. Fields collapsed to one position merge
within that property, including their mirrors and right-boundary empty fields.
Explicit raw/rhythm/ms/var values replace the entire core value and its fields.
CSS-in-JS escapes string contents, quotes non-identifier keys and remaps fields.

Pseudo/at-rule lookup applies authored aliases before prefix-free, non-partial
fuzzy matching. Known legacy `:fo` (first-of-type) and `:f-l` (first-letter) also
have aliases so data ordering cannot silently change those public inputs.
`:has(+p)` now expands correctly; nested/raw separators and JS quotes/backslashes
are intentional fixes. Unknown at-rules such as `@i+` remain literal. Templates
apply layout parameters only to authored layout, leaving raw literal tabs alone.

`test/fixtures/css-legacy.json` copies all 93 baseline CSS text expectations,
removing only the old cursor marker. Each has its own `emmet2-css-legacy-css-NNN`
ERT test; independent complete-result assertions establish fields and cursor.
The migration ledger maps those 93 and 42 CSS-related regex cases to tests that
actually ran. This preserves behavior without retaining the old regex design.
The remaining markup/extraction/editor entries are still unaccepted.

Local validation on 2026-09-26: all 102 CSS ERT tests passed on the pinned GNU
30.2 and 31.1 builds. The hand-written cases cover default collapse, distant
mirrors, explicit replacement, raw nesting/Unicode, CSS-in-JS escaping/numbers,
functions/aliases/fallback, layout and a deterministic whole-expansion deadline.
Runtime command/completion behavior is not switched by this module. JSX
extension completion and the revised ownership are recorded below.

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=css-extensions emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

## Structured JSX extension boundary

`emmet2-extensions-markup` accepts markup plus `:jsx`, `:variant`,
`:css-modules-object`, `:class-names-constructor`, `:indent` and `:base-indent`.
It passes explicit JSX settings through the existing single-request channel;
omitted settings serialize as JSON null, not an empty object. Core presets
without settings keep exactly the committed oracle output.

The original plan placed all JSX conversion after core rendering. A concrete
counterexample, `[class='a" title="b']`, renders indistinguishably from two
attributes in unmodified Emmet. Post-render regex parsing cannot recover the
class value, and can corrupt text that merely resembles an attribute. Therefore
`emmet2-jsx.mjs` temporarily owns JSX class conversion **before** serialization,
on a copied AST. No marker protocol, output parser, cache or second request is
introduced. S6 must port this contract beside the Elisp markup formatter; S8
retires the temporary JS module with the Node runtime. The final pure Elisp
objective and canonical text/fields/cursor result are unchanged.

Literal class names use dot access for identifiers and escaped bracket access
otherwise. Their fields retain numeric priority and real mirrors; multiword
field defaults cover the corresponding expression span. Whitespace-only fields
remain separate editable arguments, so mirrors cannot collapse into adjacent
fields at one position. Authored class expressions are renamed for React/Solid
without interpreting them; explicit classList/className and body text stay as
authored. Project reference strings are emitted as source, never evaluated.

`markup-legacy.json` preserves the 15 baseline expansion text cases; 4 extraction
cases remain S3 work. All 150 S2 baseline IDs now map to executed ERT assertions.
Initial cursor/field behavior deliberately follows the canonical result, not
the previous single pipe marker. Actual yas/undo/completion remain S4/S5 gates.

Local evidence (2026-09-26): 18 markup ERT tests and the 12 Node protocol tests
(including 494 core oracle cases) passed on both pinned Emacs builds; selected
CSS contracts remained green. Seven JSX tests (including 36 field/whitespace boundary combinations) and nine adapter tests passed in
Node; fixed core oracle check has no changes. Both warning-free compilations,
scoped Deno lint and actionlint passed. MCP ESLint still has no config and
Wallaby has no data. Hosted CI, editor integration and performance acceptance
remain open; this completes S2's local functional scope only.

```sh
rtk proxy node --test test/jsx.test.mjs
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=markup-extensions emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

Primary review found and fixed duplicate class emission when a nonempty field
starts at a preceding word end; the half-open intersection rule and boundary
matrix now cover that case. No core oracle or baseline expected text changed.

## CSS and web host analysis

The lexical context adapter uses `syntax-ppss` in CSS/SCSS and web-mode's own
pending scanner, attribute markers and part ranges in HTML/CSS. It adds no
parser or cached parse result. CSS classification happens at the extracted start,
so a point inside a balanced raw value still selects the complete abbreviation.
Comments and strings are forbidden. Automatic analysis also excludes values,
at-rule preludes and ordinary selectors; explicit commands retain manual CSS
positions. Unknown major modes retain manual markup only.

The extractor's CSS syntax treats host braces as boundaries, even following an
unfinished function/raw value; balanced braces inside raw values are retained.
HTML style values are bounded by their own quotes, and markup by actual tag
markers. An unfinished HTML tag whose value markers have been lost returns nil.
The CSS part's exclusive end comes from its property change: web-mode's helper
can otherwise return the last character at the end but a boundary elsewhere.
At-rule preludes stop at completed semicolons/blocks, including on the same line.

All 38 planning position probes are ERT assertions. Additional real-point cases
cover start/middle/end, pending rescans, cross-part edits, missing tree-sitter,
tight block/tag boundaries, attributes, raw values and negative contexts. The
remaining 32 legacy extraction cases now map to executed assertions; all 182
baseline IDs are accounted for. This is functional migration evidence, not
editor insertion, completion, GUI, installed-package or performance acceptance.
Astro expressions not marked by the pinned web-mode scanner retain the recorded
limitation; this is not used to relax the JS/TS/JSX grammar boundary.

Primary review reproduced out-of-range scans in narrowed web buffers. Analysis
and idle preparation now temporarily expose the complete host to web-mode and
restore narrowing afterward; accepted candidates must still lie fully inside
the original visible range. Tests cover CSS parts, style attributes and script
owners, including rejection of a partially hidden abbreviation.

Local evidence (2026-09-27): 51 context/extraction ERT tests, including the 93
JS host paths and 38 lexical probes, pass on both pinned GNU Emacs 30.2/31.1
builds; warning-free compilation also passes. This completes the current S3
functional slice. Full-path timing remains the next gate before the S4 switch.

### S3 context performance work

`test/bench-context.el` measures complete analysis using 22 fixed fixtures,
including source edits and web-mode pending scans. It records cold setup,
100 warmups and 1,000 raw samples per fixture/path with normal GC. The paths
are unchanged reads, `self-insert-command` typing, and programmatic `insert`,
each followed by analysis. These edit methods exercise different web-mode
property inheritance and must be reported separately. Pinned web-mode is loaded
from source by the isolated bootstrap; the report records this explicitly.

Run three fresh processes with distinct output paths, as documented in
[test/PERFORMANCE.md](test/PERFORMANCE.md). The runner compiles production code
into a temporary directory and rejects mixed evidence if measured source files
change while it runs. Fixture/source hashes and the dependency lock identify
the inputs. Filters are for diagnosis, never acceptance.

Local correctness evidence: 68 scoped context/extraction tests pass on pinned
Emacs 30.2 and 31.1, including local-unit invalidation, indirect edits, malformed
host structure and unterminated comments. S3 local correctness and performance
gates now pass: three fresh interleaved processes, 22 fixtures and 10000 samples
per path meet every existing budget. See the measured report below for raw
hashes, GC maxima and earlier failures. No editor entry point has been switched,
and no GUI or hosted acceptance is implied.

For HTML with web-mode's `none` engine, the context owner can retain one pending
insertion extent: two rule markers, the exact change positions and the expected modification tick. Before a
single insertion, its existing CSS rule must be fully scanned and contain no
angle brackets. Afterward only one ASCII letter, digit, underscore or hyphen
qualifies. Tokenization still uses `web-mode-scan-region`; only a successful
scan acknowledges the matching pending change. Deletion, replacement, repeated
edits, markup-sensitive rules, other engines/content types and unobserved edits
use normal scanning. The extent is detached on the next edit, scan, stop or
mode/buffer teardown. It retains no syntax or expansion result.

Tests compare all text properties against a full web-mode rescan, including
strings, comments, nesting, Unicode, part switches, hidden buffer regions and
configuration changes and nested hook edits. A scan error preserves the pending change and restores
narrowing/point. The current measurements and retained failures are recorded in
[test/performance-context-2026-09-27.md](test/performance-context-2026-09-27.md).

## Native command and insertion boundary (S4)

`emmet2-mode` now loads context, extensions and the single `emmet2-insert`
writer. It no longer requires or starts deno-bridge. Node starts lazily for an
actual expansion; disabling a buffer releases its context owner, while package
unload also stops the shared interim backend. The old TS implementation remains
only for migration/reference tests until S8 removes it.

`emmet2--expand-analysis` derives layout before calling the existing extension
layer. The formatter's final result is shared with insertion and the upcoming
S5 preview. Indentation uses the active mode's width, tabs where aligned, and
the abbreviation's display column. The writer checks buffer/mode/tick/point,
visible bounds and original text, then uses a single atomic undo group. A yas
before-expand hook cannot silently replace changed source. No-yas insertion
uses the identical canonical text and cursor.

The optional yas adapter escapes literal body/default text and creates the
final `$0` itself. It restores escaped Y last to avoid collisions with yas's
internal `YASESCAPE...PROTECTGUARD` strings, including authored guard strings.
One lazy module-owned advice suppresses the newline that yas's protection
overlay helper otherwise inserts for EOF fields, only inside Emmet's snippet
environment. Emacs clips the protection overlay to the buffer end; normal yas
fields keep their behavior. Unloading `emmet2-insert` removes the advice.
Only web-mode's built-in reindent exit hook is excluded for these snippets;
other user hooks and buffer settings are preserved. These narrow adaptations
have regression tests against the locked yasnippet/web-mode dependencies.

Run the stage-scoped editor suite after bootstrap:

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=editor emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

The suite exercises actual command/backend/host buffers, independent CSS stops,
mirrors, hostile literal text, EOF fields, cursor/undo/rollback, stale source,
project options and mode/unload cleanup. Batch editor checks are not GUI,
completion or actual package-installation acceptance; those remain S5 work.

Local S4 evidence (2026-09-27): 24 editor ERT tests pass on both pinned Emacs
versions, both from source and with project/yasnippet/web-mode bytecode. The 68
context/extraction tests remain green. Project warning-as-error compilation,
actionlint and diff checks pass. The compiled editor runner owns and removes
its temporary runtime copy; fixed web-mode dependency warnings are reported,
not treated as project warnings or hidden by editing the dependency.

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps emacs --batch -Q -L . -l test/editor-bytecode.el
```

The copied test payload is not a package-manager install. Hosted CI and GUI
acceptance are still unverified; the source and compiled editor checks are
registered in the existing 30/31 workflow for its next run.

### S5 completion session integration

`emmet2-capf` owns one immutable source snapshot and one lazy result per returned
completion table. Metadata and a frontend's prefix check do not expand. Text
edits, mode/settings changes, narrowing away from the range, disabling the mode,
or leaving the original point/end invalidate the session. Every candidate query
and acceptance rechecks the production context. No global expansion cache,
source-restoration logic, frontend advice or frontend configuration binding is
used. The table returns the original abbreviation for exact `try-completion`;
all/test matching and predicates retain their standard semantics.

Real Corfu acceptance of an identical abbreviation preserves the character tick
but may move point to END. The capf validates that transition and captures a fresh
strict insertion snapshot immediately before calling the unchanged writer.
Other frontends that rewrite identical text are conservatively rejected if the
character tick changes. Only `finished` inserts; `exact`, prompt acceptance and
cancellation leave text alone. Annotation is bounded to 60 display columns plus
a two-space separator. The optional documentation preview is described below.

`emmet2-complete` initializes context explicitly (including grammar diagnostics),
then invokes public `completion-at-point` with only Emmet in the temporary hook.
It keeps the automatic host/confidence gate and does not fall through to other
providers. Mode enable/disable owns registration at local depth -50.

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=completion emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```

The scoped suite covers real frontend policy/acceptance, middle-point completion,
prompt selection, stale-source refusal, lazy expansion, confidence gates and
mode/command isolation. `editor-bytecode.el` also compiles the pinned Corfu core
and auto extension and reruns these contracts alongside insertion tests. Neither
batch drawing stubs nor the bytecode resource copy constitute GUI or actual
package-manager installation acceptance. M1 remains open.

### S5 colored documentation

The capf's `company-doc-buffer` callback reuses the session's canonical result;
annotation, documentation and acceptance cause only one expansion. The shared
`emmet2--output-syntax` derives HTML/JSX/CSS from the existing host analysis and
project options, so Solid and CSS-in-JS use the JSX highlighter.

`emmet2-preview` owns at most three lazily created, read-only, non-file buffers.
Built-in `html-mode`, `js-jsx-mode` and `css-mode` provide fontification without
additional grammar requirements. User mode hooks are delayed and discarded;
mode-change hooks are isolated during creation. There is no timer, background
work or second result cache. Deleted buffers are recreated on demand. Module
unload and package unload clear owned buffers, bypassing close-confirmation
queries only for those buffers so ownership cannot be silently lost. Ordinary
kill hooks still run. A failed mode initialization also releases its buffer.

The completion suite tests exact preview text, fontification, three-buffer
capacity, reuse/recreation, hook isolation, failed initialization, unload and
the pinned popupinfo documentation callback. The bytecode runner includes the
preview module and popupinfo extension. The real popupinfo callback preserves
font properties; its popup drawing is still outside batch acceptance. Cold and
repeated preview costs belong to the forthcoming complete-flow measurements.

### S5 actual installation acceptance

`test/install.el` uses the pinned straight.el checkout from the test dependency
lock. It loads that checkout's source without rebuilding it, creates a fresh
isolated configuration and asks straight to clone the reviewed local Git HEAD.
The README file recipe is unchanged; only the repository fetch source differs
so unpushed code can be tested. No daily Emacs configuration is loaded or changed.

The runner removes the source directory from `load-path` before package build,
checks the installed revision, all 26 current runtime/data/license resources,
library resolution and actual bytecode, then exposes only Node on the runtime
PATH. It runs the editor, completion and preview contracts against that installed
package. The resulting directory and `acceptance.json` remain for inspection.
An existing destination is rejected, never overwritten or deleted.

```sh
# Run setup again after the addition of straight.el to the lock.
rtk proxy node test/setup.mjs /tmp/emmet2-test-deps
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_INSTALL_ROOT=/tmp/emmet2-install-new emacs --batch -Q -l test/install.el
```

The official 30.2 and 31.1 local builds each pass all 48 installed-package tests
at runtime revision `1bd9b5c`. This is a real package-manager build, including the
bundled Node files, data and license files; it does not claim the GitHub fetch,
hosted Linux CI or GUI matrix has been accepted. The 30/31 workflow now includes
this installation check for its next execution.

### JSX text under parser error recovery

The S5 complete-flow fixture exposed `ul>li.item$*5>a{Link $}` inside TSX being
truncated before expansion: tree-sitter recovered the attached text as an
`object` under `ERROR`, and the host boundary clipped everything before its
opening brace. Only such recovered, attached objects now defer to the existing
projection check; real object boundaries are preserved. The ambiguity query
also includes recovered objects, so plain `Hello{...}` remains excluded from
automatic completion. Explicit text, numbered text, middle/end point, adjacent
return/arrow objects and ordinary expressions are tested in TSX and both web
JSX modes. Preview/acceptance also exercises the original failing abbreviation.

This fixes host classification without changing the extractor, parser owners,
caches or CSS lexical paths. The affected TSX performance matrix was rerun;
see the supplementary results in `test/performance-context-2026-09-27.md`.
