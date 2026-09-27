# Manual functional GUI acceptance — 2026-09-27

**Result: PASS for the agreed Emacs 31.1 functional GUI checklist.**

The user performed the actual GUI interactions and explicitly confirmed each
group in the conversation, including all remaining Corfu combinations and the
last three edge cases. These are user-reported observations. The assistant did
not observe screenshots or control Emacs successfully: Computer Use returned
`timeoutReached (-10005)` even after restarting the desktop host, while the
Finder control read succeeded. The cause of the Emacs access failure is unknown.

## Environment and sequence

- Target implementation: `220a6a6cd2a6459ed43e4d05b54c760618ddcd09`.
- Main checks: real macOS Emacs 31.1 GUI, isolated `-Q` configuration, actual
  straight-installed native bytecode for that commit, and locked optional test
  dependencies/grammars from `test/dependencies.json`.
- Eglot checks: a real local TypeScript 7.0.2 language server, with Emmet and
  Eglot both registered as completion providers in a TSX file.
- At the user's request, the final three checks used the daily Emacs/Evil
  configuration loading the same local checkout, with yasnippet and Corfu
  popupinfo enabled. Solid options came from the fixture's `.dir-locals.el`.
- Local batch configuration checks verified mode hooks, Evil insert-state
  `C-j`, the loaded source path and directory-local options. They are setup
  evidence, separate from the user's GUI confirmations.

## Confirmed interactions

| Area | Input or action | User-confirmed result |
| --- | --- | --- |
| HTML completion | `ul>li*3`, automatic candidate/preview, select and accept | Three `li` elements; one undo restores the abbreviation |
| CSS fields | `c+bg`, enter `red`, TAB, enter `blue`, TAB | Independent values; exit at expansion end; host brace preserved |
| Session invalidation | Cancel, edit `.card` to `.panel`, switch buffers | No obsolete expansion or annotation inserted |
| JSX options | `.card.active` | Preview and inserted CSS-module/class-constructor markup agree |
| CSS-in-JS | `style={{m10+p.5}}` versus `other={{m10+p.5}}` | Style expands to margin/padding; other attribute is rejected unchanged |
| Real Eglot coexistence | `{items.ma}`, `Hello{items.ma}`, JSX `.card` | Expressions offer/accept `map`; JSX text still offers/accepts Emmet |
| Prompt preselection | RET on prompt versus explicit candidate selection | Prompt does not expand; selected candidate does |
| Partial-first completion | Exact-match `nil` versus `show` | Automatic skip/direct manual expansion versus visible candidate and acceptance |
| Automatic prefix | Prefix 3 with `m1` | No automatic popup; manual Emmet completion inserts `margin: 1px;` |
| Remaining Corfu matrix | 13 remaining styles/exact-match cases, both manual commands | Expected popup or direct expansion; all confirmed by user |
| Matrix session safety | Selected candidate then typing, deletion, movement, cancellation, buffer switch | No stale result inserted in the requested popup cases |
| Without yasnippet | `c+bg`, expand, undo | Same text/initial point; one undo restores source |
| Mirrors | `.card>span{${1:😀} ${1:😀}}`, edit first field to `hello` | Both fields become `hello`; TAB exits without an extra layout change |
| Mid-abbreviation point | Inside `ul>li*3`, direct command and Emmet completion | Both expand the entire abbreviation and retain host tags |
| EOF field exit | Bare `a` at EOF, fill href, TAB through fields | Point ends after final `>`; no extra newline |
| Directory-local Solid options | `.card.active`, Solid + `styles` + `cx` | Preview and insertion are `<div class={cx(styles.card, styles.active)}></div>` |

The configuration matrix used basic-first, partial-first, partial-only and an
`emmet2` category partial-completion override with `nil`, `show`, `insert` and
`quit` exact-match settings. The remaining 13-case helper only prepared settings
and empty buffers; advancing it did not run interactions or record passes. The
user's explicit confirmation is the evidence for those cases.

## Acceptance boundary

No functional GUI checklist items remain pending after the user's final
confirmation. This closes the manual functional GUI gate for this implementation.
It does not establish automated GUI coverage, Emacs 30 GUI behavior, measured
input/painting latency, or a performance improvement. Existing automated,
installation and performance reports retain their own version and scope.

The earlier Eglot setup probe warned about unsupported
`workspace/didChangeConfiguration`; batch shutdown required process cleanup.
The subsequent real GUI coexistence checks were confirmed successful. This
acceptance does not claim general language-server lifecycle coverage.
