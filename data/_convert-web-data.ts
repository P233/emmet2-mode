import CSS_DATA from "./browsers.css-data.json" assert { type: "json" };

const SASS_AT_RULES = [
  '@use "|";',
  '@forward "|";',
  '@import "|"',
  "@mixin | {\n\t\n}",
  "@include |;",
  "@function | {\n\t@return \n}",
  "@extend |;",
  "@at-root | {\n\t\n}",
  '@error "|";',
  '@warn "|";',
  "@debug |;",
  "@while | {\n\t\n}",
  "@each $| in $ {\n\t\n}",
  "@if | {\n\t\n}",
  "@if not | {\n\t\n}",
  "@else if not | {\n\t\n}",
  "@else if | {\n\t\n}",
  "@else {\n\t|\n}",
  "@for $| from 1 {\n\t\n}"
];

const pseudos = [...CSS_DATA.pseudoClasses, ...CSS_DATA.pseudoElements].map((i) => i.name);

const slimedCSSData = {
  atRules: CSS_DATA.atDirectives
    .map((i) => i.name + " ")
    .filter((i) => !i.startsWith("@-"))
    .concat(SASS_AT_RULES)
    .reverse(),
  pseudoFunctions: pseudos.filter((i) => i.endsWith("()")).map((i) => i.slice(0, -2)),
  pseudoSelectors: pseudos.filter((i) => !i.endsWith("()"))
};

Deno.writeTextFileSync("./data/css-data.json", JSON.stringify(slimedCSSData, null, 2));
