# emmet2-mode — boost productivity for web-developers

Emmet2-mode is an opinionated enhanced [Emmet](https://emmet.io/) minor mode I have eagerly desired to have in Emacs. Special thanks to [@manateelazycat](https://github.com/manateelazycat) for creating the [deno-bridge](https://github.com/manateelazycat/deno-bridge), which is the key to making this package come true.

Emmet2-mode is both of a pre-processor and a post-processor for Emmet. It supports all the features of Emmet but with the following improvements:

- Expanding abbreviations from any character of it
- Expanding JSX class attribute with CSS modules object and class names constructor
- Automatically detecting `style={{}}` attribute and expanding CSS in JS withinside
- Automatically detecting `<style></style>` tag and `style=""` attribute and expanding CSS withinside
- Expanding CSS and SCSS at-rules
- Expanding CSS pseudo selectors
- A lot, a lot of enhancements for Emmet CSS abbreviations

## How it works?

This package has two parts: the elisp front-end and the deno back-end. The frond-end detects abbreviations and syntaxes, sends data to the deno back-end, injects snippets to buffer, re-format code, and re-positions cursor. The back-end expands abbreviations to snippets via the [Emmet NPM package](https://www.npmjs.com/package/emmet) and sends them back to the front-end; it pre-processes abbreviations before Emmet is involved and also modifies the output snippets; this is where the magic happens.

When emmet2-mode is enabled, press `C-j` (which is the default expand key, same as [emmet-mode](https://github.com/smihica/emmet-mode)) to let emmet2-mode detect the abbreviation under the cursor and try to expand it. It uses file extensions to determine syntaxes:

1. `.tsx` and `.jsx` are `JSX` syntax
2. `.scss` and `.css` are `SCSS` syntax (yes, CSS is also treated as `SCSS` syntax)
3. the rest markup files are `HTML` syntax

When editing markup files, emmet2-mode detects if the cursor is in between `<style></style>` tag or `style=""` attribute and expands CSS withinside; or detects if the cursor is in between `style={{}}` in JSX, and expands CSS in JS. CSS in JS only works in the JSX `style` attribute.

[Solid](https://www.solidjs.com/) JSX syntax is also supported, which is quite the same as the React JSX, both of them use `.tsx` or `.jsx` file extension, but Solid uses `class=` instead of `className=`. To let emmet2-mode work with Solid, you'll need to set `emmet2-markup-variant` to `solid`; see [Custom Options](#custom-options).

## Installation

Emmet2-mode is built on top of the deno-bridge; thus, you need to install Deno and deno-bridge first.

1. Follow the [official document](https://deno.land/manual/getting_started/installation) to install Deno.

2. Clone deno-bridge and emmet2-mode to your `.emacs.d` folder and add them to your configs. Here is an example of configuring them through [use-package](https://github.com/jwiegley/use-package):

```elisp
(use-package deno-bridge
  :load-path "path/to/deno-bridge")

(use-package emmet2-mode
  :after deno-bridge
  :load-path "path/to/emmet2-mode"
  :hook ((web-mode css-mode) . emmet2-mode)                     ;; Enable emmet2-mode for web-mode and css-mode and other major modes based on them, such as the build-in scss-mode
  :config                                                       ;; OPTIONAL
  (unbind-key "C-j" emmet2-mode-map)                            ;; Unbind the default expand key
  (define-key emmet2-mode-map (kbd "C-c C-.") 'emmet2-expand))  ;; Bind custom expand key
```

## Usage

If you are not familiar with Emmet, check https://docs.emmet.io/cheat-sheet/ first. New added features are listed below, and see the `test/` folder for more deatils.

### Custom Options

Emmet2-mode has three custom options:

1. `emmet2-markup-variant` the only value is `"solid"`, let emmet2-mode output `class=` instead of `className=`
2. `emmet2-css-modules-object` set the CSS Modules object convention for your project
3. `emmet2-class-names-constructor` set the JSX class names constructor convention for your project

They only work for expanding markups, and all of them are project-based. So, if you need to custom any one of them, create a `.dir-locals.el` file at the root of your project, and add the following code:

```elisp
((web-mode . ((emmet2-markup-variant . "solid")
              (emmet2-css-modules-object . "style")                   ;; Default value is "css"
              (emmet2-class-names-constructor . "classnames"))))      ;; Default value is "clsx"
```

After that, `a.link.active` will be expanded to `<a href="" class={classnames(style.link, style.active)}>|</a>` in this project.

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

You are able to expand at any position of the abbreviation; this is helpful if you are working on a super complex abbr and want to tweak something. However, it's a bit tricky to detect the correct abbr. If you encounter any issues with regard to this, please fill an issue.

### Expand CSS

#### Remove default color

```
c  => color: |;         // instead of color: #000;
bg => background: |;    // instead of background: #000;
```

#### [Modular scale](https://github.com/modularscale/modularscale-sass) and vertical rhythm functions

Only `fw` triggers the `ms()` function, the other properties will expand with the `rhythm()` function.

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

Emmet use `:` and `-` for separating property and value; for example `m:a` expands `margin: auto;`. But emmet2-mode use `:` for expanding pseudo selectors. So, why not use camelCase? `mA` is now equal to `m:a` and `m-a`.

```
mA   => margin: auto;
allA =>
top: auto;
right: auto;
bottom: auto;
left: auto;
```

#### `,` as abbreviations spliter

As a Dvorak keybord layout user, `,` is much more easier to press than `+`.

```
t0,r0,b0,l0 === t0+r0+b0+l0
```

#### At rules

Use two or three unique letters to do an incremental narrowing search for CSS at-rules. The first character must be `@`. SCSS at-rules are also supported.

```
@cs => @charset
@kf => @keyframes
@md => @media

@us => @use "|";
@in => @if not | {}
```

#### Pseudo class and pseudo element

Use two or three unique letters to do an incremental narrowing search for pseudo classes or pseudo elements. The first two characters must be a `:` and the leading letter of your target pseudo selector. For pseudo elements, use `:` rather than `::`.

There is also a shorthand for pseudo functions, for example, `:n(:fc)` expands `&:not(:first-child) {|}`, and `:n(:fc,:lc)` expands `^:not(:first-child):not(:last-child) {|}`. Please note that space is not allowed in between `()`.

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
