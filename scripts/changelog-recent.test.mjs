// node --test scripts/changelog-recent.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import {
  COUNT,
  SUMMARY_MAX_LENGTH,
  SUMMARY_REQUIRED_FROM,
  cleanInline,
  extractRecentVersions,
  splitSummary,
  toParagraphs,
  versionBefore,
} from "./changelog-recent.mjs";

const SAMPLE = `# Changelog

Introduction.

## 2026-10-17

### v0.1.3 — fonctionnel

Texte trois, sur
deux lignes.

Second paragraphe avec \`fichier.dart\` et **gras**.

### v0.1.3 — technique

Détail technique trois.

### v0.1.2 — technique

Seulement technique.

## 2026-10-16

### v0.1.1 — fonctionnel

Premier texte.

### v0.1.1 — technique

Technique un.

### v0.1.1 — fonctionnel

Second texte.

### v0.1.0 — fonctionnel

Liste :
- première puce
  sur deux lignes ;
- seconde puce.
`;

test("ignore une version qui n'a qu'une entrée technique", () => {
  assert.deepEqual(
    extractRecentVersions(SAMPLE).map((v) => v.version),
    ["0.1.3", "0.1.1", "0.1.0"],
  );
});

test("lit la date, découpe en paragraphes, exclut le texte technique", () => {
  const [first] = extractRecentVersions(SAMPLE);
  assert.equal(first.date, "2026-10-17");
  assert.deepEqual(first.paragraphs, [
    "Texte trois, sur deux lignes.",
    "Second paragraphe avec fichier.dart et gras.",
  ]);
});

test("met bout à bout deux entrées fonctionnel d'une même version", () => {
  const second = extractRecentVersions(SAMPLE)[1];
  assert.equal(second.date, "2026-10-16");
  assert.deepEqual(second.paragraphs, ["Premier texte.", "Second texte."]);
});

test("une puce devient un paragraphe qui commence par « • »", () => {
  const last = extractRecentVersions(SAMPLE)[2];
  assert.deepEqual(last.paragraphs, [
    "Liste :",
    "• première puce sur deux lignes ;",
    "• seconde puce.",
  ]);
});

test("plafonne au nombre demandé", () => {
  assert.equal(extractRecentVersions(SAMPLE, 2).length, 2);
});

test("lit les fins de ligne Windows", () => {
  const versions = extractRecentVersions(SAMPLE.replaceAll("\n", "\r\n"));
  assert.equal(versions[0].paragraphs[0], "Texte trois, sur deux lignes.");
});

test("aucune version fonctionnel : liste vide", () => {
  assert.deepEqual(extractRecentVersions("## 2026-01-01\n\n### v0.0.1 — technique\n\nTexte.\n"), []);
});

test("une entrée fonctionnel vide est ignorée", () => {
  assert.deepEqual(extractRecentVersions("## 2026-01-01\n\n### v0.0.1 — fonctionnel\n\n"), []);
});

test("une entrée fonctionnel sans date lève", () => {
  assert.throws(() => extractRecentVersions("### v0.0.1 — fonctionnel\n\nTexte.\n"), /aucune date/);
});

const withSummary = (version, body) => `## 2026-11-22\n\n### v${version} — fonctionnel\n\n${body}\n`;

test("les entrées sans résumé donnent une liste « summaries » vide", () => {
  for (const v of extractRecentVersions(SAMPLE)) assert.deepEqual(v.summaries, []);
});

test("la ligne « Résumé : » devient le résumé, le reste le détail", () => {
  const [v] = extractRecentVersions(
    withSummary("0.2.0", "Résumé : Une note `courte`.\n\nLe détail.\n\n- une puce."),
  );
  assert.deepEqual(v.summaries, ["Une note courte."]);
  assert.deepEqual(v.paragraphs, ["Le détail.", "• une puce."]);
});

test("un résumé seul, sans détail, est accepté", () => {
  const [v] = extractRecentVersions(withSummary("0.2.0", "Résumé : Seul."));
  assert.deepEqual(v.summaries, ["Seul."]);
  assert.deepEqual(v.paragraphs, []);
});

test("deux entrées fonctionnel d'une même version : deux résumés", () => {
  const md =
    "## 2026-11-22\n\n### v0.2.0 — fonctionnel\n\nRésumé : Un.\n\nDétail un.\n\n" +
    "### v0.2.0 — technique\n\nTechnique.\n\n### v0.2.0 — fonctionnel\n\nRésumé : Deux.\n";
  const [v] = extractRecentVersions(md);
  assert.deepEqual(v.summaries, ["Un.", "Deux."]);
  assert.deepEqual(v.paragraphs, ["Détail un."]);
});

test("résumé de SUMMARY_MAX_LENGTH caractères accepté, un de plus refusé", () => {
  const ok = "é".repeat(SUMMARY_MAX_LENGTH);
  assert.deepEqual(extractRecentVersions(withSummary("0.2.0", `Résumé : ${ok}`))[0].summaries, [ok]);
  assert.throws(
    () => extractRecentVersions(withSummary("0.2.0", `Résumé : ${ok}x`)),
    /121 caractères, 120 au plus/,
  );
});

test("résumé vide refusé", () => {
  assert.throws(() => extractRecentVersions(withSummary("0.2.0", "Résumé :\n\nDétail.")), /résumé vide/);
});

test("résumé placé après le premier paragraphe refusé", () => {
  assert.throws(
    () => extractRecentVersions(withSummary("0.1.50", "Détail.\n\nRésumé : Trop tard.")),
    /doit ouvrir l'entrée/,
  );
});

test("résumé obligatoire à partir de SUMMARY_REQUIRED_FROM", () => {
  assert.equal(SUMMARY_REQUIRED_FROM, "0.2.0");
  assert.throws(() => extractRecentVersions(withSummary("0.2.0", "Détail.")), /manque/);
  assert.throws(() => extractRecentVersions(withSummary("1.0.0", "Détail.")), /manque/);
  assert.deepEqual(extractRecentVersions(withSummary("0.1.99", "Détail."))[0].summaries, []);
});

test("versionBefore compare chiffre par chiffre", () => {
  assert.equal(versionBefore("0.1.99", "0.2.0"), true);
  assert.equal(versionBefore("0.2.0", "0.2.0"), false);
  assert.equal(versionBefore("0.10.0", "0.2.0"), false);
});

test("splitSummary ne touche pas une entrée ancienne sans résumé", () => {
  assert.deepEqual(splitSummary("0.1.0", ["A.", "B."]), { summary: null, paragraphs: ["A.", "B."] });
});

test("cleanInline et toParagraphs", () => {
  assert.equal(cleanInline("  `a`  **b**  "), "a b");
  assert.deepEqual(toParagraphs("\n\nUn.\n\n\nDeux.\n"), ["Un.", "Deux."]);
});

test("le CHANGELOG du dépôt donne entre 1 et COUNT versions datées", () => {
  const text = readFileSync(new URL("../documentation/CHANGELOG.md", import.meta.url), "utf8");
  const versions = extractRecentVersions(text);
  assert.ok(versions.length >= 1 && versions.length <= COUNT);
  for (const v of versions) {
    assert.match(v.date, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(v.summaries.length + v.paragraphs.length > 0);
    for (const p of [...v.summaries, ...v.paragraphs]) assert.doesNotMatch(p, /`|\*\*/);
    for (const s of v.summaries) assert.ok([...s].length <= SUMMARY_MAX_LENGTH);
  }
});
