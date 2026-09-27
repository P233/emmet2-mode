# Editor-flow measurements: 2026-09-27

This measures the complete S5 command/completion flow with the temporary Node
backend. It does not establish GUI, hosted CI or native-engine acceptance.
S5 has no aggregate latency budget; the S6/S7 engine budgets remain unchanged.

In the large style fixture, ordinary completion p50 changes from
97.498–98.031 ms to 64.380–65.012 ms; p99 changes from 139.056–149.308 ms to
97.936–113.961 ms across the three processes. Direct-command p50 remains near
27 ms. Repeated documentation p50 roughly halves. Small-input p99 still varies,
including regressions in individual processes; all are reported below rather
than treating the hotspot improvement as a universal tail-latency guarantee.

The baseline is revision `4471f71`, installed by the real isolated straight
recipe at `/tmp/emmet2-installed-recovery31/straight/build/emmet2-mode`.
The comparison uses `/tmp/emmet2-flow-optimized31`, a separate copy of that
installation with only `emmet2-capf.el` and its bytecode replaced. Both use
the same pinned GNU Emacs 31.1 compiler. The latter is a controlled measurement
artifact, not a second package-manager installation acceptance.

Environment: Apple M1 Pro, arm64 Darwin 27.0.0, Node 24.21.0, dependencies locked
by `test/dependencies.json`. Runtime project code is bytecode; the harness and
locked optional packages are source loaded. Normal GC is retained (800000
bytes, percentage 1.0). Each cohort runs three serial fresh processes, eight
fixtures, three interleaved paths, 100 warmups and 1,000 measured operations per
path: 72,000 measured operations and 7,200 warmups per cohort. No concurrent
builds or tests ran during measurement. Baseline processes precede comparison
processes; cohort order was not randomized.

The runner invokes real Corfu candidate formatting, popupinfo and acceptance,
replacing popup drawing/hiding and bypassing its error shield so failures
propagate. Every operation checks resulting text and
cursor; editable fields additionally require an active yas snippet. A reset is
outside the clock, but its pending web-mode scan is inside the next operation.
The large style fixture is 138,052 bytes. Its multi-character reset intentionally
uses the ordinary scanner, unlike S3's proven single-character insertion fast
path. These results do not replace S3 context measurements.

The measured hotspot led to one change: a cached completion result now checks
the current source/host once per access. Fresh backend work still checks before
and after, because synchronous process waits can run filters/timers. No cache,
state owner or invalidation path was added. A regression assertion changes
web-mode's host type without editing text and still rejects the old candidate;
backend-time source changes remain rejected.

All tables use milliseconds. Slash-separated entries are process 1 / 2 / 3,
not averaged percentiles. GC samples and outliers are retained. Request combines
analysis, expansion and frontend work; annotation is `corfu--exhibit`, including
candidate checks. Nested stages are already included in the total.

## Complete warm flow, before and after

