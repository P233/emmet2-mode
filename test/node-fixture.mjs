// Fault injector for the real Emacs process channel; never a package backend.
import { Buffer } from "node:buffer";
import { createInterface } from "node:readline";
import { setTimeout as delay } from "node:timers/promises";
import process from "node:process";

for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  const { id, abbreviation } = JSON.parse(line);
  let result = { text: abbreviation, fields: [], cursor: Array.from(abbreviation).length };
  if (abbreviation === "FIRST") await delay(600);
  if (abbreviation === "SLOW") await delay(220);
  if (abbreviation === "PARTIAL") {
    process.stdout.write('{"id":');
    await delay(10_000);
    continue;
  }
  if (abbreviation === "EXIT") process.exit(17);
  if (abbreviation === "INVALID") {
    process.stdout.write("not JSON\n");
    continue;
  }
  if (abbreviation === "PARSE_ERROR" || abbreviation === "BACKEND_ERROR") {
    process.stdout.write(`${JSON.stringify({ id, error: {
      kind: abbreviation === "PARSE_ERROR" ? "parse" : "backend",
      message: "100% literal %s", position: 2, originalMessage: "100% literal %s at 2",
    } })}\n`);
    continue;
  }
  if (abbreviation === "BAD_FIELDS") result.fields = [[0, 99, 1, "bad"]];
  if (abbreviation === "NULL_FIELDS") result.fields = null;
  if (abbreviation === "MISSING_FIELDS") delete result.fields;
  if (abbreviation === "BAD_CURSOR") result.cursor = -1;
  if (abbreviation === "SPLIT") result = { text: "😀\ue000", fields: [[1, 2, 1, "\ue000"]], cursor: 1 };
  const envelope = { id: abbreviation === "WRONG_ID" ? id + 1 : id, result };
  if (abbreviation === "BOTH") envelope.error = null;
  const response = `${JSON.stringify(envelope)}\n`;
  if (abbreviation === "SPLIT") {
    const bytes = Buffer.from(response);
    const boundary = bytes.indexOf(Buffer.from("😀")) + 2;
    process.stdout.write(bytes.subarray(0, boundary));
    await delay(10);
    process.stdout.write(bytes.subarray(boundary));
  } else {
    process.stdout.write(response);
  }
}
