import assert from "node:assert/strict";
import { mkdtempSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import process from "node:process";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { differences, generate } from "./gen.mjs";

test("oracle checks detect changed, missing and unexpected files without fixing them", (t) => {
  const directory = mkdtempSync(join(tmpdir(), "emmet2-oracle-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const expected = new Map([["a.json", "a\n"], ["b.json", "b\n"]]);
  for (const [name, contents] of expected) writeFileSync(join(directory, name), contents);
  assert.deepEqual(differences(directory, expected), []);
  writeFileSync(join(directory, "a.json"), "changed\n");
  unlinkSync(join(directory, "b.json"));
  writeFileSync(join(directory, "extra.json"), "extra\n");
  assert.deepEqual(differences(directory, expected), ["a.json", "b.json", "extra.json"]);
  assert.deepEqual(differences(directory, expected), ["a.json", "b.json", "extra.json"]);
});

test("fixed inputs regenerate identical output including parse failures", () => {
  const first = generate();
  assert.deepEqual(generate(), first);
  const css = JSON.parse(first.get("stylesheet.json"));
  assert.deepEqual(css.filter((entry) => entry.error).map((entry) => entry.id),
    ["css-invalid-raw", "css-error-after-emoji"]);
  for (const contents of first.values()) {
    for (const { id, result, error } of JSON.parse(contents)) {
      if (error) continue;
      const characters = Array.from(result.text);
      const groups = new Set();
      let previous = 0;
      for (const [beg, end, index, placeholder] of result.fields) {
        assert.ok(Number.isInteger(beg) && beg >= previous && end >= beg, id);
        assert.ok(Number.isInteger(end) && end <= characters.length, id);
        assert.ok(Number.isInteger(index) && index > 0, id);
        assert.equal(characters.slice(beg, end).join(""), placeholder, id);
        previous = beg;
        groups.add(index);
      }
      assert.deepEqual([...groups].sort((a, b) => a - b),
        Array.from({ length: groups.size }, (_, index) => index + 1), id);
      assert.equal(result.cursor,
        result.fields.find((field) => field[2] === 1)?.[0] ?? characters.length, id);
    }
  }
  assert.deepEqual(css.find((entry) => entry.id === "css-invalid-raw").error,
    { message: "Unexpected character", position: 2 });
  assert.deepEqual(css.find((entry) => entry.id === "css-error-after-emoji").error,
    { message: "Unexpected character", position: 7 });
});

test("the CLI runs through a symlink and rejects unknown arguments", (t) => {
  const directory = mkdtempSync(join(tmpdir(), "emmet2-cli-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const link = join(directory, "oracle.mjs");
  symlinkSync(fileURLToPath(new URL("./gen.mjs", import.meta.url)), link);
  const checked = spawnSync(process.execPath, [link, "--check"], { encoding: "utf8", cwd: directory });
  assert.equal(checked.status, 0, checked.stderr);
  assert.equal(checked.stdout.trim(), "Oracle contents and file inventory match");
  const invalid = spawnSync(process.execPath, [link, "--unexpected"], { encoding: "utf8" });
  assert.notEqual(invalid.status, 0);
  assert.match(invalid.stderr, /Usage:/);
});
