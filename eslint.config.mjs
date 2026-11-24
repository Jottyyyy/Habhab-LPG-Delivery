import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["app/**", "web/**", "db/migrations/**", ".vercel/**", "node_modules/**"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: { globals: { ...globals.node } },
    rules: {
      // `any` is only allowed with an explanatory eslint-disable comment.
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
    },
  },
  {
    // Server code: never log request bodies or personal data; only console.error/warn.
    files: ["api/**/*.ts"],
    rules: { "no-console": ["error", { allow: ["error", "warn"] }] },
  },
);
