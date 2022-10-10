import cssSnippets from "../data/css-snippets.ts";

function parseUnit(unit: string) {
  if (!unit) return "";
  if (unit === "p") return "%";
  return unit;
}

export default function expandCSS(abbr: string) {
  const properties = abbr.split("+").reduce((a, c) => {
    const reg = /([a-z]+)(\d+)?([a-z]+)?(!)?/;
    const [_, property, value, unit, important] = c.match(reg);

    let snippet = cssSnippets[property];
    if (snippet) {
      if (snippet.includes("|")) {
        snippet = snippet.replace("|", `${value}${parseUnit(unit)}`);
      }

      if (important) {
        snippet = snippet.replace(";", " !important;");
      }

      a.push(snippet);
    }

    return a;
  }, []);

  if (!properties.length) return abbr;
  return properties.join("\n");
}
