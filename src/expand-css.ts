import emmet from "npm:emmet@2.4.4";
import CSS_DATA from "../data/css-data.json" assert { type: "json" };

// Find function
// Sort candidates by the distance from 0 to the latest searched character; return the shortest distance candidate.
function find(abbr: string, list: string[]) {
  const regex = new RegExp(`${abbr.slice(0, 2)}.*?${abbr.slice(2).split("").join(".*?")}`);
  const candidates: { result: string; score: number }[] = [];

  for (let i = 0; i < list.length; i++) {
    if (regex.test(list[i])) {
      const result = list[i];
      candidates.push({
        result,
        score: abbr.indexOf(abbr.slice(-1))
      });
    }
  }

  if (!candidates.length) {
    return abbr;
  }

  return candidates.sort((a, b) => a.score - b.score)[0].result;
}

// Expand at rules
function expandAtRules(abbr: string): string {
  return find(abbr, CSS_DATA.atRules);
}

// Expand selectors
function findPseudoSelector(abbr: string): string {
  return find(abbr, CSS_DATA.pseudoSelectors);
}

function findPseudoFunction(abbr: string): string {
  return find(abbr, CSS_DATA.pseudoFunctions);
}

function expandSelector(abbr: string): string {
  if (!/^[\w.#-]*:[\w-]+(\(.+\))?(:.+)?$/.test(abbr)) {
    return abbr;
  }

  let [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = abbr.match(
    /^([\w.#-]*)(:[\w-]+)?(?:(:[\w-]+)\((.+)\))?(:.+)?$/
  )!;

  if (!prefix) {
    prefix = "&";
  } else if (prefix === "_") {
    prefix = "";
  }

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
      if (c.startsWith(":")) {
        a += `${pseudoFunction}(${findPseudoSelector(c)})`;
      } else {
        a += `${pseudoFunction}(${c})`;
      }
      return a;
    }, prefix) +
    (chainedPseudos || "") +
    suffix
  );
}

// Expand properties
const emmetOptions = {
  type: "stylesheet",
  options: {
    "stylesheet.floatUnit": "rem",
    "output.field": () => "" // remove placeholders
  }
};

function expandProperties(abbr: string, isCSSinJS?: boolean): string {
  const propertiesList = abbr
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
        if (functionParam) {
          value =
            propertyName === "fz"
              ? `ms${functionParam}`
              : functionParam
                  .match(/\(-?[\d.]+\)/g)!
                  .map((i) => `rhythm${i}`)
                  .join(" ");
        } else if (customProperty) {
          value = customProperty.replace(/(-(-?\w+)+)/g, " var($1)").trim();
        } else if (rawValue) {
          value = rawValue.slice(1, -1); // remove "[" and "]"
        }

        property = emmet(propertyName, emmetOptions).replace(/;$/, "") + value + (flag ? " !important;" : ";");
      } else {
        // Emmet rules
        // Convert camelCase to `property:value` form
        if (/^-?[a-z]+[A-Z]/.test(c)) {
          c = c.replace(/([A-Z])/, (g) => ":" + g.toLowerCase());
        }
        property = emmet(c, emmetOptions);
      }

      property = property.replace(/\s+/, " ");

      a.push(property);
      return a;
    }, []);

  let snippet = "";
  if (isCSSinJS) {
    snippet = propertiesList
      .map((i) => {
        let [property, value] = i.split(": ");
        property = property.replace(/(-[a-z])/g, (g) => g.slice(1).toUpperCase());
        value = value.slice(0, -1); // Remove trailing `;`
        value = /^-?\d+\.?\d*(px)?$/.test(value) ? value.replace("px", "") : value ? `"${value}"` : "";
        return `${property}: ${value}`;
      })
      .join(", ");
  } else {
    snippet = propertiesList.join("\n");
  }

  // Add "|" to represent the cursor position; it will be replaced in the elisp code.
  if (/\(\)|""/.test(snippet)) {
    snippet = snippet.replace(/(\(|")(\)|")/, "$1|$2");
  } else if (isCSSinJS) {
    snippet = snippet.replace(/\s("?,|"$)/, " |$1");
  } else {
    return snippet.replace(" ;", " |;");
  }

  return snippet;
}

export function expandCSS(abbr: string): string {
  if (abbr.startsWith("@")) {
    return expandAtRules(abbr);
  }

  if (abbr.includes(":")) {
    return expandSelector(abbr);
  }

  return expandProperties(abbr);
}

export function expandCSSinJS(abbr: string): string {
  return expandProperties(abbr, true);
}
