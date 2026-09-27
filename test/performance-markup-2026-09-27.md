# Native markup measurements — 2026-09-27

S6.4 passes the local complete markup budget; see the final section for the
15-input, six-process results including project JSX and seeded lorem. Earlier
S6.0/S6.1 sections retain their original evidence and limitations. The editor
still calls Node; stylesheet and release/GUI/hosted acceptance remain open.

## Method and provenance

- Apple M1 Pro, arm64 Darwin 27.0.0; official pinned Emacs 30.2 and 31.1 builds from `test/dependencies.json`.
- Working revision `200918c` plus the S6.0 diff; exact measured source hashes are below.
- Isolated bytecode compiled with warnings fatal; runtime symbol paths and bytecode types verified.
- `gc-cons-threshold=800000`, `gc-cons-percentage=1.0`; no samples removed and no per-operation GC forcing.
- Nine unchanged performance inputs, 100 warmups then 1,000 samples each, three fresh serial processes per Emacs version.
- Every operation includes parse, repeat conversion, snippet resolution, transformation, HTML/JSX formatting, character offsets, field normalization and cursor construction. Complete oracle equality is checked after each clock.
- Inputs interleave with the first input rotated each round. There is no cross-request expansion or snippet cache. One request-local table reuses snippet syntax; conversion creates owned nodes.
- `exec-path` is nil during expansions and the Node module is not loaded. This is a pure-engine benchmark, not the editor flow or a new actual package installation.
- First expansion per fixture and explicit bytecode module loading are separate cold measurements. Compilation and fixture loading precede them; they do not measure whole Emacs/package startup.
- Raw triple format: `[milliseconds, gc-count, gc-seconds]`. p99 is sorted sample 990 of 1,000. CI checks correctness, not machine-dependent timing.

## Reviewed warm results

Ranges are the minimum and maximum across the three independent processes, never
an average of percentiles. Max includes every pause; GC totals sum timed samples.

| Emacs | Fixture ID | p50 ms range | p99 ms range | Maximum ms | GC count / seconds |
| --- | --- | --- | --- | --- | --- |
| 30 | `html-contract-01` | 0.088–0.088 | 0.107–0.124 | 0.197 | 0 / 0.000000 |
| 30 | `html-contract-02` | 0.046–0.047 | 0.061–0.065 | 11.650 | 6 / 0.066305 |
| 30 | `html-contract-03` | 0.134–0.135 | 0.182–0.241 | 12.199 | 18 / 0.198431 |
| 30 | `html-snippet:!` | 0.113–0.114 | 0.148–0.157 | 11.462 | 6 / 0.065615 |
| 30 | `html-contract-04` | 0.026–0.026 | 0.034–0.038 | 11.814 | 3 / 0.033287 |
| 30 | `jsx-contract-03` | 0.014–0.014 | 0.018–0.020 | 0.058 | 0 / 0.000000 |
| 30 | `jsx-contract-04` | 0.048–0.048 | 0.064–0.074 | 11.994 | 3 / 0.034596 |
| 30 | `html-contract-14` | 0.014–0.014 | 0.019–0.020 | 0.057 | 0 / 0.000000 |
| 30 | `html-contract-10` | 0.014–0.014 | 0.019–0.020 | 0.088 | 0 / 0.000000 |
| 31 | `html-contract-01` | 0.085–0.086 | 0.120–0.127 | 11.563 | 9 / 0.099975 |
| 31 | `html-contract-02` | 0.045–0.045 | 0.058–0.061 | 11.442 | 2 / 0.022367 |
| 31 | `html-contract-03` | 0.130–0.131 | 0.179–0.185 | 12.083 | 15 / 0.167120 |
| 31 | `html-snippet:!` | 0.109–0.109 | 0.143–0.156 | 11.643 | 4 / 0.045280 |
| 31 | `html-contract-04` | 0.025–0.025 | 0.032–0.034 | 11.900 | 2 / 0.023147 |
| 31 | `jsx-contract-03` | 0.013–0.013 | 0.018–0.023 | 10.960 | 1 / 0.010895 |
| 31 | `jsx-contract-04` | 0.046–0.047 | 0.064–0.071 | 11.682 | 3 / 0.033992 |
| 31 | `html-contract-14` | 0.013–0.014 | 0.018–0.021 | 0.059 | 0 / 0.000000 |
| 31 | `html-contract-10` | 0.014–0.014 | 0.019–0.023 | 0.115 | 0 / 0.000000 |

