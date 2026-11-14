/**
 * Admin › Journaux : callable `queryLogs` (ADR-011, J2, P49). Lit la sortie des Cloud
 * Functions dans Cloud Logging par l'API REST `entries:list`, par `fetch` (leçon 5, P26).
 *
 * 1. `requireAdmin` (P30), avant toute lecture des arguments.
 * 2. Arguments lus contre une liste fermée ou un motif ; refus `invalid-argument` avec
 *    `details.reason` et `details.field`.
 * 3. Filtre construit par le serveur seul : la clause `BASE_CLAUSE` toujours en tête,
 *    chaque valeur du client entre guillemets, échappée. Le filtre n'est jamais rendu ni
 *    journalisé.
 * 4. Jeton du compte d'exécution lu au serveur de métadonnées, mémorisé jusqu'à son
 *    échéance moins 60 s ; un seul appel à `entries:list`.
 * 5. Réponse réduite : textes passés par `redactSecrets`, `payload` coupé à 8 000
 *    caractères. Les adresses e-mail restent visibles (choix du 2026-11-14).
 *
 * `nextPageToken` rendu au client porte aussi la période et son début (`<période>|<ISO>|<jeton
 * de l'API>`) : la page suivante rejoue le même filtre, que l'API exige identique, et un
 * début plus ancien que la période (plus cinq minutes) est refusé.
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireAdmin, requireBoundedText, type AuthLike, type MemberLookup } from "../auth";
import { QUERYABLE_FUNCTIONS, QUERYABLE_PERIODS_MINUTES, QUERYABLE_SEVERITIES } from "../config";
import { logError, redactSecrets, type LogEntry } from "../logging";

/** Clause imposée en tête de chaque filtre : sortie des fonctions seule (ADR-011, P49). */
export const BASE_CLAUSE =
  'resource.type="cloud_run_revision" AND ' +
  '(LOG_ID("run.googleapis.com/stdout") OR LOG_ID("run.googleapis.com/stderr"))';

/** Champs de `jsonPayload` filtrés, écrits par `logging.ts` (P50, `logs.test.ts`). */
export const FILTERED_FIELDS = { ticketId: "ticketId", message: "message" } as const;

export const PAGE_SIZE = 50;
export const TEXT_MAX_CHARS = 8000;
export const LOGS_TIMEOUT_MS = 20_000;
export const PAGE_TOKEN_MAX = 2000;
/** Marge d'une page suivante au-delà de la période : le temps de lire la page. */
export const PAGE_TOKEN_MARGIN_MS = 5 * 60_000;
const METADATA_TIMEOUT_MS = 5_000;
const TOKEN_MARGIN_MS = 60_000;
const ENTRIES_URL = "https://logging.googleapis.com/v2/entries:list";
const TOKEN_URL =
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";

const TICKET_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
/** Vrai si [text] contient un caractère de contrôle (C0, C1) ou un séparateur de ligne. */
function hasControlChar(text: string): boolean {
  for (const ch of text) {
    const c = ch.codePointAt(0) ?? 0;
    if (c < 0x20 || (c >= 0x7f && c <= 0x9f) || c === 0x2028 || c === 0x2029) return true;
  }
  return false;
}
const ISO_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

export const MESSAGES = {
  quota: "Quota de lecture des journaux atteint, réessayez dans une minute.",
  iam: "Lecture des journaux non autorisée : rôle IAM manquant.",
  emulator: "Journaux non disponibles dans l'émulateur.",
  unavailable: "Journaux indisponibles pour l'instant.",
} as const;

export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export interface LogsQuery {
  severity?: (typeof QUERYABLE_SEVERITIES)[number];
  functionName?: (typeof QUERYABLE_FUNCTIONS)[number];
  ticketId?: string;
  freeText?: string;
  periodMinutes: number;
  pageToken?: { since: string; token: string };
}

export interface LogsEntry {
  timestamp: string;
  severity: string;
  functionName: string;
  message: string;
  insertId: string;
  payload: string;
  payloadTruncated: boolean;
  messageTruncated: boolean;
}

