/**
 * Cloud Functions de Kass'Beer (ADR-006). Deux fonctions, aucun point d'accès HTTP (P25) :
 *
 * - `publishTicket` : déclencheur de création de `tickets/{ticketId}`, publie l'Issue ;
 * - `syncTickets` : tâche horaire, renvoie les tickets `pending` et relit les Issues.
 *
 * Ce module ne construit aucun client (P26) : Firestore et GitHub s'ouvrent à l'appel.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { GITHUB_TICKETS_TOKEN, REGION, RUNTIME_SERVICE_ACCOUNT } from "./config";
import { logError } from "./logging";
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
