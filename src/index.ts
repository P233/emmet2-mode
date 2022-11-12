import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import expandCSS from "./expand-css.ts";
import { expandHTML, expandJSX } from "./expand-markup.ts";

const bridge = new DenoBridge(Deno.args[0], Deno.args[1], Deno.args[2], messageDispatcher);

function messageDispatcher(message: string) {
  const [syntax, abbr, boundsBeginning] = JSON.parse(message)[1];

  try {
    let snippet = "";
    if (syntax === "css") snippet = expandCSS(abbr);
    else if (syntax === "jsx") snippet = expandJSX(abbr);
    else if (syntax === "solid") snippet = expandJSX(abbr, { classAttr: true });
    else if (syntax === "html") snippet = expandHTML(abbr);

    snippet = snippet.replace(/"/g, '\\"');

    bridge.evalInEmacs(`(emmet2/insert "${snippet}" ${boundsBeginning})`);
  } catch (err) {
    console.error(err);
    bridge.evalInEmacs(`(message "Something wrong with expanding ${abbr}")`);
  }
}
