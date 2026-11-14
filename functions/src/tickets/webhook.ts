/**
 * `githubTicketWebhook` (ADR-008, T3 et T5, P29) : état des Issues, des PR et de la CI
 * poussé par GitHub. Copie de Kass'Dalle (`functions/src/tickets/webhook.ts`).
 *
 * Fonction HTTPS publique (`invoker: "public"`) : GitHub ne présente pas de jeton Google.
 * L'authentification est la signature `X-Hub-Signature-256`, HMAC SHA-256 du corps brut
 * sous `GITHUB_WEBHOOK_SECRET`, vérifiée avant toute lecture du corps. Dans l'ordre :
 * méthode autre que `POST` : 405 ; corps de plus de 25 Mo : 413 ; `X-GitHub-Event`
 * absent : 400 ; secret vide : 503 ; signature absente ou fausse : 401 ; `ping` : 200 ;
 * autre événement : 200, ignoré ; corps illisible : 400 ; autre dépôt, PR, Issue sans
 * ticket, commentaire d'un autre compte que 16348852 : 200, ignoré ; panne Firestore ou
 * GitHub : 500 (GitHub affiche la livraison en échec, la tâche horaire rattrape).
 *
 * Les refus de signature et de secret sont journalisés une fois par minute et par instance
 * au plus, avec leur nombre. Ni la signature, ni le secret, ni le corps ne sont journalisés.
 *
 * Effet : statut du ticket dérivé des étiquettes seules, réponse « Réponse : », analyses,
 * précisions et comptes rendus de livraison relus (`applyIssue`), `validated_at` quand le
 * compte propriétaire pose `validé`. T5 (P29, P46) : `pull_request` d'une PR du compte
 * 16348852 dans ce dépôt et `workflow_run` de `ci.yml` relisent l'état « PR prête » des
 * tickets `in_progress` dont l'Issue est fermée par la PR (`admin/delivery`), cinq au plus ;
 * une PR ouverte ne change pas le statut (décision de l'utilisateur du 2026-11-14). Relire
 * GitHub demande le jeton `GITHUB_TICKETS_TOKEN`, monté aussi.
 */

import { GITHUB_MAINTAINER_ID, GITHUB_REPO_FULL_NAME, COLL_TICKETS } from "../config";
import { firestore } from "../firestore";
import { LogSampler } from "../logSampler";
import { logError, logInfo, logWarn } from "../logging";
import { recordValidatedAt } from "./analyses";
import {
  DELIVERY_EVENT_MAX,
  refreshDeliveryFromRun,
  refreshTicketDelivery,
  type OpenPullRequests,
} from "./delivery";
import { GithubError, githubClient, type FetchLike } from "./github";
import { applyIssue } from "./issueState";
import {
  WEBHOOK_EVENTS,
  WEBHOOK_MAX_BODY_BYTES,
  deliveryRefreshFromEvent,
  verifyGithubSignature,
  webhookAction,
} from "./webhookModel";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

/** Ce que le gestionnaire lit de la requête (sous-ensemble de la requête Express). */
export interface WebhookRequest {
  method: string;
  rawBody?: Buffer;
  get(name: string): string | undefined;
}

/** Ce que le gestionnaire écrit dans la réponse. */
export interface WebhookResponse {
  status(code: number): { send(body: string): unknown };
}

export type WebhookAction = NonNullable<ReturnType<typeof webhookAction>>;
export type DeliveryRefresh = NonNullable<ReturnType<typeof deliveryRefreshFromEvent>>;

export interface WebhookDeps {
  secret: () => string;
  token: () => string;
  fetchImpl?: FetchLike;
  /** Application d'un événement retenu ; remplacée par les tests. Rend les tickets touchés. */
  apply?: (action: WebhookAction, token: string, fetchImpl?: FetchLike) => Promise<number>;
  /** Relecture de livraison d'un événement retenu ; remplacée par les tests. */
  applyDelivery?: (
    refresh: DeliveryRefresh,
    token: string,
    fetchImpl?: FetchLike,
  ) => Promise<number>;
}