All 54 reviewed fixture/process p99 values are <= 1 ms; the highest is 0.241 ms.
54,000 measured expansions and 5,400 warmups passed complete output checks.

| Fixture ID | Abbreviation | Preset |
| --- | --- | --- |
| `html-contract-01` | `ul>li.item$*5>a{Link $}` | html |
| `html-contract-02` | `div.card>(header>h2{Title})+section>p*3` | html |
| `html-contract-03` | `nav>ul>li*10>a[href=#]` | html |
| `html-snippet:!` | `!` | html |
| `html-contract-04` | `table>.row>.col` | html |
| `jsx-contract-03` | `Component.class` | jsx |
| `jsx-contract-04` | `input:checkbox` | jsx |
| `html-contract-14` | `div{😀 ${1:😸}}` | html |
| `html-contract-10` | `div{${1:x} ${1:x}}` | html |

## Cold values by process

| Emacs / run | Module loads ms | First expansion ms, in fixture order above |
| --- | --- | --- |
| 30 / 1 | 1.263 | 1.438, 0.058, 0.147, 0.167, 0.030, 0.017, 0.052, 0.020, 0.017 |
| 30 / 2 | 1.287 | 1.058, 0.055, 0.142, 0.122, 0.031, 0.015, 0.053, 0.018, 0.017 |
| 30 / 3 | 1.387 | 0.892, 0.056, 0.141, 0.121, 0.030, 0.016, 0.052, 0.019, 0.016 |
| 31 / 1 | 1.347 | 1.384, 0.057, 0.148, 0.127, 0.029, 0.016, 0.053, 0.019, 0.017 |
| 31 / 2 | 1.244 | 1.108, 0.053, 0.136, 0.118, 0.029, 0.014, 0.051, 0.018, 0.017 |
| 31 / 3 | 1.316 | 1.231, 0.058, 0.150, 0.120, 0.029, 0.019, 0.049, 0.017, 0.016 |

## Retained earlier results and diagnosis

The first three valid Emacs 31 runs (`baseline2`, `baseline3`, `baseline4`) used
per-node snippet parsing. The nav fixture failed the first run at 1.367 ms p99;
the other two were 0.247 and 0.272 ms. Seven GC samples and six non-GC samples
exceeded 1 ms in the failed row, including a 17.020 ms non-GC pause. The precise
cause of those non-GC pauses is not established; they have not been removed.

Instrumented parsing across nine fixtures found 16,515 parses of `a[href]`
(75.860 ms aggregate). The request-local syntax table removes that repeated
work; it does not retain results across calls. The earlier and later preloaded
correctness corpora differ (25 versus 40 selected cases), so these cohorts are
not used to claim a precise percentage improvement or explain all tail pauses.

| Earlier cohort | Process | Highest fixture p99 ms | Largest pause ms |
| --- | --- | --- | --- |
| Before reuse | `emmet2-markup-spike31-baseline2.json` | 1.367 | 17.020 |
| Before reuse | `emmet2-markup-spike31-baseline3.json` | 0.247 | 12.319 |
| Before reuse | `emmet2-markup-spike31-baseline4.json` | 0.272 | 12.544 |
| Before field review fix | `emmet2-markup-spike30-final1.json` | 0.192 | 11.677 |
| Before field review fix | `emmet2-markup-spike30-final2.json` | 0.231 | 11.648 |
| Before field review fix | `emmet2-markup-spike30-final3.json` | 0.428 | 24.426 |
| Before field review fix | `emmet2-markup-spike31-final1.json` | 0.213 | 12.027 |
| Before field review fix | `emmet2-markup-spike31-final2.json` | 0.230 | 12.143 |
| Before field review fix | `emmet2-markup-spike31-final3.json` | 0.182 | 11.896 |

