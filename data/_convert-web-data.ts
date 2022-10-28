import CSS_DATA from "./browsers.css-data.json" assert { type: "json" };

const pseudos = [...CSS_DATA.pseudoClasses, ...CSS_DATA.pseudoElements].map((i) => i.name);

const slimedCSSData = {
  atRules: CSS_DATA.atDirectives.map((i) => i.name).filter((i) => !i.startsWith("@-")),
  pseudoFunctions: pseudos.filter((i) => i.endsWith("()")),
  pseudoSelectors: pseudos.filter((i) => !i.endsWith("()"))
};

Deno.writeTextFileSync("./data/css-data.json", JSON.stringify(slimedCSSData, null, 2));
