import emmet from "npm:emmet";

export default function expandHTML(abbr: string): string {
  return emmet
    .default(abbr, {
      options: {
        "jsx.enabled": true
      }
    })
    .replace(/("(.+?)")/g, "{css.$2}");
}
