/**
 * Cloud Functions de Kass'Beer (ADR-006). Quatre fonctions, aucun point d'accès HTTP (P25) :
 *
 * - `publishTicket` : déclencheur de création de `tickets/{ticketId}`, publie l'Issue ;
 * - `onDecisionCreated` : déclencheur de création de
 *   `tickets/{ticketId}/decisions/{decisionId}`, applique la décision de l'admin (T2) ;
 * - `onDecisionUpdated` : déclencheur de mise à jour de la même décision, reprend une
 *   décision `failed` quand l'admin pose `retry_requested_at` (T2) ;
 * - `syncTickets` : tâche horaire, relance les envois demandés, renvoie les tickets
 *   `pending`, reprend les décisions au bail expiré et relit les Issues.
 *
 * Ce module ne construit aucun client (P26) : Firestore et GitHub s'ouvrent à l'appel.
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { GITHUB_TICKETS_TOKEN, REGION, RUNTIME_SERVICE_ACCOUNT } from "./config";
import { logError } from "./logging";
import { isRetryRequest } from "./tickets/decisionModel";
import { applyDecision } from "./tickets/decisions";
import { publishTicket as publish } from "./tickets/publish";
import { runHourlyPass } from "./tickets/sync";

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
    schedule: "every 60 minutes",
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
