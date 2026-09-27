# Context measurements: 2026-09-27

S3 remains **OPEN**. The initial measurements below exposed scale-ratio
variation and large web-mode programmatic edits; the follow-up section records
the bounded web scanner fix. Historical failures are retained.

Machine: Apple M1 Pro, arm64 Darwin 27.0.0; pinned GNU Emacs 31.1 and dependencies
from `test/dependencies.json`. Project code is byte compiled. Pinned web-mode is
source loaded, matching the isolated bootstrap. GC threshold is 800000 bytes,
percentage 1.0. Each of three fresh processes ran 22 fixtures, 100 warmups and
1000 samples per path: 198000 measured operations in total. Output/context was
checked after every operation. Cold initialization is retained separately.

The full-path baseline at `0f77f3a` showed approximately 31–32 ms p99 for
20k-line TSX reads and programmatic edits. Fixed compiled queries, independent
source/projection parsers and confirmed local units reduce all TSX p99 samples
to 0.016–0.119 ms across the three optimized runs. Baseline typing was not
measured, so no typing before/after claim is made.

TSX max/min p99 scale ratios (same kind/path across the five dimensions) are
below 1.5 in run 1. Run 2 fails at 1.526 for style/programmatic and 1.516 for
negative/typing. Run 3 fails at 3.306 for style/programmatic (0.036–0.119 ms).
These samples are retained; the cause of that variation is not yet established.
CSS/web ordinary-position large/small ratios remain below 2 in these runs.

135 KB style part, p99 milliseconds:

| Process | Read | Typing + analysis | Programmatic edit + analysis |
| --- | --- | --- | --- |
| 1 | 2.553 | 2.942 | 44.022 |
| 2 | 2.531 | 2.918 | 44.267 |
| 3 | 2.531 | 2.889 | 43.765 |

The programmatic path fails the 5 ms gate in every run. Diagnostic tracing
found that ordinary `insert` lacks the inherited `part-side` property, causing
web-mode to rescan the full part; `self-insert-command` keeps a local rule scan.
A separate bytecompiled-web-mode diagnostic still exceeded 5 ms, so changing
compilation alone is not a solution. Pending scans remain authoritative.

Raw JSON (including cold, per-operation GC and max) is compressed under the
ignored local plan directory `plans/native-emmet-rewrite/measurements/2026-09-27/`:
`context-baseline-31-1.json.gz` and `context-reviewed-31-{1,2,3}.json.gz`.
The optimized source and harness SHA256 values recorded by all three runs are:

- `emmet2-context.el`: `f7e0fe77b6e16b6abdc7a5a0d7a7bf7467fd94066bbeea38ce61c5ce8c5c7474`
- `test/bench-context.el`: `45575e440b636e5b7c8af7bcb4cc9b1b1e49f2e6731fea822f68e747fb8c8033`

The installed minor mode still uses the old Deno path. These are context API
measurements, not editor/GUI, expansion-engine or release acceptance.

## Follow-up: bounded web pending scans

Single-character ordinary insertions in previously scanned CSS rules now use
web-mode's own scanner with the original rule extent. The exact pending edit,
HTML content type and `none` engine must still match; structural, multiple or
unobserved edits use the ordinary scanner. No text properties are fabricated.

The full 22-fixture, three-process diagnostic cohort is retained as
`emmet2-web-bounded-31-{1,2,3}.json.gz`. Large style programmatic p99 dropped to
2.925–2.943 ms. TSX absolute p99 stayed below 1 ms, but sequential scale ratios
still varied. One 500-line style/typing outlier had zero GC and its median
changed from 0.034 ms to 0.119 ms within a 100-sample window. That is evidence
of time variation, not proof of its cause or a reason to discard samples.

After the final configuration and modification-tick guards, three fresh focused processes measured
the unchanged 135 KB fixture again (100 warmups and 1000 samples per path):

| Process | Read | Typing + analysis | Programmatic edit + analysis |
| --- | --- | --- | --- |
| 1 | 2.037 | 2.375 | 2.370 |
| 2 | 2.050 | 2.376 | 2.405 |
| 3 | 2.041 | 2.387 | 2.370 |

All focused paths meet 5 ms. These filtered runs validate this scanner slice;
they do not satisfy the full S3 gate. Their raw files are
`emmet2-web-tick-31-{1,2,3}.json.gz` in the same ignored measurements directory.
Final source SHA256:

- `emmet2-context.el`: `7ba5e79f9c14471e717d1fc3bf02d400eed72d9a5a836dd47dc77c74cabc1c02`

Correctness and warning-free compilation pass on both pinned Emacs versions:
68 scoped ERT tests, including property parity with a full rescan, exceptions,
cleanup, indirect changes, narrowing, configuration changes, nested hook edits and partial scan errors.

Next, compare sizes with interleaved sampling and 10000 samples per path to
reduce time-order bias. Keep the same complete operations, raw GC-inclusive
samples, three fresh processes and existing budgets. The exploratory paired
measurement is diagnostic only; a versioned runner and complete matrix are
still required before S3 closes.
