# Performance measurement protocol

This is the measurement protocol, not a performance result. Parser-only timings
do not satisfy these gates. Keep measurement reports and raw samples outside the
repository; they belong to the revision and machine that produced them.

Record the repository revision, dirty files, fixture hashes, machine/CPU/OS,
Emacs build/configuration, dependency lock, render options and GC
settings. Run before/after comparisons on the same machine and build. Use an
isolated `-Q` environment prepared by `setup.mjs`; do not change daily settings.

Use byte-compiled project code with compilation warnings treated as errors.
Native compilation is a separate optional result, never a substitute for the
bytecode gate. On a build with native compilation, pass the following before
loading test or package libraries in **both** baseline and candidate processes:

```sh
--eval '(setq load-no-native t native-comp-jit-compilation nil native-comp-enable-subr-trampolines nil)'
```

An `.elc` source filename alone does not prove bytecode execution: a native cache
can replace it. Keep the runners' `byte-code-function-p` checks enabled.
Disabling trampolines also keeps native compilation out of runners that
redefine process primitives; it is a measurement setting, not a package
default.

Keep normal GC thresholds; record `gc-cons-threshold`,
`gc-cons-percentage`, `gcs-done` and `gc-elapsed` deltas. Do not exclude samples
which performed GC or raise thresholds to pass. Keep raw per-operation samples.

For each input/size/path, record cold startup separately, then at least 100
warmups and 1,000 measured samples. Repeat in three fresh Emacs processes.
Report p50, p99 (sorted sample at ceil(0.99*N)), max and GC deltas per process;
do not average away a failed p99. Verify output/context before timing it.

| Gate | Fixed inputs and complete measured path | Budget |
| --- | --- | --- |
| Context: TSX | `ul>li*3` and style `m10`, including edits, region, extraction and confirmation; 56/306/1006-line containing statements, 500/5k/20k-line files | Warm p99 <= 1 ms; scale ratios < 1.5 |
| Context: CSS/web positions | A fixed CSS part/markup position in 500 and 20k lines; include pending scan and syntax updates after edit | Warm p99 scale ratio < 2 |
| Context: large web style | A 135 KB CSS part with the active declaration near its end; include pending scan and classification | Warm p99 <= 5 ms |
| Editor flow | Real context, engine, annotation/popupinfo and acceptance; markup plus the six-property CSS case below | Report cold and warm stages and total; no invented aggregate budget |
| CSS completion | `.a { ovh,t }` through real Corfu: a confirmed prefix and ten ranked choices, including the first open | Completion p99 <= 20 ms |
| Markup engine | Four inputs below, plus JSX, emoji and mirrored fields; parse, resolve, formatting, offsets and cursor | Bytecode warm p99 <= 1 ms |
| CSS search | Twelve representative queries, from `m` to `bdrs` | Bytecode warm p50 <= 2.5 ms, p99 <= 5 ms |
| CSS core | `margin10+padding5+border1#2s+position-absolute+display-flex+font-size16`; canonical names with parsing, keyword values, formatting and fields | Bytecode warm p99 <= 0.5 ms |

Markup inputs:

```text
ul>li.item$*5>a{Link $}
div.card>(header>h2{Title})+section>p*3
nav>ul>li*10>a[href=#]
!
```

Buffer generators must record actual line/byte counts and keep the same active
host part when varying unrelated file size. Include tight JSX and a negative
JSX expression so speed cannot improve by dropping classification work.
For edit samples, insert/delete at the active token and time each resulting
full analysis; a precomputed abbreviation start is not an analysis benchmark.
Report initialization and invalidation cost as well as steady repeated reads.

CI runs deterministic correctness and compilation checks. It must not assert
wall-clock budgets across different hosted machines. When a budget fails, keep
the samples, identify the expensive stage, change the smallest responsible
implementation and remeasure. Do not silently weaken a
budget, omit a size, or replace a full-path result with a microbenchmark.

## Context benchmark

```sh
EMMET2_TEST_DEPS=~/.cache/emmet2-test-deps \
EMMET2_BENCH_OUTPUT=/tmp/context-31-1.json \
/path/to/pinned/emacs --batch -Q -L . -l test/bootstrap.el -l test/bench-context.el
```

