# Architecture refactor measurements — 2026-09-30

**Performance acceptance remains open.** The frozen final runtime candidate
passes 862 of 864 existing numerical gates across 24 complete reports. Two
Emacs 31 large-Web edit p99 values exceed 5 ms. Several other editor flows have
higher tails, despite lower typical latency. No budget has been relaxed and no
failed process percentile has been averaged away.

## Target and method

The comparison baseline is `0ed065889e96768b64b60507769683442b839d88` plus the
70 files already staged when work began, archived as fixture commit
`c437599a79727a67c1fc6e2d48dc589809936666`. The candidate is fixture commit
`812479ca36b3141f10a8d66d383abbda027df1df` (`candidate-v3`), including the
CSS-in-JS case-fold regression correction. These are disposable installation
fixture commits, not commits made in the user's checkout. Later edits change
prose only; runtime, tests and data match that snapshot.

Both versions use the same machine and pinned dependencies, Emacs 30.2 or 31.1,
normal GC (800000/1.0), 100 warmups and at least 1,000 retained samples per path
(10,000 for context), and three serial fresh processes per suite/build. All
four existing suites run in full. Own tests, builds and profiles never run
concurrently with timing. Desktop background activity was not disabled.
Bytecode checks remain enabled; both sides disable native cache loading with
`load-no-native=t`, JIT compilation and native subr trampolines. Path-only
native isolation was insufficient and its earlier failed attempts are retained.

An external Homebrew reinstall interrupted an additional Emacs 31 baseline
process. It produced no complete report. After the executable returned, both
31 installations and all 31 A/B measurements were repeated under its recorded
SHA256. Emacs 30 uses the original baseline and final candidate. Initial 31
results remain secondary evidence and are not mixed into this comparison.

The comparison contains 692 matched workload/stage rows, each with three
before/after processes. Raw warmups, samples, max, cold stages, GC counts/time,
source/fixture hashes and build configuration remain in the local archive.
Real Corfu control, formatting, popupinfo and insertion run in batch; drawing
is replaced. These measurements do not establish GUI input latency or Eglot
interaction, and module-load timings do not measure total Emacs startup.

## Mandatory gate failures

| Attribution | Process | Path | p99 / budget |
| --- | --- | --- | --- |
| Candidate | Emacs 31 round 1 | 135 KB Web typing + analysis | **7.092 / 5 ms** |
| Candidate | Emacs 31 round 1 | 135 KB Web programmatic edit + analysis | **5.775 / 5 ms** |
| Matched baseline | Emacs 30 round 2 | 135 KB Web typing + analysis | 5.633 / 5 ms |
| Matched baseline | Emacs 31 round 2 | markup `html-contract-03` | 3.474 / 1 ms |

The original, pre-reinstall baseline also retained five large-Web failures.
Those show that this path already had tail instability; they do not excuse the
candidate's failures. Both failed candidate edit paths recorded **zero GC** in
that process, so GC cannot explain these two failures. The same paths pass in
candidate rounds 2 and 3. Lower p50 does not establish the required tail bound.

## Selected complete paths

Each cell lists rounds 1 / 2 / 3 in milliseconds. No cross-process percentile
pooling is used. Complete Corfu flows have no invented aggregate budget; the
confirmed-choice flow retains its existing 20 ms budget.

