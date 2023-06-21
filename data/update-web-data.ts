// Web data reference:
// https://github.com/microsoft/vscode-custom-data/tree/main/web-data

const cssDataResponse = await fetch(
  "https://raw.githubusercontent.com/microsoft/vscode-custom-data/main/web-data/data/browsers.css-data.json"
);
const CSS_DATA = await cssDataResponse.json();

const SASS_AT_RULES = [
  '@use "|";',
  '@forward "|";',
  '@import "|"',
  "@mixin | {\n\t\n}",
  "@include ",
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
    .filter((i) => !i.name.startsWith("@-") && i.name !== "@import")
    .map((i) => i.name + " ")
    .concat(SASS_AT_RULES)
    .sort(),
  pseudoFunctions: pseudos
    .filter((i) => i.endsWith("()"))
    .map((i) => i.slice(0, -2))
    .sort(),
  pseudoSelectors: pseudos.filter((i) => !i.endsWith("()")).sort()
};

Deno.writeTextFileSync("./data/css-data.json", JSON.stringify(slimedCSSData, null, 2));
