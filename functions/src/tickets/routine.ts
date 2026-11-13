/**
 * Client minimal de l'API des Routines Claude Code, par `fetch`, sans SDK (ADR-008, T4,
 * P35). Copie de `functions/src/tickets/routine.ts` de Kass'Dalle.
 *
 * Un seul appel : `POST https://api.anthropic.com/v1/claude_code/routines/{id}/fire`, corps
 * `{"text": "analyse #N"}` ou `{"text": "developpement #N"}` (`livraison` arrive à T5).
 * L'API n'a pas de clé d'idempotence : un appel n'est jamais rejoué, ni ici ni par
 * l'appelant. C'est le seul appel sortant vers `api.anthropic.com` (P35).
 *
 * L'identifiant et le jeton de chaque routine viennent de Secret Manager
 * (`TICKETS_ROUTINE_ANALYSIS_ID` / `_TOKEN`, `TICKETS_ROUTINE_DEV_ID` / `_TOKEN`). Le jeton ne
 * figure dans aucun message, aucun journal, aucune erreur rendue : sa valeur exacte est
 * retirée de tout texte d'erreur (`withoutSecrets`).
 *
 * Aucun appel de modèle n'est facturé au projet : la session tourne sur l'abonnement Claude
 * de l'administrateur. Le poste `ticket_routine_launch` compte les lancements (P36).
 */

import { logError, type LogEntry } from "../logging";
import { LAUNCH_TEXT_PATTERN } from "./launchModel";

/** Hôte et chemin de l'API, constants (P35). */
const API = "https://api.anthropic.com/v1/claude_code/routines";
const ANTHROPIC_VERSION = "2023-06-01";

/** Délai d'un lancement. Au-delà, le résultat est inconnu. */
export const ROUTINE_TIMEOUT_MS = 30_000;

/** Longueur gardée d'une URL de session rendue par l'API (P41). */
export const SESSION_URL_MAX = 500;

/** Forme d'un identifiant de routine : un segment d'URL sûr (P35). */
const ROUTINE_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export interface RoutineConfig {
  id: string;
  token: string;
}

/**
 * L'identifiant et le jeton d'une routine, ou `null` si l'un manque, est vide, ou si
 * l'identifiant n'a pas la forme d'un segment d'URL sûr : « non configuré », rien ne part.
 * Pure.
 */
export function routineConfig(
  id: string | null | undefined,
  token: string | null | undefined,
): RoutineConfig | null {
  const cleanId = (id ?? "").trim();
  const cleanToken = (token ?? "").trim();
  if (cleanId.length === 0 || cleanToken.length === 0) return null;
  if (!ROUTINE_ID_PATTERN.test(cleanId)) return null;
  return { id: cleanId, token: cleanToken };
}

/**
 * Le texte sans la valeur exacte du jeton ni de l'identifiant de la routine (P35, P41). La
 * forme des jetons de routine n'est pas documentée : aucun motif ne les reconnaît, seule la
 * valeur est retirée. Pure.
 */
export function withoutSecrets(text: string, config: RoutineConfig): string {
  let out = text;
  for (const secret of [config.token, config.id]) {
    if (secret.length > 0) out = out.split(secret).join("[retiré]");
  }
  return out;
}

/** Journal d'un `catch` de ce fichier : `logError` par défaut, remplacé dans les tests. */
export type RoutineLog = (entry: LogEntry) => void;

/**
 * Journalise une erreur attrapée par le client de l'API (CLAUDE.md, « Aucun `catch`
 * silencieux »). Seuls le nom et le message passent, après `clean`, qui retire la valeur
 * exacte du jeton et de l'identifiant : la pile n'est pas transmise, car elle répète le
 * message brut.
 */
function logCaught(
  log: RoutineLog,
  message: string,
  err: unknown,
  clean: (value: string) => string,
): void {
  log({
    message,
    feature: "tickets",
    extra: {
      error_name: err instanceof Error ? err.name : typeof err,
      error: clean(err instanceof Error ? err.message : String(err)).slice(0, 1000),
    },
  });
}

/**
 * - `paused` : 400, routine en pause sur claude.ai ;
 * - `rejected` : 400 pour une autre raison (texte refusé), redirection, ou tout statut
 *   non prévu ;
 * - `token` : 401 ou 403 ;
 * - `not_found` : 404, routine introuvable ;
 * - `rate_limit` : 429.
 *
 * Un 5xx n'est pas un échec : la session a pu partir, le résultat est `unknown` (comme un
 * délai dépassé).
 */
