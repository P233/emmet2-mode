# Native rewrite performance acceptance

This is the measurement protocol, not a performance result. S0 feasibility
probes allocate temporary parsers and are not the production analysis path.
The old research averages and parser-only timings do not satisfy these gates.
Implement each benchmark alongside the real path at S3, S5, S6 or S7.

Record the repository revision, dirty files, fixture hashes, machine/CPU/OS,
Emacs build/configuration, dependency lock, backend, render options and GC
settings. Run before/after comparisons on the same machine and build. Use an
isolated `-Q` environment prepared by `setup.mjs`; do not change daily settings.

Use byte-compiled project code with compilation warnings treated as errors.
Native compilation is a separate optional result, never a substitute for the
bytecode gate. Keep normal GC thresholds; record `gc-cons-threshold`,
`gc-cons-percentage`, `gcs-done` and `gc-elapsed` deltas. Do not exclude samples
which performed GC or raise thresholds to pass. Keep raw per-operation samples.

For each input/size/path, record cold startup separately, then at least 100
warmups and 1,000 measured samples. Repeat in three fresh Emacs processes.
Report p50, p99 (sorted sample at ceil(0.99*N)), max and GC deltas per process;
do not average away a failed p99. Verify output/context before timing it.

| Gate | Fixed inputs and complete measured path | Budget |
| --- | --- | --- |
| S3 TSX | `ul>li*3` and style `m10`, including edits, region, extraction and confirmation; 56/306/1006-line containing statements, 500/5k/20k-line files | Warm p99 <= 1 ms; scale ratios < 1.5 |
| S3 CSS/web ordinary positions | A fixed CSS part/markup position in 500 and 20k lines; include pending scan and syntax updates after edit | Warm p99 scale ratio < 2 |
| S3 web large style | A 135 KB CSS part with the active declaration near its end; include pending scan and classification | Warm p99 <= 5 ms |
| S5 editor flow | Real context, Node, annotation/popupinfo and acceptance; markup plus the six-property CSS case below | Report cold and warm stages and total; no invented aggregate budget |
| S6 markup | Four inputs below, plus JSX, emoji and mirrored fields; parse, resolve, formatting, offsets and cursor | Bytecode warm p99 <= 1 ms |
| S7 CSS | `m10+p5+bd1#2s+posa+dib+fz16`; include parsing, matching, values, formatting and fields | Bytecode warm p99 <= 0.5 ms |

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
wall-clock budgets across different hosted machines. A budget failure keeps
its milestone open: retain samples, identify the expensive stage, change the
smallest responsible implementation and remeasure. Do not silently weaken a
budget, omit a size, or replace a full-path result with a microbenchmark.

## Running the implemented S3 benchmark

```sh
EMMET2_TEST_DEPS=/tmp/emmet2-test-deps \
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
`self-insert-command`; dropping its slow samples would hide real work. The S3
gate stays open when either measured edit path fails. Baseline and optimized
samples belong in the ignored plan measurements directory, with a concise
result summary and hashes in versioned documentation once measured.

The S3 runner uses 100 warmups and 10,000 measured operations per path. It
interleaves comparable sizes of each fixture kind and rotates the first buffer
every round to reduce time-order bias. Up to five buffers are alive within a
group; all are released before the next kind. Buffer selection and correctness
checks are outside the clock. Per-fixture GC totals sum its timed samples;
they do not include other fixtures or between-sample work. Every sample,
including GC, is retained. Earlier sequential measurements remain evidence,
not discarded failures. Cold analysis is the first call per fixture after its
mode setup; only the first fixture in a fresh process includes process-wide
initialization that later fixtures share.
