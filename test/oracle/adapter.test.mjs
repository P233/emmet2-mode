import assert from "node:assert/strict";
import test from "node:test";
import upstream from "../vendor/emmet-2.4.11.mjs";
import { EmmetParseError, expand } from "./adapter.mjs";

test("markup preserves real mirrors but never overwrites conflicting defaults", () => {
  assert.deepEqual(expand("div{${1:x} ${1:x}}").fields,
    [[5, 6, 1, "x"], [7, 8, 1, "x"]]);
  assert.deepEqual(expand("div{${1:x} ${1:y}}").fields,
    [[5, 6, 1, "x"], [7, 8, 2, "y"]]);
  assert.deepEqual(expand("div{${0}}"), {
    text: "<div></div>", fields: [[5, 5, 1, ""]], cursor: 5,
  });
});

test("numeric field order is independent of text order", () => {
  assert.deepEqual(expand("div{${2:b} ${1:a}}").fields,
    [[5, 6, 2, "b"], [7, 8, 1, "a"]]);
  assert.equal(expand("div{${2:b} ${1:a}}").cursor, 7);
});

test("offsets count Unicode characters including inside placeholders", () => {
  assert.deepEqual(expand("div{😀 ${1:😸}}"), {
    text: "<div>😀 😸</div>", fields: [[7, 8, 1, "😸"]], cursor: 7,
  });
});

test("formatting preserves literal tabs and applies base indentation before fields", () => {
  const result = expand("div>p{a\tb}+input", { indent: "  ", baseIndent: "  " });
  assert.ok(result.text.includes("a\tb"));
  assert.ok(result.text.includes("\n    <p>"));
  for (const [beg, end, , placeholder] of result.fields) {
    assert.equal(Array.from(result.text).slice(beg, end).join(""), placeholder);
  }
  assert.equal(expand("br").cursor, 4);
});

test("presets keep JSX semantics separate and exclude stylesheets", () => {
  assert.equal(expand(".card/", { preset: "jsx" }).text, '<div className="card" />');
  assert.throws(() => expand("div", { preset: "bogus" }), TypeError);
  assert.throws(() => expand("m10", { preset: "stylesheet" }), TypeError);
});

test("tolerated incomplete markup stays successful; parser errors remain typed", () => {
  assert.equal(expand("a{").text, '<a href=""></a>');
  assert.equal(expand("ul>").text, "<ul></ul>");
});

test("markup token-parser errors are typed and use character offsets", () => {
  for (const [abbreviation, message, position] of [
    ["div)", "Unexpected character", 3],
    ["div**2", "Unexpected character", 4],
    ['div[title="x]', "Unclosed quote", 10],
    ["div{😀})", "Unexpected character", 6],
    ['div{😀}[title="x]', "Unclosed quote", 13],
    ["div[=x]", 'Unexpected "Operator" token', 4],
  ]) {
    assert.throws(() => expand(abbreviation), (error) => {
      assert.ok(error instanceof EmmetParseError, abbreviation);
      assert.equal(error.message, message);
      assert.equal(error.position, position);
      assert.equal(error.cause.string, undefined);
      assert.ok(error.originalMessage.includes(" at "));
      return true;
    });
  }
});

test("lexical errors inside surrogate pairs point to the containing character", () => {
  assert.throws(() => expand("div.\\😀"), (error) => {
    assert.ok(error instanceof EmmetParseError);
    assert.equal(error.message, "Unexpected character");
    assert.equal(error.cause.pos, 6);
    assert.equal(error.position, 5);
    return true;
  });
});

test("JSX attribute names follow the pinned upstream dialect", () => {
  for (const source of ["label[for=field]", ".card/", "label>input"]) {
    assert.equal(expand(source, { preset: "jsx" }).text,
      upstream(source, { syntax: "jsx", options: { "output.field": (_, value) => value, "output.selfClosingStyle": "xhtml" } }));
  }
});
