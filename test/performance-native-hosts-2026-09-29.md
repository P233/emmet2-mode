# Native host acceptance, 2026-09-29

Deterministic validation passes on the latest tested worktree. A fixed snapshot
completed three fresh processes per benchmark and Emacs build, but retained budget
failures keep performance acceptance **open**. GUI acceptance is also **open**.
The performance snapshot and subsequent correctness snapshot are identified below;
their results are not interchangeable. The scss2 integration was not required
or modified for these checks.

## Changes and coverage

- Canonical result normalization sizes its two call-local hash tables to the
  supplied fields. Memory profiling of installed Corfu completion identified
  repeated default-capacity allocation in rendering, cleanup and concatenation.
  Validation, mirror groups, ordering, cursor positions and public APIs remain
  unchanged. No retained cache or additional state owner was introduced.
- Integration flows now include css-ts-mode, LESS, js-ts-mode and TypeScript
  style objects, with plain insertion, Yas fields, previews and undo. Native
  html-mode and unknown hosts retain explicit markup requests; automatic HTML
  completion remains a web-mode feature.
- CSS's grammar is pinned in the existing test dependency lock. css-ts-mode is
  exercised with its real parser and separately with grammar readiness disabled.
- The context benchmark compiles and hashes CSS search and its catalog as part
  of the actual context path. Its ordinary CSS matrix now includes css-mode,
  css-ts-mode, scss-mode and less-css-mode at 500 and 20,000 lines.
- The installed editor benchmark preserves the original ten cases and adds eight
  host cases. Four live Corfu sessions also test typing/deleting within one table,
  verifying ten current candidates after every edit. Its GC counters now stop
  before timing/sample allocation, matching the other benchmark runners.

## Installation and correctness

The worktree started at `0ed065889e96768b64b60507769683442b839d88` with the
previous rewrite staged. A separate local fixture repository froze the worktree
for actual pinned straight installations; the live repository was not committed,
staged or pushed. The final installation fixture is
`ac0cbe557cb8c6cf5ec291195978fb9dc62f90fa` (a fixture identity, not a project commit).

| Check | Emacs 30.2 | Emacs 31.1 |
| --- | ---: | ---: |
| Fresh straight installation, runtime paths and resources | 100/100 | 100/100 |
| Complete integration against installed bytecode | 393/393 | 393/393 |
| Public core calls exercised by integration | 3,202 | 3,202 |
| Byte-compiled editor and optional dependencies | 163/163 | 163/163 |
| Runtime package-lint/checkdoc | 17 libraries | 17 libraries |
| Project and test compilation, warnings as errors | Passed | Passed |

All 182 legacy cases remain mapped. Installed execution excludes source fallback
and external expansion processes. The test dependency setup successfully built
all five pinned grammars. The pinned Corfu source emits its existing obsolete
`when-let` warning on Emacs 31; project compilation and package checks pass.

## Allocation experiment

One before/after pair used actual installed bytecode, the same `.a { ovh,t }`
fixture, 100 warmups and 1,000 retained samples per path, interleaved plain/Yas
acceptance, and normal GC (800000 / 1.0). All pauses are retained.

| Path | Before p50 / p99 (ms) | After p50 / p99 (ms) | Before / after timed GC count |
| --- | ---: | ---: | ---: |
| Completion | 2.088 / 8.223 | 1.862 / 3.236 | 6 / 7 |
| Completion with Yas | 2.309 / 25.067 | 2.045 / 4.654 | 11 / 9 |

This is a paired diagnostic, not completion of the three-process acceptance
protocol. The memory-profiler run is retained separately and is not timing
evidence. Within this original cohort, runtime changes affect only allocation
capacity and the installed runtime hashes remain fixed. The later retest uses
its own recorded source identities.

## First matrix: contended and incomplete

The first full Emacs 31 cohort finished every fixture and output assertion.
Independent recomputation verified recorded percentiles, counts and GC intervals
for all four completed JSON reports. Budgets remain those in [PERFORMANCE.md](PERFORMANCE.md).

