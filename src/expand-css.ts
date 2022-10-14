import emmet from "npm:emmet";

export default function expandCSS(abbr: string): string {
  return emmet.default(abbr, { type: "stylesheet" });
}