export interface LogsResponse {
  entries: LogsEntry[];
  nextPageToken: string | null;
  functions: string[];
  /** Caractères gardés de `message` et de `payload` : le client affiche cette valeur. */
  maxChars: number;
}

function invalid(field: string, reason: string): never {
  throw new HttpsError("invalid-argument", reason, { field, reason });
}

/** Valeur d'une liste fermée, ou `undefined` si absente. Pure. */
function oneOf<T extends string | number>(
  value: unknown,
  allowed: readonly T[],
  field: string,
  label: string,
): T | undefined {
  if (value === undefined || value === null) return undefined;
  if (!allowed.includes(value as T)) invalid(field, `${label} : valeur hors liste.`);
  return value as T;
}

/** Arguments de `queryLogs`, contrôlés (P49). Lève `invalid-argument`. Pure, sauf `now`. */
export function readLogsQuery(data: unknown, now: Date): LogsQuery {
  const d = (data !== null && typeof data === "object" ? data : {}) as Record<string, unknown>;
  const severity = oneOf(d.severity, QUERYABLE_SEVERITIES, "severity", "Gravité");
  const functionName = oneOf(d.functionName, QUERYABLE_FUNCTIONS, "functionName", "Fonction");
  const periodMinutes =
    oneOf(d.periodMinutes, QUERYABLE_PERIODS_MINUTES, "periodMinutes", "Période") ?? 60;

  const ticketId = requireBoundedText(d.ticketId, {
    field: "ticketId",
    max: 128,
    label: "Ticket",
  });
  if (ticketId !== undefined && !TICKET_ID_PATTERN.test(ticketId)) {
    invalid("ticketId", "Identifiant de ticket invalide.");
  }

  const freeText = requireBoundedText(d.freeText, {
    field: "freeText",
    max: 100,
    label: "Texte à chercher",
  });
  if (freeText !== undefined && (freeText.length === 0 || hasControlChar(freeText))) {
    invalid("freeText", "Texte de 1 à 100 caractères, sans saut de ligne.");
  }

  const rawToken = requireBoundedText(d.pageToken, {
    field: "pageToken",
    max: PAGE_TOKEN_MAX,
    label: "Page suivante",
  });
  let pageToken: LogsQuery["pageToken"];
  let period: number = periodMinutes;
  if (rawToken !== undefined) {
    const parsed = readPageToken(rawToken, now);
    // La période de la page suivante est celle du jeton ; un argument contraire est refusé.
    if (parsed === null || (d.periodMinutes != null && d.periodMinutes !== parsed.period)) {
      invalid("pageToken", "Page suivante illisible : relancez la recherche.");
    }
    period = parsed.period;
    pageToken = { since: parsed.since, token: parsed.token };
  }
  return { severity, functionName, ticketId, freeText, periodMinutes: period, pageToken };
}

/**
 * Jeton de page suivante rendu par `queryLogs` : `<période>|<début ISO>|<jeton de l'API>`.
 * `null` si la période sort de la liste fermée, si la date est illisible, future, ou plus
 * ancienne que `now` − période − `PAGE_TOKEN_MARGIN_MS`, ou si le jeton de l'API est vide.
 * Pure.
 */
export function readPageToken(
  raw: string,
  now: Date,
): { period: number; since: string; token: string } | null {
  const first = raw.indexOf("|");
  const second = first < 0 ? -1 : raw.indexOf("|", first + 1);
  if (second < 0) return null;
  const periodText = raw.slice(0, first);
  const since = raw.slice(first + 1, second);
  const token = raw.slice(second + 1);
  const period = /^[0-9]{1,5}$/.test(periodText) ? Number(periodText) : NaN;
  if (!(QUERYABLE_PERIODS_MINUTES as readonly number[]).includes(period)) return null;
  const sinceMs = Date.parse(since);
  const oldest = now.getTime() - period * 60_000 - PAGE_TOKEN_MARGIN_MS;
  if (
    !ISO_PATTERN.test(since) ||
    Number.isNaN(sinceMs) ||
    sinceMs > now.getTime() ||
    sinceMs < oldest ||
    token.length === 0 ||
    hasControlChar(token)
  ) {
    return null;
  }
  return { period, since, token };
}

