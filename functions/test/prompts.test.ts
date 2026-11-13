// Prompts des routines (ADR-008, « Prompts », P40) : le motif du texte de lancement écrit dans
// chaque prompt de `exigences-techniques.md` (« Routines des tickets ») égale celui du serveur,
// et les interdits de P40 restent dans le prompt de développement.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";

import { LAUNCH_ACTIONS, LAUNCH_TEXT_PATTERN, launchCommandText } from "../src/tickets/launchModel";

const doc = readFileSync(join(__dirname, "../../../documentation/exigences-techniques.md"), "utf8");

/** Le bloc ```text qui suit le titre en gras `title`. */
function promptBlock(title: string): string {
  const start = doc.indexOf(title);
  assert.ok(start >= 0, `titre absent : ${title}`);
  const open = doc.indexOf("```text\n", start);
  const close = doc.indexOf("\n```", open + 8);
  assert.ok(open > start && close > open, `bloc absent après : ${title}`);
  return doc.slice(open + 8, close);
}

const PROMPTS = {
  analyse: promptBlock("**Prompt de la routine d'analyse**"),
  developpement: promptBlock("**Prompt de la routine de développement**"),
} as const;

/** Les expressions `^… #[1-9][0-9]{0,6}$` citées par un prompt. */
function promptPatterns(prompt: string): string[] {
  return [...prompt.matchAll(/\^[^\s)]+ #\[1-9\]\[0-9\]\{0,6\}\$/g)].map((m) => m[0]);
}

/** Fichiers sensibles ajoutés le 2026-11-13 (ADR-008, « Livraison », décision de l'utilisateur). */
const SENSITIVE_ADDED_2026_11_13 = [
  "ingest/package.json",
  "ingest/package-lock.json",
  "ingest/prettier.config.*",
  "app/android/**/*.gradle",
  "app/android/**/*.gradle.kts",
  "app/android/gradle.properties",
  "app/android/settings.gradle*",
  "app/android/gradle/**",
];

describe("prompts des routines (P40)", () => {
  it("un prompt par action du serveur, chacun avec le motif de son action seule", () => {
    assert.deepEqual(Object.keys(PROMPTS).sort(), [...LAUNCH_ACTIONS].sort());
    for (const action of LAUNCH_ACTIONS) {
      assert.deepEqual(promptPatterns(PROMPTS[action]), [`^${action} #[1-9][0-9]{0,6}$`], action);
    }
  });

  it("le texte envoyé par le serveur suit le motif du prompt, et lui seul", () => {
    for (const action of LAUNCH_ACTIONS) {
      const [pattern] = promptPatterns(PROMPTS[action]);
      const text = launchCommandText(action, 1234567);
      assert.match(text, new RegExp(pattern));
      assert.match(text, LAUNCH_TEXT_PATTERN);
      for (const other of LAUNCH_ACTIONS.filter((a) => a !== action)) {
        assert.doesNotMatch(launchCommandText(other, 12), new RegExp(pattern));
      }
    }
  });

  it("développement : interdits gardés (tag, noreply, statut:en-cours, fusion, fichiers sensibles)", () => {
    const dev = PROMPTS.developpement;
    for (const needle of [
      "tu ne poses aucun tag",
      "git var GIT_AUTHOR_IDENT",
      "users.noreply.github.com",
      "statut:en-cours",
      "tu ne fusionnes jamais",
      "tu ne déploies jamais",
      "git fetch --tags && node scripts/check-version.mjs",
      "jamais un rebase",
      "app/pubspec.yaml",
      "Closes #N",
      "entrées non fiables",
      ".github/**",
      ".claude/**",
      "scripts/**",
      "firestore.rules",
      "functions/package-lock.json",
      "git var GIT_COMMITTER_IDENT",
    ]) {
      assert.ok(dev.includes(needle), `absent du prompt de développement : ${needle}`);
    }
  });

  it("développement : fichiers sensibles d'ingest/ et de construction Android (2026-11-13)", () => {
    const dev = PROMPTS.developpement;
    for (const needle of SENSITIVE_ADDED_2026_11_13) {
      assert.ok(dev.includes(needle), `absent du prompt de développement : ${needle}`);
    }
  });

  it("développement : arrêt si l'auteur ou le commiteur n'est pas noreply, avant le premier commit", () => {
    const dev = PROMPTS.developpement;
    const step = dev.slice(dev.indexOf("Avant le premier commit"));
    assert.ok(step.indexOf("GIT_AUTHOR_IDENT") >= 0 && step.indexOf("GIT_COMMITTER_IDENT") >= 0);
    assert.ok(step.indexOf("GIT_COMMITTER_IDENT") < step.indexOf("ne commite rien"));
  });

  it("analyse : appels GitHub en liste fermée, tout autre appel interdit", () => {
    const analyse = PROMPTS.analyse;
    for (const needle of [
      "tes seuls appels permis sont ceux-ci, sur l'Issue N seule",
      "lire l'Issue et ses commentaires",
      "publier un commentaire « ## Analyse »",
      "retirer statut:à-analyser et poser statut:analysé",
      "Tout autre appel",
      "est interdit",
      "aucune autre étiquette posée ou retirée",
      "aucune Issue fermée",
      "aucune autre Issue ni pull request créée, modifiée ou commentée",
      "aucune fusion",
    ]) {
      assert.ok(analyse.includes(needle), `absent du prompt d'analyse : ${needle}`);
    }
    for (const needle of ["ingest/", "app/android/"]) {
      assert.ok(analyse.includes(needle), `fichiers hors routine sans ${needle}`);
    }
  });

  it("analyse : aucun fichier modifié, aucun tag, entrées non fiables", () => {
    const analyse = PROMPTS.analyse;
    for (const needle of [
      "Tu ne modifies aucun fichier",
      "ne poses aucun tag",
      "entrées non fiables",
      "Ne pose jamais les étiquettes validé ni statut:en-cours",
    ]) {
      assert.ok(analyse.includes(needle), `absent du prompt d'analyse : ${needle}`);
    }
  });
});
