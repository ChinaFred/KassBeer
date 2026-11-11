// Écriture des documents préparés : comparaison au contenu en base par getAll, puis
// écriture par lots de 400 des seuls documents changés. Un document inchangé (même
// content_sha256) n'est pas réécrit : une seconde exécution sur la même préparation
// n'écrit rien. Chaque document est écrit en entier (set sans fusion), avec updated_at
// posé par le serveur.

import { COLLECTIONS } from "./validation.mjs";

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
  for (const collection of COLLECTIONS) {
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
