/**
 * Cloud Functions de Kass'Beer (ADR-006, ADR-008, ADR-011). Onze fonctions, dont sept points
 * d'accès de la liste fermée d'ADR-008 et d'ADR-011 (P25) :
 *
 * - `publishTicket` : déclencheur de création de `tickets/{ticketId}`, publie l'Issue ;
 * - `onDecisionCreated` : déclencheur de création de
 *   `tickets/{ticketId}/decisions/{decisionId}`, applique la décision de l'admin (T2) ;
 * - `onDecisionUpdated` : déclencheur de mise à jour de la même décision, reprend une
 *   décision `failed` quand l'admin pose `retry_requested_at` (T2) ;
 * - `syncTickets` : tâche horaire, relance les envois demandés, renvoie les tickets
 *   `pending`, reprend les décisions au bail expiré et relit les Issues et leurs analyses ;
 * - `githubTicketWebhook` : `onRequest` public, signé HMAC (P29), état des Issues poussé
 *   par GitHub (T3) ;
 * - `answerTicketAnalysis` : `onCall` de l'admin (`requireAdmin`, P30), « Répondre » (T3) ;
 * - `launchTicketAnalysis`, `launchTicketDevelopment` : `onCall` de l'admin, lancement d'une
 *   routine Claude Code d'analyse ou de développement (T4, P35, P36) ; le développement
 *   accepte `mode: "resume"`, « Relancer le développement » (T5, P47) ;
 * - `launchTicketDelivery` : `onCall` de l'admin, « Livrer » (T5, P43, P44), par la routine
 *   de développement. Chaque callable ne monte que les secrets de sa routine (P25).
 * - `attachTicketScreenshot` : `onCall` de l'auteur membre (`requireMember`, P30), joint
 *   la capture déposée dans Cloud Storage à son ticket (T6). Aucun secret ;
 * - `queryLogs` : `onCall` de l'admin, Admin › Journaux (ADR-011, J2, P49), aucun secret.
 *
 * `QUERYABLE_FUNCTIONS` de `config.ts` reprend ces noms (`logs.test.ts`).
 *
 * Ce module ne construit aucun client (P26) : Firestore, Storage et GitHub s'ouvrent à
 * l'appel.
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  CALLABLE_ORIGINS,
  GITHUB_TICKETS_TOKEN,
  GITHUB_WEBHOOK_SECRET,
  REGION,
  RUNTIME_SERVICE_ACCOUNT,
  TICKETS_ROUTINE_ANALYSIS_ID,
  TICKETS_ROUTINE_ANALYSIS_TOKEN,
  TICKETS_ROUTINE_DEV_ID,
  TICKETS_ROUTINE_DEV_TOKEN,
} from "./config";
import { logError } from "./logging";
import { handleQueryLogsCall } from "./logs/queryLogs";
import { handleAnswerCall } from "./tickets/answer";
import { isRetryRequest } from "./tickets/decisionModel";
import { applyDecision } from "./tickets/decisions";
import { handleDevelopmentCall, handleLaunchCall } from "./tickets/launch";
import { publishTicket as publish } from "./tickets/publish";
import { handleScreenshotCall } from "./tickets/screenshot";
import { runHourlyPass } from "./tickets/sync";
import { handleGithubWebhook } from "./tickets/webhook";

export const publishTicket = onDocumentCreated(
  {
    document: "tickets/{ticketId}",
    region: REGION,
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    secrets: [GITHUB_TICKETS_TOKEN],
    maxInstances: 2,
    memory: "256MiB",
    timeoutSeconds: 60,
    // Un échec n'est pas rejoué par Eventarc : la tâche horaire renvoie les `pending`.
    retry: false,
  },
  async (event) => {
    const ticketId = event.params.ticketId;
    try {
      await publish(ticketId, GITHUB_TICKETS_TOKEN.value());
    } catch (err) {
      logError({
        message: "Tickets : déclencheur de publication en échec",
        feature: "tickets",
        ticketId,
        error: err,
      });
    }
  },
);

const DECISION_TRIGGER = {
  document: "tickets/{ticketId}/decisions/{decisionId}",
  region: REGION,
  serviceAccount: RUNTIME_SERVICE_ACCOUNT,
  secrets: [GITHUB_TICKETS_TOKEN],
  maxInstances: 2,
  memory: "256MiB" as const,
  // Plus court que le bail d'une décision (2 min) : un bail expiré veut dire une
  // fonction arrêtée, que la tâche horaire reprend.
  timeoutSeconds: 60,
  // Un échec n'est pas rejoué par Eventarc : la décision passe `failed`, l'admin la
  // relance, ou la tâche horaire la reprend si elle est restée `applying`.
  retry: false,
};

export const onDecisionCreated = onDocumentCreated(DECISION_TRIGGER, async (event) => {
  const { ticketId, decisionId } = event.params;
  try {
    await applyDecision(ticketId, decisionId, GITHUB_TICKETS_TOKEN.value());
  } catch (err) {
    logError({
      message: "Tickets : déclencheur de décision en échec",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { decisionId },
    });
  }
});

/** `retry_requested_at` d'un document, en millisecondes, ou `null`. */
function retryMillis(data: Record<string, unknown> | undefined): number | null {
  const value = data?.retry_requested_at as { toMillis?: () => number } | null | undefined;
  return typeof value?.toMillis === "function" ? value.toMillis() : null;
}