| Fixture | Path | Before p50 | After p50 | Before p99 | After p99 |
| --- | --- | --- | --- | --- | --- |
| web-list | command | 0.270 / 0.206 / 0.221 | 0.196 / 0.205 / 0.193 | 1.257 / 0.440 / 0.842 | 0.395 / 0.416 / 0.362 |
| web-list | completion | 0.977 / 0.871 / 0.900 | 0.734 / 0.749 / 0.721 | 5.421 / 1.258 / 2.306 | 1.167 / 1.143 / 1.005 |
| web-list | completion-yas | 1.354 / 1.220 / 1.258 | 1.077 / 1.101 / 1.059 | 19.878 / 2.837 / 4.495 | 2.694 / 1.551 / 1.366 |
| web-card | command | 0.239 / 0.160 / 0.175 | 0.153 / 0.155 / 0.156 | 0.923 / 0.915 / 0.559 | 0.329 / 0.321 / 0.301 |
| web-card | completion | 0.893 / 0.745 / 0.778 | 0.614 / 0.625 / 0.621 | 2.279 / 2.143 / 2.047 | 0.836 / 0.882 / 0.874 |
| web-card | completion-yas | 1.256 / 1.058 / 1.107 | 0.919 / 0.937 / 0.924 | 3.046 / 7.773 / 3.103 | 1.230 / 1.302 / 1.255 |
| tsx-list | command | 0.476 / 0.379 / 0.374 | 0.341 / 0.341 / 0.350 | 0.750 / 0.841 / 0.816 | 0.736 / 0.626 / 0.632 |
| tsx-list | completion | 2.534 / 2.364 / 2.360 | 1.971 / 1.953 / 1.952 | 10.285 / 23.441 / 23.094 | 22.005 / 22.191 / 21.566 |
| tsx-list | completion-yas | 3.003 / 2.815 / 2.791 | 2.385 / 2.394 / 2.368 | 24.949 / 23.905 / 23.744 | 23.151 / 22.963 / 23.267 |
| css-one | command | 0.575 / 0.522 / 0.537 | 0.544 / 0.517 / 0.560 | 0.875 / 0.822 / 0.936 | 0.888 / 0.708 / 2.512 |
| css-one | completion | 1.061 / 0.967 / 0.989 | 0.931 / 0.881 / 0.952 | 1.483 / 2.766 / 1.550 | 1.500 / 1.107 / 4.778 |
| css-one | completion-yas | 1.073 / 0.972 / 0.993 | 0.929 / 0.885 / 0.950 | 1.433 / 1.610 / 1.581 | 1.487 / 1.113 / 5.286 |
| css-six | command | 3.746 / 3.446 / 3.500 | 3.428 / 3.427 / 3.395 | 5.576 / 4.234 / 4.710 | 4.462 / 4.324 / 4.012 |
| css-six | completion | 4.516 / 4.157 / 4.206 | 4.030 / 4.029 / 4.019 | 9.922 / 8.435 / 15.262 | 5.262 / 4.978 / 4.629 |
| css-six | completion-yas | 4.854 / 4.484 / 4.550 | 4.365 / 4.365 / 4.335 | 13.609 / 5.817 / 6.734 | 10.432 / 6.279 / 5.265 |
| css-fields | command | 1.684 / 1.497 / 1.588 | 1.476 / 1.523 / 1.515 | 4.053 / 1.925 / 4.535 | 1.770 / 1.849 / 2.029 |
| css-fields | completion | 2.267 / 2.008 / 2.126 | 1.906 / 1.956 / 1.953 | 6.083 / 2.499 / 6.706 | 2.308 / 2.349 / 2.589 |
| css-fields | completion-yas | 2.623 / 2.354 / 2.484 | 2.246 / 2.301 / 2.291 | 10.230 / 2.885 / 8.796 | 2.732 / 2.805 / 5.325 |
| tsx-style-six | command | 4.147 / 3.744 / 3.812 | 3.798 / 3.802 / 3.831 | 10.485 / 4.430 / 8.509 | 4.596 / 5.146 / 8.181 |
| tsx-style-six | completion | 6.019 / 5.531 / 5.636 | 5.022 / 5.001 / 5.060 | 32.423 / 6.835 / 31.380 | 13.350 / 12.617 / 12.658 |
| tsx-style-six | completion-yas | 6.404 / 5.901 / 5.982 | 5.373 / 5.358 / 5.404 | 16.396 / 31.918 / 31.496 | 7.716 / 8.438 / 32.073 |
| web-large-style-six | command | 27.599 / 27.367 / 27.455 | 27.324 / 27.098 / 27.322 | 63.523 / 61.154 / 61.817 | 61.414 / 59.535 / 62.892 |
| web-large-style-six | completion | 98.031 / 97.498 / 97.570 | 65.012 / 64.380 / 64.936 | 149.308 / 139.056 / 144.038 | 113.155 / 97.936 / 113.961 |
| web-large-style-six | completion-yas | 98.438 / 97.869 / 97.948 | 65.362 / 64.779 / 65.368 | 137.846 / 141.408 / 144.862 | 101.685 / 97.558 / 114.992 |

## Comparison cohort maxima and GC

These are inclusive total-operation values. GC seconds are summed over each
path's 1,000 measured samples, excluding warmup and between-sample work.

