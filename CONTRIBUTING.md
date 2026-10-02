# Development

The installed package is pure Emacs Lisp. Expansion runs entirely in Emacs Lisp
and starts no process. Node is used only in development: dependency setup,
lint, the Node tests, the offline oracle, the CSS data update and the CI Emacs
build. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the modules divide the
work and defines the terms used here; [API.md](API.md) lists the public
contracts.

## Change rules

- `emmet2-insert` is the only source writer. Every insertion passes it a
  snapshot to validate and lands in one undo group
  ([Insertion and preview](ARCHITECTURE.md#insertion-and-preview)).
- Add no global or accumulating cache. A new analysis input belongs in
  `emmet2-context-revision`, never in a second cache inside a completion table
  ([Tables and revisions](ARCHITECTURE.md#tables-and-revisions)).
- Keep the [failure policy](ARCHITECTURE.md#request-and-failure-boundaries):
  automatic failures offer no choice, explicit requests report the cause, quit
  propagates, and an input interruption leaves a table retryable.
- Never change completion-frontend configuration; adapt only Emmet tables, as
  the [Corfu adapter](ARCHITECTURE.md#corfu-adapter) does.
- Use only public yasnippet interfaces, and keep snippets to markup. Tests
  simulate an absent yasnippet with `emmet2-test--with-yasnippet`.
- Retune search parameters only against the frozen corpus in
  `test/fixtures/css-search-corpus.json` and its gates in
  `emmet2-css-search-test.el`
  ([Search and matching](ARCHITECTURE.md#search-and-matching)).
- Do not weaken the JS grammar gate to cover Astro `{expression}` regions;
  web-mode does not mark them, so they are analyzed as markup.
- Provider tests use an independent host without a CSS major mode and do not
  depend on scss2.
- Every name not documented in [API.md](API.md) is internal. Update API.md with
  any change to a public name, argument or result.
- `CHANGELOG.md` states every user-visible change for users; list breaking
  changes first, with the configuration they must edit.

## Setup and validation

Use the versions in `test/dependencies.json`: Node 24.21.0; GNU Emacs 30.2/31.1;
pinned Corfu, compat, web-mode, yasnippet, straight.el, package-lint and five
grammars. `test/setup.mjs` creates isolated checkouts and compiles grammars. It
rejects changed checkouts and never modifies a daily Emacs installation. Bootstrap
disables grammar auto-download and fails for missing locked dependencies.

```sh
npm ci --ignore-scripts --no-audit --no-fund
node test/setup.mjs ~/.cache/emmet2-test-deps
npm run lint
npm test
npm run oracle:check
export EMMET2_TEST_DEPS=~/.cache/emmet2-test-deps
emacs --batch -Q -L . -l test/byte-compile.el
emacs --batch -Q -L . -l test/package-quality.el
emacs --batch -Q -L . -l test/integration.el
emacs --batch -Q -L . -l test/editor-bytecode.el
```

Keep the dependency directory outside `/tmp`, which macOS clears periodically.
Repeat Elisp checks with both pinned Emacs builds. With a native-compiling Emacs,
add `--eval '(setq native-comp-enable-subr-trampolines nil)'` before
`-l test/integration.el` and `-l test/editor-bytecode.el`: their process guards
redefine primitives, and compiling trampolines would start a process. To run one
test file, load it after the bootstrap:

```sh
emacs --batch -Q -L . -L test -l test/bootstrap.el -l test/emmet2-fuzzy-test.el \
  -f ert-run-tests-batch-and-exit
```

The full integration runner includes all of these contracts, compares the full
canonical core results and rejects synchronous/asynchronous process creation with
an empty `exec-path`. The bytecode runner exercises real compiled editor and
optional dependencies; a copied payload is not a package-manager installation.

Compilation treats project warnings as errors. Fixed third-party warnings remain
visible. `package-quality.el` checks every runtime library with package-lint and
checkdoc; all diagnostics fail. The compiler runner is named `byte-compile.el` to
avoid shadowing Emacs's built-in `compile.el`. ESLint runs its recommended rules
plus `prefer-const`; only immutable third-party vendor output and ignored working
plans are excluded. For JavaScript changes, run `npm run lint` and `npm test`.

CI uses the same commands on Ubuntu 24.04. `test/build-emacs.mjs` verifies official
GNU release archive hashes and builds a private static tree-sitter 0.25.10, avoiding
the removed system 0.27 API. It needs Git, Make, C tooling, tar/xz, pkg-config and
terminal development headers; it never installs into system libraries. Build
directories must be new, and failures preserve `build.log`. The oracle additionally
runs in a Linux network namespace with no network and Node's read-only filesystem
permission. Node's permission flag alone is not claimed to deny networking.

## Data and oracle

`data/emmet/source.json` pins Emmet 2.4.11's archive, source commit and
individual SHA-256 hashes. `test/vendor/emmet-2.4.11.mjs`, HTML snippet JSON and
lorem dictionaries are copied verbatim. The source contains 155 HTML snippets
and 5 variables; resolved alias counts can differ. Emmet's CSS snippets are not
used; CSS abbreviations search the CSS data instead. `data/emmet/LICENSE` ships
with the vendored data; `data/COPYING` carries the project GPL license. Do not
substitute newer upstream files or edit generated vendor code. Version/hash
changes need a separately reviewed data upgrade.

`test/oracle/adapter.mjs` and `test/oracle/jsx.mjs` are independent development
references for markup. The Node tests retain hand-written field, Unicode,
error, JSX, generator and CSS data checks. The generator consumes explicit
`core-inputs.json` cases; it never infers expectations from arbitrary source
strings. The 526 fixed markup cases include errors. CSS output is defined by
this project, so the oracle covers markup only. `--check` regenerates in memory
and compares contents plus complete inventory without writing. Extra files
fail; nothing is silently deleted. An intentional input or contract change
requires reviewing both `core-inputs.json` and the regenerated
`oracle/markup.json`. These fixtures are not exhaustive upstream coverage.
Lorem uses 42 structural cases and five seeds instead of random text goldens.

`data/css-source.json` pins VS Code Custom Data (CSS and HTML) and MDN data's
CSS type syntaxes by commit, hashes, schema and input counts.
`node test/update-web-data.mjs` is an explicit networked maintenance step; it
verifies all inputs before writing the full `css-data.json` metadata, the
compact `css-index.json` search index and both upstream licenses. The files are
generated together; tests verify the index against the metadata. The full
snapshot has 888 property/descriptor records including vendor entries, named
values, restrictions and documentation. Comma-separated value presets such as
font stacks are dropped, so no value contains a comma. The index contains 579
ordinary properties (relevance, obsolete status, own keywords and the shared
value sets reachable through property and type references), 34 at-rule
descriptors kept apart from them, 175 shared value sets, the five CSS-wide
keywords, 19 at-rules, 117 pseudos and 116 HTML elements. A shared set stores
its own keywords once. Vendor names, function arguments and deprecated types
are excluded; descriptors are searched only for their own at-rule. An `atRule`
association does not exclude ordinary use: the generator also admits entries
whose source reference identifies an ordinary CSS property. The shared query
library uses this same membership. This snapshot remains pinned and offline at
runtime; updating data does not automatically add grammar support.
`css-overrides.json` holds the data-driven overrides: word and property aliases
used by search, and pseudo and at-rule aliases, pseudo functions and SCSS
at-rule templates used by `emmet2-css`. The generator never writes it.
Review upstream names and local targets together.

## Actual installation

After a reviewed commit, install that exact HEAD in a new directory:

```sh
export EMMET2_TEST_DEPS=~/.cache/emmet2-test-deps
export EMMET2_INSTALL_ROOT=/tmp/emmet2-install-new
emacs --batch -Q -l test/install.el
EMMET2_TEST_PACKAGE="$EMMET2_INSTALL_ROOT/straight/build/emmet2-mode" \
  emacs --batch -Q -l test/integration.el
```

As above, a native-compiling Emacs needs the trampoline setting before
`-l test/integration.el`.

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

## Performance

Before adding state or synchronization, justify why the existing owner or a
derived value cannot serve the requirement, and measure the affected hot path.
The protocol, exact inputs, budgets and reproduction commands live in
[test/PERFORMANCE.md](test/PERFORMANCE.md). Measure bytecode on a fixed machine,
with normal GC and independent processes, and validate complete outputs.
Parser-only timing cannot establish whole-flow performance. Screen painting,
input latency and Eglot behavior require real GUI evidence; do not infer them
from batch measurements, and never treat batch drawing replacements as GUI
interaction.