The six intermediate `final` runs passed before primary review found multiline
field-default and invalid-field-suffix defects. Those were fixed with failing
handwritten tests; all six processes were measured again as `reviewed`.
An earlier report serialization error and an encoding prompt produced no valid
result file; their logs are retained and are not counted as accepted measurements.

## Correctness and limits

- Native source ERT: six tests on both pinned Emacs versions, including all 241 current markup oracle cases and 40 explicitly selected spike cases.
- Bytecode editor/native ERT: 54/54 on each build; Node protocol: 12/12 on each, including all 509 core inputs. The original 494 inputs/results are unchanged; 15 explicit cases were added.
- Handwritten checks cover token-local mirrors, conflicting defaults, empty fields at the same offset, emoji, multiline defaults, precise lexical errors, shared deadline, source/editor immutability and shared syntax immutability.
- Scoped byte compilation remains warnings-fatal; oracle `--check`, actionlint and diff checks pass. Existing-output rejection is verified.
- The full frozen markup corpus primarily covers shipped snippets. Passing it does not prove full tokenizer/parser/formatter coverage. Primary attributes, JSX shorthand/project CSS Modules/Solid transforms, snippet/text-child edge cases and lorem still require the S6.1/S6.2 corpus and implementation.
- Upstream token-parser errors such as `div)` carry `pos` but no `string`; the existing Node adapter currently classifies them as backend errors. This pre-existing gap is explicitly assigned to the next error-corpus slice; no current goldens were changed to hide it.
- M1 GUI and hosted CI remain unverified; the default engine remains Node.

## Reproduction and retained evidence

Run `test/bench-markup.el` using the command in [PERFORMANCE.md](PERFORMANCE.md)
with a new output name, serially in each fresh process. Raw JSON and diagnostic
logs are gzip archived under the ignored directory
`plans/native-emmet-rewrite/measurements/2026-09-27/markup-s6.0/`.
All stored summary statistics were independently recomputed from raw samples;
archive round trips and reviewed source hashes were checked.

| Measured source | SHA256 |
| --- | --- |
| `emmet2-engine.el` | `fc47373962a6a20e3966859e77900e14f8e6c7500e514c53429e83ba6f4567df` |
| `emmet2-engine-markup.el` | `82d2cd25f1491962bc1e9886c54205fd21363d80c92d7d57277fef3293ab6eef` |
| `data/emmet/html.json` | `e71fa03133b6a9900f50fe2fda6322482654090a005f98781261c0350d054212` |
| `data/emmet/variables.json` | `58bb8e0278c2240973cf6fa2a663dafaee5137bc102a28f78c01f5fca0d7d851` |
| `test/emmet2-engine-markup-test.el` | `2614e559a48d201a1acac0fffe402cb2ce48e3d6e03e5da94a6d5bcfb6c92a3f` |
| `test/fixtures/core-inputs.json` | `49820c7a721df8f04120cf6a11240a41e4cb610b5fb0a73d9b64099d69bc886c` |
| `test/fixtures/oracle/markup.json` | `8edef4e7bdb3229adf213c4f9315517a341793bc5841a0732721beb35958489e` |
| `test/bench-markup.el` | `5a2c986fd56207c032b65dc250d375d8f6d0f47c0ccd3e0f4fb5b59b872517fc` |
| `test/dependencies.json` | `8e8bd5bf9f88b66d85d6815d6c1c4cf6e5eeed956342803a5cf52c9c702aabc0` |

| Reviewed raw JSON | SHA256 (uncompressed) |
| --- | --- |
| `emmet2-markup-spike30-reviewed1.json` | `bc7e47f6d93fd388c0067e0a218ccc2046599cebcb233042e7139ba1d855b8b5` |
| `emmet2-markup-spike30-reviewed2.json` | `afe86c4e32b492545b861cf3949b4740ae25f651085999232daa9958f17e1431` |
| `emmet2-markup-spike30-reviewed3.json` | `0ab61607d5cf004e102e2f102126fda2a325bcb420414d3ad521df2c6fa2d7db` |
| `emmet2-markup-spike31-reviewed1.json` | `9b196de758a3a179313163a3a8e3c7a0e871f852701bccd0858884d4fb4d1546` |
| `emmet2-markup-spike31-reviewed2.json` | `60d78f759ea099d796576ad83ee1a9cab5b5704bea92949bbedcef57ca5ce895` |
| `emmet2-markup-spike31-reviewed3.json` | `c803b8ff33050eecbcbd95b96e5bc2f92433ea2dddc6a27885d586d55fd48e1a` |

