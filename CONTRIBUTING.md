# Development

The installed package is pure Emacs Lisp. `emmet2-engine-expand` calls the native
markup or stylesheet engine directly; commands, completion and previews share
that entry. There is no runtime backend selector, external process or fallback.
Node is used only for development setup, lint and the independent offline oracle.

## Ownership and public contracts

- `emmet2-context` owns host classification and source-buffer parser lifetimes;
  `emmet2-extract` alone computes abbreviation bounds.
- `emmet2-engine` owns the canonical result and shared expansion deadline. Native
  cores return text, positive editable-field groups and an initial cursor, using
  zero-based character offsets and half-open field intervals. They never read or
  write an editor buffer. Loaded snippet/index data is read-only; ASTs, output,
  random state and snippet resolution belong to the current call.
- Markup preserves mirrors. CSS fields belong to one parsed property; identical
  upstream numbers in different properties are independent. Upstream zero is an
  editable field. Conflicting defaults form independent groups so mirrors cannot
  silently overwrite authored text.
- `emmet2-extensions` owns opinionated syntax, CSS default removal and all related
  text/field transformations. Project JSX class conversion runs on the markup AST
  before formatting. A rendered class value cannot safely be recovered by regex.
- `emmet2-insert` is the only source-text writer. It checks buffer, mode, tick,
  point, visible bounds and original text, then uses one atomic undo group.
  Layout derives from mode width and the abbreviation's display column before
  insertion; there is no subsequent `indent-region` pass.
- `emmet2-capf` owns an immutable snapshot and one lazy result per completion
  table. Candidate text is the original abbreviation. Only a current `finished`
  callback inserts; metadata and prefix checks do not expand. No global expansion
  cache, source-restoration state or frontend configuration mutation is allowed.
- `emmet2-preview` owns at most three lazy, read-only, non-file buffers. Built-in
  HTML/JSX/CSS modes fontify final text without extra grammars. Creation isolates
  user mode hooks. Failed initialization, module unload and package unload clear
  owned buffers; ordinary kill hooks still run. There is no timer or result cache.

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
its own final `$0`. A module-owned advice suppresses yas's EOF protection newline
only within an Emmet snippet; unloading the insert module removes it. Only
web-mode's built-in reindent exit hook is excluded for these snippets. Other user
hooks and settings remain intact. Plain insertion uses the same text and initial
cursor; one undo restores the abbreviation.

## Extension and host boundaries

`emmet2-extensions-css` accepts `:css-in-js`, `:indent` and `:base-indent`.
A balanced scanner splits only top-level comma/plus separators. Aliases feed
individual core expansions; default removal and first-whitespace normalization
happen once per property. Fields collapsed to one position merge within that
property. Raw/rhythm/ms/var values replace the complete value and its fields.
CSS-in-JS escapes string contents, quotes non-identifier keys and remaps fields.

Pseudo/at-rule lookup applies authored aliases before prefix-free, non-partial
fuzzy matching. The shared `emmet2-fuzzy` preserves candidate position reuse,
partial suffixes, early exact hits and later nonzero tie wins. The stylesheet core
builds a read-only first-character index at load time. No fuzzy cache is needed.
Unknown at-rules stay literal; templates change only authored layout, leaving
literal tabs untouched. Empty alias tables retain the fuzzy fallback.

`emmet2-extensions-markup` accepts `:jsx`, `:variant`, `:css-modules-object`,
`:class-names-constructor`, `:indent` and `:base-indent`. Literal class names use
dot access for identifiers and escaped bracket access otherwise. Fields preserve
priority, mirrors and multiword expression spans. Whitespace-only fields remain
separate arguments. Authored class expressions are renamed for React/Solid without
interpretation. Project reference strings are emitted as source, never evaluated.

CSS/SCSS context uses `syntax-ppss`; web-mode owns its pending scanner, attribute
markers and part ranges. JS/TS/JSX requires the matching pinned tree-sitter grammar.
CSS classification starts at the extracted abbreviation, including when point is
inside a balanced raw value. Comments and strings are forbidden. Automatic analysis
also excludes values, at-rule preludes, ordinary selectors and unrelated script
expressions; explicit commands retain supported manual positions. Unknown major
modes retain manual markup only. Missing grammars give capf nil and an explicit
command diagnostic; HTML/CSS paths do not need additional grammars.

Narrowed web buffers temporarily expose the full host to its scanner and restore
narrowing afterward; accepted abbreviations must remain entirely visible. TSX error
recovery must retain complete attached Emmet text while keeping ordinary object
and expression exclusions. Astro expressions not identified by the pinned web-mode
scanner retain the documented host limitation; do not weaken the JS grammar gate.

