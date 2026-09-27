# Native stylesheet measurements — 2026-09-27

S7.3 passes the local complete CSS budget on both pinned Emacs versions.
The six-property input passed all six fresh processes; its highest p99 was
0.366 ms against the fixed 0.5 ms budget. This is native core timing, not
editor/GUI latency or a before/after speedup claim. The default remains Node.

## Method and scope

- Apple M1 Pro, arm64 Darwin 27.0.0; pinned GNU Emacs 30.2 and 31.1.
- Revision `a2c62d5` plus benchmark/documentation changes; production code unchanged.
- Isolated core, fuzzy matcher and stylesheet bytecode, warnings fatal; loaded paths checked.
- Three fresh serial processes per version; no concurrent builds/tests or source edits.
- Twelve unchanged oracle inputs, 100 warmups and 1000 formal samples each: 72000 formal operations.
- Normal GC 800000/1.0; no samples or pauses removed and no forced per-operation GC.
- Full tokenization, parsing, fuzzy/value resolution, formatting, field normalization and cursor creation are timed.
- Every complete result is compared with the frozen oracle outside the clock. All 447 CSS success/error contracts pass in each process before warmups.
- Inputs interleave with the first one rotated per round; native calls have no executable path and reject process creation.
- First expansions and explicit bytecode loads are separate cold values; loads include fixed snippet preprocessing. Compilation/dependencies precede them; whole Emacs startup is excluded.
- p99 is sorted sample 990/1000; ranges below are minima/maxima of independent percentiles, never averaged percentiles.
- Raw `[milliseconds, gc-count, gc-seconds]` and complete expected results are retained. All statistics were independently recomputed; all 79272 cold/warmup/formal GC intervals fit inside their elapsed interval (1 microsecond tolerance).

## Fixed six-property gate

`m10+p5+bd1#2s+posa+dib+fz16` (`stylesheet-contract-10`).

| Emacs / process | p50 ms | p99 ms | Max ms | GC count / seconds |
| --- | --- | --- | --- | --- |
| 30 / 1 | 0.115 | 0.351 | 12.752 | 1 / 0.012562 |
| 30 / 2 | 0.116 | 0.194 | 12.255 | 1 / 0.012074 |
| 30 / 3 | 0.118 | 0.282 | 12.733 | 1 / 0.012570 |
| 31 / 1 | 0.113 | 0.366 | 12.232 | 2 / 0.023458 |
| 31 / 2 | 0.113 | 0.337 | 12.372 | 2 / 0.024150 |
| 31 / 3 | 0.112 | 0.178 | 12.084 | 2 / 0.023075 |

## All measured fixtures

Only the fixed six-property row has the S7 0.5 ms gate. The other rows are
additional reported boundary coverage. Maxima and GC totals retain all
three processes per version; individual process values remain in raw JSON.

