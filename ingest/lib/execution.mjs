// Une exécution de l'écrivain : options, lecture de la préparation, contrôle, écriture,
// rapport JSON dans import/ingest/rapports/ et document ingest_runs/<id>.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  ecrireCollections,
  idsEnLigne,
  planifierSuppressions,
  supprimerDocuments,
} from "./ecriture.mjs";
import {
  cheminIdentifiants,
  confirmerProduction,
  confirmerSuppressions,
  controlerIdentifiants,
  ErreurOptions,
  lireOptions,
} from "./options.mjs";
import { NATURE_HOUBLON } from "./aromes/nature.mjs";
import { NATURE_DIVERS } from "./divers/nature.mjs";
import { NATURE_LEVURE } from "./levures/nature.mjs";
import { empreinteContenu } from "./redaction/texte.mjs";
import {
  COLLECTION_EXECUTIONS,
  COLLECTIONS,
  COLLECTIONS_ECRITES,
  controlerDocument,
  ID_INDEX_AROMES,
} from "./validation.mjs";

const NATURES = ["fermentable", "hop", "culture", "misc"];

/// Natures rédigées par l'API dont ecrire.mjs écrit les entrées, dans l'ordre : houblons
/// (beer_hop_aromas, ADR-013), levures (beer_culture_aromas, ADR-017), divers
/// (beer_misc_descriptions, ADR-018).
export const NATURES_REDIGEES = [NATURE_HOUBLON, NATURE_LEVURE, NATURE_DIVERS];

/// Commandes qui refont la liste du groupe de [nature], en production.
const commandesListe = (nature) =>
  `node lister-ingredients-recettes.mjs --nature ${nature.cle} --production --projet kassbeer, ` +
  `puis dart run bin/lister_ingredients_recettes.dart --nature ${nature.cle}`;

/// Dossier des entrées de [nature] pour ecrire.mjs : option de la nature (--aromes,
/// --divers) ou dossier frère de la préparation, puis sous-dossier de la nature (levures/).
export function dossierRedigees(nature, options, dossierPrepare) {
  const e = nature.ecriture;
  const base = resolve(options[e.option] ?? join(dossierPrepare, "..", e.nomDossier));
  return e.sousDossier === null ? base : join(base, e.sousDossier);
}

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
      if (collection === "beer_index" && doc?.id === ID_INDEX_AROMES) {
        erreurs.push("id : construit par ecrire.mjs depuis aromes.json, jamais préparé");
      }
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

/// Lit le dossier d'une nature rédigée ([dossier], import/ingest/aromes/,
/// import/ingest/aromes/levures/ ou import/ingest/divers/) : le fichier des entrées
/// (`aromes.json`, `descriptions.json`, liste `{id, data}`) et la liste du groupe
/// (`houblons-recettes.json`, `levures-recettes.json`, `divers-recettes.json`). Rend null si le fichier des entrées manque : aucune entrée n'est
/// écrite. Lève une erreur s'il existe sans la liste du groupe : sans elle, l'écrivain ne
/// peut pas refuser une entrée du groupe non relue, et rien n'est écrit.
export function lireEntreesRedigees(dossier, nature) {
  const { fichierEntrees, fichierGroupe } = nature;
  const chemin = join(dossier, fichierEntrees);
  if (!existsSync(chemin)) return null;
  const entrees = JSON.parse(readFileSync(chemin, "utf8"));
  if (!Array.isArray(entrees)) throw new Error(`${fichierEntrees} : liste attendue`);
  const cheminGroupe = join(dossier, fichierGroupe);
  if (!existsSync(cheminGroupe)) {
    throw new Error(
      `${fichierGroupe} absent à côté de ${fichierEntrees} : lancez ` +
        `lister-ingredients-recettes.mjs --nature ${nature.cle} puis ` +
        `exchange/bin/lister_ingredients_recettes.dart --nature ${nature.cle}. Rien n'est écrit.`,
    );
  }
  const groupe = JSON.parse(readFileSync(cheminGroupe, "utf8"));
  if (groupe?.format !== nature.formatGroupe || !Array.isArray(groupe.resolus)) {
    throw new Error(`${fichierGroupe} : fichier de lister_ingredients_recettes.dart attendu`);
  }
  return {
    entrees,
    groupe: new Set(groupe.resolus.map((r) => r.id)),
    origine: { target: groupe.target ?? null, generated_at: groupe.generated_at ?? null },
  };
}

