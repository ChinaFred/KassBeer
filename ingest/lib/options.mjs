// Options de l'écrivain (ADR-005, « Échange et ingestion ») : émulateur par défaut,
// production sur option explicite (--production --projet kassbeer) et confirmation
// interactive. Aucune clé JSON de compte de service : GOOGLE_APPLICATION_CREDENTIALS et
// CLOUDSDK_CONFIG sont refusés (quelle que soit la casse), et en production le fichier ADC
// doit être celui d'un compte utilisateur ou d'un emprunt de compte de service
// (gcloud auth application-default login, avec ou sans --impersonate-service-account).

import { homedir } from "node:os";
import { join } from "node:path";

/// Projet de production, seul accepté avec --production.
export const PROJET_PRODUCTION = "kassbeer";

/// Projet de l'émulateur par défaut.
export const PROJET_EMULATEUR = "demo-kassbeer";

/// Erreur d'utilisation : message montré tel quel, code de sortie 2.
export class ErreurOptions extends Error {}

const AIDE = `Usage : node ecrire.mjs [--simulation] [--dossier <prepare>] [--rapports <dossier>]
        node ecrire.mjs --production --projet ${PROJET_PRODUCTION} [--simulation] [...]`;

/// Lit [argv] (sans `node` ni le script) et [env]. Rend
/// `{ cible, projet, simulation, dossier, rapports }` ; lève ErreurOptions.
export function lireOptions(argv, env) {
  const options = {
    production: false,
    simulation: false,
    projet: null,
    dossier: null,
    rapports: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const nom = argv[i];
    switch (nom) {
      case "--production":
        options.production = true;
        break;
      case "--simulation":
        options.simulation = true;
        break;
      case "--projet":
      case "--dossier":
      case "--rapports": {
        const valeur = argv[++i];
        if (valeur === undefined || valeur.startsWith("--")) {
          throw new ErreurOptions(`${nom} demande une valeur.\n${AIDE}`);
        }
        options[nom.slice(2)] = valeur;
        break;
      }
      default:
        throw new ErreurOptions(`Option inconnue : ${nom}\n${AIDE}`);
    }
  }
  for (const cle of Object.keys(env)) {
    const majuscule = cle.toUpperCase();
    if (majuscule === "GOOGLE_APPLICATION_CREDENTIALS" || majuscule === "CLOUDSDK_CONFIG") {
      throw new ErreurOptions(
        `${cle} est défini : seuls les identifiants ADC du dossier gcloud par défaut sont ` +
          "acceptés, jamais une clé de compte de service. Retirez la variable et utilisez " +
          "« gcloud auth application-default login ».",
      );
    }
  }
  if (options.production) {
    if (options.projet !== PROJET_PRODUCTION) {
      throw new ErreurOptions(
        `--production demande --projet ${PROJET_PRODUCTION} (lu : ${options.projet ?? "rien"}).`,
      );
    }
    if (env.FIRESTORE_EMULATOR_HOST) {
      throw new ErreurOptions(
        "FIRESTORE_EMULATOR_HOST est défini avec --production : cible ambiguë, rien n'est écrit.",
      );
    }
  } else {
    if (!env.FIRESTORE_EMULATOR_HOST) {
      throw new ErreurOptions(
        "FIRESTORE_EMULATOR_HOST n'est pas défini : sans lui, l'Admin SDK viserait la " +
          "production. Lancez l'émulateur (firebase emulators:exec ou emulators:start) ou " +
          "passez --production --projet " +
          PROJET_PRODUCTION +
          ".",
      );
    }
    if (options.projet !== null && !options.projet.startsWith("demo-")) {
      throw new ErreurOptions(
        `Sur l'émulateur, seul un projet demo-* est accepté (lu : ${options.projet}).`,
      );
    }
  }
  return {
    cible: options.production ? "production" : "emulator",
    projet: options.production ? PROJET_PRODUCTION : (options.projet ?? PROJET_EMULATEUR),
    simulation: options.simulation,
    dossier: options.dossier,
    rapports: options.rapports,
  };
}

/// Types de fichier ADC acceptés en production.
export const TYPES_IDENTIFIANTS = ["authorized_user", "impersonated_service_account"];

/// Chemin du fichier ADC de gcloud : %APPDATA%\gcloud sous Windows, ~/.config/gcloud
/// ailleurs (CLOUDSDK_CONFIG est refusé par lireOptions).
export function cheminIdentifiants(env, plateforme = process.platform, maison = homedir()) {
  const dossier =
    plateforme === "win32"
      ? join(env.APPDATA ?? join(maison, "AppData", "Roaming"), "gcloud")
      : join(maison, ".config", "gcloud");
  return join(dossier, "application_default_credentials.json");
}

/// Vérifie le type du fichier ADC lu par [lire] (chemin → texte) : `authorized_user`, ou
/// `impersonated_service_account` dont les identifiants sources (`source_credentials`)
/// sont eux-mêmes `authorized_user`. Lève ErreurOptions pour une clé de compte de service,
/// à la racine ou en source d'un emprunt, un autre type, un fichier absent ou illisible.
/// Rend le type ; aucun autre champ n'est montré.
export function controlerIdentifiants(chemin, lire) {
  let texte;
  try {
    texte = lire(chemin);
  } catch (erreur) {
    throw new ErreurOptions(
      `Identifiants ADC illisibles (${chemin}, ${erreur.code ?? erreur.name}) : lancez ` +
        "« gcloud auth application-default login ».",
    );
  }
  let type;
  let typeSource;
  try {
    const adc = JSON.parse(texte);
    type = adc.type;
    typeSource = adc.source_credentials?.type;
  } catch (erreur) {
    throw new ErreurOptions(`Identifiants ADC illisibles (${chemin}, ${erreur.name}).`);
  }
  if (!TYPES_IDENTIFIANTS.includes(type)) {
    throw new ErreurOptions(
      `Identifiants ADC de type « ${type} » refusés : seuls ${TYPES_IDENTIFIANTS.join(" et ")} ` +
        "sont acceptés (aucune clé de compte de service).",
    );
  }
  if (type === "impersonated_service_account" && typeSource !== "authorized_user") {
    throw new ErreurOptions(
      `Emprunt de compte de service depuis des identifiants de type « ${typeSource} » ` +
        "refusé : la source doit être authorized_user (aucune clé de compte de service).",
    );
  }
  return type;
}

/// Demande la saisie du nom du projet sur un terminal. [entree] et [sortie] : flux
/// du processus. Rend vrai si la saisie est exactement le nom attendu ; lève
/// ErreurOptions sans terminal (aucune confirmation possible, donc aucun envoi).
export async function confirmerProduction(projet, entree, sortie) {
  if (!entree.isTTY || !sortie.isTTY) {
    throw new ErreurOptions(
      "Écriture en production sans terminal : la confirmation est impossible, rien n'est écrit.",
    );
  }
  const { createInterface } = await import("node:readline/promises");
  const rl = createInterface({ input: entree, output: sortie });
  try {
    const saisie = await rl.question(
      `Écriture dans le projet de PRODUCTION « ${projet} ». Saisissez son nom pour confirmer : `,
    );
    return saisie.trim() === projet;
  } finally {
    rl.close();
  }
}
