// Prompts des routines (ADR-008, « Prompts », P40) : le motif du texte de lancement écrit dans
// chaque prompt de `exigences-techniques.md` (« Routines des tickets ») égale celui du serveur,
// routine par routine (analyse : `analyse` ; développement : `developpement`, `livraison`,
// `reprise`), les interdits de P40 restent dans le prompt de développement, et la liste L3
// des fichiers sensibles égale celle de `delivery.ts` (tableau « Logique dupliquée »).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";

import { SENSITIVE_DELIVERY_PATTERNS, isSensitiveDeliveryPath } from "../src/tickets/delivery";
import {
  LAUNCH_ACTIONS,
  LAUNCH_ROUTINE,
  LAUNCH_TEXT_PATTERN,
  launchCommandText,
  type LaunchAction,
} from "../src/tickets/launchModel";

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

/** Les actions envoyées à chaque routine, tirées de `LAUNCH_ROUTINE`. */
function actionsOf(routine: keyof typeof PROMPTS): LaunchAction[] {
  return LAUNCH_ACTIONS.filter((a) => LAUNCH_ROUTINE[a] === routine);
}

/** Le motif attendu dans le prompt d'une routine. */
function expectedPattern(routine: keyof typeof PROMPTS): string {
  const actions = actionsOf(routine);
  const head = actions.length === 1 ? actions[0] : `(${actions.join("|")})`;
  return `^${head} #[1-9][0-9]{0,6}$`;
}

/** Les motifs de la liste L3 du prompt de développement, un par ligne « - motif ». */
function l3Patterns(prompt: string): string[] {
  const start = prompt.indexOf("\nL3. ");
  const end = prompt.indexOf("\nL4. ", start);
  assert.ok(start >= 0 && end > start, "bloc L3 absent");
  return prompt
    .slice(start, end)
    .split("\n")
    .map((line) => /^\s+- (\S+)$/.exec(line)?.[1])
    .filter((p): p is string => p !== undefined);
}

