# emmet2-mode

Emmet2-mode is an opinionated enhanced [Emmet](https://emmet.io/) minor mode I have eagerly desired to have in Emacs. Special thanks to [@manateelazycat](https://github.com/manateelazycat) for creating the [deno-bridge](https://github.com/manateelazycat/deno-bridge), which is the key to making this package come true.

Emmet2-mode supports all the features of Emmet but with the following improvements:

- Expanding markup with CSS modules object and JSX class names constructor
- Automatically detecting markup abbreviations (Beta)
- Automatically detecting style tags and attributes in markup and expanding CSS abbreviations within
- Expanding CSS at-rules
- Expanding CSS pseudo selectors
- A lot, a lot of enhancements for Emmet CSS abbreviations

## How it works?

This package has two parts: the elisp front-end and the deno back-end. The frond-end detects abbreviations and syntaxes, sends data to the deno back-end, injects snippets to buffer, re-format code, and re-positions cursor. The back-end expands abbreviations to snippets via the [Emmet NPM package](https://www.npmjs.com/package/emmet) and sends them back to the front-end; it pre-processes abbreviations before Emmet is involved and also modifies the output snippets; this is where the magic happens.

When emmet2-mode is enabled, press `C-j` (which is the default expand key, same as [emmet-mode](https://github.com/smihica/emmet-mode)) to let emmet2-mode detect the abbreviation under the cursor and try to expand it. It uses file extensions to determine syntaxes:

1. `.tsx` and `.jsx` are `JSX` syntax
2. `.scss` and `.css` are `SCSS` syntax (yes, CSS is also treated as `SCSS` syntax)
3. the rest markup files are `HTML` syntax

When editing markup files, emmet2-mode detects if the cursor is in between `<style></style>` tag or `style=""` attribute, if it is, then expands CSS instead. CSS in JS syntax in between `style={{}}` is planned.

The [Solid](https://www.solidjs.com/) JSX syntax is also supported, which is quite the same as the React JSX, both of them use `.tsx` or `.jsx` file extension, but Solid uses `class=` instead of `className=`. To let emmet2-mode work with Solid, you'll need to set `emmet2-markup-variant` to `solid`; see [Custom Options](#custom-options).

## Installation

Emmet2-mode is built on top of the deno-bridge; thus, you need to install it first. Clone deno-bridge and emmet2-mode to your `.emacs.d` folder and add them to your configs. Here is an example of configuring them through [use-package](https://github.com/jwiegley/use-package):

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

If you are not familiar with Emmet, check https://docs.emmet.io/cheat-sheet/ first. New added features are listed below:

### Custom Options

Emmet2-mode has there custom options:

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

_Note: Subcomponent must be capitalised._

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

### Expand CSS

## TODOs

1. [ ] Remove "Indenting region...done" message
2. [ ] Optimise automatically detecting markup abbreviations
3. [ ] Add CSS-in-JS syntax support
4. [ ] Expand class attribute standalone
5. [ ] Maybe other markup syntaxes

## Credits

- [deno-bridge](https://github.com/manateelazycat/deno-bridge)
- [Emmet](https://emmet.io/)
- [emmet-mode](https://github.com/smihica/emmet-mode).
- [VS Code Custom Data](https://github.com/microsoft/vscode-custom-data)
