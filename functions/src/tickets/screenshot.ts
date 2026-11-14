/**
 * Capture d'écran jointe à un ticket (`attachTicketScreenshot`, ADR-008, T6, P30). Copie de
 * `attachTicketScreenshot` de Kass'Dalle (`functions/src/callable/ticketsCallable.ts`).
 *
 * Le client crée le ticket dans Firestore, dépose l'image dans
 * `tickets/{uid}/{ticketId}/screenshot.png` sous `storage.rules` (création seule), puis
 * appelle cette callable. Elle vérifie, dans l'ordre :
 *
 * 1. `requireMember` (P30), avant toute lecture des arguments ;
 * 2. `ticketId` et `path` bornés en taille brute (`requireBoundedText`), `path` égal au
 *    chemin de l'appelant pour ce ticket ;
 * 3. le ticket existe et son `author_uid` est l'appelant ;
 * 4. le fichier existe, son type annoncé est `image/png`, sa taille va de 1 octet à 5 Mo, et
 *    ses premiers octets sont ceux d'un PNG ;
 *
 * puis écrit `screenshot_path` sur le ticket. La capture ne part jamais sur GitHub. Ni son
 * contenu, ni son chemin, ni le message ou la pile d'une erreur de Cloud Storage (qui
 * portent le chemin) ne sont journalisés : le code de l'erreur seul (2026-11-14).
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireBoundedText, requireMember, type AuthLike, type MemberLookup } from "../auth";
import { COLL_TICKETS } from "../config";
import { firestore, type FirestoreKit } from "../firestore";
import { logError, type LogEntry } from "../logging";
import { storageScreenshotStore, type ScreenshotStore } from "../storage";
import { readTicketIdArg } from "./answer";

/** Taille maximale d'une capture, comme `storage.rules`. */
export const SCREENSHOT_MAX_BYTES = 5 * 1024 * 1024;

/** Octets lus en tête d'une capture pour en vérifier la signature. */
export const SCREENSHOT_SIGNATURE_BYTES = 8;

/** Longueur brute maximale de `path` avant toute lecture. */
export const SCREENSHOT_PATH_MAX_CHARS = 300;

/** Seul type admis : le client ne produit que des PNG (ADR-008, note du 2026-11-14). */
export const SCREENSHOT_CONTENT_TYPE = "image/png";

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** Le seul chemin admis pour la capture du ticket `ticketId` de `uid`. Pure. */
export function screenshotPath(uid: string, ticketId: string): string {
  return `tickets/${uid}/${ticketId}/screenshot.png`;
}

/**
 * Vrai si les premiers octets sont la signature PNG sur 8 octets. Le type annoncé par le
 * client ne prouve rien sur le contenu. Pure.
 */
export function screenshotBytesMatch(head: Uint8Array): boolean {
  if (head.length < PNG_SIGNATURE.length) return false;
  return PNG_SIGNATURE.every((byte, i) => head[i] === byte);
}

/**
 * Code d'une erreur de Cloud Storage ou de Firestore, seul élément journalisé : nombre
 * (statut HTTP) ou texte court sans `/` ; sinon le nom de la classe, sinon `inconnu`. Le
 * message et la pile portent le chemin du fichier. Pure.
 */
export function storageErrorCode(err: unknown): string {
  const code = (err as { code?: unknown } | null | undefined)?.code;
  if (typeof code === "number" && Number.isInteger(code)) return String(code);
  if (typeof code === "string" && /^[A-Za-z0-9_.-]{1,40}$/.test(code)) return code;
  if (err instanceof Error && /^[A-Za-z0-9_]{1,40}$/.test(err.name)) return err.name;
  return "inconnu";
}

export const SCREENSHOT_PATH_INVALID = "Chemin de capture invalide.";
export const SCREENSHOT_TICKET_MISSING = "Ce ticket n'existe plus.";
export const SCREENSHOT_NOT_AUTHOR = "Ce ticket ne vous appartient pas.";
export const SCREENSHOT_FILE_MISSING = "La capture n'a pas été trouvée.";
export const SCREENSHOT_FILE_REFUSED = "Seules les images PNG de 5 Mo au plus sont acceptées.";
export const SCREENSHOT_INTERNAL = "La capture n'a pas pu être jointe. Réessayez.";