export type RoutineFailureKind = "paused" | "rejected" | "token" | "not_found" | "rate_limit";

export type FireOutcome =
  | {
      kind: "launched";
      /** URL `https://claude.ai/…` de la session, 500 caractères au plus, ou `null`. */
      sessionUrl: string | null;
      /** Réponse 2xx dont le corps ne se lit pas : la raison, pour le journal. */
      note: string | null;
    }
  | {
      kind: "failed";
      failure: RoutineFailureKind;
      status: number;
      /** Minutes à attendre, arrondies au-dessus (429 seulement). */
      retryMinutes: number | null;
      /** Extrait du corps de la réponse, pour le journal. Jamais le jeton. */
      detail: string;
    }
  | {
      kind: "unknown";
      /** Statut HTTP d'une réponse 5xx ; `null` sans réponse (délai, réseau). */
      status: number | null;
      detail: string;
    };

/** Message d'un 5xx, rendu à l'administrateur comme un résultat inconnu. */
export const ROUTINE_SERVER_ERROR_MESSAGE =
  "Claude ne répond pas. Vérifiez sur claude.ai/code avant de relancer.";

/**
 * Minutes annoncées par `Retry-After` (secondes ou date HTTP), arrondies à la minute
 * supérieure, au moins 1. `null` si l'en-tête manque ou ne se lit pas. Pure.
 */
export function retryAfterMinutes(header: string | null, nowMs: number): number | null {
  if (header === null) return null;
  const text = header.trim();
  if (text.length === 0) return null;
  let seconds: number;
  if (/^\d+$/.test(text)) {
    seconds = Number(text);
  } else {
    const at = Date.parse(text);
    if (Number.isNaN(at)) return null;
    seconds = (at - nowMs) / 1000;
  }
  return Math.max(1, Math.ceil(seconds / 60));
}

function excerpt(body: string): string {
  return body.replace(/\s+/g, " ").trim().slice(0, 300);
}

/**
 * L'URL de session gardée : `https://claude.ai/…`, 500 caractères au plus ; toute autre
 * valeur est écartée (P41). Pure.
 */
export function sessionUrlOrNull(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > SESSION_URL_MAX) {
    return null;
  }
  // Valeur illisible rendue par l'API : écartée, la session reste « lancée » sans lien.
  if (!URL.canParse(value)) return null;
  const url = new URL(value);
  return url.protocol === "https:" && url.hostname === "claude.ai" && url.username === ""
    ? value
    : null;
}

/** Une réponse 400 qui dit que la routine est en pause. */
function isPausedBody(body: string): boolean {
  return /\bpause/i.test(body);
}

/**
 * Classe une réponse de l'API. Testée. `body` arrive déjà sans jeton ni identifiant
 * (`fireRoutine` le passe par `withoutSecrets`). Seul effet : un corps 2xx illisible est
 * journalisé par `log`. `clean` est obligatoire : le message d'erreur de `JSON.parse`
 * cite un extrait du corps, qui passe par `clean` avant le journal et `note`.
 */
export function classifyRoutineResponse(
  status: number,
  body: string,
  retryAfterHeader: string | null,
  nowMs: number,
  clean: (value: string) => string,
  log: RoutineLog = logError,
): FireOutcome {
  if (status >= 200 && status < 300) {
    let parsed: Record<string, unknown> = {};
    let note: string | null = null;
    try {
      const json: unknown = JSON.parse(body);
      if (json !== null && typeof json === "object") parsed = json as Record<string, unknown>;
    } catch (err) {
      // La session est créée (2xx) : seul le lien manque. L'appelant l'enregistre sans
      // lien et journalise aussi `note`.
      logCaught(log, "Tickets : réponse de la routine illisible (2xx)", err, clean);
      note = `corps illisible : ${clean(err instanceof Error ? err.message : String(err))}`;
    }
    return {
      kind: "launched",
      sessionUrl: sessionUrlOrNull(parsed.claude_code_session_url),
      note,
    };
  }
  const detail = excerpt(body);
  const failed = (
    failure: RoutineFailureKind,
    retryMinutes: number | null = null,
  ): FireOutcome => ({
    kind: "failed",
    failure,
    status,
    retryMinutes,
    detail,
  });
  if (status === 400) return failed(isPausedBody(body) ? "paused" : "rejected");
  if (status === 401 || status === 403) return failed("token");
  if (status === 404) return failed("not_found");
  if (status === 429) return failed("rate_limit", retryAfterMinutes(retryAfterHeader, nowMs));
  // 500, 503 et tout 5xx : la session a pu être créée avant l'erreur.
  if (status >= 500) return { kind: "unknown", status, detail };
  return failed("rejected");
}

