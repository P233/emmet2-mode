# Completion search measurements — 2026-09-28

Confirmed-prefix and preceding-candidate reuse reduce repeated expansion during
continuous typing. Search results, ordering, highlighting and insertion remain
unchanged. Functional checks pass; complete performance acceptance remains open:
one of six final S7 processes exceeds its existing p99 budget, and opening 479
candidates still takes about 46 ms before screen painting.

## Scope and retained state

- The completion table owns one confirmed-prefix result. `ovh,ta → ovh,tac` expands
  `ovh` once. Prefix edits replace it, removing the prefix clears it, and invalid
  context or render settings invalidate the table.
- Canonical results may be reused from the immediately preceding candidate set
  by complete abbreviation. Old entries are not retained as a growing history.
  Each revision creates fresh choice identities, highlights and previews.
- Confidence checks stop at the first viable match. The matcher folds strings
  once per pair and handles a compact property prefix without dynamic matching.
- Keyword resolution preserves scope and spelling tie breaks without sorting
  each vocabulary; later scopes are skipped after an exact match. No query cache,
  frontend advice, candidate cap or GC-setting change was added.

## Measurement boundary

- These measurements and validation counts describe the archived source hashes
  below. The subsequent Primary review corrected dual-role CSS property
  classification and full-property value parsing; those corrections are not
  covered by this historical performance acceptance evidence.
- Apple M1 Pro, arm64 Darwin 27.0.0; Emacs 31.1 for completion/host diagnostics;
  pinned Emacs 30.2 and 31.1 for the formal stylesheet rerun.
- Repository HEAD is `0ed065889e96768b64b60507769683442b839d88` with existing dirty
  work. **Before** means the data-driven fuzzy implementation at the start of this
  performance review, not HEAD or the retired Emmet algorithm.
- Isolated bytecode copies of runtime/data and the pinned Corfu dependency were
  used. Project compilation treats warnings as errors. Copies are not new
  package-manager installation acceptance. User configuration was not loaded.
- Completion diagnostics: three fresh serial processes per revision, 25 warmups
  and 100 retained samples per case. These short diagnostics do not replace the
  100-warmup/1000-sample S5 acceptance protocol.
- Completion GC settings stayed at 800000/1.0; all measured pauses were retained.
- Fresh completion timings include the real request, Corfu computation, display
  formatting, first/repeated documentation and acceptance. Live timings edit
  one surviving Corfu session. Drawing/hiding are stubbed; these are not GUI
  input-to-display, idle-delay, Eglot or screen-paint measurements.
- Six complete candidate-payload hashes agree before/after: canonical fields,
  cursor, preview and highlighted labels. The new internal abbreviation key is
  excluded from that comparison. No candidates were removed to improve timings.

## Complete Corfu paths

Each cell lists processes 1 / 2 / 3 independently, in milliseconds. Percentiles
are never averaged. GC counts are timed-operation totals per process.

### Before

| Path | Choices | p50 ms | p99 ms | Max ms | GC count |
| --- | ---: | --- | --- | --- | --- |
| `m10` | 1 | 0.280 / 0.286 / 0.287 | 0.469 / 0.460 / 0.512 | 11.340 / 11.802 / 12.707 | 1 / 1 / 1 |
| `ta` | 183 | 11.780 / 11.945 / 11.925 | 24.386 / 24.611 / 25.216 | 24.689 / 24.694 / 25.239 | 32 / 29 / 29 |
| `ovh,ta` | 183 | 12.613 / 12.854 / 12.740 | 25.418 / 25.825 / 25.821 | 25.445 / 25.890 / 26.127 | 36 / 36 / 36 |
| `ovh,t` | 479 | 49.326 / 49.724 / 50.089 | 62.294 / 51.097 / 60.714 | 93.277 / 51.162 / 75.352 | 75 / 75 / 75 |
| `ins` | 88 | 8.461 / 8.538 / 8.536 | 21.268 / 21.239 / 21.599 | 21.317 / 21.301 / 21.678 | 25 / 26 / 26 |
| `size` | 17 | 4.170 / 4.146 / 4.185 | 16.774 / 16.951 / 17.055 | 16.836 / 17.137 / 17.148 | 14 / 13 / 13 |
| `live/type-ta` | 183 | 11.546 / 11.335 / 11.118 | 32.369 / 24.427 / 29.096 | 41.715 / 24.427 / 40.946 | 49 / 49 / 44 |
| `live/delete-to-t` | 479 | 39.409 / 28.593 / 39.849 | 45.660 / 41.774 / 61.036 | 46.534 / 41.806 / 61.249 | 51 / 50 / 56 |

### After

