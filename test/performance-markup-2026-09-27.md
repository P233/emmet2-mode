# Native markup S6.0 measurements — 2026-09-27

S6.0 passes its local complete-path budget on the reviewed implementation. This
is partial engine acceptance: the editor still calls Node; full grammar, project
JSX transforms, lorem, stylesheet and release/GUI/hosted acceptance remain open.

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
