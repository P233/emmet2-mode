import emmet from "npm:emmet";
import Flexsearch from "npm:flexsearch";
import cssData from "../data/css-data.json" assert { type: "json" };

const flexsearchOptions = {
  tokenize: "forward"
};

// Expand at rules
const atRulesIndex = new Flexsearch.Index(flexsearchOptions);
cssData.atRules.forEach((i, idx) => atRulesIndex.add(idx, i));

function expandAtRules(abbr: string): string {
  const searchResult = atRulesIndex.search(abbr, 1);
  if (!searchResult.length) return abbr;
  return cssData.atRules[searchResult[0]];
}

// Expand selectors
const pseudoSelectorsIndex = new Flexsearch.Index(flexsearchOptions);
cssData.pseudoSelectors.forEach((i, idx) => pseudoSelectorsIndex.add(idx, i));

function searchPseudoSelector(s: string): string {
  const searchResult = pseudoSelectorsIndex.search(s, 1);
  if (!searchResult.length) return s;
  return cssData.pseudoSelectors[searchResult[0]];
}

const pseudoFunctionsIndex = new Flexsearch.Index(flexsearchOptions);
cssData.pseudoFunctions.forEach((i, idx) => pseudoFunctionsIndex.add(idx, i));

function searchPseudoFunction(s: string): string {
  const searchResult = pseudoFunctionsIndex.search(s, 1);
  if (!searchResult.length) return s;
  return cssData.pseudoFunctions[searchResult[0]];
}

function expandSelector(abbr: string): string {
  if (!/^[\w.#-]*:[\w-]+(\(.+\))?$/.test(abbr)) return abbr;

  let [_, prefix, pseudoSelector, __, pseudoFunction, pseudoParams] = abbr.match(
    /^([\w.#-]*)(:[\w-]+)?((:[\w-]+)\((.+)\))?$/
  )!;

  if (!prefix) prefix = "&";
  else if (prefix === "_") prefix = "";

  if (pseudoSelector) {
    pseudoSelector = searchPseudoSelector(pseudoSelector);
    return prefix + pseudoSelector;
  }

  pseudoFunction = searchPseudoFunction(pseudoFunction);
  return pseudoParams.split(",").reduce((a, c) => {
    c = c.trim();
    if (c.startsWith(":")) a += `${pseudoFunction}(${searchPseudoSelector(c)})`;
    else a += `${pseudoFunction}(${c})`;
    return a;
  }, prefix);
}

// Expand properties
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

// main
export default function expandCSS(abbr: string): string {
  if (abbr.startsWith("@")) return expandAtRules(abbr);
  if (abbr.includes(":")) return expandSelector(abbr);
  return expandProperties(abbr);
}
