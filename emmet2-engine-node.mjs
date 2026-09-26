// Fixed-version reference adapter. S1 will reuse this boundary for Node IPC.
import expandAbbreviation, {
  parseStylesheet,
  resolveConfig,
  stringifyStylesheet,
} from "./vendor/emmet-2.4.11.mjs";

export class EmmetParseError extends Error {
  constructor(error, abbreviation) {
    super(error.message.split("\n")[0].replace(/ at \d+$/, ""), { cause: error });
    this.name = "EmmetParseError";
    this.position = characterOffsets(abbreviation)[error.pos];
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
} = {}) {
  if (typeof abbreviation !== "string" ||
      typeof indent !== "string" || typeof baseIndent !== "string") {
    throw new TypeError("Abbreviation and indentation must be strings");
  }
  if (!["html", "jsx", "stylesheet"].includes(preset)) {
    throw new TypeError(`Unknown preset: ${preset}`);
  }

  let localFields = [];
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
      "markup.attributes": { class: "classList" },
    });
  } else if (preset === "stylesheet") {
    options["stylesheet.floatUnit"] = "rem";
  }

  let text;
  let fields;
  try {
    if (preset === "stylesheet") {
      const config = resolveConfig({ type: "stylesheet", options });
      const nodes = parseStylesheet(abbreviation, config);
      const separator = config.options["output.format"]
        ? config.options["output.newline"] + baseIndent
        : "";
      const parts = [];
      fields = [];
      let length = 0;
      let nextIndex = 1;
      for (const node of nodes) {
        if (parts.length) length += separator.length;
        localFields = [];
        const part = stringifyStylesheet([node], config);
        nextIndex = renumber(localFields, nextIndex);
        for (const field of localFields) {
          fields.push({ ...field, offset: field.offset + length });
        }
        parts.push(part);
        length += part.length;
      }
      text = parts.join(separator);
    } else {
      text = expandAbbreviation(abbreviation, { type: "markup", options });
      renumber(localFields, 1);
      fields = localFields;
    }
  } catch (error) {
    if (Number.isInteger(error.pos) && typeof error.string === "string") {
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