/** Les expressions `^… #[1-9][0-9]{0,6}$` citées par un prompt. */
function promptPatterns(prompt: string): string[] {
  return [...prompt.matchAll(/\^\S+? #\[1-9\]\[0-9\]\{0,6\}\$/g)].map((m) => m[0]);
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
  it("un prompt par routine, chacun avec le motif de ses seules actions", () => {
    assert.deepEqual(
      Object.keys(PROMPTS).sort(),
      [...new Set(LAUNCH_ACTIONS.map((a) => LAUNCH_ROUTINE[a]))].sort(),
    );
    assert.deepEqual(actionsOf("analyse"), ["analyse"]);
    assert.deepEqual(actionsOf("developpement"), ["developpement", "livraison", "reprise"]);
    for (const routine of Object.keys(PROMPTS) as (keyof typeof PROMPTS)[]) {
      assert.deepEqual(promptPatterns(PROMPTS[routine]), [expectedPattern(routine)], routine);
    }
  });

  it("le texte envoyé par le serveur suit le motif de sa routine, et lui seul", () => {
    for (const action of LAUNCH_ACTIONS) {
      const routine = LAUNCH_ROUTINE[action];
      const [pattern] = promptPatterns(PROMPTS[routine]);
      const text = launchCommandText(action, 1234567);
      assert.match(text, new RegExp(pattern));
      assert.match(text, LAUNCH_TEXT_PATTERN);
      for (const other of LAUNCH_ACTIONS.filter((a) => LAUNCH_ROUTINE[a] !== routine)) {
        assert.doesNotMatch(launchCommandText(other, 12), new RegExp(pattern));
      }
    }
  });

  it("livraison : liste L3 du prompt égale à SENSITIVE_DELIVERY_PATTERNS (logique dupliquée)", () => {
    assert.deepEqual(l3Patterns(PROMPTS.developpement), [...SENSITIVE_DELIVERY_PATTERNS]);
  });

  it("livraison : les trois pubspec.lock sensibles pour la livraison seule (2026-11-14)", () => {
    for (const lock of ["app/pubspec.lock", "brewing/pubspec.lock", "exchange/pubspec.lock"]) {
      assert.equal(isSensitiveDeliveryPath(lock), true, lock);
    }
    const dev = PROMPTS.developpement;
    const point5 = dev.slice(dev.indexOf("\n5. "), dev.indexOf("\n6. "));
    assert.ok(point5.includes("reste permise"), "point 5 : dépendance permise au développement");
  });

  it("livraison et développement : ajouts du 2026-11-14 (décision 15)", () => {
    const dev = PROMPTS.developpement;
    const point5 = dev.slice(dev.indexOf("\n5. "), dev.indexOf("\n6. "));
    for (const path of [
      "app/android/gradlew",
      "app/android/gradlew.bat",
      "**/hook/**",
      "**/.claude/**",
      "functions/src/auth.ts",
      "functions/src/config.ts",
      "functions/src/tickets/delivery.ts",
      "test-fixtures/member_access.json",
    ]) {
      assert.ok(point5.includes(path), `point 5 : ${path}`);
      assert.ok(SENSITIVE_DELIVERY_PATTERNS.includes(path), `serveur : ${path}`);
    }
    assert.ok(!SENSITIVE_DELIVERY_PATTERNS.includes(".claude/**"), "racine seule remplacée");
  });

  it("livraison : aiguillage et interdits L0 à L11 gardés", () => {
    const dev = PROMPTS.developpement;
    const part = dev.slice(dev.indexOf("Livraison (texte « livraison #N »)"));
    const flat = (t: string) => t.replace(/\s+/g, " ");
    for (const step of [
      "L0.",
      "L1.",
      "L2.",
      "L3.",
      "L4.",
      "L5.",
      "L6.",
      "L7.",
      "L8.",
      "L9.",
      "L10.",
      "L11.",
    ]) {
      assert.ok(part.includes(`\n${step} `), `étape absente : ${step}`);
    }
    for (const needle of [
      "« livraison » → partie « Livraison » (points L0 à L11)",
      "## Livraison — blocage",
      "## Livraison — terminée",
      "Une condition manque : blocage qui la nomme",
      "jamais par un rebase",
      "jamais sur main, jamais --force",
      "gh pr merge M --merge --match-head-commit <ce sha>",
      "Refais le contrôle de L3 sur cette tête",
      "git var GIT_AUTHOR_IDENT et git var GIT_COMMITTER_IDENT",
      "git fetch --tags && node scripts/check-version.mjs",
      "Version et outillage",
      "Tag de la version déployée",
      "poser un tag",
      "lancer un workflow à la main",
      "poser ou retirer\n    une étiquette",
      "Mille fichiers ou plus",
      "arrête-toi sans rien écrire",
    ]) {
      assert.ok(
        flat(
          needle === "« livraison » → partie « Livraison » (points L0 à L11)" ? dev : part,
        ).includes(flat(needle)),
        `absent de la partie Livraison : ${needle}`,
      );
    }
  });

  it("reprise : aiguillage et interdits R1 à R7 gardés", () => {
    const dev = PROMPTS.developpement;
    const part = dev.slice(dev.indexOf("Reprise (texte « reprise #N »)"));
    const flat = (t: string) => t.replace(/\s+/g, " ");
    for (const step of ["R1.", "R2.", "R3.", "R4.", "R5.", "R6.", "R7."]) {
      assert.ok(part.includes(`\n${step} `), `étape absente : ${step}`);
    }
    for (const needle of [
      "« reprise » → partie « Reprise » (points R1 à R7)",
      "ne publie rien sur GitHub",
      "failure, timed_out ou\n      startup_failure (cancelled ne compte pas)",
      "sans --force",
      "ouvrir une nouvelle pull request",
      "gh run rerun",
      "statut:en-cours\n    compris",
      "fusionner",
      "jamais un rebase",
    ]) {
      assert.ok(
        flat(needle.startsWith("« reprise »") ? dev : part).includes(flat(needle)),
        `absent de la partie Reprise : ${needle}`,
      );
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
