// Écriture par lots et comparaison au contenu en base, sur une base simulée en mémoire.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  ecrireCollections,
  inchange,
  PLAFOND_SUPPRESSIONS,
  planifierSuppressions,
  supprimerDocuments,
  TAILLE_LECTURE,
  TAILLE_LOT,
} from "../lib/ecriture.mjs";
import { idExecution, idsPrepares } from "../lib/execution.mjs";
import { ErreurOptions } from "../lib/options.mjs";

const SERVEUR = Symbol("serverTimestamp");
const FieldValue = { serverTimestamp: () => SERVEUR };

/// Base en mémoire : `chemin → data`, lots comptés.
function base(initiale = {}) {
  const docs = new Map(Object.entries(initiale));
  const stats = { lots: [], lectures: [] };
  const ref = (collection, id) => ({ path: `${collection}/${id}` });
  return {
    docs,
    stats,
    collection: (c) => ({ doc: (id) => ref(c, id) }),
    async getAll(...refs) {
      stats.lectures.push(refs.length);
      return refs.map((r) => ({ exists: docs.has(r.path), data: () => docs.get(r.path) }));
    },
    batch() {
      const ops = [];
      return {
        set: (r, data) => ops.push([r.path, data]),
        async commit() {
          assert.ok(ops.length <= 500, "500 écritures au plus par lot");
          stats.lots.push(ops.length);
          for (const [path, data] of ops) docs.set(path, data);
        },
      };
    },
  };
}

const hop = (i, empreinte = "a") => ({
  id: `hop-h${i}`,
  data: { name: `H${i}`, content_sha256: empreinte.repeat(64) },
});

describe("inchange", () => {
  it("même content_sha256 : inchangé ; autre ou absent : à écrire", () => {
    const data = { name: "x", content_sha256: "a".repeat(64) };
    assert.equal(inchange(undefined, data), false);
    assert.equal(inchange({ ...data, updated_at: 1 }, data), true);
    assert.equal(inchange({ ...data, content_sha256: "b".repeat(64) }, data), false);
  });

  it("import_unresolved : champs comparés, hors updated_at", () => {
    const data = { nature: "hop", name: "X", source: "diydog", count: 2 };
    assert.equal(inchange({ ...data, updated_at: 1 }, data), true);
    assert.equal(inchange({ ...data, count: 3 }, data), false);
    assert.equal(inchange({ ...data, extra: 1 }, data), false);
  });
});

describe("ecrireCollections", () => {
  it("lots de 400, lectures de 300, updated_at posé par le serveur", async () => {
    const db = base();
    const docs = Array.from({ length: 850 }, (_, i) => hop(i));
    const comptes = await ecrireCollections({
      db,
      FieldValue,
      documents: { beer_hops: docs },
      simulation: false,
    });
    assert.deepEqual(comptes.beer_hops, { written: 850, unchanged: 0 });
    assert.deepEqual(db.stats.lots, [TAILLE_LOT, TAILLE_LOT, 50]);
    assert.deepEqual(db.stats.lectures, [TAILLE_LECTURE, TAILLE_LECTURE, 250]);
    assert.equal(db.docs.get("beer_hops/hop-h0").updated_at, SERVEUR);
    assert.deepEqual(comptes.public_recipes, { written: 0, unchanged: 0 });
  });

  it("seconde exécution : aucune écriture", async () => {
    const db = base();
    const documents = { beer_hops: [hop(1), hop(2)] };
    await ecrireCollections({ db, FieldValue, documents, simulation: false });
    const lots = db.stats.lots.length;
    const comptes = await ecrireCollections({ db, FieldValue, documents, simulation: false });
    assert.deepEqual(comptes.beer_hops, { written: 0, unchanged: 2 });
    assert.equal(db.stats.lots.length, lots);
  });

  it("document changé : seul lui est réécrit, en entier", async () => {
    const db = base({
      "beer_hops/hop-h1": { name: "Ancien", vieux_champ: 1, content_sha256: "a".repeat(64) },
    });
    const comptes = await ecrireCollections({
      db,
      FieldValue,
      documents: { beer_hops: [hop(1, "b"), hop(2)] },
      simulation: false,
    });
    assert.deepEqual(comptes.beer_hops, { written: 2, unchanged: 0 });
    assert.equal("vieux_champ" in db.docs.get("beer_hops/hop-h1"), false);
  });

  it("simulation : compte sans écrire", async () => {
    const db = base();
    const comptes = await ecrireCollections({
      db,
      FieldValue,
      documents: { beer_hops: [hop(1)] },
      simulation: true,
    });
    assert.deepEqual(comptes.beer_hops, { written: 1, unchanged: 0 });
    assert.deepEqual(db.stats.lots, []);
    assert.equal(db.docs.size, 0);
  });
});