Use three fresh processes and unique output names. The optional
`EMMET2_BENCH_FILTER` is an Emacs regexp for diagnosis only. The runner refuses
existing output files and source changes during measurement. It compiles only
project code into an owned temporary directory; package source/bytecode status
is reported rather than silently altered in the dependency checkout.

Keep `analyze`, `typing-and-analyze` and `programmatic-edit-and-analyze` separate.
Both edit paths include modification hooks and pending scanning. A programmatic
`insert` does not necessarily inherit the same web-mode part properties as
`self-insert-command`; dropping its slow samples would hide real work. A
context budget fails when either edit path exceeds it. Keep baseline and
candidate samples outside the repository, as above; a commit message or pull
request may quote their summary and hashes.

The context runner uses 100 warmups and 10,000 measured operations per path. It
interleaves comparable sizes of each fixture kind and rotates the first buffer
every round to reduce time-order bias. Up to five buffers are alive within a
group; all are released before the next kind. Buffer selection and correctness
checks are outside the clock. Per-fixture GC totals sum its timed samples;
they do not include other fixtures or between-sample work. Every sample,
including GC, is retained. Cold analysis is the first call per fixture after its
mode setup; only the first fixture in a fresh process includes process-wide
initialization that later fixtures share.

The ordinary CSS pairs run in css-mode, css-ts-mode, scss-mode and less-css-mode.
The isolated dependency lock includes CSS's grammar, so css-ts-mode uses its
real parser. CSS search and its catalog are compiled and hashed with the
context modules, so the measured path runs only bytecode.

## Editor-flow benchmark

