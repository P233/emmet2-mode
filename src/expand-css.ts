import emmet from "npm:emmet";
import Flexsearch from "npm:flexsearch";
import cssData from "../data/css-data.json" assert { type: "json" };

const atRulesIndex = new Flexsearch.Index({ tokenize: "full" });
cssData.atRules.forEach((i, idx) => atRulesIndex.add(idx, i));

function expandAtRules(abbr: string): string {
  const searchResult = atRulesIndex.search(abbr, 1);
  if (!searchResult.length) return abbr;
  return cssData.atRules[searchResult[0]];
}


function expandProperties(abbr: string): string {
  return abbr
    .replace(/\bpos(a|f)(.+?)?(?=,|\+|$)/g, "pos$1+z$2") // posa => posa+z, posf => posf+z
    .replace(/\ball(.+?)?(?=,|\+|$)/g, "t$1+r$1+b$1+l$1") // all => t+r+b+l
    .split(/[,+]/)
    .reduce((a: string[], c: string) => {
      // Opinionated Rules
      if (/^-?[a-z]+(\(-?\d*\.?\d+\)|--[\w-]+|\[.+?\])!?$/.test(c)) {
        const [_, property, functionParam, cpValue, rawValue, flag] = c.match(
          /^(-?[a-z]+)(\(-?\d*\.?\d+\))?(--[\w-]+)?(\[.+?\])?(!)?/
        )!;

        let value = "";
        if (functionParam) value = property === "fz" ? `ms${functionParam}` : `rhythm${functionParam}`;
        else if (cpValue) value = cpValue.replace(/(--\w+)/g, " var($1)").trim();
        else if (rawValue) value = rawValue.slice(1, -1); // remove "[" and "]"

        a.push(emmet.default(property, { type: "stylesheet" }).slice(0, -1) + value + (flag ? " !important;" : ";"));
        return a;
      }

      // Convert camelCase
      if (/^-?[a-z]+[A-Z]/.test(c)) c = c.replace(/([A-Z])/, ":$1").toLowerCase();

      a.push(emmet.default(c, { type: "stylesheet" }));
      return a;
    }, [])
    .join("\n");
}

export default function expandCSS(abbr: string): string {
  if (abbr.startsWith("@")) return expandAtRules(abbr);
  return expandProperties(abbr);
}
