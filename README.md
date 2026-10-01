# emmet2-mode

emmet2-mode offers Emmet abbreviations as completion choices for HTML, JSX,
CSS and SCSS in Emacs. Expansion runs locally in Emacs Lisp.
JSX classes use CSS Modules and a project class-joining function; see
[project settings](#jsx-and-project-settings).

## Supported modes

- **CSS and SCSS:** `scss2-mode`, `css2-mode`, `css-mode`, `scss-mode`,
  `css-ts-mode` and `less-css-mode`.
- **HTML and JSX:** `web-mode` and `tsx-ts-mode`.
- **JavaScript and TypeScript:** `js-mode`, `js-ts-mode` and `typescript-ts-mode`.

For CSS/SCSS, the optional development packages scss2-mode and css2-mode combine
abbreviation completion with context-aware suggestions. They currently install
from a locally built archive; see the
[scss2-mode documentation](https://github.com/P233/scss2-mode) for setup and usage.

## Installation

Requires **Emacs 30+**. Add the package directory to your Emacs configuration
and enable emmet2-mode in the modes you use:

```elisp
(add-to-list 'load-path "/path/to/emmet2-mode")
(autoload 'emmet2-mode "emmet2-mode" nil t)
(dolist (hook '(web-mode-hook css-base-mode-hook
                js-base-mode-hook typescript-ts-base-mode-hook))
  (add-hook hook #'emmet2-mode))
```

Keep the bundled `data/` directory alongside the Lisp files. Package-manager
recipes should include `:files (:defaults "data")`. You can also enable emmet2-mode
in an open buffer with `M-x emmet2-mode`.

For straight.el with use-package, the equivalent package recipe is:

```elisp
(use-package emmet2-mode
  :straight (emmet2-mode :type git :host github :repo "P233/emmet2-mode"
                        :files (:defaults "data"))
  :hook ((web-mode css-base-mode js-base-mode typescript-ts-base-mode) . emmet2-mode))
```

JavaScript/JSX contexts require Emacs built with tree-sitter and an installed
matching grammar: `javascript` for `js-mode`, `js-ts-mode` and Web script parts;
`typescript` for `typescript-ts-mode` and typed Web script parts; `tsx` for
`tsx-ts-mode` and Web JSX files.
Automatic completion waits for a grammar; a manual request reports a missing
one. HTML and built-in CSS/SCSS analysis need no additional grammar. The exact
tested grammar revisions are in [test/dependencies.json](test/dependencies.json).
The default HTML mode, `mhtml-mode`, supports manual Emmet completion only.

### Corfu and yasnippet

Use **[Corfu](https://github.com/minad/corfu)** for automatic completion popups
and full previews, and **[yasnippet](https://github.com/joaotavora/yasnippet)**
for **TAB** navigation and linked fields. Both are optional packages that you
install and configure in your Emacs setup.

Emmet2 automatically adapts its Corfu rows to show expansion labels in the main
column, honoring your width limit. Each popup stays at its initial cursor
position while typing. Other completion providers keep their normal display.

The following example uses straight.el and use-package:

```elisp
(use-package corfu
  :straight t
  :hook ((web-mode css-base-mode js-base-mode typescript-ts-base-mode) . corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-on-exact-match 'show)
  :config
  (corfu-popupinfo-mode 1))

;; Installing is enough; emmet2-mode enables yas-minor-mode when needed.
(use-package yasnippet
  :straight t
  :defer t)
```

Corfu normally waits for three characters before point. For one- or two-character
abbreviations such as `d`, `ta` and `@f`, request completion manually or set
`corfu-auto-prefix` to `1`; emmet2-mode leaves that threshold to your configuration.
`corfu-on-exact-match 'show` keeps expansion choices visible when your completion
styles consider the unchanged abbreviation an exact match, including configurations
whose first style is not `basic`.

Corfu is the tested frontend. Other CAPF frontends may merge choices with identical
text or discard the properties identifying alternatives; full alternative selection
and preview behavior has not been verified with those frontends.

### Optional Corfu settings

These are **personal examples, not emmet2-mode defaults**; they also affect
other completion providers in the same buffers.

| Setting | Example | Effect |
| --- | --- | --- |
| `corfu-auto-delay` | `0.08` | Delay before automatic candidates. |
| `corfu-popupinfo-delay` | `'(0 . 0)` | Immediate initial and subsequent previews. |
| `corfu-auto-prefix` | `1` | Offer candidates after one character. |
| `corfu-max-width` | `32` | Limit menu width. |
| `corfu-count` | `10` | Visible rows; does not change candidate count. |

## Use

With [automatic completion](#corfu-and-yasnippet) enabled in your frontend:

1. Type an abbreviation, such as `ul>li*3` in HTML or `m10` inside a CSS rule.
2. Select a choice from the completion popup as you type.
3. Accept a choice to replace the abbreviation; undo once to restore it.

You can keep point anywhere inside the abbreviation. Your completion frontend
controls whether a sole match is accepted automatically.

CSS property values also match fuzzily: `display: if` offers `inline-flex`.
Accepting a function such as `calc()` places point inside its parentheses;
`css2-mode` / `scss2-mode` use TAB to leave the parentheses, then skip the
declaration's semicolon. Value completion creates no snippet fields. CSS Base
modes share the matching and initial cursor placement.

| Context | Abbreviation | Result |
| --- | --- | --- |
| HTML | `ul>li*3` | A list with three items |
| JSX | `.card.active` | `<div className={clsx(styles.card, styles.active)}></div>` |
| CSS | `m10,p.5` or `m10+p.5` | `margin: 10px; padding: 0.5rem;` |
| CSS | `ins32` | `inset: 32px;` |
| CSS | `m--gutter` | `margin: var(--gutter);` |
| CSS | `p1-2` or `p[1px 2px]` | `padding: 1px 2px;` |
| JSX style object | `m10,p.5` or `m10+p.5` | `margin: 10, padding: "0.5rem"` |

### Where to type abbreviations

- **HTML and JSX:** type in markup content. Automatic completion recognizes
  abbreviations such as `ul>li*3` and standalone tags such as `div`.
- **CSS and SCSS:** type property abbreviations at the start of a declaration
  inside braces. Pseudos and at-rules also work at the stylesheet root.
  Existing property values use your language mode's completion.
- **Embedded styles:** `<style>` and `style=""` use CSS output; JSX `style={{...}}`
  and objects passed to `StyleSheet.create(...)` or `createTheme(...)` use
  camelCase properties and JavaScript values.

In supported modes, emmet2-mode skips ordinary comments, strings and unrelated
JavaScript.

### Choosing an expansion

CSS completion offers up to ten choices. For example, `ta` offers `text-align: ;`,
its keywords and alternatives such as `top: auto;`. Keep typing to refine the
list, use **up/down** to select, **RET** to accept and **C-g** to cancel with
Corfu's default keys. If `corfu-preselect` is `prompt`, select a candidate first.

For `ovh,ta` or `ovh+ta`, the menu shows choices for the active property;
the full preview and insertion include `overflow: hidden;` too. Accepting after
a trailing `,` or `+` consumes that separator. In a JSX style object, a trailing
comma stays as an object separator.

### Editable fields

After accepting `a.link` from completion, point starts in `href`; after `c,bg`,
it starts in the first value. With yasnippet installed, **TAB** visits subsequent
fields and exits at the end, and repeated fields update together. emmet2-mode
enables yasnippet when fields are first needed, so no extra hook is required.

Without yasnippet, you get the same text and initial cursor position, and TAB
keeps its usual behavior. Outside an active field, your normal snippet and TAB
commands remain available.

### Manual completion

To request choices manually, run **`M-x emmet2-complete`**. In other major modes,
this command also offers plain markup, including in `text-mode` and `mhtml-mode`.
It works without enabling the minor mode first.

For manual requests, you can optionally bind **`C-c .`**; emmet2-mode binds no
keys by default. This binding applies only while the minor mode is enabled:

```elisp
(with-eval-after-load 'emmet2-mode
  (keymap-set emmet2-mode-map "C-c ." #'emmet2-complete))
```

## Abbreviation reference

`│` marks the initial cursor; multiline CSS is condensed for readability.
The [Emmet cheat sheet](https://docs.emmet.io/cheat-sheet/) covers general markup
syntax; the CSS examples below use emmet2-mode in built-in CSS/SCSS modes.

### HTML and JSX

| Context | Abbreviation | Expansion |
| --- | --- | --- |
| HTML | `.` | `<div class="│"></div>` |
| HTML | `.card` | `<div class="card">│</div>` |
| HTML | `a.link` | `<a href="│" class="link"></a>` |
| JSX | `Component` | `<Component>│</Component>` |
| JSX | `Component/` | `<Component />` |
| JSX | `Component./` | `<Component className={styles["│"]} />` |
| JSX | `Component.card` | `<Component className={styles.card}>│</Component>` |
| JSX | `Component.Subcomponent` | `<Component.Subcomponent>│</Component.Subcomponent>` |
| JSX | `Component.Subcomponent.card` | `<Component.Subcomponent className={styles.card}>│</Component.Subcomponent>` |
| JSX | `Component.Subcomponent.a.b/` | `<Component.Subcomponent className={clsx(styles.a, styles.b)} />` |
| JSX | `Component{{props.value}}` | `<Component>{props.value}</Component>` |
| Solid JSX | `Component.card` | `<Component class={styles.card}>│</Component>` |

Uppercase dotted names select subcomponents; lowercase suffixes add classes.
Use `/` for self-closing components and doubled braces for JSX text expressions.

### CSS search and aliases

Use property initials, word fragments or full names: `bgc` finds `background-color`,
`ta` finds `text-align`, `mbs` finds `margin-block-start`, and `ins` finds `inset`.
`inset-b` finds `inset-block`, and `is` finds `inline-size`. Short queries favor
common properties, so `m` offers `margin` first.

Combine a property and value in one query: `tac` → `text-align: center;`,
`dib` → `display: inline-block;`, `bdn` → `border: none;`. Start the value with an
uppercase letter to make the split explicit: `mA` → `margin: auto;`,
`dN` → `display: none;`.

Common aliases include `bg` (background), `bd` (border), `bx` (box), `fx` (flex),
`trf` (transform), `trs` (transition), `ol` (outline) and `rs` (radius).
Use `b` for `bottom`, `ct` for `content`, `fz` for `font-size` and `bxz` for `box-sizing`.

A bare property leaves an editable value: `d` gives `display: │;`.
`bgilg` gives `background-image: linear-gradient(│);` and `crgb` gives `color: rgb(│);`.
For ambiguous forms, `fs` prefers `font-size` and `bdr` prefers `border-radius`;
select another choice for a different reading. Full names retain their meaning,
including obsolete properties such as `clip`, which are omitted from fuzzy search.

A colon starts a pseudo-class, so use `dn` or `dN` rather than `d:n`.
`display:fl` stays with language completion; `button:hv` can start a nested selector.

### CSS values

Join properties with `,` or `+` without spaces, as in `m10,p.5`. Put literal
values and functions in `[...]`; commas and plus signs inside brackets stay literal.
Lengths default to `px` for integers and `rem` for decimals. Zero and numeric
properties such as `line-height`, `order`, Grid line numbers and opacity stay
unitless. Override units with `r` for `rem`, `e` for `em` or `p` for `%`, and
append `!` for `!important`.

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
| `order1` | `order: 1;` |
| `column-count2` | `column-count: 2;` |
| `grid-row-start2` | `grid-row-start: 2;` |
| `fill-opacity.5` | `fill-opacity: 0.5;` |
| `m-10` | `margin: -10px;` |
| `m10--20` | `margin: 10px -20px;` |
| `m--gutter!` | `margin: var(--gutter) !important;` |
| `p--a--b--c` | `padding: var(--a) var(--b) var(--c);` |
| `w[calc(100% - 2rem)]` | `width: calc(100% - 2rem);` |
| `ff[Arial,sans-serif]` | `font-family: Arial,sans-serif;` |

SCSS supports property-plus-variable forms such as `m$gutter` and `p$a$b$c`
(`padding: $a $b $c;`). Completion stays
available while typing `p$` or `p$-`; bare `$name` uses your language mode's completion.

A hyphen after an explicit unit means a negative value: `m10px-20px` gives
`margin: 10px -20px;`. Use `m[10px 20px]` for two positive values.
Empty parentheses and quotes become editable fields: `w[calc()]` and `ct[""]`
place point inside.

In JSX style objects, unitless and pixel values become numbers; other units
become strings. Leading zeros stay literal: `p[010px]` gives `padding: "010px"`.

### CSS shorthands

| Abbreviation | Expansion |
| --- | --- |
| `posa` | `position: absolute; z-index: │;` |
| `posa1000` | `position: absolute; z-index: 1000;` |
| `posf100` | `position: fixed; z-index: 100;` |
| `all` | `top: │; right: ; bottom: ; left: ;` |
| `all8` | `top: 8px; right: 8px; bottom: 8px; left: 8px;` |
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
as `0`. These are project conventions: your stylesheet build must provide both
functions, for example `rhythm()` from [rhythm-sass](https://github.com/P233/rhythm-sass)
and your own `ms()` scale helper.

| Abbreviation | Expansion |
| --- | --- |
| `fz(1)` | `font-size: ms(1);` |
| `t(2)` | `top: rhythm(2);` |
| `p(1)(2)(3)` | `padding: rhythm(1) rhythm(2) rhythm(3);` |
| `p(0)(2)` | `padding: 0 rhythm(2);` |

### CSS and SCSS at-rules

Type an `@` fragment and select a choice: `@f` offers `@font-face`,
`@font-feature-values` and `@font-palette-values`. Built-in CSS modes insert
at-rule names; `scss-mode` and `<style lang="scss">` also offer Sass templates.

| Context | Input | Selected menu row | After acceptance |
| --- | --- | --- | --- |
| CSS/SCSS | `@md` | `@media` | `@media │` |
| CSS/SCSS | `@kf` | `@keyframes` | `@keyframes │` |
| CSS | `@f` | `@font-face` | `@font-face │` |
| CSS | `@i` | `@import` | `@import │` |
| SCSS | `@cs` | `@charset` | `@charset │` |
| SCSS | `@us` | `@use "";` | `@use "│";` |
| SCSS | `@in` | `@if not  { }` | `@if not │ { }` |
| SCSS | `@in` | `@include` | `@include │` |
| SCSS | `@else` | `@else { }` | `@else { │ }` |

### Pseudo-classes and pseudo-elements

Type after `:` to search both kinds, or after `::` for pseudo-elements only.
Prefixes such as `&`, `.card` and `button` are preserved; add `&` yourself when
needed. The menu shows just the pseudo chain, so `&::be` offers `::before` and
inserts `&::before`.

Required arguments get editable parentheses (`:not` → `:not(│)`). Optional forms
such as `:host` and `::cue` stay bare unless you type parentheses. Add rule braces
and any `content` declaration yourself.

| Input | Selected menu row | After acceptance |
| --- | --- | --- |
| `:fu` | `:focus` | `:focus│` |
| `&:fu` | `:focus` | `&:focus│` |
| `.card:fu` | `:focus` | `.card:focus│` |
| `button:hv` | `:hover` | `button:hover│` |
| `::be` | `::before` | `::before│` |
| `&::be` | `::before` | `&::before│` |
| `:hv:af` | `:hover::after` | `:hover::after│` |
| `:n` | `:not()` | `:not(│)` |
| `:n(:fc)` | `:not(:first-child)` | `:not(:first-child)│` |
| `:n(:fc,:lc):be` | `:not(:first-child):not(:last-child)::before` | `:not(:first-child):not(:last-child)::before│` |
| `:is(:fu,:hv)` | `:is(:focus, :hover)` | `:is(:focus, :hover)│` |
| `:nc(2n-1)` | `:nth-child(2n-1)` | `:nth-child(2n-1)│` |
| `:h(+p)` | `:has(+ p)` | `:has(+ p)│` |
| `::part` | `::part()` | `::part(│)` |

Selector lists, attributes and combinators are preserved:
`.a,:hv` → `.a,:hover`, and `.card[disabled] > .child:hv` → `.card[disabled] > .child:hover`.
Comma-separated `:not()` arguments become chained calls, which adds specificity;
other functions retain their selector lists. The older `_:fu` form also gives `:focus`.

## JSX and project settings

`.abc.xyz/` uses **`styles`** for CSS Modules and **`clsx`** to join classes.
Add matching imports yourself:

```jsx
import styles from './Card.module.css';
import clsx from 'clsx';

<div className={clsx(styles.abc, styles.xyz)} />
```

A single class uses `styles.abc` directly. Hyphenated names use bracket access:
`.btn-primary` becomes `styles["btn-primary"]`. An empty class abbreviation such
as `.` starts an editable key, as in `styles["│"]`. React maps `for` to `htmlFor`; Solid retains `for`.

| Emacs option | Default | Purpose |
| --- | --- | --- |
| `emmet2-css-modules-object` | `"styles"` | CSS Modules import name or object reference, such as `cardStyles` or `styles.module` |
| `emmet2-class-names-constructor` | `"clsx"` | Function reference for joining multiple classes, such as `cx` or `helpers.cx` |
| `emmet2-markup-variant` | `nil` | Detect HTML/JSX from context; `"solid"` emits Solid JSX, with `class` instead of `className`, in every markup context |

Set object/helper names globally with `setq` or per project in `.dir-locals.el`.
Keep `emmet2-markup-variant` project-local: `"solid"` changes all markup output,
including HTML contexts, to Solid JSX. For example (substitute `web-mode` when
using it for JSX):

```elisp
((tsx-ts-mode . ((emmet2-markup-variant . "solid")
                (emmet2-css-modules-object . "cardStyles")
                (emmet2-class-names-constructor . "cx"))))
```

Then `.card.active` becomes `<div class={cx(cardStyles.card, cardStyles.active)}></div>`;
the project must provide `cardStyles`, `cx` and CSS Modules support.

## Troubleshooting

- No automatic popup: enable the frontend's automatic completion, check its prefix
  threshold, and try `M-x emmet2-complete` for a diagnostic.
- No Emmet choice: check the [allowed contexts](#where-to-type-abbreviations).
  Existing property values and comments belong to the language mode.
- Missing tree-sitter grammar: install the grammar for the host listed above.
- Missing JSX names: configure and import the CSS Modules object and class helper
  used by your project.

Host integrations and pure expansion interfaces are documented in [API.md](API.md).

## Upgrading from 0.2

- Remove the Deno, `deno-bridge` and `websocket` configuration, then restart Emacs.
- Accept choices from automatic completion to expand abbreviations. If you keep
  a manual completion key, replace `emmet2-expand` with `emmet2-complete`.
- Replace `:files (:defaults "*.ts" "src" "data")` with `:files (:defaults "data")`.
- CSS properties now leave an empty value field; replace value presets such as
  `lg` with property-and-value queries such as `bgilg`.

See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## License

GPL-3.0-or-later. Third-party credits and licenses are in [NOTICE](NOTICE).
