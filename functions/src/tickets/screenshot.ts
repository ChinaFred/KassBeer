/**
 * Capture d'écran jointe à un ticket (`attachTicketScreenshot`, ADR-008, T6, P30). Copie de
 * `attachTicketScreenshot` de Kass'Dalle (`functions/src/callable/ticketsCallable.ts`).
 *
 * Le client crée le ticket dans Firestore, dépose l'image dans
 * `tickets/{uid}/{ticketId}/screenshot.png` (ou `.jpg`) sous `storage.rules`, puis appelle
 * cette callable. Elle vérifie, dans l'ordre :
 *
 * 1. `requireMember` (P30), avant toute lecture des arguments ;
 * 2. `ticketId` et `path` bornés en taille brute (`requireBoundedText`), `path` égal à l'un
 *    des deux chemins de l'appelant pour ce ticket ;
 * 3. le ticket existe et son `author_uid` est l'appelant ;
 * 4. le fichier existe, son type annoncé est celui de l'extension, sa taille va de 1 octet à
 *    5 Mo, et ses premiers octets sont ceux d'un PNG ou d'un JPEG ;
 *
 * puis écrit `screenshot_path` sur le ticket. La capture ne part jamais sur GitHub, et ni
 * son contenu ni son nom ne sont journalisés.
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireBoundedText, requireMember, type AuthLike, type MemberLookup } from "../auth";
import { COLL_TICKETS } from "../config";
import { firestore, type FirestoreKit } from "../firestore";
import { logError } from "../logging";
import { storageScreenshotStore, type ScreenshotStore } from "../storage";
import { readTicketIdArg } from "./answer";

/** Taille maximale d'une capture, comme `storage.rules`. */
export const SCREENSHOT_MAX_BYTES = 5 * 1024 * 1024;

/** Octets lus en tête d'une capture pour en vérifier la signature. */
export const SCREENSHOT_SIGNATURE_BYTES = 8;

/** Longueur brute maximale de `path` avant toute lecture. */
export const SCREENSHOT_PATH_MAX_CHARS = 300;

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG_SIGNATURE = [0xff, 0xd8, 0xff];

/** Les deux chemins admis pour la capture du ticket `ticketId` de `uid`. Pure. */
export function screenshotPaths(uid: string, ticketId: string): string[] {
  return [`tickets/${uid}/${ticketId}/screenshot.png`, `tickets/${uid}/${ticketId}/screenshot.jpg`];
}

/** Type MIME attendu pour un chemin admis. Pure. */
export function screenshotContentType(path: string): "image/png" | "image/jpeg" {
  return path.endsWith(".png") ? "image/png" : "image/jpeg";
}

/**
 * Vrai si les premiers octets sont ceux du format annoncé : signature PNG sur 8 octets, ou
 * `FF D8 FF` pour un JPEG. Le type annoncé par le client ne prouve rien sur le contenu. Pure.
 */
export function screenshotBytesMatch(head: Uint8Array, contentType: string): boolean {
  const signature =
    contentType === "image/png"
      ? PNG_SIGNATURE
      : contentType === "image/jpeg"
        ? JPEG_SIGNATURE
        : null;
  if (signature === null || head.length < signature.length) return false;
  return signature.every((byte, i) => head[i] === byte);
}

export const SCREENSHOT_PATH_INVALID = "Chemin de capture invalide.";
export const SCREENSHOT_TICKET_MISSING = "Ce ticket n'existe plus.";
export const SCREENSHOT_NOT_AUTHOR = "Ce ticket ne vous appartient pas.";
export const SCREENSHOT_FILE_MISSING = "La capture n'a pas été trouvée.";
export const SCREENSHOT_FILE_REFUSED =
  "Seules les images PNG ou JPEG de 5 Mo au plus sont acceptées.";
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
 * `path` d'une requête : texte borné, égal à l'un des chemins de [uid] pour [ticketId].
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
  if (!screenshotPaths(uid, ticketId).includes(value)) {
    throw refusal("invalid-argument", SCREENSHOT_PATH_INVALID, "path_invalid", "path");
  }
  return value;
}

export interface ScreenshotDeps {
  lookup?: MemberLookup;
  kit?: () => Promise<FirestoreKit>;
  store?: ScreenshotStore;
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
    file.contentType !== screenshotContentType(path) ||
    !(file.size > 0 && file.size <= SCREENSHOT_MAX_BYTES)
  ) {
    throw refusal("invalid-argument", SCREENSHOT_FILE_REFUSED, "file_refused");
  }
  const head = await store.head(path, SCREENSHOT_SIGNATURE_BYTES);
  if (!screenshotBytesMatch(head, file.contentType)) {
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
    // Ni le chemin, ni le contenu : l'identifiant du ticket suffit.
    logError({
      message: "Tickets : capture non jointe",
      feature: "tickets",
      ticketId,
      error: err,
    });
    throw refusal("internal", SCREENSHOT_INTERNAL, "internal");
  }
}