Each candidate query and acceptance rechecks source and host. Editing, switching
mode/settings, narrowing away, disabling the mode or leaving the original point/end
invalidates the session. Corfu can accept identical text without changing the
character tick and move point to END; acceptance takes a new strict insertion
snapshot. Frontends that rewrite the same text and change the tick are rejected.
`emmet2-complete` temporarily selects only Emmet capf and keeps its confidence gate.
Mode enable/disable owns local registration at depth -50. Corfu styles/category/
exact-match policies are described below; optional mode setup is in README.
Batch drawing replacements are never evidence of real GUI interaction.

## Completion behavior

The candidate remains the original abbreviation; its annotation summarizes the
expansion, and optional `corfu-popupinfo-mode` shows the final colored text.
Bare markup identifiers, bare CSS property names and unconfirmed host positions
are left to other providers. Use `C-j` for explicit expansion.

Automatic presentation respects Corfu's prefix, delay and trigger settings.
With `basic` first, the exact candidate can remain visible for `nil`, `show`,
`insert` and `quit` policies. With `partial-completion` first, alone, or selected
by an `emmet2` category override, automatic completion skips it unless the
persistent `corfu-on-exact-match` is `show`; manual completion may expand directly.
The package changes none of these settings. With `corfu-preselect` set to
`prompt`, select the candidate before accepting it; accepting the prompt does
not expand. Editing or moving away invalidates the old session.

## Data, oracle and migration authority

`data/emmet/source.json` pins Emmet 2.4.11's archive, source commit and individual
SHA-256 hashes. `test/vendor/emmet-2.4.11.mjs`, snippet JSON and lorem dictionaries
are copied verbatim. The source contains 155 HTML snippets, 249 CSS snippets and
5 variables; resolved alias counts can differ. `data/emmet/LICENSE` ships with the
native port and data; `data/COPYING` carries the project GPL license. Do not substitute newer upstream files or edit generated
vendor code. Version/hash changes need a separately reviewed data upgrade.

`test/oracle/adapter.mjs` and `test/oracle/jsx.mjs` are independent development
references. Their 23 Node tests retain hand-written field, Unicode, error, JSX
and generator checks. The generator consumes explicit `core-inputs.json` cases;
it never infers expectations from arbitrary source strings. The 973 fixed cases
cover 526 markup and 447 CSS inputs, including errors. `--check` regenerates in
memory and compares contents plus complete inventory without writing. Extra files
fail; nothing is silently deleted. Intentional input/contract changes require
reviewing both output files. These fixtures are not exhaustive upstream coverage.
Lorem uses 42 structural cases and five native seeds instead of random text goldens.

`data/css-source.json` pins VS Code Custom Data by commit, hashes, schema and input
counts. `node test/update-web-data.mjs` is an explicit networked maintenance step;
it verifies all inputs before writing sorted, deduplicated, non-vendor names and
the upstream license. Current names contain 19 at-rules and 117 pseudos.
`css-overrides.json` alone owns authored aliases, functions and SCSS templates;
the generator never writes it. Review upstream names and local targets together.

`test/fixtures/migration.json` retains the exact baseline identities, file hashes
and replacement test IDs for all 182 old cases: 93 CSS, 19 markup and 70 regex.
Baseline files remain available at commit `3f9ddc6`; the old TS/Deno implementation
and runners have been removed. The complete native runner rejects missing
replacement tests before running them. Text expectations, extraction boundaries,
field behavior and editor integration remain separate contracts. No skipped suite
or changed expected output counts as migration evidence. Intentional changes
(first editable field, separate CSS stops, safe-context gating, Emacs 30 minimum)
are recorded in that ledger and README.

## Setup and validation

Use the versions in `test/dependencies.json`: Node 24.21.0; GNU Emacs 30.2/31.1;
pinned Corfu, compat, web-mode, yasnippet, straight.el, package-lint and four
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

Every implementation slice follows primary review, any required follow-up,
read-only final and a signed commit. Check the actual committed scope, then update
the ignored working plans from implemented behavior. The current authorized push
target is `native-emmet-rewrite`; merging or publishing is separate from testing.

Performance protocol, exact inputs, budgets and reproduction commands live in
[test/PERFORMANCE.md](test/PERFORMANCE.md). Measure bytecode on the fixed machine,
normal GC and independent processes; retain raw samples, maxima, warmups, failures,
source hashes and complete output validation. Parser-only timing cannot establish
whole-flow performance. Screen painting, input latency and Eglot behavior require
real GUI evidence; do not infer them from batch measurements.

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
