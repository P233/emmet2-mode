import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { setTimeout } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

const server = new URL("../emmet2-node-server.mjs", import.meta.url);

async function runServer(chunks) {
  const child = spawn(process.execPath, [fileURLToPath(server)], { timeout: 5000 });
  const closed = once(child, "close");
  let stdout = "", stderr = "";
  child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
  child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
  try {
    for (const chunk of chunks) {
      child.stdin.write(chunk);
      if (chunks.length > 1) await setTimeout(1);
    }
    child.stdin.end();
    const [code, signal] = await closed;
    assert.equal(signal, null, stderr);
    return { code, stdout, stderr };
  } finally {
    child.kill();
  }
}

test("JSONL preserves literal Unicode separators across byte fragments", async () => {
  const value = "😀\u2028😸\u2029end";
  const request = Buffer.from(`${JSON.stringify({ id: 1, abbreviation: `div{${value}}` })}\n`);
  const { code, stdout, stderr } = await runServer(Array.from(request, (byte) => Buffer.from([byte])));
  assert.equal(code, 0, stderr);
  assert.equal(stderr, "");
  assert.deepEqual(JSON.parse(stdout), {
    id: 1, result: { text: `<div>${value}</div>`, fields: [], cursor: 18 },
  });
});

test("JSONL accepts LF, CRLF, and a final request without a newline", async () => {
  const requests = [1, 2, 3].map((id) => JSON.stringify({ id, abbreviation: `p{${id}}` }));
  const { code, stdout, stderr } = await runServer([`${requests[0]}\r\n${requests[1]}\n${requests[2]}`]);
  assert.equal(code, 0, stderr);
  assert.equal(stderr, "");
  assert.deepEqual(stdout.trimEnd().split("\n").map((line) => JSON.parse(line)),
    [1, 2, 3].map((id) => ({ id, result: { text: `<p>${id}</p>`, fields: [], cursor: 8 } })));
});

test("JSONL stops at a malformed request before processing later requests", async () => {
  const valid = JSON.stringify({ id: 1, abbreviation: "p" });
  for (const invalid of ["not JSON", "{}", ""]) {
    const { code, stdout, stderr } = await runServer([`${valid}\n${invalid}\n${valid}\n`]);
    assert.equal(code, 1);
    assert.equal(stdout.trimEnd().split("\n").length, 1);
    assert.equal(JSON.parse(stdout).id, 1);
    assert.notEqual(stderr, "");
  }
});
