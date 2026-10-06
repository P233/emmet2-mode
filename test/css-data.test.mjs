// SPDX-License-Identifier: GPL-3.0-or-later
import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { cssCompletionData, cssDescriptors, cssIndex, cssMetadata, cssNames, cssSyntaxes, htmlElements, scanSyntax }
  from "./update-web-data.mjs";

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
const atRules = {
  "@font-face": { descriptors: {
    "font-display": { syntax: "auto | swap", status: "standard" },
    "font-style": { syntax: "normal | italic", status: "standard" },
    src: { syntax: "<url>", status: "standard" }, "font-family": { syntax: "<family-name>", status: "obsolete" },
  } },
  "@media": {},
  "@page": { descriptors: { "page-margin-safety": { syntax: "none | add", status: "standard" } } },
};
const pinned = { ...source, html: { schemaVersion: 1.1, counts: { tags: 2 } }, mdn: { counts: { syntaxes: 3, descriptors: 5 } } };
const syntaxes = {
  "line-style": { syntax: "none | solid" }, "deprecated-old": { syntax: "legacy" },
  color: { syntax: "<named-color> | currentColor | <deprecated-old>" },
};
const html = { version: 1.1, tags: [{ name: "div" }, { name: "button" }] };

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

test("written metadata keeps only completion fields, with string documentation", () => {
  const complete = structuredClone(data);
  Object.assign(complete, { extra: true });
  Object.assign(complete.properties[0], {
    browsers: ["FF1"], syntax: "auto", relevance: 50, status: "obsolete", baseline: { status: "high" },
    description: { kind: "markdown", value: "Property documentation" }, restrictions: ["length"],
    values: [{ name: "auto", description: { kind: "markdown", value: "Automatic" }, browsers: ["FF1"] }, { name: "none" }],
  });
  Object.assign(complete.atDirectives[0], { description: "Media", descriptors: [{ name: "width" }] });
  const before = structuredClone(complete);
  const written = JSON.parse(JSON.stringify(cssCompletionData(complete, source)));
  assert.deepEqual(complete, before);
  assert.deepEqual(Object.keys(written), ["version", ...Object.keys(source.counts)]);
  assert.deepEqual(written.properties[0], {
    name: "inset", description: "Property documentation", restrictions: ["length"],
    values: [{ name: "auto", description: "Automatic" }, { name: "none" }],
  });
  assert.deepEqual(written.properties[6], { name: "src", atRule: "@font-face" });
  assert.deepEqual(written.atDirectives[0], { name: "@media", description: "Media" });
  assert.deepEqual(written.pseudoClasses, data.pseudoClasses);
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
  const complete = structuredClone(data);
  Object.assign(complete.properties[0], { syntax: "<line-style> || <color>", relevance: 69 });
  Object.assign(complete.properties[1], { syntax: "auto | <'inset'>", values: [{ name: "-vendor" }, { name: "auto" }] });
  const index = cssIndex(complete, syntaxes, atRules, html, pinned);
  assert.deepEqual(index.properties.find((entry) => entry.name === "inset"),
    { name: "inset", relevance: 69, values: [], sets: ["type:color", "type:line-style"] });
  assert.deepEqual(index.properties.find((entry) => entry.name === "inset-block"),
    { name: "inset-block", relevance: 50, values: ["auto"], sets: ["type:color", "type:line-style"] });
  assert.deepEqual(index.sets, { "type:color": ["currentColor"], "type:line-style": ["none", "solid"] });
  assert.deepEqual(index.elements, ["button", "div"]);
  assert.deepEqual(index.wide, ["inherit", "initial", "unset", "revert", "revert-layer"]);
  // Metadata names neither font-family nor page-margin-safety here.
  assert.deepEqual(index.descriptors.map(({ name, atRule }) => [name, atRule]),
    [["font-display", "@font-face"], ["font-style", "@font-face"], ["src", "@font-face"]]);
  const { src, ...withoutSource } = atRules["@font-face"].descriptors;
  assert.equal(src.syntax, "<url>");
  assert.throws(() => cssIndex(complete, syntaxes, { "@font-face": { descriptors: withoutSource } }, html,
    { ...pinned, mdn: { counts: { syntaxes: 3, descriptors: 3 } } }), /without MDN syntax: src$/);
  assert.throws(() => htmlElements({ ...html, tags: [{ name: "Div" }, { name: "b" }] }, pinned), /Unexpected HTML/);
  assert.throws(() => cssSyntaxes({ a: { syntax: "x" } }, pinned), /Unexpected CSS type/);
});