## S6.1 grammar checkpoint (after cc0cd97)

The sections above retain the S6.0 historical source and evidence. This checkpoint
replaces the original character parser with complete tokenization followed by
parsing/conversion, and preserves the same nine benchmark inputs, harness, normal
GC settings, bytecode isolation and per-sample result checks. The final six serial
processes add 54,000 measured samples and 5,400 warmups. Every fixture/process
p99 remains below 1 ms; highest p99 is 0.920 ms. The maximum sample is 33.105 ms,
with all GC and slow samples retained. One Emacs 31 cohort has higher tails
across several fixtures; its cause is unconfirmed and it is not excluded.

| Final raw JSON | Highest p99 ms | Maximum ms | Largest first-call ms | Module load ms |
| --- | ---: | ---: | ---: | ---: |
| `emmet2-markup-grammar30-reviewed1.json` | 0.281 | 12.597 | 1.642 | 1.592 |
| `emmet2-markup-grammar30-reviewed2.json` | 0.581 | 12.082 | 1.134 | 1.694 |
| `emmet2-markup-grammar30-reviewed3.json` | 0.314 | 12.491 | 1.140 | 1.617 |
| `emmet2-markup-grammar31-reviewed1.json` | 0.250 | 12.051 | 1.517 | 1.657 |
| `emmet2-markup-grammar31-reviewed2.json` | 0.920 | 33.105 | 1.215 | 1.511 |
| `emmet2-markup-grammar31-reviewed3.json` | 0.267 | 12.176 | 0.949 | 1.609 |

The initial Emacs 31 cohort (highest p99 0.336 ms) is retained separately, before
the final attribute/error-precedence corpus and conversion changes. It is not
part of the six accepted cohorts. These results are an absolute-budget check;
they are not a percentage comparison with S6.0, because the implementation
and loaded correctness corpus changed. Cold values exclude process startup,
compilation and module loading, as in the original harness.

Correctness: eight source-native tests and 56 bytecode editor/native tests on
each pinned Emacs build; thirteen real Node protocol tests on each; eleven Node
adapter tests. Markup has 442 oracle cases; combined core has 710. The previous
578 inputs/results are unchanged. Scoped compilation/lint and oracle checks pass.
Third-party package compiler warnings remain separate from project compilation.
This does not close full S6: seeded lorem and project JSX transformations, final
integration/performance, M1 GUI and hosted CI remain outstanding.

Raw initial/final JSON is gzip archived in the ignored directory
`plans/native-emmet-rewrite/measurements/2026-09-27/markup-s6.1/`. Summary values,
archive round trips and final source hashes were independently checked.

| Final measured source | SHA256 |
| --- | --- |
| `emmet2-engine.el` | `fc47373962a6a20e3966859e77900e14f8e6c7500e514c53429e83ba6f4567df` |
| `emmet2-engine-markup.el` | `e500d03266eb99c6ddb5a9ed10211d92fceb5f38023941ca265672943a090e13` |
| `data/emmet/html.json` | `e71fa03133b6a9900f50fe2fda6322482654090a005f98781261c0350d054212` |
| `data/emmet/variables.json` | `58bb8e0278c2240973cf6fa2a663dafaee5137bc102a28f78c01f5fca0d7d851` |
| `test/emmet2-engine-markup-test.el` | `faec9a5924466043d002233e25fedffd8e856e61e36f88a1124a95458be42d38` |
| `test/fixtures/core-inputs.json` | `2ae8fad17097e2078bcf525816561e653c74fb1334f53b3dfdf6f5040d53d1eb` |
| `test/fixtures/oracle/markup.json` | `e581a12a2cb29a727c3826a16d746ea28fe377e9381f3c86e3541e6bfb6d7fc0` |
| `test/bench-markup.el` | `5a2c986fd56207c032b65dc250d375d8f6d0f47c0ccd3e0f4fb5b59b872517fc` |
| `test/dependencies.json` | `8e8bd5bf9f88b66d85d6815d6c1c4cf6e5eeed956342803a5cf52c9c702aabc0` |

