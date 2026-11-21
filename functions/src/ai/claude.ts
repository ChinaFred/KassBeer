/**
 * Client de l'API Messages d'Anthropic, par `fetch`, sans SDK (ADR-016, section 2 ; P57).
 *
 * Seul module de `functions/` qui appelle `https://api.anthropic.com/v1/messages`. Un seul
 * appel, jamais rejoué ; `redirect: "error"` (une redirection renverrait la clé ailleurs) ;
 * délai fixé par l'appelant. Aucune clé `thinking`, `tools` ni `tool_choice`, aucun message
 * `assistant` prérempli : l'effort passe par `output_config.effort` quand la politique en
 * donne un, la sortie structurée par `output_config.format` quand le poste en donne une.
 *
 * La clé (`ANTHROPIC_API_KEY`) n'entre dans aucun journal, aucun résultat ni aucune erreur
 * rendue : sa valeur exacte est retirée de tout texte (`withoutKey`). Du corps d'une erreur
 * d'Anthropic, seuls le statut HTTP et `error.type` vont au journal, jamais un extrait ni
 * `error.message` ; le client ne reçoit qu'un code stable (`runClaudeTurn`).
 */

import { logError, type LogEntry } from "../logging";
import type { ClaudeUsage } from "./pricing";
import type { AiEffort } from "./settings";

export const MESSAGES_URL = "https://api.anthropic.com/v1/messages";
export const ANTHROPIC_VERSION = "2023-06-01";

export interface ClaudeSystemBlock {
  text: string;
  /** Vrai : `cache_control` éphémère sur ce bloc (partie fixe du prompt). */
  cache: boolean;
}

export interface ClaudeMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ClaudeRequest {
  model: string;
  effort: AiEffort | null;
  system: readonly ClaudeSystemBlock[];
  messages: readonly ClaudeMessage[];
  maxTokens: number;
  timeoutMs: number;
  /**
   * Format de sortie structurée (`{type: "json_schema", schema}`), posé dans
   * `output_config.format` ; absent ou `null` : réponse en texte.
   */
  outputFormat?: Record<string, unknown> | null;
}

/**
 * - `answered` : réponse 2xx lisible, tour gardé ;
 * - `rejected` : réponse 4xx reçue, rien de facturé, tour rendu ;
 * - `not_sent` : connexion impossible avant l'envoi, tour rendu ;
 * - `failed` : délai dépassé, 408, 5xx, 529, réponse 1xx ou 3xx (redirection comprise),
 *   réponse 2xx illisible ou coupure après l'envoi : Anthropic a pu facturer, tour gardé
 *   (`failed_calls` + 1).
 *
 * `detail` ne cite jamais le corps d'une réponse : seulement un texte fixe, le statut ou
 * `error.type` d'Anthropic (borné, sans `error.message`), pour le journal.
 */
export type ClaudeOutcome =
  | {
      kind: "answered";
      text: string;
      stopReason: string | null;
      /** `null` si la réponse ne porte pas `usage` lisible : appel compté sans montant. */
      usage: ClaudeUsage | null;
    }
  | { kind: "rejected"; status: number; rejection: ClaudeRejection; detail: string }
  | { kind: "not_sent"; detail: string }
  | { kind: "failed"; status: number | null; failure: ClaudeFailure; detail: string };

/** Motif d'un refus 4xx, rendu au client en code stable. */
export type ClaudeRejection =
  "credit_exhausted" | "rate_limited" | "key_invalid" | "model_unavailable" | "request_rejected";

export type ClaudeFailure =
  | "timeout"
  | "server_error"
  | "overloaded"
  | "unreadable"
  | "network"
  | "redirect"
  | "unexpected_status";

export type ClaudeFetch = (input: string, init: RequestInit) => Promise<Response>;
export type ClaudeLog = (entry: LogEntry) => void;

/** Le texte sans la valeur exacte de la clé. Pure. */
export function withoutKey(text: string, key: string): string {
  return key.length === 0 ? text : text.split(key).join("[clé retirée]");
}

