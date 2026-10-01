# Context and editor performance follow-up — 2026-10-01

**Result: all 624 existing numerical checks in the fixed 12-report follow-up
passed. Overall architecture acceptance remains incomplete: current GUI
interaction has not been verified, and historical sporadic tails are not fully
explained. No production code was changed by this investigation.**

The source includes the newly added optional Corfu presentation adapter. Both
Emacs 30.2 and 31.1 passed 415 source integration tests, 180 isolated bytecode
editor tests and 100 actual straight installation checks. These are separate
from graphical interaction. Engine-only markup/search benchmarks were not part
of this context/editor follow-up.

[Durable evidence](../plans/architecture-refactor/performance-followup-2026-10-01/README.md)
contains the frozen source, raw samples, logs, executable/source hashes, fixed
measurement plan, instrumentation and failed attempts. The measured snapshot's
local commit is `bf89657c6188af1e97213db31386c947d6a59c07`; the main checkout's
HEAD remained `0ed065889e96768b64b60507769683442b839d88`. The main index changed
during measurement without any index write by this session; both index snapshots
are retained, and the final staging is preserved. All measured working files
matched the frozen source before these documentation updates.

## Fixed measurement and results

The plan was recorded before the formal runs: context and completion, both
builds, three fresh processes each, every fixture, no filter, normal GC, strict
bytecode execution and serial measurement. No concurrent test/build or automated
GUI interaction ran during the formal measurements. Emacs 30's previously missing
Lisp/data resources were restored from the official 30.2 source archive; both
executables were hashed before and after every run. Locked dependencies were
recreated in an owned directory. This is a follow-up under the recorded current
environment, not a controlled before/after claim for an optimization.

All 12 runners completed with output, point and session assertions intact.
An independent pass recalculated p50, p99, max and GC totals from all
**5,304,000 measured operations**, checked sample counts, GC settings, source
hashes and the absence of fixture filters. Warmup and cold records remain
separate. The existing gate evaluator reports **624/624**, with no changed
budgets or discarded samples.

135 KB Web context p99, in milliseconds; each cell lists rounds 1 / 2 / 3:

| Emacs | Read | Typing and analysis | Programmatic edit and analysis |
| --- | --- | --- | --- |
| 30.2 | 3.075 / 2.433 / 2.273 | 2.866 / 3.751 / 2.645 | 2.788 / 3.187 / 2.724 |
| 31.1 | 3.243 / 4.300 / 2.280 | 2.855 / 3.201 / 2.714 | 3.496 / 3.727 / 2.625 |

The budget is 5 ms for every path/process. TSX absolute/scale gates and ordinary
CSS/Web scale gates also passed. The eight measured context source/harness files
are byte-for-byte equal to the archived candidate-v3 files. Consequently these
passes do not establish that a source change fixed the earlier **7.092 / 5.775 ms**
failures; those remain in the [previous report](performance-architecture-2026-09-30.md).

Confirmed-prefix ten-choice Corfu completion p99, milliseconds, budget 20 ms:

| Emacs | Without yas | With yas |
| --- | --- | --- |
| 30.2 | 3.019 / 2.267 / 2.074 | 9.113 / 2.760 / 2.458 |
| 31.1 | 2.301 / 4.361 / 2.055 | 2.682 / 2.866 / 2.346 |

## What the diagnostics establish

A separate instrumented Web context run recorded wall time, process CPU time,
GC and nested stages. One typing sample took **42.361 ms wall / 2.429 ms CPU**,
with zero GC; its lexical-state stage took 40.207 ms wall / 1.358 ms CPU.
This establishes a substantial non-CPU interval in that sample. It does not
identify its scheduling/I/O cause or explain every historical failure. Typical
lexical-state CPU time was about 1.2 ms. Instrumentation allocates additional
objects, so its timings and GC frequency are diagnostic only.

The first instrumented run finished its benchmark but failed serializing the
CPU-clock dotted pair. Its raw benchmark, failure log and exact script are
retained. The corrected stage report came from a separate fresh process.

Complete editor flows still have substantial tails outside the numerical gates
above. For the large-Web six-property flow on Emacs 31, total p99 was
45.678 / 29.188 / 36.093 ms without yas and 40.173 / 39.620 / 39.028 ms with yas.
All six p99-ranked samples had zero GC. In the 45.678 ms sample, the request stage
accounted for 45.271 ms. The existing protocol assigns no aggregate budget to
this flow; these numbers are reported, not silently called fast or excluded.

A separate request-only diagnostic retained 2,202 calls (cold, warmup and measured)
through this real flow. It found one context analysis and one host scan per
request. Its p50 stages were:

| Stage | Wall ms | CPU ms |
| --- | --- | --- |
| Whole request | 25.580 | 25.579 |
| `web-mode-scan` | 21.236 | 21.233 |
| `web-mode-scan-region`, nested in the above | 19.102 | 19.097 |
| CSS lexical state | 1.568 | 1.566 |
| Expansion choices | 2.188 | 2.186 |

These nested medians must not be added. This fixture includes the pending scan
left by a multi-character reset, as the protocol already specifies. It differs
from the single-character context path. The measured cost is chiefly the host's
pending scan, with one context analysis per request. Broadening the bounded scan
to compound edits would require new proof of Web part/rule boundaries and edit
coalescing; this follow-up does not introduce that state or an unproven lexical
cache. The formal full-flow tails cannot all be attributed to GC, and the
filtered diagnostic's GC pauses cannot explain GC-free formal samples.

## GUI and completion boundary

Computer Use could read the existing daily Emacs inventory. No interaction or
configuration change was made in daily buffers. A separate copied app and
isolated configuration loaded the current installed bytecode and pinned optional
dependencies.

The initial generated GUI script had a substitution error in an environment
variable name; that failed script is preserved. After correction, all prepared
fixture initializers passed in batch, and the separate GUI process recorded
`display-graphic-p = t` with its HTML fixture. Computer Use still timed out when
reading that app by path and by its running bundle ID. Its process log also
contains a sandbox-extension permission error; this is observed evidence, not a
proven root cause of the automation timeout.

No current popup rendering, keyboard/field/mirror navigation, undo/redo, stale
candidate interaction or real Eglot coexistence is marked passed. The user selected manual verification; actual observations are pending. Batch Corfu formatting, control, documentation and acceptance
remain validated, with drawing mocked. No GUI input/painting latency, hosted CI
or release result is claimed.

The smallest remaining actions are the functional GUI checklist in the prepared
isolated session and, if pursuing the full-flow latency further, a bounded host
scan design tested against compound edits and Web part boundaries. The present
results justify neither a speculative cache nor declaring the historical tails
fully resolved.
