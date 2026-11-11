// Contrôle des documents avant écriture : liste blanche, clés, unités, schéma partiel,
// taille de beer_index.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { lirePreparation, resumePreparation, trier } from "../lib/execution.mjs";
import {
  COLLECTIONS,
  controlerDocument,
  TAILLE_MAX_INDEX,
  tailleFirestore,
} from "../lib/validation.mjs";

const FIXTURE = fileURLToPath(new URL("./fixtures/prepare/", import.meta.url));

/// Document [id] de [collection] de la fixture, copié.
function doc(collection, id) {
  const { documents } = lirePreparation(FIXTURE);
  const d = documents[collection].find((e) => e.id === id) ?? documents[collection][0];
  return structuredClone(d);
}

const refuse = (collection, d) => assert.notDeepEqual(controlerDocument(collection, d), []);

describe("fixture préparée", () => {
  it("chaque document passe le contrôle", () => {
    const { documents } = lirePreparation(FIXTURE);
    for (const collection of COLLECTIONS) {
      for (const d of documents[collection]) {
        assert.deepEqual(controlerDocument(collection, d), [], `${collection}/${d.id}`);
      }
    }
  });

  it("résumé : sources et non résolus par nature", () => {
    const { rapport } = lirePreparation(FIXTURE);
    assert.deepEqual(resumePreparation(rapport), {
      sources: [
        { source: "brewtarget-001", version: "v5.2.3 ea10908" },
        { source: "diydog", version: "e6c12ab" },
      ],
      unresolved: { fermentable: 1, hop: 0, culture: 0, misc: 0 },
    });
  });
});

