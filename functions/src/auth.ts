/**
 * Garde des callables (ADR-008, « Protection des callables », P30, P31).
 *
 * Copie de la vérification d'appartenance de `firestore.rules` (`isGoogleVerified`,
 * `isMember`, `isAdmin`, P11) : jeton présent, `email_verified === true`,
 * `firebase.sign_in_provider === 'google.com'`, document `members/{email en minuscules}`
 * relu à chaque appel, rôle `admin` pour `requireAdmin`. Les deux copies rejouent la
 * fixture `test-fixtures/member_access.json` (`rules-tests/`, `functions/test/`).
 *
 * Un refus ne dit pas si le compte existe : `unauthenticated` sans jeton,
 * `permission-denied` sinon, avec le même message pour un non-membre et un brasseur.
 * Aucun cache : un rôle retiré dans `members/` vaut à l'appel suivant (P26).
 */

import { HttpsError } from "firebase-functions/v2/https";

import { COLL_MEMBERS } from "./config";
import { firestore } from "./firestore";

/** Ce que le SDK rend du jeton vérifié (`request.auth.token`), lu sans supposer sa forme. */
export type TokenClaims = Record<string, unknown>;

/** Accès d'un compte : aucun, membre (`brewer` ou autre rôle), administrateur. */
export type MemberAccess = "none" | "member" | "admin";

/** Lecture de `members/{clé}` : ses champs, ou `null` si le document n'existe pas. */
export type MemberLookup = (emailKey: string) => Promise<Record<string, unknown> | null>;

/**
 * La clé de `members/` du jeton (e-mail en minuscules), ou `null` si le jeton ne remplit
 * pas `isGoogleVerified()` : e-mail textuel, vérifié (`true`, pas `"true"`), fournisseur
 * `google.com`. Pure.
 */
export function memberKeyOf(token: TokenClaims | null | undefined): string | null {
  if (token === null || token === undefined) return null;
  const email = token.email;
  if (typeof email !== "string" || email.length === 0) return null;
  if (token.email_verified !== true) return null;
  const firebase = token.firebase as { sign_in_provider?: unknown } | null | undefined;
  if (firebase?.sign_in_provider !== "google.com") return null;
  return email.toLowerCase();
}

/**
 * L'accès d'un compte, d'après son jeton et le document `members/` lu : `isMember()` exige
 * le document, quel que soit son rôle ; `isAdmin()` exige `role == 'admin'`, à l'identique.
 * Pure.
 */
export function accessFrom(
  token: TokenClaims | null | undefined,
  member: Record<string, unknown> | null,
): MemberAccess {
  if (memberKeyOf(token) === null || member === null) return "none";
  return member.role === "admin" ? "admin" : "member";
}

/** L'accès d'un compte, `members/` relu par `lookup`. */
export async function memberAccess(
  token: TokenClaims | null | undefined,
  lookup: MemberLookup,
): Promise<MemberAccess> {
  const key = memberKeyOf(token);
  if (key === null) return "none";
  return accessFrom(token, await lookup(key));
}

/** Lecture de `members/{clé}` dans Firestore. */
export const firestoreMemberLookup: MemberLookup = async (emailKey) => {
  const { db } = await firestore();
  const snap = await db.collection(COLL_MEMBERS).doc(emailKey).get();
  return snap.exists ? (snap.data() ?? {}) : null;
};

/** Ce qu'une callable lit de sa requête pour la garde. */
export interface AuthLike {
  auth?: { uid: string; token: TokenClaims } | null;
}

export const UNAUTHENTICATED_MESSAGE = "Connexion requise.";
export const MEMBER_DENIED_MESSAGE = "Accès réservé aux membres.";
export const ADMIN_DENIED_MESSAGE = "Accès réservé à l'administrateur.";

async function requireAccess(
  req: AuthLike,
  need: "member" | "admin",
  lookup: MemberLookup,
): Promise<{ uid: string }> {
  const auth = req.auth;
  if (auth === null || auth === undefined || typeof auth.uid !== "string") {
    throw new HttpsError("unauthenticated", UNAUTHENTICATED_MESSAGE, {
      reason: UNAUTHENTICATED_MESSAGE,
    });
  }
  const access = await memberAccess(auth.token, lookup);
  const granted = need === "admin" ? access === "admin" : access !== "none";
  if (!granted) {
    const message = need === "admin" ? ADMIN_DENIED_MESSAGE : MEMBER_DENIED_MESSAGE;
    throw new HttpsError("permission-denied", message, { reason: message });
  }
  return { uid: auth.uid };
}

/** Exige un membre (P30). Première instruction de chaque callable ouverte aux membres. */
export function requireMember(
  req: AuthLike,
  lookup: MemberLookup = firestoreMemberLookup,
): Promise<{ uid: string }> {
  return requireAccess(req, "member", lookup);
}

/** Exige l'administrateur (P30). Première instruction de chaque callable de l'admin. */
export function requireAdmin(
  req: AuthLike,
  lookup: MemberLookup = firestoreMemberLookup,
): Promise<{ uid: string }> {
  return requireAccess(req, "admin", lookup);
}

/**
 * Garde de taille brute d'un argument texte, avant toute lecture (P30, `requireBoundedText`
 * de Kass'Dalle) : absent ou `null` refusé si `required`, sinon rendu `undefined` ; autre
 * type que texte refusé ; plus de `max` unités UTF-16 refusé. Lève `invalid-argument` avec
 * `details.field` et `details.reason` (« Réponse : texte trop long. »).
 */
export function requireBoundedText(
  value: unknown,
  opts: { field: string; max: number; required: true; label: string },
): string;
export function requireBoundedText(
  value: unknown,
  opts: { field: string; max: number; required?: boolean; label: string },
): string | undefined;
export function requireBoundedText(
  value: unknown,
  opts: { field: string; max: number; required?: boolean; label: string },
): string | undefined {
  const fail = (reason: string): never => {
    throw new HttpsError("invalid-argument", reason, { field: opts.field, reason });
  };
  if (value === undefined || value === null) {
    if (opts.required === true) fail(`${opts.label} : valeur requise.`);
    return undefined;
  }
  if (typeof value !== "string") return fail(`${opts.label} : un texte est attendu.`);
  if (value.length > opts.max) return fail(`${opts.label} : texte trop long.`);
  return value;
}