| Fixture | Path | Max ms | GC count | GC seconds |
| --- | --- | --- | --- | --- |
| web-list | command | 1.018 / 0.481 / 0.487 | 0 / 0 / 0 | 0.000000 / 0.000000 / 0.000000 |
| web-list | completion | 19.514 / 20.438 / 19.898 | 7 / 8 / 7 | 0.127220 / 0.147490 / 0.126633 |
| web-list | completion-yas | 19.877 / 20.462 / 20.024 | 6 / 6 / 6 | 0.107710 / 0.109848 / 0.107396 |
| web-card | command | 0.381 / 0.401 / 0.407 | 0 / 0 / 0 | 0.000000 / 0.000000 / 0.000000 |
| web-card | completion | 21.269 / 21.410 / 21.226 | 4 / 4 / 4 | 0.079356 / 0.080188 / 0.079497 |
| web-card | completion-yas | 21.241 / 20.941 / 20.827 | 5 / 5 / 5 | 0.096399 / 0.095356 / 0.097190 |
| tsx-list | command | 4.684 / 4.372 / 22.762 | 0 / 0 / 1 | 0.000000 / 0.000000 / 0.022197 |
| tsx-list | completion | 23.791 / 23.931 / 24.096 | 14 / 14 / 11 | 0.284760 / 0.290434 / 0.228758 |
| tsx-list | completion-yas | 44.891 / 25.209 / 26.684 | 14 / 14 / 16 | 0.308556 / 0.290917 / 0.337811 |
| css-one | command | 6.131 / 0.857 / 74.405 | 0 / 0 / 0 | 0.000000 / 0.000000 / 0.000000 |
| css-one | completion | 24.064 / 23.381 / 48.774 | 2 / 1 / 3 | 0.044967 / 0.022346 / 0.069217 |
| css-one | completion-yas | 24.862 / 24.458 / 25.709 | 3 / 3 / 1 | 0.069689 / 0.068206 / 0.024599 |
| css-six | command | 18.478 / 16.268 / 28.201 | 0 / 0 / 2 | 0.000000 / 0.000000 / 0.048693 |
| css-six | completion | 37.078 / 28.613 / 29.144 | 3 / 3 / 4 | 0.072211 / 0.071877 / 0.096662 |
| css-six | completion-yas | 29.456 / 30.010 / 29.692 | 7 / 8 / 4 | 0.168970 / 0.191656 / 0.097486 |
| css-fields | command | 8.973 / 2.229 / 10.535 | 0 / 0 / 0 | 0.000000 / 0.000000 / 0.000000 |
| css-fields | completion | 28.847 / 33.044 / 27.449 | 3 / 2 / 1 | 0.077398 / 0.055794 / 0.025468 |
| css-fields | completion-yas | 28.491 / 29.493 / 29.726 | 6 / 6 / 8 | 0.151067 / 0.152636 / 0.210298 |
| tsx-style-six | command | 30.985 / 16.351 / 31.711 | 1 / 0 / 2 | 0.027270 / 0.000000 / 0.053629 |
| tsx-style-six | completion | 38.229 / 72.856 / 49.761 | 8 / 9 / 1 | 0.217851 / 0.245208 / 0.026793 |
| tsx-style-six | completion-yas | 33.588 / 47.989 / 48.199 | 7 / 6 / 10 | 0.186659 / 0.163816 / 0.273057 |
| web-large-style-six | command | 262.806 / 89.837 / 72.734 | 70 / 70 / 73 | 2.180918 / 2.160658 / 2.333289 |
| web-large-style-six | completion | 339.599 / 149.621 / 157.995 | 72 / 72 / 70 | 2.289244 / 2.218361 / 2.308307 |
| web-large-style-six | completion-yas | 258.264 / 143.002 / 155.594 | 71 / 71 / 71 | 2.231479 / 2.191349 / 2.286379 |

## Comparison cohort warm stages

The command has only its total above. Completion stage summaries below retain
both the ordinary and yas paths; all stage GC triples remain in the raw JSON.

