/**
 * Comptes du mois par membre et par poste (ADR-016, section 6 ; P57, P58).
 *
 * `ai_usage/{AAAA-MM}_{uid}` : `month`, `uid`, `member_email` (e-mail en minuscules tiré du
 * jeton vérifié, jamais d'un argument), `expires_at` (premier jour du mois M + 13 à minuit de
 * Paris, champ TTL), `updated_at`, et par poste dans `features` : `calls`, `failed_calls`,
 * `unpriced_calls`, `input_tokens`, `cache_write_tokens`, `cache_read_tokens`,
 * `output_tokens`, `cost_usd`. Aucun texte de la personne ni du modèle. Le montant s'écrit une
 * fois : un changement de grille ne recalcule pas les mois passés.
 */

import { AI_USAGE_RETENTION_MONTHS, COLL_AI_USAGE } from "../config";
import type { FirestoreKit } from "../firestore";
import type { AiCostCenter } from "./costCenters";
import { parisMidnightMs } from "./parisTime";
import type { ClaudeUsage } from "./pricing";

export const USAGE_COUNTERS = [
  "calls",
  "failed_calls",
  "unpriced_calls",
  "input_tokens",
  "cache_write_tokens",
  "cache_read_tokens",
  "output_tokens",
  "cost_usd",
] as const;

export type UsageCounters = Record<(typeof USAGE_COUNTERS)[number], number>;

/** Ce qu'un appel ajoute au mois. */
export type UsageDelta =
  { kind: "answered"; usage: ClaudeUsage | null; costUsd: number | null } | { kind: "failed" };

/** Identifiant du document du mois. Pure. */
export function usageDocId(month: string, uid: string): string {
  return `${month}_${uid}`;
}

/** Échéance des comptes du mois `AAAA-MM` : premier jour du mois M + 13, minuit de Paris. Pure. */
export function usageExpiresAtMs(month: string): number {
  const year = Number(month.slice(0, 4));
  const monthIndex = Number(month.slice(5, 7));
  return parisMidnightMs(year, monthIndex + AI_USAGE_RETENTION_MONTHS, 1);
}

function counterOf(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
}

/** Compteurs d'un poste après l'appel. Pure. */
export function nextCounters(current: unknown, delta: UsageDelta): UsageCounters {
  const c = (current !== null && typeof current === "object" ? current : {}) as Record<
    string,
    unknown
  >;
  const out = Object.fromEntries(USAGE_COUNTERS.map((k) => [k, counterOf(c[k])])) as UsageCounters;
  out.calls += 1;
  if (delta.kind === "failed") {
    out.failed_calls += 1;
    return out;
  }
  if (delta.usage !== null) {
    out.input_tokens += delta.usage.input_tokens;
    out.cache_write_tokens += delta.usage.cache_creation_input_tokens;
    out.cache_read_tokens += delta.usage.cache_read_input_tokens;
    out.output_tokens += delta.usage.output_tokens;
  }
  if (delta.costUsd === null) out.unpriced_calls += 1;
  else out.cost_usd = Math.round((out.cost_usd + delta.costUsd) * 1_000_000) / 1_000_000;
  return out;
}

/** Ajoute un appel aux comptes du mois, en transaction. Lève sur une panne. */
export async function recordUsage(
  kit: FirestoreKit,
  args: {
    uid: string;
    email: string;
    costCenter: AiCostCenter;
    month: string;
    delta: UsageDelta;
  },
): Promise<void> {
  const { db, FieldValue, Timestamp } = kit;
  const ref = db.collection(COLL_AI_USAGE).doc(usageDocId(args.month, args.uid));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const raw = data?.features;
    const features =
      raw !== null && typeof raw === "object" && !Array.isArray(raw)
        ? { ...(raw as Record<string, unknown>) }
        : {};
    features[args.costCenter] = nextCounters(features[args.costCenter], args.delta);
    const write: Record<string, unknown> = {
      month: args.month,
      uid: args.uid,
      member_email: args.email,
      features,
      updated_at: FieldValue.serverTimestamp(),
    };
    if (!(data?.expires_at instanceof Timestamp)) {
      write.expires_at = Timestamp.fromMillis(usageExpiresAtMs(args.month));
    }
    tx.set(ref, write, { merge: true });
  });
}
