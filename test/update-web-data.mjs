// SPDX-License-Identifier: GPL-3.0-or-later
// Explicit, pinned maintenance step. Never invoked by the offline oracle.
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

// Every property also accepts the CSS-wide keywords.
const cssWide = ["inherit", "initial", "unset", "revert", "revert-layer"];

export function cssNames(data, source) {
  if (data?.version !== source.schemaVersion) throw new Error("Unexpected CSS data schema");
  for (const [key, count] of Object.entries(source.counts)) {
    const prefix = key === "properties" ? /^-?[a-z][a-z0-9-]*$/ : key === "atDirectives" ? /^@[-a-z]+$/ : /^::?[-a-z]+$/;
    if (!Array.isArray(data[key]) || data[key].length !== count ||
        data[key].some((item) => typeof item?.name !== "string" || !prefix.test(item.name) ||
          (item.atRule !== undefined && (typeof item.atRule !== "string" || !/^@[-a-z]+$/.test(item.atRule))) ||
          (item.references !== undefined && (!Array.isArray(item.references) ||
            item.references.some((reference) => typeof reference?.url !== "string"))))) {
      throw new Error(`Unexpected CSS ${key} names or count`);
    }
  }
  const names = (items) => [...new Set(items.map((item) => item.name))]
    .filter((name) => !/^[:@]*-/.test(name)).sort();
  return {
    // atRule is an association, not an exclusive role. A property reference
    // identifies entries such as font-style that are also ordinary properties.
    properties: names(data.properties.filter((item) => !item.atRule ||
      item.references?.some((reference) => reference.url.endsWith(`/Web/CSS/Reference/Properties/${item.name}`)))),
    atRules: names(data.atDirectives),
    pseudos: names([...data.pseudoClasses, ...data.pseudoElements]),
  };
}

export function cssMetadata(data, source) {
  cssNames(data, source);
  const description = (value) => value === undefined || typeof value === "string" ||
    (value !== null && typeof value === "object" && typeof value.value === "string");
  for (const key of Object.keys(source.counts)) {
    for (const entry of data[key]) {
      if (!description(entry.description) ||
          (entry.restrictions !== undefined && (!Array.isArray(entry.restrictions) ||
            entry.restrictions.some((value) => typeof value !== "string"))) ||
          (entry.values !== undefined && (!Array.isArray(entry.values) ||
            entry.values.some((value) => typeof value?.name !== "string" ||
              value.name.length === 0 || !description(value.description)))) ||
          (entry.syntax !== undefined && typeof entry.syntax !== "string") ||
          (entry.relevance !== undefined && typeof entry.relevance !== "number")) {
        throw new Error(`Unexpected CSS ${key} metadata`);
      }
    }
  }
  return data;
}

export function htmlElements(data, source) {
  if (data?.version !== source.html.schemaVersion || !Array.isArray(data.tags) ||
      data.tags.length !== source.html.counts.tags ||
      data.tags.some((tag) => typeof tag?.name !== "string" || !/^[a-z][a-z0-9]*$/.test(tag.name))) {
    throw new Error("Unexpected HTML elements");
  }
  return [...new Set(data.tags.map((tag) => tag.name))].sort();
}

export function cssSyntaxes(syntaxes, source) {
  if (syntaxes === null || typeof syntaxes !== "object" || Array.isArray(syntaxes) ||
      Object.keys(syntaxes).length !== source.mdn.counts.syntaxes ||
      Object.values(syntaxes).some((entry) => typeof entry?.syntax !== "string")) {
    throw new Error("Unexpected CSS type syntaxes");
  }
  return syntaxes;
}

/**
 * Return the keywords and references at the top level of a value definition.
 * Functions are values; their arguments, such as auto-fill in repeat(), are not.
 */
export function scanSyntax(syntax) {
  const keywords = [];
  const references = [];
  let depth = 0;
  for (const [, angle, word, open, bracket] of syntax.matchAll(/<([^<>]*)>|(-{0,2}[a-zA-Z][-a-zA-Z0-9]*)(\()?|([()])/g)) {
    if (angle !== undefined) {
      if (depth > 0) continue;
      const property = /^'([a-z][-a-z]*)'$/.exec(angle);
      const functional = /^([a-z][-a-z0-9]*)\(\)$/.exec(angle);
      const type = /^([a-z][-a-z0-9]*)(?: \[[^\]]*\])?$/.exec(angle);
      if (property) references.push(`property:${property[1]}`);
      else if (functional) keywords.push(`${functional[1]}()`);
      else if (type) references.push(`type:${type[1]}`);
    } else if (word !== undefined) {
      if (depth === 0 && !word.startsWith("-")) keywords.push(open ? `${word}()` : word);
      if (open) depth++;
    } else {
      depth = bracket === "(" ? depth + 1 : Math.max(0, depth - 1);
    }
  }
  return { keywords: [...new Set(keywords)], references: [...new Set(references)] };
}

