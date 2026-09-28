# emmet2-mode

[Emmet](https://emmet.io/) for Emacs.

Starting with **V2**, emmet2-mode is implemented natively in Emacs Lisp and no
longer calls the Emmet npm package. Requires **Emacs 30+**; no Node, Deno or other
external runtime is needed.

- Expand HTML, JSX, Solid, CSS and SCSS from anywhere inside an abbreviation.
- Context-aware CSS expansion in style attributes, style blocks and JSX style objects.
- CSS Modules and configurable class-name helpers for JSX.
- Completion-at-point with an expansion summary and optional colored Corfu preview.
- Editable fields and mirrors with yasnippet; one undo restores the abbreviation.
- CSS extensions: custom properties, raw values, SCSS at-rules and pseudo-selectors.

## Install

With straight.el and use-package:

```elisp
(use-package emmet2-mode
  :straight (:type git :host github :repo "p233/emmet2-mode"
             :files (:defaults "data"))
  :hook ((web-mode css-mode tsx-ts-mode js-ts-mode) . emmet2-mode))
```

Keep the bundled `data/` directory. Restart Emacs when upgrading from an older
Node/Deno version. JS/TS/JSX support requires the matching tree-sitter grammar;
CSS/SCSS and web-mode HTML/CSS do not.

## Use

Press **`C-j`** to expand, or **`M-x emmet2-complete`** for Emmet-only completion.
Point can be at the start, middle or end of the abbreviation; the whole
abbreviation is replaced. Use `C-j` for bare names such as `div`, `c` or `bg`.
Completion offers more distinctive abbreviations, leaving ordinary JavaScript
expressions and bare names to other providers such as Eglot.

| Context | Abbreviation | Result |
| --- | --- | --- |
| HTML | `ul>li*3` | A list with three items |
| JSX | `.card.active` | `<div className={clsx(styles.card, styles.active)}></div>` |
| CSS | `m10,p.5` or `m10+p.5` | `margin: 10px; padding: 0.5rem;` |
| CSS | `m--gutter` | `margin: var(--gutter);` |
| CSS | `p1-2` or `p[1px 2px]` | `padding: 1px 2px;` |
| JSX style object | `m10,p.5` or `m10+p.5` | `margin: 10, padding: "0.5rem"` |

Use `,` or `+` between CSS properties without spaces. Use `[...]` for literal
values and functions; commas and plus signs inside brackets stay unchanged.

CSS context is detected inside `<style>` blocks and `style=""` attributes.
JSX `style={{...}}` and objects passed to `StyleSheet.create(...)` or
`createTheme(...)` use CSS-in-JS output: camelCase property names, numeric pixel
values and quoted strings for other units. Ordinary comments, strings and
unrelated JavaScript expressions are excluded. In unsupported major modes,
`C-j` still offers plain markup expansion, including in buffers without a file.

To use a different expansion key:

```elisp
(with-eval-after-load 'emmet2-mode
  (keymap-unset emmet2-mode-map "C-j")
  (keymap-set emmet2-mode-map "C-c C-." #'emmet2-expand))
```

## Completion and snippets

These companions are optional; **`C-j`** works without them:

- [Corfu](https://github.com/minad/corfu) displays completion candidates.
- **`corfu-popupinfo-mode`**, included with Corfu, shows the full, syntax-highlighted expansion.
- [yasnippet](https://github.com/joaotavora/yasnippet) adds **TAB** navigation between fields and synchronized mirrors.

Add these settings to your existing setup, or use:

```elisp
(use-package corfu
  :straight t
  :hook ((web-mode css-mode tsx-ts-mode js-ts-mode) . corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-on-exact-match 'show)
  :config
  (corfu-popupinfo-mode 1))

(use-package yasnippet
  :straight t
  :hook ((web-mode css-mode tsx-ts-mode js-ts-mode) . yas-minor-mode))
```

Candidate rows show expansion text, without repeating the abbreviation or a
provider label. CSS prefixes offer matching snippet and keyword choices; for
example, `ta` includes:

```text
text-align: ;
text-align: left;
text-align: center;
text-align: right;
text-align: justify;
```

Menu rows fold line breaks and indentation into spaces, without package
truncation. Single-line results appear in the list only. Multiline results also
provide a complete popupinfo panel, even when the current fragment alone is one
line. The panel starts at column zero: ordinary CSS properties align left,
while HTML/JSX and nested CSS retain their relative
indentation. Leading tabs use the source buffer's width. These display changes
preserve the actual insertion text and editable fields.
Matching word characters are highlighted when the abbreviation corresponds to a
literal subsequence of the expansion. Aliases without such a correspondence stay
unhighlighted. The frontend still controls how much text fits on screen.

Typing or deleting within a valid abbreviation updates the existing completion
session without closing and reopening the list. In CSS declarations, a trailing
comma keeps the preceding choices visible while waiting for the next property.
For `ovh,ta`, the list shows only the text-alignment choices, prefixed with `…`
to indicate the omitted overflow property. The preview and insertion retain the
complete expansion, including that property. A `+` inside
the current fragment still displays all of that fragment's properties. Accepting
while the comma is pending inserts the selected expansion and consumes that comma.
`C-j` still reports an incomplete abbreviation until the next property is supplied.
The menu label and complete preview are prepared once per candidate and reused
for display requests; no formatter or expansion runs again on hover.

Corfu preserves distinct choices for the same typed abbreviation. Frontends that
discard candidate properties or merge identical candidate strings may offer only
the default expansion.

Popup timing is a personal Corfu setting. For example, `corfu-auto-delay` of `0.08`
shortens the wait for candidates, and `corfu-popupinfo-delay` of `'(0 . 0)` removes
the initial and subsequent documentation delay. Scope these settings to your web
editing buffers if other modes should retain their defaults; other completion
providers in the same buffer also use them. Emmet does not set these values.
Set `corfu-auto-prefix` to `1` to see choices after a single CSS letter such as
`m`; `corfu-count` controls visible rows, not the total number of candidates.
Popup width and positioning also remain frontend settings; for example, set
`corfu-max-width` to `24` in your web editing buffers to limit the menu width.

With Corfu's default keys, select with **up/down**, accept with **RET**, or cancel
with **C-g**. If `corfu-preselect` is `prompt`, select the candidate first;
accepting the prompt leaves the abbreviation unchanged.

After expansion, point starts at the first editable field, such as an anchor's
`href`. With yasnippet, **TAB** visits separate values in `c,bg` or `m,p`, while
repeated `${1:...}` fields remain synchronized mirrors. The final TAB exits at
the expansion's end, including at EOF without an extra newline. Indentation follows
your major mode; one undo restores the original abbreviation. Without yasnippet,
the text and initial cursor position are the same.

`corfu-on-exact-match` set to `show` keeps the Emmet candidate visible even when it
matches the input exactly. Automatic display follows your Corfu prefix and delay
settings; **`M-x emmet2-complete`** requests it manually. Emmet does not enable these
optional modes or change your completion settings. See [completion behavior](CONTRIBUTING.md#completion-behavior)
for details.

## JSX variables and project options

V2 defaults to **`styles`** for the CSS Modules object and **`clsx`** for joining
multiple class names. For example, `.abc.xyz/` expands to the element below; add
the matching imports to your source file:

```jsx
import styles from './Card.module.css';
import clsx from 'clsx';

<div className={clsx(styles.abc, styles.xyz)} />
```

`styles.abc` refers to the local `.abc` class in `Card.module.css`. A single class
uses `styles.abc` directly; multiple classes use `clsx(...)`. Hyphenated names use
bracket access, for example `.btn-primary` becomes `styles["btn-primary"]`.

| Emacs option | Default | Purpose |
| --- | --- | --- |
| `emmet2-css-modules-object` | `"styles"` | CSS Modules import name or object reference, such as `cardStyles` or `styles.module` |
| `emmet2-class-names-constructor` | `"clsx"` | Function reference for joining multiple classes, such as `cx` or `helpers.cx` |
| `emmet2-markup-variant` | `nil` | Detect HTML/JSX from context; `"solid"` emits Solid JSX with `class` instead of `className` |

These names must match your JavaScript imports or bindings. They control generated
JSX; configure your frontend project for CSS Modules and the chosen class-name helper.
Set them globally with `setq` or use `.dir-locals.el` for a project's conventions
(use `web-mode` instead of `tsx-ts-mode` when editing JSX with web-mode):

```elisp
((tsx-ts-mode . ((emmet2-markup-variant . "solid")
                (emmet2-css-modules-object . "cardStyles")
                (emmet2-class-names-constructor . "cx"))))
```

Then `.card.active` becomes `<div class={cx(cardStyles.card, cardStyles.active)}></div>`.
Use the corresponding `cardStyles` and `cx` imports in that project.

## Abbreviation reference

See the [Emmet cheat sheet](https://docs.emmet.io/cheat-sheet/) for general syntax.
The examples below cover this mode's additions and editing behavior.
`│` marks the initial cursor position where relevant.
Multiline CSS output is shown on one line for readability.

### HTML and JSX

| Context | Abbreviation | Expansion |
| --- | --- | --- |
| HTML | `.` | `<div class="│"></div>` |
| HTML | `.card` | `<div class="card">│</div>` |
| HTML | `a.link` | `<a href="│" class="link"></a>` |
| JSX | `Component` | `<Component>│</Component>` |
| JSX | `Component/` | `<Component />` |
| JSX | `Component./` | `<Component className={│} />` |
| JSX | `Component.card` | `<Component className={styles.card}>│</Component>` |
| JSX | `Component.Subcomponent` | `<Component.Subcomponent>│</Component.Subcomponent>` |
| JSX | `Component.Subcomponent.card` | `<Component.Subcomponent className={styles.card}>│</Component.Subcomponent>` |
| JSX | `Component.Subcomponent.a.b/` | `<Component.Subcomponent className={clsx(styles.a, styles.b)} />` |
| JSX | `Component{{props.value}}` | `<Component>{props.value}</Component>` |
| Solid JSX | `Component.card` | `<Component class={styles.card}>│</Component>` |

Uppercase dotted names select subcomponents; lowercase suffixes add classes.
Use `/` for self-closing components and doubled braces for JSX text expressions.

### CSS values

Length values default to `px` for integers and `rem` for decimals. Zero and
unitless properties such as `line-height` stay unitless. Explicit units override
these defaults; `r` abbreviates `rem`, `e` abbreviates `em`, and `p` abbreviates `%`.
Append `!` to a property abbreviation to add `!important`.

| Abbreviation | Expansion |
| --- | --- |
| `c` | `color: │;` |
| `bg` | `background: │;` |
| `bd` | `border: │;` |
| `p1-2-3` or `p[1px 2px 3px]` | `padding: 1px 2px 3px;` |
| `p1px2px3px` | `padding: 1px 2px 3px;` |
| `p1r` | `padding: 1rem;` |
| `w50p` | `width: 50%;` |
| `lh1.5` | `line-height: 1.5;` |
| `m-10` | `margin: -10px;` |
| `m10--20` | `margin: 10px -20px;` |
| `m--gutter!` | `margin: var(--gutter) !important;` |
| `p--a--b--c` | `padding: var(--a) var(--b) var(--c);` |
| `p$a$b$c` | `padding: $a $b $c;` |
| `w[calc(100% - 2rem)]` | `width: calc(100% - 2rem);` |
| `ff[Arial,sans-serif]` | `font-family: Arial,sans-serif;` |

Default suggestions are cleared so `c`, `bg` and `bd` leave editable values.
A hyphen after a number with an explicit unit is a minus sign:
`m10px-20px` means `margin: 10px -20px;`. Use raw brackets for complex values
when you want the literal CSS, for example `m[10px 20px]`.

### CSS aliases

`posa` and `posf` also create a `z-index` declaration. `all` expands to the four
offsets in top/right/bottom/left order, with separate fields when no value is given.
In stylesheet context, `:` starts a pseudo-selector; use camelCase aliases such
as `mA` for keyword values. Recognized lowercase property/value combinations such
as `tac`, `dn`, `db`, and `posr` also offer completion, as do value aliases such as
`wf`. Known snippet prefixes such as `m`, `bd`, and `ta` offer matching properties
and literal keyword choices. Ordinary CSS property names such as `margin` and
declaration values remain with the language completion provider. Corfu's prefix
threshold still applies.

For example, Emmet's `d:n` becomes a `d:not` selector here, so write `dn` or `dN`
for `display: none;`. Inside declaration blocks,
bare names followed by a single colon, such as `display:fl` or `button:hv`,
are left to the language completion provider. Use `C-j` to explicitly expand
a type/pseudo selector such as `button:hv`.

| Abbreviation | Expansion |
| --- | --- |
| `posa` | `position: absolute; z-index: │;` |
| `posa1000` | `position: absolute; z-index: 1000;` |
| `posf100` | `position: fixed; z-index: 100;` |
| `all` | `top: │; right: ; bottom: ; left: ;` |
| `all8` | `top: 8px; right: 8px; bottom: 8px; left: 8px;` |
| `mA` | `margin: auto;` |
| `dN` | `display: none;` |
| `allA` | `top: auto; right: auto; bottom: auto; left: auto;` |
| `fw7` | `font-weight: 700;` |
| `wf` | `width: 100%;` |
| `hf` | `height: 100%;` |
| `mawf` | `max-width: 100%;` |
| `miwf` | `min-width: 100%;` |
| `mahf` | `max-height: 100%;` |
| `mihf` | `min-height: 100%;` |

### Scale and rhythm functions

`fz(...)` emits `ms(...)`; other properties use `rhythm(...)`, with `(0)` kept
as `0`. These are function calls for your stylesheet build to provide.

| Abbreviation | Expansion |
| --- | --- |
| `fz(1)` | `font-size: ms(1);` |
| `t(2)` | `top: rhythm(2);` |
| `p(1)(2)(3)` | `padding: rhythm(1) rhythm(2) rhythm(3);` |
| `p(0)(2)` | `padding: 0 rhythm(2);` |

### CSS and SCSS at-rules

In SCSS (`scss-mode` or `<style lang="scss">`), short names expand to at-rule
names or Sass templates with editable fields:

| Abbreviation | Expansion |
| --- | --- |
| `@cs` | `@charset │` |
| `@kf` | `@keyframes │` |
| `@md` | `@media │` |
| `@us` | `@use "│";` |
| `@in` | `@if not │ { }` |
| `@else` | `@else { │ }` |

Plain CSS (`css-mode`, other `<style>` blocks and `style=""` attributes) keeps
Emmet's own at-rule snippets and never offers Sass-only rules. Other short names
resolve to CSS at-rule names:

| Abbreviation | Expansion |
| --- | --- |
| `@m` or `@md` | `@media │screen { }` |
| `@f` | `@font-face { font-family: │; src: url(); }` |
| `@i` or `@im` | `@import url(│);` |
| `@kf` | `@keyframes │identifier { }` |
| `@sup` | `@supports │` |

### Pseudo-classes and pseudo-elements

Use `:` for either kind, including short names such as `:af` for `::after`.
Selectors start with `&` by default; prefix `_` to omit it, or supply a selector
such as `.card:fu`. Comma-separated `:not(...)` arguments retain the legacy
expansion into chained calls. They match the same elements as a selector list,
but their specificity adds up. Other pseudo-functions such as `:is(...)` keep
one selector list. Nested pseudo-functions are supported.

| Abbreviation | Expansion |
| --- | --- |
| `:fu` | `&:focus { │ }` |
| `_:fu` | `:focus { │ }` |
| `.card:fu` | `.card:focus { │ }` |
| `:hv:af` | `&:hover::after { │ }` |
| `:n(:fc)` | `&:not(:first-child) { │ }` |
| `:n(:fc,:lc):be` | `&:not(:first-child):not(:last-child)::before { │ }` |
| `:is(:fu,:hv)` | `&:is(:focus, :hover) { │ }` |
| `:nc(2n-1)` | `&:nth-child(2n-1) { │ }` |
| `:h(+p)` | `&:has(+ p) { │ }` |

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and tests, and the
[manual GUI acceptance record](test/gui-acceptance-2026-09-27.md) for verified scope.
Upstream credits and licenses are in [NOTICE](NOTICE).
