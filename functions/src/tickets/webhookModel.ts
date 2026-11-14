/**
 * Règles pures du webhook GitHub des tickets (ADR-008, T3, P29), reprises de Kass'Dalle
 * (`functions/src/tickets/webhook.ts` et `rules.ts`). Aucune lecture ni écriture ici.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

import {
  CI_WORKFLOW_NAME,
  CI_WORKFLOW_PATH,
  DELIVERY_EVENT_MAX,
  isDeliveryCandidatePr,
} from "./delivery";
import { readIssue, readPullRequest } from "./github";
import { LABEL_VALIDATED, closingIssueNumbers, type IssueView } from "./model";

/** Plafond d'une livraison GitHub : au-delà, le corps est refusé avant le HMAC. */
export const WEBHOOK_MAX_BODY_BYTES = 25 * 1024 * 1024;

/** Événements traités : ceux de T3, et `pull_request` et `workflow_run` depuis T5 (P29). */
export const WEBHOOK_EVENTS = new Set([
  "ping",
  "issues",
  "issue_comment",
  "pull_request",
  "workflow_run",
]);

/** Actions d'une PR qui changent son état « PR prête » (corps, brouillon, tête, fermeture). */
const DELIVERY_PR_ACTIONS = new Set([
  "opened",
  "reopened",
  "edited",
  "ready_for_review",
  "converted_to_draft",
  "synchronize",
  "closed",
]);

/** Actions d'un `workflow_run` qui relisent la livraison : départ, exécution, fin. */
const DELIVERY_RUN_ACTIONS = new Set(["requested", "in_progress", "completed"]);

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

/**
 * Vrai si un côté (`base` ou `head`) d'une PR portée par `workflow_run.pull_requests` est dans
 * ce dépôt. GitHub y donne `repo` sous la forme `{ id, url, name }` : l'adresse d'API
 * `https://api.github.com/repos/<dépôt>` est comparée, casse ignorée ; `full_name`, s'il est
 * présent, aussi. Pure.
 */
export function isOwnRunPrSide(side: unknown, repoFullName: string): boolean {
  if (side === null || typeof side !== "object") return false;
  const repo = (side as { repo?: unknown }).repo as
    { url?: unknown; full_name?: unknown } | null | undefined;
  if (repo === null || typeof repo !== "object") return false;
  const want = repoFullName.toLowerCase();
  if (typeof repo.full_name === "string") return repo.full_name.toLowerCase() === want;
  return (
    typeof repo.url === "string" &&
    repo.url.toLowerCase() === `https://api.github.com/repos/${want}`
  );
}

/**
 * Ce qu'un événement demande de relire pour « Livrer » (P29, P46), ou `null` :
 *
 * - `pull_request` d'une PR candidate (`isDeliveryCandidatePr` : tête dans ce dépôt, auteur
 *   `maintainerId`) : les Issues citées par un mot-clé de fermeture dans le corps, et dans
 *   l'ancien corps d'un `edited` (un renvoi retiré rend la PR inéligible pour cette Issue),
 *   `DELIVERY_EVENT_MAX` au plus. Le corps n'est lu que pour ces numéros ;
 * - `workflow_run` du seul workflow `.github/workflows/ci.yml` (chemin et nom) : les PR de ce
 *   dépôt qu'il porte (`pull_requests` dont base et tête sont dans ce dépôt,
 *   `isOwnRunPrSide`), `DELIVERY_EVENT_MAX` au plus ; l'appelant relit chaque PR et ses runs, jamais la liste des PR ouvertes.
 *
 * Un autre dépôt, un autre workflow (« Déploiement ») ou une autre action : `null`, sans
 * appel à GitHub. Pure.
 */
export function deliveryRefreshFromEvent(
  event: string,
  payload: Payload,
  repoFullName: string,
): { issueNumbers: number[]; prNumbers: number[] } | null {
  if (!isOwnRepository(payload, repoFullName)) return null;
  const action = typeof payload.action === "string" ? payload.action : "";
  if (event === "pull_request" && DELIVERY_PR_ACTIONS.has(action)) {
    const raw = payload.pull_request as Payload | null | undefined;
    if (raw === null || typeof raw !== "object") return null;
    const pr = readPullRequest(raw);
    if (!isDeliveryCandidatePr(pr)) return null;
    const changes = payload.changes as { body?: { from?: unknown } } | null | undefined;
    const bodies = [raw.body, changes?.body?.from].filter(
      (b): b is string => typeof b === "string",
    );
    const issues = new Set<number>();
    for (const body of bodies) {
      for (const n of closingIssueNumbers(body, repoFullName)) issues.add(n);
    }
    if (issues.size === 0) return null;
    return {
      issueNumbers: [...issues].sort((a, b) => a - b).slice(0, DELIVERY_EVENT_MAX),
      prNumbers: [],
    };
  }
  if (event === "workflow_run" && DELIVERY_RUN_ACTIONS.has(action)) {
    const run = payload.workflow_run as Payload | null | undefined;
    if (run === null || typeof run !== "object") return null;
    if (run.path !== CI_WORKFLOW_PATH || run.name !== CI_WORKFLOW_NAME) return null;
    if (!Array.isArray(run.pull_requests)) return null;
    const prs = new Set<number>();
    for (const item of run.pull_requests) {
      const pr = item as { number?: unknown; base?: unknown; head?: unknown } | null;
      // Base et tête dans ce dépôt, sinon ignorée sans appel à GitHub (P29).
      if (!isOwnRunPrSide(pr?.base, repoFullName) || !isOwnRunPrSide(pr?.head, repoFullName)) {
        continue;
      }
      const n = pr?.number;
      if (typeof n === "number" && Number.isSafeInteger(n) && n > 0) prs.add(n);
    }
    if (prs.size === 0) return null;
    return {
      issueNumbers: [],
      prNumbers: [...prs].sort((a, b) => a - b).slice(0, DELIVERY_EVENT_MAX),
    };
  }
  return null;
}
