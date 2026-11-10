/**
 * Réglages des Cloud Functions de Kass'Beer (ADR-006).
 *
 * Chaque valeur vient d'une décision écrite : région de la base (ADR-001), dépôt public
 * et compte propriétaire (ADR-002, ADR-006), plafonds du jour (ADR-006, décision 7).
 */

import { defineSecret } from "firebase-functions/params";

/** Région de la base Firestore `(default)`. */
export const REGION = "europe-west1";

/** Compte d'exécution des fonctions, complété par l'identifiant du projet au déploiement. */
export const RUNTIME_SERVICE_ACCOUNT = "tickets-functions@";

/**
 * Jeton à grain fin du compte propriétaire, limité à `ChinaFred/KassBeer` : Issues en
 * lecture et écriture, Pull requests et Contents en lecture (P25). Déclaré ici, lu à l'appel.
 */
export const GITHUB_TICKETS_TOKEN = defineSecret("GITHUB_TICKETS_TOKEN");

export const GITHUB_OWNER = "ChinaFred";
export const GITHUB_REPO = "KassBeer";
export const GITHUB_REPO_FULL_NAME = `${GITHUB_OWNER}/${GITHUB_REPO}`;

/** Identifiant numérique du compte propriétaire (un login se renomme, pas un identifiant). */
export const GITHUB_MAINTAINER_ID = 16348852;

/** Fichier qui porte la version de l'application (CLAUDE.md, « Version »). */
export const PUBSPEC_PATH = "app/pubspec.yaml";

export const COLL_TICKETS = "tickets";
export const COLL_MEMBERS = "members";
export const COLL_TICKET_QUOTAS = "ticket_quotas";
export const COLL_TICKET_STATUS = "ticket_status";
export const TICKET_STATUS_GITHUB_DOC = "github";

/** Plafonds du jour de Paris (ADR-006, décision 7) ; l'administrateur n'est pas compté. */
export const MEMBER_DAILY_LIMIT = 5;
export const GROUP_DAILY_LIMIT = 20;

/** Durée de vie d'un compteur de plafond (TTL de `ticket_quotas/`). */
export const QUOTA_TTL_DAYS = 7;

/** Au dixième envoi en échec, le ticket passe `send_failed`. */
export const MAX_SEND_ATTEMPTS = 10;

/** Bail d'un envoi : deux envois simultanés du même ticket ne publient qu'une Issue. */
export const SEND_LEASE_MS = 2 * 60 * 1000;

/** Issues relues au plus par passe de la tâche horaire (ADR-006, question 6). */
export const ISSUES_PER_PASS = 30;

/** Tickets `pending` renvoyés au plus par passe. */
export const PENDING_PER_PASS = 20;

/** Longueur gardée d'une réponse relevée sur GitHub. */
export const REPLY_MAX_CHARS = 2000;
