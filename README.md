# emmet2-mode

emmet2-mode brings [Emmet](https://emmet.io/) abbreviations to Emacs as
completion choices for HTML, JSX, CSS, SCSS and CSS-in-JS. Type `ul>li*3`,
`.card.active` or `m10,p.5`, accept a choice, and the abbreviation becomes code.

emmet2-mode 2.0 is a rewrite in Emacs Lisp. It needs no Deno, deno-bridge,
websocket or Emmet npm package, and abbreviations expand when you accept a
completion choice instead of on `C-j`. To upgrade from 0.2, see
[Upgrading from 0.2](#upgrading-from-02).

## Supported modes

- CSS and SCSS in every mode derived from `css-base-mode`, such as `css-mode`,
  `scss-mode`, `css-ts-mode` and `less-css-mode` (Less is treated as CSS).
- HTML in `web-mode` (a separate package), including `<style>` blocks,
  `style=""` attributes and script parts.
- JSX and style objects in `js-mode`, `js-ts-mode`, `tsx-ts-mode` and web-mode
  JSX files; `typescript-ts-mode` offers style objects only.
- In other modes, such as `text-mode` or `mhtml-mode`, only the commands below
  work, and they treat all text as markup, even `<style>` blocks in
  `mhtml-mode`.

## Installation

emmet2-mode requires Emacs 30.1 or later and runs no external program. With
straight.el and use-package:

```elisp
(use-package emmet2-mode
  :straight (emmet2-mode :type git :host github :repo "P233/emmet2-mode"
                         :files (:defaults "data"))
  :hook ((web-mode css-base-mode js-base-mode typescript-ts-base-mode) . emmet2-mode))
```

The `data` directory must be installed next to the Lisp files. From a plain
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

To check the installation, open a `.css` file, type `.a { m10 }`, put point
after `m10` and run `M-x emmet2-expand-at-point`; it becomes
`.a { margin: 10px; }`.

JavaScript, TypeScript and JSX need Emacs built with Tree-sitter and the
matching grammar: `javascript` for `js-mode`, `js-ts-mode` and web-mode
JavaScript, `typescript` for `typescript-ts-mode` and web-mode TypeScript, and
`tsx` for `tsx-ts-mode` and web-mode JSX and TSX. HTML and CSS need no grammar.
Tested revisions are in [test/dependencies.json](test/dependencies.json).

### Completion frontend

[Corfu](https://github.com/minad/corfu) is the supported completion frontend.
emmet2-mode needs no Corfu setting and changes none of yours.
`corfu-popupinfo-mode` previews multi-line expansions in full:

```elisp
(use-package corfu
  :straight t
  :hook ((web-mode css-base-mode js-base-mode typescript-ts-base-mode) . corfu-mode)
  :custom (corfu-auto t)
  :config (corfu-popupinfo-mode 1))
```

Corfu's automatic completion waits for three characters by default
(`corfu-auto-prefix`);
for short abbreviations such as `d`, `ta` or `@f`, lower it or request
completion manually.

[Company](https://github.com/company-mode/company-mode) works through standard
completion-at-point; after Company accepts a function value such as `calc()`,
point stays after the parentheses, where Corfu places it inside.

With Emacs's default completion UI and styles, `completion-at-point` first
reports "Complete, but not unique"; repeat it to list the choices in
`*Completions*`.

In a read-only buffer, choices can be listed, but accepting one is refused.

With [yasnippet](https://github.com/joaotavora/yasnippet) installed, TAB
visits the remaining HTML and JSX fields; emmet2-mode enables `yas-minor-mode`
when a snippet needs it. Without yasnippet you get the same text and starting
point.

## Usage

Type an abbreviation, with point anywhere inside it, and accept a choice. One
undo restores the abbreviation.

- In HTML and JSX, type in markup content. Automatic completion offers a bare
  word only when it is a known element alone on its line, such as `div`.
- In CSS and SCSS, type at the start of a declaration inside braces.
  Pseudo-classes, pseudo-elements and at-rules also work at the stylesheet root.
- `<style>` and `style=""` produce CSS. JSX `style={{...}}` and objects passed
  to `StyleSheet.create(...)` or `createTheme(...)` produce camelCase
  properties and JavaScript values.
- Comments and strings are skipped.

CSS offers up to ten choices: `ta` offers `text-align: ;`, its keywords, then
alternatives such as `top: auto;`. For `ovh,ta`, the menu shows the property
being typed, and accepting also inserts `overflow: hidden;`.

Markup starts in the first empty field, such as `href` in `a.link`. CSS starts
no snippet: `d` leaves point in `display: │;`, and TAB keeps your binding. In
CSS and SCSS modes, a complete declaration alone on its line, such as `m10`,
continues on a new line with the same indentation; set `emmet2-css-auto-newline`
to `nil` to stay put.

### Commands

emmet2-mode binds no keys. `M-x emmet2-complete` requests choices explicitly,
even without the minor mode, and `M-x emmet2-expand-at-point` inserts the first
choice at once. To bind them:

```elisp
(with-eval-after-load 'emmet2-mode
  (keymap-set emmet2-mode-map "C-c ." #'emmet2-complete)
  (keymap-set emmet2-mode-map "C-j" #'emmet2-expand-at-point))
```

### CSS value completion

In built-in CSS modes, values after a property's colon match fuzzily, as in
`display: if` for `inline-flex`, with a short description that
`corfu-echo-mode` shows. This replaces css-mode's own value list for known
properties; when no value matches, other completion functions such as Eglot's
still run. To keep css-mode's list:

```elisp
(add-hook 'emmet2-mode-hook
          (lambda ()
            (remove-hook 'completion-at-point-functions #'emmet2-css-value-capf t)))
```

## Abbreviations

Markup follows the [Emmet cheat sheet](https://docs.emmet.io/cheat-sheet/). `│`
marks where point ends; results with several declarations insert one per line.

| Context | Abbreviation | Result |
| --- | --- | --- |
| HTML | `a.link` | `<a href="│" class="link"></a>` |
| JSX | `.card.active` | `<div className={clsx(styles.card, styles.active)}>│</div>` |
| JSX | `_.card.active` | `<div className="card active">│</div>` |
| JSX | `Component.card/` | `<Component className={styles.card} />` |
| CSS | `m10,p.5` or `m10+p.5` | `margin: 10px; padding: 0.5rem;` |
| CSS | `tac`, `dN`, `bgc` | `text-align: center;`, `display: none;`, `background-color: │;` |
| CSS | `p1-2`, `m10--20` | `padding: 1px 2px;`, `margin: 10px -20px;` |
| CSS | `w50p`, `p1r`, `lh1.5` | `width: 50%;`, `padding: 1rem;`, `line-height: 1.5;` |
| CSS | `m--gutter!` | `margin: var(--gutter) !important;` |
| CSS | `ff[Inter]`, `w[calc(100% - 2rem)]` | `font-family: Inter;`, `width: calc(100% - 2rem);` |
| CSS | `posa1000` | `position: absolute; z-index: 1000;` |
| SCSS | `m$gutter` | `margin: $gutter;` |
| Style object | `m10+p.5` | `margin: 10, padding: "0.5rem"` |
| Selector | `&::be`, `:n(:fc)` | `&::before`, `:not(:first-child)` |
| At-rule | `@md`; in SCSS, `@us` | `@media │`; `@use "│";` |

- In JSX, classes use the CSS Modules object `styles` and join with `clsx`; add
  the imports yourself. Hyphenated names use brackets, as in
  `styles["btn-primary"]`. A leading `_` keeps the classes a plain string.
- In CSS, properties are found by initials and word fragments; an uppercase
  letter starts the value explicitly, as in `mA`. Integers get `px` and decimals
  `rem`; zero and numeric properties such as `line-height` and `order` stay
  unitless. Suffix `r`, `e` or `p` for `rem`, `em` or `%`, and `!` for
  `!important`. Unknown names, values and units offer no choice; put project
  values in brackets. A colon starts a pseudo-class, so write `dn`, not `d:n`.
- In style objects, unitless and pixel values become numbers, others strings.
  A trailing comma ends the member, so `m10,` offers nothing; join with `+`.

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `emmet2-jsx-class-style` | `css-modules` | `css-modules` references, or `plain` class strings |
| `emmet2-css-modules-object` | `"styles"` | CSS Modules object reference, such as `cardStyles` |
| `emmet2-class-names-constructor` | `"clsx"` | Function joining several classes, such as `cx` |
| `emmet2-markup-variant` | `nil` | `"solid"` writes Solid JSX, with `class`, in every markup context, HTML included |
| `emmet2-css-in-js-attributes` | `("style")` | JSX attributes holding style objects, such as `"sx"` |
| `emmet2-css-in-js-functions` | `("StyleSheet.create" "createTheme")` | Functions whose object arguments hold styles, such as `"css"` |
| `emmet2-css-scale-functions` | `nil` | SCSS functions for `(N)` values; see below |
| `emmet2-css-auto-newline` | `t` | In CSS and SCSS modes, continue on a new line after a standalone declaration |

All options are safe as directory-local variables. For example, in
`.dir-locals.el`:

```elisp
((tsx-ts-mode . ((emmet2-markup-variant . "solid")
                 (emmet2-css-modules-object . "cardStyles")
                 (emmet2-class-names-constructor . "cx"))))
```

Then `.card.active` gives
`<div class={cx(cardStyles.card, cardStyles.active)}>│</div>`.

With `emmet2-css-scale-functions` set to
`'(("font-size" . "ms") (t . "rhythm"))`, SCSS `fz(1)` gives
`font-size: ms(1);` and `p(0)(2)` gives `padding: 0 rhythm(2);`. Your
stylesheet build must provide the functions, for example from
[rhythm-sass](https://github.com/P233/rhythm-sass).

## Troubleshooting

- If no choice appears, check [where abbreviations work](#usage) and Corfu's
  prefix threshold, then try `M-x emmet2-complete`, which reports errors. For
  another style object, add its attribute or function to
  `emmet2-css-in-js-attributes` or `emmet2-css-in-js-functions`.
- `M-x emmet2-complete` reports a missing grammar, as in
  `Missing tree-sitter grammar: javascript`. Install it with
  `M-x treesit-install-language-grammar`.

## With scss2-mode

[scss2-mode](https://github.com/P233/scss2-mode) provides Tree-sitter major
modes for CSS and SCSS and requires Emacs 31.1 or later. It uses emmet2-mode for
declaration abbreviations, so `emmet2-mode` need not be enabled in its buffers,
and completes values, pseudo-selectors, at-rules and Sass variables, functions,
mixins and module members itself. Other major modes can supply their own context
the same way; see [API.md](API.md).

## Upgrading from 0.2

- Emacs 30.1 or later is required.
- Remove the Deno, `deno-bridge` and `websocket` configuration, including
  `:after deno-bridge` in the emmet2-mode declaration, and restart Emacs.
- Replace `:files (:defaults "*.ts" "src" "data")` with
  `:files (:defaults "data")`.
- `emmet2-expand` and its `C-j` binding are gone. Bind `emmet2-expand-at-point`
  or `emmet2-complete` yourself.
- The default CSS Modules object is now `styles`; set
  `emmet2-css-modules-object` to `"css"` to keep 0.2 output.
- Syntax follows the major mode: `css-mode` is plain CSS, so Sass at-rules such
  as `@use` need `scss-mode` or `<style lang="scss">`.
- Scale and rhythm values such as `p(1)` are opt-in and SCSS-only; set
  `emmet2-css-scale-functions` to `'(("font-size" . "ms") (t . "rhythm"))` to
  keep 0.2 output.
- Pseudo-selectors expand without `&` and rule braces: `:fu` gives `:focus`.
- Emmet's preset values are gone and some short forms changed meaning, such as
  `fs` (now `font-size`) and `lg` (now `list-style: georgian;`); use `bgilg` for
  a linear gradient. Unknown names, values and units no longer expand
  literally.

See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## License

GPL-3.0-or-later. Third-party credits and licenses are in [NOTICE](NOTICE).