| Emacs | Fixture | p50 ms range | p99 ms range | Max ms | GC count / seconds |
| --- | --- | --- | --- | --- | --- |
| 30 | `stylesheet-contract-10` | 0.115–0.118 | 0.194–0.351 | 12.752 | 3 / 0.037206 |
| 30 | `stylesheet-contract-01` | 0.051–0.052 | 0.083–0.147 | 0.817 | 0 / 0.000000 |
| 30 | `stylesheet-contract-06` | 0.037–0.037 | 0.069–0.124 | 13.722 | 9 / 0.108995 |
| 30 | `stylesheet-contract-09` | 0.024–0.024 | 0.045–0.083 | 0.240 | 0 / 0.000000 |
| 30 | `stylesheet-contract-11` | 0.021–0.022 | 0.041–0.066 | 0.765 | 0 / 0.000000 |
| 30 | `stylesheet-native-067` | 0.041–0.042 | 0.086–0.121 | 0.529 | 0 / 0.000000 |
| 30 | `stylesheet-native-070` | 0.048–0.049 | 0.086–0.141 | 13.417 | 3 / 0.038949 |
| 30 | `stylesheet-native-072` | 0.062–0.063 | 0.105–0.183 | 12.688 | 3 / 0.035857 |
| 30 | `stylesheet-native-097` | 0.043–0.044 | 0.074–0.123 | 0.525 | 0 / 0.000000 |
| 30 | `stylesheet-native-109` | 0.039–0.040 | 0.065–0.113 | 0.269 | 0 / 0.000000 |
| 30 | `stylesheet-native-176` | 0.055–0.057 | 0.094–0.177 | 25.281 | 6 / 0.084813 |
| 30 | `stylesheet-native-178` | 0.041–0.042 | 0.077–0.117 | 13.170 | 3 / 0.036325 |
| 31 | `stylesheet-contract-10` | 0.112–0.113 | 0.178–0.366 | 12.372 | 6 / 0.070683 |
| 31 | `stylesheet-contract-01` | 0.049–0.049 | 0.082–0.136 | 0.399 | 0 / 0.000000 |
| 31 | `stylesheet-contract-06` | 0.036–0.036 | 0.064–0.101 | 0.279 | 0 / 0.000000 |
| 31 | `stylesheet-contract-09` | 0.023–0.023 | 0.051–0.072 | 13.153 | 3 / 0.036854 |
| 31 | `stylesheet-contract-11` | 0.021–0.021 | 0.038–0.049 | 0.593 | 0 / 0.000000 |
| 31 | `stylesheet-native-067` | 0.040–0.041 | 0.068–0.125 | 0.729 | 0 / 0.000000 |
| 31 | `stylesheet-native-070` | 0.047–0.047 | 0.072–0.140 | 1.042 | 0 / 0.000000 |
| 31 | `stylesheet-native-072` | 0.060–0.060 | 0.104–0.190 | 12.403 | 6 / 0.071606 |
| 31 | `stylesheet-native-097` | 0.042–0.042 | 0.066–0.129 | 0.919 | 0 / 0.000000 |
| 31 | `stylesheet-native-109` | 0.038–0.038 | 0.077–0.119 | 12.489 | 6 / 0.071637 |
| 31 | `stylesheet-native-176` | 0.055–0.055 | 0.100–0.169 | 13.445 | 3 / 0.036918 |
| 31 | `stylesheet-native-178` | 0.040–0.040 | 0.086–0.144 | 12.592 | 6 / 0.071622 |

| Fixture | Input |
| --- | --- |
| `stylesheet-contract-10` | `m10+p5+bd1#2s+posa+dib+fz16` |
| `stylesheet-contract-01` | `c+bg` |
| `stylesheet-contract-06` | `bd+bd` |
| `stylesheet-contract-09` | `c#3.5` |
| `stylesheet-contract-11` | `p$a$b$c` |
| `stylesheet-native-067` | `lg(to right, #0, #f00.5)` |
| `stylesheet-native-070` | `tf:scale3d(1,2,3)` |
| `stylesheet-native-072` | `bxs:var(--bxsh-${1})` |
| `stylesheet-native-097` | `p${2:😀}-${1:x}-${2:😀}-${1:y}+m${1:z}` |
| `stylesheet-native-109` | `ct"😀"+m${1:😸}` |
| `stylesheet-native-176` | `@ff+m${1:😀}` |
| `stylesheet-native-178` | `ct"😀\nnext"+m${1:a\nb}` |

## Cold values

First expansion values follow the fixture order above. Later fixtures share
already loaded modules. These are single observations, not cold percentiles.

| Emacs / process | Module load ms | First expansions ms |
| --- | --- | --- |
| 30 / 1 | 3.643 | 0.211, 0.070, 0.046, 0.046, 0.024, 0.048, 0.057, 0.072, 0.052, 0.049, 0.087, 0.059 |
| 30 / 2 | 3.459 | 0.187, 0.064, 0.043, 0.051, 0.024, 0.046, 0.053, 0.068, 0.051, 0.099, 0.072, 0.046 |
| 30 / 3 | 3.523 | 0.186, 0.063, 0.054, 0.049, 0.025, 0.058, 0.059, 0.069, 0.053, 0.052, 0.072, 0.045 |
| 31 / 1 | 3.420 | 0.164, 0.057, 0.041, 0.041, 0.023, 0.047, 0.054, 0.062, 0.046, 0.042, 0.062, 0.043 |
| 31 / 2 | 3.354 | 0.163, 0.056, 0.041, 0.041, 0.023, 0.044, 0.050, 0.062, 0.046, 0.041, 0.061, 0.043 |
| 31 / 3 | 3.320 | 0.161, 0.057, 0.041, 0.043, 0.024, 0.044, 0.050, 0.063, 0.046, 0.042, 0.063, 0.043 |

