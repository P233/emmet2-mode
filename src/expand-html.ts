import emmet from "npm:emmet";

export default function expandHTML(abbr: string): string {
  return emmet.default(abbr).replace(/"/g, '\\"');
}