| Raw JSON | SHA256 (uncompressed) |
| --- | --- |
| `emmet2-markup-grammar30-reviewed1.json` | `20916d42b0b072004b7b61c2da105790dc01d9ea60a3c4f4d23e33b13b083528` |
| `emmet2-markup-grammar30-reviewed2.json` | `44044866b2742be6e09e919d5b08e319aa5a2a434104c1f3e7bb138d9dc36ed9` |
| `emmet2-markup-grammar30-reviewed3.json` | `0cfaf40b5fedec7a9f5ba47842ec70b8bda9a38e284eef6706963e374f17055b` |
| `emmet2-markup-grammar31-reviewed1.json` | `1494ff5adbb65c9a6a2b30d6b401bbf65d005427d0772cce113f2a9c185ba17d` |
| `emmet2-markup-grammar31-reviewed2.json` | `ce800020fcb4703ade6b8217d859f0498acfd697df21329914e54780a2c2d322` |
| `emmet2-markup-grammar31-reviewed3.json` | `a39f4a36cede8a4bfc9fdae29cbb5bb1ac633d75418ec9a3c785af3e33183a7f` |
| `emmet2-markup-grammar31-initial1.json` | `79f6ab3e49fc2e68af6d9b9c69a902db51e84f80c195540051d306a76c8fd0c9` |

## S6.4 complete markup gate

All 90 final fixture/process rows pass the 1 ms p99 gate. The highest p99 is **0.210 ms**; the largest retained sample is **12.398 ms**. This closes the local S6 engine budget, alongside deterministic, lorem and independent integration checks. The editor still uses Node; S7 stylesheet, default switching and GUI/hosted gates remain open.

Measured production is signed revision `5d94d66`, unchanged during this slice. The benchmark, shared lorem assertion helper and documentation were dirty; the final 15 source/data/fixture hashes below identify the measured code. The original nine inputs remain; three project JSX cases and Latin 80/Russian 50/Spanish 50 lorem cases bring each process to 15,000 retained operations. Six final serial processes retain **90,000 measured samples and 9,000 warmups**, plus first calls. Run order was 31-1, 30-1, 31-2, 30-2, 31-3, 30-3.

Hardware/build/GC and measurement boundaries are the same as above. Lorem uses seed 42; its first timed result is structurally checked outside the clock and retained as the reference for all later complete-result comparisons. Every process produced identical text/fields/cursor for each of the 15 cases. This does not compare independently random implementations word for word. Module loading precedes first-call timing; compilation, fixture loading, assertions, Emacs startup and GUI painting are outside the expansion clock.

No runtime performance optimization was made in this slice; differences from historical cohorts are not a claimed speedup. Every slow sample is retained. Passing p99 does not mean every expansion finishes under 1 ms.

### Measurement correction found during primary review

The initial six S6.4 cohorts had a maximum p99 of 0.214 ms and maximum sample of 12.038 ms. Review found a sample with roughly 10.5 ms of GC but only 0.053 ms of elapsed time: the harness read GC counters after allocating the timing/sample representation, so a collection after the end timestamp could be charged to the preceding expansion. Those counters do not reliably describe GC within that expansion.

The harness now snapshots both ending GC counters immediately after expansion, before taking the end timestamp and calculating/allocating the duration. This keeps the counter interval inside the timed interval; timing also includes the small counter-read overhead. Bookkeeping and correctness checks remain outside the timed expansion. All six processes were rerun; the initial raw records are retained separately below. The final audit checks that each recorded GC duration is no greater than its elapsed interval (1 microsecond tolerance), including warmups and first calls.

The same old counter ordering was present in S6.0/S6.1. Their archived expansion timings remain recorded, but their per-operation GC attribution and GC totals can include bookkeeping outside the interval. Use the final S6.4 cohorts for corrected GC attribution; historical GC totals are not silently rewritten.

### Final per-process summary