| Gate | First Emacs 31 cohort | Status of this cohort |
| --- | --- | --- |
| CSS search | `trfo` p99 10.561 ms; `bdrs` 11.759 ms | Over 5 ms |
| Canonical CSS core | p50 0.183 ms; p99 1.478 ms | Over 0.5 ms |
| Markup core, all 15 fixtures | Highest p99 0.962 ms | Within 1 ms |
| TSX context, all sizes and edit paths | Highest p99 0.488 ms; worst size ratio 1.202 | Within both budgets |
| Ordinary CSS/SCSS/LESS/css-ts/web context | Worst size ratio 1.333 | Within ratio 2 |
| 135 KB web style context | Read/type/programmatic p99 14.095 / 21.592 / 25.008 ms | Over 5 ms |
| Confirmed CSS choices, real Corfu | Plain/Yas p99 14.724 / 7.595 ms | Within 20 ms, including first-open sample |

The other editor rows have no aggregate budget. Their slow samples still matter:
the large web-style flow reached p99 124.839 ms plain / 98.847 ms with Yas, and
the later live TSX session reached 228.002 ms typing / 185.379 ms deleting. They
must be rechecked; passing the one confirmed-choice gate does not certify all
editor latency. Raw stage, cold, maximum, GC and output hashes remain available.

During measurement, unrelated Emacs compilation and later Rust/Clang builds were
observed. System load snapshots included 59.46 and 60.79 (one-minute load), with
more than 10 GB of swap in use. Large non-GC pauses occurred even in unchanged
CSS search code. These observations make attribution inconclusive; they do not
turn failed budgets into passes. No unrelated process was stopped and no GC or
expansion deadline was relaxed.

The next Emacs 30 stylesheet process raised `Expansion deadline exceeded` while
searching `m`. It produced a retained failure log, not a complete sample report.
The remaining serial queue was stopped. Its recorded wall duration includes the
orchestrator suspension and must not be interpreted as benchmark execution time.
Neither build has the three complete accepted cohorts required by the protocol.

## Lower-load retest

The initial restart measured the live worktree. Its source guard rejected the
Emacs 30 context run when CSS descriptor handling changed during measurement.
Six completed reports and the interrupted log remain separate evidence. They
were not combined with the following fixed-snapshot matrix.

The worktree was then frozen as fixture
`4462f881d2f309bfced2647f8bba5b948263dd91`, including the first descriptor
changes. Both actual straight installations matched all 31 runtime/data
resources. All four runners completed three fresh serial processes per build:
**24 complete reports**, with unchanged GC settings (800000 / 1.0), sample
counts, fixtures and budgets. All output, context, candidate and field assertions
passed. Independent recomputation verified every retained percentile, count and
GC interval. Source files, installed resources and Emacs binaries remained
unchanged throughout this matrix.

The following values are p99 in milliseconds. CSS search reports the worst of
twelve queries. CSS choices include the first-open sample in each path.

| Emacs / process | CSS search | CSS core | 135 KB context: read / type / programmatic | CSS choices: plain / Yas |
| --- | ---: | ---: | --- | --- |
| 31.1 / 1 | 2.969 | 0.463 | 3.219 / **5.659** / **6.314** | 2.600 / 2.646 |
| 31.1 / 2 | 2.290 | 0.277 | **5.533** / 4.765 / 3.729 | 2.406 / 2.721 |
| 31.1 / 3 | 1.179 | 0.254 | 3.302 / 3.990 / 3.928 | 5.235 / 5.890 |
| 30.2 / 1 | 2.572 | 0.327 | 2.611 / 4.067 / **5.760** | 7.028 / **23.115** |
| 30.2 / 2 | **8.579** | **0.567** | 2.505 / 2.868 / 3.135 | 2.400 / 3.364 |
| 30.2 / 3 | 2.334 | 0.463 | 2.463 / 3.847 / 2.870 | 2.331 / 2.897 |

Bold values exceed their existing budgets: CSS search 5 ms, CSS core 0.5 ms,
large-style context 5 ms and confirmed CSS choices 20 ms. The search failure is
`bdrs`. In total, seven gate checks failed across five reports; both builds'
third rounds passed all defined gates. Earlier failures remain failures.

All six markup reports passed, with a highest p99 of 0.746 ms. All TSX context
reports passed: highest p99 0.165 ms and worst size ratio 1.291. The worst
ordinary CSS/css-ts/SCSS/LESS/web size ratio was 1.444, below 2.

