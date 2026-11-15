// Écriture contre l'émulateur Firestore (projet demo-kassbeer), lancée par
// `npm test` (firebase emulators:exec). Sans FIRESTORE_EMULATOR_HOST, ces tests sont
// passés : l'écrivain refuserait de toute façon de viser la production sans option.

import assert from "node:assert/strict";
import { cpSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { executer } from "../lib/execution.mjs";
import { listerHoublons } from "../lib/lister.mjs";
import { ErreurOptions } from "../lib/options.mjs";

const HOTE = process.env.FIRESTORE_EMULATOR_HOST;
const FIXTURE = fileURLToPath(new URL("./fixtures/prepare/", import.meta.url));
const AROMES = fileURLToPath(new URL("./fixtures/aromes/", import.meta.url));
const PROJET = "demo-kassbeer";

async function viderEmulateur() {
  const reponse = await fetch(
    `http://${HOTE}/emulator/v1/projects/${PROJET}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  assert.equal(reponse.ok, true, `émulateur : ${reponse.status}`);
}

describe(
  "écriture contre l'émulateur",
  { skip: HOTE ? false : "FIRESTORE_EMULATOR_HOST absent" },
  () => {
    let rapports;
    let horloge = Date.parse("2026-11-11T10:00:00Z");
    const maintenant = () => new Date((horloge += 1000));
    const lancer = (argv = []) =>
      executer({
        argv: ["--dossier", FIXTURE, "--rapports", rapports, ...argv],
        env: { FIRESTORE_EMULATOR_HOST: HOTE },
        entree: process.stdin,
        sortie: process.stdout,
        maintenant,
      });

    before(async () => {
      rapports = mkdtempSync(join(tmpdir(), "kassbeer-ingest-"));
      await viderEmulateur();
    });
    after(() => rmSync(rapports, { recursive: true, force: true }));

    it("simulation : compte sans écrire", async () => {
      const r = await lancer(["--simulation"]);
      assert.equal(r.simulation, true);
      assert.deepEqual(r.counts.beer_index, { written: 5, unchanged: 0, refused: 0 });
      const r2 = await lancer(["--simulation"]);
      assert.deepEqual(r2.counts.beer_index, { written: 5, unchanged: 0, refused: 0 });
    });

    it("première écriture, puis seconde à 0 écriture", async () => {
      const premiere = await lancer();
      assert.equal(premiere.target, "emulator");
      for (const [collection, c] of Object.entries(premiere.counts)) {
        assert.equal(c.unchanged, 0, collection);
        assert.equal(c.refused, 0, collection);
        assert.ok(c.written >= 1, collection);
      }
      const seconde = await lancer();
      for (const [collection, c] of Object.entries(seconde.counts)) {
        assert.equal(c.written, 0, collection);
        assert.equal(c.unchanged, premiere.counts[collection].written, collection);
      }
      // Rapport JSON et document ingest_runs de chaque exécution.
      const fichiers = readdirSync(rapports).filter((f) => !f.includes("simulation"));
      assert.equal(fichiers.length, 2);
      const texte = readFileSync(join(rapports, `${seconde.run_id}.json`), "utf8");
      assert.equal(JSON.parse(texte).counts.beer_hops.written, 0);

      const { deleteApp, initializeApp } = await import("firebase-admin/app");
      const { getFirestore } = await import("firebase-admin/firestore");
      const app = initializeApp({ projectId: PROJET }, "lecture-test");
      try {
        const db = getFirestore(app);
        const run = (await db.doc(`ingest_runs/${seconde.run_id}`).get()).data();
        assert.equal(run.target, "emulator");
        assert.equal(run.report_sha256, seconde.report_sha256);
        assert.deepEqual(run.unresolved, { fermentable: 1, hop: 0, culture: 0, misc: 0 });
        assert.deepEqual(Object.keys(run).sort(), [
          "counts",
          "finished_at",
          "report_sha256",
          "sources",
          "started_at",
          "target",
          "unresolved",
        ]);
        const recette = (await db.doc("public_recipes/diydog-1").get()).data();
        assert.equal(recette.owner_uid, "system");
        assert.ok(recette.updated_at, "updated_at posé par le serveur");
        assert.equal((await db.collection("ingest_runs").get()).size, 2);
        const arome = (await db.doc("beer_hop_aromas/hop-houblon-fictif").get()).data();
        assert.equal(arome.reviewed, true);
        assert.match(arome.content_sha256, /^[0-9a-f]{64}$/);
        assert.ok(arome.updated_at, "updated_at posé par le serveur");
      } finally {
        await deleteApp(app);
      }
    });

    it("arômes : houblon du groupe non relu refusé et nommé ; houblons sans description comptés", async () => {
      const dossierAromes = mkdtempSync(join(tmpdir(), "kassbeer-aromes-"));
      try {
        const source = fileURLToPath(new URL("./fixtures/aromes/", import.meta.url));
        const entrees = JSON.parse(readFileSync(join(source, "aromes.json"), "utf8"));
        entrees[0].data.reviewed = false;
        delete entrees[0].data.reviewed_at;
        writeFileSync(join(dossierAromes, "aromes.json"), JSON.stringify(entrees));
        writeFileSync(
          join(dossierAromes, "houblons-recettes.json"),
          readFileSync(join(source, "houblons-recettes.json")),
        );
        const r = await lancer(["--simulation", "--aromes", dossierAromes]);
        assert.deepEqual(r.counts.beer_hop_aromas, { written: 0, unchanged: 0, refused: 1 });
        assert.deepEqual(r.refused, [
          {
            collection: "beer_hop_aromas",
            id: "hop-houblon-fictif",
            erreurs: ["reviewed : houblon des recettes du groupe non relu"],
          },
        ]);
        assert.equal(r.hops_without_aroma, 0);
        writeFileSync(join(dossierAromes, "aromes.json"), "[]");
        const vide = await lancer(["--simulation", "--aromes", dossierAromes]);
        assert.equal(vide.hops_without_aroma, 1);
      } finally {
        rmSync(dossierAromes, { recursive: true, force: true });
      }
    });

    it("lister-houblons-recettes : noms seuls, triés, sans doublon, aucune écriture", async () => {
      const { deleteApp, initializeApp } = await import("firebase-admin/app");
      const { getFirestore } = await import("firebase-admin/firestore");
      const app = initializeApp({ projectId: PROJET }, "semis-lister");
      const sortieNoms = join(rapports, "noms-houblons.json");
      try {
        const db = getFirestore(app);
        const ligne = (name) => ({ name, amount: { value: 20, unit: "g" } });
        await db.doc("recipes/r1").set({
          owner_uid: "uid-fictif",
          recipe: {
            name: "Recette",
            ingredients: { hop_additions: [ligne("Saaz"), ligne("Cascade")] },
          },
        });
        await db.doc("recipes/r2").set({ recipe: { name: "Sans houblon", ingredients: {} } });
        await db.doc("brews/b1").set({
          owner_uid: "uid-fictif",
          recipe_snapshot: {
            recipe: {
              ingredients: { hop_additions: [ligne(" Cascade "), ligne("Ancien"), { amount: 1 }] },
            },
          },
        });
        const avant = (await db.collection("recipes").get()).size;
        const r = await listerHoublons({
          argv: ["--sortie", sortieNoms],
          env: { FIRESTORE_EMULATOR_HOST: HOTE },
          entree: process.stdin,
          sortie: process.stdout,
        });
        assert.equal(r.recettes, 2);
        assert.equal(r.brassins, 1);
        assert.equal(r.ecartees, 1);
        const fichier = JSON.parse(readFileSync(sortieNoms, "utf8"));
        assert.deepEqual(fichier.noms, ["Ancien", "Cascade", "Saaz"]);
        assert.deepEqual(Object.keys(fichier).sort(), [
          "format",
          "generated_at",
          "noms",
          "target",
          "version",
        ]);
        assert.equal(JSON.stringify(fichier).includes("uid-fictif"), false);
        assert.equal((await db.collection("recipes").get()).size, avant);
      } finally {
        await deleteApp(app);
      }
    });

    it("production depuis l'environnement de l'émulateur : refusée", async () => {
      await assert.rejects(
        executer({
          argv: ["--production", "--projet", "kassbeer", "--dossier", FIXTURE],
          env: { FIRESTORE_EMULATOR_HOST: HOTE },
          entree: { isTTY: false },
          sortie: { isTTY: false },
        }),
        ErreurOptions,
      );
    });
  },
);

describe(
  "--supprimer-absents contre l'émulateur (ADR-014)",
  { skip: HOTE ? false : "FIRESTORE_EMULATOR_HOST absent" },
  () => {
    let prepare;
    let rapports;
    let app;
    let db;
    let horloge = Date.parse("2026-11-15T10:00:00Z");
    const maintenant = () => new Date((horloge += 1000));
    const PREPARES = 61;
    const ne = () => {
      throw new Error("confirmation demandée à tort");
    };
    const lancer = (argv, confirmerSuppression = ne) =>
      executer({
        argv: ["--dossier", prepare, "--rapports", rapports, ...argv],
        env: { FIRESTORE_EMULATOR_HOST: HOTE },
        entree: process.stdin,
        sortie: process.stdout,
        maintenant,
        confirmerSuppression,
      });
    const existe = async (chemin) => (await db.doc(chemin).get()).exists;
    const semer = async (collection, ids) => {
      for (const id of ids) await db.collection(collection).doc(id).set({ name: id });
    };

    before(async () => {
      prepare = mkdtempSync(join(tmpdir(), "kassbeer-prepare-"));
      rapports = mkdtempSync(join(tmpdir(), "kassbeer-rapports-"));
      cpSync(FIXTURE, prepare, { recursive: true });
      // 61 houblons préparés : le fictif de la fixture et 60 copies.
      const [fictif] = JSON.parse(readFileSync(join(FIXTURE, "beer_hops.json"), "utf8"));
      const hops = [fictif];
      for (let i = 1; i < PREPARES; i++) {
        hops.push({ id: `hop-prepare-${i}`, data: { ...fictif.data, name: `Préparé ${i}` } });
      }
      writeFileSync(join(prepare, "beer_hops.json"), JSON.stringify(hops));
      const { initializeApp } = await import("firebase-admin/app");
      const { getFirestore } = await import("firebase-admin/firestore");
      app = initializeApp({ projectId: PROJET }, "suppression-test");
      db = getFirestore(app);
    });
    after(async () => {
      const { deleteApp } = await import("firebase-admin/app");
      await deleteApp(app);
      rmSync(prepare, { recursive: true, force: true });
      rmSync(rapports, { recursive: true, force: true });
    });

    it("sans l'option : aucun document supprimé", async () => {
      await viderEmulateur();
      await semer("beer_hops", ["hop-ancien-1"]);
      const r = await lancer([]);
      assert.equal(r.deletions, undefined);
      assert.equal(await existe("beer_hops/hop-ancien-1"), true);
    });

    it("simulation : liste des absents, rien supprimé ni demandé", async () => {
      // En ligne : 61 préparés, 2 absents conformes, 1 identifiant hors motif (64, 95,3 %).
      await semer("beer_hops", ["hop-ancien-1", "hop-ancien-2", "Hop_Mauvais"]);
      const r = await lancer(["--supprimer-absents", "beer_hops", "--simulation"]);
      assert.deepEqual(r.deletions, {
        collection: "beer_hops",
        online: 64,
        prepared: PREPARES,
        candidates: ["hop-ancien-1", "hop-ancien-2"],
        deleted: [],
        ignored: [{ id: "Hop_Mauvais", raison: "identifiant hors du motif de la collection" }],
        errors: [],
      });
      assert.equal(await existe("beer_hops/hop-ancien-1"), true);
      const fichier = JSON.parse(readFileSync(r.fichier, "utf8"));
      assert.deepEqual(fichier.deletions.candidates, ["hop-ancien-1", "hop-ancien-2"]);
    });

    it("nombre non confirmé : rien n'est écrit ni supprimé", async () => {
      await db.doc("beer_hops/hop-prepare-1").delete();
      const executions = (await db.collection("ingest_runs").get()).size;
      let demande = null;
      await assert.rejects(
        lancer(["--supprimer-absents", "beer_hops"], async (collection, ids) => {
          demande = { collection, ids };
          return false;
        }),
        (e) => e instanceof ErreurOptions && /non confirmé/.test(e.message),
      );
      assert.deepEqual(demande, {
        collection: "beer_hops",
        ids: ["hop-ancien-1", "hop-ancien-2"],
      });
      assert.equal(await existe("beer_hops/hop-ancien-1"), true);
      assert.equal(await existe("beer_hops/hop-prepare-1"), false, "aucune écriture");
      assert.equal((await db.collection("ingest_runs").get()).size, executions);
    });

    it("nombre confirmé : absents supprimés, hors motif gardé, rapport chiffré", async () => {
      const r = await lancer(["--supprimer-absents", "beer_hops"], async () => true);
      assert.deepEqual(r.deletions.deleted, ["hop-ancien-1", "hop-ancien-2"]);
      assert.deepEqual(r.deletions.errors, []);
      assert.equal(r.deletions.ignored.length, 1);
      assert.equal(r.counts.beer_hops.written, 1);
      assert.equal(await existe("beer_hops/hop-ancien-1"), false);
      assert.equal(await existe("beer_hops/hop-ancien-2"), false);
      assert.equal(await existe("beer_hops/Hop_Mauvais"), true);
      assert.equal(await existe("beer_hops/hop-prepare-1"), true);
      const encore = await lancer(["--supprimer-absents", "beer_hops"]);
      assert.deepEqual(encore.deletions.candidates, [], "rien à confirmer");
    });

    it("préparation à moins de 90 % des documents en ligne : refusée", async () => {
      await semer(
        "beer_hops",
        Array.from({ length: 10 }, (_, i) => `hop-ancien-${i + 1}`),
      );
      await assert.rejects(
        lancer(["--supprimer-absents", "beer_hops"], async () => true),
        /moins de 90 %/,
      );
      assert.equal(await existe("beer_hops/hop-ancien-1"), true);
    });

    it("plus de 30 absents : refusé", async () => {
      await viderEmulateur();
      await semer(
        "beer_hops",
        Array.from({ length: 31 }, (_, i) => `hop-ancien-${i}`),
      );
      await assert.rejects(
        lancer(["--supprimer-absents", "beer_hops"], async () => true),
        /30 au plus/,
      );
      assert.equal(await existe("beer_hops/hop-ancien-0"), true);
      assert.equal(await existe("beer_hops/hop-houblon-fictif"), false, "aucune écriture");
    });

    it("autre collection : refusée avant toute lecture", async () => {
      await semer("beer_fermentables", ["fermentable-ancien"]);
      await assert.rejects(
        lancer(["--supprimer-absents", "beer_fermentables"], async () => true),
        ErreurOptions,
      );
      assert.equal(await existe("beer_fermentables/fermentable-ancien"), true);
    });

    it("beer_hop_aromas : absent d'aromes.json supprimé ; sans aromes.json refusé", async () => {
      await viderEmulateur();
      const vide = mkdtempSync(join(tmpdir(), "kassbeer-sans-aromes-"));
      try {
        await assert.rejects(
          lancer(["--supprimer-absents", "beer_hop_aromas", "--aromes", vide]),
          /sans aromes.json/,
        );
      } finally {
        rmSync(vide, { recursive: true, force: true });
      }
      // aromes.json de la fixture : 1 entrée (hop-houblon-fictif) ; en ligne : elle seule,
      // puis un orphelin : 1 pour 2, refusé ; l'orphelin seul en ligne : supprimé.
      await semer("beer_hop_aromas", ["hop-houblon-fictif", "hop-orphelin"]);
      await assert.rejects(
        lancer(["--supprimer-absents", "beer_hop_aromas", "--aromes", AROMES], async () => true),
        /moins de 90 %/,
      );
      await db.doc("beer_hop_aromas/hop-houblon-fictif").delete();
      const r = await lancer(
        ["--supprimer-absents", "beer_hop_aromas", "--aromes", AROMES],
        async () => true,
      );
      assert.deepEqual(r.deletions.deleted, ["hop-orphelin"]);
      assert.equal(await existe("beer_hop_aromas/hop-orphelin"), false);
      assert.equal(await existe("beer_hop_aromas/hop-houblon-fictif"), true, "écrit");
    });
  },
);

describe("arômes en production : liste des houblons du groupe contrôlée avant toute écriture", () => {
  const source = fileURLToPath(new URL("./fixtures/aromes/", import.meta.url));
  const MAINTENANT = new Date("2026-11-15T10:00:00Z");
  let dossierAromes;

  const lancerProduction = (origine) => {
    const groupe = JSON.parse(readFileSync(join(source, "houblons-recettes.json"), "utf8"));
    writeFileSync(
      join(dossierAromes, "houblons-recettes.json"),
      JSON.stringify({ ...groupe, ...origine }),
    );
    let identifiantsLus = false;
    return {
      lus: () => identifiantsLus,
      promesse: executer({
        argv: [
          "--production",
          "--projet",
          "kassbeer",
          "--dossier",
          FIXTURE,
          "--aromes",
          dossierAromes,
        ],
        env: {},
        entree: { isTTY: false },
        sortie: { isTTY: false },
        maintenant: () => MAINTENANT,
        lireIdentifiants: () => {
          identifiantsLus = true;
          return JSON.stringify({ type: "authorized_user" });
        },
      }),
    };
  };

  before(() => {
    dossierAromes = mkdtempSync(join(tmpdir(), "kassbeer-aromes-prod-"));
    writeFileSync(join(dossierAromes, "aromes.json"), readFileSync(join(source, "aromes.json")));
  });
  after(() => rmSync(dossierAromes, { recursive: true, force: true }));

  it("liste d'émulateur + --production : rien n'est écrit", async () => {
    const r = lancerProduction({ target: "emulator", generated_at: "2026-11-15T09:00:00.000Z" });
    await assert.rejects(
      r.promesse,
      (e) => e instanceof ErreurOptions && /émulateur|emulator/.test(e.message),
    );
    assert.equal(r.lus(), false, "refus avant les identifiants et toute écriture");
  });

  it("liste sans cible ni date (essai à la main) : refusée", async () => {
    const r = lancerProduction({});
    await assert.rejects(r.promesse, ErreurOptions);
  });

  it("liste de production de plus de 7 jours : refusée", async () => {
    const r = lancerProduction({ target: "production", generated_at: "2026-11-07T09:00:00.000Z" });
    await assert.rejects(r.promesse, /plus de 7 jours/);
    assert.equal(r.lus(), false);
  });

  it("liste de production récente : le contrôle passe, la suite exige un terminal", async () => {
    const r = lancerProduction({ target: "production", generated_at: "2026-11-14T09:00:00.000Z" });
    await assert.rejects(r.promesse, /sans terminal/);
    assert.equal(r.lus(), true);
  });
});
