# CSS value completion, 2026-10-01

This report records the earlier implementation. Its function snippet behavior
has since been replaced: semantic completion only inserts the candidate and
places point inside empty parentheses. `scss2-mode` / `css2-mode` now own TAB
navigation and request declaration insertion without YAS fields. The archived
tests and hashes below remain evidence for the earlier snapshot only.

`display: if` now offers `inline-flex` in CSS Base hosts with Emmet2 enabled.
Accepting `calc()` places point inside the parentheses; optional yasnippet fields
let TAB leave the function. Existing call arguments and one-step acceptance undo
are preserved. The change spans the local emmet2-mode and scss2-mode checkouts.

## Diagnosis and ownership

Actual CAPF probes reproduced no `if` candidates in `css-mode` and `scss-mode`.
Their native provider used prefix matching. Both `css2-mode` and `scss2-mode`
already matched `inline-flex` through their shared semantic completion module.
Neither path supplied function fields. Both new Corfu regressions failed before
the implementation changed.

The existing spelling-aware style moved from `scss2-completion` into
`emmet2-completion`. Both hosts now call `emmet2-completion-capf`, using
`emmet2-css-data-query` and the same fuzzy matcher. SCSS retains ownership of
its scope, symbols and escape/Sass name identity. Its public `scss2` category
and style remain available, including user overrides.

CSS Base's small value adapter obtains bounds from `emmet2-context-css-value`;
the Tree-sitter modes retain their own context classifier. These are intentionally
different syntax authorities. The native adapter declines external-provider
buffers, and scss2 removes overlapping hooks. No matcher, field inserter, parser,
cache or second candidate catalog was copied into another host.

Function acceptance delegates to `emmet2-insert`, using its optional `continuing`
argument to join the frontend's undo group. Without yasnippet, point still enters
the parentheses. The existing-call case offers the function name without adding
another pair of parentheses. The previous host test expecting `calc()` beside an
existing call was updated to this intentional insertion behavior.

## Validation

| Check | Emacs 30.2 | Emacs 31.1 |
| --- | ---: | ---: |
| Complete Emmet source integration | 423 passed | 423 passed |
| Isolated bytecode editor suite | 188 passed | 188 passed |
| Actual isolated straight installation | 108 passed | 108 passed |
| Complete scss2 host suite | 222 passed | 222 passed |
| Real Corfu/YAS host integration | 6 passed | 6 passed |

Thirteen changed libraries and runners also passed independent warning-as-error
byte compilation on Emacs 31. The pinned Corfu dependency retains its existing
obsolete-macro warning. The isolated scss2 semantic boundary suite passed 3 tests.

Coverage includes `css-mode`, `scss-mode`, `css-ts-mode`, both Tree-sitter host
modes, candidate equivalence, token bounds without colon whitespace, comments,
strings, literals, nested rule boundaries, existing arguments, cancelled/stale
acceptance callbacks, optional YAS, single undo, and nested declaration/function
fields. Nested YAS tests execute post-command hooks, as the real command loop does.

The Corfu code is real, but popup drawing is stubbed; GUI observations remain
pending. This change did not rerun the earlier performance matrix. Its frozen
snapshot results are not evidence for the new value path. The earlier isolated
GUI window also contains the previous build; reload the updated packages before
manually checking these changes.

Both repositories' pre-existing staged changes were preserved byte for byte.
Nothing was staged, committed or pushed in either working repository. The
installation test uses a separate, locally committed source snapshot.

Logs, reproduction scripts, source snapshots and hashes are archived in
[plans/value-completion-2026-10-01](../plans/value-completion-2026-10-01/README.md).
