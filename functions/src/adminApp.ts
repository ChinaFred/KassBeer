/**
 * Application par défaut du SDK Admin, partagée par `firestore.ts` et `storage.ts`.
 *
 * `firebase-functions` crée sa propre application nommée pour vérifier le jeton d'une
 * callable, avant d'appeler le code de la fonction. Tester `getApps().length === 0` ne
 * suffit donc pas : la liste n'est pas vide, aucune application par défaut n'existe, et
 * `getFirestore()` lève `app/no-app` (panne de chaque callable jusqu'à la v0.1.47).
 */

import type * as AdminApp from "firebase-admin/app";

/** Nom de l'application par défaut du SDK Admin. */
export const DEFAULT_APP_NAME = "[DEFAULT]";

/**
 * Crée l'application par défaut si elle manque, même quand une application nommée existe.
 * Synchrone : deux appels simultanés n'en créent qu'une.
 */
export function ensureDefaultApp(app: typeof AdminApp): void {
  if (!app.getApps().some((a) => a.name === DEFAULT_APP_NAME)) app.initializeApp();
}
