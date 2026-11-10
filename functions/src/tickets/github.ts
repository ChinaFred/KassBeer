/**
 * Client REST GitHub des tickets, par `fetch`, sans SDK (P26). Il se construit à l'appel,
 * avec le jeton lu dans le secret : rien n'est ouvert au chargement du module.
 *
 * De GitHub, le serveur ne lit que l'état et les étiquettes des Issues, le corps des
 * Issues `source:app` du compte propriétaire (pour y reconnaître la ligne « Référence »,
 * sans rien en garder), leurs commentaires (pour la seule réponse du compte
 * propriétaire), les événements de fermeture, les PR d'un commit et `app/pubspec.yaml` à
 * ce commit (P24).
 *
 * Chaque échec lève une `GithubError` classée. Le message ne contient jamais le jeton
 * (P25) : il reprend le code HTTP et le message de GitHub.
 */

import { GITHUB_MAINTAINER_ID, GITHUB_REPO_FULL_NAME } from "../config";
import { redactSecrets } from "../logging";
import {
  LABEL_SOURCE_APP,
  referenceLine,
  type CommentView,
  type IssueView,
  type MergedPrCandidate,
} from "./model";

const API = "https://api.github.com";
const REPO_PATH = `/repos/${GITHUB_REPO_FULL_NAME}`;
const TIMEOUT_MS = 15_000;
const USER_AGENT = "KassBeer-Tickets";
const MAX_PAGES = 5;

/**
 * - `token` : secret vide, jeton refusé (401), 403 hors limite de débit, 404 sur le dépôt ;
 * - `rate_limit` : limite de débit (403 quota épuisé ou limite secondaire, 429) ;
 * - `not_found` : Issue absente (404 ou 410), dépôt joignable ;
 * - `network` : délai dépassé, connexion refusée ;
 * - `other` : toute autre réponse.
 */
export type GithubErrorKind = "token" | "rate_limit" | "not_found" | "network" | "other";

export class GithubError extends Error {
  constructor(
    readonly kind: GithubErrorKind,
    readonly status: number | null,
    message: string,
  ) {
    super(redactSecrets(message).slice(0, 300));
    this.name = "GithubError";
  }
}

/** Classe une réponse en échec. Pure. */
export function classifyGithubFailure(
  status: number,
  headers: { rateLimitRemaining: string | null; retryAfter: string | null },
  message: string,
  repoLevel: boolean,
): GithubErrorKind {
  if (status === 401) return "token";
  if (status === 429) return "rate_limit";
  if (status === 403) {
    const limited =
      headers.rateLimitRemaining === "0" ||
      (headers.retryAfter !== null && headers.retryAfter.trim().length > 0) ||
      /rate limit/i.test(message);
    return limited ? "rate_limit" : "token";
  }
  if (status === 404) return repoLevel ? "token" : "not_found";
  if (status === 410) return "not_found";
  return "other";
}

export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

