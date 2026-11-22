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
import { contexteStyles, NATURE_LEVURE } from "./aromes/natures/culture.mjs";
import { NATURE_HOUBLON } from "./aromes/natures/hop.mjs";
import { COLLECTION_AROMES, empreinteContenu } from "./aromes/validation.mjs";
import {
  COLLECTION_EXECUTIONS,
  COLLECTIONS,
  COLLECTIONS_ECRITES,
  controlerDocument,
  stylesBaRefusesEnProduction,
  ID_INDEX_AROMES,
} from "./validation.mjs";

const NATURES = ["fermentable", "hop", "culture", "misc"];

/// Natures des descriptions aromatiques écrites (ADR-013, ADR-017) : houblons depuis
/// import/ingest/aromes/, levures depuis import/ingest/aromes/levures/.
export const NATURES_AROMES = [NATURE_HOUBLON, NATURE_LEVURE];

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

/// Commandes qui refont la liste du groupe de [nature], en production.
const commandesListe = (nature) =>
  `node lister-ingredients-recettes.mjs --nature ${nature.cle} --production --projet kassbeer, ` +
  `puis dart run bin/lister_ingredients_recettes.dart --nature ${nature.cle}`;

/// Lit le dossier des arômes de [nature] ([dossier] : import/ingest/aromes/, ou levures/) :
/// `aromes.json` (liste `{id, data}`) et la liste du groupe (`houblons-recettes.json`,
/// `levures-recettes.json`). Rend null si aromes.json manque : aucune description n'est
/// écrite. Lève une erreur si aromes.json existe sans la liste du groupe : sans elle,
/// l'écrivain ne peut pas refuser un élément du groupe non relu, et rien n'est écrit.
export function lireAromesPrepares(dossier, nature = NATURE_HOUBLON) {
  const chemin = join(dossier, "aromes.json");
  if (!existsSync(chemin)) return null;
  const entrees = JSON.parse(readFileSync(chemin, "utf8"));
  if (!Array.isArray(entrees)) throw new Error("aromes.json : liste attendue");
  const nomGroupe = nature.fichierGroupe;
  const cheminGroupe = join(dossier, nomGroupe);
  if (!existsSync(cheminGroupe)) {
    throw new Error(
      `${nomGroupe} absent à côté de aromes.json : lancez ` +
        `lister-ingredients-recettes.mjs --nature ${nature.cle} puis ` +
        `exchange/bin/lister_ingredients_recettes.dart --nature ${nature.cle}. Rien n'est écrit.`,
    );
  }
  const groupe = JSON.parse(readFileSync(cheminGroupe, "utf8"));
  if (groupe?.format !== nature.formatGroupe || !Array.isArray(groupe.resolus)) {
    throw new Error(`${nomGroupe} : fichier de lister_ingredients_recettes.dart attendu`);
  }
  return {
    entrees,
    groupe: new Set(groupe.resolus.map((r) => r.id)),
    origine: { target: groupe.target ?? null, generated_at: groupe.generated_at ?? null },
  };
}

/// Âge maximal, en jours, de la liste des éléments du groupe lue par une écriture en
/// production : une liste plus ancienne peut omettre un houblon ou une levure ajouté depuis
/// à une recette, dont le texte non relu partirait.
export const AGE_MAX_LISTE_GROUPE_JOURS = 7;

/// Contrôle, avant une écriture en production, l'origine de la liste du groupe de [nature]
/// ([origine] : `target` et `generated_at` recopiés de la liste des noms). Lève
/// ErreurOptions si la liste vient de l'émulateur, d'une cible inconnue, n'a pas de date
/// lisible ou a plus de AGE_MAX_LISTE_GROUPE_JOURS jours : rien n'est écrit.
export function controlerListeGroupe(origine, maintenant, nature = NATURE_HOUBLON) {
  const nom = nature.fichierGroupe;
  const refaire = `Refaites la liste : ${commandesListe(nature)}. Rien n'est écrit.`;
  if (origine?.target !== "production") {
    throw new ErreurOptions(
      `${nom} vient de la cible « ${origine?.target ?? "inconnue"} », pas ` +
        `de la production : les ${nature.mots.des} du groupe peuvent manquer. ${refaire}`,
    );
  }
  const date = Date.parse(origine.generated_at ?? "");
  if (!Number.isFinite(date)) {
    throw new ErreurOptions(`${nom} sans date de liste lisible. ${refaire}`);
  }
  const age = (maintenant.getTime() - date) / 86_400_000;
  if (age > AGE_MAX_LISTE_GROUPE_JOURS || age < -1) {
    throw new ErreurOptions(
      `${nom} tiré le ${origine.generated_at.slice(0, 10)} : plus de ` +
        `${AGE_MAX_LISTE_GROUPE_JOURS} jours. ${refaire}`,
    );
  }
}

