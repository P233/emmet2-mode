import js from "@eslint/js";

export default [
  // The pinned upstream bundle is verified by checksum, never edited.
  { ignores: ["test/vendor/**", "plans/**"] },
  js.configs.recommended,
  {
    files: ["**/*.mjs"],
    languageOptions: {
      globals: {
        AbortSignal: "readonly", Buffer: "readonly", URL: "readonly",
        console: "readonly", fetch: "readonly", process: "readonly",
        structuredClone: "readonly",
      },
    },
    rules: { "prefer-const": "error" },
  },
];
