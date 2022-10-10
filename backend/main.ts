import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import expandCSS from "./expand-css.ts";

const bridge = new DenoBridge(
  Deno.args[0],
  Deno.args[1],
  Deno.args[2],
  messageDispatcher
);

async function messageDispatcher(message: string) {
  const info = JSON.parse(message);
  const snippet = expandCSS(info[0]);

  bridge.evalInEmacs(`(insert "${snippet}")`);
}