/**
 * Build the compact runtime index.  Each property lists its own keywords and
 * every shared value set reachable through property and type references.
 * A set stores only its own keywords, so shared sets such as named colors
 * appear once.  Obsolete properties remain canonical names but are marked.
 */
export function cssIndex(data, syntaxes, html, source) {
  const names = cssNames(data, source);
  const entries = new Map();
  for (const entry of data.properties) entries.set(entry.name, [...(entries.get(entry.name) ?? []), entry]);
  const ordinary = (name) => entries.get(name).find((entry) => !entry.atRule) ?? entries.get(name)[0];
  const definitions = new Map(Object.entries(cssSyntaxes(syntaxes, source))
    .map(([name, entry]) => [`type:${name}`, entry.syntax]));
  for (const name of names.properties) {
    if (ordinary(name).syntax !== undefined) definitions.set(`property:${name}`, ordinary(name).syntax);
  }
  const descriptors = data.properties.filter((entry) => entry.atRule && !entry.name.startsWith("-"));
  for (const entry of descriptors) definitions.set(`${entry.atRule}:${entry.name}`, entry.syntax ?? "");
  const scanned = new Map();
  const scan = (key) => {
    if (!scanned.has(key)) scanned.set(key, scanSyntax(definitions.get(key) ?? ""));
    return scanned.get(key);
  };
  const sets = new Map();
  const indexEntry = (entry, start) => {
    const { name } = entry;
    const reached = new Set();
    const pending = [...scan(start).references];
    while (pending.length) {
      const key = pending.shift();
      // Deprecated types, such as the old system colors, are not offered.
      if (key === start || reached.has(key) || key.startsWith("type:deprecated-")) continue;
      reached.add(key);
      pending.push(...scan(key).references);
    }
    const keys = [...reached].filter((key) => scan(key).keywords.length).sort();
    for (const key of keys) sets.set(key, scan(key).keywords);
    const values = [...new Set([...(entry.values ?? []).map((value) => value.name), ...scan(start).keywords])]
      .filter((value) => !value.startsWith("-"));
    const relevance = entry.relevance ?? entries.get(name).find((item) => item.relevance !== undefined)?.relevance ?? 50;
    return { name, relevance, ...(entry.status === "obsolete" ? { obsolete: true } : {}), values, sets: keys };
  };
  return {
    properties: names.properties.map((name) => indexEntry(ordinary(name), `property:${name}`)),
    descriptors: descriptors.map((entry) => ({ atRule: entry.atRule, ...indexEntry(entry, `${entry.atRule}:${entry.name}`) })),
    sets: Object.fromEntries([...sets].sort(([a], [b]) => (a < b ? -1 : 1))),
    wide: cssWide,
    atRules: names.atRules,
    pseudos: names.pseudos,
    elements: htmlElements(html, source),
  };
}

async function download(base, files) {
  const result = {};
  for (const [path, hash] of Object.entries(files)) {
    const url = `${base}/${path}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (createHash("sha256").update(bytes).digest("hex") !== hash) {
      throw new Error(`Checksum mismatch: ${path}`);
    }
    result[path] = bytes;
  }
  return result;
}

if (import.meta.main) {
  if (process.argv.length !== 2) throw new Error("Usage: node test/update-web-data.mjs");
  const source = JSON.parse(await readFile(new URL("../data/css-source.json", import.meta.url), "utf8"));
  const vscode = await download(`https://raw.githubusercontent.com/microsoft/vscode-custom-data/${source.commit}`, source.files);
  const mdn = await download(`https://raw.githubusercontent.com/mdn/data/${source.mdn.commit}`, source.mdn.files);
  const data = cssMetadata(JSON.parse(vscode["web-data/data/browsers.css-data.json"]), source);
  const index = cssIndex(data, JSON.parse(mdn["css/syntaxes.json"]),
    JSON.parse(vscode["web-data/data/browsers.html-data.json"]), source);
  // Validate every input before writing; local overrides are never outputs.
  await writeFile(new URL("../data/css-data.json", import.meta.url),
    JSON.stringify(data, null, 2) + "\n");
  await writeFile(new URL("../data/css-index.json", import.meta.url), JSON.stringify(index, null, 2) + "\n");
  await writeFile(new URL("../data/vscode-custom-data-LICENSE", import.meta.url), vscode.LICENSE);
  await writeFile(new URL("../data/mdn-data-LICENSE", import.meta.url), mdn.LICENSE);
  console.log(`Pinned CSS index: ${index.properties.length} properties, ${Object.keys(index.sets).length} value sets, ` +
    `${index.atRules.length} at-rules, ${index.pseudos.length} pseudos, ${index.elements.length} elements`);
}