/** Refus de signature, échantillonnés : un relevé par minute et par instance au plus. */
const signatureRejections = new LogSampler();
/** Même échantillonnage pour les livraisons refusées faute de secret. */
const missingSecretRejections = new LogSampler();

class MissingToken extends Error {
  constructor() {
    super("jeton GitHub absent (secret GITHUB_TICKETS_TOKEN vide)");
  }
}

/**
 * Applique un événement retenu aux tickets de son Issue (zéro ou un). Lève en cas d'échec ;
 * le gestionnaire journalise et rend 500.
 */
export async function applyWebhookAction(
  action: WebhookAction,
  token: string,
  fetchImpl?: FetchLike,
): Promise<number> {
  const { db } = await firestore();
  const snap = await db
    .collection(COLL_TICKETS)
    .where("github_issue_number", "==", action.issue.number)
    .limit(2)
    .get();
  if (snap.empty) return 0;
  const trimmed = token.trim();
  if (trimmed.length === 0) throw new MissingToken();
  const client = githubClient(trimmed, fetchImpl);
  for (const doc of snap.docs) {
    await applyIssue(client, doc, action.issue, { forceComments: action.forceComments });
    if (action.validatedLabel) {
      const ms = action.issue.updatedAt === null ? Number.NaN : Date.parse(action.issue.updatedAt);
      await recordValidatedAt(doc.id, Number.isNaN(ms) ? Date.now() : ms);
    }
  }
  await recordTokenAccepted(client);
  return snap.size;
}

/**
 * Relit l'état « PR prête » (P46) : `pull_request`, tickets `in_progress` des Issues citées,
 * liste des PR ouvertes lue une fois pour l'événement ; `workflow_run`, chaque PR et les runs
 * de sa tête, sans la liste. Rend le nombre de tickets réécrits. Lève en cas d'échec.
 */
export async function applyDeliveryRefresh(
  refresh: DeliveryRefresh,
  token: string,
  fetchImpl?: FetchLike,
): Promise<number> {
  const kit = await firestore();
  const trimmed = token.trim();
  if (trimmed.length === 0) throw new MissingToken();
  const client = githubClient(trimmed, fetchImpl);
  let count = 0;
  for (const prNumber of refresh.prNumbers.slice(0, DELIVERY_EVENT_MAX)) {
    count += await refreshDeliveryFromRun(kit, client, prNumber);
  }
  let openPrs: OpenPullRequests | null = null;
  for (const issueNumber of refresh.issueNumbers.slice(0, DELIVERY_EVENT_MAX)) {
    const snap = await kit.db
      .collection(COLL_TICKETS)
      .where("github_issue_number", "==", issueNumber)
      .limit(2)
      .get();
    for (const doc of snap.docs) {
      if (doc.get("status") !== "in_progress") continue;
      openPrs ??= await client.listOpenPullRequests();
      if ((await refreshTicketDelivery(kit, client, doc.id, issueNumber, openPrs)) !== null) {
        count++;
      }
    }
  }
  await recordTokenAccepted(client);
  return count;
}

