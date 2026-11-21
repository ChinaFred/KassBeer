/**
 * Callable `saveAiSettings` : Admin › Moteur d'IA enregistre la politique ou la grille
 * tarifaire (ADR-016, section 8 ; P58).
 *
 * 1. `requireAdmin` (P30), avant toute lecture de l'argument.
 * 2. Taille brute de l'argument bornée à 32 Ko ; `{kind: "policy" | "pricing", value}` seul.
 * 3. Validation par `settings.ts`, le code qui relit ces documents à chaque appel.
 * 4. Transaction : la politique s'écrit après relecture de la grille (grille illisible :
 *    refus ; modèle ou effort hors grille : refus) ; la grille s'écrit après relecture de la
 *    politique (modèle ou effort retiré alors qu'un poste s'en sert : refus).
 * 5. Écriture complète du document, avec `updated_at` et `updated_by_uid`.
 *
 * Refus `invalid-argument` avec `details.field` (chemin du champ en faute, `""` pour
 * l'argument entier) et `details.reason` (texte affiché sous le champ). Aucun secret.
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireAdmin, type AuthLike, type MemberLookup } from "../auth";
import { AI_POLICY_DOC, AI_PRICING_DOC, COLL_AI_CONFIG } from "../config";
import { firestore, type FirestoreKit } from "../firestore";
import { jsonLength } from "./json";
import {
  policyConflict,
  pricingConflict,
  readPolicy,
  readPricing,
  type AiPolicy,
  type AiPricing,
} from "./settings";

/** Taille brute de l'argument, en caractères de son JSON (32 Ko). */
export const SETTINGS_MAX_CHARS = 32 * 1024;

export interface SaveSettingsDeps {
  kit?: () => Promise<FirestoreKit>;
  lookup?: MemberLookup;
}

export interface SaveSettingsResult {
  saved: true;
  kind: "policy" | "pricing";
}

function invalid(field: string, reason: string): HttpsError {
  return new HttpsError("invalid-argument", reason, { field, reason });
}

export async function handleSaveAiSettingsCall(
  req: AuthLike & { data?: unknown },
  deps: SaveSettingsDeps = {},
): Promise<SaveSettingsResult> {
  const { uid } = await requireAdmin(req, deps.lookup);
  const size = jsonLength(req.data);
  if (size === null || size > SETTINGS_MAX_CHARS) {
    throw invalid("", "Réglages trop volumineux (32 Ko au plus).");
  }
  const data = req.data;
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw invalid("", "Réglages illisibles.");
  }
  const arg = data as Record<string, unknown>;
  const extra = Object.keys(arg).find((k) => k !== "kind" && k !== "value");
  if (extra !== undefined) throw invalid(extra, "Champ inconnu.");
  const kind = arg.kind;
  if (kind !== "policy" && kind !== "pricing") {
    throw invalid("kind", "Type de réglage : « policy » ou « pricing ».");
  }
  const kit = await (deps.kit ?? firestore)();
  if (kind === "policy") {
    const policy = readPolicy(arg.value, { stored: false });
    if (!policy.ok) throw invalid(policy.field, policy.message);
    await savePolicy(kit, policy.value, uid);
  } else {
    const pricing = readPricing(arg.value, { stored: false });
    if (!pricing.ok) throw invalid(pricing.field, pricing.message);
    await savePricing(kit, pricing.value, uid);
  }
  return { saved: true, kind };
}

async function savePolicy(kit: FirestoreKit, policy: AiPolicy, uid: string): Promise<void> {
  const { db, FieldValue } = kit;
  const policyRef = db.collection(COLL_AI_CONFIG).doc(AI_POLICY_DOC);
  const pricingRef = db.collection(COLL_AI_CONFIG).doc(AI_PRICING_DOC);
  await db.runTransaction(async (tx) => {
    const pricingSnap = await tx.get(pricingRef);
    const pricing = readPricing(pricingSnap.exists ? pricingSnap.data() : undefined, {
      stored: true,
    });
    if (!pricing.ok) {
      throw new HttpsError(
        "failed-precondition",
        "Grille tarifaire absente ou illisible : enregistrez-la d'abord.",
        { field: "pricing", reason: "ai_pricing_unavailable" },
      );
    }
    const conflict = policyConflict(policy, pricing.value);
    if (conflict !== null) throw invalid(conflict.field, conflict.message);
    tx.set(policyRef, {
      ...policy,
      updated_at: FieldValue.serverTimestamp(),
      updated_by_uid: uid,
    });
  });
}

async function savePricing(kit: FirestoreKit, pricing: AiPricing, uid: string): Promise<void> {
  const { db, FieldValue } = kit;
  const policyRef = db.collection(COLL_AI_CONFIG).doc(AI_POLICY_DOC);
  const pricingRef = db.collection(COLL_AI_CONFIG).doc(AI_PRICING_DOC);
  await db.runTransaction(async (tx) => {
    const policySnap = await tx.get(policyRef);
    // Politique absente ou illisible : rien à protéger, chaque poste refuse déjà tout appel.
    const policy = readPolicy(policySnap.exists ? policySnap.data() : undefined, { stored: true });
    if (policy.ok) {
      const conflict = pricingConflict(policy.value, pricing);
      if (conflict !== null) throw invalid(conflict.field, conflict.message);
    }
    tx.set(pricingRef, {
      ...pricing,
      updated_at: FieldValue.serverTimestamp(),
      updated_by_uid: uid,
    });
  });
}
