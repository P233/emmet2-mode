// SPDX-License-Identifier: GPL-3.0-or-later
// Independent JSX reference for the offline development oracle.
// Operate before serialization: quoted class values cannot be recovered safely
// from Emmet's rendered markup (it does not escape embedded attribute quotes).

const identifier = /^[a-zA-Z_$][a-zA-Z0-9_$]*$/;
const escape = (character) => JSON.stringify(character).slice(1, -1)
  .replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");

function classExpression(value, object, constructor) {
  let text = "";
  const fields = [];
  for (const token of value ?? [{ type: "Field", index: 0, name: "" }]) {
    if (typeof token === "string") text += token;
    else {
      fields.push({ ...token, beg: text.length, end: text.length + token.name.length });
      text += token.name;
    }
  }
  const words = Array.from(text.matchAll(/\S+/g), (match) => [match.index, match.index + match[0].length]);
  const empty = [];
  let wordIndex = 0;
  for (const field of fields) {
    while (words[wordIndex] && (words[wordIndex][1] < field.beg ||
      (field.beg !== field.end && words[wordIndex][1] === field.beg))) wordIndex++;
    const word = words[wordIndex];
    const intersects = word && (field.beg === field.end ? word[0] <= field.beg
      : word[0] < field.end && field.beg < word[1]);
    if (!intersects && empty.at(-1)?.[0] !== field.beg) {
      empty.push([field.beg, field.end]);
    }
  }
  words.push(...empty);
  words.sort((a, b) => a[0] - b[0]);
  if ((words.length && !object.trim()) || (words.length > 1 && !constructor.trim())) {
    throw new TypeError("JSX class expressions require nonempty project references");
  }
  const offsets = new Array(text.length + 1);
  let output = words.length > 1 ? `${constructor}(` : words.length ? "" : '""';
  for (let i = 0; i < words.length; i++) {
    const [beg, end] = words[i];
    const word = text.slice(beg, end).trim();
    if (i) output += ", ";
    const dot = identifier.test(word);
    output += dot ? `${object}.` : `${object}["`;
    offsets[beg] = output.length;
    let position = beg;
    for (const character of word) {
      output += dot ? character : escape(character);
      position += character.length;
      offsets[position] = output.length;
    }
    offsets[end] = output.length;
    if (!dot) output += '"]';
  }
  // Whitespace outside class tokens collapses; a field spanning multiple class
  // names covers the intervening expression syntax too, without dropping it.
  let last = 0;
  for (let i = 0; i < offsets.length; i++) {
    last = offsets[i] ?? last;
    offsets[i] = last;
  }
  if (words.length > 1) output += ")";
  const tokens = [];
  let start = 0;
  for (const field of fields) {
    const beg = offsets[field.beg];
    const end = offsets[field.end];
    tokens.push(output.slice(start, beg));
    tokens.push({ type: "Field", index: field.index, name: output.slice(beg, end) });
    start = end;
  }
  tokens.push(output.slice(start));
  return tokens;
}

export function transformClasses(abbreviation, { classAttribute, cssModulesObject, classConstructor }) {
  if (!["className", "class"].includes(classAttribute) ||
      typeof cssModulesObject !== "string" || typeof classConstructor !== "string") {
    throw new TypeError("Invalid JSX extension options");
  }
  function node(current) {
    return {
      ...current,
      children: current.children.map(node),
      ...(current.attributes && {
        attributes: current.attributes.map((attribute) => attribute.name === "class" ? {
          ...attribute,
          name: classAttribute,
          value: attribute.valueType === "expression" ? attribute.value
            : classExpression(attribute.value, cssModulesObject, classConstructor),
          valueType: "expression",
        } : attribute),
      }),
    };
  }
  return { ...abbreviation, children: abbreviation.children.map(node) };
}