/// Âge maximal, en jours, de la liste du groupe (houblons, levures, divers) lue par une écriture en
/// production : une liste plus ancienne peut omettre un ingrédient ajouté depuis à une
/// recette, dont le texte non relu partirait.
export const AGE_MAX_LISTE_GROUPE_JOURS = 7;

/// Contrôle, avant une écriture en production, l'origine de la liste du groupe de [nature]
/// ([origine] : `target` et `generated_at` recopiés de la liste des noms). Lève ErreurOptions
/// si la liste vient de l'émulateur, d'une cible inconnue, n'a pas de date lisible ou a plus
/// de AGE_MAX_LISTE_GROUPE_JOURS jours : rien n'est écrit.
export function controlerListeGroupe(origine, maintenant, nature) {
  const { fichierGroupe, mots } = nature;
  const refaire = `Refaites la liste : ${commandesListe(nature)}. Rien n'est écrit.`;
  if (origine?.target !== "production") {
    throw new ErreurOptions(
      `${fichierGroupe} vient de la cible « ${origine?.target ?? "inconnue"} », pas ` +
        `de la production : les ${mots.des} du groupe peuvent manquer. ${refaire}`,
    );
  }
  const date = Date.parse(origine.generated_at ?? "");
  if (!Number.isFinite(date)) {
    throw new ErreurOptions(`${fichierGroupe} sans date de liste lisible. ${refaire}`);
  }
  const age = (maintenant.getTime() - date) / 86_400_000;
  if (age > AGE_MAX_LISTE_GROUPE_JOURS || age < -1) {
    throw new ErreurOptions(
      `${fichierGroupe} tiré le ${origine.generated_at.slice(0, 10)} : plus de ` +
        `${AGE_MAX_LISTE_GROUPE_JOURS} jours. ${refaire}`,
    );
  }
}

/// Sépare les entrées d'une nature rédigée bonnes des refusées (P55, P62, P63) : contrôle de
/// lib/<nature>/validation.mjs (styles de [contexte] pour les levures, contexteEcriture),
/// identifiant absent du référentiel préparé ([idsReferentiel]), entrée du groupe non relue,
/// identifiant en double. Les bonnes reçoivent `content_sha256`.
export function trierRedigees(nature, entrees, idsReferentiel, groupe, contexte) {
  const { collection } = nature.ecriture;
  const valides = [];
  const refuses = [];
  const vus = new Set();
  for (const doc of entrees) {
    const erreurs = nature.controlerEntree(doc, contexte);
    const id = typeof doc?.id === "string" ? doc.id : null;
    if (id !== null && !idsReferentiel.has(id)) erreurs.push(`id : ${nature.refus.absent}`);
    if (id !== null && groupe.has(id) && doc?.data?.reviewed !== true) {
      erreurs.push(`reviewed : ${nature.refus.nonRelu}`);
    }
    if (id !== null && vus.has(id)) erreurs.push("id : en double");
    if (id !== null) vus.add(id);
    if (erreurs.length > 0) {
      refuses.push({ collection, id, erreurs });
    } else {
      valides.push({ id, data: { ...doc.data, content_sha256: empreinteContenu(doc.data) } });
    }
  }
  return { valides, refuses };
}

