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
  if (!_propertyMatchResult) return abbrOrAlias;

  const abbr = PROPERTY_ALIAS_MAP[_propertyMatchResult[0]];
  if (typeof abbr === "string") return abbr;
  if (typeof abbr === "function") {
    const [_, __, value, unit, important] = abbrOrAlias.match(/([a-z]+)(\d+)?([a-z]+)?(!)?/)!;
    return abbr(value, unit, important);
  }
  return abbrOrAlias;
}

export default function expandCSS(abbrOrAlias: string): string {
  const abbr = replaceAlias(abbrOrAlias);
  return emmet.default(abbr, { type: "stylesheet" });
}
