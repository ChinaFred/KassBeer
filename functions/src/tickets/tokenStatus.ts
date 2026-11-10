/**
 * `ticket_status/github` : état du jeton, écrit par le serveur seul et lu par
 * l'administrateur (bandeau de la page Admin). Champs :
 *
 * - `token_invalid_since` : date du premier refus (401, 403 hors limite de débit, 404 sur
 *   le dépôt, secret vide), `null` après le premier appel réussi ;
 * - `token_invalid_reason` : code court (`secret_vide`, `http_401`…), jamais le jeton ;
 * - `token_expires_at` : date de l'en-tête `github-authentication-token-expiration`,
 *   `null` quand la dernière réponse réussie ne le portait pas ;
 * - `token_checked_at` : date de la dernière réponse réussie qui a écrit ce document.
 *
 * `issues_cursor`, curseur de la passe horaire, est écrit par `sync.ts`.
 *
 * Chaque écriture est journalisée en cas d'échec et ne lève pas : l'état du jeton ne
 * bloque ni la publication ni la passe.
 */

import { COLL_TICKET_STATUS, TICKET_STATUS_GITHUB_DOC } from "../config";
import { firestore } from "../firestore";
import { logError, logInfo } from "../logging";
import type { GithubClient, GithubError } from "./github";
import { parseTokenExpiration } from "./model";

async function statusRef() {
  const { db } = await firestore();
  return db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_GITHUB_DOC);
}

/** Code court d'un refus du jeton. Pure. */
export function tokenInvalidReason(error: GithubError | null): string {
  if (error === null) return "secret_vide";
  return error.status === null ? "jeton_refuse" : `http_${error.status}`;
}

/** Pose `token_invalid_since` s'il ne l'est pas déjà. */
export async function markTokenInvalid(error: GithubError | null): Promise<void> {
  const reason = tokenInvalidReason(error);
  logError({
    message: "Tickets : jeton GitHub refusé ou absent",
    feature: "tickets",
    error: error ?? undefined,
    extra: { reason },
  });
  try {
    const { db, Timestamp } = await firestore();
    const ref = await statusRef();
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.get("token_invalid_since") instanceof Timestamp) return;
      tx.set(
        ref,
        { token_invalid_since: Timestamp.now(), token_invalid_reason: reason },
        { merge: true },
      );
    });
  } catch (err) {
    logError({
      message: "Tickets : état du jeton GitHub non enregistré",
      feature: "tickets",
      error: err,
    });
  }
}

/**
 * Après une réponse réussie : efface `token_invalid_since` et écrit l'échéance du jeton,
 * seulement si l'une des deux valeurs change (une écriture par changement).
 */
export async function recordTokenAccepted(client: GithubClient): Promise<void> {
  const header = client.tokenExpirationHeader;
  if (header === undefined) return;
  try {
    const { Timestamp } = await firestore();
    const ref = await statusRef();
    const snap = await ref.get();
    const expires = parseTokenExpiration(header);
    if (header !== null && expires === null) {
      logError({
        message: "Tickets : en-tête d'expiration du jeton GitHub illisible",
        feature: "tickets",
        extra: { header: header.slice(0, 60) },
      });
    }
    const stored = snap.get("token_expires_at");
    const storedMs = stored instanceof Timestamp ? stored.toMillis() : null;
    const wantedMs = expires === null ? null : expires.getTime();
    const wasInvalid = snap.get("token_invalid_since") != null;
    const knownExpiry = snap.exists && "token_expires_at" in (snap.data() ?? {});
    if (!wasInvalid && knownExpiry && storedMs === wantedMs) return;
    await ref.set(
      {
        token_invalid_since: null,
        token_invalid_reason: null,
        token_expires_at: expires === null ? null : Timestamp.fromDate(expires),
        token_checked_at: Timestamp.now(),
      },
      { merge: true },
    );
    if (wasInvalid)
      logInfo({ message: "Tickets : jeton GitHub de nouveau accepté", feature: "tickets" });
  } catch (err) {
    logError({
      message: "Tickets : état du jeton GitHub non enregistré",
      feature: "tickets",
      error: err,
    });
  }
}
