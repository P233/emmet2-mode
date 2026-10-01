# Changelog

## v2.0.0 (Unreleased)

The native Emacs Lisp implementation is being prepared as v2.0.0. All changes
below belong to this release and are relative to the earlier 0.2 implementation.

### Architecture and completion correctness

- CSS completion retains resolved property identities through rendering. CSS and
  JavaScript output share declarations, with fields emitted at their final offsets.
- Project options and buffer-aware expansion live in `emmet2-expand`; loading CAPF
  does not require minor-mode registration. Public expansion names remain available.
- React labels use `htmlFor`; empty JSX class fields start an editable CSS Modules
  key. Solid retains `class` and `for`. Invalid required references and raw non-Unicode
  class bytes report domain errors.
- Automatic errors expire the completion table; explicit requests and acceptance
  report the cause. Provider callbacks restore point and narrowing. Web script/style
  parts share exclusive endpoints, and standalone `.scss` files retain Sass syntax.

### Breaking changes

- Emacs 30 or later is required. Expansion runs entirely in Emacs Lisp;
  Deno, `deno-bridge`, `websocket` and the Emmet npm package are no longer used.
  Remove their configuration and restart Emacs after upgrading.
- `emmet2-expand` and its default `C-j` binding are removed. Accept a completion
  choice instead, through `completion-at-point` or a frontend such as Corfu.
  `emmet2-complete` requests Emmet choices and respects the frontend's popup
  and sole-match settings. `emmet2-mode-map` is empty; bind the command yourself
  if you want a dedicated key.
- Package recipes need `:files (:defaults "data")`; the `*.ts` and `src`
  entries are no longer needed.
- Syntax follows the major mode and surrounding context instead of the file
  extension. Plain CSS hosts offer CSS at-rule names; `scss-mode` and
  `<style lang="scss">` also offer Sass templates.
- CSS abbreviations use a bundled property/value catalog instead of Emmet's
  CSS snippet table:
  - Properties have no default values: `d` is `display: ;` and `c` is `color: ;`.
  - Value presets such as `lg`, `cr`, `qen` and `qru` are replaced by combined
    property/value queries: `bgilg` gives `background-image: linear-gradient();`
    and `crgb` gives `color: rgb();`. Use brackets for literal values, such as `q[none]`.
  - Some short forms rank differently: `fs` prefers `font-size` and `bdr`
    prefers `border-radius`. Other readings remain completion choices.
- Pseudo completion inserts names and editable function arguments, without a
  trailing space, rule body or `content` declaration. CSS and SCSS preserve
  authored selector prefixes and never add an implicit `&`.
- JSX class names use `styles` for CSS Modules and `clsx` to join multiple
  classes by default. Set `emmet2-css-modules-object` and
  `emmet2-class-names-constructor` to match your project's imports.
- Scale and rhythm values such as `p(1)` and `fz(1)` are opt-in through
  `emmet2-css-scale-functions`, and apply only to SCSS.
- The Deno-era functions `emmet2-expand-css`, `emmet2-expand-markup`,
  `emmet2-expand-css-in-js` and the `emmet2-detect-*` helpers are removed.

### Added

- Completion offers the expansion and up to ten ranked CSS choices. Queries
  combine properties and keywords (`tac`), numeric suffixes (`ins32`), custom
  properties (`w--gap`) and Sass variables (`m$gutter`). Value search includes
  keywords inherited from a property's value types.
- Full previews with `corfu-popupinfo-mode`, editable fields and mirrors with
  yasnippet, and one undo that restores the abbreviation. An installed
  yasnippet is enabled when fields are first needed; no separate hook is required.
- Empty parentheses and quoted CSS values become editable fields, with point
  inside and TAB navigation when yasnippet is available.
- Automatic markup completion recognizes distinctive abbreviations, known
  elements with a pseudo-class such as `button:hv`, and standalone tags such as `div`.
- CSS support covers every `css-base-mode` descendant, including `css-ts-mode`
  and `less-css-mode`. Manual and automatic completion share position rules
  and candidates; existing property values stay with language completion.
- Selector lists, attributes and combinators are preserved during pseudo
  completion. Rows show the pseudo chain; insertion retains the full selector.
- Public [library and host APIs](API.md) for shared CSS data, matching and
  expansion. Hosts such as scss2-mode can supply context, replacement bounds,
  indentation and revisions through `emmet2-context-provider`, and use
  `emmet2-expand-analysis` for synchronous expansion.
- Enclosing at-rules select descriptor names and values through the same CSS
  data, search and expansion paths as ordinary properties.
- `emmet2-css-in-js-attributes` and `emmet2-css-in-js-functions` add style-object
  hosts such as `sx={{...}}` or `css({...})`.
- A leading `_` keeps an abbreviation's JSX classes as a string, as in `_.a.b`
  for `className="a b"`. `emmet2-jsx-class-style` set to `plain` does this for
  a whole project.

### Fixes included during development

- Keep numeric CSS properties such as `order`, `column-count`, Grid line numbers
  and SVG opacity unitless in direct expansion, completion and CSS-in-JS.
- Keep full CSS property names such as `clip` consistent between direct
  expansion and the first completion choice, including obsolete properties.
- Preserve CSS-in-JS raw values with leading zeros as strings, avoiding octal
  interpretation and JavaScript syntax errors.
- Preserve selector commas and quoted attribute colons instead of treating
  them as declaration separators or pseudo names.
- Reject stale completion candidates and insertion snapshots before editing.
  Roll back source edits if on-demand yasnippet activation hooks fail or
  invalidate the abbreviation.

### Internal organization

- Separate CSS, Web and JSX host adapters from the pure HTML/JSX and CSS
  expansion pipelines. Completion, previews and insertion share canonical results.
- Share one authored CSS override catalog across search and expansion. Remove
  the unused stylesheet value-parser mode and empty-declaration intermediate.
- Remove the development-only `:selector-block` option together with automatic
  pseudo-element rule bodies. Hosts no longer need rule-body permission checks.
- Remove the workarounds that relied on private yasnippet symbols. A field that
  ends at the very end of a buffer gets yasnippet's usual trailing newline.

See [Upgrading from 0.2](README.md#upgrading-from-02) for the configuration checklist.