function str(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

/** Noms des étiquettes d'une Issue, qu'elles arrivent en objets ou en chaînes. Pure. */
export function labelNames(labels: unknown): string[] {
  if (!Array.isArray(labels)) return [];
  return labels
    .map((l) => (typeof l === "string" ? l : (l as { name?: unknown } | null)?.name))
    .filter((n): n is string => typeof n === "string");
}

/** Lit une Issue rendue par l'API, ou `null` si son numéro manque. Pure. */
export function readIssue(raw: Record<string, unknown>): IssueView | null {
  if (typeof raw.number !== "number" || !Number.isSafeInteger(raw.number)) return null;
  return {
    number: raw.number,
    state: raw.state === "closed" ? "closed" : "open",
    stateReason: str(raw.state_reason),
    labels: labelNames(raw.labels),
    isPullRequest: raw.pull_request != null,
    updatedAt: str(raw.updated_at),
    comments: typeof raw.comments === "number" && raw.comments >= 0 ? raw.comments : 0,
  };
}

/** Lit un commentaire rendu par l'API. Pure. */
export function readComment(raw: Record<string, unknown>): CommentView {
  const user = raw.user as { id?: unknown } | null | undefined;
  return {
    id: typeof raw.id === "number" ? raw.id : null,
    authorId: typeof user?.id === "number" ? user.id : null,
    body: str(raw.body),
    createdAt: str(raw.created_at),
    updatedAt: str(raw.updated_at),
  };
}

/** Lit une PR rendue par `GET /commits/{sha}/pulls`, ou `null`. Pure. */
export function readMergedPrCandidate(raw: Record<string, unknown>): MergedPrCandidate | null {
  if (typeof raw.number !== "number" || !Number.isSafeInteger(raw.number)) return null;
  const user = raw.user as { id?: unknown } | null | undefined;
  const base = raw.base as { repo?: { full_name?: unknown } | null } | null | undefined;
  return {
    number: raw.number,
    mergedAt: str(raw.merged_at),
    mergeCommitSha: str(raw.merge_commit_sha),
    body: str(raw.body),
    baseRepoFullName: str(base?.repo?.full_name),
    authorId: typeof user?.id === "number" ? user.id : null,
    authorAssociation: str(raw.author_association),
  };
}

/**
 * Vrai si l'Issue rendue par l'API est celle du ticket : Issue (pas une PR), créée par le
 * compte `maintainerId` (le compte du jeton), dont une ligne du corps est exactement la
 * ligne « Référence » du ticket. Pure.
 */
export function isIssueOfTicket(
  raw: Record<string, unknown>,
  ticketId: string,
  maintainerId: number,
): boolean {
  if (typeof raw.number !== "number" || typeof raw.html_url !== "string") return false;
  if (raw.pull_request != null) return false;
  const user = raw.user as { id?: unknown } | null | undefined;
  if (user?.id !== maintainerId) return false;
  if (typeof raw.body !== "string") return false;
  const marker = referenceLine(ticketId);
  return raw.body.split(/\r?\n/).some((line) => line.trim() === marker);
}

export interface GithubClient {
  /**
   * Dernier en-tête `github-authentication-token-expiration` lu sur une réponse réussie :
   * `undefined` avant toute réponse réussie, `null` si la réponse ne le portait pas.
   */
  readonly tokenExpirationHeader: string | null | undefined;
  createIssue(issue: {
    title: string;
    body: string;
    labels: string[];
  }): Promise<{ number: number; url: string }>;
  findIssueByReference(
    ticketId: string,
    since: string | null,
  ): Promise<{ number: number; url: string } | null>;
  getIssue(issueNumber: number): Promise<IssueView>;
  listIssuesUpdatedSince(
    label: string,
    since: string | null,
    perPage: number,
  ): Promise<IssueView[]>;
  lastCommentsFirst(issueNumber: number, commentCount: number): AsyncGenerator<CommentView[]>;
  listIssueEvents(issueNumber: number): Promise<unknown[]>;
  pullsForCommit(sha: string): Promise<MergedPrCandidate[]>;
  fileAtCommit(path: string, sha: string): Promise<string | null>;
}

/** Construit le client pour un jeton. `fetchImpl` est remplacé par les tests. */
export function githubClient(token: string, fetchImpl: FetchLike = fetch): GithubClient {
  let tokenExpirationHeader: string | null | undefined = undefined;

  async function request<T>(
    method: "GET" | "POST",
    path: string,
    opts: { body?: unknown; repoLevel?: boolean } = {},
  ): Promise<T> {
    let response: Response;
    try {
      response = await fetchImpl(`${API}${path}`, {
        method,
        headers: {
          accept: "application/vnd.github+json",
          authorization: `Bearer ${token}`,
          "x-github-api-version": "2022-11-28",
          "user-agent": USER_AGENT,
          ...(opts.body !== undefined ? { "content-type": "application/json" } : {}),
        },
        body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (err) {
      throw new GithubError(
        "network",
        null,
        `GitHub injoignable : ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    if (!response.ok) {
      let detail: string;
      try {
        const json = (await response.json()) as { message?: unknown };
        detail = typeof json.message === "string" ? json.message : "";
      } catch (parseErr) {
        detail = `réponse illisible (${parseErr instanceof Error ? parseErr.name : "?"})`;
      }
      const kind = classifyGithubFailure(
        response.status,
        {
          rateLimitRemaining: response.headers.get("x-ratelimit-remaining"),
          retryAfter: response.headers.get("retry-after"),
        },
        detail,
        opts.repoLevel === true,
      );
      throw new GithubError(
        kind,
        response.status,
        `GitHub HTTP ${response.status}${detail ? ` : ${detail}` : ""}`,
      );
    }
    tokenExpirationHeader = response.headers.get("github-authentication-token-expiration");
    return (await response.json()) as T;
  }

  return {
    get tokenExpirationHeader() {
      return tokenExpirationHeader;
    },

    async createIssue(issue) {
      const created = await request<{ number: number; html_url: string }>(
        "POST",
        `${REPO_PATH}/issues`,
        {
          body: issue,
          repoLevel: true,
        },
      );
      return { number: created.number, url: created.html_url };
    },

    /**
     * L'Issue déjà créée pour ce ticket (P26), lue dans la liste des Issues `source:app`
     * modifiées depuis `since`, par ordre de création, 500 au plus. La liste ne dépend pas
     * de l'index de recherche de GitHub, qui a quelques minutes de retard. Seule compte une
     * Issue du compte propriétaire dont le corps porte la ligne « Référence » exacte.
     */
    async findIssueByReference(ticketId, since) {
      for (let page = 1; page <= MAX_PAGES; page++) {
        const params = new URLSearchParams({
          labels: LABEL_SOURCE_APP,
          state: "all",
          sort: "created",
          direction: "asc",
          per_page: "100",
          page: String(page),
        });
        if (since !== null) params.set("since", since);
        const batch = await request<Array<Record<string, unknown>>>(
          "GET",
          `${REPO_PATH}/issues?${params.toString()}`,
          { repoLevel: true },
        );
        for (const item of batch) {
          if (isIssueOfTicket(item, ticketId, GITHUB_MAINTAINER_ID)) {
            return { number: item.number as number, url: item.html_url as string };
          }
        }
        if (batch.length < 100) break;
      }
      return null;
    },

    async getIssue(issueNumber) {
      const raw = await request<Record<string, unknown>>(
        "GET",
        `${REPO_PATH}/issues/${issueNumber}`,
      );
      const issue = readIssue(raw);
      if (issue === null) throw new GithubError("other", null, `Issue #${issueNumber} illisible`);
      return issue;
    },

    /** Issues d'une étiquette modifiées depuis `since`, les plus anciennes d'abord, PR écartées. */
    async listIssuesUpdatedSince(label, since, perPage) {
      const params = new URLSearchParams({
        labels: label,
        state: "all",
        sort: "updated",
        direction: "asc",
        per_page: String(perPage),
      });
      if (since !== null) params.set("since", since);
      const raw = await request<Array<Record<string, unknown>>>(
        "GET",
        `${REPO_PATH}/issues?${params.toString()}`,
        { repoLevel: true },
      );
      return raw.map(readIssue).filter((i): i is IssueView => i !== null && !i.isPullRequest);
    },

    /**
     * Pages de commentaires, de la dernière à la première (`MAX_PAGES` au plus) ; chaque
     * page dans l'ordre chronologique. L'appelant s'arrête à la première réponse trouvée.
     */
    async *lastCommentsFirst(issueNumber, commentCount) {
      const lastPage = Math.max(1, Math.ceil(commentCount / 100));
      for (let page = lastPage; page >= 1 && lastPage - page < MAX_PAGES; page--) {
        const batch = await request<Array<Record<string, unknown>>>(
          "GET",
          `${REPO_PATH}/issues/${issueNumber}/comments?per_page=100&page=${page}`,
        );
        yield batch.map(readComment);
      }
    },

    async listIssueEvents(issueNumber) {
      const events: unknown[] = [];
      for (let page = 1; page <= MAX_PAGES; page++) {
        const batch = await request<unknown[]>(
          "GET",
          `${REPO_PATH}/issues/${issueNumber}/events?per_page=100&page=${page}`,
        );
        events.push(...batch);
        if (batch.length < 100) break;
      }
      return events;
    },

    async pullsForCommit(sha) {
      const raw = await request<Array<Record<string, unknown>>>(
        "GET",
        `${REPO_PATH}/commits/${sha}/pulls?per_page=30`,
      );
      return raw.map(readMergedPrCandidate).filter((p): p is MergedPrCandidate => p !== null);
    },

    /** Contenu texte d'un fichier à un commit, ou `null` s'il n'est pas lisible. */
    async fileAtCommit(path, sha) {
      const file = await request<{ content?: unknown; encoding?: unknown }>(
        "GET",
        `${REPO_PATH}/contents/${path}?ref=${encodeURIComponent(sha)}`,
      );
      if (typeof file.content !== "string" || file.encoding !== "base64") return null;
      return Buffer.from(file.content, "base64").toString("utf8");
    },
  };
}