/// Document beer_index/hop_aromas (ADR-013, note du 2026-11-21) tiré des entrées
/// acceptées par trierRedigees(NATURE_HOUBLON, …) ([valides]) : une entrée `{id, confidence}`
/// par houblon, triée par identifiant, `confidence` valant celle d'une entrée `described` ou
/// `unknown`. Aucun texte, aucun état de relecture. Rend `{id, data}` avec `count` et
/// `content_sha256`.
export function indexAromes(valides) {
  const entries = valides
    .map(({ id, data }) => ({
      id,
      confidence: data.status === "described" ? data.confidence : "unknown",
    }))
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const data = { count: entries.length, entries };
  return { id: ID_INDEX_AROMES, data: { ...data, content_sha256: empreinteContenu(data) } };
}

/// Index de beer_index construit par ecrire.mjs depuis les entrées acceptées d'une nature
/// rédigée. Seuls les houblons en ont un (ADR-013, note du 2026-11-21) ; les divers n'en ont
/// pas (ADR-018).
const INDEX_REDIGEES = new Map([[NATURE_HOUBLON, indexAromes]]);

/// Entrées du référentiel préparé ([documents]) sans entrée rédigée (ADR-013, « Ajouter un
/// houblon » ; ADR-018).
export function compterSansDescription(documents, entrees) {
  const decrits = new Set((entrees ?? []).map((e) => e?.id));
  return (documents ?? []).filter((d) => !decrits.has(d.id)).length;
}

