/**
 * Client REST GitHub des tickets, par `fetch`, sans SDK (P26). Il se construit à l'appel,
 * avec le jeton lu dans le secret : rien n'est ouvert au chargement du module.
 *
 * De GitHub, le serveur ne lit que l'état et les étiquettes des Issues, le corps des
 * Issues `source:app` du compte propriétaire (pour y reconnaître la ligne « Référence »,
 * sans rien en garder), leurs commentaires (pour la seule réponse du compte
 * propriétaire, et ses analyses et précisions, P32), les événements de fermeture, les PR
 * d'un commit et `app/pubspec.yaml` à ce commit (P24). Pour la livraison (T5, P24, P46) :
 * PR ouvertes (numéro, état, brouillon, auteur, tête, corps lu pour `closingIssueNumbers`
 * et jamais gardé), chemins des fichiers d'une PR, runs d'un commit (identifiant, nom,
 * chemin, événement, état, conclusion, dates). Il écrit l'Issue, les commentaires des
 * décisions (T2) et des précisions (T3), leurs étiquettes et leur fermeture ; rien pour une
 * livraison.
 *
 * Chaque échec lève une `GithubError` classée. Le message ne contient jamais le jeton
 * (P25) : il reprend le code HTTP et le message de GitHub.
 */

import { GITHUB_MAINTAINER_ID, GITHUB_REPO_FULL_NAME } from "../config";
import { logError, redactSecrets } from "../logging";
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
/** Pages de 100 fichiers lues au plus pour une PR (P43) : au-delà, la liste est tronquée. */
export const MAX_FILE_PAGES = 10;

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

/**
 * 403 sur `GET /actions/runs` : la permission « Actions : lecture » manque au jeton, qui sert
 * par ailleurs. Panne à part (`kind` `other`, jamais `token`) : elle ne pose pas
 * `token_invalid_since` (décision de l'utilisateur du 2026-11-14, P25).
 */
