// Explicit development setup; never called by the offline oracle or package.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import process from "node:process";

if (process.argv.length !== 3) throw new Error("Usage: node test/setup.mjs DEPENDENCY_DIRECTORY");
if (!["darwin", "linux"].includes(process.platform)) throw new Error("Test setup supports macOS and Linux");
const root = resolve(process.argv[2]);
const lock = JSON.parse(readFileSync(new URL("./dependencies.json", import.meta.url)));
mkdirSync(root, { recursive: true });

function run(command, args, cwd) {
  return execFileSync(command, args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function checkout(name, { repository, revision }) {
  if (!/^[a-f0-9]{40}$/.test(revision)) throw new Error(`Unpinned dependency: ${name}`);
  const target = join(root, `${name}-${revision}`);
  if (!existsSync(target)) {
    const temporary = mkdtempSync(join(root, ".checkout-"));
    try {
      run("git", ["init", "--quiet"], temporary);
      run("git", ["fetch", "--quiet", "--depth=1", repository, revision], temporary);
      run("git", ["checkout", "--quiet", "--detach", "FETCH_HEAD"], temporary);
      renameSync(temporary, target);
    } finally {
      rmSync(temporary, { recursive: true, force: true });
    }
  }
  if (run("git", ["rev-parse", "HEAD"], target) !== revision ||
      run("git", ["status", "--porcelain"], target)) {
    throw new Error(`Dependency checkout changed: ${target}`);
  }
  return target;
}

for (const [name, source] of Object.entries(lock.packages)) {
  checkout(name, source);
  console.log(`Ready: ${name} ${source.revision}`);
}
const grammarDirectory = join(root, "grammars");
mkdirSync(grammarDirectory, { recursive: true });
for (const [name, source] of Object.entries(lock.grammars)) {
  // The two TypeScript grammars share one immutable source checkout.
  const checkoutName = name === "tsx" ? "typescript-grammar" : `${name}-grammar`;
  const repository = checkout(checkoutName, source);
  const directory = join(repository, source.directory);
  const extension = process.platform === "darwin" ? "dylib" : "so";
  const output = join(grammarDirectory, `libtree-sitter-${name}.${extension}`);
  const temporary = `${output}.building`;
  try {
    run("cc", [process.platform === "darwin" ? "-dynamiclib" : "-shared", "-fPIC", "-O2",
      "-I", directory, join(directory, "parser.c"),
      ...(existsSync(join(directory, "scanner.c")) ? [join(directory, "scanner.c")] : []),
      "-o", temporary], repository);
    renameSync(temporary, output);
  } finally {
    rmSync(temporary, { force: true });
  }
  console.log(`Built: ${name} ${source.revision}`);
}
console.log(`Use EMMET2_TEST_DEPS=${root}`);