| Emacs | Workload/path | Baseline p50 | Candidate p50 | Baseline p99 | Candidate p99 |
| --- | --- | --- | --- | --- | --- |
| 30.2 | css-confirmed-choices / completion | 2.031 / 1.988 / 2.043 | 1.872 / 1.885 / 1.768 | 2.370 / 2.398 / 3.473 | 3.316 / 2.214 / 2.075 |
| 30.2 | css-confirmed-choices / completion-yas | 2.359 / 2.303 / 2.365 | 2.199 / 2.201 / 2.053 | 2.839 / 2.758 / 4.148 | 3.978 / 2.561 / 2.399 |
| 30.2 | css-one / completion | 1.251 / 1.220 / 1.242 | 1.099 / 1.114 / 1.052 | 1.526 / 1.465 / 1.522 | 4.649 / 1.411 / 1.343 |
| 30.2 | css-one / completion-yas | 1.253 / 1.222 / 1.241 | 1.101 / 1.112 / 1.052 | 1.540 / 1.526 / 1.550 | 2.653 / 1.359 / 1.220 |
| 30.2 | css-six / completion | 2.861 / 2.795 / 2.846 | 2.770 / 2.818 / 2.637 | 3.286 / 6.322 / 3.330 | 12.623 / 3.632 / 3.003 |
| 30.2 | css-six / completion-yas | 3.203 / 3.116 / 3.192 | 3.090 / 3.166 / 2.930 | 3.617 / 6.699 / 3.651 | 10.033 / 4.513 / 3.415 |
| 30.2 | web-large-style-six / completion | 27.498 / 27.062 / 27.725 | 27.282 / 27.442 / 26.060 | 28.559 / 28.256 / 28.853 | 28.281 / 28.495 / 27.645 |
| 30.2 | web-large-style-six / completion-yas | 27.886 / 27.482 / 28.084 | 27.626 / 27.822 / 26.399 | 28.838 / 28.703 / 29.431 | 28.632 / 28.889 / 28.051 |
| 30.2 | web-large-style-135kb / analyze | 2.323 / 2.300 / 2.240 | 2.044 / 2.118 / 2.034 | 2.544 / 2.821 / 2.459 | 2.238 / 2.338 / 2.243 |
| 30.2 | web-large-style-135kb / programmatic-edit-and-analyze | 2.588 / 2.544 / 2.556 | 2.334 / 2.414 / 2.334 | 2.968 / 2.863 / 3.101 | 2.620 / 2.704 / 2.599 |
| 30.2 | web-large-style-135kb / typing-and-analyze | 2.624 / 2.599 / 2.537 | 2.332 / 2.413 / 2.333 | 2.934 / 5.633 / 2.805 | 2.592 / 2.700 / 2.568 |
| 30.2 | core:six-canonical | 0.190 / 0.185 / 0.179 | 0.176 / 0.186 / 0.177 | 0.264 / 0.236 / 0.222 | 0.271 / 0.283 / 0.213 |
| 31.1 | css-confirmed-choices / completion | 1.999 / 1.909 / 2.015 | 1.840 / 1.803 / 1.731 | 2.769 / 2.327 / 2.383 | 2.392 / 4.776 / 1.989 |
| 31.1 | css-confirmed-choices / completion-yas | 2.339 / 2.195 / 2.332 | 2.129 / 2.110 / 2.005 | 6.695 / 2.883 / 2.766 | 3.217 / 6.833 / 2.384 |
| 31.1 | css-one / completion | 1.177 / 1.169 / 1.199 | 1.096 / 1.085 / 1.044 | 1.714 / 2.160 / 1.533 | 7.704 / 13.585 / 1.374 |
| 31.1 | css-one / completion-yas | 1.179 / 1.175 / 1.195 | 1.099 / 1.088 / 1.045 | 1.509 / 1.837 / 1.505 | 1.438 / 3.214 / 1.215 |
| 31.1 | css-six / completion | 2.823 / 2.735 / 2.806 | 2.754 / 2.650 / 2.563 | 15.111 / 8.461 / 3.170 | 5.463 / 5.719 / 2.895 |
| 31.1 | css-six / completion-yas | 3.140 / 3.047 / 3.128 | 3.078 / 2.973 / 2.838 | 15.441 / 7.513 / 3.584 | 20.405 / 17.499 / 3.322 |
| 31.1 | web-large-style-six / completion | 27.985 / 27.461 / 27.741 | 27.564 / 27.327 / 26.157 | 75.414 / 62.719 / 29.565 | 34.174 / 44.099 / 27.802 |
| 31.1 | web-large-style-six / completion-yas | 28.337 / 27.890 / 28.117 | 27.919 / 27.618 / 26.362 | 57.305 / 58.635 / 35.146 | 34.715 / 45.937 / 28.324 |
| 31.1 | web-large-style-135kb / analyze | 2.368 / 2.344 / 2.377 | 2.175 / 2.144 / 2.092 | 3.176 / 4.300 / 2.716 | 2.471 / 3.735 / 2.320 |
| 31.1 | web-large-style-135kb / programmatic-edit-and-analyze | 2.631 / 2.605 / 2.673 | 2.475 / 2.418 / 2.375 | 3.125 / 4.314 / 3.211 | 5.775 / 4.093 / 2.628 |
| 31.1 | web-large-style-135kb / typing-and-analyze | 2.643 / 2.629 / 2.674 | 2.480 / 2.413 / 2.406 | 3.124 / 4.637 / 3.260 | 7.092 / 2.768 / 2.666 |
| 31.1 | core:six-canonical | 0.175 / 0.175 / 0.178 | 0.184 / 0.177 / 0.172 | 0.343 / 0.273 / 0.274 | 0.383 / 0.312 / 0.209 |