export class GithubActionsForbidden extends GithubError {
  constructor() {
    super(
      "other",
      403,
      "GitHub refuse la lecture des runs de la CI : ajoutez « Actions : lecture » au jeton GITHUB_TICKETS_TOKEN.",
    );
    this.name = "GithubActionsForbidden";
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

/** Une pull request telle que la livraison la lit (liste ou détail, P24). */
export interface PullRequestView {
  number: number;
  /** `open` ou `closed`, `null` si illisible. */
  state: string | null;
  draft: boolean;
  /** Corps, lu pour `closingIssueNumbers` seul : jamais écrit dans Firestore (P24). */
  body: string | null;
  authorId: number | null;
  /** `head.repo.full_name`, `null` pour une copie supprimée. */
  headRepoFullName: string | null;
  headRef: string | null;
  headSha: string | null;
}

/** Lit une PR rendue par `GET /pulls` ou `GET /pulls/{n}`, ou `null`. Pure. */
export function readPullRequest(raw: Record<string, unknown>): PullRequestView | null {
  if (typeof raw.number !== "number" || !Number.isSafeInteger(raw.number)) return null;
  const user = raw.user as { id?: unknown } | null | undefined;
  const head = raw.head as
    { ref?: unknown; sha?: unknown; repo?: { full_name?: unknown } | null } | null | undefined;
  return {
    number: raw.number,
    state: str(raw.state),
    draft: raw.draft === true,
    body: str(raw.body),
    authorId: typeof user?.id === "number" ? user.id : null,
    headRepoFullName: str(head?.repo?.full_name),
    headRef: str(head?.ref),
    headSha: str(head?.sha),
  };
}

/** Un fichier d'une PR (`GET /pulls/{n}/files`) : chemin et ancien chemin d'un renommage. */
export interface PullRequestFileView {
  filename: string | null;
  previousFilename: string | null;
}

/** Un run de GitHub Actions, tel que la livraison le lit (P24). */
export interface CiRunView {
  id: number | null;
  name: string | null;
  /** Chemin du fichier du workflow (`.github/workflows/ci.yml`). */
  path: string | null;
  /** Événement qui l'a lancé (`push`, `pull_request`…). */
  event: string | null;
  headSha: string | null;
  /** Dépôt de la tête (`head_repository.full_name`) : seuls les runs de ce dépôt comptent. */
  headRepoFullName: string | null;
  /** `queued`, `in_progress`, `completed`… */
  status: string | null;
  /** `success`, `failure`, `cancelled`… ; `null` tant que le run n'est pas fini. */
  conclusion: string | null;
  createdAt: string | null;
  updatedAt: string | null;
}

/** Lit un run rendu par `GET /actions/runs` ou porté par un événement `workflow_run`. Pure. */
export function readCiRun(raw: Record<string, unknown>): CiRunView {
  return {
    id: typeof raw.id === "number" ? raw.id : null,
    name: str(raw.name),
    path: str(raw.path),
    event: str(raw.event),
    headSha: str(raw.head_sha),
    headRepoFullName: str((raw.head_repository as { full_name?: unknown } | null)?.full_name),
    status: str(raw.status),
    conclusion: str(raw.conclusion),
    createdAt: str(raw.created_at),
    updatedAt: str(raw.updated_at),
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
  recentComments(issueNumber: number, commentCount: number): Promise<CommentView[]>;
  listIssueEvents(issueNumber: number): Promise<unknown[]>;
  pullsForCommit(sha: string): Promise<MergedPrCandidate[]>;
  fileAtCommit(path: string, sha: string): Promise<string | null>;
  getComment(commentId: number): Promise<CommentView | null>;
  createComment(issueNumber: number, body: string): Promise<{ id: number | null }>;
  addLabels(issueNumber: number, labels: string[]): Promise<void>;
  removeLabel(issueNumber: number, label: string): Promise<"removed" | "absent">;
  closeIssue(issueNumber: number, stateReason: "completed" | "not_planned"): Promise<void>;
  /** PR ouvertes du dépôt, `MAX_PAGES` pages de 100 ; `complete` faux si tronquée (P45). */
  listOpenPullRequests(): Promise<{ prs: PullRequestView[]; complete: boolean }>;
  getPullRequest(prNumber: number): Promise<PullRequestView>;
  /** Fichiers d'une PR, `MAX_FILE_PAGES` pages de 100 ; `complete` faux au-delà (P43). */
  listPullRequestFiles(
    prNumber: number,
  ): Promise<{ files: PullRequestFileView[]; complete: boolean }>;
  /** Runs de GitHub Actions d'un commit (100 au plus). */
  listRunsForCommit(headSha: string): Promise<CiRunView[]>;
}

/** Construit le client pour un jeton. `fetchImpl` est remplacé par les tests. */
export function githubClient(token: string, fetchImpl: FetchLike = fetch): GithubClient {
  let tokenExpirationHeader: string | null | undefined = undefined;

  async function request<T>(
    method: "GET" | "POST" | "PATCH" | "DELETE",
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

    /**
     * Les 500 derniers commentaires au plus (`MAX_PAGES` pages de 100, de la dernière à la
     * première), rendus dans l'ordre chronologique. Sert au relevé des analyses (P32) et
     * de la réponse « Réponse : » en une seule lecture.
     */
    async recentComments(issueNumber, commentCount) {
      const pages: CommentView[][] = [];
      for await (const page of this.lastCommentsFirst(issueNumber, commentCount)) {
        pages.unshift(page);
      }
      return pages.flat();
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

    /**
     * Un commentaire par son identifiant, ou `null` s'il n'existe plus (404 ou 410). Sert
     * à reconnaître le commentaire d'une décision reprise sans relire toutes les pages.
     */
    async getComment(commentId) {
      try {
        const raw = await request<Record<string, unknown>>(
          "GET",
          `${REPO_PATH}/issues/comments/${commentId}`,
        );
        return readComment(raw);
      } catch (err) {
        if (!(err instanceof GithubError) || err.kind !== "not_found") throw err;
        logError({
          message: `Tickets : commentaire ${commentId} introuvable sur GitHub (HTTP ${err.status})`,
          feature: "tickets",
          error: err,
        });
        return null;
      }
    },

    /** Commentaire d'une décision (T2). Rend son identifiant, gardé sur la décision. */
    async createComment(issueNumber, body) {
      const created = await request<{ id?: unknown }>(
        "POST",
        `${REPO_PATH}/issues/${issueNumber}/comments`,
        { body: { body } },
      );
      return { id: typeof created.id === "number" ? created.id : null };
    },

    /** Ajoute des étiquettes ; celles déjà posées restent (l'API ne les duplique pas). */
    async addLabels(issueNumber, labels) {
      await request<unknown>("POST", `${REPO_PATH}/issues/${issueNumber}/labels`, {
        body: { labels },
      });
    },

    /**
     * Retire une étiquette. Rend `absent` quand GitHub répond 404 (étiquette déjà
     * retirée) : le résultat voulu est atteint, et l'écart est journalisé.
     */
    async removeLabel(issueNumber, label) {
      try {
        await request<unknown>(
          "DELETE",
          `${REPO_PATH}/issues/${issueNumber}/labels/${encodeURIComponent(label)}`,
        );
        return "removed";
      } catch (err) {
        if (!(err instanceof GithubError) || err.kind !== "not_found") throw err;
        logError({
          message: `Tickets : étiquette ${label} déjà absente de l'Issue #${issueNumber}`,
          feature: "tickets",
          error: err,
        });
        return "absent";
      }
    },

    async closeIssue(issueNumber, stateReason) {
      await request<unknown>("PATCH", `${REPO_PATH}/issues/${issueNumber}`, {
        body: { state: "closed", state_reason: stateReason },
      });
    },

    async listOpenPullRequests() {
      const prs: PullRequestView[] = [];
      for (let page = 1; page <= MAX_PAGES; page++) {
        const batch = await request<Array<Record<string, unknown>>>(
          "GET",
          `${REPO_PATH}/pulls?state=open&per_page=100&page=${page}`,
          { repoLevel: true },
        );
        for (const raw of batch) {
          const pr = readPullRequest(raw);
          if (pr !== null) prs.push(pr);
        }
        if (batch.length < 100) return { prs, complete: true };
      }
      return { prs, complete: false };
    },

    async getPullRequest(prNumber) {
      const raw = await request<Record<string, unknown>>("GET", `${REPO_PATH}/pulls/${prNumber}`);
      const pr = readPullRequest(raw);
      if (pr === null) throw new GithubError("other", null, `PR #${prNumber} illisible`);
      return pr;
    },

    async listPullRequestFiles(prNumber) {
      const files: PullRequestFileView[] = [];
      for (let page = 1; page <= MAX_FILE_PAGES; page++) {
        const batch = await request<Array<Record<string, unknown>>>(
          "GET",
          `${REPO_PATH}/pulls/${prNumber}/files?per_page=100&page=${page}`,
        );
        for (const f of batch) {
          files.push({ filename: str(f.filename), previousFilename: str(f.previous_filename) });
        }
        if (batch.length < 100) return { files, complete: true };
      }
      return { files, complete: false };
    },

    /**
     * Un 403 hors limite de débit dit ici que la permission « Actions : lecture » manque au
     * jeton, qui sert par ailleurs : il est rendu en `GithubActionsForbidden`, sans déclarer
     * tout le jeton refusé (Kass'Dalle, `listRunsForCommit` ; P25).
     */
    async listRunsForCommit(headSha) {
      if (!/^[0-9a-f]{40}$/i.test(headSha)) {
        throw new GithubError("other", null, `SHA de commit illisible : ${headSha.slice(0, 64)}`);
      }
      let raw: { workflow_runs?: unknown };
      try {
        raw = await request<{ workflow_runs?: unknown }>(
          "GET",
          `${REPO_PATH}/actions/runs?head_sha=${headSha}&per_page=100`,
        );
      } catch (err) {
        if (err instanceof GithubError && err.kind === "token" && err.status === 403) {
          throw new GithubActionsForbidden();
        }
        throw err;
      }
      const runs = Array.isArray(raw.workflow_runs) ? raw.workflow_runs : [];
      return runs
        .filter((r): r is Record<string, unknown> => r !== null && typeof r === "object")
        .map(readCiRun);
    },
  };
}