/** Corps JSON envoyé à l'API. Pure. */
export function messagesBody(req: ClaudeRequest): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: req.model,
    max_tokens: req.maxTokens,
    system: req.system.map((block) => ({
      type: "text",
      text: block.text,
      ...(block.cache ? { cache_control: { type: "ephemeral" } } : {}),
    })),
    messages: req.messages.map((m) => ({ role: m.role, content: m.content })),
  };
  const outputConfig: Record<string, unknown> = {};
  if (req.effort !== null) outputConfig.effort = req.effort;
  if (req.outputFormat) outputConfig.format = req.outputFormat;
  if (Object.keys(outputConfig).length > 0) body.output_config = outputConfig;
  return body;
}

function nonNegativeInt(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

/** `usage` de la réponse ; `null` sans jetons d'entrée et de sortie lisibles. Pure. */
export function readUsage(raw: unknown): ClaudeUsage | null {
  if (raw === null || typeof raw !== "object") return null;
  const u = raw as Record<string, unknown>;
  const input = nonNegativeInt(u.input_tokens);
  const output = nonNegativeInt(u.output_tokens);
  if (input === null || output === null) return null;
  return {
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: nonNegativeInt(u.cache_creation_input_tokens) ?? 0,
    cache_read_input_tokens: nonNegativeInt(u.cache_read_input_tokens) ?? 0,
  };
}

/** Texte des blocs `text` d'une réponse, ou `null` si `content` n'est pas une liste. Pure. */
export function readText(content: unknown): string | null {
  if (!Array.isArray(content)) return null;
  return content
    .filter(
      (b): b is { type: "text"; text: string } =>
        b !== null &&
        typeof b === "object" &&
        (b as Record<string, unknown>).type === "text" &&
        typeof (b as Record<string, unknown>).text === "string",
    )
    .map((b) => b.text)
    .join("");
}

/** Forme admise de `error.type` d'Anthropic (`invalid_request_error`…) pour le journal. */
const ERROR_TYPE_PATTERN = /^[a-z_]{1,60}$/;

/**
 * Erreur d'Anthropic (`{"type":"error","error":{"type","message"}}`) : `type` borné à
 * `ERROR_TYPE_PATTERN` (sinon `null`), seul journalisé ; `message`, lu pour reconnaître un
 * crédit épuisé et jamais journalisé (il peut citer la requête).
 */
export function anthropicErrorOf(
  body: string,
  log: ClaudeLog,
): { type: string | null; message: string } {
  try {
    const json: unknown = JSON.parse(body);
    const error = (json as { error?: { type?: unknown; message?: unknown } } | null)?.error;
    const type =
      typeof error?.type === "string" && ERROR_TYPE_PATTERN.test(error.type) ? error.type : null;
    return { type, message: typeof error?.message === "string" ? error.message : "" };
  } catch (err) {
    // Corps d'erreur non JSON (proxy, page HTML) : le statut décide seul. Journalisé sans le
    // corps, qui peut citer la requête.
    log({
      message: "IA : corps d'une réponse d'erreur illisible",
      feature: "ai",
      extra: { error_name: err instanceof Error ? err.name : typeof err },
    });
    return { type: null, message: "" };
  }
}

/** `detail` d'une réponse d'erreur : statut et `error.type`, rien du corps. Pure. */
function statusDetail(status: number, type: string | null): string {
  return `HTTP ${status}${type === null ? "" : ` ${type}`}`;
}

const CREDIT_PATTERN = /credit balance|usage limit|spend(ing)? limit|billing/i;

/** Motif d'un refus 4xx. Pure (le message vient de `anthropicErrorOf`, jamais journalisé). */
export function rejectionOf(status: number, message: string): ClaudeRejection {
  if ((status === 400 || status === 429 || status === 402) && CREDIT_PATTERN.test(message)) {
    return "credit_exhausted";
  }
  if (status === 429) return "rate_limited";
  if (status === 401 || status === 403) return "key_invalid";
  if (status === 404) return "model_unavailable";
  return "request_rejected";
}

/** Codes d'erreur réseau levés avant l'envoi de la requête (undici, Node). */
const BEFORE_SEND_CODES = [
  "ECONNREFUSED",
  "ENOTFOUND",
  "EAI_AGAIN",
  "ENETUNREACH",
  "EHOSTUNREACH",
  "UND_ERR_CONNECT_TIMEOUT",
];

function causeCode(err: unknown): string {
  const cause = (err as { cause?: unknown } | null)?.cause;
  const code = (cause as { code?: unknown } | null)?.code;
  return typeof code === "string" ? code : "";
}

/** Vrai pour l'échec de `fetch` sur une réponse 3xx avec `redirect: "error"`. Pure. */
function isRedirect(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const cause = (err as Error & { cause?: unknown }).cause;
  return /redirect/i.test(`${err.message} ${cause instanceof Error ? cause.message : ""}`);
}

/**
 * Appelle l'API une fois. Ne lève pas : chaque issue est rendue (`ClaudeOutcome`). Les textes
 * d'erreur sont rendus sans la clé.
 */
export async function callClaude(
  req: ClaudeRequest,
  apiKey: string,
  opts: { fetchImpl?: ClaudeFetch; log?: ClaudeLog } = {},
): Promise<ClaudeOutcome> {
  const doFetch = opts.fetchImpl ?? fetch;
  const log = opts.log ?? logError;
  const clean = (text: string) => withoutKey(text, apiKey);
  let response: Response;
  try {
    response = await doFetch(MESSAGES_URL, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
      },
      body: JSON.stringify(messagesBody(req)),
      redirect: "error",
      signal: AbortSignal.timeout(req.timeoutMs),
    });
  } catch (err) {
    const name = err instanceof Error ? err.name : typeof err;
    const message = clean(err instanceof Error ? err.message : String(err));
    const code = causeCode(err);
    log({
      message: "IA : appel de l'API Messages en échec",
      feature: "ai",
      extra: { error_name: name, error: message.slice(0, 500), error_code: code },
    });
    if (isRedirect(err)) {
      // Réponse 3xx reçue après l'envoi : la requête a pu être traitée, le tour reste compté.
      return {
        kind: "failed",
        status: null,
        failure: "redirect",
        detail: "redirection refusée (3xx)",
      };
    }
    if (name === "TimeoutError" || name === "AbortError") {
      return { kind: "failed", status: null, failure: "timeout", detail: "délai dépassé" };
    }
    if (BEFORE_SEND_CODES.includes(code)) {
      return { kind: "not_sent", detail: `connexion impossible (${code})` };
    }
    return { kind: "failed", status: null, failure: "network", detail: message.slice(0, 300) };
  }
  let body: string;
  try {
    body = clean(await response.text());
  } catch (err) {
    log({
      message: "IA : corps de la réponse de l'API Messages illisible",
      feature: "ai",
      extra: {
        status: response.status,
        error_name: err instanceof Error ? err.name : typeof err,
      },
    });
    if (response.status >= 400 && response.status < 500 && response.status !== 408) {
      return {
        kind: "rejected",
        status: response.status,
        rejection: rejectionOf(response.status, ""),
        detail: "corps illisible",
      };
    }
    const failure = response.status === 529 ? "overloaded" : "unreadable";
    return { kind: "failed", status: response.status, failure, detail: "corps illisible" };
  }
  const status = response.status;
  if (status >= 200 && status < 300) {
    let json: Record<string, unknown> | null = null;
    try {
      const parsed: unknown = JSON.parse(body);
      if (parsed !== null && typeof parsed === "object") json = parsed as Record<string, unknown>;
    } catch (err) {
      log({
        message: "IA : réponse 2xx de l'API Messages illisible",
        feature: "ai",
        extra: { error_name: err instanceof Error ? err.name : typeof err },
      });
    }
    const text = json === null ? null : readText(json.content);
    if (json === null || text === null) {
      return { kind: "failed", status, failure: "unreadable", detail: "réponse illisible" };
    }
    return {
      kind: "answered",
      text,
      stopReason: typeof json.stop_reason === "string" ? json.stop_reason : null,
      usage: readUsage(json.usage),
    };
  }
  if (status >= 400 && status < 500 && status !== 408) {
    const error = anthropicErrorOf(body, log);
    return {
      kind: "rejected",
      status,
      rejection: rejectionOf(status, error.message),
      detail: statusDetail(status, error.type),
    };
  }
  if (status === 529) {
    return { kind: "failed", status, failure: "overloaded", detail: statusDetail(status, null) };
  }
  // 408 (délai côté Anthropic) : la requête a pu être traitée, comme un délai dépassé.
  if (status >= 500 || status === 408) {
    return { kind: "failed", status, failure: "server_error", detail: statusDetail(status, null) };
  }
  // 1xx ou 3xx rendu sans erreur de `fetch` : la requête a pu être traitée, tour gardé.
  return {
    kind: "failed",
    status,
    failure: "unexpected_status",
    detail: statusDetail(status, null),
  };
}