| Process | Highest p99 ms | Maximum ms | Largest first call ms | Module load ms | Measured GC count | Measured GC ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 30.2 / 1 | 0.210 | 12.004 | 0.911 | 1.780 | 17 | 177.767 |
| 30.2 / 2 | 0.207 | 11.468 | 0.908 | 1.776 | 17 | 177.494 |
| 30.2 / 3 | 0.199 | 11.451 | 0.958 | 1.792 | 17 | 174.155 |
| 31.1 / 1 | 0.193 | 12.398 | 1.589 | 1.704 | 16 | 168.798 |
| 31.1 / 2 | 0.194 | 11.317 | 1.006 | 1.592 | 16 | 164.121 |
| 31.1 / 3 | 0.204 | 12.120 | 1.079 | 1.769 | 16 | 166.136 |

### Emacs 30.2: final per-fixture results

Every cell lists process 1 / 2 / 3; timing values are milliseconds. No percentile is averaged across processes.

| Input ID | p50 | p99 | max | GC count | GC ms |
| --- | --- | --- | --- | --- | --- |
| html-contract-01 | 0.119 / 0.119 / 0.118 | 0.140 / 0.137 / 0.133 | 11.015 / 10.519 / 10.627 | 2 / 2 / 2 | 21.227 / 20.416 / 20.521 |
| html-contract-02 | 0.072 / 0.072 / 0.072 | 0.089 / 0.085 / 0.085 | 10.756 / 11.304 / 11.040 | 3 / 3 / 3 | 30.810 / 32.209 / 30.734 |
| html-contract-03 | 0.174 / 0.174 / 0.173 | 0.210 / 0.207 / 0.199 | 12.004 / 10.702 / 11.451 | 5 / 5 / 5 | 53.740 / 51.401 / 51.735 |
| html-snippet:! | 0.169 / 0.168 / 0.168 | 0.198 / 0.199 / 0.189 | 10.369 / 11.170 / 10.328 | 2 / 2 / 2 | 19.909 / 20.903 / 19.978 |
| html-contract-04 | 0.038 / 0.038 / 0.038 | 0.046 / 0.046 / 0.043 | 0.059 / 0.068 / 0.073 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| jsx-contract-03 | 0.022 / 0.022 / 0.022 | 0.027 / 0.027 / 0.025 | 0.049 / 0.037 / 0.053 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| jsx-contract-04 | 0.081 / 0.081 / 0.081 | 0.098 / 0.096 / 0.093 | 10.480 / 10.587 / 10.603 | 1 / 1 / 1 | 10.372 / 10.473 / 10.491 |
| html-contract-14 | 0.022 / 0.022 / 0.022 | 0.028 / 0.027 / 0.026 | 10.279 / 10.256 / 10.189 | 1 / 1 / 1 | 10.241 / 10.220 / 10.158 |
| html-contract-10 | 0.022 / 0.022 / 0.022 | 0.027 / 0.027 / 0.027 | 11.252 / 10.323 / 10.498 | 1 / 1 / 1 | 11.199 / 10.280 / 10.436 |
| jsx-project-007 | 0.035 / 0.035 / 0.035 | 0.042 / 0.044 / 0.042 | 0.082 / 0.081 / 0.064 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| jsx-project-038 | 0.034 / 0.034 / 0.034 | 0.044 / 0.040 / 0.039 | 0.066 / 0.047 / 0.074 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| jsx-project-084 | 0.082 / 0.082 / 0.082 | 0.097 / 0.099 / 0.096 | 9.654 / 11.468 / 10.068 | 1 / 1 / 1 | 9.547 / 11.337 / 9.951 |
| lorem-006 | 0.049 / 0.049 / 0.049 | 0.058 / 0.059 / 0.057 | 0.073 / 0.103 / 0.063 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| lorem-012 | 0.036 / 0.036 / 0.036 | 0.044 / 0.046 / 0.041 | 0.076 / 0.075 / 0.056 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| lorem-015 | 0.031 / 0.031 / 0.031 | 0.040 / 0.042 / 0.036 | 10.788 / 10.318 / 10.210 | 1 / 1 / 1 | 10.722 / 10.255 / 10.151 |

### Emacs 31.1: final per-fixture results

Every cell lists process 1 / 2 / 3; timing values are milliseconds. No percentile is averaged across processes.

