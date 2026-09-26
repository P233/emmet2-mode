# Development and native rewrite

The installed mode still uses the original Deno bridge. The native rewrite is
in progress; vendoring data does not switch the runtime or change user behavior.
Do not use the new design as evidence that a milestone has shipped.

## Baseline and migration

The starting revision is `3f9ddc6`. On 2026-09-26, Deno 2.9.7 passed all existing
tasks: 93 CSS, 19 markup and 70 regex cases. These tasks intentionally use the
existing `--no-check` setting; this is test evidence, not a type-check claim.

```sh
rtk proxy deno task test:css
rtk proxy deno task test:markup
rtk proxy deno task test:regex
```

`test/fixtures/migration.json` maps every baseline test by source, ordinal ID,
name and line. Duplicate test names are separate cases. `tests: []` means no
replacement has passed yet. Fill it with concrete new test IDs only after
running those tests. Preserve the baseline identity when the old files retire.
The integration and intentional-change lists cover contracts that the 182
pure-function tests cannot establish, including README examples, host modes,
project options, insertion, packaging and resource lifetimes.

Do not turn the regex suite into a core expansion oracle. Migrate its extraction
and extension behavior to the layer that owns it. Record intentional behavior
changes explicitly; do not silently change expected output or count skipped
tests as migrated coverage.

## Ownership and contracts

- `emmet2-context` owns host classification and source-buffer parser lifetimes;
  `emmet2-extract` alone computes abbreviation bounds.
- The pure engine returns text, positive editable-field groups and an initial
  cursor, using zero-based character offsets and half-open field intervals.
  It never reads or writes an editor buffer.
- Markup preserves real mirror groups. CSS fields belong to one parsed property;
  identical upstream numbers in different properties are independent. Upstream
  zero is an editable field, not the final snippet exit.
- Extensions own opinionated syntax and all transformations of text and fields,
  including removal of CSS defaults. No later layer repeats this cleanup.
- `emmet2-insert` is the only active source-text writer. It checks source/range/
  content, inserts atomically, encodes literal snippet text safely and creates
  the final yas exit at the end. Without yas, it uses the same initial cursor.
- Completion candidates contain the original abbreviation; annotation and docs
  contain the expansion. Only a valid `finished` callback expands. The selected
  custom try semantics can bypass Corfu's exact insert/quit policies; test the
  effective styles/category settings instead of guessing from `basic` membership.
  Do not mutate the user's completion settings or add label-recovery state.

The Node backend is temporary: one process and one request, with a deadline for
the whole expansion. Cancellation before a complete response destroys that
process. S7 must prove the complete Elisp backend before Node runtime files and
their protocol tests are retired. The offline development oracle may still use
Node after the package runtime becomes pure Elisp.

## Data and test authority

`vendor/emmet-source.json` pins the npm 2.4.11 archive and matching source commit.
The archive integrity was verified before extraction. The bundle and JSON files
are copied verbatim, never formatted or edited. In particular, the earlier
research checkout was newer than the published package; it is not the oracle.
The pinned raw files contain 155 HTML snippets, 249 CSS snippets and 5 variables.
Aliases can produce a different number of resolved keys.

The vendor directory is excluded from Deno lint because it is unmodified
third-party generated code. Hand-authored source and tooling remain checked.
Use a separate explicit upgrade to change vendor versions, checksums or fixtures.

The upcoming S0 checks must run without network or node_modules. Hand-written
field, Unicode and error assertions must pass before generated golden results
are accepted. The core oracle, extension behavior and editor integration are
separate suites; no shared adapter may serve as its own only correctness proof.

## Review and milestones

For each independently validated slice:

1. Inspect the complete uncommitted implementation with `mode=primary`, fix
   confirmed issues, perform its residual scan and follow up as required.
2. Run the read-only final review. Commit only the reviewed implementation with
   normal hooks; preserve unrelated working-tree changes. Do not push.
3. After the commit, re-evaluate the next slice against the actual contracts,
   measurements and remaining risks. Update the execution plan before proceeding.

S0 establishes the pinned oracle and context/completion probes. S1 adds the
temporary Node API; S2 the extensions; S3 host analysis; S4 insertion and the
runtime switch; S5 completion, preview and actual M1 installation. S6/S7 supply
and validate the native engines before M2. S8 retires temporary runtime and test
entry points and verifies the final installed package.

MCP gaps must remain explicit. Wallaby returned no data for the three legacy
test files during baseline capture; the repository Deno tasks supplied evidence.
Emacs 31.1 and Node 24.21.0 are available locally. Emacs 30, clean CI, GUI flows,
installed-package checks and native performance are not yet validated.
ESLint MCP has no configuration in this Deno repository. A scoped Deno lint
check of unchanged `src/index.ts` reports the existing inline-URL import under
Deno 2.9.7's `no-import-prefix` rule. Do not weaken that rule or rewrite the old
bridge merely to admit the vendored data; migrate its runtime in S4/S8.

Performance checks use fixed inputs, bytecode, normal GC, at least 100 warmups
and 1,000 samples per group, repeated three times. Report cold time, p50/p99/max
and GC costs. Do not put machine-specific timing assertions in ERT or infer
whole-flow performance from parser or matching microbenchmarks.
