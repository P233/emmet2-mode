import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import expandCSS from "./expand-css.ts";
import { expandHTML, expandJSX } from "./expand-markup.ts";

const bridge = new DenoBridge(Deno.args[0], Deno.args[1], Deno.args[2], messageDispatcher);

function messageDispatcher(message: string) {
  const [lang, input, boundsBeginning, bufferPoint, cssModulesObject, classConstructor] = JSON.parse(message)[1];

  try {
    let snippet = "";
    let start = boundsBeginning;
    let end = boundsBeginning + input.length;

    if (lang === "css") {
      snippet = expandCSS(input);
    } else {
      let offset, length;
      const point = bufferPoint - boundsBeginning;

      if (lang === "jsx") {
        ({ snippet, offset, length } = expandJSX(input, { cssModulesObject, classConstructor, point }));
      } else if (lang === "solid") {
        const classAttr = true;
        ({ snippet, offset, length } = expandJSX(input, { classAttr, cssModulesObject, classConstructor, point }));
      } else {
        ({ snippet, offset, length } = expandHTML(input, { point }));
      }

      start += offset;
      end = start + length;
    }

    snippet = snippet.replace(/"/g, '\\"');
    const shouldReposition = snippet.includes("|") ? "t" : "nil";
    const shouldIndent = snippet.includes("\n") ? "t" : "nil";

    bridge.evalInEmacs(`(emmet2-insert "${snippet}" ${start} ${end} ${shouldReposition} ${shouldIndent})`);
  } catch (err) {
    if (/^\[\[.+\]\]$/.test(err.message)) {
      bridge.evalInEmacs(`(message "${err.message.slice(2, -2).replace(/"/g, '\\"')}")`);
    } else {
      console.error(err);
      bridge.evalInEmacs(`(message "Something wrong with expanding \\"${input}\\"")`);
    }
  }
}
