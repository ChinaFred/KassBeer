/**
 * Plafond des tours par membre et par jour de Paris (ADR-016, section 11 ; P57).
 *
 * `ai_quotas/{uid}` porte, par poste, `day` (`AAAAMMJJ`), `count` et `resets_at` (minuit
 * suivant à Paris) dans la carte `features`. Un tour est réservé en transaction AVANT
 * l'appel ; il est rendu (− 1, jamais sous 0) seulement quand rien n'a pu être facturé
 * (réponse 4xx, connexion impossible avant l'envoi) ; il reste compté sur un délai dépassé, un
 * 5xx, un 529 et dès que le modèle a répondu. Plafond du fondateur (`members/{email}.founder`,
 * lu par `requireMember`) : `founder_turns_per_day`, sur le même document.
 */

import { HttpsError } from "firebase-functions/v2/https";

import { COLL_AI_QUOTAS } from "../config";
import type { FirestoreKit } from "../firestore";
import type { AiCostCenter } from "./costCenters";
import { nextParisMidnightMs, parisDay } from "./parisTime";
import type { AiFeaturePolicy } from "./settings";

export interface QuotaView {
  limit: number;
  /** Tours restants du jour après cette réservation. */
  remaining: number;
  /** Minuit suivant à Paris, en millisecondes. */
  resetsAtMs: number;
}

export interface Reservation extends QuotaView {
  day: string;
}

/** Plafond du jour de l'appelant. Pure. */
export function dailyLimit(feature: AiFeaturePolicy, founder: boolean): number {
  return founder ? feature.founder_turns_per_day : feature.turns_per_day;
}

/** Tours déjà comptés `day` dans l'entrée du poste ; 0 pour un autre jour. Pure. */
export function countFor(entry: unknown, day: string): number {
  if (entry === null || typeof entry !== "object") return 0;
  const e = entry as Record<string, unknown>;
  if (e.day !== day) return 0;
  const count = e.count;
  return typeof count === "number" && Number.isInteger(count) && count > 0 ? count : 0;
}

function featuresOf(data: Record<string, unknown> | undefined): Record<string, unknown> {
  const features = data?.features;
  return features !== null && typeof features === "object" && !Array.isArray(features)
    ? { ...(features as Record<string, unknown>) }
    : {};
}

export const QUOTA_MESSAGE = "Plus de tours aujourd'hui : le compteur repart à minuit.";

/**
 * Réserve un tour, en transaction. Lève `resource-exhausted` (`details.reason`
 * `quota_exhausted`) au plafond, sans rien écrire.
 */
export async function reserveTurn(
  kit: FirestoreKit,
  args: { uid: string; costCenter: AiCostCenter; limit: number; nowMs: number },
): Promise<Reservation> {
  const { db, Timestamp } = kit;
  const ref = db.collection(COLL_AI_QUOTAS).doc(args.uid);
  const day = parisDay(new Date(args.nowMs));
  const resetsAtMs = nextParisMidnightMs(args.nowMs);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const features = featuresOf(snap.data());
    const count = countFor(features[args.costCenter], day);
    if (count >= args.limit) {
      throw new HttpsError("resource-exhausted", QUOTA_MESSAGE, {
        reason: "quota_exhausted",
        quota: {
          limit: args.limit,
          remaining: 0,
          resets_at: new Date(resetsAtMs).toISOString(),
        },
      });
    }
    features[args.costCenter] = {
      day,
      count: count + 1,
      resets_at: Timestamp.fromMillis(resetsAtMs),
    };
    tx.set(ref, { features }, { merge: true });
    return { day, limit: args.limit, remaining: args.limit - count - 1, resetsAtMs };
  });
}

/**
 * Rend un tour réservé `day` (− 1, jamais sous 0). Sans effet si le jour a changé depuis.
 * Lève sur une panne : l'appelant journalise.
 */
export async function releaseTurn(
  kit: FirestoreKit,
  args: { uid: string; costCenter: AiCostCenter; day: string },
): Promise<void> {
  const { db } = kit;
  const ref = db.collection(COLL_AI_QUOTAS).doc(args.uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const features = featuresOf(snap.data());
    const entry = features[args.costCenter];
    const count = countFor(entry, args.day);
    if (count === 0) return;
    features[args.costCenter] = { ...(entry as Record<string, unknown>), count: count - 1 };
    tx.set(ref, { features }, { merge: true });
  });
}
