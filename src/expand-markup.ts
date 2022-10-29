import emmet from "npm:emmet";

export function expandHTML(abbr: string): string {
  return emmet.default(abbr);
}

export function expandJSX(abbr: string): string {
  return emmet
    .default(abbr, {
      options: {
        "jsx.enabled": true
      }
    })
    .replace(/("(.+?)")/g, "{css.$2}");
}
