import emmet from "npm:emmet@2.4.11";
import CSS_DATA from "../data/css-data.json" with { type: "json" };
import {
  SELECTOR_REGEX,
  SELECTOR_ELEMENTS_REGEX,
  OPINIONATED_PROPERTY_REGEX,
  OPINIONATED_ELEMENTS_REGEX,
  CSS_IN_JS_NUMBER_REGEX
} from "./regex.ts";

// Find function
// Sort candidates by the distance from 0 to the latest searched character; return the shortest distance candidate.
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
  if (!SELECTOR_REGEX.test(abbr)) {
    return abbr;
  }

  const match = abbr.match(SELECTOR_ELEMENTS_REGEX);
  if (!match) {
    return abbr;
  }

  let [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = match;

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
  type: "stylesheet" as const,
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

      if (OPINIONATED_PROPERTY_REGEX.test(c)) {
        const elementsMatch = c.match(OPINIONATED_ELEMENTS_REGEX);
        if (!elementsMatch) {
          a.push(emmet(c, emmetOptions));
          return a;
        }

        const [_, propertyName, functionParam, customProperty, rawValue, flag] = elementsMatch;

        let value = "";
        if (functionParam) {
          const rhythmMatches = functionParam.match(/\(-?[\d.]+\)/g);
          value =
            propertyName === "fz"
              ? `ms${functionParam}`
              : rhythmMatches
                  ? rhythmMatches.map((i) => (i === "(0)" ? "0" : `rhythm${i}`)).join(" ")
                  : "";
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
        value = CSS_IN_JS_NUMBER_REGEX.test(value) ? value.replace("px", "") : value ? `"${value}"` : "";
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