describe("idExecution", () => {
  it("horodatage ISO compact en UTC", () => {
    assert.equal(idExecution(new Date("2026-11-11T14:30:12.345Z")), "20261111T143012Z");
  });
});

describe("planifierSuppressions (ADR-014)", () => {
  const ids = (n, prefixe = "hop-p") => Array.from({ length: n }, (_, i) => `${prefixe}${i}`);

  it("absents de la préparation, triés ; identifiant hors motif ignoré", () => {
    const plan = planifierSuppressions({
      collection: "beer_hops",
      enLigne: [...ids(40), "hop-z-ancien", "hop-a-ancien", "Hop_Mauvais"],
      prepares: ids(41),
    });
    assert.deepEqual(plan.candidates, ["hop-a-ancien", "hop-z-ancien"]);
    assert.deepEqual(plan.ignored, [
      { id: "Hop_Mauvais", raison: "identifiant hors du motif de la collection" },
    ]);
    assert.equal(plan.online, 43);
    assert.equal(plan.prepared, 41);
  });

  it("plafond : 30 acceptés, 31 refusés", () => {
    const prepares = ids(1000);
    const plan = planifierSuppressions({
      collection: "beer_hops",
      enLigne: [...prepares, ...ids(PLAFOND_SUPPRESSIONS, "hop-x")],
      prepares,
    });
    assert.equal(plan.candidates.length, 30);
    assert.throws(
      () =>
        planifierSuppressions({
          collection: "beer_hops",
          enLigne: [...prepares, ...ids(PLAFOND_SUPPRESSIONS + 1, "hop-x")],
          prepares,
        }),
      (e) => e instanceof ErreurOptions && /30 au plus/.test(e.message),
    );
  });

  it("préparation à moins de 90 % des documents en ligne : refusée", () => {
    const prepares = ids(90);
    const ok = planifierSuppressions({
      collection: "beer_hop_aromas",
      enLigne: [...prepares, ...ids(10, "hop-x")],
      prepares,
    });
    assert.equal(ok.candidates.length, 10);
    assert.throws(
      () =>
        planifierSuppressions({
          collection: "beer_hop_aromas",
          enLigne: [...prepares, ...ids(11, "hop-x")],
          prepares,
        }),
      (e) => e instanceof ErreurOptions && /moins de 90 %/.test(e.message),
    );
  });

  it("beer_cultures (amendement du 2026-11-15) : absents supprimables, motif culture-", () => {
    const prepares = ids(40, "culture-p");
    const plan = planifierSuppressions({
      collection: "beer_cultures",
      enLigne: [...prepares, "culture-omega-oyl-044-kolsch-ii", "hop-ancien", "Culture_Mauvaise"],
      prepares,
    });
    assert.deepEqual(plan.candidates, ["culture-omega-oyl-044-kolsch-ii"]);
    assert.deepEqual(
      plan.ignored.map((i) => i.id),
      ["Culture_Mauvaise", "hop-ancien"],
    );
    assert.deepEqual(
      idsPrepares("beer_cultures", { documents: { beer_cultures: [{ id: "culture-a" }] } }, null),
      ["culture-a"],
    );
  });

  it("beer_cultures : plafond de 30 dépassé refusé", () => {
    const prepares = ids(1000, "culture-p");
    assert.throws(
      () =>
        planifierSuppressions({
          collection: "beer_cultures",
          enLigne: [...prepares, ...ids(PLAFOND_SUPPRESSIONS + 1, "culture-x")],
          prepares,
        }),
      (e) => e instanceof ErreurOptions && /30 au plus/.test(e.message),
    );
  });

  it("beer_cultures : préparation à moins de 90 % refusée", () => {
    const prepares = ids(90, "culture-p");
    assert.throws(
      () =>
        planifierSuppressions({
          collection: "beer_cultures",
          enLigne: [...prepares, ...ids(11, "culture-x")],
          prepares,
        }),
      (e) => e instanceof ErreurOptions && /moins de 90 %/.test(e.message),
    );
  });

  it("beer_culture_aromas (ADR-017) : absents supprimables au motif culture-, plafond et 90 %", () => {
    const prepares = ids(40, "culture-p");
    const plan = planifierSuppressions({
      collection: "beer_culture_aromas",
      enLigne: [...prepares, "culture-absorbee", "hop-ancien"],
      prepares,
    });
    assert.deepEqual(plan.candidates, ["culture-absorbee"]);
    assert.deepEqual(
      plan.ignored.map((i) => i.id),
      ["hop-ancien"],
    );
    assert.throws(
      () =>
        planifierSuppressions({
          collection: "beer_culture_aromas",
          enLigne: [...ids(1000, "culture-p"), ...ids(PLAFOND_SUPPRESSIONS + 1, "culture-x")],
          prepares: ids(1000, "culture-p"),
        }),
      (e) => e instanceof ErreurOptions && /30 au plus/.test(e.message),
    );
    assert.throws(
      () =>
        planifierSuppressions({
          collection: "beer_culture_aromas",
          enLigne: [...ids(90, "culture-p"), ...ids(11, "culture-x")],
          prepares: ids(90, "culture-p"),
        }),
      (e) => e instanceof ErreurOptions && /moins de 90 %/.test(e.message),
    );
  });

  it("beer_culture_aromas sans levures/aromes.json : refusée ; identifiants des levures", () => {
    assert.throws(
      () => idsPrepares("beer_culture_aromas", { documents: {} }, { beer_culture_aromas: null }),
      (e) => e instanceof ErreurOptions && e.message.includes("levures/aromes.json"),
    );
    assert.deepEqual(
      idsPrepares(
        "beer_culture_aromas",
        { documents: {} },
        { beer_culture_aromas: { entrees: [{ id: "culture-a" }] } },
      ),
      ["culture-a"],
    );
  });

  it("autre collection : refusée", () => {
    for (const collection of [
      "beer_fermentables",
      "beer_miscs",
      "beer_styles",
      "beer_index",
      "public_recipes",
      "recipes",
    ]) {
      assert.throws(
        () => planifierSuppressions({ collection, enLigne: ["x"], prepares: ["x"] }),
        ErreurOptions,
        collection,
      );
    }
  });

  it("beer_hop_aromas sans aromes.json : refusée ; identifiants préparés, refusés compris", () => {
    assert.throws(
      () => idsPrepares("beer_hop_aromas", { documents: {} }, { beer_hop_aromas: null }),
      ErreurOptions,
    );
    assert.deepEqual(
      idsPrepares(
        "beer_hop_aromas",
        { documents: {} },
        { beer_hop_aromas: { entrees: [{ id: "hop-a" }, {}] } },
      ),
      ["hop-a"],
    );
    assert.deepEqual(
      idsPrepares("beer_hops", { documents: { beer_hops: [{ id: "hop-b" }] } }, null),
      ["hop-b"],
    );
  });
});

describe("supprimerDocuments", () => {
  it("un par un ; un échec noté avec son code, les autres supprimés", async () => {
    const supprimes = [];
    const db = {
      collection: (c) => ({
        doc: (id) => ({
          async delete() {
            if (id === "hop-b") throw Object.assign(new Error("refus"), { code: 7 });
            supprimes.push(`${c}/${id}`);
          },
        }),
      }),
    };
    const r = await supprimerDocuments({ db, collection: "beer_hops", ids: ["hop-a", "hop-b"] });
    assert.deepEqual(r, { deleted: ["hop-a"], errors: [{ id: "hop-b", erreur: "7" }] });
    assert.deepEqual(supprimes, ["beer_hops/hop-a"]);
  });
});
