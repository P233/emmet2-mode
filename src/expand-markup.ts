import emmet from "npm:emmet@2.4.11";
import { MARKUP_ABBR_REGEX } from "./regex.ts";

type JSXOptions = {
  classAttr?: boolean;
  cssModulesObject: string;
  classConstructor: string;
  point: number;
};

type AbbrAndPositions = {
  abbr: string;
  offset: number;
  length: number;
};

export function extractAbbr(line: string, point: number): AbbrAndPositions {
  const abbrs = line.match(MARKUP_ABBR_REGEX);
  if (!abbrs) {
    throw new Error(`[[Invalid abbreviation: "${line}"]]`);
  }

  if (abbrs.length === 1) {
    const abbr = abbrs[0].trim();
    const offset = line.indexOf(abbr);
    const end = offset + abbr.length - 1; // -1 convert length to index

    if ((point > offset && point < end) || point === offset || point === end || point === end + 1) {
      return { abbr, offset, length: abbr.length };
    }

    throw new Error("[[There is no abbr under the point]]");
  }

  let offset = line.indexOf(abbrs[0]);
  let _line = line.slice(offset);

  for (let i = 0; i < abbrs.length; i++) {
    let abbr = abbrs[i];
    const end = offset + abbr.length - 1; // -1 convert length to index
    if (
      (point > offset && point < end) ||
      point === offset ||
      point === end ||
      (i === abbrs.length - 1 && point === end + 1)
    ) {
      abbr = abbr.trim();
      return { abbr, offset, length: abbr.length };
    }

    const nextAbbrIdx = _line.indexOf(abbrs[i + 1]);
    offset += nextAbbrIdx;
    _line = _line.slice(nextAbbrIdx);
  }

  throw new Error("[[There is no abbr under the point]]");
}

export function expandHTML(line: string, { point }: { point: number }) {
  const { abbr, offset, length } = extractAbbr(line, point);
  const snippet = emmet(abbr).replace("></", ">|</"); // Add "|" to represent the cursor position; it will be replaced in the elisp code.
  return { snippet, offset, length };
}

export function expandJSX(line: string, options: JSXOptions) {
  const { abbr, offset, length } = extractAbbr(line, options.point);

  let snippet = emmet(abbr, {
    options: {
      "output.selfClosingStyle": "xhtml", // use the <br /> form
      "jsx.enabled": true,
      "markup.attributes": {
        class: "classList" // "classList" is a placeholder that will be replaced with either "class=" or "className=" later.
      }
    }
  });

  const classAttrList = snippet.match(/classList=".*?"/g);
  if (classAttrList) {
    snippet = classAttrList.reduce((a: string, c: string) => {
      const idx = a.indexOf(c);
      const prefix = a.slice(0, a.indexOf(c)) + (options.classAttr ? "class={" : "className={");
      const suffix = "}" + a.slice(idx + c.length);

      const rawClass = c.match(/"(.*)"/)![1];
      if (rawClass === "") {
        return prefix + suffix;
      }

      const classList = rawClass.split(" ");
      const { cssModulesObject, classConstructor } = options;
      if (classList.length === 1) {
        return prefix + `${cssModulesObject}.${classList[0]}` + suffix;
      }

      return prefix + `${classConstructor}(${classList.map((i) => cssModulesObject + "." + i).join(", ")})` + suffix;
    }, snippet);
  }

  // Add "|" to represent the cursor position; it will be replaced in the elisp code.
  if (snippet.includes("></")) {
    snippet = snippet.replace("></", ">|</");
  } else {
    snippet = snippet.replace(/("|\{)("|\})/, "$1|$2");
  }

  return { snippet, offset, length };
}
