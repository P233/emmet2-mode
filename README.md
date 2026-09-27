# emmet2-mode

Emmet2-mode expands [Emmet](https://emmet.io/) abbreviations in Emacs. The native
front-end now analyzes the host buffer, renders structured fields and inserts
atomically. A bundled Node backend is temporary while the pure Emacs Lisp
engine is being implemented. Features include:

- Expand abbreviation from any character
- Expand JSX class attribute with CSS modules object and class names constructor
- Automatically detect `style={{}}` attribute and then expand CSS in JS
- Automatically detect `<style></style>` tag and `style=""` attribute, then expand CSS
- Expand CSS and SCSS at-rules
- Expand CSS pseudo-selectors
- Numerous enhancements for Emmet CSS abbreviations

## How it works

Press `C-j` (`emmet2-expand`) anywhere inside an abbreviation. Analysis uses the
major mode and actual host syntax. CSS/SCSS and web-mode HTML/CSS work without
tree-sitter grammars; JS/TS/JSX contexts require the matching installed grammar.
Confirmed comments, strings and unrelated JavaScript expressions are excluded.
An unsupported major mode retains explicit markup expansion.

web-mode supports style attributes/blocks, JSX style objects and the named
`StyleSheet.create` / `createTheme` contexts. TSX and JavaScript modes use the
same context rules. Set `emmet2-markup-variant` to `"solid"` for Solid JSX.
Project options also work in buffers without a file name.

Layout comes from the major mode's indentation width and the abbreviation's
display column. Literal tabs in authored text remain literal. The rendered
result is inserted once; it is not passed through `indent-region` afterward.
Only a still-valid source snapshot can be replaced, and failures roll back.

## Installation

The current transition release requires **Emacs 30 or later** and **Node 24**
on Emacs's `exec-path`. Deno, deno-bridge, websocket and `npm install` are no
longer needed to run the mode. The bundled Emmet runtime and data must be
included in the installation. Restart Emacs after upgrading from the old
Deno release so its already-loaded bridge and callbacks are retired.

Example using straight.el and use-package:

```elisp
(use-package emmet2-mode
  :straight (:type git :host github :repo "p233/emmet2-mode"
             :files (:defaults "*.mjs" "vendor" "data"))
  :hook ((web-mode css-mode tsx-ts-mode) . emmet2-mode)
  :config
  ;; Optional alternative key:
  (unbind-key "C-j" emmet2-mode-map)
  (define-key emmet2-mode-map (kbd "C-c C-.") #'emmet2-expand))
```

Enable `yas-minor-mode` separately for editable fields and mirrors. Without
it, expansion produces the same text and first-field cursor.
Actual packaged-installation and GUI acceptance remain the next milestone.

### Completion

The mode registers a buffer-local completion-at-point function. The candidate
is the original abbreviation; its annotation summarizes the expansion.
Accepting a current candidate expands it through the same insertion path as
`C-j`. Bare markup identifiers (including tag names), bare CSS property names,
and unconfirmed host positions are left to other completion providers. Use
`C-j` for explicit expansion, or `M-x emmet2-complete` to request only Emmet
completion with the same confidence gate.

Corfu is optional. Automatic presentation respects your Corfu prefix, delay
and trigger settings. With the default `basic`-first completion styles, the
single candidate can remain visible for all exact-match policies. With
`partial-completion` first, or an `emmet2` category override selecting it,
automatic completion skips the exact candidate unless your persistent
`corfu-on-exact-match` is `show`; manual completion may immediately expand it.
The mode changes none of these settings. With `corfu-preselect` set to `prompt`,
select the candidate before accepting it; accepting the prompt keeps the
abbreviation unchanged. Editing or moving away ends an obsolete session.
For the full colored expansion beside Corfu's candidate popup, enable the
optional `corfu-popupinfo-mode` separately. The documentation shows the same
final text that acceptance inserts, including project JSX/Solid options.
The package does not enable Corfu, popupinfo or yasnippet for you.

### Field behavior after upgrading

Point now starts at the **first editable field**, such as an anchor's `href`,
then TAB visits independent fields when yasnippet is enabled. For `c+bg` or
`m+p`, the two values are separate stops; `bd` has one stop. Repeated markup
fields remain mirrors. The final TAB exits at the expansion's text end.
One undo restores the original abbreviation.

Only Emmet snippets suppress yasnippet's extra newline for an EOF field and
web-mode's automatic reindent-on-exit. Other snippets and user exit hooks
retain their behavior. Text and defaults containing dollars, backslashes,
backticks or braces remain literal; they are not evaluated as Lisp.

## Usage

If you're not familiar with Emmet, a great place to start is by exploring the cheat sheet found at https://docs.emmet.io/cheat-sheet/. New added features are listed below, and see the `test/` folder for more usage examples.

### Custom Options

Emmet2-mode has three custom options:

1. `emmet2-markup-variant`: This option has a single value, `"solid"`. When set, emmet2-mode outputs `class=` instead of `className=`.
2. `emmet2-css-modules-object`: This option allows you to set the CSS Modules object for your project.
3. `emmet2-class-names-constructor`: This option allows you to set the JSX class names constructor for your project.

All these options work for expanding markups only, and they are project-based. If you need to customize any of them, create a `.dir-locals.el` file at the root of your project and add the following code:

```elisp
((web-mode . ((emmet2-markup-variant . "solid")
              (emmet2-css-modules-object . "style")                   ;; Default value is "css"
              (emmet2-class-names-constructor . "classnames"))))      ;; Default value is "clsx"
```

After configuring the custom options, the abbreviation `a.link.active` will be expanded to `<a href="|" class={classnames(style.link, style.active)}></a>` in this project, where the pipe symbol `|` represents the cursor position after expansion.

### Expand Markups

#### HTML

```
.                             ->  <div class="|"></div>
.class                        ->  <div class="class">|</div>
```

#### React JSX

```
Component                     ->  <Component>|</Component>
Component/                    ->  <Component />
Component./                   ->  <Component className={|} />
Component.class               ->  <Component className={css.class}>|</Component>
Component.Subcomponent        ->  <Component.Subcomponent>|</Component.Subcomponent>
Component.Subcomponent.class  ->  <Component.Subcomponent className={css.class}>|</Component.Subcomponent>
Component.Subcomponent.a.b.c  ->  <Component.Subcomponent className={clsx(css.a, css.b, css.c)}>|</Component.Subcomponent>
Component.Subcomponent.a.b.c/ ->  <Component.Subcomponent className={clsx(css.a, css.b, css.c)} />
Component{{props.value}}      ->  <Component>{props.value}</Component>
```

#### Solid JSX

```
Component.class               ->  <Component class={css.class}>|</Component>
```

#### Automatically detect markup abbreviations

Emmet2-mode allows you to expand abbreviations at any character within them, which can be helpful if you're working on a complex abbreviation and want to make tweaks. However, detecting the correct abbreviation under the cursor can be a bit tricky. If you encounter any issues related to this, please create an issue.

### Expand CSS

#### Remove default color

```
c               ->  color: |;         // instead of color: #000;
bg              ->  background: |;    // instead of background: #000;
```

#### [Modular Scale](https://github.com/modularscale/modularscale-sass) and vertical rhythm functions

Only `fw` triggers the `ms()` function while the other properties will expand with the `rhythm()` function.

```
fz(1)           ->  font-size: ms(1);
```

```
t(2)            ->  top: rhythm(2);
p(1)(2)(3)      ->  padding: rhythm(1) rhythm(2) rhythm(3);
```

#### Custom properties

```
m--gutter       ->  margin: var(--gutter);
p--a--b--c      ->  padding: var(--a) var(--b) var(--c);
```

#### Raw property value brackets

```
p[1px 2px 3px]  ->  padding: 1px 2px 3px;
```

#### Opinionated alias

```
posa ->
position: absolute;
z-index: |;

posa1000  ->
position: absolute;
z-index: 1000;

all  ->
top: |;
right: ;
bottom: ;
left: ;

all8 ->
top: 8px;
right: 8px;
bottom: 8px;
left: 8px;

fw2  ->  font-weight: 200;
fw7  ->  font-weight: 700;

wf   ->  width: 100%;
hf   ->  height: 100%;
```

#### camelCase alias

In Emmet, `:` and `-` are used to separate properties and values. For example, `m:a` expands to `margin: auto;`. However, in emmet2-mode, `:` is designed to expand pseudo-selectors. To avoid this conflict, consider using camelCase instead. For instance, `mA` is equivalent to both `m:a` and `m-a`.

```
mA   ->  margin: auto;
allA ->
top: auto;
right: auto;
bottom: auto;
left: auto;
```

#### Comma as abbreviations spliter

As a user of the Dvorak keyboard layout, I find it much easier to press the `,` key than the `+` key.

```
t0,r0,b0,l0 == t0+r0+b0+l0
```

#### At rules

To expand CSS at-rules, start with the `@` symbol, followed by two or three distinct letters. SCSS at-rules are also supported.

```
@cs  ->  @charset
@kf  ->  @keyframes
@md  ->  @media

@us  ->  @use "|";
@in  ->  @if not | {}
```

#### Pseudo-class and pseudo-element

To expand CSS pseudo-classes or pseudo-elements, start with the `:` symbol, followed by two or three distinct letters. When dealing with pseudo-elements, use `:` instead of `::`.

There is a shorthand for pseudo-functions like `:n(:fc)`, which expands to `&:not(:first-child) {|}`, and `:n(:fc,:lc)` expands to `&:not(:first-child):not(:last-child) {|}`. It's important to note that spaces are not allowed within the `()` parentheses.

```
:fu  ->
&:focus {
  |
}

_:fu  ->
:focus {
  |
}

:hv:af  ->
&:hover::after {
  |
}

:n(:fc)  ->
&:not(:first-child) {
  |
}

:n(:fc,:lc):be  ->
&:not(:first-child):not(:last-child)::before {
  |
}

:nc(2n-1)  ->
&:nth-child(2n-1) {
  |
}
```

## Credits

- [deno-bridge](https://github.com/manateelazycat/deno-bridge)
- [Emmet](https://emmet.io/)
- [emmet-mode](https://github.com/smihica/emmet-mode).
- [VS Code Custom Data](https://github.com/microsoft/vscode-custom-data)
