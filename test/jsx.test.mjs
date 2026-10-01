// SPDX-License-Identifier: GPL-3.0-or-later
import assert from "node:assert/strict";
import test from "node:test";
import { expand } from "./oracle/adapter.mjs";
import { transformClasses } from "./oracle/jsx.mjs";
import { parseMarkup, resolveConfig } from "./vendor/emmet-2.4.11.mjs";

const jsx = { classAttribute: "className", cssModulesObject: "css", classConstructor: "clsx" };
const run = (input, options = jsx) => expand(input, { preset: "jsx", jsx: options });

function canonical(result) {
  const characters = Array.from(result.text);
  for (const [beg, end, , value] of result.fields) assert.equal(characters.slice(beg, end).join(""), value);
  assert.equal(result.cursor, result.fields.find((field) => field[2] === 1)?.[0] ?? characters.length);
}

test("JSX class transformation does not mutate parsed AST or reused options", () => {
  const tree = parseMarkup('.card>span[class="a b"]', resolveConfig({ type: "markup" }));
  const before = structuredClone(tree);
  const react = transformClasses(tree, jsx);
  const solid = transformClasses(tree, { ...jsx, classAttribute: "class" });
  assert.deepEqual(tree, before);
  assert.equal(react.children[0].attributes[0].name, "className");
  assert.equal(solid.children[0].attributes[0].name, "class");
  assert.deepEqual(transformClasses(tree, jsx), react);
});

test("quoted and Unicode class keys become valid expressions with literal values", () => {
  for (const [input, key] of [
    ['[class=\'a"b\']', 'a"b'], ['[class="a\\\\b"]', 'a\\b'], ['[class="😀"]', '😀'],
    ['[class=\'x"];sideEffect();["y\']', 'x"];sideEffect();["y'],
  ]) {
    const result = run(input);
    const expression = result.text.slice('<div className={'.length, result.text.indexOf('}></div>'));
    // Executing these fixed fixture expressions verifies both escaping and the
    // addressed key; no repository/project option is evaluated by production.
    const actual = new Function("css", `return ${expression}`)({ [key]: "literal" });
    assert.equal(actual, "literal");
    assert.equal(result.text, `<div className={css[${JSON.stringify(key)}]}></div>`);
    canonical(result);
  }
});

test("class fields preserve mirrors, numeric priority and multiword defaults", () => {
  const mirrors = run('[class="${1:a} ${1:a}"]');
  assert.deepEqual(mirrors.fields.filter((field) => field[3] === "a").map((field) => field[2]), [1, 1]);
  const order = run('[class="${2:b} ${1:a}"]');
  assert.deepEqual(order.fields.slice(0, 2).map((field) => field[2]), [2, 1]);
  const spanning = run('[class="${1:a b}"]');
  assert.equal(spanning.text, '<div className={clsx(css.a, css.b)}></div>');
  assert.equal(spanning.fields[0][3], 'a, css.b');
  const escaped = run('[class=\'${1:a"b}\']');
  assert.equal(escaped.fields[0][3], 'a\\"b');
  const blanks = run('[class="${1: } ${1: }"]');
  assert.equal(blanks.text, '<div className={clsx(css[""], css[""])}></div>');
  assert.equal(blanks.fields[0][2], blanks.fields[1][2]);
  assert.notEqual(blanks.fields[0][0], blanks.fields[1][0]);
  for (const result of [mirrors, order, spanning, escaped, run('[class="base ${1}"]'),
    run('[class="${1} base"]'), blanks]) canonical(result);
});

test("expressions, other attributes and markup text are not class literals", () => {
  assert.equal(run('[class={foo}]').text, '<div className={foo}></div>');
  assert.equal(run('[classList={foo}]').text, '<div classList={foo}></div>');
  assert.equal(run('[className="literal"]').text, '<div className="literal"></div>');
  const input = 'p{<div class="untouched">}';
  assert.equal(run(input).text, expand(input, { preset: "jsx" }).text);
  assert.equal(run('p{classList="literal"}').text, '<p>classList="literal"</p>');
});

test("fields starting at a previous word boundary do not duplicate class names", () => {
  for (const [value, expression] of [
    ["base${1: a}", "clsx(css.base, css.a)"],
    ["${1:a }base", "clsx(css.a, css.base)"],
    ["x${1: a b}c", "clsx(css.x, css.a, css.bc)"],
    ["${1:a}${2: b}", "clsx(css.a, css.b)"],
  ]) {
    const result = run(`[class="${value}"]`);
    assert.equal(result.text, `<div className={${expression}}></div>`);
    canonical(result);
  }
  for (const prefix of ["", "x", "x "]) {
    for (const suffix of ["", "y", " y"]) {
      for (const value of ["a", "a b", " a", "a "]) {
        const classes = `${prefix}${value}${suffix}`.trim().split(/\s+/);
        const members = classes.map((name) => `css.${name}`);
        const expression = members.length === 1 ? members[0] : `clsx(${members.join(", ")})`;
        const result = run(`[class="${prefix}\${1:${value}}${suffix}"]`);
        assert.equal(result.text, `<div className={${expression}}></div>`);
        canonical(result);
      }
    }
  }
});

test("solid names and project references apply before layout and field collection", () => {
  const result = run('.a.b>span{😀}', {
    classAttribute: "class", cssModulesObject: "styles.module", classConstructor: "helpers.cx",
  });
  assert.equal(result.text, '<div class={helpers.cx(styles.module.a, styles.module.b)}><span>😀</span></div>');
  assert.equal(result.fields.length, 0);
  canonical(result);
  assert.deepEqual(run('.'), {
    text: '<div className={css[""]}></div>', fields: [[21, 21, 1, ""], [25, 25, 2, ""]], cursor: 21,
  });
});

test("JSX options are validated at the backend boundary", () => {
  assert.throws(() => run('.a', { ...jsx, classAttribute: "unknown" }), TypeError);
  assert.throws(() => expand('.a', { preset: "html", jsx }), /require the JSX preset/);
});

test("empty classes remain valid expressions and editable keys", () => {
  for (const input of [".", '[class=""]', '[class="  "]', '[class="${1} ${2}"]',
    '[class="${1: } ${1: }"]']) {
    const result = run(input);
    const expression = result.text.slice('<div className={'.length, result.text.indexOf('}></div>'));
    const value = new Function("css", "clsx", `return (${expression});`)({ "": "empty" }, (...args) => args.join(" "));
    assert.equal(typeof value, "string");
    canonical(result);
  }
  for (const key of ["cssModulesObject", "classConstructor"]) {
    for (const value of ["", " \t\n", null]) {
      assert.throws(() => run(".a.b", { ...jsx, [key]: value }), TypeError);
    }
  }
});

test("React and Solid own both class and label attribute mappings", () => {
  assert.equal(run("label.a[for=field]").text, '<label htmlFor="field" className={css.a}></label>');
  assert.equal(run("label.a[for=field]", { ...jsx, classAttribute: "class" }).text,
    '<label for="field" class={css.a}></label>');
});
