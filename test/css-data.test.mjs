// SPDX-License-Identifier: GPL-3.0-or-later
import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { cssIndex, cssMetadata, cssNames, cssSyntaxes, htmlElements, scanSyntax } from "./update-web-data.mjs";

const source = { schemaVersion: 1.1, counts: { properties: 7, atDirectives: 2, pseudoClasses: 3, pseudoElements: 1 } };
const data = {
  version: 1.1,
  properties: [{ name: "inset" }, { name: "inset-block" }, { name: "inset" },
    { name: "-vendor" }, { name: "font-display", atRule: "@font-face" },
    { name: "font-style", atRule: "@font-face",
      references: [{ url: "https://developer.mozilla.org/docs/Web/CSS/Reference/Properties/font-style" }] },
    { name: "src", atRule: "@font-face",
      references: [{ url: "https://developer.mozilla.org/docs/Web/CSS/Reference/At-rules/@font-face/src" }] }],
  atDirectives: [{ name: "@media" }, { name: "@-vendor" }],
  pseudoClasses: [{ name: ":host" }, { name: ":host" }, { name: ":-vendor" }],
  pseudoElements: [{ name: "::part" }],
};

test("CSS names retain ordinary properties that also serve as descriptors", () => {
  const before = structuredClone(data);
  assert.deepEqual(cssNames(data, source), {
    properties: ["font-style", "inset", "inset-block"], atRules: ["@media"], pseudos: ["::part", ":host"],
  });
  assert.deepEqual(data, before);
});

test("CSS schema, count and name drift fail before output", () => {
  for (const broken of [
    { ...data, version: 2 }, { ...data, pseudoClasses: [] },
    { ...data, pseudoElements: [{ name: "::part()" }] },
    { ...data, atDirectives: null }, { ...data, pseudoElements: [null] },
    { ...data, properties: [] },
    { ...data, properties: [...data.properties.slice(1), { name: "color", atRule: 42 }] },
    ...[42, [null], [{ url: 42 }]].map((references) => ({
      ...data, properties: [...data.properties.slice(1), { name: "color", references }],
    })),
  ]) assert.throws(() => cssNames(broken, source), /Unexpected CSS/);
});

test("CSS values and descriptions are preserved and validated before output", () => {
  const complete = structuredClone(data);
  Object.assign(complete.properties[0], {
    description: { kind: "markdown", value: "Property documentation" },
    restrictions: ["length"], values: [{ name: "auto", description: "Automatic" }],
  });
  const before = structuredClone(complete);
  assert.deepEqual(cssMetadata(complete, source), before);
  assert.deepEqual(complete, before);
  for (const bad of [{ description: 42 }, { restrictions: [null] },
    { values: [null] }, { values: [{ name: "" }] }, { values: [{ name: "auto", description: {} }] }]) {
    const broken = structuredClone(complete);
    Object.assign(broken.properties[0], bad);
    assert.throws(() => cssMetadata(broken, source), /Unexpected CSS properties metadata/);
  }
});

test("comma-separated value presets are not offered as values", () => {
  const stacked = structuredClone(data);
  stacked.properties[0].values = [{ name: "Arial, Helvetica, sans-serif" }, { name: "serif" }];
  const before = structuredClone(stacked);
  assert.deepEqual(cssMetadata(stacked, source).properties[0].values, [{ name: "serif" }]);
  assert.deepEqual(stacked, before);
});

test("value syntax scanning keeps top-level keywords and references only", () => {
  assert.deepEqual(scanSyntax("<line-width> || <line-style> || <color>"),
    { keywords: [], references: ["type:line-width", "type:line-style", "type:color"] });
  assert.deepEqual(scanSyntax("normal | pre | <'white-space-collapse'> || <'text-wrap-mode'>"),
    { keywords: ["normal", "pre"], references: ["property:white-space-collapse", "property:text-wrap-mode"] });
  // Functions are values; their arguments are not keywords of the property.
  assert.deepEqual(scanSyntax("none | repeat( [ <integer [1,∞]> | auto-fill ] , <track-list> ) | <anchor()>"),
    { keywords: ["none", "repeat()", "anchor()"], references: [] });
  assert.deepEqual(scanSyntax("auto | -webkit-box | <length [0,∞]>"),
    { keywords: ["auto"], references: ["type:length"] });
});

