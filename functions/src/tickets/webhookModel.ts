/**
 * Règles pures du webhook GitHub des tickets (ADR-008, T3, P29), reprises de Kass'Dalle
 * (`functions/src/tickets/webhook.ts` et `rules.ts`). Aucune lecture ni écriture ici.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

import { readIssue } from "./github";
import { LABEL_VALIDATED, type IssueView } from "./model";

/** Plafond d'une livraison GitHub : au-delà, le corps est refusé avant le HMAC. */
export const WEBHOOK_MAX_BODY_BYTES = 25 * 1024 * 1024;

/** Événements traités à T3 ; `pull_request` et `workflow_run` arrivent à T5. */
export const WEBHOOK_EVENTS = new Set(["ping", "issues", "issue_comment"]);

const ISSUE_ACTIONS = new Set(["opened", "edited", "labeled", "unlabeled", "closed", "reopened"]);
const COMMENT_ACTIONS = new Set(["created", "edited", "deleted"]);

/**
 * Vrai si `signatureHeader` (`X-Hub-Signature-256`, `sha256=<hex>`) est le HMAC SHA-256 de
 * `rawBody` sous `secret`. Longueurs comparées avant `timingSafeEqual`, qui lève sur deux
 * tampons de tailles différentes. Secret vide, en-tête absent ou mal formé : `false`. Pure.
 */
export function verifyGithubSignature(
  rawBody: Buffer,
  signatureHeader: string | null | undefined,
  secret: string,
): boolean {
  if (secret.length === 0 || typeof signatureHeader !== "string") return false;
  const match = /^sha256=([0-9a-f]+)$/i.exec(signatureHeader.trim());
  if (match === null || match[1].length % 2 !== 0) return false;
  const expected = createHmac("sha256", secret).update(rawBody).digest();
  const received = Buffer.from(match[1], "hex");
  if (received.length !== expected.length) return false;
  return timingSafeEqual(received, expected);
}

type Payload = Record<string, unknown>;

/** Vrai si l'événement vient de ce dépôt (`repository.full_name`, casse ignorée). Pure. */
export function isOwnRepository(payload: Payload, repoFullName: string): boolean {
  const repo = (payload.repository as { full_name?: unknown } | null | undefined)?.full_name;
  return typeof repo === "string" && repo.toLowerCase() === repoFullName.toLowerCase();
}

/**
 * Ce qu'un événement demande, ou `null` s'il est ignoré :
 * - `issues` (ouverture, modification, étiquettes, fermeture, réouverture) : l'état de
 *   l'Issue lu dans la charge ; `validatedLabel` quand le compte `maintainerId` (expéditeur)
 *   pose `validé` (la date est `issue.updated_at`, à défaut l'heure de réception) ;
 * - `issue_comment` (création, modification, suppression) d'un commentaire du compte
 *   `maintainerId` (identifiant numérique) sur une Issue : relevé forcé des commentaires.
 *   Tout autre auteur est ignoré.
 * Une PR, un autre dépôt ou une autre action : `null`. Aucun texte n'est interprété : le
 * ticket se retrouve par le numéro d'Issue écrit par le serveur. Pure.
 */
export function webhookAction(
  event: string,
  payload: Payload,
  repoFullName: string,
  maintainerId: number,
): { issue: IssueView; forceComments: boolean; validatedLabel: boolean } | null {
  if (!isOwnRepository(payload, repoFullName)) return null;
  const action = typeof payload.action === "string" ? payload.action : "";
  const rawIssue = payload.issue as Payload | null | undefined;
  if (rawIssue === null || typeof rawIssue !== "object") return null;
  const issue = readIssue(rawIssue);
  if (issue === null || issue.isPullRequest) return null;

  if (event === "issues" && ISSUE_ACTIONS.has(action)) {
    const label = payload.label as { name?: unknown } | null | undefined;
    const sender = payload.sender as { id?: unknown } | null | undefined;
    const validatedLabel =
      action === "labeled" && label?.name === LABEL_VALIDATED && sender?.id === maintainerId;
    return { issue, forceComments: false, validatedLabel };
  }

  if (event === "issue_comment" && COMMENT_ACTIONS.has(action)) {
    const comment = payload.comment as Payload | null | undefined;
    const user = comment?.user as { id?: unknown } | null | undefined;
    if (user?.id !== maintainerId) return null;
    return { issue, forceComments: true, validatedLabel: false };
  }
  return null;
}
