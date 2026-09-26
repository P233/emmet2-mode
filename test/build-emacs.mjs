// Explicit isolated build used by CI. No system installation or build cache.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { closeSync, mkdirSync, openSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import process from "node:process";

if (process.argv.length !== 4) throw new Error("Usage: node test/build-emacs.mjs VERSION NEW_BUILD_DIRECTORY");
const lock = JSON.parse(readFileSync(new URL("./dependencies.json", import.meta.url)));
const emacs = lock.emacs.find(({ version }) => version === process.argv[2]);
if (!emacs) throw new Error(`Unlocked Emacs version: ${process.argv[2]}`);
const root = resolve(process.argv[3]);
mkdirSync(root); // Refuse an existing directory, including partial prior builds.
const logPath = join(root, "build.log");
const log = openSync(logPath, "w");

function run(command, args, cwd, env = process.env) {
  try {
    execFileSync(command, args, { cwd, env, stdio: ["ignore", log, log] });
  } catch (error) {
    throw new Error(`${command} failed; inspect ${logPath}`, { cause: error });
  }
}

function checkout(name, repository, revision) {
  if (!/^[a-f0-9]{40}$/.test(revision)) throw new Error(`Unpinned source: ${name}`);
  const directory = join(root, name);
  mkdirSync(directory);
  run("git", ["init", "--quiet"], directory);
  run("git", ["fetch", "--quiet", "--depth=1", repository, revision], directory);
  run("git", ["checkout", "--quiet", "--detach", revision], directory);
  return directory;
}

try {
  const runtime = lock.tree_sitter_runtime;
  const tree = checkout("tree-sitter", runtime.repository, runtime.revision);
  run("make", ["-j4", "libtree-sitter.a"], tree);
  const response = await fetch(emacs.archive, { signal: AbortSignal.timeout(120_000) });
  if (!response.ok) throw new Error(`Download failed: ${response.status} ${emacs.archive}`);
  const data = Buffer.from(await response.arrayBuffer());
  if (createHash("sha256").update(data).digest("hex") !== emacs.sha256) {
    throw new Error("Emacs source archive checksum mismatch");
  }
  const archive = join(root, "emacs.tar.xz");
  writeFileSync(archive, data);
  const source = join(root, "emacs");
  mkdirSync(source);
  run("tar", ["-xf", archive, "--strip-components=1", "-C", source], root);
  const env = { ...process.env,
    TREE_SITTER_CFLAGS: `-I${tree}/lib/include`,
    TREE_SITTER_LIBS: join(tree, "libtree-sitter.a") };
  run("./configure", [`--prefix=${root}/install`, "--without-all", "--with-tree-sitter",
    "--without-native-compilation", "--without-x", "--without-ns"], source, env);
  run("make", ["-j4"], source, env);
  // A build-tree executable finds its own Lisp files and dump; no install step.
  console.log(join(source, "src", "emacs"));
} finally {
  closeSync(log);
}
