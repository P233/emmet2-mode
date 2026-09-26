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
default), `results`, `node`, `fuzzy` or `css-extensions`; unknown suites fail explicitly. Missing
packages or local grammars fail bootstrap instead of skipping integration or
falling back to a grammar in the user's configuration.

The four Corfu tests exercise its pinned completion control flow with only
popup drawing replaced. They cover the original candidate, effective styles
and category override, all four exact-match policies, automatic/manual entry,
prefix threshold, cancellation and explicit acceptance.
This is feasibility evidence, not GUI or Emmet integration
acceptance: S5 must run the same matrix against the real capf and insertion.
The probe uses private Corfu functions only in tests; production must use the
public completion API. It never changes the user's completion settings.

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

The test-only host classifier is a feasibility probe, not the S3 context module.
S3 must retain these fixtures, replace that helper with the real context owner,
and validate HTML/CSS adapters, parser reuse/cleanup, missing grammars, full
extraction compatibility and performance. The bounded scanner has no mode or
parser state. Neither new module is connected to the installed mode yet.

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
Runtime command/completion behavior is not switched by this module; JSX
extensions and the S2 total gate remain open.

```sh
rtk proxy env EMMET2_TEST_DEPS=/tmp/emmet2-test-deps EMMET2_TEST_SUITE=css-extensions emacs --batch -Q -L . -l test/emmet2-test.el -f ert-run-tests-batch-and-exit
```
