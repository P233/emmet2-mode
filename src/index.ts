import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import expandCSS from "./expand-css.ts";

const bridge = new DenoBridge(Deno.args[0], Deno.args[1], Deno.args[2], messageDispatcher);

function messageDispatcher(message: string) {
  const [syntax, abbr, boundsBeginning] = JSON.parse(message)[1];

  if (syntax === "css") {
    const snippet = expandCSS(abbr);
    bridge.evalInEmacs(`(insert "${snippet}")`);
    bridge.evalInEmacs(`(indent-region ${boundsBeginning} (point))`);
  }
}