function refusal(
  code: "invalid-argument" | "not-found" | "permission-denied" | "internal",
  reason: string,
  machine: string,
  field?: string,
): HttpsError {
  return new HttpsError(code, reason, {
    reason,
    code: machine,
    ...(field === undefined ? {} : { field }),
  });
}

/**
 * `path` d'une requête : texte borné, égal au chemin de [uid] pour [ticketId].
 * Lève `invalid-argument` (`details.field = "path"`). Pure.
 */
export function readScreenshotPathArg(data: unknown, uid: string, ticketId: string): string {
  const raw = (data as Record<string, unknown> | null | undefined)?.path;
  const value = requireBoundedText(raw, {
    field: "path",
    max: SCREENSHOT_PATH_MAX_CHARS,
    required: true,
    label: "Chemin de la capture",
  });
  if (value !== screenshotPath(uid, ticketId)) {
    throw refusal("invalid-argument", SCREENSHOT_PATH_INVALID, "path_invalid", "path");
  }
  return value;
}

export interface ScreenshotDeps {
  lookup?: MemberLookup;
  kit?: () => Promise<FirestoreKit>;
  store?: ScreenshotStore;
  /** Journal des erreurs, remplacé dans les tests. */
  log?: (entry: LogEntry) => void;
}

/** Vérifie la capture déposée et écrit `screenshot_path` (étapes 3 et 4). */
export async function attachScreenshot(
  uid: string,
  ticketId: string,
  path: string,
  deps: ScreenshotDeps = {},
): Promise<void> {
  const kit = await (deps.kit ?? firestore)();
  const store = deps.store ?? storageScreenshotStore;
  const ref = kit.db.collection(COLL_TICKETS).doc(ticketId);
  const snap = await ref.get();
  if (!snap.exists) throw refusal("not-found", SCREENSHOT_TICKET_MISSING, "ticket_missing");
  if (snap.data()?.author_uid !== uid) {
    throw refusal("permission-denied", SCREENSHOT_NOT_AUTHOR, "not_author");
  }

  const file = await store.stat(path);
  if (!file.exists) throw refusal("not-found", SCREENSHOT_FILE_MISSING, "file_missing");
  if (
    file.contentType !== SCREENSHOT_CONTENT_TYPE ||
    !(file.size > 0 && file.size <= SCREENSHOT_MAX_BYTES)
  ) {
    throw refusal("invalid-argument", SCREENSHOT_FILE_REFUSED, "file_refused");
  }
  const head = await store.head(path, SCREENSHOT_SIGNATURE_BYTES);
  if (!screenshotBytesMatch(head)) {
    throw refusal("invalid-argument", SCREENSHOT_FILE_REFUSED, "file_refused");
  }

  await ref.update({
    screenshot_path: path,
    updated_at: kit.FieldValue.serverTimestamp(),
  });
}

/** Corps de `attachTicketScreenshot`. */
export async function handleScreenshotCall(
  req: AuthLike & { data?: unknown },
  deps: ScreenshotDeps = {},
): Promise<{ ok: true }> {
  const { uid } = await requireMember(req, deps.lookup);
  const ticketId = readTicketIdArg(req.data);
  const path = readScreenshotPathArg(req.data, uid, ticketId);
  try {
    await attachScreenshot(uid, ticketId, path, deps);
    return { ok: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    // Ni le chemin, ni le contenu, ni le message ou la pile de l'erreur, qui portent le
    // chemin : l'identifiant du ticket et le code suffisent.
    (deps.log ?? logError)({
      message: "Tickets : capture non jointe",
      feature: "tickets",
      ticketId,
      extra: { errorCode: storageErrorCode(err) },
    });
    throw refusal("internal", SCREENSHOT_INTERNAL, "internal");
  }
}
