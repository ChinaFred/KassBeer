// Contrôle des documents avant écriture : liste blanche, clés, unités, schéma partiel,
// taille de beer_index.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { executer, lirePreparation, resumePreparation, trier } from "../lib/execution.mjs";
import { ErreurOptions } from "../lib/options.mjs";
import {
  COLLECTIONS,
  controlerDocument,
  motifIdentifiant,
  STYLES_BA_EN_PRODUCTION,
  stylesBaRefusesEnProduction,
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

  it("provenance d'une fiche de fabricant : acceptée", () => {
    const c = doc("beer_cultures");
    c.data.provenance = [
      {
        source: "fabricants",
        source_id: "fermentis-safale-us-05",
        version: "2026-11-14",
        licence: "Données publiées par le fabricant",
        retrieved: "2026-11-14",
      },
    ];
    assert.deepEqual(controlerDocument("beer_cultures", c), []);
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
    const usage = doc("beer_index", "hops");
    usage.data.entries[0].purpose = "aromatique";
    refuse("beer_index", usage);
    const origine = doc("beer_index", "hops");
    origine.data.entries[0].origin = "";
    refuse("beer_index", origine);
  });

  it("beer_index/hops : usage et origine permis", () => {
    const d = doc("beer_index", "hops");
    d.data.entries[0].purpose = "aroma/bittering";
    d.data.entries[0].origin = "United States";
    assert.deepEqual(controlerDocument("beer_index", d), []);
  });

  it("beer_index/hop_aromas : id et confidence seuls, confiance en liste fermée", () => {
    const index = (entries) => ({
      id: "hop_aromas",
      data: { count: entries.length, entries, content_sha256: "a".repeat(64) },
    });
    assert.deepEqual(
      controlerDocument(
        "beer_index",
        index([
          { id: "hop-alpha", confidence: "high" },
          { id: "hop-beta", confidence: "unknown" },
        ]),
      ),
      [],
    );
    refuse("beer_index", index([{ id: "hop-alpha", confidence: "élevée" }]));
    refuse("beer_index", index([{ id: "hop-alpha" }]));
    refuse("beer_index", index([{ id: "hop-alpha", confidence: "low", reviewed: true }]));
    refuse("beer_index", index([{ id: "hop-alpha", name: "Alpha", confidence: "low" }]));
    refuse("beer_index", index([{ id: "fermentable-malt", confidence: "low" }]));
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
  it("beer_index/hop_aromas dans la préparation : refusé, construit par l'écrivain seul", () => {
    const d = {
      id: "hop_aromas",
      data: { count: 0, entries: [], content_sha256: "a".repeat(64) },
    };
    const { valides, refuses } = trier({ beer_index: [d] });
    assert.deepEqual(valides.beer_index, []);
    assert.deepEqual(refuses[0].erreurs, [
      "id : construit par ecrire.mjs depuis aromes.json, jamais préparé",
    ]);
  });

  it("identifiant en double : le second refusé", () => {
    const d = doc("beer_hops");
    const { valides, refuses } = trier({ beer_hops: [d, structuredClone(d)] });
    assert.equal(valides.beer_hops.length, 1);
    assert.equal(refuses.length, 1);
    assert.ok(refuses[0].erreurs.includes("id : en double"));
  });
});

describe("styles de la Brewers Association (ADR-018)", () => {
  /// Style BA inventé, de la forme écrite par la préparation de exchange/ (P20).
  function styleBa() {
    const d = doc("beer_styles");
    d.id = "ba-ambree-inventee";
    Object.assign(d.data, {
      name: "Ambrée Inventée",
      category: "Catégorie Inventée",
      category_id: "BA1",
      style_id: "BA1A",
      style_guide: "BA2026",
      provenance: [
        {
          source: "brewers-association",
          source_id: "Ambrée Inventée",
          version: "2026",
          licence: "BA (usage gratuit, mention de la BA)",
          retrieved: "2026-11-22",
        },
      ],
    });
    return d;
  }

  it("style ba- accepté, source et licence de la BA", () => {
    assert.deepEqual(controlerDocument("beer_styles", styleBa()), []);
  });

  it("motif d'écriture : bjcp2021- et ba- seuls", () => {
    const motif = motifIdentifiant("beer_styles");
    assert.ok(motif.test("bjcp2021-21a"));
    assert.ok(motif.test("ba-ambree-inventee"));
    for (const id of ["ba2026-ambree", "BA-ambree", "bjcp-21a", "ba-", "ba-Ambree", "style-21a"]) {
      assert.equal(motif.test(id), false, id);
      refuse("beer_styles", { ...styleBa(), id });
    }
  });

  it("style ba- : code BA, guide BA<édition> et source de la BA exigés", () => {
    const code = styleBa();
    code.data.style_id = "99A";
    refuse("beer_styles", code);
    const guide = styleBa();
    guide.data.style_guide = "BJCP2021";
    refuse("beer_styles", guide);
    const source = styleBa();
    source.data.provenance[0].source = "brewtarget-002";
    refuse("beer_styles", source);
    const licence = styleBa();
    licence.data.provenance[0].licence = "BA";
    refuse("beer_styles", licence);
  });

  it("style ba- : licence d'une autre source refusée", () => {
    for (const licence of ["BJCP (noms et plages)", "GPL-3.0"]) {
      const d = styleBa();
      d.data.provenance[0].licence = licence;
      refuse("beer_styles", d);
    }
  });

  it("nom et catégorie d'un style : contrôle et bidirectionnel refusés", () => {
    for (const c of [
      "\u0000",
      "\u001F",
      "\u007F",
      "\u0085",
      "\u009F",
      "\u061C",
      "\u200E",
      "\u200F",
      "\u202A",
      "\u202E",
      "\u2066",
      "\u2069",
      "\n",
    ]) {
      for (const cle of ["name", "category"]) {
        const ba = styleBa();
        ba.data[cle] = `Ambrée${c}Inventée`;
        refuse("beer_styles", ba);
        const bjcp = doc("beer_styles");
        bjcp.data[cle] = `Style${c}Fictif`;
        refuse("beer_styles", bjcp);
      }
    }
  });

  it("beer_index/styles : nom et catégorie d'une entrée, contrôle et bidirectionnel refusés", () => {
    for (const c of ["\u200F", "\u0085", "\u202E", "\u0007"]) {
      for (const cle of ["name", "category"]) {
        const d = doc("beer_index", "styles");
        d.data.entries[0][cle] = `Style${c}Fictif`;
        refuse("beer_index", d);
      }
    }
    const bon = doc("beer_index", "styles");
    bon.data.entries[0].name = "Bière de Garde Fictive";
    assert.deepEqual(controlerDocument("beer_index", bon), []);
  });

  it("ba_mention : contrôle, bidirectionnel, lien, www. et @ refusés", () => {
    for (const mention of [
      "Mention\u202Einventée 2026.",
      "Mention\u200Finventée 2026.",
      "Mention\u0085inventée 2026.",
      "Mention\ninventée 2026.",
      "Voir https://exemple.fr, 2026.",
      "Voir HTTP 2026.",
      "Voir www.exemple.fr, 2026.",
      "Écrire à contact@exemple.fr, 2026.",
    ]) {
      const d = doc("beer_index", "styles");
      d.data.ba_mention = { edition: 2026, mention };
      refuse("beer_index", d);
    }
  });

  it("beer_index/styles : guide par entrée et ba_mention permis", () => {
    const d = doc("beer_index", "styles");
    d.data.entries[0].guide = "BJCP2021";
    d.data.ba_mention = { edition: 2026, mention: "Mention inventée, édition 2026." };
    assert.deepEqual(controlerDocument("beer_index", d), []);
  });

  it("ba_mention : forme contrôlée, refusée hors de beer_index/styles", () => {
    const cle = doc("beer_index", "styles");
    cle.data.ba_mention = { edition: 2026, mention: "Mention inventée.", lien: "x" };
    refuse("beer_index", cle);
    const edition = doc("beer_index", "styles");
    edition.data.ba_mention = { edition: "2026", mention: "Mention inventée." };
    refuse("beer_index", edition);
    const longue = doc("beer_index", "styles");
    longue.data.ba_mention = { edition: 2026, mention: "x".repeat(401) };
    refuse("beer_index", longue);
    const ailleurs = doc("beer_index", "hops");
    ailleurs.data.ba_mention = { edition: 2026, mention: "Mention inventée." };
    refuse("beer_index", ailleurs);
    const guide = doc("beer_index", "styles");
    guide.data.entries[0].guide = "x".repeat(11);
    refuse("beer_index", guide);
  });
});

describe("styles de la Brewers Association en production (ADR-018, avant S2)", () => {
  /// Préparation de la fixture, plus un style ba- et ba_mention, copiée dans un dossier
  /// temporaire.
  function preparationAvecBa() {
    const dossier = mkdtempSync(join(tmpdir(), "kassbeer-prepare-ba-"));
    cpSync(FIXTURE, dossier, { recursive: true });
    const styles = JSON.parse(readFileSync(join(dossier, "beer_styles.json"), "utf8"));
    const ba = structuredClone(styles[0]);
    ba.id = "ba-ambree-inventee";
    styles.push(ba);
    writeFileSync(join(dossier, "beer_styles.json"), JSON.stringify(styles));
    const index = JSON.parse(readFileSync(join(dossier, "beer_index.json"), "utf8"));
    index.find((d) => d.id === "styles").data.ba_mention = { edition: 2026, mention: "M 2026." };
    writeFileSync(join(dossier, "beer_index.json"), JSON.stringify(index));
    return dossier;
  }

  it("garde-fou actif tant que le lot S2 n'est pas livré", () => {
    assert.equal(STYLES_BA_EN_PRODUCTION, false);
  });

  it("documents ba- et ba_mention listés ; préparation BJCP seule sans refus", () => {
    const dossier = preparationAvecBa();
    try {
      assert.deepEqual(stylesBaRefusesEnProduction(lirePreparation(dossier).documents), [
        "beer_styles/ba-ambree-inventee",
        "beer_index/styles.ba_mention",
      ]);
      assert.deepEqual(stylesBaRefusesEnProduction(lirePreparation(FIXTURE).documents), []);
    } finally {
      rmSync(dossier, { recursive: true, force: true });
    }
  });

  it("entrée d'index ba- ou de guide BA et recette publique de style ba- listées", () => {
    const { documents } = lirePreparation(FIXTURE);
    const d = structuredClone(documents);
    const index = d.beer_index.find((e) => e.id === "styles");
    index.data.entries.push({ ...index.data.entries[0], id: "ba-ambree-inventee" });
    index.data.entries.push({ ...index.data.entries[0], guide: "BA2026" });
    d.public_recipes[0].data.style_id = "ba-ambree-inventee";
    const n = index.data.entries.length;
    assert.deepEqual(stylesBaRefusesEnProduction(d), [
      `beer_index/styles.entries[${n - 2}] (ba-ambree-inventee)`,
      `beer_index/styles.entries[${n - 1}] (${index.data.entries[0].id})`,
      `public_recipes/${d.public_recipes[0].id}.style_id`,
    ]);
  });

  it("--production : refusé avant les identifiants, rien n'est écrit", async () => {
    const dossier = preparationAvecBa();
    const aromes = mkdtempSync(join(tmpdir(), "kassbeer-aromes-vide-"));
    let identifiantsLus = false;
    try {
      await assert.rejects(
        executer({
          argv: ["--production", "--projet", "kassbeer", "--dossier", dossier, "--aromes", aromes],
          env: {},
          entree: { isTTY: false },
          sortie: { isTTY: false },
          lireIdentifiants: () => {
            identifiantsLus = true;
            return JSON.stringify({ type: "authorized_user" });
          },
        }),
        (e) =>
          e instanceof ErreurOptions &&
          e.message.includes("refusés en production avant le lot S2") &&
          e.message.includes("beer_styles/ba-ambree-inventee"),
      );
      assert.equal(identifiantsLus, false);
    } finally {
      rmSync(dossier, { recursive: true, force: true });
      rmSync(aromes, { recursive: true, force: true });
    }
  });
});
