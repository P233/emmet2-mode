// SPDX-License-Identifier: GPL-3.0-or-later
import assert from "node:assert/strict";
import test from "node:test";
import { cssNames } from "./update-web-data.mjs";

const source = { schemaVersion: 1.1, counts: { atDirectives: 2, pseudoClasses: 3, pseudoElements: 1 } };
const data = {
  version: 1.1,
  atDirectives: [{ name: "@media" }, { name: "@-vendor" }],
  pseudoClasses: [{ name: ":host" }, { name: ":host" }, { name: ":-vendor" }],
  pseudoElements: [{ name: "::part" }],
};

test("CSS data generates only sorted unique non-vendor names", () => {
  const before = structuredClone(data);
  assert.deepEqual(cssNames(data, source), { atRules: ["@media"], pseudos: ["::part", ":host"] });
  assert.deepEqual(data, before);
});

test("CSS schema, count and name drift fail before output", () => {
  for (const broken of [
    { ...data, version: 2 }, { ...data, pseudoClasses: [] },
    { ...data, pseudoElements: [{ name: "::part()" }] },
    { ...data, atDirectives: null }, { ...data, pseudoElements: [null] },
  ]) assert.throws(() => cssNames(broken, source), /Unexpected CSS/);
});
