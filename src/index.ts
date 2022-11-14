import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import expandCSS from "./expand-css.ts";
import { expandHTML, expandJSX } from "./expand-markup.ts";

const bridge = new DenoBridge(Deno.args[0], Deno.args[1], Deno.args[2], messageDispatcher);

function messageDispatcher(message: string) {
  const [syntax, input, boundsBeginning] = JSON.parse(message)[1];

  try {
    let snippet = "";
    if (syntax === "css") snippet = expandCSS(input);
    else if (syntax === "jsx") snippet = expandJSX(input);
    else if (syntax === "solid") snippet = expandJSX(input, { classAttr: true });
    else if (syntax === "html") snippet = expandHTML(input);

    bridge.evalInEmacs(
      `(emmet2/insert "${snippet.replace(/"/g, '\\"')}" ${boundsBeginning} ${snippet.includes("|") ? "t" : "nil"})`
    );
  } catch (err) {
    console.error(err);
    bridge.evalInEmacs(`(message "Something wrong with expanding ${input}")`);
  }
}
