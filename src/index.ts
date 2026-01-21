import { DenoBridge } from "https://deno.land/x/denobridge@0.0.1/mod.ts";
import { expandCSS, expandCSSinJS } from "./expand-css.ts";
import { expandHTML, expandJSX } from "./expand-markup.ts";

const bridge = new DenoBridge(Deno.args[0], Deno.args[1], Deno.args[2], messageDispatcher);

function messageDispatcher(message: string) {
  let parsedMessage: unknown[];
  try {
    const parsed = JSON.parse(message);
    if (!Array.isArray(parsed) || !Array.isArray(parsed[1])) {
      throw new Error("Invalid message format");
    }
    parsedMessage = parsed[1];
  } catch {
    console.error("Failed to parse message:", message);
    return;
  }

  const [lang, input, boundsBeginning, bufferPoint, cssModulesObject = "styles", classConstructor = "clsx"] = parsedMessage as [
    string,
    string,
    number,
    number,
    string?,
    string?
  ];

  try {
    let snippet = "";
    let start = boundsBeginning;
    let end = boundsBeginning + input.length;

    if (lang === "css") {
      snippet = expandCSS(input);
    } else if (lang === "css-in-js") {
      snippet = expandCSSinJS(input);
    } else {
      let offset: number;
      let length: number;
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

    snippet = snippet.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    const shouldReposition = snippet.includes("|") ? "t" : "nil";
    const shouldIndent = snippet.includes("\\n") ? "t" : "nil";

    bridge.evalInEmacs(`(emmet2-insert "${snippet}" ${start} ${end} ${shouldReposition} ${shouldIndent})`);
  } catch (err) {
    if (err instanceof Error && /^\[\[.+\]\]$/.test(err.message)) {
      bridge.evalInEmacs(`(message "${err.message.slice(2, -2).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}")`);
    } else {
      console.error(err);
      bridge.evalInEmacs(`(message "Something wrong with expanding \\"${input.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}\\"")`);
    }
  }
}
