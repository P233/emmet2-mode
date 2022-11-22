import emmet from "npm:emmet";
import cssData from "../data/css-data.json" assert { type: "json" };

const emmetOptions = {
  type: "stylesheet"
};

// Find function
function find(abbr: string, list: string[]) {
  const regex = new RegExp(`${abbr.slice(0, 2)}.*?${abbr.slice(2).split("").join(".*?")}`);

  for (let i = 0; i < list.length; i++) {
    if (regex.test(list[i])) {
      return list[i];
    }
  }
  return abbr;
}

// Expand at rules
function expandAtRules(abbr: string): string {
  return find(abbr, cssData.atRules);
}

// Expand selectors
function findPseudoSelector(abbr: string): string {
  return find(abbr, cssData.pseudoSelectors);
}

function findPseudoFunction(abbr: string): string {
  return find(abbr, cssData.pseudoFunctions);
}

function expandSelector(abbr: string): string {
  if (!/^[\w.#-]*:[\w-]+(\(.+\))?(:.+)?$/.test(abbr)) return abbr;

  let [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = abbr.match(
    /^([\w.#-]*)(:[\w-]+)?(?:(:[\w-]+)\((.+)\))?(:.+)?$/
  )!;

  if (!prefix) prefix = "&";
  else if (prefix === "_") prefix = "";

  const suffix = " {\n\t|\n}";

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
function expandProperties(abbr: string, isCSSinJS?: boolean): string {
  let snippet = "";

  snippet = abbr
    .replace(/\bpos(a|f)(.+?)?(?=,|\+|$)/g, "pos$1+z$2") // posa => posa+z, posf => posf+z
    .replace(/\ball(.+?)?(?=,|\+|$)/g, "t$1+r$1+b$1+l$1") // all => t+r+b+l
    .replace(/\bfw(\d)\b/g, "fw$100") // fw7 => fw700
    .replace(/\b(ma|mi)?(w|h)f\b/g, "$1$2100p") // wf => w100p, hf => h100p, etc.
    .split(/[,+]/)
    .reduce((a: string[], c: string) => {
      let property = "";

      if (/^-?[a-z]+((\(-?\d*\.?\d+\))*|--[\w-]+|\[.+?\])!?$/.test(c)) {
        // Opinionated rules
        // prettier-ignore
        const [_, propertyName, functionParam, customProperty, rawValue, flag] = c.match(/^(-?[a-z]+)(\(.+\))?(--[\w-]+)?(\[.+?\])?(!)?/)!;

        let value = "";
        // prettier-ignore
        if (functionParam) value = propertyName === "fz" ? `ms${functionParam}` : functionParam.match(/\([\d.]+\)/g)!.map((i) => `rhythm${i}`).join(" ");
        else if (customProperty) value = customProperty.replace(/(-(-?\w+)+)/g, " var($1)").trim();
        else if (rawValue) value = rawValue.slice(1, -1); // remove "[" and "]"

        property = emmet.default(propertyName, emmetOptions).replace(/(#000)?;$/, "");
        property = property + value + (flag ? " !important;" : ";");
      } else {
        // Default Emmet rules
        // Convert camelCase to `property:value` format
        if (/^-?[a-z]+[A-Z]/.test(c)) c = c.replace(/([A-Z])/, (g) => ":" + g.toLowerCase());
        property = emmet.default(c, emmetOptions).replace(/#000/, "");
      }

      a.push(property);
      return a;
    }, []);

  if (isCSSinJS) {
    snippet = snippet
      .map((i) => {
        let [property, value] = i.split(": ");
        property = property.replace(/(-[a-z])/g, (g) => g.slice(1).toUpperCase());
        value = value.slice(0, -1); // Remove trailing `;`
        value = /^-?\d+\.?\d*(px)?$/.test(value) ? value.replace("px", "") : `"${value}"`;
        return `${property}: ${value}`;
      })
      .join(", ");
  } else {
    snippet = snippet.join("\n");
  }

  // Add | to represent the cursor position
  if (/\(\)|""/.test(snippet)) {
    snippet = snippet.replace(/(\(|")(\)|")/, "$1|$2");
  } else {
    snippet = snippet.replace(/: (;|,)/, ": |$1");
  }

  return snippet;
}

export function expandCSS(abbr: string): string {
  if (abbr.startsWith("@")) return expandAtRules(abbr);
  if (abbr.includes(":")) return expandSelector(abbr);
  return expandProperties(abbr);
}

export function expandCSSinJS(abbr: string): string {
  return expandProperties(abbr, true);
}