| Path | Choices | p50 ms | p99 ms | Max ms | GC count |
| --- | ---: | --- | --- | --- | --- |
| `m10` | 1 | 0.277 / 0.281 / 0.293 | 0.514 / 0.436 / 9.134 | 11.773 / 11.665 / 12.984 | 1 / 1 / 1 |
| `ta` | 183 | 10.998 / 10.903 / 10.962 | 24.043 / 23.724 / 23.768 | 24.367 / 24.094 / 38.684 | 29 / 29 / 29 |
| `ovh,ta` | 183 | 11.795 / 11.723 / 11.640 | 24.685 / 24.789 / 24.655 | 36.992 / 24.873 / 25.205 | 32 / 32 / 32 |
| `ovh,t` | 479 | 46.384 / 46.184 / 46.035 | 48.038 / 47.754 / 56.389 | 48.077 / 47.758 / 65.483 | 67 / 67 / 67 |
| `ins` | 88 | 5.907 / 5.844 / 5.874 | 18.550 / 18.449 / 18.661 | 18.823 / 18.466 / 18.725 | 14 / 15 / 16 |
| `size` | 17 | 2.222 / 2.220 / 2.288 | 14.340 / 14.872 / 15.070 | 14.767 / 15.138 / 15.506 | 4 / 6 / 6 |
| `live/type-ta` | 183 | 5.764 / 5.699 / 5.720 | 19.651 / 18.839 / 19.022 | 20.234 / 18.939 / 19.366 | 11 / 11 / 10 |
| `live/delete-to-t` | 479 | 21.909 / 21.502 / 21.635 | 35.156 / 35.052 / 34.834 | 35.474 / 35.376 / 35.075 | 46 / 46 / 47 |

`type-ta` is `ovh,t → ovh,ta`; `delete-to-t` reverses that edit. The live
per-operation GC incidence moves across the median for deletion in the baseline,
so its 29–40 ms p50 range should not be reduced to a single speedup percentage.
Final typing p50 is 5.70–5.76 ms, down from about 11–12 ms. First-open `ovh,t`
remains the expensive path. Profiling found quadratic pairwise duplicate checks
in Corfu for same-text, distinct-property candidates; full result construction
also contributes. Redundant candidate-ID experiments gave little benefit and
were not adopted. The package does not patch Corfu internals.

## Shared CSS data and host completion

Pure-query figures below are warm diagnostics on the final implementation.
Cold full-metadata library loading is separate from process/dependency startup.

| Query | p50 range ms | p99 by process ms | Largest sample ms |
| --- | --- | --- | --- |
| `(property :query "ins")` | 1.745–1.769 | 14.689 / 14.739 / 14.688 | 15.376 |
| `(property :query "t")` | 1.666–1.679 | 14.747 / 14.493 / 14.809 | 15.282 |
| `(value :property "display" :query "ib")` | 0.091–0.092 | 0.098 / 0.195 / 0.106 | 13.241 |
| `(value :property "color" :query "r")` | 0.055–0.056 | 0.085 / 0.076 / 0.067 | 0.093 |

Full-metadata load: 5.964 / 5.826 / 6.557 ms.

Host diagnostics invoke real CSS2/SCSS2 context, completion and first-candidate
documentation after insert/delete, without Corfu or painting. They use 25 warmups
and 100 retained samples per process. The large fixture contains 2000 extra rules
and 92,024 bytes. All candidate-output digests agree across revisions.

| Host path | Before p50 range ms | After p50 range ms | After p99 by process ms | After max ms |
| --- | --- | --- | --- | --- |
| `css-property` | 4.559–4.725 | 3.381–3.529 | 16.292 / 16.393 / 16.071 | 16.929 |
| `css-value` | 0.335–1.609 | 0.285–0.350 | 1.976 / 1.940 / 1.876 | 13.816 |
| `scss-value` | 1.906–2.044 | 1.837–2.864 | 8.947 / 3.248 / 3.174 | 10.164 |
| `large-scss-value` | 10.722–11.112 | 10.353–10.768 | 13.116 / 13.176 / 12.921 | 25.489 |

SCSS value timings vary between processes, including the retained first final
run. These measurements do not establish a uniform host-completion speedup.
The small pure value-query cost does not justify adding a separate data cache.

## Formal S7 rerun: gate remains open

The existing runner, twelve fixtures, 447 expansion contracts, 100 warmups and
1000 retained samples per fixture were used unchanged. Three fresh serial
processes ran per Emacs version with normal GC 800000/1.0. The fixed gate remains
**p99 ≤ 0.5 ms** for `m10+p5+bd1#2s+posa+dib+fz16`.

Initial rows include the first completion optimizations but precede the later
keyword/partial-prefix optimizations. They are retained failures, not discarded
noise. The final six processes pass all full-output assertions; five satisfy the
timing gate. Final Emacs 31 process 3 has p99 **0.831 ms**, so the gate is not
declared passed. Several slow non-GC samples coincide with slow operations in
other fixtures; that observation does not establish their cause.