Large web-style full-completion p99 ranged from 31.400 to 75.183 ms across the
plain/Yas paths. Live-session typing/deletion p99 ranged from 1.460 to 5.366 ms
across CSS, css-ts, HTML style attributes and TSX style objects. These rows have
no aggregate budget and are not certified by the confirmed-choice gate. An HTML
style-attribute Yas flow also reached p99 33.742 ms in Emacs 31's third process.

GC diagnostics preserve the unfiltered acceptance result. In the failed Emacs
30 CSS/Yas path, eight of eleven samples above 20 ms included GC; its non-GC p99
was 8.900 ms. In the HTML style-attribute path, ten of eleven samples above 20 ms
included GC. By contrast, only two of 554 samples above 5 ms across the four
failing large-style context paths included GC, and their non-GC p99 values still
failed. GC alone cannot explain the context failures. Nested stage timings and
GC counts are inclusive and must not be added to the total.

Process-start one-minute load snapshots ranged from 3.47 to 17.24; the second
Emacs 30 stylesheet run occurred during a short load increase. These snapshots
do not establish the cause of individual pauses. No samples were discarded,
thresholds raised or budgets weakened. Several observed tails are lower than in
the contended matrix. Source and load both changed, so this is not a controlled
before/after comparison and does not close acceptance.

## Latest-worktree correctness follow-up

While the fixed performance matrix ran, descriptor shadowing and descriptor
color/image metadata received further edits. Those changes were preserved and
frozen separately as fixture `8c7ab50f2b6db30a00b425c2874a5faecd8c2388`.
Fresh installations and deterministic checks were repeated against this version:

| Check | Emacs 30.2 | Emacs 31.1 |
| --- | ---: | ---: |
| Actual isolated straight installation | 100/100 | 100/100 |
| Complete installed integration | 395/395 | 395/395 |
| Public core calls / mapped legacy cases | 3,206 / 182 | 3,206 / 182 |
| Byte-compiled editor checks | 165/165 | 165/165 |
| Project/test compilation and runtime package quality | Passed | Passed |

All 31 installed runtime/data resources matched the current worktree at the end
of these checks. Neither fixture is a live project commit; the staged diff was
unchanged. The three-process performance results apply to `4462f881`, not this
later runtime. Only reporting and a benchmark comment clarifying cold timing
were updated after validation; benchmark behavior was not changed.

GUI access was retried after the batch processes ended. Computer Use again
returned `-10005 timeoutReached` for `/Applications/Emacs.app`; no current popup
drawing or keyboard interaction was verified.

## Remaining acceptance

1. Investigate the retained large-style context failures and GC-associated
   completion tails, then repeat the unchanged protocol on a fixed final runtime
   without concurrent source edits or competing builds. The latest descriptor
   changes have correctness evidence but not their own three-process timing
   acceptance. Keep all earlier failed and interrupted evidence.
2. Verify actual GUI drawing and keyboard interaction. Computer Use returned
   `-10005 timeoutReached` for both the Emacs name and absolute app-path attempts.
   Batch Corfu replaces drawing, so it cannot close this gap. Check popup opening
   and frontend-configured sole-match acceptance, choice navigation/documentation,
   Yas field traversal and one-step undo in CSS, HTML style attributes and TSX.

Raw JSON (compressed), logs, profiler evidence, dependency/source manifests,
installation records and serial/recomputation scripts are retained under
`plans/native-emmet-rewrite/measurements/2026-09-29/native-host-acceptance/`.
The lower-load retest, interrupted restart, both new source snapshots and latest
correctness records are retained separately under
`plans/native-emmet-rewrite/measurements/2026-09-29/native-host-retest/`.
The final `emmet2-engine.el` SHA256 is
`9815a4a295a8ba6020a91eac7fc92de84acab374426b4e9856d837c75ea99af3`.
The machine was Apple M1 Pro, Darwin 27.0.0. Every measured process used normal
GC and byte-compiled project code. The local Emacs trampoline workaround only
disabled `native-comp-enable-subr-trampolines`; it is not a product change.

Architecture operation: `improve`. Inspected scope: result normalization and its
CSS/markup callers, native-host integration, actual installation, and benchmark
boundaries. The final residual scan introduced no additional runtime behavior or
ownership change. **INCOMPLETE** for full performance/GUI acceptance;
**RESIDUAL NOT NEEDED** for the stable implementation diff. The remaining work
is the named validation, independent of scss2's update.