export const onDecisionUpdated = onDocumentUpdated(DECISION_TRIGGER, async (event) => {
  const { ticketId, decisionId } = event.params;
  try {
    // Les écritures du serveur sur la décision (état, bail, motif) déclenchent aussi
    // cette fonction : seule une reprise demandée par l'admin est traitée.
    const before = retryMillis(event.data?.before.data());
    const after = retryMillis(event.data?.after.data());
    if (!isRetryRequest(before, after)) return;
    await applyDecision(ticketId, decisionId, GITHUB_TICKETS_TOKEN.value());
  } catch (err) {
    logError({
      message: "Tickets : reprise de décision en échec",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { decisionId },
    });
  }
});

export const syncTickets = onSchedule(
  {
    // À heure fixe (minute 0, heure de Paris) : la passe de minuit remet le compteur des
    // lancements au nouveau jour (`refreshLaunchStatus`, ADR-008, T4).
    schedule: "0 * * * *",
    timeZone: "Europe/Paris",
    region: REGION,
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    secrets: [GITHUB_TICKETS_TOKEN],
    maxInstances: 1,
    memory: "256MiB",
    timeoutSeconds: 300,
    retryCount: 0,
  },
  async () => {
    try {
      await runHourlyPass(GITHUB_TICKETS_TOKEN.value());
    } catch (err) {
      logError({ message: "Tickets : tâche horaire en échec", feature: "tickets", error: err });
    }
  },
);

/**
 * Webhook GitHub des tickets (ADR-008, P29). Seule fonction qui monte
 * `GITHUB_WEBHOOK_SECRET` (P25) ; le jeton GitHub sert à relire les commentaires.
 */
