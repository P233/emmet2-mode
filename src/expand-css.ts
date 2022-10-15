import emmet from "npm:emmet";

const PROPERTY_ALIAS_MAP: Record<string, string | ((value: string, unit?: string, important?: string) => string)> = {
  all: (value: string, unit?: string, important?: string) => {
    return ["t", "r", "b", "l"].map((property) => `${property}${value}${unit || ""}${important || ""}`).join("+");
  },
  posa: "posa+z",
  posf: "posf+z"
};

function replaceAlias(abbrOrAlias: string): string {
  const _propertyMatchResult = abbrOrAlias.match(/^[a-z]+/);
  if (!_propertyMatchResult) return abbrOrAlias; // let emmet handle invalid abbr

  const abbr = PROPERTY_ALIAS_MAP[_propertyMatchResult[0]];
  if (typeof abbr === "string") return abbr;
  if (typeof abbr === "function") {
    const [_, __, value, unit, important] = abbrOrAlias.match(/([a-z]+)(\d+)?([a-z]+)?(!)?/)!;
    return abbr(value, unit, important);
  }
  return abbrOrAlias;
}

function isOpinionated(abbr: string): boolean {
  return /\(\d+\)/.test(abbr);
}

function opinionatedExpand(abbr: string): string {
  return abbr.split("+").reduce((a, c, idx) => {
    if (isOpinionated(c)) {
      const _abbrMatchResult = c.match(/^([a-z]+)(\(\d+\)?)(!?)/);
      if (!_abbrMatchResult) return a; // skip invalid abbr
      const [_, property, value, important] = _abbrMatchResult;
      return (a +=
        (idx === 0 ? "" : "\n") +
        emmet.default(property, { type: "stylesheet" }).slice(0, -1) + // remove ";" from emmet
        (property === "fz" ? `ms${value}` : `rhythm${value}`) +
        (important ? " !important;" : ";"));
    }
    return (a += (idx === 0 ? "" : "\n") + emmet.default(c, { type: "stylesheet" }));
  }, "");
}

export default function expandCSS(abbrOrAlias: string): string {
  const abbr = replaceAlias(abbrOrAlias);
  if (isOpinionated(abbr)) return opinionatedExpand(abbr);
  return emmet.default(abbr, { type: "stylesheet" });
}
