// SPDX-License-Identifier: GPL-3.0-or-later
// Explicit, pinned maintenance step. Never invoked by the offline oracle.
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

export function cssNames(data, source) {
  if (data?.version !== source.schemaVersion) throw new Error("Unexpected CSS data schema");
  for (const [key, count] of Object.entries(source.counts)) {
    const prefix = key === "atDirectives" ? /^@[-a-z]+$/ : /^::?[-a-z]+$/;
    if (!Array.isArray(data[key]) || data[key].length !== count ||
        data[key].some((item) => typeof item?.name !== "string" || !prefix.test(item.name))) {
      throw new Error(`Unexpected CSS ${key} names or count`);
    }
  }
  const names = (items) => [...new Set(items.map((item) => item.name))]
    .filter((name) => !/^[:@]+-/.test(name)).sort();
  return {
    atRules: names(data.atDirectives),
    pseudos: names([...data.pseudoClasses, ...data.pseudoElements]),
  };
}

if (import.meta.main) {
  if (process.argv.length !== 2) throw new Error("Usage: node data/update-web-data.mjs");
  const source = JSON.parse(await readFile(new URL("css-source.json", import.meta.url), "utf8"));
  const files = {};
  for (const [path, hash] of Object.entries(source.files)) {
    const url = `https://raw.githubusercontent.com/microsoft/vscode-custom-data/${source.commit}/${path}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (createHash("sha256").update(bytes).digest("hex") !== hash) {
      throw new Error(`Checksum mismatch: ${path}`);
    }
    files[path] = bytes;
  }
  const names = cssNames(JSON.parse(files["web-data/data/browsers.css-data.json"]), source);
  // Validate every input before writing; local overrides and legacy data are never outputs.
  await writeFile(new URL("css-names.json", import.meta.url), JSON.stringify(names, null, 2) + "\n");
  await writeFile(new URL("vscode-custom-data-LICENSE", import.meta.url), files.LICENSE);
  console.log(`Pinned CSS names: ${names.atRules.length} at-rules, ${names.pseudos.length} pseudos`);
}
