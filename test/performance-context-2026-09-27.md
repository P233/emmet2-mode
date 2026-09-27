# Context measurements: 2026-09-27

S3 remains **OPEN**. The optimized TSX absolute budget passes these samples,
but some scale ratios and large web-mode programmatic edits still fail.

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
