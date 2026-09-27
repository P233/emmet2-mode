import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { EmmetParseError, expand } from "../../emmet2-engine-node.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const fixtures = join(root, "test/fixtures");

export function generate() {
  const provenance = JSON.parse(readFileSync(join(root, "vendor/emmet-source.json")));
  for (const [file, { sha256 }] of Object.entries(provenance.files)) {
    const actual = createHash("sha256").update(readFileSync(join(root, file))).digest("hex");
    if (actual !== sha256) throw new Error(`Vendor checksum mismatch: ${file}`);
  }
  const inputs = JSON.parse(readFileSync(join(fixtures, "core-inputs.json")));
  const results = { markup: [], stylesheet: [] };
  const ids = new Set();
  for (const input of inputs) {
    const { id, abbreviation, preset, source, ...options } = input;
    if (typeof id !== "string" || ids.has(id) || typeof source !== "string" ||
        !["html", "jsx", "stylesheet"].includes(preset) ||
        Object.keys(options).some((key) => !["indent", "baseIndent", "jsx"].includes(key))) {
      throw new Error(`Invalid or duplicate oracle input: ${id}`);
    }
    ids.add(id);
    let outcome;
    try {
      outcome = { result: expand(abbreviation, { preset, ...options }) };
    } catch (error) {
      if (!(error instanceof EmmetParseError)) throw error;
      outcome = { error: { message: error.message, position: error.position } };
    }
    results[preset === "stylesheet" ? "stylesheet" : "markup"].push({ id, ...outcome });
  }
  return new Map(Object.entries(results).map(([name, cases]) => [
    `${name}.json`, `${JSON.stringify(cases, null, 2)}\n`,
  ]));
}

/** Compare both contents and the complete file inventory; never update on check. */
export function differences(directory, expected) {
  const actual = readdirSync(directory);
  const changed = actual.filter((name) => !expected.has(name));
  for (const [name, content] of expected) {
    if (!actual.includes(name) || readFileSync(join(directory, name), "utf8") !== content) {
      changed.push(name);
    }
  }
  return changed.sort();
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== "--check")) {
    throw new Error("Usage: node test/oracle/gen.mjs [--check]");
  }
  const output = join(fixtures, "oracle");
  const generated = generate();
  if (args[0] === "--check") {
    const changed = differences(output, generated);
    if (changed.length) throw new Error(`Oracle differs: ${changed.join(", ")}`);
    console.log("Oracle contents and file inventory match");
  } else {
    mkdirSync(output, { recursive: true });
    const unexpected = readdirSync(output).filter((name) => !generated.has(name));
    if (unexpected.length) throw new Error(`Unexpected oracle files: ${unexpected.join(", ")}`);
    for (const [name, content] of generated) writeFileSync(join(output, name), content);
    console.log(`Generated ${generated.size} oracle files`);
  }
}