/// Message de fin de ecrire.mjs pour [n] entrées de [nature] sans description ; null pour 0.
export function messageSansDescription(n, nature) {
  if (n === 0) return null;
  const { un, des } = nature.mots;
  return (
    `${n} ${n > 1 ? des : un} ${nature.ecriture.sansDescription} : lancez ` +
    `\`node ${nature.script} --nouveaux\` (ou \`--lot --nouveaux\` au-delà de 20).`
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

/// Entrées relues ([entrees] d'une nature rédigée) dont l'identifiant manque au référentiel
/// préparé ([idsReferentiel]) : description relue orpheline, après une fusion d'ADR-014
/// (ADR-017, section 5 ; ADR-019, pour les trois natures). Identifiants triés.
export function relueOrphelines(entrees, idsReferentiel) {
  return entrees
    .filter((e) => e?.data?.reviewed === true && typeof e?.id === "string")
    .map((e) => e.id)
    .filter((id) => !idsReferentiel.has(id))
    .sort();
}

/// Identifiants préparés de [collection] (refusés compris : un document refusé garde sa
/// version en ligne), pour --supprimer-absents. beer_hop_aromas et beer_culture_aromas
/// exigent leur fichier d'entrées ([lues] : lecture par collection, null si absent) : sans
/// lui, ErreurOptions, rien n'est écrit ni supprimé. beer_misc_descriptions n'est pas
/// supprimable (ADR-018, décision 5 ; COLLECTIONS_SUPPRIMABLES).
export function idsPrepares(collection, preparation, lues) {
  const nature = NATURES_REDIGEES.find((n) => n.ecriture.collection === collection);
  if (nature !== undefined) {
    const lu = lues?.[collection] ?? null;
    if (lu === null) {
      const e = nature.ecriture;
      const fichier =
        e.sousDossier === null
          ? nature.fichierEntrees
          : `${e.sousDossier}/${nature.fichierEntrees}`;
      throw new ErreurOptions(
        `--supprimer-absents ${collection} sans ${fichier} : rien n'est écrit ni supprimé.`,
      );
    }
    return lu.entrees.map((e) => e?.id).filter((id) => typeof id === "string");
  }
  return (preparation.documents[collection] ?? [])
    .map((d) => d?.id)
    .filter((id) => typeof id === "string");
}

/// Exécute l'écrivain. [argv] sans `node` ni le script ; [env], [entree], [sortie] : ceux
/// du processus. Rend le rapport d'exécution. Lève ErreurOptions pour une utilisation
/// refusée, une autre erreur pour un échec. [confirmerSuppression] (collection, ids) :
/// saisie du nombre de suppressions, remplacée dans les tests.
export async function executer({
  argv,
  env,
  entree,
  sortie,
  maintenant = () => new Date(),
  lireIdentifiants = (chemin) => readFileSync(chemin, "utf8"),
  confirmerSuppression = (collection, ids) =>
    confirmerSuppressions(collection, ids, entree, sortie),
}) {
  const debut = maintenant();
  const options = lireOptions(argv, env);
  const dossier = resolve(options.dossier ?? DOSSIER_PREPARE);
  const dossierRapports = resolve(options.rapports ?? DOSSIER_RAPPORTS);
  const preparation = lirePreparation(dossier);
  const { valides, refuses } = trier(preparation.documents);
  // Natures rédigées : entrées lues et listes du groupe contrôlées avant toute écriture.
  const redigees = new Map();
  for (const nature of NATURES_REDIGEES) {
    const lues = lireEntreesRedigees(dossierRedigees(nature, options, dossier), nature);
    if (lues !== null && options.cible === "production") {
      controlerListeGroupe(lues.origine, debut, nature);
    }
    redigees.set(nature, lues);
  }
  const resume = {};
  const orphelines = {};
  const luesParCollection = {};
  for (const [nature, lues] of redigees) {
    const e = nature.ecriture;
    luesParCollection[e.collection] = lues;
    const documentsReferentiel = preparation.documents[e.referentielCollection];
    if (lues !== null) {
      const ids = new Set(documentsReferentiel.map((d) => d.id));
      // Levures : styles acceptés par trier() seuls ; une entrée qui cite un style refusé à
      // la préparation est refusée.
      const contexte = e.contexteEcriture?.(valides);
      const tri = trierRedigees(nature, lues.entrees, ids, lues.groupe, contexte);
      valides[e.collection] = tri.valides;
      refuses.push(...tri.refuses);
      orphelines[e.collection] = relueOrphelines(lues.entrees, ids);
      // Index de la nature (houblons seuls), contrôlé comme les autres documents de beer_index.
      const construireIndex = INDEX_REDIGEES.get(nature);
      if (construireIndex !== undefined) {
        const index = construireIndex(tri.valides);
        const erreurs = controlerDocument("beer_index", index);
        if (erreurs.length > 0) {
          refuses.push({ collection: "beer_index", id: index.id, erreurs });
        } else {
          valides.beer_index.push(index);
        }
      }
    }
    resume[e.champFichier] = lues === null ? "absent" : "read";
    if (e.champSansDescription !== null) {
      resume[e.champSansDescription] = compterSansDescription(
        documentsReferentiel,
        lues?.entrees ?? [],
      );
    }
  }
  const prepares =
    options.supprimerAbsents === null
      ? null
      : idsPrepares(options.supprimerAbsents, preparation, luesParCollection);

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
    // Plan et confirmation des suppressions avant toute écriture : un refus n'écrit rien.
    let plan = null;
    if (prepares !== null) {
      plan = planifierSuppressions({
        collection: options.supprimerAbsents,
        enLigne: await idsEnLigne(db, options.supprimerAbsents),
        prepares,
      });
      if (!options.simulation && plan.candidates.length > 0) {
        const confirme = await confirmerSuppression(plan.collection, plan.candidates);
        if (!confirme) {
          throw new ErreurOptions(
            "Nombre de suppressions non confirmé : rien n'est écrit ni supprimé.",
          );
        }
      }
    }
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
    let deletions = null;
    if (plan !== null) {
      const fait = options.simulation
        ? { deleted: [], errors: [] }
        : await supprimerDocuments({ db, collection: plan.collection, ids: plan.candidates });
      deletions = {
        collection: plan.collection,
        online: plan.online,
        prepared: plan.prepared,
        candidates: plan.candidates,
        deleted: fait.deleted,
        ignored: plan.ignored,
        errors: fait.errors,
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
      ...resume,
      reviewed_orphans: orphelines,
      ...(deletions === null ? {} : { deletions }),
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