/** Texte entre guillemets du langage de requête de Cloud Logging. Pure. */
export function quoted(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/** Début de la période : celui de la page précédente, sinon `now` − période. Pure. */
export function sinceOf(query: LogsQuery, now: Date): string {
  return (
    query.pageToken?.since ?? new Date(now.getTime() - query.periodMinutes * 60_000).toISOString()
  );
}

/** Filtre de `entries:list`, `BASE_CLAUSE` en tête, clauses jointes par `AND`. Pure. */
export function buildFilter(query: LogsQuery, since: string): string {
  const clauses: string[] = [BASE_CLAUSE];
  if (query.severity === "DEBUG") clauses.push("severity=DEBUG");
  else if (query.severity !== undefined) clauses.push(`severity>=${query.severity}`);
  if (query.functionName !== undefined) {
    clauses.push(`resource.labels.service_name=${quoted(query.functionName.toLowerCase())}`);
  }
  if (query.ticketId !== undefined) {
    clauses.push(`jsonPayload.${FILTERED_FIELDS.ticketId}=${quoted(query.ticketId)}`);
  }
  if (query.freeText !== undefined) {
    clauses.push(`jsonPayload.${FILTERED_FIELDS.message}:${quoted(query.freeText)}`);
  }
  clauses.push(`timestamp>=${quoted(since)}`);
  return clauses.join(" AND ");
}

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/** Une entrée de l'API réduite à ce que l'écran affiche. Pure. */
export function toEntry(raw: unknown): LogsEntry | null {
  if (raw === null || typeof raw !== "object") return null;
  const e = raw as Record<string, unknown>;
  const json =
    e.jsonPayload !== null && typeof e.jsonPayload === "object"
      ? { ...(e.jsonPayload as Record<string, unknown>) }
      : null;
  const message = json !== null ? str(json.message) : str(e.textPayload);
  if (json !== null) delete json.message;
  const serialized =
    json === null || Object.keys(json).length === 0 ? "" : JSON.stringify(json, null, 2);
  const labels = (e.resource as { labels?: Record<string, unknown> } | undefined)?.labels;
  // Nettoyer avant de couper : une coupe au milieu d'un jeton le rendrait méconnaissable.
  const cleanMessage = redactSecrets(message);
  const cleanPayload = redactSecrets(serialized);
  return {
    timestamp: str(e.timestamp),
    severity: str(e.severity) || "DEFAULT",
    functionName: redactSecrets(str(labels?.service_name)),
    message: cleanMessage.slice(0, TEXT_MAX_CHARS),
    messageTruncated: cleanMessage.length > TEXT_MAX_CHARS,
    insertId: str(e.insertId),
    payload: cleanPayload.slice(0, TEXT_MAX_CHARS),
    payloadTruncated: cleanPayload.length > TEXT_MAX_CHARS,
  };
}

/** Jeton d'accès mémorisé : vide au démarrage, rempli au premier appel (P26). */
export interface TokenCache {
  value: string | null;
  expiresAt: number;
}
const moduleTokenCache: TokenCache = { value: null, expiresAt: 0 };

export interface LogsDeps {
  lookup?: MemberLookup;
  fetchImpl?: FetchLike;
  now?: () => Date;
  env?: Record<string, string | undefined>;
  tokenCache?: TokenCache;
  log?: (entry: LogEntry) => void;
}

function unavailable(): HttpsError {
  return new HttpsError("unavailable", MESSAGES.unavailable, { reason: "logging_unavailable" });
}

async function accessToken(doFetch: FetchLike, cache: TokenCache, nowMs: number): Promise<string> {
  if (cache.value !== null && nowMs < cache.expiresAt) return cache.value;
  const res = await doFetch(TOKEN_URL, {
    method: "GET",
    headers: { "Metadata-Flavor": "Google" },
    redirect: "error",
    signal: AbortSignal.timeout(METADATA_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`serveur de métadonnées : statut ${res.status}`);
  const body = (await res.json()) as { access_token?: unknown; expires_in?: unknown };
  if (typeof body.access_token !== "string" || typeof body.expires_in !== "number") {
    throw new Error("serveur de métadonnées : réponse illisible");
  }
  cache.value = body.access_token;
  cache.expiresAt = nowMs + body.expires_in * 1000 - TOKEN_MARGIN_MS;
  return body.access_token;
}

/** `queryLogs` (ADR-011, J2, P49). */
export async function handleQueryLogsCall(
  req: AuthLike & { data?: unknown },
  deps: LogsDeps = {},
): Promise<LogsResponse> {
  await requireAdmin(req, deps.lookup);
  const now = (deps.now ?? (() => new Date()))();
  const query = readLogsQuery(req.data, now);
  const env = deps.env ?? process.env;
  const log = deps.log ?? logError;
  if (env.FUNCTIONS_EMULATOR === "true") {
    throw new HttpsError("failed-precondition", MESSAGES.emulator, { reason: "emulator" });
  }
  const project = env.GCLOUD_PROJECT ?? env.GOOGLE_CLOUD_PROJECT ?? "";
  if (!PROJECT_PATTERN.test(project)) {
    log({ message: "Journaux : projet d'exécution inconnu", feature: "logs" });
    throw unavailable();
  }
  const doFetch = deps.fetchImpl ?? fetch;

  const cache = deps.tokenCache ?? moduleTokenCache;
  let token: string;
  try {
    token = await accessToken(doFetch, cache, now.getTime());
  } catch (err) {
    log({ message: "Journaux : jeton d'accès non obtenu", feature: "logs", error: err });
    throw unavailable();
  }

  const since = sinceOf(query, now);
  const body: Record<string, unknown> = {
    resourceNames: [`projects/${project}`],
    filter: buildFilter(query, since),
    orderBy: "timestamp desc",
    pageSize: PAGE_SIZE,
  };
  if (query.pageToken !== undefined) body.pageToken = query.pageToken.token;

  let res: Response;
  try {
    res = await doFetch(ENTRIES_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      redirect: "error",
      signal: AbortSignal.timeout(LOGS_TIMEOUT_MS),
    });
  } catch (err) {
    log({ message: "Journaux : appel de Cloud Logging en échec", feature: "logs", error: err });
    throw unavailable();
  }
  // Le corps d'une réponse en erreur peut citer le filtre : seul le statut est journalisé.
  if (!res.ok) {
    log({
      message: "Journaux : Cloud Logging refuse",
      feature: "logs",
      extra: { status: res.status },
    });
    if (res.status === 429) {
      throw new HttpsError("resource-exhausted", MESSAGES.quota, { reason: "quota" });
    }
    if (res.status === 401 || res.status === 403) {
      // Jeton refusé : l'appel suivant en redemande un.
      if (res.status === 401) clearToken(cache);
      throw new HttpsError("failed-precondition", MESSAGES.iam, { reason: "iam" });
    }
    throw unavailable();
  }

  let parsed: { entries?: unknown; nextPageToken?: unknown };
  try {
    parsed = (await res.json()) as typeof parsed;
  } catch (err) {
    log({ message: "Journaux : réponse de Cloud Logging illisible", feature: "logs", error: err });
    throw unavailable();
  }
  const entries = (Array.isArray(parsed.entries) ? parsed.entries : [])
    .map(toEntry)
    .filter((e): e is LogsEntry => e !== null);
  const next =
    typeof parsed.nextPageToken === "string" && parsed.nextPageToken.length > 0
      ? `${query.periodMinutes}|${since}|${parsed.nextPageToken}`
      : null;
  // Un jeton de suite plus long que la borne de `pageToken` ne pourrait pas revenir :
  // la panne s'affiche au lieu d'une fausse « fin des journaux ».
  if (next !== null && next.length > PAGE_TOKEN_MAX) {
    log({
      message: "Journaux : jeton de page suivante trop long",
      feature: "logs",
      extra: { length: next.length },
    });
    throw unavailable();
  }
  return {
    entries,
    nextPageToken: next,
    functions: [...QUERYABLE_FUNCTIONS],
    maxChars: TEXT_MAX_CHARS,
  };
}

function clearToken(cache: TokenCache): void {
  cache.value = null;
  cache.expiresAt = 0;
}
