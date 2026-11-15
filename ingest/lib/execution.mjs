// Une exécution de l'écrivain : options, lecture de la préparation, contrôle, écriture,
// rapport JSON dans import/ingest/rapports/ et document ingest_runs/<id>.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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
import { COLLECTION_AROMES, controlerEntreeArome, empreinteContenu } from "./aromes/validation.mjs";
import {
  COLLECTION_EXECUTIONS,
  COLLECTIONS,
  COLLECTIONS_ECRITES,
  controlerDocument,
} from "./validation.mjs";

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

/// Lit import/ingest/aromes/ ([dossier]) : `aromes.json` (liste `{id, data}`) et
/// `houblons-recettes.json` (houblons des recettes du groupe). Rend null si aromes.json
/// manque : aucune description n'est écrite. Lève une erreur si aromes.json existe sans
/// houblons-recettes.json : sans cette liste, l'écrivain ne peut pas refuser un houblon du
/// groupe non relu, et rien n'est écrit.
export function lireAromesPrepares(dossier) {
  const chemin = join(dossier, "aromes.json");
  if (!existsSync(chemin)) return null;
  const entrees = JSON.parse(readFileSync(chemin, "utf8"));
  if (!Array.isArray(entrees)) throw new Error("aromes.json : liste attendue");
  const cheminGroupe = join(dossier, "houblons-recettes.json");
  if (!existsSync(cheminGroupe)) {
    throw new Error(
      "houblons-recettes.json absent à côté de aromes.json : lancez lister-houblons-recettes.mjs " +
        "puis exchange/bin/lister_houblons_recettes.dart. Rien n'est écrit.",
    );
  }
  const groupe = JSON.parse(readFileSync(cheminGroupe, "utf8"));
  if (groupe?.format !== "kassbeer_houblons_recettes" || !Array.isArray(groupe.resolus)) {
    throw new Error("houblons-recettes.json : fichier de lister_houblons_recettes.dart attendu");
  }
  return {
    entrees,
    groupe: new Set(groupe.resolus.map((r) => r.id)),
    origine: { target: groupe.target ?? null, generated_at: groupe.generated_at ?? null },
  };
}

/// Âge maximal, en jours, de la liste des houblons du groupe lue par une écriture en
/// production : une liste plus ancienne peut omettre un houblon ajouté depuis à une recette,
/// dont le texte non relu partirait.
export const AGE_MAX_LISTE_GROUPE_JOURS = 7;

/// Contrôle, avant une écriture en production, l'origine de houblons-recettes.json
/// ([origine] : `target` et `generated_at` recopiés de noms-houblons.json). Lève
/// ErreurOptions si la liste vient de l'émulateur, d'une cible inconnue, n'a pas de date
/// lisible ou a plus de AGE_MAX_LISTE_GROUPE_JOURS jours : rien n'est écrit.
export function controlerListeGroupe(origine, maintenant) {
  const refaire =
    "Refaites la liste : node lister-houblons-recettes.mjs --production --projet kassbeer, " +
    "puis dart run bin/lister_houblons_recettes.dart. Rien n'est écrit.";
  if (origine?.target !== "production") {
    throw new ErreurOptions(
      `houblons-recettes.json vient de la cible « ${origine?.target ?? "inconnue"} », pas ` +
        `de la production : les houblons du groupe peuvent manquer. ${refaire}`,
    );
  }
  const date = Date.parse(origine.generated_at ?? "");
  if (!Number.isFinite(date)) {
    throw new ErreurOptions(`houblons-recettes.json sans date de liste lisible. ${refaire}`);
  }
  const age = (maintenant.getTime() - date) / 86_400_000;
  if (age > AGE_MAX_LISTE_GROUPE_JOURS || age < -1) {
    throw new ErreurOptions(
      `houblons-recettes.json tiré le ${origine.generated_at.slice(0, 10)} : plus de ` +
        `${AGE_MAX_LISTE_GROUPE_JOURS} jours. ${refaire}`,
    );
  }
}

/// Sépare les entrées de aromes.json bonnes des refusées (ADR-013, P55) : contrôle de
/// lib/aromes/validation.mjs, identifiant absent de beer_hops.json, houblon du groupe non
/// relu, identifiant en double. Les bonnes reçoivent `content_sha256`.
export function trierAromes(entrees, idsHoublons, groupe) {
  const valides = [];
  const refuses = [];
  const vus = new Set();
  for (const doc of entrees) {
    const erreurs = controlerEntreeArome(doc);
    const id = typeof doc?.id === "string" ? doc.id : null;
    if (id !== null && !idsHoublons.has(id)) erreurs.push("id : houblon absent de beer_hops.json");
    if (id !== null && groupe.has(id) && doc?.data?.reviewed !== true) {
      erreurs.push("reviewed : houblon des recettes du groupe non relu");
    }
    if (id !== null && vus.has(id)) erreurs.push("id : en double");
    if (id !== null) vus.add(id);
    if (erreurs.length > 0) {
      refuses.push({ collection: COLLECTION_AROMES, id, erreurs });
    } else {
      valides.push({ id, data: { ...doc.data, content_sha256: empreinteContenu(doc.data) } });
    }
  }
  return { valides, refuses };
}

/// Houblons de beer_hops.json sans entrée dans aromes.json (ADR-013, « Ajouter un houblon »).
export function compterSansDescription(documentsHoublons, entreesAromes) {
  const decrits = new Set((entreesAromes ?? []).map((e) => e?.id));
  return (documentsHoublons ?? []).filter((d) => !decrits.has(d.id)).length;
}

/// Message de fin de ecrire.mjs pour [n] houblons sans description ; null pour 0.
export function messageSansDescription(n) {
  if (n === 0) return null;
  return (
    `${n} houblon${n > 1 ? "s" : ""} sans description aromatique : lancez ` +
    "`node generer-aromes.mjs --nouveaux` (ou `--lot --nouveaux` au-delà de 20)."
  );
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
  const dossierAromes = resolve(options.aromes ?? join(dossier, "..", "aromes"));
  const preparation = lirePreparation(dossier);
  const { valides, refuses } = trier(preparation.documents);
  const aromes = lireAromesPrepares(dossierAromes);
  if (aromes !== null && options.cible === "production") {
    controlerListeGroupe(aromes.origine, debut);
  }
  const idsHoublons = new Set(preparation.documents.beer_hops.map((d) => d.id));
  if (aromes !== null) {
    const tri = trierAromes(aromes.entrees, idsHoublons, aromes.groupe);
    valides[COLLECTION_AROMES] = tri.valides;
    refuses.push(...tri.refuses);
  }
  const sansDescription = compterSansDescription(
    preparation.documents.beer_hops,
    aromes?.entrees ?? [],
  );

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
    for (const collection of COLLECTIONS_ECRITES) {
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
      aromas_file: aromes === null ? "absent" : "read",
      hops_without_aroma: sansDescription,
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
