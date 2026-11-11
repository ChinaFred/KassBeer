// Écriture par lots et comparaison au contenu en base, sur une base simulée en mémoire.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { ecrireCollections, inchange, TAILLE_LECTURE, TAILLE_LOT } from "../lib/ecriture.mjs";
import { idExecution } from "../lib/execution.mjs";

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