/// Sépare les entrées de aromes.json de [nature] bonnes des refusées (ADR-013, P55 ;
/// ADR-017, P62) : contrôle de la nature (lib/aromes/validation.mjs ou
/// lib/aromes/natures/culture.mjs, styles de [contexte] pour les levures), identifiant
/// absent du référentiel préparé ([idsReferentiel]), élément du groupe non relu, identifiant
/// en double. Les bonnes reçoivent `content_sha256`.
export function trierAromes(entrees, idsReferentiel, groupe, nature = NATURE_HOUBLON, contexte) {
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
      refuses.push({ collection: nature.collection, id, erreurs });
    } else {
      valides.push({ id, data: { ...doc.data, content_sha256: empreinteContenu(doc.data) } });
    }
  }
  return { valides, refuses };
}

/// Document beer_index/hop_aromas (ADR-013, note du 2026-11-21) tiré des entrées
/// acceptées par trierAromes ([valides]) : une entrée `{id, confidence}` par houblon, triée
/// par identifiant, `confidence` valant celle d'une entrée `described` ou `unknown`. Aucun
/// texte, aucun état de relecture. Rend `{id, data}` avec `count` et `content_sha256`.
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

/// Entrées relues ([entrees] de aromes.json) dont l'identifiant manque au référentiel
/// préparé ([idsReferentiel]) : description relue orpheline, après une fusion d'ADR-014
/// (ADR-017, section 5). Identifiants triés.
export function relueOrphelines(entrees, idsReferentiel) {
  return entrees
    .filter((e) => e?.data?.reviewed === true && typeof e?.id === "string")
    .map((e) => e.id)
    .filter((id) => !idsReferentiel.has(id))
    .sort();
}

/// Identifiants préparés de [collection] (refusés compris : un document refusé garde sa
/// version en ligne), pour --supprimer-absents. beer_hop_aromas et beer_culture_aromas
/// exigent leur aromes.json ([aromes] : lecture par collection, null si absent) : sans lui,
/// ErreurOptions, rien n'est écrit ni supprimé.
export function idsPrepares(collection, preparation, aromes) {
  const nature = NATURES_AROMES.find((n) => n.collection === collection);
  if (nature !== undefined) {
    const lu = aromes?.[collection] ?? null;
    if (lu === null) {
      const fichier =
        nature.sousDossier === null ? "aromes.json" : `${nature.sousDossier}/aromes.json`;
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
  const dossierAromes = resolve(options.aromes ?? join(dossier, "..", "aromes"));
  const preparation = lirePreparation(dossier);
  const { valides, refuses } = trier(preparation.documents);
  // Arômes des deux natures : houblons à la racine du dossier, levures dans levures/.
  const lus = {};
  for (const nature of NATURES_AROMES) {
    const d = nature.sousDossier === null ? dossierAromes : join(dossierAromes, nature.sousDossier);
    lus[nature.collection] = lireAromesPrepares(d, nature);
    if (lus[nature.collection] !== null && options.cible === "production") {
      controlerListeGroupe(lus[nature.collection].origine, debut, nature);
    }
  }
  const aromes = lus[COLLECTION_AROMES];
  const orphelines = {};
  for (const nature of NATURES_AROMES) {
    const lu = lus[nature.collection];
    if (lu === null) continue;
    const referentiel = nature.referentiel.replace(/\.json$/, "");
    const ids = new Set(preparation.documents[referentiel].map((d) => d.id));
    // Styles acceptés par trier() seuls : un style refusé à la préparation n'est pas écrit, et
    // une entrée qui le cite est refusée.
    const contexte = nature === NATURE_LEVURE ? contexteStyles(valides.beer_styles) : undefined;
    const tri = trierAromes(lu.entrees, ids, lu.groupe, nature, contexte);
    valides[nature.collection] = tri.valides;
    refuses.push(...tri.refuses);
    orphelines[nature.collection] = relueOrphelines(lu.entrees, ids);
  }
  if (aromes !== null) {
    // Index des arômes des houblons, contrôlé comme les autres documents de beer_index.
    const index = indexAromes(valides[COLLECTION_AROMES]);
    const erreurs = controlerDocument("beer_index", index);
    if (erreurs.length > 0) {
      refuses.push({ collection: "beer_index", id: index.id, erreurs });
    } else {
      valides.beer_index.push(index);
    }
  }
  const sansDescription = compterSansDescription(
    preparation.documents.beer_hops,
    aromes?.entrees ?? [],
  );
  const prepares =
    options.supprimerAbsents === null
      ? null
      : idsPrepares(options.supprimerAbsents, preparation, lus);

  if (options.cible === "production") {
    // Styles de la Brewers Association : refusés en production avant le lot S2 (ADR-018).
    const ba = stylesBaRefusesEnProduction(preparation.documents);
    if (ba.length > 0) {
      throw new ErreurOptions(
        `Styles de la Brewers Association refusés en production avant le lot S2 d'ADR-018 ` +
          `(mention de la BA et guide encore absents de l'application) : ${ba.length} ` +
          `document(s), dont ${ba.slice(0, 5).join(", ")}. Rien n'est écrit. Préparer sans --ba ` +
          `pour la production, ou écrire dans l'émulateur.`,
      );
    }
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
      aromas_file: aromes === null ? "absent" : "read",
      culture_aromas_file: lus[NATURE_LEVURE.collection] === null ? "absent" : "read",
      reviewed_orphans: orphelines,
      hops_without_aroma: sansDescription,
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