/** Message rendu à l'administrateur pour un échec de l'API (Kass'Dalle). Pure. */
export function routineFailureMessage(
  failure: RoutineFailureKind,
  retryMinutes: number | null,
): string {
  switch (failure) {
    case "paused":
      return "La routine est en pause sur claude.ai. Réactivez-la, puis relancez.";
    case "token":
      return "Le jeton de la routine est refusé. Remplacez-le dans Secret Manager.";
    case "not_found":
      return "Routine introuvable : vérifiez son identifiant dans Secret Manager.";
    case "rate_limit":
      return retryMinutes === null
        ? "Trop de lancements chez Claude. Réessayez plus tard."
        : `Trop de lancements chez Claude. Réessayez dans ${retryMinutes} min.`;
    case "rejected":
      return "Lancement refusé par Claude.";
  }
}

/**
 * Vrai pour l'échec que `fetch` lève sur une réponse 3xx avec `redirect: "error"` (undici :
 * `TypeError`, cause « unexpected redirect »). Pure, testée.
 */
export function isRedirectError(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const cause = (err as Error & { cause?: unknown }).cause;
  const text = `${err.message} ${cause instanceof Error ? cause.message : String(cause ?? "")}`;
  return /redirect/i.test(text);
}

export type RoutineFetch = (input: string, init: RequestInit) => Promise<Response>;

/**
 * Lance la routine avec `text`. Le texte est revérifié contre `LAUNCH_TEXT_PATTERN` : hors
 * motif, lève avant tout appel. Sinon ne lève pas : un délai dépassé ou une panne réseau
 * rendent `unknown` (la session a pu partir), une réponse rend `launched`, `failed` ou
 * `unknown` (5xx). Une redirection (3xx) n'est pas suivie et rend `failed` (`rejected`).
 * Un seul `fetch`, jamais rejoué. Les textes d'erreur sont rendus sans le jeton ni
 * l'identifiant (`withoutSecrets`).
 */
export async function fireRoutine(
  config: RoutineConfig,
  text: string,
  opts: {
    timeoutMs?: number;
    fetchImpl?: RoutineFetch;
    nowMs?: () => number;
    log?: RoutineLog;
  } = {},
): Promise<FireOutcome> {
  if (!LAUNCH_TEXT_PATTERN.test(text)) {
    throw new Error(`texte de lancement refusé : ${JSON.stringify(text)}`);
  }
  const doFetch = opts.fetchImpl ?? fetch;
  const now = opts.nowMs ?? Date.now;
  const clean = (value: string) => withoutSecrets(value, config);
  const log = opts.log ?? logError;
  let response: Response;
  try {
    response = await doFetch(`${API}/${encodeURIComponent(config.id)}/fire`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.token}`,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
      },
      body: JSON.stringify({ text }),
      // Une redirection n'est jamais suivie : elle renverrait le jeton vers une autre
      // adresse.
      redirect: "error",
      signal: AbortSignal.timeout(opts.timeoutMs ?? ROUTINE_TIMEOUT_MS),
    });
  } catch (err) {
    logCaught(log, "Tickets : appel de la routine en échec", err, clean);
    if (isRedirectError(err)) {
      // Le serveur a répondu (3xx) : rien n'est parti vers la routine.
      return {
        kind: "failed",
        failure: "rejected",
        status: 0,
        retryMinutes: null,
        detail: "redirection refusée (3xx), jeton non transmis",
      };
    }
    const name = err instanceof Error ? err.name : "";
    const message = err instanceof Error ? err.message : String(err);
    return {
      kind: "unknown",
      status: null,
      detail: name === "TimeoutError" || name === "AbortError" ? "délai dépassé" : clean(message),
    };
  }
  let body: string;
  try {
    body = await response.text();
  } catch (err) {
    logCaught(log, "Tickets : corps de la réponse de la routine illisible", err, clean);
    // Statut reçu, corps perdu : le statut décide seul. Un succès reste un succès, sans
    // lien ; la raison part dans `note` ou `detail`.
    body = `corps illisible : ${err instanceof Error ? err.message : String(err)}`;
  }
  const outcome = classifyRoutineResponse(
    response.status,
    clean(body),
    response.headers.get("retry-after"),
    now(),
    clean,
    log,
  );
  if (outcome.kind === "launched" && outcome.note !== null) {
    return { ...outcome, note: clean(outcome.note) };
  }
  return outcome;
}