| Input ID | p50 | p99 | max | GC count | GC ms |
| --- | --- | --- | --- | --- | --- |
| html-contract-01 | 0.116 / 0.116 / 0.116 | 0.135 / 0.142 / 0.139 | 11.650 / 11.317 / 11.034 | 2 / 4 / 2 | 21.439 / 41.382 / 21.165 |
| html-contract-02 | 0.070 / 0.070 / 0.070 | 0.081 / 0.083 / 0.089 | 12.398 / 10.713 / 11.167 | 1 / 1 / 1 | 12.280 / 10.621 / 11.070 |
| html-contract-03 | 0.170 / 0.169 / 0.170 | 0.193 / 0.194 / 0.204 | 11.196 / 10.845 / 10.545 | 1 / 1 / 1 | 11.015 / 10.651 / 10.368 |
| html-snippet:! | 0.164 / 0.164 / 0.164 | 0.191 / 0.189 / 0.202 | 11.409 / 10.604 / 10.539 | 4 / 2 / 4 | 41.735 / 20.476 / 40.345 |
| html-contract-04 | 0.037 / 0.037 / 0.037 | 0.044 / 0.043 / 0.046 | 10.022 / 10.643 / 10.144 | 1 / 1 / 1 | 9.973 / 10.586 / 10.096 |
| jsx-contract-03 | 0.022 / 0.022 / 0.022 | 0.027 / 0.026 / 0.027 | 0.065 / 9.981 / 0.047 | 0 / 1 / 0 | 0.000 / 9.939 / 0.000 |
| jsx-contract-04 | 0.079 / 0.079 / 0.079 | 0.092 / 0.090 / 0.097 | 10.226 / 10.237 / 10.213 | 1 / 2 / 1 | 10.136 / 19.946 / 10.124 |
| html-contract-14 | 0.022 / 0.022 / 0.022 | 0.027 / 0.025 / 0.028 | 0.065 / 0.037 / 0.056 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| html-contract-10 | 0.021 / 0.021 / 0.021 | 0.027 / 0.026 / 0.025 | 9.905 / 0.041 / 10.144 | 1 / 0 / 1 | 9.875 / 0.000 / 10.113 |
| jsx-project-007 | 0.034 / 0.034 / 0.034 | 0.044 / 0.040 / 0.041 | 0.069 / 0.060 / 0.057 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |
| jsx-project-038 | 0.033 / 0.034 / 0.033 | 0.041 / 0.039 / 0.039 | 10.855 / 10.308 / 10.752 | 1 / 1 / 1 | 10.800 / 10.265 / 10.697 |
| jsx-project-084 | 0.081 / 0.081 / 0.081 | 0.096 / 0.095 / 0.100 | 10.074 / 0.190 / 10.082 | 2 / 0 / 2 | 19.790 / 0.000 / 19.930 |
| lorem-006 | 0.049 / 0.049 / 0.049 | 0.057 / 0.058 / 0.060 | 10.756 / 10.553 / 10.237 | 1 / 2 / 1 | 10.681 / 20.539 / 10.162 |
| lorem-012 | 0.035 / 0.035 / 0.036 | 0.043 / 0.042 / 0.043 | 11.121 / 9.765 / 12.120 | 1 / 1 / 1 | 11.074 / 9.716 / 12.066 |
| lorem-015 | 0.031 / 0.031 / 0.031 | 0.040 / 0.040 / 0.038 | 0.074 / 0.062 / 0.051 | 0 / 0 / 0 | 0.000 / 0.000 / 0.000 |

### S6.4 provenance

All twelve gzip archives are under the ignored `plans/native-emmet-rewrite/measurements/2026-09-27/markup-s6.4/` directory. Hashes below are for uncompressed JSON. An audit independent of the benchmark recomputed all final percentiles, maxima, sample counts and GC sums from raw triples and checked source hashes, GC interval bounds and complete output identity across processes.