/** Gestionnaire du webhook. Ne lève pas : chaque issue est une réponse HTTP. */
export async function handleGithubWebhook(
  req: WebhookRequest,
  res: WebhookResponse,
  deps: WebhookDeps,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).send("Méthode non admise.");
    return;
  }
  const rawBody: Buffer = req.rawBody ?? Buffer.alloc(0);
  const declared = Number(req.get("content-length") ?? 0);
  if (
    rawBody.length > WEBHOOK_MAX_BODY_BYTES ||
    (Number.isFinite(declared) && declared > WEBHOOK_MAX_BODY_BYTES)
  ) {
    res.status(413).send("Corps trop volumineux.");
    return;
  }
  const event = req.get("x-github-event") ?? "";
  if (event.length === 0) {
    res.status(400).send("En-tête X-GitHub-Event absent.");
    return;
  }

  const secret = deps.secret().trim();
  if (secret.length === 0) {
    const refused = missingSecretRejections.record(Date.now());
    if (refused !== null) {
      logError({
        message: `githubTicketWebhook : secret GITHUB_WEBHOOK_SECRET vide, ${refused} livraison(s) refusée(s) depuis le dernier relevé`,
        feature: "tickets",
      });
    }
    res.status(503).send("Webhook non configuré.");
    return;
  }

  const signature = req.get("x-hub-signature-256");
  if (!verifyGithubSignature(rawBody, signature, secret)) {
    const rejected = signatureRejections.record(Date.now());
    if (rejected !== null) {
      logWarn({
        message: `githubTicketWebhook : ${rejected} livraison(s) refusée(s) pour signature absente ou invalide depuis le dernier relevé`,
        feature: "tickets",
        extra: { has_signature: typeof signature === "string", rejected },
      });
    }
    res.status(401).send("Signature invalide.");
    return;
  }

  if (event === "ping") {
    res.status(200).send("pong");
    return;
  }
  if (!WEBHOOK_EVENTS.has(event)) {
    res.status(200).send("ignoré");
    return;
  }

  const delivery = (req.get("x-github-delivery") ?? "").slice(0, 64);
  let payload: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(rawBody.toString("utf8"));
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("charge JSON qui n'est pas un objet");
    }
    payload = parsed as Record<string, unknown>;
  } catch (err) {
    logError({
      message: "githubTicketWebhook : corps JSON illisible",
      feature: "tickets",
      error: err instanceof Error ? err.name : "erreur",
      extra: { event, delivery },
    });
    res.status(400).send("Corps illisible.");
    return;
  }

  const action = webhookAction(event, payload, GITHUB_REPO_FULL_NAME, GITHUB_MAINTAINER_ID);
  if (action === null) {
    const refresh = deliveryRefreshFromEvent(event, payload, GITHUB_REPO_FULL_NAME);
    if (refresh === null) {
      res.status(200).send("ignoré");
      return;
    }
    await handleDeliveryRefresh(refresh, event, delivery, res, deps);
    return;
  }

  try {
    const apply = deps.apply ?? applyWebhookAction;
    const count = await apply(action, deps.token(), deps.fetchImpl);
    if (count > 0) {
      logInfo({
        message: `githubTicketWebhook : Issue #${action.issue.number} appliquée (${event})`,
        feature: "tickets",
        extra: { delivery, tickets: count },
      });
    }
    res.status(200).send(count > 0 ? `ok (${count})` : "ignoré");
  } catch (err) {
    const kind =
      err instanceof MissingToken ? "token" : err instanceof GithubError ? err.kind : "other";
    logError({
      message: `githubTicketWebhook : événement ${event} non appliqué (Issue #${action.issue.number})`,
      feature: "tickets",
      error: err,
      extra: { delivery, kind },
    });
    if (err instanceof MissingToken) await markTokenInvalid(null);
    else if (err instanceof GithubError && err.kind === "token") await markTokenInvalid(err);
    res.status(500).send("Erreur interne.");
  }
}

/** `pull_request` ou `workflow_run` retenu : relecture de livraison. Ne lève pas. */
async function handleDeliveryRefresh(
  refresh: DeliveryRefresh,
  event: string,
  delivery: string,
  res: WebhookResponse,
  deps: WebhookDeps,
): Promise<void> {
  try {
    const count = await (deps.applyDelivery ?? applyDeliveryRefresh)(
      refresh,
      deps.token(),
      deps.fetchImpl,
    );
    if (count > 0) {
      logInfo({
        message: `githubTicketWebhook : état « PR prête » relu (${event})`,
        feature: "tickets",
        extra: { delivery, tickets: count },
      });
    }
    res.status(200).send(count > 0 ? `ok (${count})` : "ignoré");
  } catch (err) {
    const kind =
      err instanceof MissingToken ? "token" : err instanceof GithubError ? err.kind : "other";
    logError({
      message: `githubTicketWebhook : état « PR prête » non relu (${event})`,
      feature: "tickets",
      error: err,
      extra: { delivery, kind },
    });
    if (err instanceof MissingToken) await markTokenInvalid(null);
    else if (err instanceof GithubError && err.kind === "token") await markTokenInvalid(err);
    res.status(500).send("Erreur interne.");
  }
}