describe("controlerDocument", () => {
  it("collection hors liste blanche : refusée", () => {
    refuse("recipes", doc("beer_hops"));
    refuse("ingest_runs", doc("beer_hops"));
    refuse("users", doc("beer_hops"));
  });

  it("identifiant mal formé ou d'une autre nature : refusé", () => {
    const d = doc("beer_hops");
    refuse("beer_hops", { ...d, id: "fermentable-malt-fictif" });
    refuse("beer_hops", { ...d, id: "hop-Majuscule" });
    refuse("beer_hops", { ...d, id: "hop/chemin" });
    refuse("public_recipes", { ...doc("public_recipes"), id: "recette-1" });
    refuse("beer_index", { ...doc("beer_index"), id: "recettes" });
    refuse("import_unresolved", { ...doc("import_unresolved"), id: "abc" });
  });

  it("clé non permise : refusée (aucun notes, description ni URL, P20)", () => {
    for (const cle of ["notes", "description", "url", "price_eur"]) {
      const d = doc("beer_fermentables");
      d.data[cle] = "texte";
      refuse("beer_fermentables", d);
    }
    const s = doc("beer_styles");
    s.data.overall_impression = "texte";
    refuse("beer_styles", s);
  });

  it("unité autre que l'unité canonique : refusée", () => {
    const f = doc("beer_fermentables");
    f.data.color = { value: 2, unit: "Lovi" };
    refuse("beer_fermentables", f);
    const c = doc("beer_cultures");
    c.data.temperature_range.minimum.unit = "F";
    refuse("beer_cultures", c);
    const s = doc("beer_styles");
    s.data.color.maximum = { value: 6, unit: "SRM" };
    refuse("beer_styles", s);
    const r = doc("public_recipes");
    r.data.announced.original_gravity = { value: 1050, unit: "plato" };
    refuse("public_recipes", r);
  });

  it("valeur illisible ou plage inversée : refusée", () => {
    const h = doc("beer_hops");
    h.data.alpha_acid = { value: "7", unit: "%" };
    refuse("beer_hops", h);
    const c = doc("beer_cultures");
    c.data.attenuation.minimum.value = 90;
    refuse("beer_cultures", c);
  });

  it("provenance absente, source ou licence inconnue : refusée", () => {
    const a = doc("beer_miscs");
    a.data.provenance = [];
    refuse("beer_miscs", a);
    const b = doc("beer_miscs");
    b.data.provenance[0].licence = "MIT";
    refuse("beer_miscs", b);
    const c = doc("beer_miscs");
    c.data.provenance[0].source = "kaggle";
    refuse("beer_miscs", c);
  });

  it("updated_at préparé : refusé, l'écrivain le pose", () => {
    const d = doc("beer_hops");
    d.data.updated_at = "2026-11-11";
    refuse("beer_hops", d);
  });

  it("recette publique : clés de recipe limitées à isBeerJsonRecipe", () => {
    const r = doc("public_recipes");
    r.data.recipe.fermentation = { name: "Fermentation" };
    refuse("public_recipes", r);
    const e = doc("public_recipes");
    e.data.recipe.efficiency = { brewhouse: { value: 75, unit: "%" } };
    refuse("public_recipes", e);
  });

  it("recette publique : schéma partiel (palier sans durée) refusé", () => {
    const r = doc("public_recipes");
    delete r.data.recipe.mash.mash_steps[0].step_time;
    const erreurs = controlerDocument("public_recipes", r);
    assert.ok(
      erreurs.some((e) => e.includes("schéma partiel")),
      erreurs.join("\n"),
    );
  });

  it("recette publique : plafonds, enveloppe, source_hop_timing", () => {
    const a = doc("public_recipes");
    const ligne = a.data.recipe.ingredients.culture_additions[0];
    a.data.recipe.ingredients.culture_additions = Array(11).fill(ligne);
    refuse("public_recipes", a);
    const b = doc("public_recipes");
    b.data.owner_uid = "brewer-a";
    refuse("public_recipes", b);
    const c = doc("public_recipes");
    c.data.source_hop_timing = [{ hop_index: 1, label: "start" }];
    refuse("public_recipes", c);
    const d = doc("public_recipes");
    d.data.ingredient_refs = { "malt-fictif": "users/admin" };
    refuse("public_recipes", d);
    for (const nom of ["Bière Fictive", "biere  fictive", "biere-fictive", ""]) {
      const n = doc("public_recipes");
      n.data.search_name = nom;
      refuse("public_recipes", n);
    }
    const sans = doc("public_recipes");
    delete sans.data.search_name;
    refuse("public_recipes", sans);
    const style = doc("public_recipes");
    style.data.style_id = "x/y";
    refuse("public_recipes", style);
    const bon = doc("public_recipes");
    bon.data.style_id = "bjcp2021-21a";
    assert.deepEqual(controlerDocument("public_recipes", bon), []);
  });

  it("import_unresolved : champs en liste blanche", () => {
    const d = doc("import_unresolved");
    d.data.email = "brasseur@example.com";
    refuse("import_unresolved", d);
    const n = doc("import_unresolved");
    n.data.nature = "style";
    refuse("import_unresolved", n);
  });

  it("beer_index : clés et types de chaque entrée, par nature", () => {
    const prix = doc("beer_index", "hops");
    prix.data.entries = [{ id: "hop-houblon-fictif", name: "Houblon Fictif", price: 3 }];
    refuse("beer_index", prix);
    const infini = doc("beer_index", "hops");
    infini.data.entries[0].alpha = Infinity;
    refuse("beer_index", infini);
    const texte = doc("beer_index", "fermentables");
    texte.data.entries[0].color = "4";
    refuse("beer_index", texte);
    const nature = doc("beer_index", "hops");
    nature.data.entries[0].id = "fermentable-malt-fictif";
    refuse("beer_index", nature);
    const plage = doc("beer_index", "styles");
    plage.data.entries[0].og = [1.05, 1.04];
    refuse("beer_index", plage);
    const sansCode = doc("beer_index", "styles");
    delete sansCode.data.entries[0].code;
    refuse("beer_index", sansCode);
    const type = doc("beer_index", "cultures");
    type.data.entries[0].form = "poudre";
    refuse("beer_index", type);
  });

  it("ingredient_refs : identifiant de référentiel, 200 caractères au plus", () => {
    const long = doc("public_recipes");
    long.data.ingredient_refs = { "malt-fictif": `fermentable-${"a".repeat(500)}` };
    refuse("public_recipes", long);
    const forme = doc("public_recipes");
    forme.data.ingredient_refs = { "malt-fictif": "fermentable-Malt Fictif" };
    refuse("public_recipes", forme);
  });

  it("beer_index : nombre d'entrées et taille de 900 Ko au plus", () => {
    const d = doc("beer_index");
    d.data.count = 2;
    refuse("beer_index", d);
    const grand = doc("beer_index");
    const entree = { id: "hop-x", name: "x".repeat(100) };
    const n = Math.ceil(TAILLE_MAX_INDEX / 100);
    grand.data.entries = Array(n).fill(entree);
    grand.data.count = n;
    const erreurs = controlerDocument("beer_index", grand);
    assert.ok(
      erreurs.some((e) => e.startsWith("taille")),
      erreurs.join("\n"),
    );
  });
});

describe("tailleFirestore", () => {
  it("calcul de la documentation Firestore", () => {
    // users/jeff/tasks/my_task_id (exemple de la documentation) : 6 + 5 + 6 + 11 + 16 = 44.
    const nom = tailleFirestore("users/jeff/tasks/my_task_id", {}) - 32;
    assert.equal(nom, 44);
    // Champs : "type" "Personal" (5 + 9), "done" false (5 + 1), "priority" 1 (9 + 8),
    // "description" "Learn Cloud Firestore" (12 + 22) : 71 octets.
    const taille = tailleFirestore("users/jeff/tasks/my_task_id", {
      type: "Personal",
      done: false,
      priority: 1,
      description: "Learn Cloud Firestore",
    });
    assert.equal(taille, 147);
  });
});

describe("trier", () => {
  it("identifiant en double : le second refusé", () => {
    const d = doc("beer_hops");
    const { valides, refuses } = trier({ beer_hops: [d, structuredClone(d)] });
    assert.equal(valides.beer_hops.length, 1);
    assert.equal(refuses.length, 1);
    assert.ok(refuses[0].erreurs.includes("id : en double"));
  });
});