## Reproduction and provenance

Use the stylesheet command in [PERFORMANCE.md](PERFORMANCE.md) with a new
absolute output file in each process. CI compiles the runner but does not
assert machine-dependent timing. Raw data is gzip archived under ignored
`plans/native-emmet-rewrite/measurements/2026-09-27/stylesheet-s7.3/`.

| Raw JSON (uncompressed) | SHA256 |
| --- | --- |
| `emmet2-stylesheet-s73-30-1.json` | `afe2898450fb68423fa4b2690fe054a846f2d69a78b729d17d73225af2cfb824` |
| `emmet2-stylesheet-s73-30-2.json` | `382d1d1f96edf497526218d125c0a97edafdbb31e247ada076a4fed711ea7d40` |
| `emmet2-stylesheet-s73-30-3.json` | `336bae29a119c444d8297d96256b562ca6898c423366403dfe9a8854b17605b7` |
| `emmet2-stylesheet-s73-31-1.json` | `f833e1a5706d48346c9f4af97577466136b9d886636b5785e6822e9aa6065df0` |
| `emmet2-stylesheet-s73-31-2.json` | `a410ff0c116a3496fb86e0d32c3b1feac0575803a4af805511055088f17e864e` |
| `emmet2-stylesheet-s73-31-3.json` | `8ef85072e21d717792fe4a16642942c8b387d9a20ffbb1e741d7ec465ba3cd8e` |

| Measured source/data | SHA256 |
| --- | --- |
| `emmet2-engine.el` | `fc47373962a6a20e3966859e77900e14f8e6c7500e514c53429e83ba6f4567df` |
| `emmet2-engine-stylesheet.el` | `a5b70a1af5da512d78aa500245c061ac9f9f4281bbb7fa640732b79cbb93c674` |
| `emmet2-fuzzy.el` | `8804ec16da1d4e6797a7f94fbabad4c652967fd179038b2381feb75ca2122867` |
| `data/emmet/css.json` | `c193df4a49e14d4246bbe6b39f7d5073d357883189d06d93f4d1ac7d28c85891` |
| `test/emmet2-engine-stylesheet-test.el` | `a1436a89bf24ce686e42fe427edf162e5b83c5436ef6d0b47573e51dff052209` |
| `test/fixtures/core-inputs.json` | `72b78eda680fae299ad00d910256ab1ddc479ac0b6ab496b125e0ff95e69ba60` |
| `test/fixtures/oracle/stylesheet.json` | `aebab2a172ede185c0db158d84aa4a895c909da49672c3150a30e3a40d0708c4` |
| `vendor/emmet-source.json` | `07498bd5f57bea64f3026ecb9576e5a4d84bc2f4a776dde79b9b1d14c5a485aa` |
| `test/bootstrap.el` | `91f9c27133956fa0541ca5ee2f06a22a6157717163a77b1cb3bfa0e2c83d442c` |
| `test/bench-stylesheet.el` | `9bba3e3e79ca7e29ca516836d101285cc5d008c896c80a2e559e43e5afcbeca4` |
| `test/dependencies.json` | `8e8bd5bf9f88b66d85d6815d6c1c4cf6e5eeed956342803a5cf52c9c702aabc0` |

## Acceptance boundaries

Actual straight installations of `a2c62d5` on both versions contain 31 runtime
resources and pass 48 editor tests each. Four separate installed Node/native
runs pass the same 250 integration tests (1669 core calls each), including
973 core oracle inputs and 42 lorem contracts. These installations are
separate from the benchmark temporary bytecode directories.

S6 markup and S7 CSS local correctness, installed integration and pure-core
performance gates now pass. M1 real GUI/Eglot interaction and hosted CI
remain open; default backend switching and runtime retirement await them.
