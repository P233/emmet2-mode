import emmet from "npm:emmet";

type JSXOptions = {
  classAttr?: true;
};

export function expandHTML(abbr: string): string {
  return emmet.default(abbr).replace("><", ">|<");
}

export function expandJSX(abbr: string, { classAttr }: JSXOptions = {}): string {
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
      const prefix = a.slice(0, a.indexOf(c)) + (classAttr ? "class={" : "className={");
      const suffix = "}" + a.slice(idx + c.length);

      const rawClass = c.match(/"(.*)"/)![1];
      if (rawClass === "") return prefix + suffix;

      const classList = rawClass.split(" ");
      if (classList.length === 1) return prefix + `css.${classList[0]}` + suffix;
      return prefix + "clsx(" + classList.map((i) => `css.${i}`).join(", ") + ")" + suffix;
    }, snippet);
  }

  if (snippet.includes("><")) return snippet.replace("><", ">|<");
  return snippet.replace(/("|{)("|})/, "$1|$2");
}
