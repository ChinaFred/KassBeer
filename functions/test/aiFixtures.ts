// Réglages et réponses de l'API Messages communs aux tests de l'IA (ADR-016, ADR-015) :
// aucun appel réel, `fetch` simulé.

const CC = "recipe_assistant_turn";

export const FEATURE = {
  model: "claude-sonnet-5-5",
  effort: "medium",
  members_enabled: false,
  turns_per_day: 20,
  founder_turns_per_day: 60,
  turns_per_conversation: 20,
};

export const POLICY = { version: 1, features: { [CC]: FEATURE } };

export const PRICING = {
  version: 1,
  checked_on: "2026-11-15",
  source: "Page des tarifs d'Anthropic",
  models: {
    "claude-sonnet-5-5": {
      label: "Sonnet 5.5",
      input_usd_per_mtok: 2,
      output_usd_per_mtok: 10,
      cache_write_usd_per_mtok: 2.5,
      cache_read_usd_per_mtok: 0.2,
      efforts: ["low", "medium", "high"],
    },
    "claude-haiku-5-5": {
      label: "Haiku 5.5",
      input_usd_per_mtok: 0.1,
      output_usd_per_mtok: 0.5,
      cache_write_usd_per_mtok: 0.125,
      cache_read_usd_per_mtok: 0.01,
      efforts: [],
    },
  },
};

export function anthropicResponse(
  text: string,
  opts: { stop?: string; usage?: Record<string, number> } = {},
): Response {
  return new Response(
    JSON.stringify({
      id: "msg_1",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-5-5",
      content: [{ type: "text", text }],
      stop_reason: opts.stop ?? "end_turn",
      usage: opts.usage ?? {
        input_tokens: 1000,
        output_tokens: 500,
        cache_creation_input_tokens: 200,
        cache_read_input_tokens: 2000,
      },
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}