| Revision / Emacs / process | p50 ms | p99 ms | Max ms | GC count / seconds |
| --- | ---: | ---: | ---: | --- |
| Initial / 30 / 1 | 0.339 | 1.606 | 14.030 | 6 / 0.075334 |
| Initial / 30 / 2 | 0.336 | 2.223 | 33.851 | 6 / 0.079559 |
| Initial / 30 / 3 | 0.340 | 3.786 | 15.759 | 5 / 0.064785 |
| Initial / 31 / 1 | 0.336 | 0.701 | 15.558 | 2 / 0.029711 |
| Initial / 31 / 2 | 0.334 | 0.433 | 14.809 | 2 / 0.028632 |
| Initial / 31 / 3 | 0.338 | 0.530 | 15.399 | 2 / 0.029912 |
| Final / 30 / 1 | 0.294 | 0.395 | 13.438 | 5 / 0.060959 |
| Final / 30 / 2 | 0.293 | 0.388 | 12.943 | 5 / 0.060639 |
| Final / 30 / 3 | 0.292 | 0.391 | 12.666 | 5 / 0.058562 |
| Final / 31 / 1 | 0.291 | 0.385 | 15.157 | 4 / 0.056837 |
| Final / 31 / 2 | 0.291 | 0.390 | 14.943 | 4 / 0.056886 |
| Final / 31 / 3 | 0.291 | 0.831 | 28.596 | 4 / 0.071218 |

A separate starting-baseline S7 diagnostic (`stylesheet-before31-1.json`) is
also retained: p50 0.385 ms, p99 0.555 ms. Historical 2026-09-27 acceptance belongs
only to its recorded source revision. No historical baseline or gate was changed.

## Validation and provenance

- Emacs 30.2 and 31.1: 331 integration tests each, including 14,771 public engine
  calls; 120 bytecode editor tests each; strict project compilation and
  package-lint/checkdoc across all 12 runtime libraries.
- SCSS2 integration: 144 tests on each version. No sibling runtime files changed
  during this review; they consume the changed shared matcher.
- 245,000 full score/position comparisons match the starting implementation,
  including empty inputs, repeated characters, case, separators, camel case,
  Unicode and explicit partial matching. Digest:
  `c1fb7127642e6229f1694c4269c73b1badb4cf982a54f232bffddd0edf8605ba`.
- Prefix replacement/removal, settings invalidation, unchanged full insertion,
  stale choice rejection, bounded preceding-set retention and keyword tie
  semantics are covered by regression tests.
- No Emacs server socket was available for new GUI timing. Earlier manual GUI
  evidence does not measure this implementation. No commit or publish occurred.

Runtime source hashes (SHA256):

| File | Before | Final |
| --- | --- | --- |
| `emmet2-capf.el` | `5357d0a4bbc932db183e444d5333cacd0d34121206a549e4d0a8b94a1f1ada4c` | `b38f9f8c5cc1f1283adb81af6fde5f249c88de9137caca6007bd6518b8691df6` |
| `emmet2-fuzzy.el` | `250360d681223c1b13a85a8826eb861e3717262b62529cf25ba67c468997205c` | `97bc0a80e28e879fe817e120df6fcb6f2e0bff5e9871e04b8d224e150e1781a4` |
| `emmet2-engine-stylesheet.el` | `2a470e1416f2b03e10369554da96133ac7385d69bdfeac07e91b40b1ed800d3e` | `417ec32da10cadf4ede7ff2344471d29ec5c5997faa0e4c9a7bf6c065794d6ee` |

Raw JSON, all intermediate/failed runs, source archives, scripts and logs are
local ignored artifacts under:
`plans/native-emmet-rewrite/measurements/2026-09-28/fuzzy-search-review/`.
The `artifacts-sha256.json` manifest hash is
`4247eb74e7b3429eada2894ea55f358c8860c6328dfadddd25aa86dbd91e2068`.
It covers the raw sources/results; it does not include itself.

For the diagnostics, unpack a source archive, set `PERF_COHORT` to that cohort
directory, and use the archived `emmet2-perf-compile.el` followed by
`emmet2-perf-review.el` with `PERF_RUNS=100` and a fresh `PERF_OUTPUT` filename.
Both load the pinned dependencies through `EMMET2_TEST_DEPS=/tmp/emmet2-test-deps`.
`scss2-perf-query.el` additionally takes an owned `PERF_GRAMMAR` cache directory.
Run serially without concurrent builds/tests. The scripts retain their original
local checkout/bootstrap paths. For the formal S7 rerun, use the standard command
in [PERFORMANCE.md](PERFORMANCE.md) and a new output file for each process.