| Fixture | Path | Stage | p50 | p99 | Max |
| --- | --- | --- | --- | --- | --- |
| web-list | completion | request | 0.323 / 0.327 / 0.314 | 0.543 / 0.571 / 0.502 | 18.775 / 19.850 / 18.743 |
| web-list | completion | annotation | 0.114 / 0.116 / 0.112 | 0.163 / 0.169 / 0.155 | 17.873 / 17.714 / 18.325 |
| web-list | completion | documentation | 0.124 / 0.126 / 0.123 | 0.173 / 0.175 / 0.161 | 18.361 / 19.249 / 19.225 |
| web-list | completion | documentation-repeat | 0.107 / 0.109 / 0.107 | 0.144 / 0.154 / 0.146 | 18.896 / 19.059 / 17.441 |
| web-list | completion | accept | 0.037 / 0.038 / 0.036 | 0.064 / 0.069 / 0.060 | 0.118 / 0.098 / 0.105 |
| web-list | completion-yas | request | 0.317 / 0.326 / 0.310 | 0.540 / 0.555 / 0.475 | 8.053 / 0.683 / 0.589 |
| web-list | completion-yas | annotation | 0.111 / 0.114 / 0.111 | 0.166 / 0.171 / 0.146 | 18.243 / 17.936 / 18.305 |
| web-list | completion-yas | documentation | 0.117 / 0.119 / 0.116 | 0.176 / 0.171 / 0.158 | 0.364 / 0.208 / 0.208 |
| web-list | completion-yas | documentation-repeat | 0.106 / 0.107 / 0.106 | 0.154 / 0.151 / 0.139 | 18.839 / 19.312 / 19.036 |
| web-list | completion-yas | accept | 0.390 / 0.396 / 0.382 | 0.511 / 0.505 / 0.491 | 18.274 / 18.784 / 17.863 |
| web-card | completion | request | 0.280 / 0.284 / 0.282 | 0.440 / 0.451 / 0.440 | 19.395 / 19.492 / 19.475 |
| web-card | completion | annotation | 0.108 / 0.110 / 0.109 | 0.148 / 0.157 / 0.147 | 20.030 / 20.402 / 20.664 |
| web-card | completion | documentation | 0.089 / 0.090 / 0.090 | 0.120 / 0.126 / 0.124 | 20.726 / 20.822 / 20.306 |
| web-card | completion | documentation-repeat | 0.075 / 0.076 / 0.076 | 0.096 / 0.104 / 0.098 | 0.123 / 0.154 / 0.123 |
| web-card | completion | accept | 0.036 / 0.036 / 0.036 | 0.060 / 0.069 / 0.064 | 0.108 / 0.087 / 0.104 |
| web-card | completion-yas | request | 0.275 / 0.279 / 0.279 | 0.427 / 0.471 / 0.460 | 0.803 / 0.651 / 0.675 |
| web-card | completion-yas | annotation | 0.105 / 0.107 / 0.106 | 0.152 / 0.154 / 0.146 | 18.766 / 19.043 / 19.082 |
| web-card | completion-yas | documentation | 0.082 / 0.083 / 0.083 | 0.125 / 0.126 / 0.122 | 20.223 / 19.950 / 19.827 |
| web-card | completion-yas | documentation-repeat | 0.075 / 0.076 / 0.075 | 0.108 / 0.099 / 0.096 | 0.223 / 0.152 / 0.181 |
| web-card | completion-yas | accept | 0.351 / 0.356 / 0.349 | 0.453 / 0.447 / 0.447 | 19.337 / 19.474 / 20.155 |
| tsx-list | completion | request | 0.647 / 0.634 / 0.638 | 1.170 / 0.986 / 1.052 | 22.126 / 22.361 / 21.929 |
| tsx-list | completion | annotation | 0.202 / 0.202 / 0.200 | 0.290 / 0.267 / 0.287 | 0.718 / 0.338 / 21.322 |
| tsx-list | completion | documentation | 0.504 / 0.504 / 0.504 | 0.665 / 0.606 / 0.624 | 22.197 / 22.300 / 22.466 |
| tsx-list | completion | documentation-repeat | 0.483 / 0.487 / 0.488 | 1.014 / 0.660 / 0.615 | 21.153 / 22.051 / 21.410 |
| tsx-list | completion | accept | 0.070 / 0.070 / 0.071 | 0.142 / 0.122 / 0.120 | 0.692 / 0.226 / 0.238 |
| tsx-list | completion-yas | request | 0.651 / 0.650 / 0.641 | 1.019 / 0.982 / 0.974 | 21.665 / 21.879 / 21.502 |
| tsx-list | completion-yas | annotation | 0.199 / 0.200 / 0.198 | 0.302 / 0.286 / 0.273 | 22.060 / 22.719 / 0.491 |
| tsx-list | completion-yas | documentation | 0.498 / 0.500 / 0.500 | 0.786 / 0.661 / 1.250 | 41.076 / 21.990 / 24.673 |
| tsx-list | completion-yas | documentation-repeat | 0.482 / 0.486 / 0.487 | 0.640 / 0.628 / 0.614 | 21.205 / 21.805 / 22.155 |
| tsx-list | completion-yas | accept | 0.490 / 0.489 / 0.488 | 0.683 / 0.623 / 0.710 | 21.113 / 21.557 / 22.108 |
| css-one | completion | request | 0.655 / 0.619 / 0.668 | 1.024 / 0.798 / 3.486 | 23.763 / 23.021 / 48.050 |
| css-one | completion | annotation | 0.090 / 0.086 / 0.092 | 0.166 / 0.126 / 0.305 | 1.019 / 0.177 / 22.779 |
| css-one | completion | documentation | 0.077 / 0.074 / 0.078 | 0.121 / 0.100 / 0.163 | 0.545 / 0.129 / 1.322 |
| css-one | completion | documentation-repeat | 0.034 / 0.033 / 0.034 | 0.062 / 0.056 / 0.093 | 0.188 / 0.076 / 1.998 |
| css-one | completion | accept | 0.039 / 0.037 / 0.042 | 0.118 / 0.075 / 0.166 | 0.297 / 0.111 / 0.677 |
| css-one | completion-yas | request | 0.658 / 0.624 / 0.671 | 1.051 / 0.800 / 4.196 | 23.104 / 22.652 / 25.393 |
| css-one | completion-yas | annotation | 0.088 / 0.085 / 0.090 | 0.158 / 0.116 / 0.335 | 23.785 / 23.011 / 2.656 |
| css-one | completion-yas | documentation | 0.075 / 0.073 / 0.077 | 0.118 / 0.100 / 0.253 | 0.408 / 0.122 / 1.739 |
| css-one | completion-yas | documentation-repeat | 0.034 / 0.034 / 0.034 | 0.071 / 0.046 / 0.093 | 0.423 / 0.077 / 0.358 |
| css-one | completion-yas | accept | 0.039 / 0.037 / 0.041 | 0.111 / 0.086 / 0.213 | 23.796 / 23.492 / 1.011 |
| css-six | completion | request | 3.551 / 3.552 / 3.540 | 4.687 / 4.357 / 4.063 | 36.598 / 7.396 / 28.607 |
| css-six | completion | annotation | 0.137 / 0.136 / 0.134 | 0.211 / 0.181 / 0.186 | 24.760 / 24.540 / 0.370 |
| css-six | completion | documentation | 0.156 / 0.157 / 0.155 | 0.206 / 0.198 / 0.199 | 0.278 / 0.234 / 25.185 |
| css-six | completion | documentation-repeat | 0.092 / 0.093 / 0.092 | 0.125 / 0.129 / 0.128 | 0.207 / 0.164 / 0.228 |
| css-six | completion | accept | 0.055 / 0.055 / 0.054 | 0.100 / 0.096 / 0.103 | 0.448 / 0.134 / 0.169 |
| css-six | completion-yas | request | 3.562 / 3.562 / 3.528 | 4.748 / 4.549 / 4.195 | 28.638 / 29.082 / 28.123 |
| css-six | completion-yas | annotation | 0.134 / 0.133 / 0.132 | 0.182 / 0.190 / 0.182 | 2.769 / 0.513 / 25.220 |
| css-six | completion-yas | documentation | 0.155 / 0.155 / 0.154 | 0.201 / 0.197 / 0.198 | 0.277 / 0.358 / 0.503 |
| css-six | completion-yas | documentation-repeat | 0.092 / 0.093 / 0.093 | 0.125 / 0.126 / 0.125 | 0.203 / 0.218 / 0.239 |
| css-six | completion-yas | accept | 0.384 / 0.387 / 0.384 | 0.501 / 0.515 / 0.496 | 25.235 / 24.650 / 24.940 |
| css-fields | completion | request | 1.585 / 1.625 / 1.620 | 1.937 / 1.973 / 2.202 | 28.486 / 32.673 / 27.063 |
| css-fields | completion | annotation | 0.105 / 0.107 / 0.107 | 0.150 / 0.153 / 0.147 | 0.438 / 25.245 / 0.476 |
| css-fields | completion | documentation | 0.096 / 0.098 / 0.098 | 0.123 / 0.128 / 0.130 | 0.194 / 0.173 / 0.231 |
| css-fields | completion | documentation-repeat | 0.047 / 0.047 / 0.047 | 0.062 / 0.063 / 0.071 | 25.418 / 0.088 / 0.122 |
| css-fields | completion | accept | 0.042 / 0.044 / 0.044 | 0.085 / 0.087 / 0.095 | 0.096 / 0.123 / 0.161 |
| css-fields | completion-yas | request | 1.583 / 1.620 / 1.615 | 1.900 / 1.964 / 2.303 | 26.806 / 27.461 / 29.015 |
| css-fields | completion-yas | annotation | 0.102 / 0.104 / 0.104 | 0.141 / 0.150 / 0.151 | 0.344 / 25.319 / 26.637 |
| css-fields | completion-yas | documentation | 0.094 / 0.096 / 0.097 | 0.124 / 0.132 / 0.129 | 25.122 / 0.208 / 0.186 |
| css-fields | completion-yas | documentation-repeat | 0.047 / 0.048 / 0.047 | 0.072 / 0.068 / 0.075 | 0.140 / 0.107 / 26.227 |
| css-fields | completion-yas | accept | 0.385 / 0.396 / 0.393 | 0.498 / 0.518 / 0.524 | 26.564 / 27.416 / 27.235 |
| tsx-style-six | completion | request | 4.278 / 4.258 / 4.305 | 6.016 / 5.934 / 10.830 | 32.595 / 71.379 / 47.837 |
| tsx-style-six | completion | annotation | 0.284 / 0.286 / 0.289 | 0.374 / 0.405 / 0.486 | 31.927 / 27.949 / 1.276 |
| tsx-style-six | completion | documentation | 0.172 / 0.172 / 0.176 | 0.230 / 0.227 / 0.259 | 0.295 / 2.093 / 1.669 |
| tsx-style-six | completion | documentation-repeat | 0.141 / 0.142 / 0.143 | 0.193 / 0.222 / 0.235 | 0.331 / 27.687 / 26.967 |
| tsx-style-six | completion | accept | 0.101 / 0.101 / 0.105 | 0.146 / 0.177 / 0.176 | 0.458 / 0.479 / 1.432 |
| tsx-style-six | completion-yas | request | 4.298 / 4.273 / 4.312 | 5.221 / 5.984 / 11.942 | 31.440 / 31.723 / 40.880 |
| tsx-style-six | completion-yas | annotation | 0.283 / 0.283 / 0.286 | 0.394 / 0.390 / 0.533 | 27.424 / 27.656 / 28.259 |
| tsx-style-six | completion-yas | documentation | 0.171 / 0.170 / 0.173 | 0.224 / 0.336 / 0.250 | 0.308 / 26.377 / 0.616 |
| tsx-style-six | completion-yas | documentation-repeat | 0.141 / 0.142 / 0.143 | 0.202 / 0.227 / 0.208 | 0.278 / 0.582 / 0.444 |
| tsx-style-six | completion-yas | accept | 0.439 / 0.442 / 0.447 | 0.562 / 0.679 / 0.626 | 28.330 / 31.035 / 28.460 |
| web-large-style-six | completion | request | 48.242 / 47.780 / 48.223 | 87.567 / 80.774 / 91.183 | 317.334 / 83.552 / 137.505 |
| web-large-style-six | completion | annotation | 9.386 / 9.304 / 9.388 | 16.503 / 10.488 / 12.308 | 50.511 / 38.601 / 44.666 |
| web-large-style-six | completion | documentation | 2.496 / 2.468 / 2.498 | 4.644 / 2.825 / 3.000 | 11.518 / 49.873 / 7.363 |
| web-large-style-six | completion | documentation-repeat | 2.471 / 2.400 / 2.471 | 3.596 / 2.894 / 3.027 | 17.753 / 8.967 / 9.148 |
| web-large-style-six | completion | accept | 2.360 / 2.341 / 2.353 | 2.926 / 2.662 / 3.279 | 6.788 / 4.273 / 35.756 |
| web-large-style-six | completion-yas | request | 48.220 / 47.831 / 48.253 | 83.139 / 80.306 / 88.582 | 185.589 / 125.273 / 131.974 |
| web-large-style-six | completion-yas | annotation | 9.397 / 9.306 / 9.373 | 13.545 / 10.226 / 15.429 | 26.951 / 17.734 / 46.921 |
| web-large-style-six | completion-yas | documentation | 2.489 / 2.476 / 2.495 | 3.182 / 2.857 / 3.429 | 18.144 / 7.867 / 4.797 |
| web-large-style-six | completion-yas | documentation-repeat | 2.471 / 2.413 / 2.461 | 3.043 / 2.749 / 3.702 | 10.257 / 6.803 / 37.375 |
| web-large-style-six | completion-yas | accept | 2.720 / 2.702 / 2.719 | 3.452 / 2.967 / 3.675 | 17.317 / 8.100 / 21.409 |

