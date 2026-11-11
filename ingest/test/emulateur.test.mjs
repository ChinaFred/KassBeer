// Écriture contre l'émulateur Firestore (projet demo-kassbeer), lancée par
// `npm test` (firebase emulators:exec). Sans FIRESTORE_EMULATOR_HOST, ces tests sont
// passés : l'écrivain refuserait de toute façon de viser la production sans option.

import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { executer } from "../lib/execution.mjs";
import { ErreurOptions } from "../lib/options.mjs";

const HOTE = process.env.FIRESTORE_EMULATOR_HOST;
const FIXTURE = fileURLToPath(new URL("./fixtures/prepare/", import.meta.url));
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