export const githubTicketWebhook = onRequest(
  {
    region: REGION,
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    invoker: "public",
    secrets: [GITHUB_WEBHOOK_SECRET, GITHUB_TICKETS_TOKEN],
    maxInstances: 5,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (req, res) => {
    try {
      await handleGithubWebhook(req, res, {
        secret: () => GITHUB_WEBHOOK_SECRET.value(),
        token: () => GITHUB_TICKETS_TOKEN.value(),
      });
    } catch (err) {
      logError({ message: "githubTicketWebhook : échec imprévu", feature: "tickets", error: err });
      if (!res.headersSent) res.status(500).send("Erreur interne.");
    }
  },
);

/** « Répondre » à la dernière analyse (ADR-008, P30, P34). */
export const answerTicketAnalysis = onCall(
  {
    region: REGION,
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    cors: CALLABLE_ORIGINS,
    secrets: [GITHUB_TICKETS_TOKEN],
    maxInstances: 2,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  (req) => handleAnswerCall(req, () => GITHUB_TICKETS_TOKEN.value()),
);

/**
 * Réglages communs des lancements (ADR-008, T4, P25) : délai de 120 s (Issue relue, 15 s,
 * appel de la routine, 30 s, écritures), une instance chacun. La livraison porte 180 s.
 */
const LAUNCH_CALLABLE = {
  region: REGION,
  serviceAccount: RUNTIME_SERVICE_ACCOUNT,
  cors: CALLABLE_ORIGINS,
  maxInstances: 1,
  memory: "256MiB" as const,
  timeoutSeconds: 120,
};

/** « Lancer l'analyse » (ADR-008, T4, P35, P36). Seule à monter les secrets d'analyse. */
export const launchTicketAnalysis = onCall(
  {
    ...LAUNCH_CALLABLE,
    secrets: [GITHUB_TICKETS_TOKEN, TICKETS_ROUTINE_ANALYSIS_ID, TICKETS_ROUTINE_ANALYSIS_TOKEN],
  },
  (req) =>
    handleLaunchCall(req, "analyse", {
      routine: () => ({
        id: TICKETS_ROUTINE_ANALYSIS_ID.value(),
        token: TICKETS_ROUTINE_ANALYSIS_TOKEN.value(),
      }),
      githubToken: () => GITHUB_TICKETS_TOKEN.value(),
    }),
);

/** Identifiant et jeton de la routine de développement, lus à l'appel. */
function devRoutine(): { id: string; token: string } {
  return { id: TICKETS_ROUTINE_DEV_ID.value(), token: TICKETS_ROUTINE_DEV_TOKEN.value() };
}

/**
 * « Lancer le développement » et, avec `mode: "resume"`, « Relancer le développement »
 * (ADR-008, T4 et T5, P35, P36, P47). Monte les secrets de développement, comme
 * `launchTicketDelivery` seule.
 */
export const launchTicketDevelopment = onCall(
  {
    ...LAUNCH_CALLABLE,
    secrets: [GITHUB_TICKETS_TOKEN, TICKETS_ROUTINE_DEV_ID, TICKETS_ROUTINE_DEV_TOKEN],
  },
  (req) =>
    handleDevelopmentCall(req, {
      routine: devRoutine,
      githubToken: () => GITHUB_TICKETS_TOKEN.value(),
    }),
);

/**
 * « Livrer » (ADR-008, T5, P43, P44) : par la routine de développement (aucun secret
 * `TICKETS_ROUTINE_DELIVERY_*`). Délai de 180 s : PR, fichiers et runs relus sur GitHub
 * avant l'appel ; bail de 210 s (`DELIVERY_LEASE_MS`).
 */
export const launchTicketDelivery = onCall(
  {
    ...LAUNCH_CALLABLE,
    timeoutSeconds: 180,
    secrets: [GITHUB_TICKETS_TOKEN, TICKETS_ROUTINE_DEV_ID, TICKETS_ROUTINE_DEV_TOKEN],
  },
  (req) =>
    handleLaunchCall(req, "livraison", {
      routine: devRoutine,
      githubToken: () => GITHUB_TICKETS_TOKEN.value(),
    }),
);

/**
 * Capture d'écran jointe par l'auteur de son ticket (ADR-008, T6, P30). Aucun secret : la
 * fonction lit Firestore et le bucket par défaut avec le compte d'exécution.
 */
export const attachTicketScreenshot = onCall(
  {
    region: REGION,
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    cors: CALLABLE_ORIGINS,
    maxInstances: 2,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  (req) => handleScreenshotCall(req),
);

/**
 * Admin › Journaux (ADR-011, J2, P49) : lecture de la sortie des fonctions dans Cloud
 * Logging. Aucun secret ; jeton du compte d'exécution (`roles/logging.viewer`). Une
 * instance, une requête à la fois : le quota de `entries.list` est de 60 par minute.
 */
export const queryLogs = onCall(
  {
    region: REGION,
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    cors: CALLABLE_ORIGINS,
    maxInstances: 1,
    concurrency: 1,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  (req) => handleQueryLogsCall(req),
);
