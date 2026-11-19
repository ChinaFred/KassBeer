// Écriture des documents préparés : comparaison au contenu en base par getAll, puis
// écriture par lots de 400 des seuls documents changés. Un document inchangé (même
// content_sha256) n'est pas réécrit : une seconde exécution sur la même préparation
// n'écrit rien. Chaque document est écrit en entier (set sans fusion), avec updated_at
// posé par le serveur.
//
// Suppression des documents absents de la préparation (ADR-014, section 3, P19) : seulement
// sur option (--supprimer-absents <collection>), dans beer_hops ou beer_hop_aromas, 30 au
// plus par lancement, refusée si la préparation compte moins de 90 % des documents en ligne.
// Un identifiant hors du motif de la collection n'est jamais supprimé.

import { COLLECTIONS_SUPPRIMABLES, ErreurOptions } from "./options.mjs";
import { COLLECTIONS_ECRITES, motifIdentifiant } from "./validation.mjs";

/// Écritures par lot (limite Firestore : 500).
export const TAILLE_LOT = 400;

/// Documents lus par appel à getAll.
export const TAILLE_LECTURE = 300;

/// Vrai si [stocke] (données en base, ou undefined) a le contenu de [data]. Un document
/// à content_sha256 se compare sur elle ; un document de import_unresolved, qui n'en a
/// pas, champ par champ, hors updated_at.
export function inchange(stocke, data) {
  if (stocke === undefined) return false;
  if ("content_sha256" in data) return stocke.content_sha256 === data.content_sha256;
  const cles = Object.keys(stocke).filter((k) => k !== "updated_at");
  return (
    cles.length === Object.keys(data).length &&
    Object.entries(data).every(([k, v]) => stocke[k] === v)
  );
}

/// Écrit [documents] (`{collection: [{id, data}]}`, déjà contrôlés) dans [db]. En
/// [simulation], lit et compte sans écrire. Rend `{collection: {written, unchanged}}`.
export async function ecrireCollections({ db, FieldValue, documents, simulation }) {
  const comptes = {};
  let lot = db.batch();
  let dansLot = 0;
  const ajouter = async (ref, data) => {
    lot.set(ref, { ...data, updated_at: FieldValue.serverTimestamp() });
    dansLot++;
    if (dansLot === TAILLE_LOT) {
      await lot.commit();
      lot = db.batch();
      dansLot = 0;
    }
  };
  for (const collection of COLLECTIONS_ECRITES) {
    const docs = documents[collection] ?? [];
    const compte = { written: 0, unchanged: 0 };
    for (let i = 0; i < docs.length; i += TAILLE_LECTURE) {
      const partie = docs.slice(i, i + TAILLE_LECTURE);
      const refs = partie.map((d) => db.collection(collection).doc(d.id));
      const lus = await db.getAll(...refs);
      for (let j = 0; j < partie.length; j++) {
        const stocke = lus[j].exists ? lus[j].data() : undefined;
        if (inchange(stocke, partie[j].data)) {
          compte.unchanged++;
        } else {
          compte.written++;
          if (!simulation) await ajouter(refs[j], partie[j].data);
        }
      }
    }
    comptes[collection] = compte;
  }
  if (dansLot > 0) await lot.commit();
  return comptes;
}

/// Suppressions au plus par lancement.
export const PLAFOND_SUPPRESSIONS = 30;

/// Part minimale des documents en ligne que la préparation doit compter.
export const PART_MIN_PREPAREE = 0.9;

/// Identifiants des documents de [collection] en ligne dans [db] (lecture des seuls
/// identifiants, sans les champs).
export async function idsEnLigne(db, collection) {
  const instantane = await db.collection(collection).select().get();
  return instantane.docs.map((d) => d.id);
}

/// Plan de suppression de [collection] : [enLigne] (identifiants en base) moins
/// [prepares] (identifiants de la préparation, refusés compris). Rend
/// `{ collection, online, prepared, candidates, ignored }` : `candidates` triés, conformes
/// au motif de la collection ; `ignored` : `{ id, raison }` hors motif, jamais supprimés.
/// Lève ErreurOptions, avant toute écriture, pour une autre collection, plus de
/// PLAFOND_SUPPRESSIONS suppressions ou une préparation à moins de PART_MIN_PREPAREE des
/// documents en ligne.
export function planifierSuppressions({ collection, enLigne, prepares }) {
  if (!COLLECTIONS_SUPPRIMABLES.includes(collection)) {
    throw new ErreurOptions(
      `Suppression refusée dans ${collection} : seules ${COLLECTIONS_SUPPRIMABLES.join(" et ")} ` +
        "sont permises (ADR-014). Rien n'est écrit ni supprimé.",
    );
  }
  const preparesSet = new Set(prepares);
  const enLigneSet = new Set(enLigne);
  if (enLigneSet.size > 0 && preparesSet.size < PART_MIN_PREPAREE * enLigneSet.size) {
    throw new ErreurOptions(
      `Suppression refusée dans ${collection} : la préparation compte ${preparesSet.size} ` +
        `documents pour ${enLigneSet.size} en ligne, moins de ${PART_MIN_PREPAREE * 100} %. ` +
        "Préparation incomplète ? Rien n'est écrit ni supprimé.",
    );
  }
  const motif = motifIdentifiant(collection);
  const candidates = [];
  const ignored = [];
  for (const id of [...enLigneSet].sort()) {
    if (preparesSet.has(id)) continue;
    if (id.length > 200 || !motif.test(id)) {
      ignored.push({ id, raison: "identifiant hors du motif de la collection" });
    } else {
      candidates.push(id);
    }
  }
  if (candidates.length > PLAFOND_SUPPRESSIONS) {
    throw new ErreurOptions(
      `Suppression refusée dans ${collection} : ${candidates.length} documents absents de la ` +
        `préparation, ${PLAFOND_SUPPRESSIONS} au plus par lancement. Rien n'est écrit ni supprimé.`,
    );
  }
  return {
    collection,
    online: enLigneSet.size,
    prepared: preparesSet.size,
    candidates,
    ignored,
  };
}

/// Supprime un à un les documents [ids] de [collection]. Rend `{ deleted, errors }` :
/// identifiants supprimés, et `{ id, erreur }` pour chaque échec (code ou nom de l'erreur),
/// noté au rapport et montré par ecrire.mjs.
export async function supprimerDocuments({ db, collection, ids }) {
  const deleted = [];
  const errors = [];
  for (const id of ids) {
    try {
      await db.collection(collection).doc(id).delete();
      deleted.push(id);
    } catch (erreur) {
      errors.push({ id, erreur: String(erreur?.code ?? erreur?.name ?? "inconnue") });
    }
  }
  return { deleted, errors };
}
