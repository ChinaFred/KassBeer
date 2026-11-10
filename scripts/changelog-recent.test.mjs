// node --test scripts/changelog-recent.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { COUNT, cleanInline, extractRecentVersions, toParagraphs } from "./changelog-recent.mjs";

const SAMPLE = `# Changelog

Introduction.

## 2026-10-17

### v0.2.3 — fonctionnel

Texte trois, sur
deux lignes.

Second paragraphe avec \`fichier.dart\` et **gras**.

### v0.2.3 — technique

Détail technique trois.

### v0.2.2 — technique

Seulement technique.

## 2026-10-16

### v0.2.1 — fonctionnel

Premier texte.

### v0.2.1 — technique

Technique un.

### v0.2.1 — fonctionnel

Second texte.

### v0.2.0 — fonctionnel

Liste :
- première puce
  sur deux lignes ;
- seconde puce.
`;

test("ignore une version qui n'a qu'une entrée technique", () => {
  assert.deepEqual(
    extractRecentVersions(SAMPLE).map((v) => v.version),
    ["0.2.3", "0.2.1", "0.2.0"],
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
    assert.ok(v.paragraphs.length > 0);
    for (const p of v.paragraphs) assert.doesNotMatch(p, /`|\*\*/);
  }
});
