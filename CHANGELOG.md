# Changelog

## v2.0.0 (Unreleased)

emmet2-mode 2.0 is a native Emacs Lisp rewrite. All changes below are relative
to the earlier 0.2 implementation. See
[Upgrading from 0.2](README.md#upgrading-from-02) for the configuration checklist.

### Breaking changes

- Emacs 30 or later is required. Expansion runs entirely in Emacs Lisp; Deno,
  `deno-bridge`, `websocket` and the Emmet npm package are no longer used.
  Remove their configuration, including `:after deno-bridge` in the
  emmet2-mode declaration, and restart Emacs.
- Package recipes need `:files (:defaults "data")`; the `*.ts` and `src`
  entries are no longer needed.
- The `emmet2-expand` command and its `C-j` binding are removed. Abbreviations
  expand when you accept a completion choice; run `emmet2-expand-at-point` to
  insert the first choice directly, or `emmet2-complete` to request choices.
  `emmet2-mode-map` is empty; bind either command yourself.
- The Deno-era functions and variables `emmet2-expand-css`,
  `emmet2-expand-markup`, `emmet2-expand-css-in-js`, `emmet2-detect-*`,
  `emmet2-check-in-between`, `emmet2-after-hook`, `emmet2-file-extension` and
  `emmet2-backend-path` are removed. `emmet2-insert` now takes a snapshot and
  a result; see [API.md](API.md).
- Syntax follows the major mode and surrounding context. A `.css` file in
  `css-mode` is now plain CSS, so Sass at-rules and scale functions need
  `scss-mode`, `<style lang="scss">` or a `.scss` file in web-mode.
- The default `emmet2-css-modules-object` is now `"styles"` instead of `"css"`,
  so `.card` gives `className={styles.card}`. Set it to `"css"` to keep 0.2
  output. `emmet2-class-names-constructor` still defaults to `"clsx"`.
- CSS abbreviations are found by searching a bundled CSS property and value
  catalog instead of Emmet's snippet table:
  - Many short forms now resolve differently. Of Emmet's 226 stock CSS
    abbreviations, 59 give a different property and 9 give no choice. For
    example, `fs` is `font-size` (was `font-style`), `bdr` and `rs` are
    `border-radius` (were `border-right` and `resize`), `f` is `float` (was
    `font`), `fd` is `flex-direction` (was `font-display`), `ga` is `gap` (was
    `grid-area`), `ws` is `white-space` (was `word-spacing`), `wm` is
    `width: max-content;` (was `writing-mode`), `ap` is `animation: paused;`
    (was `appearance: none;`) and `b-n` is `border: none;` (was
    `bottom: none;`). `gg`, `grg`, `gcg`, `pgba`, `pgbb` and `ffv` give no
    choice. Most old readings remain completion choices, and full property
    names always work.
  - Emmet's preset values are gone: `us` gives `user-select: ;` (was
    `user-select: none;`), `zom` gives `zoom: ;` (was `zoom: 1;`) and `bgi`
    gives `background-image: ;` (was `background-image: url();`). Type the
    value as part of the query instead, as in `usn`, `zom1` or `bgi[url()]`.
  - Value presets are gone too, and their old abbreviations now mean something
    else: `lg` gives `list-style: georgian;`, `cr` gives `clear: right;` and
    `qen` gives `quotes: none;`. Use combined property/value queries instead:
    `bgilg` gives `background-image: linear-gradient();` and `crgb` gives
    `color: rgb();`.
  - Unknown property, at-rule and pseudo names, value words and units offer no
    choice instead of expanding literally: `ff-inter` and `w10zz` give nothing.
    Write a project value in brackets, as in `ff[Inter]`.
  - Comma-separated value presets such as font stacks are not offered;
    `font-family` offers generic families such as `sans-serif` and `monospace`.
- Pseudo completion inserts only the selector: `:fu` gives `:focus` instead of
  `&:focus { }`. No `&` and no rule braces are added; type them yourself.
  `:is()` and other functions keep comma-separated lists, as in
  `:is(:focus, :hover)`, while `:not()` still becomes chained calls.
