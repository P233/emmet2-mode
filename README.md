# emmet2-mode — boost productivity for web-developers

Emmet2-mode is an enhanced Emacs minor mode for [Emmet](https://emmet.io/). The credit goes to [@manateelazycat](https://github.com/manateelazycat) for creating [deno-bridge](https://github.com/manateelazycat/deno-bridge).

It acts as both a pre-processor and a post-processor for Emmet, incorporating all of its features along with several improvements. These include:

- Expand abbreviation from any character
- Expand JSX class attribute with CSS modules object and class names constructor
- Automatically detect `style={{}}` attribute and expand CSS in JS
- Automatically detect `<style></style>` tag and `style=""` attribute and expand CSS
- Expand CSS and SCSS at-rules
- Expand CSS pseudo selectors
- Numerous enhancements for Emmet CSS abbreviations

## How it works?

This package has two parts: the elisp front-end and the deno back-end. The front-end detects abbreviations and syntaxes, sends data to the deno back-end, injects snippets to the buffer, reformats code and re-positions the cursor. The back-end expands abbreviations to snippets via the [Emmet NPM package](https://www.npmjs.com/package/emmet) and sends them back to the front-end. It pre-processes abbreviations before Emmet is involved and modifies the output snippets.

When enabled, emmet2-mode detects the abbreviation under the cursor and expands it when you press `C-j` (which is the default expansion key, same as [emmet-mode](https://github.com/smihica/emmet-mode)). It uses file extensions to determine syntaxes, as follows:

1. `.tsx` and `.jsx` are considered to have `JSX` syntax
2. `.scss` and `.css` are considered to have `SCSS` syntax (even CSS is treated as `SCSS` syntax)
3. all other markup files are considered to have `HTML` syntax

When editing markup files, emmet2-mode detects if the cursor is between `<style>|</style>` tags or in a `style="|"` attribute, and expands CSS withinside. It also detects if the cursor is within `style={{|}}` in JSX and expands CSS in JS.

In addition, Solid JSX syntax is supported, which is very similar to React JSX. Both use `.tsx` or `.jsx` file extensions, but Solid uses `class=` instead of `className=`. To work with Solid, you'll need to set `emmet2-markup-variant` to `solid`. See [Custom Options](#custom-options) for more information.

## Installation

Emmet2-mode is built on top of the deno-bridge; therefore, you need to install [Deno](https://deno.land/) and [deno-bridge](https://github.com/manateelazycat/deno-bridge) first.

To install Deno, follow the instructions provided in the [official document](https://deno.land/manual/getting_started/installation).

After installing Deno, clone deno-bridge and emmet2-mode to your `.emacs.d` folder and add them to your configuration file. Here's an example of how to configure them using [use-package](https://github.com/jwiegley/use-package):

```elisp
(use-package deno-bridge
  :load-path "path/to/deno-bridge"
  :init
  (use-package websocket))

(use-package emmet2-mode
  :after deno-bridge
  :load-path "path/to/emmet2-mode"
  :hook ((web-mode css-mode) . emmet2-mode)                     ;; Enable emmet2-mode for web-mode and css-mode and other major modes based on them, such as the build-in scss-mode
  :config                                                       ;; OPTIONAL
  (unbind-key "C-j" emmet2-mode-map)                            ;; Unbind the default expand key
  (define-key emmet2-mode-map (kbd "C-c C-.") 'emmet2-expand))  ;; Bind custom expand key
```

## Usage

If you're not familiar with Emmet, a great place to begin is by exploring the cheat sheet found at https://docs.emmet.io/cheat-sheet/. New added features are listed below, and see the `test/` folder for more usage examples.

### Custom Options

Emmet2-mode has three custom options:

1. `emmet2-markup-variant`: This option has a single value, `"solid"`. When set, emmet2-mode outputs `class=` instead of `className=`.
2. `emmet2-css-modules-object`: This option allows you to set the CSS Modules object for your project.
3. `emmet2-class-names-constructor`: This option allows you to set the JSX class names constructor for your project.

These options only work for expanding markups, and they are all project-based. If you need to customize any of them, create a `.dir-locals.el` file at the root of your project and add the following code:

```elisp
((web-mode . ((emmet2-markup-variant . "solid")
              (emmet2-css-modules-object . "style")                   ;; Default value is "css"
              (emmet2-class-names-constructor . "classnames"))))      ;; Default value is "clsx"
```

After configuring the custom options in `.dir-locals.el`, `a.link.active` will be expanded to `<a href="" class={classnames(style.link, style.active)}>|</a>` in this project.

Note that the pipe symbol `|` represents the cursor position after expanding abbreviations.

### Expand Markups

#### HTML

```
.      => <div class="">|</div>
.class => <div class="class">|</div>
```

#### React JSX

```
Component                     => <Component>|</Component>
Component/                    => <Component />
Component./                   => <Component className={|} />
Component.class               => <Component className={css.class}>|</Component>
Component.Subcomponent        => <Component.Subcomponent>|</Component.Subcomponent>
Component.Subcomponent.class  => <Component.Subcomponent className={css.class}>|</Component.Subcomponent>
Component.Subcomponent.a.b.c  => <Component.Subcomponent className={clsx(css.a, css.b, css.c)}>|</Component.Subcomponent>
Component.Subcomponent.a.b.c/ => <Component.Subcomponent className={clsx(css.a, css.b, css.c)} />
```

#### Solid JSX

```
Component.class => <Component class={css.class}>|</Component>
```

#### Automatically detect markup abbreviations

Emmet2-mode allows you to expand abbreviations at any character of it, which can be helpful if you're working on a complex abbreviation and want to make tweaks. However, detecting the correct abbreviation under the cursor can be a bit tricky. If you encounter any issues related to this, please create an issue.

### Expand CSS

#### Remove default color

```
c  => color: |;         // instead of color: #000;
bg => background: |;    // instead of background: #000;
```

#### [Modular scale](https://github.com/modularscale/modularscale-sass) and vertical rhythm functions

Only `fw` triggers the `ms()` function while the other properties will expand with the `rhythm()` function.

```
fz(1)      => font-size: ms(1);
```

```
t(2)       => top: rhythm(2);
p(1)(2)(3) => padding: rhythm(1) rhythm(2) rhythm(3);
```

#### Custom properties

```
m--gutter  => margin: var(--gutter);
p--a--b--c => padding: var(--a) var(--b) var(--c);
```

#### Raw property value brackets

```
p[1px 2px 3px] => padding: 1px 2px 3px;
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

Emmet uses `:` and `-` to separate properties and values; for example, `m:a` expands to `margin: auto;`. However, in emmet2-mode, `:` is used to expand pseudo selectors. To avoid this conflict, consider using camelCase. For instance, `mA` is equivalent to `m:a` and `m-a`.

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

To perform an incremental narrowing search for CSS at-rules, use two or three distinct letters, with the first character being `@`. In addition, SCSS at-rules are also supported.

```
@Cs => @charset
@kf => @keyframes
@md => @media

@us => @use "|";
@in => @if not | {}
```

#### Pseudo class and pseudo element

To perform an incremental narrowing search for CSS pseudo classes or pseudo elements, use two or three distinct letters, with the first character being `:`. When dealing with pseudo elements, use `:` instead of `::`.

Additionally, there is a shorthand for pseudo functions such as `:n(:fc)` which expands to `&:not(:first-child) {|}`, while `:n(:fc,:lc)` expands to `^:not(:first-child):not(:last-child) {|}`. It's important to note that spaces are not allowed within the `()` parentheses.

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
