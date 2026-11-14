/**
 * Réglages des Cloud Functions de Kass'Beer (ADR-006).
 *
 * Chaque valeur vient d'une décision écrite : région de la base (ADR-001), dépôt public
 * et compte propriétaire (ADR-002, ADR-006), plafonds du jour (ADR-006, décision 7).
 */

import { defineSecret } from "firebase-functions/params";

/** Région de la base Firestore `(default)`. */
export const REGION = "europe-west1";

/** Projet Firebase de Kass'Beer (`.firebaserc`). */
export const PROJECT_ID = "kassbeer";

/**
 * Bucket Cloud Storage des captures de tickets (ADR-008, T6), nommé : Firebase ne le
 * déclare pas comme bucket par défaut du projet (déploiement de la v0.1.41), et
 * `getStorage().bucket()` sans nom n'en trouverait aucun.
 */
export const STORAGE_BUCKET = `${PROJECT_ID}.firebasestorage.app`;

/**
 * Compte d'exécution des fonctions, adresse complète. La forme courte `tickets-functions@`
 * n'est pas complétée par firebase-tools quand il donne au compte l'accès au secret
 * (`secrets:setIamPolicy` refusé en 400, déploiement du 2026-11-10).
 */
export const RUNTIME_SERVICE_ACCOUNT = `tickets-functions@${PROJECT_ID}.iam.gserviceaccount.com`;

/**
 * Jeton à grain fin du compte propriétaire, limité à `ChinaFred/KassBeer` : Issues en
 * lecture et écriture ; Pull requests, Contents et Actions en lecture (P25 ; Actions depuis
 * T5, pour les runs de la CI d'une PR). Déclaré ici, lu à l'appel.
 */
export const GITHUB_TICKETS_TOKEN = defineSecret("GITHUB_TICKETS_TOKEN");

/**
 * Secret partagé avec le webhook du dépôt (ADR-008, T3) : HMAC SHA-256 du corps de chaque
 * livraison (`X-Hub-Signature-256`). Monté par `githubTicketWebhook` seul (P25).
 */
export const GITHUB_WEBHOOK_SECRET = defineSecret("GITHUB_WEBHOOK_SECRET");

/**
 * Routines Claude Code des tickets (ADR-008, T4, P35) : identifiant (`trig_…`) et jeton de
 * déclenchement de chaque routine, créés sur claude.ai/code. Chaque paire est montée par les
 * seules callables qui la lisent (P25) : l'analyse par `launchTicketAnalysis` ; le
 * développement par `launchTicketDevelopment` (développement et reprise) et
 * `launchTicketDelivery`, la livraison partant par la routine de développement (T5). Vides :
 * « Lancement non configuré », rien ne part.
 */
export const TICKETS_ROUTINE_ANALYSIS_ID = defineSecret("TICKETS_ROUTINE_ANALYSIS_ID");
export const TICKETS_ROUTINE_ANALYSIS_TOKEN = defineSecret("TICKETS_ROUTINE_ANALYSIS_TOKEN");
export const TICKETS_ROUTINE_DEV_ID = defineSecret("TICKETS_ROUTINE_DEV_ID");
export const TICKETS_ROUTINE_DEV_TOKEN = defineSecret("TICKETS_ROUTINE_DEV_TOKEN");

/**
 * Origines admises par les callables (ADR-008, P25) : l'application web hébergée. Cette
 * liste limite les navigateurs, pas un script.
 */
export const CALLABLE_ORIGINS = ["https://kassbeer.web.app", "https://kassbeer.firebaseapp.com"];

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

/** Sous-collection des documents d'un ticket lus par l'admin seul (ADR-008). */
export const TICKET_ADMIN_SUBCOLLECTION = "admin";
/** Analyses relevées sur l'Issue : `tickets/{id}/admin/analysis` (P32). */
export const TICKET_ANALYSIS_DOC = "analysis";
/** Historique des lancements de sessions : `tickets/{id}/admin/launches` (P41). */
export const TICKET_LAUNCHES_DOC = "launches";
/** Compteurs des lancements affichés à l'admin : `ticket_status/launches` (P36, P41). */
export const TICKET_STATUS_LAUNCHES_DOC = "launches";
/** État « PR prête » et comptes rendus de livraison : `tickets/{id}/admin/delivery` (P45). */
export const TICKET_DELIVERY_DOC = "delivery";

/**
 * Poste de coût des lancements de routines (CLAUDE.md, « Coûts variables », P36) : inscrit
 * au catalogue de `exigences-techniques.md`. Seul nom employé pour ce poste.
 */
export const LAUNCH_COST_CENTER = "ticket_routine_launch";

/**
 * Plafond des lancements de routines, analyse, développement, reprise et livraison confondus,
 * pour le groupe, par jour de Paris (ADR-008, P36). Seul endroit où il est écrit : le client
 * le lit dans `ticket_status/launches.per_day`.
 */
export const LAUNCHES_PER_DAY = 10;

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