## Comparison cohort cold totals

Mode initialization and context preparation are separate. Command and
completion restart Node independently; cold completion creates its first
preview. Yas follows with warm Node/preview. Package/dependency loading precedes
timing; loaded Lisp/mode features can remain warm between fixtures. These
values do not measure total Emacs or package startup. Cold GC and nested
stages are in the raw JSON.

| Fixture | Mode initialization | Context preparation | Command | Completion | Completion with yas |
| --- | --- | --- | --- | --- | --- |
| web-list | 0.555 / 0.513 / 0.488 | 0.128 / 0.057 / 0.059 | 59.188 / 55.151 / 52.061 | 56.645 / 58.617 / 55.429 | 2.027 / 1.796 / 1.690 |
| web-card | 0.497 / 0.498 / 0.513 | 0.016 / 0.020 / 0.032 | 49.429 / 50.190 / 48.741 | 51.369 / 51.649 / 50.959 | 1.505 / 1.446 / 1.447 |
| tsx-list | 69.222 / 65.739 / 63.530 | 11.175 / 11.173 / 10.799 | 50.793 / 51.808 / 54.058 | 55.285 / 52.243 / 52.265 | 3.243 / 3.321 / 3.098 |
| css-one | 0.028 / 0.025 / 0.066 | 0.004 / 0.004 / 0.006 | 59.315 / 57.085 / 99.069 | 54.913 / 55.179 / 54.064 | 2.905 / 2.134 / 2.503 |
| css-six | 0.025 / 0.023 / 0.034 | 0.002 / 0.001 / 0.003 | 62.095 / 58.510 / 61.896 | 60.133 / 60.993 / 62.244 | 6.731 / 6.207 / 6.491 |
| css-fields | 0.027 / 0.023 / 0.028 | 0.002 / 0.001 / 0.003 | 59.087 / 61.024 / 52.699 | 53.740 / 53.958 / 55.035 | 4.123 / 4.168 / 4.141 |
| tsx-style-six | 11.774 / 11.524 / 11.798 | 2.811 / 2.614 / 2.771 | 60.119 / 63.291 / 68.083 | 60.794 / 60.906 / 63.469 | 7.579 / 6.946 / 7.210 |
| web-large-style-six | 0.605 / 0.525 / 0.578 | 16.136 / 16.324 / 15.947 | 67.763 / 72.644 / 61.945 | 150.393 / 150.217 / 149.438 | 66.698 / 84.163 / 66.122 |