First build the reviewed revision with `test/install.el` (see
[CONTRIBUTING](../CONTRIBUTING.md#actual-installation)).
Then use its actual `straight/build/emmet2-mode` directory:

```sh
EMMET2_TEST_DEPS=~/.cache/emmet2-test-deps \
EMMET2_BENCH_PACKAGE="$EMMET2_INSTALL_ROOT/straight/build/emmet2-mode" \
EMMET2_BENCH_OUTPUT=/tmp/editor-flow-31-1.json \
/path/to/pinned/emacs --batch -Q -l test/bootstrap.el -l test/bench-completion.el
```

Run three fresh processes serially, without concurrent builds or tests. The
runner verifies runtime source/resource hashes against the package, removes
the source checkout from `load-path`, and requires bytecode entry points from
that package. It rejects an existing output, an empty fixture selection, and
source changes during measurement. `EMMET2_BENCH_FILTER` is diagnostic only.
A before/after experiment may use a separate copy of that installation with
the changed module recompiled by the same Emacs; record that distinction and
its hashes. Such a copy is not a new package-manager installation acceptance.

Each of the eighteen fixtures runs completion and completion with yas paths
interleaved, rotating the first path each round: 100 warmups and 1,000
retained samples per path. The first accepted choice defines the expected
output. Inputs cover the first two markup cases above, TSX numbered text,
one/six CSS properties, CSS with empty values, ranked CSS choices with and
without a confirmed prefix, CSS-in-JS and a 138,052-byte web-mode style
buffer. Additional fixtures cover css-ts-mode, builtin SCSS variables, LESS,
HTML style attributes, js-mode/js-ts-mode/TypeScript style objects, and the
built-in html-mode's explicit `emmet2-complete` request. Reset and output/cursor assertions
are outside the clock. The next operation includes any pending scan left by the
multi-character reset, unlike the context benchmark's single-character typing
path.
Yas mode setup is outside the clock, but field creation during acceptance is
timed and checked; only markup fixtures create fields, CSS inserts plain text.
Undo recording remains enabled, with history cleared between operations.

Completion uses the real Corfu control, candidate formatting, popupinfo
getter and insertion. Popup drawing/hiding is replaced, and Corfu's error
shield is bypassed so failures propagate to the runner. Stage labels
mean request (`completion-at-point`), annotation (`corfu--exhibit`, including
its candidate checks), first/repeated documentation, and acceptance. Nested
stage times/GC deltas must not be added to the already inclusive total. These
batch results do not measure screen painting, input-to-display latency, idle
scheduling or Eglot interaction.

Four additional live sessions (CSS, css-ts-mode, HTML style attributes and TSX
style objects) alternate typing `a` and deleting it at `ovh,t`. Each retains 100
warmups and 1,000 samples per edit, including modification hooks and Corfu's
post-command update and annotation work. Every edit must keep the same table,
offer ten choices, and label them with the current abbreviation. First open is
recorded separately. These rows measure an existing session, not repeated opens;
they have no separate aggregate budget. Normal GC and all slow samples remain.

Mode initialization and context preparation are reported separately. The first
completion follows an untimed context check and expansion used to establish the
fixture's formatting; it does not measure first engine/data loading. Cold
completion creates its first preview buffer; cold yas follows with that preview
warm. Front-end/dependency loading also precedes timing, so cold values do not
measure Emacs startup or total package loading. The installed runtime has no
external executable path and the measured flows reject process creation.

Raw warmup and measured triples are milliseconds, GC count and GC seconds.
Keep per-process p50, p99, max and GC totals, with no aggregate editor-flow
pass/fail budget or cross-process percentile averaging.

## Markup benchmark

```sh
EMMET2_TEST_DEPS=~/.cache/emmet2-test-deps \
EMMET2_BENCH_OUTPUT=/tmp/markup-31-1.json \
/path/to/pinned/emacs --batch -Q -L . -l test/bootstrap.el -l test/bench-markup.el
```

Run three fresh processes serially on the fixed macOS machine for each pinned
Emacs build. The runner compiles the pure engine into an owned temporary
directory and copies packaged data next to it; no installed package or daily
configuration is changed. It checks bytecode entry points, source/fixture
hashes before and after, and full oracle output after every operation.
Fifteen fixtures cover the four markup inputs above with implicit tags, JSX,
emoji and mirrored fields (nine), three project JSX cases (multiword fields,
escaped keys and Solid layout) and three seeded lorem cases (`lorem80`,
`loremru50` and `loremsp50`). Lorem uses seed
42: its first timed output passes the independent structural contract, then
every later output must match that complete result. Each raw row retains its
reference text, fields and cursor. These are measurement records, not new random
goldens in the correctness corpus. Data/contract hashes cover the three lexicons
and lorem fixtures as well as the markup inputs. Samples interleave and rotate
the first fixture each round, with 100 warmups and 1,000 retained measurements.
GC uses the normal 800000/1.0 settings; all pauses are retained. First expansions and explicit
bytecode loads are reported separately and exclude Emacs startup, compilation
and fixture loading. The budget covers the complete markup expansion only.

## Stylesheet benchmark

```sh
EMMET2_TEST_DEPS=~/.cache/emmet2-test-deps \
EMMET2_BENCH_OUTPUT=/tmp/stylesheet-31-1.json \
/path/to/pinned/emacs --batch -Q -L . -l test/bootstrap.el -l test/bench-stylesheet.el
```

Use three fresh serial processes per pinned Emacs build on the fixed machine,
without concurrent tests or builds. The runner compiles the core, the fuzzy
matcher, the CSS search, the stylesheet engine and the extension layer into an
owned temporary directory, verifies their loaded bytecode paths and copies their
data beside them. It refuses an existing output, a preloaded module or source
changes during measurement. Native calls have no executable search path and
process creation is rejected.

Cases cover the search itself, the string choices of
`emmet2-extensions-css-choices` (completion is measured by the editor-flow
benchmark), the expansion of compact abbreviations including the six-property
input, and the core alone with complete names. The CSS search budget applies to
the `search:` rows and the CSS core budget to `core:six-canonical`. The other
rows, including `expand:m10+p5+bd1#2s+posa+dib+fz16`, which searches once per
property, are reported without a budget. The first result of each case is kept, and
every sample must equal it outside the clock.

The runner rotates the first case each round and interleaves 100 warmups and
1,000 samples per case. Normal GC remains 800000/1.0 and all pauses are kept.
End GC counters are captured before duration/sample allocation. Raw triples and
per-process statistics use the same units and quantile rule as the markup
benchmark. The first
call per case and explicit bytecode loading (including the search index) are
separate cold values. Compilation and dependencies precede that load; these
values do not measure whole Emacs startup. Actual package installation, editor
flow and GUI acceptance remain separate checks.