test("the index shares value sets and skips deprecated types", () => {
  const pinned = { ...source, html: { schemaVersion: 1.1, counts: { tags: 2 } }, mdn: { counts: { syntaxes: 3 } } };
  const syntaxes = {
    "line-style": { syntax: "none | solid" }, "deprecated-old": { syntax: "legacy" },
    color: { syntax: "<named-color> | currentColor | <deprecated-old>" },
  };
  const html = { version: 1.1, tags: [{ name: "div" }, { name: "button" }] };
  const complete = structuredClone(data);
  Object.assign(complete.properties[0], { syntax: "<line-style> || <color>", relevance: 69 });
  Object.assign(complete.properties[1], { syntax: "auto | <'inset'>", values: [{ name: "-vendor" }, { name: "auto" }] });
  const index = cssIndex(complete, syntaxes, html, pinned);
  assert.deepEqual(index.properties.find((entry) => entry.name === "inset"),
    { name: "inset", relevance: 69, values: [], sets: ["type:color", "type:line-style"] });
  assert.deepEqual(index.properties.find((entry) => entry.name === "inset-block"),
    { name: "inset-block", relevance: 50, values: ["auto"], sets: ["type:color", "type:line-style"] });
  assert.deepEqual(index.sets, { "type:color": ["currentColor"], "type:line-style": ["none", "solid"] });
  assert.deepEqual(index.elements, ["button", "div"]);
  assert.deepEqual(index.wide, ["inherit", "initial", "unset", "revert", "revert-layer"]);
  assert.deepEqual(index.descriptors.map(({ name, atRule }) => [name, atRule]),
    [["font-display", "@font-face"], ["font-style", "@font-face"], ["src", "@font-face"]]);
  assert.throws(() => htmlElements({ ...html, tags: [{ name: "Div" }, { name: "b" }] }, pinned), /Unexpected HTML/);
  assert.throws(() => cssSyntaxes({ a: { syntax: "x" } }, pinned), /Unexpected CSS type/);
});

test("complete metadata and the compact index have exactly the same pinned source", async () => {
  const json = async (name) => JSON.parse(await readFile(new URL(`../data/${name}`, import.meta.url), "utf8"));
  const [metadata, index, pinned] = await Promise.all([json("css-data.json"), json("css-index.json"), json("css-source.json")]);
  const names = cssNames(cssMetadata(metadata, pinned), pinned);
  assert.deepEqual(index.properties.map((entry) => entry.name), names.properties);
  assert.deepEqual(index.descriptors.map(({ name, atRule }) => [name, atRule]),
    metadata.properties.filter((entry) => entry.atRule && !entry.name.startsWith("-"))
      .map(({ name, atRule }) => [name, atRule]));
  assert.deepEqual([index.atRules, index.pseudos], [names.atRules, names.pseudos]);
  assert.equal(index.elements.length, pinned.html.counts.tags);
  assert.ok(metadata.properties.find((entry) => entry.name === "display").values.some((entry) => entry.name === "grid"));
  // Every value a property can take includes inherited types and properties.
  const values = (name) => {
    const entry = index.properties.find((property) => property.name === name);
    return [...entry.values, ...entry.sets.flatMap((key) => index.sets[key])];
  };
  for (const [name, value] of [["border", "none"], ["border", "solid"], ["border", "thin"], ["border", "currentColor"],
    ["white-space", "nowrap"], ["justify-content", "space-between"]]) {
    assert.ok(values(name).includes(value), `${name}: ${value}`);
  }
  assert.ok(!values("grid-template-columns").includes("auto-fill"));
  assert.ok(!Object.values(index.sets).flat().some((value) => value.startsWith("-")));
});
