// Une exécution de l'écrivain : options, lecture de la préparation, contrôle, écriture,
// rapport JSON dans import/ingest/rapports/ et document ingest_runs/<id>.

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ecrireCollections } from "./ecriture.mjs";
import {
  cheminIdentifiants,
  confirmerProduction,
  controlerIdentifiants,
  ErreurOptions,
  lireOptions,
} from "./options.mjs";
import { COLLECTION_EXECUTIONS, COLLECTIONS, controlerDocument } from "./validation.mjs";

const NATURES = ["fermentable", "hop", "culture", "misc"];

/// Dossier de la préparation par défaut : import/ingest/prepare/ à la racine du dépôt.
export const DOSSIER_PREPARE = fileURLToPath(
  new URL("../../import/ingest/prepare/", import.meta.url),
);

/// Dossier des rapports par défaut : import/ingest/rapports/.
export const DOSSIER_RAPPORTS = fileURLToPath(
  new URL("../../import/ingest/rapports/", import.meta.url),
);

/// Identifiant d'une exécution : horodatage ISO compact en UTC (`20261111T143012Z`).
export function idExecution(date) {
  return date
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
}

/// Lit `<collection>.json` (listes `{id, data}`) et `rapport.json` de [dossier]. Un
/// fichier absent ou illisible lève une erreur : rien n'est écrit.
export function lirePreparation(dossier) {
  const lire = (nom) => JSON.parse(readFileSync(join(dossier, nom), "utf8"));
  const documents = {};
  for (const collection of COLLECTIONS) {
    const liste = lire(`${collection}.json`);
    if (!Array.isArray(liste)) throw new Error(`${collection}.json : liste attendue`);
    documents[collection] = liste;
  }
  return { documents, rapport: lire("rapport.json") };
}

/// Sépare les documents bons des refusés (contrôle, ou identifiant en double).
export function trier(documents) {
  const valides = {};
  const refuses = [];
  for (const collection of COLLECTIONS) {
    const vus = new Set();
    valides[collection] = [];
    for (const doc of documents[collection] ?? []) {
      const erreurs = controlerDocument(collection, doc);
      if (typeof doc?.id === "string" && vus.has(doc.id)) erreurs.push("id : en double");
      if (typeof doc?.id === "string") vus.add(doc.id);
      if (erreurs.length > 0) {
        refuses.push({ collection, id: doc?.id ?? null, erreurs });
      } else {
        valides[collection].push(doc);
      }
    }
  }
  return { valides, refuses };
}

/// Sources lues et nombre de noms non résolus par nature, tirés du rapport de préparation.
export function resumePreparation(rapport) {
  const sources = (rapport.sources ?? []).map(({ source, version }) => ({ source, version }));
  const unresolved = Object.fromEntries(
    NATURES.map((n) => [n, (rapport.non_resolus?.[n] ?? []).length]),
  );
  return { sources, unresolved };
}

/// Exécute l'écrivain. [argv] sans `node` ni le script ; [env], [entree], [sortie] : ceux
/// du processus. Rend le rapport d'exécution. Lève ErreurOptions pour une utilisation
/// refusée, une autre erreur pour un échec.
export async function executer({
  argv,
  env,
  entree,
  sortie,
  maintenant = () => new Date(),
  lireIdentifiants = (chemin) => readFileSync(chemin, "utf8"),
}) {
  const debut = maintenant();
  const options = lireOptions(argv, env);
  const dossier = resolve(options.dossier ?? DOSSIER_PREPARE);
  const dossierRapports = resolve(options.rapports ?? DOSSIER_RAPPORTS);
  const preparation = lirePreparation(dossier);
  const { valides, refuses } = trier(preparation.documents);

  if (options.cible === "production") {
    controlerIdentifiants(cheminIdentifiants(env), lireIdentifiants);
    const confirme = await confirmerProduction(options.projet, entree, sortie);
    if (!confirme) throw new ErreurOptions("Nom du projet non confirmé : rien n'est écrit.");
  }

  // Admin SDK chargé au premier usage : les contrôles ci-dessus n'en ont pas besoin.
  const { deleteApp, initializeApp } = await import("firebase-admin/app");
  const { FieldValue, getFirestore, Timestamp } = await import("firebase-admin/firestore");
  const runId = idExecution(debut);
  const app = initializeApp({ projectId: options.projet }, `ingest-${runId}-${process.pid}`);
  try {
    const db = getFirestore(app);
    const ecrits = await ecrireCollections({
      db,
      FieldValue,
      documents: valides,
      simulation: options.simulation,
    });
    const counts = {};
    for (const collection of COLLECTIONS) {
      counts[collection] = {
        ...ecrits[collection],
        refused: refuses.filter((r) => r.collection === collection).length,
      };
    }
    const fin = maintenant();
    const { sources, unresolved } = resumePreparation(preparation.rapport);
    const rapport = {
      run_id: runId,
      target: options.cible,
      project: options.projet,
      simulation: options.simulation,
      started_at: debut.toISOString(),
      finished_at: fin.toISOString(),
      counts,
      refused: refuses,
      sources,
      unresolved,
    };
    mkdirSync(dossierRapports, { recursive: true });
    const texte = `${JSON.stringify(rapport, null, 2)}\n`;
    const fichier = join(
      dossierRapports,
      `${runId}${options.simulation ? "-simulation" : ""}.json`,
    );
    writeFileSync(fichier, texte);
    const reportSha256 = createHash("sha256").update(texte).digest("hex");
    if (!options.simulation) {
      // create : une seconde exécution dans la même seconde échoue au lieu d'écraser.
      await db
        .collection(COLLECTION_EXECUTIONS)
        .doc(runId)
        .create({
          started_at: Timestamp.fromDate(debut),
          finished_at: Timestamp.fromDate(fin),
          target: options.cible,
          counts,
          sources,
          unresolved,
          report_sha256: reportSha256,
        });
    }
    return { ...rapport, fichier, report_sha256: reportSha256 };
  } finally {
    await deleteApp(app);
  }
}
