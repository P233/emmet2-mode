// SPDX-License-Identifier: GPL-3.0-or-later
// Fixed-version result adapter for the offline development oracle.
import expandAbbreviation, {
  parseMarkup,
  resolveConfig,
  stringifyMarkup,
} from "../vendor/emmet-2.4.11.mjs";
import { transformClasses } from "./jsx.mjs";

export class EmmetParseError extends Error {
  constructor(error, abbreviation) {
    super(error.message.split("\n")[0].replace(/ at \d+$/, ""), { cause: error });
    this.name = "EmmetParseError";
    const offsets = characterOffsets(abbreviation);
    this.position = offsets[error.pos];
    // After an escape, the tokenizer can stop inside a surrogate pair.
    // Report the containing character; other invalid offsets stay invalid.
    if (this.position === undefined && offsets[error.pos - 1] !== undefined &&
        offsets[error.pos + 1] !== undefined) {
      this.position = offsets[error.pos - 1];
    }
    this.originalMessage = error.message;
  }
}

// Convert once per output, rather than rescanning every field's prefix.
function characterOffsets(text) {
  const offsets = [0];
  let utf16 = 0;
  let characters = 0;
  for (const character of text) {
    utf16 += character.length;
    offsets[utf16] = ++characters;
  }
  return offsets;
}

function renumber(fields, firstIndex) {
  const ordered = [...fields].sort((a, b) =>
    (a.index || Infinity) - (b.index || Infinity)
  );
  const groups = new Map();
  let nextIndex = firstIndex;
  for (const field of ordered) {
    // Different defaults must not become mirrors that silently rewrite text.
    let defaults = groups.get(field.index);
    if (!defaults) groups.set(field.index, defaults = new Map());
    if (field.index === 0 || !defaults.has(field.placeholder)) {
      defaults.set(field.placeholder, nextIndex++);
    }
    field.normalizedIndex = defaults.get(field.placeholder);
  }
  return nextIndex;
}

/** Expand using a fixed preset; all offsets in the result count characters. */
export function expand(abbreviation, {
  preset = "html",
  indent = "\t",
  baseIndent = "",
  jsx,
} = {}) {
  if (typeof abbreviation !== "string" ||
      typeof indent !== "string" || typeof baseIndent !== "string") {
    throw new TypeError("Abbreviation and indentation must be strings");
  }
  // Stylesheet output is project-owned and no longer compared with Emmet.
  if (!["html", "jsx"].includes(preset)) {
    throw new TypeError(`Unknown preset: ${preset}`);
  }
  if (jsx && preset !== "jsx") throw new TypeError("JSX extensions require the JSX preset");

  const localFields = [];
  const options = {
    "output.indent": indent,
    "output.baseIndent": baseIndent,
    "output.field": (index, placeholder, offset) => {
      localFields.push({ index, placeholder, offset });
      return placeholder;
    },
  };
  if (preset === "jsx") {
    Object.assign(options, {
      "output.selfClosingStyle": "xhtml",
      "jsx.enabled": true,
      // Keep upstream attribute names, but preserve the project's authored
      // multiple-value expressions: it has never enabled styleName/prefixing.
      "markup.attributes": {
        ...resolveConfig({ type: "markup", syntax: "jsx" }).options["markup.attributes"],
        "class*": jsx?.classAttribute ?? "className",
        ...(jsx?.classAttribute === "class" && { class: "class", for: "for" }),
      },
      "markup.valuePrefix": {},
    });
  }

  const syntax = preset === "jsx" ? "jsx" : "html";
  let text;
  let fields;
  try {
    if (jsx) {
      const config = resolveConfig({ type: "markup", syntax, options });
      text = stringifyMarkup(transformClasses(parseMarkup(abbreviation, config), jsx), config);
    } else {
      text = expandAbbreviation(abbreviation, { type: "markup", syntax, options });
    }
    renumber(localFields, 1);
    fields = localFields;
  } catch (error) {
    // Both upstream scanners identify parse errors by pos; token-parser
    // errors do not carry the source string found on character-scanner errors.
    if (Number.isInteger(error.pos)) {
      throw new EmmetParseError(error, abbreviation);
    }
    throw error;
  }

  const offsets = characterOffsets(text);
  const normalized = fields.map(({ offset, placeholder, normalizedIndex }) => [
    offsets[offset], offsets[offset + placeholder.length], normalizedIndex, placeholder,
  ]).sort((a, b) => a[0] - b[0]);
  return {
    text,
    fields: normalized,
    cursor: normalized.find((field) => field[2] === 1)?.[0] ?? offsets[text.length],
  };
}
