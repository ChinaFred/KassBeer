/**
 * Callable `recipeAssistantTurn` : un tour de l'assistant de recette (ADR-015, lot A1 ; P59).
 *
 * `requireMember` (P30), puis le socle (`runClaudeTurn`) : politique, ouverture du poste
 * (`members_enabled` ou administrateur), lecture bornée de l'argument (`readAssistantArgs`,
 * aucun décompte en cas de refus), réservation du tour, appel, comptes. La réponse du modèle
 * est coupée à 6 000 caractères à la dernière ligne vide (le client la rejoue dans `history`,
 * borné à 6 000) ; un résumé aussi. Au lot A1, `proposition` vaut toujours `null`.
 *
 * Aucun texte de la personne, du modèle ni de la recette n'est journalisé.
 */

import { accessFrom, firestoreMemberLookup, memberKeyOf, requireMember } from "../auth";
import type { AuthLike, MemberLookup } from "../auth";
import { runClaudeTurn, type RunDeps } from "../ai/run";
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
  /** Lot A2 ; toujours `null` au lot A1. */
  proposition: null;
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
  const cut = cutText(result.text, read.mode === "summary" ? SUMMARY_MAX_CHARS : REPLAY_MAX_CHARS);
  return {
    reponse: cut.text,
    proposition: null,
    mode: read.mode,
    turn: read.turn,
    truncated: cut.truncated,
    quota: {
      limit: result.quota.limit,
      remaining: result.quota.remaining,
      resets_at: new Date(result.quota.resetsAtMs).toISOString(),
    },
    conversation: { turn: read.turn, limit: read.turnsPerConversation },
  };
}
