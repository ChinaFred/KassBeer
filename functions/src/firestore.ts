/**
 * Accès à Firestore par le SDK Admin, chargé au premier usage et mémorisé (P26, CLAUDE.md
 * « Aucune dépendance lourde chargée au démarrage »). La découverte des fonctions au
 * déploiement charge `index.js` sans ouvrir de client.
 */

import type * as AdminFirestore from "firebase-admin/firestore";

import { ensureDefaultApp } from "./adminApp";

export interface FirestoreKit {
  db: AdminFirestore.Firestore;
  FieldValue: typeof AdminFirestore.FieldValue;
  Timestamp: typeof AdminFirestore.Timestamp;
  FieldPath: typeof AdminFirestore.FieldPath;
}

let kit: FirestoreKit | null = null;

/**
 * Le client Firestore. Un chargement en échec lève et n'est pas mémorisé : l'appelant
 * journalise, l'appel suivant réessaie. `ensureDefaultApp` est synchrone : deux appels
 * simultanés n'initialisent qu'une application par défaut.
 */
export async function firestore(): Promise<FirestoreKit> {
  if (kit !== null) return kit;
  const app = await import("firebase-admin/app");
  const fs = await import("firebase-admin/firestore");
  ensureDefaultApp(app);
  kit = {
    db: fs.getFirestore(),
    FieldValue: fs.FieldValue,
    Timestamp: fs.Timestamp,
    FieldPath: fs.FieldPath,
  };
  return kit;
}
