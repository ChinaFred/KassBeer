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
 *    ses 24 premiers octets (seuls lus) sont ceux d'un PNG dont l'en-tête IHDR annonce une
 *    largeur et une hauteur de 1 à 2 000 px (note du 2026-11-14) ;
 *
 * puis écrit `screenshot_path` et `screenshot_expires_at` (rattachement + 180 jours, date
 * d'effacement par la règle de cycle de vie du bucket) sur le ticket. La capture ne part jamais sur GitHub. Ni son
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

/**
 * Octets lus en tête d'une capture : signature (0 à 7), longueur et type du premier bloc
 * (8 à 15, `IHDR`), largeur et hauteur (16 à 23). Lecture partielle : le reste du fichier
 * n'est jamais téléchargé.
 */
export const SCREENSHOT_HEAD_BYTES = 24;

/** Largeur et hauteur maximales d'une capture, en pixels (note du 2026-11-14). */
export const SCREENSHOT_MAX_SIDE_PX = 2000;

/**
 * Durée de conservation d'une capture, en jours : la règle de cycle de vie du bucket
 * l'efface après ce délai (`exigences-techniques.md`, réglages faits une fois).
 */
export const SCREENSHOT_RETENTION_DAYS = 180;

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
 * Largeur et hauteur lues dans l'en-tête IHDR d'un PNG (octets 16 à 23, gros-boutiste), ou
 * `null` si la tête est trop courte, si la signature manque, si le premier bloc n'est pas
 * un `IHDR` de 13 octets ou si un côté vaut 0. Pure.
 */
export function pngDimensions(head: Uint8Array): { width: number; height: number } | null {
  if (head.length < SCREENSHOT_HEAD_BYTES || !screenshotBytesMatch(head)) return null;
  const view = new DataView(head.buffer, head.byteOffset, head.byteLength);
  if (view.getUint32(8) !== 13) return null;
  const type = String.fromCharCode(head[12], head[13], head[14], head[15]);
  if (type !== "IHDR") return null;
  const width = view.getUint32(16);
  const height = view.getUint32(20);
  if (width === 0 || height === 0) return null;
  return { width, height };
}

/** Vrai si la largeur et la hauteur valent au plus 2 000 px. Pure. */
export function screenshotDimensionsAccepted(dims: { width: number; height: number }): boolean {
  return dims.width <= SCREENSHOT_MAX_SIDE_PX && dims.height <= SCREENSHOT_MAX_SIDE_PX;
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
export const SCREENSHOT_TOO_LARGE = "Cette image dépasse 2 000 pixels de côté.";
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
  /** Heure courante en millisecondes, remplacée dans les tests. */
  now?: () => number;
}

/**
 * Vérifie la capture déposée et écrit `screenshot_path` et `screenshot_expires_at`
 * (étapes 3 et 4).
 */
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
  const head = await store.head(path, SCREENSHOT_HEAD_BYTES);
  if (!screenshotBytesMatch(head)) {
    throw refusal("invalid-argument", SCREENSHOT_FILE_REFUSED, "file_refused");
  }
  const dims = pngDimensions(head);
  if (dims === null) {
    throw refusal("invalid-argument", SCREENSHOT_FILE_REFUSED, "file_refused");
  }
  if (!screenshotDimensionsAccepted(dims)) {
    throw refusal("invalid-argument", SCREENSHOT_TOO_LARGE, "dimensions_refused");
  }

  const nowMs = (deps.now ?? Date.now)();
  await ref.update({
    screenshot_path: path,
    screenshot_expires_at: kit.Timestamp.fromMillis(nowMs + SCREENSHOT_RETENTION_DAYS * 86_400_000),
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