## Reproducibility and evidence limits

The six raw JSON files retain every warmup, sample, stage, GC delta, cold
operation, source/fixture hash, compiler configuration and environment value.
An independent Python pass recomputed every count, p50, p99, max and GC sum;
all matched, and input/output hashes matched across all six processes. Only
the capf runtime source differs between cohorts; the harness is identical.

- `emmet2-capf.el` before: `24801aa6b69ee2ed294d7b828368ab4523bdd23691e74423555880426326b966`; after: `d55fbbe9c82f8d1e9d592469853625786dc0ba94c296d0a8fa91de19eba005f4`.
- `test/bench-completion.el`: `c01dbdacce640ae0139b37dec4e4aebf3fc5aa19802af704f6860e8488f61b57`.
- `test/dependencies.json`: `8e8bd5bf9f88b66d85d6815d6c1c4cf6e5eeed956342803a5cf52c9c702aabc0`.

Raw files are retained as gzip in the ignored local directory
`plans/native-emmet-rewrite/measurements/2026-09-27/`. SHA256 values below
refer to uncompressed JSON, not its compressed container:

- `emmet2-flow-complete31-1.json`: `2f7da39b2d1ef29ad3e9a69326ddc66fef7acaccbbc9a943b3a76c102ffdda51`.
- `emmet2-flow-complete31-2.json`: `cf2e61a55e119b02aadcf5f91ef94f61343d627be968ad6ab2190708c2ff1f75`.
- `emmet2-flow-complete31-3.json`: `f8121446154c2ef40342813c292455e212218552a9554c2e5a45299677aa0b4e`.
- `emmet2-flow-optimized31-1.json`: `b3bb4e2d88bf3210e4a5de56c0b3458c1f02dcc6d0f5e94e0dd6c6fc7fe94e35`.
- `emmet2-flow-optimized31-2.json`: `976d75af3f6e6a6ffdf2428fec7be7c6f362c43c089834139ca82276d2a336ae`.
- `emmet2-flow-optimized31-3.json`: `43be87fc13cff4110d56d4b3c35a7cef12135efb58a0f1c6488e0fcde995a829`.

