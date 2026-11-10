// ESLint des Cloud Functions (ADR-006). Règles de correction seulement : le style est
// laissé à Prettier.

import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["lib/**", "build-test/**", "node_modules/**", "*.mjs"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      // Aucun catch silencieux (CLAUDE.md, « Règles de code ») : un catch vide est une
      // erreur, et une variable d'erreur inutilisée aussi (elle part à logError).
      "no-empty": ["error", { allowEmptyCatch: false }],
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrors: "all" },
      ],
      // Une promesse non attendue sort de la fonction avant son écriture.
      "@typescript-eslint/no-floating-promises": "error",
      "no-console": "error",
      // Leçon 5 et P26 : ni SDK GitHub, ni client Cloud Logging.
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            { group: ["@octokit/*", "octokit"], message: "Client GitHub par fetch (P26)." },
            {
              group: ["@google-cloud/logging", "@google-cloud/logging/*"],
              message: "Journal par firebase-functions/logger (leçon 5).",
            },
          ],
        },
      ],
    },
  },
  {
    files: ["**/*.ts"],
    languageOptions: {
      parserOptions: { project: "./tsconfig.test.json", tsconfigRootDir: import.meta.dirname },
    },
  },
  {
    // describe() et it() de node:test rendent une promesse que le lanceur attend.
    files: ["test/**/*.ts"],
    rules: { "@typescript-eslint/no-floating-promises": "off" },
  },
);
