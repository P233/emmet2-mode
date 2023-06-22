# emmet2-mode

Emmet2-mode is an [Emmet](https://emmet.io/)-enhanced minor mode for Emacs. It is built on top of [Deno](https://deno.com/runtime), [deno-bridge](https://github.com/manateelazycat/deno-bridge) and the [Emmet NPM package](https://www.npmjs.com/package/emmet), delivering the complete set of Emmet functionalities while also integrating a wide array of extra features, such as:

- Expand abbreviation from any character
- Expand JSX class attribute with CSS modules object and class names constructor
- Automatically detect `style={{}}` attribute and then expand CSS in JS
- Automatically detect `<style></style>` tag and `style=""` attribute, then expand CSS
- Expand CSS and SCSS at-rules
- Expand CSS pseudo-selectors
- Numerous enhancements for Emmet CSS abbreviations

The credit goes to [@manateelazycat](https://github.com/manateelazycat) for creating [deno-bridge](https://github.com/manateelazycat/deno-bridge).

## How it works?

This minor mode has two parts: the elisp front-end and the deno back-end. The front-end detects abbreviations and syntax, sends data to the deno back-end, injects snippets into the buffer, reformats code, and repositions the cursor. The back-end expands abbreviations to snippets using the Emmet NPM package and sends them back to the front-end. It preprocesses abbreviations before involving Emmet and modifies the output snippets.

Emmet2-mode detects the abbreviation under the cursor and expands it when you press `C-j` (which is the default expansion key, the same as [emmet-mode](https://github.com/smihica/emmet-mode)). It uses file extensions to determine syntax as follows:

1. `.tsx` and `.jsx` files are considered to have `JSX` syntax.
2. Both `.scss` and `.css` files are considered to have `SCSS` syntax (CSS is treated as `SCSS` syntax).
3. All other markup files are considered to have `HTML` syntax.

When editing markup files, emmet2-mode detects if the cursor is in between a `<style>|</style>` tag or in a `style="|"` attribute, and expands CSS within. It also detects if the cursor is inside a `style={{|}}` JSX attribute and expands CSS in JS.

Additionally, [Solid.js](https://www.solidjs.com/) is supported, which is very similar to React.js. However, Solid.js uses `class=` instead of `className=`. To work with Solid.js, you'll need to set the `emmet2-markup-variant` to `solid`. For more information, refer to the [Custom Options](#custom-options) section.

## Installation

Emmet2-mode is built on top of the [deno-bridge](https://github.com/manateelazycat/deno-bridge); therefore, you will need to install [Deno](https://deno.land/) and deno-bridge as dependencies.

To install Deno, follow the instructions provided in the [official documentation](https://deno.land/manual/getting_started/installation).

To install and configure deno-bridge and emmet2-mode, refer to the following example using [straight.el](https://github.com/radian-software/straight.el) and [use-package](https://github.com/jwiegley/use-package):

```elisp
(use-package deno-bridge
  :straight (:type git :host github :repo "manateelazycat/deno-bridge")
  :init
  (use-package websocket))

(use-package emmet2-mode
  :straight (:type git :host github :repo "p233/emmet2-mode" :files (:defaults "*.ts" "src" "data"))
  :after deno-bridge
  :hook ((web-mode css-mode) . emmet2-mode)                     ;; Enable emmet2-mode for web-mode and css-mode and other major modes based on them, such as the build-in scss-mode
  :config                                                       ;; OPTIONAL
  (unbind-key "C-j" emmet2-mode-map)                            ;; Unbind the default expand key
  (define-key emmet2-mode-map (kbd "C-c C-.") 'emmet2-expand))  ;; Bind custom expand key
```

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

After configuring the custom options, the abbreviation `a.link.active` will be expanded to `<a href="" class={classnames(style.link, style.active)}>|</a>` in this project, where the pipe symbol `|` represents the cursor position after expansion.

### Expand Markups

#### HTML

```
.                             =>   <div class="">|</div>
.class                        =>   <div class="class">|</div>
```

#### React JSX

```
Component                     =>   <Component>|</Component>
Component/                    =>   <Component />
Component./                   =>   <Component className={|} />
Component.class               =>   <Component className={css.class}>|</Component>
Component.Subcomponent        =>   <Component.Subcomponent>|</Component.Subcomponent>
Component.Subcomponent.class  =>   <Component.Subcomponent className={css.class}>|</Component.Subcomponent>
Component.Subcomponent.a.b.c  =>   <Component.Subcomponent className={clsx(css.a, css.b, css.c)}>|</Component.Subcomponent>
Component.Subcomponent.a.b.c/ =>   <Component.Subcomponent className={clsx(css.a, css.b, css.c)} />
Component{{props.value}}      =>   <Component>{props.value}</Component>
```

#### Solid JSX

```
Component.class               =>   <Component class={css.class}>|</Component>
```

#### Automatically detect markup abbreviations

Emmet2-mode allows you to expand abbreviations at any character within them, which can be helpful if you're working on a complex abbreviation and want to make tweaks. However, detecting the correct abbreviation under the cursor can be a bit tricky. If you encounter any issues related to this, please create an issue.

### Expand CSS

#### Remove default color

```
c                =>   color: |;         // instead of color: #000;
bg               =>   background: |;    // instead of background: #000;
```

#### [Modular Scale](https://github.com/modularscale/modularscale-sass) and vertical rhythm functions

Only `fw` triggers the `ms()` function while the other properties will expand with the `rhythm()` function.

```
fz(1)            =>   font-size: ms(1);
```

```
t(2)             =>   top: rhythm(2);
p(1)(2)(3)       =>   padding: rhythm(1) rhythm(2) rhythm(3);
```

#### Custom properties

```
m--gutter        =>   margin: var(--gutter);
p--a--b--c       =>   padding: var(--a) var(--b) var(--c);
```

#### Raw property value brackets

```
p[1px 2px 3px]   =>   padding: 1px 2px 3px;
```

#### Opinionated alias

```
posa =>
position: absolute;
z-index: |;

posa1000 =>
position: absolute;
z-index: 1000;

all =>
top: |;
right: ;
bottom: ;
left: ;

all8 =>
top: 8px;
right: 8px;
bottom: 8px;
left: 8px;

fw2 => font-weight: 200;
fw7 => font-weight: 700;

wf  => width: 100%;
hf  => height: 100%;
```

#### camelCase alias

In Emmet, `:` and `-` are used to separate properties and values. For example, `m:a` expands to `margin: auto;`. However, in emmet2-mode, `:` is designed to expand pseudo-selectors. To avoid this conflict, consider using camelCase instead. For instance, `mA` is equivalent to both `m:a` and `m-a`.

```
mA   => margin: auto;
allA =>
top: auto;
right: auto;
bottom: auto;
left: auto;
```

#### `,` as abbreviations spliter

As a user of the Dvorak keyboard layout, I find it much easier to press the `,` key than the `+` key.

```
t0,r0,b0,l0 === t0+r0+b0+l0
```

#### At rules

To expand CSS at-rules, start with the `@` symbol, followed by two or three distinct letters. SCSS at-rules are also supported.

```
@cs => @charset
@kf => @keyframes
@md => @media

@us => @use "|";
@in => @if not | {}
```

#### Pseudo class and pseudo element

To expand CSS pseudo-classes or pseudo-elements, start with the `:` symbol, followed by two or three distinct letters. When dealing with pseudo-elements, use `:` instead of `::`.

There is a shorthand for pseudo-functions like `:n(:fc)`, which expands to `&:not(:first-child) {|}`, and `:n(:fc,:lc)` expands to `&:not(:first-child):not(:last-child) {|}`. It's important to note that spaces are not allowed within the `()` parentheses.

```
:fu =>
&:focus {
  |
}

_:fu =>
:focus {
  |
}

:hv:af =>
&:hover::after {
  |
}

:n(:fc) =>
&:not(:first-child) {
  |
}

:n(:fc,:lc):be =>
&:not(:first-child):not(:last-child)::before {
  |
}
```

## Credits

- [deno-bridge](https://github.com/manateelazycat/deno-bridge)
- [Emmet](https://emmet.io/)
- [emmet-mode](https://github.com/smihica/emmet-mode).
- [VS Code Custom Data](https://github.com/microsoft/vscode-custom-data)