| Final raw file | SHA256 |
| --- | --- |
| emmet2-markup-s64-reviewed-30-1.json | `6ba7782f2c708d3a07a0a02aa9230a8630351dd04b4f5f035a100ed6a853303c` |
| emmet2-markup-s64-reviewed-30-2.json | `3eb9027df18ed25e489f70d34090a29d42f11b15c666931fa843c2910f69a158` |
| emmet2-markup-s64-reviewed-30-3.json | `61a359224a921ae0e5e3db6121ad5d6971e561ec09117ee3f7b09e1a6c31e8da` |
| emmet2-markup-s64-reviewed-31-1.json | `fd69f0030d81d41d031da5d76f8410ba30ca8bbe8969f65c9c0fbb3bb84ba379` |
| emmet2-markup-s64-reviewed-31-2.json | `20ba749016bb30d2c12ee4b9c5439773cc81d8013a7335fcec6c91c97a613fdb` |
| emmet2-markup-s64-reviewed-31-3.json | `eebf26905b16781bfd78a968f6c5f309fee56ec803bac458fe925661b7f271d8` |

| Initial raw file (old GC attribution) | SHA256 |
| --- | --- |
| emmet2-markup-s64-30-1.json | `3f6ee507f2d21a650ab6c3785306f9a488754cc7605841b8972b26b29bae36db` |
| emmet2-markup-s64-30-2.json | `8b276304b1e8aacd75cf8bba8196f03d2b1b2e1081fdb80914318a98c04a3bb7` |
| emmet2-markup-s64-30-3.json | `668a80c2d69004abf8c5b40241c179dffa2f181fa60bc14b1b936f86e3353c8a` |
| emmet2-markup-s64-31-1.json | `97c5ecb01e1e95a7fefd80982230149424d6f591460b63d19e38f549418b342a` |
| emmet2-markup-s64-31-2.json | `cca6eef0bca11483a2dfb4b13bf2117169dc141b7972faf8139eee531cb42606` |
| emmet2-markup-s64-31-3.json | `eb42dd4fb38d46ca43e4df51b5f2d293f31a4514e11573827399b1c995190aa4` |

| Final measured input or code | SHA256 |
| --- | --- |
| emmet2-engine.el | `fc47373962a6a20e3966859e77900e14f8e6c7500e514c53429e83ba6f4567df` |
| emmet2-engine-markup.el | `0ba5a9c6883b0007b35c57b26220909dd7d2530caaef2e352ef8d839bb18c6b6` |
| data/emmet/html.json | `e71fa03133b6a9900f50fe2fda6322482654090a005f98781261c0350d054212` |
| data/emmet/variables.json | `58bb8e0278c2240973cf6fa2a663dafaee5137bc102a28f78c01f5fca0d7d851` |
| data/emmet/lorem/latin.json | `41d36ec83d6f6f1e13e9f0fe5faeeb27e3ea98a6d152968860bb035fa88b54bf` |
| data/emmet/lorem/russian.json | `96b9eec34568bd33eeb192134e5f5de53731216d3d691dd1b031ae9e6bfe86e5` |
| data/emmet/lorem/spanish.json | `ae5157cbc959856ffc73a0ff47babf9106603c3026a9feaa66f432563f143456` |
| test/emmet2-engine-markup-test.el | `a0b94758b3ce0b170ccb3bc75d1bdd9b4c1e6bdc982ba9b9351163774d12523e` |
| test/fixtures/core-inputs.json | `4a642561e31a77a405360d3627a26918fe0567222937f03aab2a1c724112516c` |
| test/emmet2-lorem-contract.el | `197170f7840e974924a90d74ad70afd5929f4ddba15e5a5c493a496e374a650f` |
| test/fixtures/lorem.json | `acb699d906b26033dbc25ad3de7e6a718c99733eb3782612980c73063b93a5e8` |
| vendor/emmet-source.json | `07498bd5f57bea64f3026ecb9576e5a4d84bc2f4a776dde79b9b1d14c5a485aa` |
| test/fixtures/oracle/markup.json | `7a7698952f86e918de810e9bf0342f8cdfce89ef63936b1151690d306d0444a4` |
| test/bench-markup.el | `25eac99c8e24b843c74ebafe6954b87d89a67f2437a09d1058b34ef267a30d1f` |
| test/dependencies.json | `8e8bd5bf9f88b66d85d6815d6c1c4cf6e5eeed956342803a5cf52c9c702aabc0` |