test("descriptors take values from their own syntax, not from a property's record", () => {
  const complete = structuredClone(data);
  complete.properties[4].values = [{ name: "fallback" }];
  // An upstream record that also documents the font-style property lists the property's values.
  complete.properties[5].values = [{ name: "italic" }, { name: "bolder" }];
  // An ordinary record names font-family, whose descriptor the upstream data does not associate.
  complete.properties.push({ name: "font-family", values: [{ name: "serif" }] });
  const index = cssIndex(complete, syntaxes, atRules, html,
    { ...pinned, counts: { ...pinned.counts, properties: 8 } });
  const descriptor = (name) => index.descriptors.find((entry) => entry.name === name);
  assert.deepEqual(descriptor("font-display").values, ["fallback", "auto", "swap"]);
  assert.deepEqual(descriptor("font-style").values, ["normal", "italic"]);
  assert.deepEqual(descriptor("font-family"),
    { atRule: "@font-face", name: "font-family", relevance: 50, obsolete: true, values: [], sets: [] });
  assert.deepEqual(index.properties.find((entry) => entry.name === "font-style").values, ["italic", "bolder"]);
  // The metadata admits font-display only in @font-face.
  const elsewhere = { ...atRules, "@font-feature-values": { descriptors: { "font-display": { syntax: "auto", status: "standard" } } } };
  assert.deepEqual(cssIndex(complete, syntaxes, elsewhere, html,
    { ...pinned, counts: { ...pinned.counts, properties: 8 }, mdn: { counts: { syntaxes: 3, descriptors: 6 } } })
    .descriptors.filter(({ name }) => name === "font-display").map(({ atRule }) => atRule), ["@font-face"]);
});

test("at-rule descriptor drift fails before output", () => {
  assert.deepEqual(cssDescriptors({ ...atRules, "@page": { descriptors: { "-vendor": { syntax: "x", status: "standard" } } } },
    { mdn: { counts: { descriptors: 5 } } }).map(({ name }) => name), ["font-display", "font-style", "src", "font-family"]);
  for (const broken of [null, [], { "@font-face": { descriptors: { src: { status: "standard" } } } },
    { "@font-face": { descriptors: { src: { syntax: "x" } } } },
    { page: { descriptors: { size: { syntax: "x", status: "standard" } } } },
    { "@page": { descriptors: { Size: { syntax: "x", status: "standard" } } } },
    { "@page": 5 }, { "@page": { descriptors: [{ syntax: "x", status: "standard" }] } }]) {
    assert.throws(() => cssDescriptors(broken, { mdn: { counts: { descriptors: 1 } } }), /Unexpected CSS at-rule descriptors/);
  }
  assert.throws(() => cssDescriptors(atRules, { mdn: { counts: { descriptors: 3 } } }), /Unexpected CSS at-rule descriptors/);
});

test("written metadata and the compact index have the same pinned source", async () => {
  const texts = await Promise.all(["css-data.json", "css-index.json", "css-source.json"]
    .map((name) => readFile(new URL(`../data/${name}`, import.meta.url), "utf8")));
  const [metadata, index, pinned] = texts.map((text) => JSON.parse(text));
  assert.equal(JSON.stringify(cssCompletionData(metadata, pinned), null, 2) + "\n", texts[0]);
  const names = cssNames(cssMetadata(metadata, pinned), pinned);
  // Without upstream references, which admit dual-role descriptors, the metadata only bounds the index.
  const indexed = index.properties.map((entry) => entry.name);
  const known = new Set(metadata.properties.map((entry) => entry.name));
  assert.deepEqual(names.properties.filter((name) => !indexed.includes(name)), []);
  assert.deepEqual(indexed.filter((name) => !known.has(name)), []);
  // MDN supplies descriptors that one upstream record per name cannot associate, such as @font-face font-family.
  const descriptors = index.descriptors.map(({ name, atRule }) => `${atRule}:${name}`);
  assert.ok(descriptors.includes("@font-face:font-family"));
  assert.deepEqual(index.descriptors.filter(({ name }) => !known.has(name)), []);
  assert.deepEqual(metadata.properties.filter((entry) => entry.atRule && !entry.name.startsWith("-"))
    .map(({ name, atRule }) => `${atRule}:${name}`).filter((key) => !descriptors.includes(key)), []);
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
  assert.ok(values("font-weight").includes("bolder"));
  // Descriptors share no keyword with a same-named property that their syntax lacks.
  const descriptor = (atRule, name) => {
    const entry = index.descriptors.find((item) => item.atRule === atRule && item.name === name);
    return [...entry.values, ...entry.sets.flatMap((key) => index.sets[key])];
  };
  assert.deepEqual(descriptor("@font-face", "font-weight"), ["normal", "bold"]);
  assert.deepEqual(descriptor("@font-face", "font-family"), []);
  assert.deepEqual(descriptor("@font-palette-values", "font-family"), []);
  assert.ok(descriptor("@font-face", "font-display").includes("swap"));
  assert.ok(!Object.values(index.sets).flat().some((value) => value.startsWith("-")));
});
