import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import expandCSS from "./expand-css.ts";
import { expandHTML, expandJSX } from "./expand-markup.ts";

const bridge = new DenoBridge(Deno.args[0], Deno.args[1], Deno.args[2], messageDispatcher);

function messageDispatcher(message: string) {
  const [lang, input, boundsBeginning, point, cssModulesObject, classNamesConstructor] = JSON.parse(message)[1];

  try {
    let snippet = "";
    if (lang === "css") snippet = expandCSS(input);
    else if (lang === "jsx") snippet = expandJSX(input, { cssModulesObject, classNamesConstructor });
    else if (lang === "solid") snippet = expandJSX(input, { classAttr: true, cssModulesObject, classNamesConstructor });
    else if (lang === "html") snippet = expandHTML(input);

    snippet = snippet.replace(/"/g, '\\"');
    const boundsEnd = boundsBeginning + input.length;
    const shouldReposition = snippet.includes("|") ? "t" : "nil";
    const shouldIndent = snippet.includes("\n") ? "t" : "nil";

    bridge.evalInEmacs(
      `(emmet2-insert "${snippet}" ${boundsBeginning} ${boundsEnd} ${shouldReposition} ${shouldIndent})`
    );
  } catch (err) {
    console.error(err);
    bridge.evalInEmacs(`(message "Something wrong with expanding ${input}")`);
  }
}
