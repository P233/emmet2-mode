import emmet from "npm:emmet";
import cssData from "../data/css-data.json" assert { type: "json" };

const emmetOptions = {
  type: "stylesheet"
};

// Find functions
function find(abbr: string, list: string[]) {
  const regex = new RegExp(`${abbr.slice(0, 2)}.*?${abbr.slice(2).split("").join(".*?")}`);

  for (let i = 0; i < list.length; i++) {
    if (regex.test(list[i])) {
      return list[i];
    }
  }
}

// Expand at rules
function expandAtRules(abbr: string): string {
  return find(abbr, cssData.atRules) || abbr;
}

// Expand selectors
function findPseudoSelector(abbr: string): string {
  return find(abbr, cssData.pseudoSelectors) || abbr;
}

function findPseudoFunction(abbr: string): string {
  return find(abbr, cssData.pseudoFunctions) || abbr;
}

function expandSelector(abbr: string): string {
  if (!/^[\w.#-]*:[\w-]+(\(.+\))?(:.+)?$/.test(abbr)) return abbr;

  const suffix = " {\n\t|\n}";

  let [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = abbr.match(
    /^([\w.#-]*)(:[\w-]+)?(?:(:[\w-]+)\((.+)\))?(:.+)?$/
  )!;

  if (!prefix) prefix = "&";
  else if (prefix === "_") prefix = "";

  if (chainedPseudos) {
    chainedPseudos = chainedPseudos
      .split(/(?=:)/g)
      .map((i) => findPseudoSelector(i))
      .join("");
  }

  if (pseudoSelector) {
    pseudoSelector = findPseudoSelector(pseudoSelector);
    return prefix + pseudoSelector + (chainedPseudos || "") + suffix;
  }

  pseudoFunction = findPseudoFunction(pseudoFunction);
  return (
    pseudoParams.split(",").reduce((a, c) => {
      c = c.trim();
      if (c.startsWith(":")) a += `${pseudoFunction}(${findPseudoSelector(c)})`;
      else a += `${pseudoFunction}(${c})`;
      return a;
    }, prefix) +
    (chainedPseudos || "") +
    suffix
  );
}

// Expand properties
function expandProperties(abbr: string): string {
  const snippet = abbr
    .replace(/\bpos(a|f)(.+?)?(?=,|\+|$)/g, "pos$1+z$2") // posa => posa+z, posf => posf+z
    .replace(/\ball(.+?)?(?=,|\+|$)/g, "t$1+r$1+b$1+l$1") // all => t+r+b+l
    .replace(/\bfw(\d)\b/g, "fw$100") // fw7 => fw700
    .replace(/\b(ma|mi)?(w|h)f\b/g, "$1$2100p") // wf => w100p, hf => h100p, etc.
    .split(/[,+]/)
    .reduce((a: string[], c: string) => {
      // Opinionated Rules
      if (/^-?[a-z]+((\(-?\d*\.?\d+\))*|--[\w-]+|\[.+?\])!?$/.test(c)) {
        const [_, property, functionParam, cpValue, rawValue, flag] = c.match(
          /^(-?[a-z]+)(\(.+\))?(--[\w-]+)?(\[.+?\])?(!)?/
        )!;

        let value = "";
        // prettier-ignore
        if (functionParam) value = property === "fz" ? `ms${functionParam}` : functionParam.match(/\([\d.]+\)/g)!.map((i) => `rhythm${i}`).join(" ");
        else if (cpValue) value = cpValue.replace(/(-(-?\w+)+)/g, " var($1)").trim();
        else if (rawValue) value = rawValue.slice(1, -1); // remove "[" and "]"

        a.push(emmet.default(property, emmetOptions).replace(/(#000)?;$/, "") + value + (flag ? " !important;" : ";"));
        return a;
      }

      // Convert camelCase
      if (/^-?[a-z]+[A-Z]/.test(c)) c = c.replace(/([A-Z])/, (g) => ":" + g.toLowerCase());

      a.push(emmet.default(c, emmetOptions).replace(/#000/, ""));
      return a;
    }, [])
    .join("\n");

  if (snippet.includes("()")) return snippet.replace("()", "(|)");
  return snippet.replace(": ;", ": |;");
}

// main
export default function expandCSS(abbr: string): string {
  if (abbr.startsWith("@")) return expandAtRules(abbr);
  if (abbr.includes(":")) return expandSelector(abbr);
  return expandProperties(abbr);
}