The retained attention report flags 31 rows, including nested stages, using
p50 median +15% and >0.05 ms or p99 median +25% and >0.3 ms. This is a diagnostic
filter, not an additional acceptance budget. None qualifies on p50; all are
tail flags. Some unchanged search paths also show tail inflation. That suggests
measurement/background variation as one hypothesis, not an established cause.

For example, Emacs 31 `css-one` plain completion GC counts are 8/8/8 before
and 10/10/10 after, while the interleaved yas path changes from 4/4/4 to 3/3/3.
For `css-six`, plain counts change from 5/6/5 to 1/1/1 and yas from 4/4/4 to
9/9/9. Allocation and phase changes can move pauses between these paths; do not
add nested stage totals or infer a leak from the per-path count alone.

## Focused diagnostics and architecture decisions

A serial, single-process-per-side CPU+memory profile covered the unchanged
large-Web fixture and the two CSS completion fixtures. Instrumented timings do
not replace budget samples. The Web CPU profile is dominated by
`parse-partial-sexp` (baseline 59.0%, candidate 64.9% of sampled weight) and
previous/next text-property traversal (34.0%, 28.7%). The candidate removes one
old region-discovery pass; the bounded parse from the CSS part start remains.
The profile locates steady work but does not explain a transient wall-clock
outlier or prove that the operating system caused it.

Whole-fixture sampled allocation weights, including setup, warmups, resets and
checks, rise by about 3.2% for `css-one` and 1.6% for `css-six`. These are one
profile each, not precise per-operation bytes, retained heap, RSS or a proof of
stable allocation regression. Regex/string work remains prominent. The evidence
does not justify adding another persistent cache or changing parsing semantics.

A separate single-round cache deletion experiment on candidate-v2 retains
100 warmups and 1,000 samples per live CSS edit. Removing confirmed-prefix reuse
raises typing/deletion p50 from 1.301/1.150 to 1.720/1.567 ms. Removing preceding
choice reuse gives 1.305/1.153 ms and raises typing GC from 8 to 10. Both bounded
reuse mechanisms remain; the experiment does not establish a benefit to deletion.

## Remaining acceptance work and evidence

The two failed Web gates and unexplained editor tail increases prevent a claim
that all important performance is equal or better. The smallest next investigation
is to correlate slow full-path samples with stage costs and scheduling under a
stable host build, then remeasure the unchanged full workload inventory after
any evidence-backed correction. An isolated passing rerun cannot erase the
retained failures. No performance tradeoff has been accepted by the user.

Local evidence is in the ignored `plans/architecture-refactor/` tree:
`final-benchmark-comparison.json`, `candidate-v3-benchmarks-summary.json`,
`final-profiles-summary.json`, `baseline/` and `final-evidence/`. The latter
contains raw compressed reports, full captured command logs, source archives,
installation checks and a SHA256 manifest. Reproduction scripts live alongside
it. [The protocol](PERFORMANCE.md) defines the budgets and full commands.

Computer Use could not start its native pipe. GUI painting, keyboard/focus
acceptance and Eglot coexistence remain separate open checks; batch controls are
not substituted for that evidence. No hosted CI or publication result is claimed.