Correctness validation: both pinned Emacs 30.2 and 31.1 passed all 24
source completion/preview tests, 48 compiled editor tests, and project
compilation with warnings fatal. Existing optional-package warnings are
separate from project warnings. GUI painting, idle interaction with Eglot,
and hosted Linux CI remain unverified; M1 stays open. The current Node
backend and conservative large-style scan remain real costs. No whole-editor
latency or native-engine budget claim follows from these batch measurements.

## Primary-review check of the single-property tail

The third full comparison process has a 74.405 ms direct-command sample with
zero Emacs GC, alongside elevated completion tails. The command does not call
capf, so its delay cannot be attributed to the removed cached-result check.
The cause of the delay is not established. An additional diagnostic alternated
baseline/comparison order (A/B, B/A, A/B), with three fresh processes per cohort,
the unchanged runner and only `css-one` selected. The baseline used a detached
`4471f71` worktree plus the same harness; it was removed after measurement.
These filtered 18,000 operations supplement rather than replace either full
cohort. Medians improve consistently; p99 does not degrade consistently.
No sample is excluded and no universal tail-latency guarantee is made.

| Path | Baseline p50 | Comparison p50 | Baseline p99 | Comparison p99 |
| --- | --- | --- | --- | --- |
| command | 0.514 / 0.512 / 0.512 | 0.518 / 0.517 / 0.514 | 0.673 / 0.716 / 0.691 | 0.898 / 0.678 / 0.680 |
| completion | 0.941 / 0.945 / 0.948 | 0.880 / 0.876 / 0.873 | 1.198 / 1.213 / 1.193 | 1.972 / 1.091 / 1.167 |
| completion-yas | 0.946 / 0.944 / 0.949 | 0.877 / 0.876 / 0.878 | 1.189 / 1.256 / 1.174 | 1.678 / 1.092 / 1.176 |

Raw files share the archive directory above; uncompressed SHA256:

- `emmet2-css-control-baseline-1.json`: `ccbf8906da64bc002ad6bb88cef33d18b32ef5d084efad9ffa6a44c0694a73d0`.
- `emmet2-css-control-baseline-2.json`: `83a63172afe9c2905e35d20a7ae96f8ccfa689612bdeca8ac498fb08c02413d9`.
- `emmet2-css-control-baseline-3.json`: `058dc24bf7b8621a9a8dfb24b08fe5080809cf0a5b00d750ac80f5436577eb66`.
- `emmet2-css-control-optimized-1.json`: `09466a9af06b1d49b8da6884d06031d4cd6fa4f1ad4207c60c7ffa7beb4b4e55`.
- `emmet2-css-control-optimized-2.json`: `37dc79e4bbe3a421f226440f95149642f8218e5b9c83c580b8f0fc9086eb27b5`.
- `emmet2-css-control-optimized-3.json`: `4827d3ddb68f4d122edcd5c68987fbb2154c8960a07379e0ba408ee396d5ad8b`.
