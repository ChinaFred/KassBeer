/**
 * Accès au bucket Cloud Storage par défaut, par le SDK Admin, chargé au premier usage et
 * mémorisé (ADR-008, T6, P26). Comme `firestore.ts` : la découverte des fonctions au
 * déploiement charge `index.js` sans ouvrir de client.
 */

import type * as AdminStorage from "firebase-admin/storage";

/** Ce que `attachTicketScreenshot` lit d'un fichier du bucket. */
export interface StoredFile {
  exists: boolean;
  /** Taille en octets ; `NaN` si illisible. */
  size: number;
  /** Type MIME sans paramètres, en minuscules ; vide si absent. */
  contentType: string;
}

/** Lecture du bucket, remplacée dans les tests. */
export interface ScreenshotStore {
  stat(path: string): Promise<StoredFile>;
  /** Les `count` premiers octets du fichier. */
  head(path: string, count: number): Promise<Uint8Array>;
}

let bucket: ReturnType<AdminStorage.Storage["bucket"]> | null = null;

async function defaultBucket(): Promise<ReturnType<AdminStorage.Storage["bucket"]>> {
  if (bucket !== null) return bucket;
  const app = await import("firebase-admin/app");
  const st = await import("firebase-admin/storage");
  // Aucun `await` entre le test et l'initialisation : une seule application.
  if (app.getApps().length === 0) app.initializeApp();
  bucket = st.getStorage().bucket();
  return bucket;
}

/** Le bucket par défaut du projet. Un chargement en échec lève et n'est pas mémorisé. */
export const storageScreenshotStore: ScreenshotStore = {
  async stat(path) {
    const file = (await defaultBucket()).file(path);
    const [exists] = await file.exists();
    if (!exists) return { exists: false, size: Number.NaN, contentType: "" };
    const [metadata] = await file.getMetadata();
    return {
      exists: true,
      size: Number(metadata.size ?? Number.NaN),
      contentType: String(metadata.contentType ?? "")
        .split(";")[0]
        .trim()
        .toLowerCase(),
    };
  },
  async head(path, count) {
    const file = (await defaultBucket()).file(path);
    const [bytes] = await file.download({ start: 0, end: count - 1 });
    return new Uint8Array(bytes);
  },
};
