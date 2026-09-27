import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { EmmetParseError, expand } from "./adapter.mjs";
import upstream from "../vendor/emmet-2.4.11.mjs";

const css = (abbreviation, options = {}) =>
  expand(abbreviation, { preset: "stylesheet", ...options });

test("CSS positive fields are independent across properties", () => {
  assert.deepEqual(css("c+bg"), {
    text: "color: #000;\nbackground: #000;",
    fields: [[7, 11, 1, "#000"], [25, 29, 2, "#000"]], cursor: 7,
  });
});

test("CSS zero fields become ordinary independent editable stops", () => {
  assert.deepEqual(css("m+p"), {
    text: "margin: ;\npadding: ;",
    fields: [[8, 8, 1, ""], [19, 19, 2, ""]], cursor: 8,
  });
  for (const [abbr, offset] of [["t", 5], ["z", 9], ["lg", 34]]) {
    assert.deepEqual(css(abbr).fields, [[offset, offset, 1, ""]]);
  }
});

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

test("presets keep JSX and rem semantics separate", () => {
  assert.equal(expand(".card/", { preset: "jsx" }).text, '<div classList="card" />');
  assert.equal(css("m.5").text, "margin: 0.5rem;");
  assert.throws(() => expand("div", { preset: "bogus" }), TypeError);
});

test("tolerated incomplete markup stays successful; parser errors remain typed", () => {
  assert.equal(expand("a{").text, '<a href=""></a>');
  assert.equal(expand("ul>").text, "<ul></ul>");
  assert.throws(() => css("tn[all 0.3s]"), (error) => {
    assert.ok(error instanceof EmmetParseError);
    assert.equal(error.message, "Unexpected character");
    assert.equal(error.position, 2);
    assert.ok(error.originalMessage.includes("tn[all 0.3s]"));
    return true;
  });
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

test("per-property formatting matches the complete published CSS formatter", () => {
  const snippets = JSON.parse(readFileSync(new URL("../../data/emmet/css.json", import.meta.url)));
  const inputs = [...new Set(Object.keys(snippets).flatMap((key) => key.split("|"))),
    "c+bg", "m+p", "bd+bd", "m10+p5+bd1#2s+posa+dib+fz16"];
  for (const baseIndent of ["", "  "]) {
    for (const abbreviation of inputs) {
      const options = {
        "output.field": (_index, placeholder) => placeholder,
        "output.indent": "  ", "output.baseIndent": baseIndent,
        "stylesheet.floatUnit": "rem",
      };
      const expected = upstream(abbreviation, { type: "stylesheet", options });
      assert.equal(css(abbreviation, { indent: "  ", baseIndent }).text, expected, abbreviation);
    }
  }
});
