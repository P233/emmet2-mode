// INTERIM since 2026-09-26; retired after S6/S7 validate the Elisp engine.
import process from "node:process";
import { EmmetParseError, expand } from "./emmet2-engine-node.mjs";

// readline also splits U+2028/U+2029, which are valid inside JSON strings.
async function* requestLines() {
  process.stdin.setEncoding("utf8");
  let parts = [];
  for await (const chunk of process.stdin) {
    let start = 0;
    let end;
    while ((end = chunk.indexOf("\n", start)) !== -1) {
      parts.push(chunk.slice(start, end));
      const line = parts.join("");
      parts = [];
      yield line;
      start = end + 1;
    }
    if (start < chunk.length) parts.push(chunk.slice(start));
  }
  if (parts.length) yield parts.join("");
}

for await (const line of requestLines()) {
  let request;
  try {
    request = JSON.parse(line);
    if (!request || !Number.isSafeInteger(request.id) || request.id < 1 ||
        typeof request.abbreviation !== "string") {
      throw new TypeError("Invalid request envelope");
    }
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
    process.stdin.destroy();
    break;
  }
  let response;
  try {
    response = { id: request.id, result: expand(request.abbreviation, {
      preset: request.preset, indent: request.indent, baseIndent: request.baseIndent,
      jsx: request.jsx,
    }) };
  } catch (error) {
    response = { id: request.id, error: error instanceof EmmetParseError
      ? { kind: "parse", message: error.message, position: error.position,
        originalMessage: error.originalMessage }
      : { kind: "backend", message: error.message } };
  }
  process.stdout.write(`${JSON.stringify(response)}\n`);
}
