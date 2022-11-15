import emmet from "npm:emmet";

type JSXOptions = {
  classAttr?: boolean;
  cssModulesObject: string;
  classNamesConstructor: string;
};

type ParsedInput = {
  prefix: string;
  suffix: string;
  abbr: string;
};

export function parseInput(input: string): ParsedInput {
  if (input.startsWith("return (")) {
    const hasSemicolon = input.endsWith(";");
    const leftParenCounter = (input.match(/\(/g) || []).length;
    const rightParenCounter = (input.match(/\)/g) || []).length;

    let suffix = hasSemicolon ? ";" : "";
    let abbr = input.slice(8, hasSemicolon ? -1 : undefined);
    if (leftParenCounter === rightParenCounter) {
      suffix = ")" + suffix;
      abbr = abbr.slice(0, -1);
    }

    return {
      prefix: "return (",
      suffix,
      abbr: abbr.trim()
    };
  }

  const [_, prefix, abbr, suffix] = input.match(/((?:<.+?>\s*)*)(.+?)(<.*)?$/)!;

  return {
    prefix: prefix.trim(),
    suffix: suffix ? suffix.trim() : "",
    abbr: abbr.trim()
  };
}

export function expandHTML(input: string): string {
  const { prefix, suffix, abbr } = parseInput(input);
  const snippet = emmet.default(abbr).replace("><", ">|<");

  return prefix + snippet + suffix;
}

export function expandJSX(input: string, options: JSXOptions): string {
  const { prefix, suffix, abbr } = parseInput(input);

  let snippet = emmet.default(abbr, {
    options: {
      "output.selfClosingStyle": "xhtml", // <br />
      "jsx.enabled": true
    }
  });

  const classAttrList = snippet.match(/className=".*?"/g);
  if (classAttrList) {
    snippet = classAttrList.reduce((a: string, c: string) => {
      const idx = a.indexOf(c);
      const prefix = a.slice(0, a.indexOf(c)) + (options.classAttr ? "class={" : "className={");
      const suffix = "}" + a.slice(idx + c.length);

      const rawClass = c.match(/"(.*)"/)![1];
      if (rawClass === "") return prefix + suffix;

      const classList = rawClass.split(" ");
      const { cssModulesObject, classNamesConstructor } = options;
      if (classList.length === 1) return prefix + `${cssModulesObject}.${classList[0]}` + suffix;

      return (
        prefix + `${classNamesConstructor}(${classList.map((i) => cssModulesObject + "." + i).join(", ")})` + suffix
      );
    }, snippet);
  }

  if (snippet.includes("><")) snippet = snippet.replace("><", ">|<");
  else snippet = snippet.replace(/("|\{)("|\})/, "$1|$2");

  return prefix + snippet + suffix;
}
