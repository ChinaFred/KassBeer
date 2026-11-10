// v0.1.19 — sorties du paquet exchange/ (L2b d'ADR-005, P21), validées par ajv sans
// émulateur :
//   - chaque recette lue des fixtures d'import (exchange/test/fixtures/lecture/*.attendu.json,
//     vérifiées à l'identique par exchange/test/import_fixtures_test.dart) contre le schéma
//     partiel, comme un document écrit par toFirestore ;
//   - chaque fichier exporté (exchange/test/fixtures/export/*.json, vérifié par
//     exchange/test/export_test.dart) contre le schéma officiel au commit figé, document
//     entier (beer.json).

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { describe, it } from "node:test";
import Ajv2020 from "ajv/dist/2020.js";
import { officialSchemas, partialSchemas, recipeValidator } from "./beerjson_partial.mjs";

const EXCHANGE = new URL("../../exchange/test/fixtures/", import.meta.url);
const BEER_JSON = "https://raw.githubusercontent.com/beerjson/beerjson/main/json/beer.json";

const json = (url) => JSON.parse(readFileSync(url, "utf8"));
const files = (dir, suffix) =>
  readdirSync(new URL(dir, EXCHANGE)).filter((f) => f.endsWith(suffix));

function documentValidator(schemas) {
  const ajv = new Ajv2020({ allErrors: true });
  for (const schema of Object.values(schemas)) ajv.addSchema(schema);
  return ajv.compile({ $ref: BEER_JSON });
}

describe("import : recettes lues, schéma partiel", () => {
  const partial = recipeValidator(partialSchemas());
  const attendus = files("lecture/", ".attendu.json");

  it("au moins deux fixtures d'import", () => {
    assert.ok(attendus.length >= 2, attendus.join(", "));
  });

  for (const file of attendus) {
    const lues = json(new URL(`lecture/${file}`, EXCHANGE)).recettes.filter((r) => r.document);
    it(`${file} : ${lues.length} recettes lues, format_version 1, recipe valide`, () => {
      assert.ok(lues.length > 0);
      for (const r of lues) {
        assert.equal(r.document.format_version, 1);
        const ok = partial(r.document.recipe);
        assert.ok(ok, `${r.nom} : ${JSON.stringify(partial.errors, null, 2)}`);
      }
    });
  }
});

describe("export : fichiers BeerJSON, schéma officiel", () => {
  const official = documentValidator(officialSchemas());
  const exports = files("export/", ".json");

  it("au moins un fichier exporté", () => {
    assert.ok(exports.length >= 1);
  });

  for (const file of exports) {
    it(`${file} : document valide, version 2.01, aucun prix`, () => {
      const doc = json(new URL(`export/${file}`, EXCHANGE));
      const ok = official(doc);
      assert.ok(ok, JSON.stringify(official.errors, null, 2));
      assert.equal(doc.beerjson.version, 2.01);
      const text = JSON.stringify(doc);
      for (const forbidden of ["price", "inventory", "owner_uid", "equipment_id"]) {
        assert.equal(text.includes(forbidden), false, forbidden);
      }
    });
  }

  it("un fichier sans auteur ni rendement est refusé par le schéma officiel", () => {
    const doc = json(new URL(`export/${exports[0]}`, EXCHANGE));
    delete doc.beerjson.recipes[0].author;
    delete doc.beerjson.recipes[0].efficiency;
    assert.equal(official(doc), false);
  });
});
