/**
 * Callable `recipeAssistantTurn` : un tour de l'assistant de recette (ADR-015, lot A1 ; P59).
 *
 * `requireMember` (P30), puis le socle (`runClaudeTurn`) : politique, ouverture du poste
 * (`members_enabled` ou administrateur), lecture bornée de l'argument (`readAssistantArgs`,
 * aucun décompte en cas de refus), réservation du tour, appel, comptes. La réponse du modèle
 * est coupée à 6 000 caractères à la dernière ligne vide (le client la rejoue dans `history`,
 * borné à 6 000) ; un résumé aussi.
 *
 * Lot A2 : un tour rend une sortie structurée `{reponse, proposition}` (`proposition.ts`). Une
 * sortie qui n'est pas un JSON avec `reponse` rend `ai_no_answer`, tour compté ; une
 * proposition hors format ou de plus de 30 opérations est rendue `null`
 * (`proposition_rejected: true`), tour compté. Un résumé ne porte jamais de proposition.
 *
 * Aucun texte de la personne, du modèle ni de la recette n'est journalisé.
 */

import { HttpsError } from "firebase-functions/v2/https";

import { accessFrom, firestoreMemberLookup, memberKeyOf, requireMember } from "../auth";
import type { AuthLike, MemberLookup } from "../auth";
import { NO_ANSWER_MESSAGE, defaultLogger, runClaudeTurn, type RunDeps } from "../ai/run";
import { readTurnOutput, type Proposition } from "./proposition";
import {
  REPLAY_MAX_CHARS,
  SUMMARY_MAX_CHARS,
  buildAssistantRequest,
  cutText,
  readAssistantArgs,
  type AssistantArgs,
} from "./request";

export const ASSISTANT_COST_CENTER = "recipe_assistant_turn";

export interface AssistantResponse {
  /** Réponse du modèle en Markdown, ou le résumé en mode `summary`. */
  reponse: string;
  /** Proposition du modèle (lot A2), ou `null` : aucune, écartée, ou mode `summary`. */
  proposition: Proposition | null;
  /** Vrai si le modèle a rendu une proposition hors format, écartée par le serveur. */
  proposition_rejected: boolean;
  mode: "turn" | "summary";
  /** Rang du tour dans la conversation (1 pour le premier). */
  turn: number;
  /** Vrai si `reponse` a été coupée par le serveur. */
  truncated: boolean;
  quota: { limit: number; remaining: number; resets_at: string };
  conversation: { turn: number; limit: number };
}

export interface AssistantDeps extends RunDeps {
  lookup?: MemberLookup;
}

export async function handleRecipeAssistantCall(
  req: AuthLike & { data?: unknown },
  deps: AssistantDeps,
): Promise<AssistantResponse> {
  const lookup = deps.lookup ?? firestoreMemberLookup;
  let member: Record<string, unknown> | null = null;
  const { uid, founder } = await requireMember(req, async (key) => {
    member = await lookup(key);
    return member;
  });
  const token = req.auth?.token;
  const email = memberKeyOf(token) ?? "";
  const isAdmin = accessFrom(token, member) === "admin";

  let args: AssistantArgs | null = null;
  const result = await runClaudeTurn(
    {
      costCenter: ASSISTANT_COST_CENTER,
      caller: { uid, email, isAdmin, founder },
      build: (feature) => {
        args = readAssistantArgs(req.data, feature);
        return buildAssistantRequest(args);
      },
    },
    deps,
  );
  const read = args as AssistantArgs | null;
  if (read === null) throw new Error("recipeAssistantTurn : argument non lu");
  const log = deps.log ?? defaultLogger;
  const quota = {
    limit: result.quota.limit,
    remaining: result.quota.remaining,
    resets_at: new Date(result.quota.resetsAtMs).toISOString(),
  };
  let text = result.text;
  let proposition: Proposition | null = null;
  let rejected = false;
  if (read.mode === "turn") {
    const output = readTurnOutput(result.text, (entry) => log("error", entry));
    if (output === null) {
      throw new HttpsError("aborted", NO_ANSWER_MESSAGE, {
        reason: "ai_no_answer",
        counted: true,
        quota,
      });
    }
    text = output.reponse;
    proposition = output.proposition;
    if (output.rejectedPath !== null) {
      rejected = true;
      log("warn", {
        message: "Assistant : proposition hors format écartée (tour compté)",
        feature: "assistant",
        extra: { path: output.rejectedPath, correlation_id: read.conversationId },
      });
    }
  }
  const cut = cutText(text, read.mode === "summary" ? SUMMARY_MAX_CHARS : REPLAY_MAX_CHARS);
  return {
    reponse: cut.text,
    proposition,
    proposition_rejected: rejected,
    mode: read.mode,
    turn: read.turn,
    truncated: cut.truncated,
    quota,
    conversation: { turn: read.turn, limit: read.turnsPerConversation },
  };
}
