// node --test scripts/check-agents.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";
import { checkDefinition, namesInTable } from "./check-agents.mjs";

const file = (header) => `---\n${header}\n---\n\nCorps.\n`;

test("en-tête valide, description entre guillemets avec deux-points", () => {
  const text = file('name: a\ndescription: "Rôle — lecture seule : il relit."\ntools: Read, Grep');
  assert.deepEqual(checkDefinition(text, "a"), []);
});

test("deux-points dans une description sans guillemets", () => {
  const problems = checkDefinition(file("name: a\ndescription: Lecture seule : il relit."), "a");
  assert.equal(problems.length, 1);
  assert.match(problems[0], /guillemets doubles/);
});

test("guillemets non refermés", () => {
  const problems = checkDefinition(file('name: a\ndescription: "ouvert'), "a");
  assert.match(problems[0], /non refermés/);
});

test("en-tête absent", () => {
  assert.match(checkDefinition("Pas d'en-tête.", "a")[0], /absent/);
});

test("nom différent du fichier", () => {
  const problems = checkDefinition(file("name: b\ndescription: Rôle."), "a");
  assert.match(problems[0], /diffère/);
});

test("description en bloc", () => {
  const text = file("name: a\ndescription: >\n  Rôle : sur deux\n  lignes.");
  assert.deepEqual(checkDefinition(text, "a"), []);
});

test("clé manquante", () => {
  assert.match(checkDefinition(file("name: a"), "a")[0], /description/);
});

test("noms d'un tableau", () => {
  const md = "## Agents\n\n| Agent | Quand |\n|---|---|\n| `x` | … |\n| `y` | … |\n\nSuite.";
  assert.deepEqual(namesInTable(md, "## Agents"), ["x", "y"]);
});