- `allu` and `all[unset]` give the real `all: unset;` instead of four
  `top`/`right`/`bottom`/`left` declarations; other values, as in `all8`, keep
  the four-side alias.
- Scale and rhythm values such as `p(1)` and `fz(1)` are opt-in through
  `emmet2-css-scale-functions`, and apply only to SCSS.

### Added

- Complete declaration expansions alone on a line in CSS/SCSS modes now
  continue on an indented next line, reusing an immediately following blank
  line. Expansion and continuation undo together. Empty fields, embedded
  styles, value completion and lines shared with code or comments retain
  their cursor behavior. Set `emmet2-css-auto-newline` to `nil` to disable it.
- Abbreviations appear as completion choices while you type, with full
  previews through `corfu-popupinfo-mode` and one undo that restores the
  abbreviation.
- CSS completion offers up to ten ranked choices. Property names are found by
  initials and word fragments (`bgc`, `ins32`), and a query can combine a
  property and a keyword (`tac`). Value search includes keywords inherited
  from a property's value types.
- Property values complete fuzzily with documentation, and accepting a function
  places point inside its parentheses. In built-in CSS modes such as
  `css-mode`, this replaces css-mode's own value list for known properties.
- Inside rules such as `@font-face`, abbreviations offer that rule's
  descriptors and their values.
- CSS support covers every `css-base-mode` descendant, including `css-ts-mode`
  and `less-css-mode`.
- In CSS, a known element followed by a pseudo, as in `button:hv`, completes as
  a nested selector. Selector lists, attributes and combinators are preserved.
  An element followed by a comma, as in a `th,` selector-list line, is not
  offered automatically, so RET keeps the selector.
- Automatic markup completion recognizes distinctive abbreviations and
  standalone tags such as `div` alone on a line.
- HTML and JSX fields become yasnippet fields with TAB navigation and mirrors
  when yasnippet is installed; it is enabled when fields are first needed.
- With Corfu, Emmet choices stay plain text next to icon margins such as
  kind-icon or nerd-icons-corfu, and a sole Emmet choice stays in the popup
  whatever `corfu-on-exact-match` is.
- Choices also appear under Company through standard completion-at-point.
  Accepting a function value such as `calc()` there leaves point after the
  parentheses, and a buffer that is really read-only lists choices but refuses
  to insert one.
- `emmet2-css-in-js-attributes` and `emmet2-css-in-js-functions` add style-object
  hosts such as `sx={{...}}` or `css({...})`.
- A leading `_` keeps an abbreviation's JSX classes as a string, as in `_.a.b`
  for `className="a b"`. `emmet2-jsx-class-style` set to `plain` does this for
  a whole project.
- Public [library and host APIs](API.md) for CSS data, matching and expansion.
  Other major modes, such as scss2-mode, can supply their own syntax context
  through `emmet2-context-provider`.

### Changed

- Markup puts point in the first empty attribute: `a.link` starts in `href`
  instead of the element content.
- An empty JSX class, as in `.`, `div.` or `Component./`, gives an editable
  CSS Modules key, `className={styles["│"]}`, instead of `className={│}`.

### Fixed

- Numeric properties stay unitless: `order1` gives `order: 1;`, and
  `column-count2`, `grid-row-start2` and `fill-opacity.5` expand to those
  properties instead of being split, as in `column: count 2px;`.
- 4- and 8-digit hex colors are kept: `c#ffffff80` gives `color: #ffffff80;`
  instead of `color: #fff;`.
- A trailing `!` on `posa` or `posf` makes both `position` and `z-index`
  `!important`, not only `z-index`.
- Expanding a declaration before an existing semicolon reuses it: `m10│;`
  gives `margin: 10px;` instead of `margin: 10px;;`.
- CSS-in-JS raw values with leading zeros stay strings: `p[010px]` gives
  `padding: "010px"` instead of `padding: 010`.
- Hyphenated JSX classes use bracket access: `.btn-primary` gives
  `styles["btn-primary"]` instead of the invalid `css.btn-primary`.
- React JSX writes `htmlFor` for `for`.
