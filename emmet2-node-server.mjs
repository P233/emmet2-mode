// INTERIM since 2026-09-26; retired after S6/S7 validate the Elisp engine.
import { createInterface } from "node:readline";
import process from "node:process";
import { EmmetParseError, expand } from "./emmet2-engine-node.mjs";

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
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
    input.close();
    process.stdin.destroy();
    break;
  }
  let response;
  try {
    response = { id: request.id, result: expand(request.abbreviation, {
      preset: request.preset, indent: request.indent, baseIndent: request.baseIndent,
    }) };
  } catch (error) {
    response = { id: request.id, error: error instanceof EmmetParseError
      ? { kind: "parse", message: error.message, position: error.position,
        originalMessage: error.originalMessage }
      : { kind: "backend", message: error.message } };
  }
  process.stdout.write(`${JSON.stringify(response)}\n`);
}
