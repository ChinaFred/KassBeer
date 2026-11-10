// v0.1.14 — documents de recettes écrits par toFirestore (app/test/fixtures/recipe_documents,
// vérifiés à l'identique par app/test/recipe_conversion_test.dart) validés par ajv contre
// le schéma BeerJSON partiel (ADR-005). Sans émulateur : ce fichier ne lit que des JSON.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { officialSchemas, partialSchemas, recipeValidator } from "./beerjson_partial.mjs";

const FIXTURES = new URL("../../app/test/fixtures/recipe_documents/", import.meta.url);
const fixture = (name) => JSON.parse(readFileSync(new URL(`${name}.json`, FIXTURES), "utf8"));

const partial = recipeValidator(partialSchemas());
const official = recipeValidator(officialSchemas());

function expectValid(validate, recipe) {
  const ok = validate(recipe);
  assert.ok(ok, JSON.stringify(validate.errors, null, 2));
}

function expectInvalid(validate, recipe) {
  assert.equal(validate(recipe), false, "document accepté");
}

describe("fixtures de toFirestore : schéma partiel", () => {
  for (const name of ["complete", "minimal", "snapshot"]) {
    it(`${name} : format_version 1, recipe valide`, () => {
      const doc = fixture(name);
      assert.equal(doc.format_version, 1);
      expectValid(partial, doc.recipe);
    });
  }

  it("la copie figée porte la même recette que la recette complète", () => {
    assert.deepEqual(fixture("snapshot").recipe, fixture("complete").recipe);
  });
});

describe("schéma partiel : seules différences avec le schéma officiel", () => {
  it("recette minimale refusée par le schéma officiel (champs obligatoires)", () => {
    expectInvalid(official, fixture("minimal").recipe);
  });

  it("recette complète refusée par le schéma officiel (author, efficiency absents)", () => {
    expectInvalid(official, fixture("complete").recipe);
  });

  it("recette qui porte tous les champs obligatoires : acceptée par le schéma officiel", () => {
    expectValid(official, {
      name: "Blonde",
      type: "all grain",
      author: "Brasseuse Fictive",
      efficiency: { brewhouse: { value: 72, unit: "%" } },
      batch_size: { value: 20, unit: "l" },
      ingredients: {
        fermentable_additions: [
          {
            name: "Pils",
            type: "grain",
            yield: { fine_grind: { value: 80, unit: "%" } },
            color: { value: 3.5, unit: "EBC" },
            amount: { value: 4500, unit: "g" },
          },
        ],
      },
    });
  });

  const base = () => fixture("complete").recipe;
  const cases = [
    ["volume en gallons", (r) => ({ ...r, batch_size: { value: 5, unit: "gal" } })],
    ["unité sans valeur", (r) => ({ ...r, batch_size: { unit: "l" } })],
    ["durée décimale", (r) => ({ ...r, boil: { boil_time: { value: 60.5, unit: "min" } } })],
    ["durée en heures", (r) => ({ ...r, boil: { boil_time: { value: 1, unit: "hr" } } })],
    [
      "température en °F",
      (r) => ({ ...r, mash: { ...r.mash, grain_temperature: { value: 64, unit: "F" } } }),
    ],
    ["champ inconnu dans recipe", (r) => ({ ...r, key: "malt-pils" })],
    [
      "champ inconnu dans un ajout (clé stockée)",
      (r) => ({
        ...r,
        ingredients: {
          ...r.ingredients,
          fermentable_additions: [{ ...r.ingredients.fermentable_additions[0], key: "malt-pils" }],
        },
      }),
    ],
    [
      "prix dans un ajout",
      (r) => ({
        ...r,
        ingredients: {
          ...r.ingredients,
          hop_additions: [{ ...r.ingredients.hop_additions[0], price_eur: 3 }],
        },
      }),
    ],
    ["type de recette hors schéma", (r) => ({ ...r, type: "bière" })],
    ["sans ingredients", (r) => ({ ...r, ingredients: undefined })],
  ];
  for (const [label, change] of cases) {
    it(`${label} : refusé`, () => {
      expectInvalid(partial, JSON.parse(JSON.stringify(change(base()))));
    });
  }
});
