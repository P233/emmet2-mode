# emmet2-mode

emmet2-mode brings [Emmet](https://emmet.io/) abbreviations to Emacs as
completion choices for HTML, JSX, CSS, SCSS and CSS-in-JS. Type `ul>li*3`,
`.card.active` or `m10,p.5`, pick a choice from the completion popup, and the
abbreviation becomes code.

> **emmet2-mode 2.0 is a native rewrite.** Everything now runs inside Emacs as
> Emacs Lisp: Deno, deno-bridge, websocket and the Emmet npm package are no
> longer needed. Abbreviations appear as completion choices with previews
> instead of expanding on `C-j`. Coming from 0.2? See
> [Upgrading from 0.2](#upgrading-from-02).

## Features

- Emmet abbreviations as completion choices, with full previews and one-step
  undo.
- Fast CSS search such as `bgc`, `tac` and `ins32`; see
  [CSS search and aliases](#css-search-and-aliases).
- Fuzzy CSS value completion with documentation; see
  [CSS value completion](#css-value-completion).
- JSX output for CSS Modules, plain classes or Solid; see
  [JSX and project settings](#jsx-and-project-settings).
- Styles in `<style>`, `style=""`, JSX `style={{...}}` and style objects such
  as `StyleSheet.create({...})`.
- Pseudo-classes, pseudo-elements and at-rules, with Sass templates in SCSS.
- HTML and JSX attributes become yasnippet fields you visit with **TAB**; CSS
  selects nothing and leaves TAB to you; see [Cursor and fields](#cursor-and-fields).

## Better with scss2-mode

For CSS and SCSS files, use emmet2-mode together with
**[scss2-mode](https://github.com/P233/scss2-mode)**, a native major mode
package that provides `scss2-mode` and `css2-mode`. It is built on
**[tree-sitter-scss](https://github.com/P233/tree-sitter-scss)**, a new parser
written for SCSS and CSS that parses everyday Sass, such as maps, `!default`
and `@use ... as`, without errors.

The two packages share one completion popup:

- **The syntax tree decides where abbreviations expand.** `m10` expands at the
  start of a declaration, never inside a value or selector, and descriptors
  inside rules such as `@font-face` come from the enclosing at-rule.
- **scss2-mode completes everything else:** property values, CSS functions,
  pseudo-selectors, media queries, custom properties in `var()`, import paths,
  and Sass variables, functions, mixins and module members.
- **Structural editing:** kill, copy, duplicate or clear a selector branch,
  declaration, value, argument or block. **TAB** leaves a value past its `;`.

scss2-mode bundles its parser and compiles it on first use, so there is no
grammar to install, and it installs emmet2-mode as a dependency. It is in
active development and currently installs from a locally built package
archive; see the [scss2-mode README](https://github.com/P233/scss2-mode) for
setup.

emmet2-mode also works on its own in the built-in CSS modes listed below.

## Supported modes

- **CSS and SCSS:** `scss2-mode` and `css2-mode` (recommended), `css-mode`,
  `scss-mode`, `css-ts-mode` and `less-css-mode`.
- **HTML and JSX:** `web-mode` (a separate package) and `tsx-ts-mode`. In the
  default HTML mode, `mhtml-mode`, only manual completion works, and it treats
  everything as markup, including `<style>` blocks; use web-mode for CSS in
  HTML.
- **JavaScript and TypeScript:** `js-mode` and `js-ts-mode` for JSX and style
  objects, and `typescript-ts-mode` for style objects. Use `tsx-ts-mode` for
  TypeScript JSX.

## Installation

emmet2-mode requires **Emacs 30 or later** and has no external runtime. With
straight.el and use-package:

```elisp
(use-package emmet2-mode
  :straight (emmet2-mode :type git :host github :repo "P233/emmet2-mode"
                         :files (:defaults "data"))
  :hook ((web-mode css-base-mode js-base-mode typescript-ts-base-mode) . emmet2-mode))
```

Keep the bundled `data/` directory alongside the Lisp files; other package
managers need the same `:files (:defaults "data")` recipe. From a plain
checkout:

```elisp
(add-to-list 'load-path "/path/to/emmet2-mode")
(autoload 'emmet2-mode "emmet2-mode" nil t)
(autoload 'emmet2-complete "emmet2-capf" nil t)
(autoload 'emmet2-expand-at-point "emmet2-capf" nil t)
(dolist (hook '(web-mode-hook css-base-mode-hook
                js-base-mode-hook typescript-ts-base-mode-hook))
  (add-hook hook #'emmet2-mode))
```

You can also enable it in an open buffer with `M-x emmet2-mode`.

To check the installation, open a `.css` file, type `.a { m10 }`, put point
after `m10` and run `M-x emmet2-expand-at-point`; it becomes
`.a { margin: 10px; }`.

JavaScript, TypeScript and JSX buffers need Emacs built with tree-sitter and
the matching grammar: `javascript` for `js-mode`, `js-ts-mode` and web-mode
script parts, `typescript` for `typescript-ts-mode`, and `tsx` for `tsx-ts-mode`
and web-mode JSX files. HTML and CSS need no grammar. The tested grammar
revisions are listed in [test/dependencies.json](test/dependencies.json).

### Corfu and yasnippet

Use **[Corfu](https://github.com/minad/corfu)**, a completion frontend that shows
choices in a popup, for automatic completion and full previews, and **[yasnippet](https://github.com/joaotavora/yasnippet)**
for **TAB** navigation and linked fields in HTML and JSX. Both are optional;
install and configure them as usual:

```elisp
(use-package corfu
  :straight t
  :hook ((web-mode css-base-mode js-base-mode typescript-ts-base-mode) . corfu-mode)
  :custom
  (corfu-auto t)
  :config
  (corfu-popupinfo-mode 1))

;; Installing is enough; emmet2-mode enables yas-minor-mode when needed.
(use-package yasnippet
  :straight t
  :defer t)
```

emmet2-mode needs no other Corfu settings, changes none of yours, and works
with icon margins such as kind-icon and nerd-icons-corfu.

Corfu waits for three characters by default. For short abbreviations such as
`d`, `ta` and `@f`, request completion manually or lower `corfu-auto-prefix`.
Corfu is the tested frontend; other frontends may merge choices with identical
text, so selecting alternatives and previews may not work there.

These **optional personal settings** also affect other completion sources in
the same buffers:

| Setting | Example | Effect |
| --- | --- | --- |
| `corfu-auto-delay` | `0.08` | Delay before automatic candidates. |
| `corfu-popupinfo-delay` | `'(0 . 0)` | Immediate previews. |
| `corfu-auto-prefix` | `1` | Offer candidates after one character. |
| `corfu-max-width` | `32` | Limit menu width. |
| `corfu-count` | `15` | Visible rows; does not change the number of choices. |

## Usage

With [automatic completion](#corfu-and-yasnippet) enabled in your frontend:

1. Type an abbreviation, such as `ul>li*3` in HTML or `m10` inside a CSS rule.
2. Select a choice from the completion popup as you type.
3. Accept a choice to replace the abbreviation; undo once to restore it.

You can keep point anywhere inside the abbreviation. With Corfu, a sole Emmet
choice stays in the popup until you accept it, even when auto-paired quotes
follow point as in `a[href="│"]`; other frontends decide whether a sole match is
accepted automatically.

Without Corfu, the default completion UI shows only "Complete, but not
unique" on the first request; request again to list the choices in
*Completions*, or use `M-x emmet2-expand-at-point` to insert the first choice
directly.

| Context | Abbreviation | Result |
| --- | --- | --- |
| HTML | `ul>li*3` | A list with three items |
| JSX | `.card.active` | `<div className={clsx(styles.card, styles.active)}></div>` |
| JSX | `_.card.active` | `<div className="card active"></div>` |
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
  Property values offer value completion, not abbreviations.
- **Embedded styles:** `<style>` and `style=""` use CSS output; JSX `style={{...}}`
  and objects passed to `StyleSheet.create(...)` or `createTheme(...)` use
  camelCase properties and JavaScript values. Add other style attributes and
  functions, such as `sx` or `css(...)`, in [project settings](#jsx-and-project-settings).

In supported modes, emmet2-mode skips ordinary comments, strings and unrelated
JavaScript.

### CSS value completion

After a property's colon, values match fuzzily and show documentation:
`display: if` offers `inline-flex`. Accepting a function such as `calc()` places
point inside its parentheses; in `scss2-mode` and `css2-mode`, **TAB** then
leaves the value past its semicolon.

In built-in modes such as `css-mode`, `scss-mode` and `less-css-mode`, this
replaces css-mode's own value list for known properties, which matches only by
prefix and shows no documentation. When no value matches, other completion
sources such as Eglot still run. To keep css-mode's value completion instead:

```elisp
(add-hook 'emmet2-mode-hook
          (lambda ()
            (remove-hook 'completion-at-point-functions #'emmet2-css-value-capf t)))
```

### Choosing an expansion

CSS completion offers up to ten choices. For example, `ta` offers `text-align: ;`,
its keywords and alternatives such as `top: auto;`. Keep typing to refine the
list, use **up/down** to select, **RET** to accept and **C-g** to cancel with
Corfu's default keys. If `corfu-preselect` is `prompt`, select a candidate first.

For `ovh,ta` or `ovh+ta`, the menu shows choices for the active property;
the full preview and insertion include `overflow: hidden;` too. Accepting after
a trailing `,` or `+` consumes that separator. In a JSX style object, a trailing
comma ends the member, so `m10,` offers nothing; join properties with `+` or
keep typing, as in `m10,p.5`.

### Cursor and fields

After accepting `a.link` from completion, point starts in `href`. With yasnippet
installed, **TAB** visits subsequent HTML and JSX fields and exits at the end,
and repeated fields update together. emmet2-mode enables yasnippet when fields
are first needed, so no extra hook is required. Without yasnippet, you get the
same text and initial cursor position, and TAB keeps its usual behavior.

CSS expansions start no snippet: after `c,bg` point starts in the first value,
and after `d` before the semicolon. Typed or completed values are never
highlighted, and **TAB** keeps your own binding.

### Manual completion

To request choices manually, run **`M-x emmet2-complete`**. In major modes
without built-in support, such as `text-mode` and `mhtml-mode`, it offers plain
markup. It works without enabling the minor mode first.

To expand immediately without a menu, run **`M-x emmet2-expand-at-point`**. It
uses the same contexts as `emmet2-complete` and inserts the first choice, with
the same fields and one-step undo. For CSS, the first choice is the top-ranked
interpretation, so `fs` always gives `font-size`.

emmet2-mode binds no keys by default. You can bind either command; these
bindings apply only while the minor mode is enabled:

```elisp
(with-eval-after-load 'emmet2-mode
  (keymap-set emmet2-mode-map "C-c ." #'emmet2-complete)
  (keymap-set emmet2-mode-map "C-j" #'emmet2-expand-at-point))
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
| JSX | `_Component.card` | `<Component className="card">│</Component>` |
| JSX | `Component.Subcomponent` | `<Component.Subcomponent>│</Component.Subcomponent>` |
| JSX | `Component.Subcomponent.card` | `<Component.Subcomponent className={styles.card}>│</Component.Subcomponent>` |
| JSX | `Component.Subcomponent.a.b/` | `<Component.Subcomponent className={clsx(styles.a, styles.b)} />` |
| JSX | `Component{{props.value}}` | `<Component>{props.value}</Component>` |
| Solid JSX | `Component.card` | `<Component class={styles.card}>│</Component>` |

Uppercase dotted names select subcomponents; lowercase suffixes add classes.
Use `/` for self-closing components and doubled braces for JSX text expressions.
A leading `_` keeps the abbreviation's classes as a plain string.

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
select another choice for a different interpretation. Full names retain their meaning,
including obsolete properties such as `clip`, which are omitted from fuzzy search.

A colon starts a pseudo-class, so use `dn` or `dN` rather than `d:n`.
`display:fl` stays with the major mode's own completion; `button:hv` can start a nested selector.

### CSS values

Join properties with `,` or `+` without spaces, as in `m10,p.5`. Put literal
values and functions in `[...]`; commas and plus signs inside brackets stay literal.
Unknown properties, values, units, at-rules and pseudos offer no choice, so write
a font or project value in brackets: `ff[Inter]` gives `font-family: Inter;`.
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
available while typing `p$` or `p$-`; bare `$name` uses the major mode's own completion.

A hyphen after an explicit unit means a negative value: `m10px-20px` gives
`margin: 10px -20px;`. Use `m[10px 20px]` for two positive values.
Empty parentheses and quotes take the cursor: `w[calc()]` and `ct[""]` place
point inside.

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
| `allu` or `all[unset]` | `all: unset;` |
| `fw7` | `font-weight: 700;` |
| `wf` | `width: 100%;` |
| `hf` | `height: 100%;` |
| `mawf` | `max-width: 100%;` |
| `miwf` | `min-width: 100%;` |
| `mahf` | `max-height: 100%;` |
| `mihf` | `min-height: 100%;` |

### Scale and rhythm functions

Parenthesized numbers can become Sass function calls. This is off by default,
because your stylesheet build must provide the functions, for example `rhythm()`
from [rhythm-sass](https://github.com/P233/rhythm-sass) and your own `ms()` scale
helper. Set `emmet2-css-scale-functions` to map properties to functions; `t`
covers the remaining properties. It applies to SCSS only, not to plain CSS or
CSS-in-JS. A zero stays `0`, except for `font-size`, whose scale step 0 is the
base size.

```elisp
;; .dir-locals.el
((nil . ((emmet2-css-scale-functions . (("font-size" . "ms") (t . "rhythm"))))))
```

With that setting:

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
as `.` starts an editable key, as in `styles["│"]`. React maps `for` to `htmlFor`;
Solid retains `for`.

For global or library classes, start the abbreviation with `_`: `_.swiper.active/`
gives `<div className="swiper active" />`, and `_ul>li.item` keeps every class in
the expansion a string. Projects without CSS Modules, such as Tailwind projects,
can set `emmet2-jsx-class-style` to `plain` instead of typing `_` each time.

| Emacs option | Default | Purpose |
| --- | --- | --- |
| `emmet2-jsx-class-style` | `css-modules` | `css-modules` references, or `plain` class strings |
| `emmet2-css-modules-object` | `"styles"` | With `css-modules`: import name or object reference, such as `cardStyles` or `styles.module` |
| `emmet2-class-names-constructor` | `"clsx"` | With `css-modules`: function reference for joining classes, such as `cx` or `helpers.cx` |
| `emmet2-markup-variant` | `nil` | Detect HTML/JSX from context; `"solid"` emits Solid JSX, with `class` instead of `className`, in every markup context |
| `emmet2-css-in-js-attributes` | `("style")` | JSX attributes holding style objects, such as `"sx"` |
| `emmet2-css-in-js-functions` | `("StyleSheet.create" "createTheme")` | Functions whose object arguments hold styles, written as called, such as `"css"` or `"stylex.create"` |
| `emmet2-css-scale-functions` | `nil` | SCSS [scale and rhythm functions](#scale-and-rhythm-functions) |

Set these globally with `setq` or per project in `.dir-locals.el`.
Keep `emmet2-markup-variant` project-local: `"solid"` changes all markup output,
including HTML contexts, to Solid JSX. For example (substitute `web-mode` when
using it for JSX):

```elisp
((tsx-ts-mode . ((emmet2-markup-variant . "solid")
                (emmet2-css-modules-object . "cardStyles")
                (emmet2-class-names-constructor . "cx")
                (emmet2-css-in-js-functions . ("css")))))
```

Then `.card.active` becomes `<div class={cx(cardStyles.card, cardStyles.active)}></div>`,
and `css({m10})` expands to `css({margin: 10})`; the project must provide
`cardStyles`, `cx`, `css` and CSS Modules support.

## Troubleshooting

- No automatic popup: enable Corfu's automatic completion, check its prefix
  threshold, and try `M-x emmet2-complete` for a diagnostic.
- No Emmet choice: check the [allowed contexts](#where-to-type-abbreviations).
  Property values offer value completion; comments belong to the language mode.
- No choice inside a style object: add its attribute or function to
  `emmet2-css-in-js-attributes` or `emmet2-css-in-js-functions`.
- Missing tree-sitter grammar: `M-x emmet2-complete` reports it, as in
  `Missing tree-sitter grammar: javascript`. Install it with
  `M-x treesit-install-language-grammar`; [Installation](#installation) lists
  the grammar each mode needs.
- Missing JSX names: configure and import the CSS Modules object and class helper
  used by your project, or use `_` or `plain` for string classes.

## For package authors

emmet2-mode's CSS data, search and expansion can also be used as a library,
and other major modes can supply their own syntax context, as scss2-mode does.
See [API.md](API.md).

## Upgrading from 0.2

- Emacs 30 or later is required.
- Remove the Deno, `deno-bridge` and `websocket` configuration, and remove
  `:after deno-bridge` from the emmet2-mode declaration; otherwise use-package
  never loads emmet2-mode. Restart Emacs.
- Replace `:files (:defaults "*.ts" "src" "data")` with `:files (:defaults "data")`.
- Abbreviations expand when you accept a completion choice; `C-j` is no longer
  bound. To keep a direct expansion key, bind `emmet2-expand-at-point` in place
  of `emmet2-expand`, or bind `emmet2-complete` to request choices.
- The default CSS Modules object is now `styles` instead of `css`; set
  `emmet2-css-modules-object` to `"css"` to keep 0.2 output.
- Syntax follows the major mode: `.css` files in `css-mode` are plain CSS, so
  Sass at-rules such as `@use` need `scss-mode` or `<style lang="scss">`.
- Scale and rhythm values such as `p(1)` are opt-in and SCSS-only; set
  `emmet2-css-scale-functions` to `'(("font-size" . "ms") (t . "rhythm"))`
  to keep 0.2 output.
- Pseudo-selectors expand without `&` and rule braces: `:fu` gives `:focus`.
- Emmet's preset values are gone and some short forms changed meaning, such as
  `fs` (now `font-size`) and `lg` (now `list-style: georgian;`); use `bgilg`
  for a linear gradient. Unknown CSS names, values and units no longer expand
  literally; write a project value in brackets, as in `ff[Inter]`.

See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## License

GPL-3.0-or-later. Third-party credits and licenses are in [NOTICE](NOTICE).
