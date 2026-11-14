/**
 * Callables des décisions de l'administrateur (ADR-008, lot T7, P53) : `validateTicket`,
 * `refuseTicket`, `closeTicket` et `retryTicketSend`. Copie de `ticketsCallable.ts` de
 * Kass'Dalle, adaptée au bail et à l'historique de Kass'Beer (`decisions.ts`).
 *
 * Chaque callable appelle `requireAdmin` (P30) avant de lire ses arguments : `ticketId`
 * (`readTicketIdArg`), puis `text` pour Refuser et Clore (taille brute, puis 5 à 4 000
 * caractères après nettoyage). Tout autre champ est ignoré. Le texte n'est jamais
 * journalisé (P53).
 *
 * `retryTicketSend` porte sur la publication de l'Issue d'un ticket `send_failed` (champs
 * `send_*` de `publish.ts`), pas sur une décision : remise à zéro en transaction, puis un
 * seul essai de `publishTicket` pendant l'appel.
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireAdmin, requireBoundedText, type AuthLike, type MemberLookup } from "../auth";
import { COLL_TICKETS } from "../config";
import { firestore } from "../firestore";
import { logError, logInfo } from "../logging";
import { readTicketIdArg } from "./answer";
import {
  DECISION_TEXT_RAW_MAX_CHARS,
  allowedDecisions,
  readDecisionText,
  type DecisionAction,
} from "./decisionModel";
import { decideTicket, type DecisionResult } from "./decisions";
import type { FetchLike } from "./github";
import { publishTicket } from "./publish";

/** Dépendances remplacées par les tests. */
export interface CallDeps {
  lookup?: MemberLookup;
  fetchImpl?: FetchLike;
}

export const DECISION_INTERNAL = "La décision n'a pas pu être appliquée. Réessayez.";
export const RETRY_SEND_INTERNAL = "L'envoi n'a pas pu être relancé. Réessayez.";
export const RETRY_SEND_TICKET_MISSING = "Ce ticket n'existe plus.";
export const RETRY_SEND_TOKEN =
  "GitHub refuse le jeton. L'envoi reprendra quand le jeton sera remplacé.";

/**
 * `text` de Refuser ou de Clore, lu et nettoyé. Lève `invalid-argument`
 * (`details.field = "text"`, `details.reason` en français). Pure.
 */
export function readDecisionTextArg(action: "refuse" | "close", data: unknown): string {
  const raw = (data as Record<string, unknown> | null | undefined)?.text;
  const value = requireBoundedText(raw, {
    field: "text",
    max: DECISION_TEXT_RAW_MAX_CHARS,
    required: true,
    label: action === "refuse" ? "Motif" : "Commentaire",
  });
  const read = readDecisionText(action, value);
  if (!read.ok) {
    throw new HttpsError("invalid-argument", read.reason, { field: "text", reason: read.reason });
  }
  return read.text;
}

/**
 * Corps de `validateTicket`, `refuseTicket` et `closeTicket`. Toute erreur hors
 * `HttpsError` est journalisée et rendue en `internal`.
 */
export async function handleDecisionCall(
  req: AuthLike & { data?: unknown },
  action: DecisionAction,
  token: () => string,
  deps: CallDeps = {},
): Promise<DecisionResult> {
  const admin = await requireAdmin(req, deps.lookup);
  const ticketId = readTicketIdArg(req.data);
  const text = action === "validate" ? null : readDecisionTextArg(action, req.data);
  try {
    return await decideTicket(ticketId, action, text, admin.uid, token(), deps.fetchImpl);
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logError({
      message: "Tickets : décision non appliquée",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { action },
    });
    throw new HttpsError("internal", DECISION_INTERNAL, {
      reason: DECISION_INTERNAL,
      code: "internal",
    });
  }
}

/** Réponse de `retryTicketSend` : statut lu après l'essai, Issue si publiée. */
export interface RetrySendResult {
  status: string;
  changed: boolean;
  issueNumber: number | null;
}

/**
 * Relance l'envoi du ticket `ticketId`. Ticket `send_failed` sans Issue : `pending`,
 * `send_attempts` à 0, `send_retried_at` posé (la publication cherche d'abord une Issue
 * déjà créée), `retry_requested_at` retiré (valeur laissée par le client d'avant T7), puis
 * un seul `publishTicket`. Autre statut : rien n'est écrit, `changed: false` (relance déjà
 * faite ailleurs). `status_changed_at` ne change pas : la pastille du membre ne s'allume pas.
 */
export async function retryTicketSend(
  ticketId: string,
  token: string,
  fetchImpl?: FetchLike,
): Promise<RetrySendResult> {
  const { db, FieldValue, Timestamp } = await firestore();
  const ref = db.collection(COLL_TICKETS).doc(ticketId);
  const issueOf = (value: unknown): number | null =>
    typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : null;
  const reset = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", RETRY_SEND_TICKET_MISSING, {
        reason: RETRY_SEND_TICKET_MISSING,
        code: "ticket_missing",
      });
    }
    const status = String(snap.get("status"));
    const issueNumber = issueOf(snap.get("github_issue_number"));
    if (status !== "send_failed" || issueNumber !== null) {
      return { status, changed: false, issueNumber };
    }
    const now = Timestamp.now();
    tx.update(ref, {
      status: "pending",
      allowed_decisions: allowedDecisions("pending"),
      send_attempts: 0,
      send_retried_at: now,
      retry_requested_at: FieldValue.delete(),
      send_lease_until: FieldValue.delete(),
      updated_at: now,
    });
    return null;
  });
  if (reset !== null) return reset;

  logInfo({
    message: "Tickets : relance d'envoi demandée par l'admin",
    feature: "tickets",
    ticketId,
  });
  const outcome = await publishTicket(ticketId, token, fetchImpl);
  if (outcome === "token") {
    throw new HttpsError("failed-precondition", RETRY_SEND_TOKEN, {
      reason: RETRY_SEND_TOKEN,
      code: "github_token",
    });
  }
  const after = await ref.get();
  return {
    status: String(after.get("status")),
    changed: true,
    issueNumber: issueOf(after.get("github_issue_number")),
  };
}

/** Corps de `retryTicketSend`. Toute erreur hors `HttpsError` est journalisée. */
export async function handleRetrySendCall(
  req: AuthLike & { data?: unknown },
  token: () => string,
  deps: CallDeps = {},
): Promise<RetrySendResult> {
  await requireAdmin(req, deps.lookup);
  const ticketId = readTicketIdArg(req.data);
  try {
    return await retryTicketSend(ticketId, token(), deps.fetchImpl);
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logError({
      message: "Tickets : relance d'envoi non faite",
      feature: "tickets",
      ticketId,
      error: err,
    });
    throw new HttpsError("internal", RETRY_SEND_INTERNAL, {
      reason: RETRY_SEND_INTERNAL,
      code: "internal",
    });
  }
}
