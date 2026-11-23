/**
 * Livraison d'un ticket (« Livrer », ADR-008, T5, P43 à P46), copie de
 * `functions/src/tickets/delivery.ts` et des règles de livraison de `rules.ts` de Kass'Dalle,
 * adaptée :
 *
 * - CI : le dernier run de `.github/workflows/ci.yml` de chaque événement sur la tête compte,
 *   et non le dernier run nommé « CI » ; « verte » exige les deux événements `push` et
 *   `pull_request` présents et en `success` ; un run d'une autre tête de dépôt est ignoré ;
 * - un 403 sur `GET /actions/runs` pose `ticket_status/launches.ci_read_denied_since`, effacé
 *   à la lecture suivante réussie (décision de l'utilisateur du 2026-11-14) ;
 * - le serveur écrit les échéances à jour (verrou libéré par un blocage relevé ou par un
 *   ticket sorti de `in_progress`, `retry_after` de l'entrée de livraison ramené à l'heure du
 *   relevé) : le client ne lit que `retry_after`, sans règle recopiée (P46) ;
 * - `relaunch_ready` (CI terminée en échec) ouvre « Relancer le développement » (P47) ;
 * - fichiers sensibles : liste d'ADR-008 « Livraison », plus les ajouts des décisions de
 *   l'utilisateur du 2026-11-14, écrite une seule fois ici
 *   (`SENSITIVE_DELIVERY_PATTERNS`) et comparée au bloc L3 du prompt par
 *   `functions/test/prompts.test.ts`.
 *
 * - file des livraisons (amendement du 2026-11-22, P44) : `delivery_queue` (entrées dans l'ordre
 *   des accords, `DELIVERY_QUEUE_MAX` au plus) et `delivery_last` (dernière livraison lancée,
 *   `reported_at` posé au relevé de son compte rendu) ; un blocage relevé vide la file ; chaque
 *   sortie de file est notée dans `admin/delivery.queue_exit` (`code`, `at`).
 *
 * `tickets/{id}/admin/delivery` (P45) et `ticket_status/launches.delivery_running`,
 * `delivery_queue` et `delivery_last` (P44) sont écrits par le serveur seul et lus par
 * l'administrateur seul. Aucun titre ni corps de PR n'y
 * est écrit (P24). Le serveur n'écrit rien sur GitHub pour une livraison.
 *
 * Les fonctions qui lisent ou écrivent reçoivent le client Firestore (`kit`) et le client
 * GitHub de l'appelant : rien n'est construit au chargement du module (P26).
 */

import type { Transaction } from "firebase-admin/firestore";

import {
  COLL_TICKET_STATUS,
  COLL_TICKETS,
  DELIVERY_QUEUE_MAX,
  GITHUB_MAINTAINER_ID,
  GITHUB_REPO_FULL_NAME,
  TICKET_ADMIN_SUBCOLLECTION,
  TICKET_DELIVERY_DOC,
  TICKET_LAUNCHES_DOC,
  TICKET_STATUS_LAUNCHES_DOC,
} from "../config";
import type { FirestoreKit } from "../firestore";
import { logError, logInfo } from "../logging";
import { truncateAnalysis } from "./analysisModel";
import {
  GithubActionsForbidden,
  type CiRunView,
  type GithubClient,
  type PullRequestFileView,
  type PullRequestView,
} from "./github";
import {
  LAUNCH_RETRY_MS,
  closeRunningEntries,
  endLatestEntry,
  launchEntryViews,
  launchRawEntries,
  parisHourMinute,
  parisShortDate,
  type LaunchEntryView,
} from "./launchModel";
import { closingIssueNumbers, pullRequestUrl, type CommentView } from "./model";

// ── PR éligible ─────────────────────────────────────────────────────────────

/** Préfixe des branches des sessions Claude Code : seules leurs PR se livrent. */
export const DELIVERY_BRANCH_PREFIX = "claude/";

/** Issues ou PR relues au plus par événement du webhook (P29). */
export const DELIVERY_EVENT_MAX = 5;

/**
 * Vrai si une PR peut concerner une livraison : tête dans ce dépôt et auteur 16348852
 * (identifiant numérique). Toute autre PR (copie du dépôt, autre compte) ne déclenche aucune
 * relecture (P29). Pure.
 */
export function isDeliveryCandidatePr(pr: PullRequestView | null): pr is PullRequestView {
  return (
    pr !== null &&
    pr.authorId === GITHUB_MAINTAINER_ID &&
    typeof pr.headRepoFullName === "string" &&
    pr.headRepoFullName.toLowerCase() === GITHUB_REPO_FULL_NAME.toLowerCase()
  );
}

/**
 * Vrai si cette PR peut être livrée pour l'Issue `issueNumber` : ouverte, pas brouillon,
 * candidate (`isDeliveryCandidatePr`), branche `claude/…`, et Issues fermées par son corps
 * égales à `[issueNumber]` (P43). Pure.
 */
export function isEligibleDeliveryPr(pr: PullRequestView, issueNumber: number): boolean {
  if (pr.state !== "open" || pr.draft) return false;
  if (!isDeliveryCandidatePr(pr)) return false;
  if (typeof pr.headRef !== "string" || !pr.headRef.startsWith(DELIVERY_BRANCH_PREFIX)) {
    return false;
  }
  const closes = closingIssueNumbers(pr.body, GITHUB_REPO_FULL_NAME);
  return closes.length === 1 && closes[0] === issueNumber;
}

// ── CI ──────────────────────────────────────────────────────────────────────

/** Workflow dont les runs comptent : reconnu par son chemin et par son nom (P43). */
export const CI_WORKFLOW_PATH = ".github/workflows/ci.yml";
export const CI_WORKFLOW_NAME = "CI";

/** Conclusions d'une CI rouge ; `cancelled` n'en est pas (concurrence de `ci.yml`, P45). */
export const CI_RED_CONCLUSIONS: readonly string[] = ["failure", "timed_out", "startup_failure"];

/** Événements dont le dernier run doit exister et être vert pour une CI « verte » (P43). */
export const CI_REQUIRED_EVENTS: readonly string[] = ["pull_request", "push"];

/** Vrai si ce run est un run de `ci.yml` dont la tête est dans ce dépôt. Pure. */
export function isCiRun(run: Pick<CiRunView, "path" | "name" | "headRepoFullName">): boolean {
  return (
    run.path === CI_WORKFLOW_PATH &&
    run.name === CI_WORKFLOW_NAME &&
    typeof run.headRepoFullName === "string" &&
    run.headRepoFullName.toLowerCase() === GITHUB_REPO_FULL_NAME.toLowerCase()
  );
}

function isoMs(iso: string | null): number {
  const ms = iso === null ? Number.NaN : Date.parse(iso);
  return Number.isNaN(ms) ? Number.NEGATIVE_INFINITY : ms;
}

/**
 * Le dernier run de `ci.yml` sur `headSha` pour chaque événement (plus grand `createdAt`, à
 * égalité le plus grand identifiant), triés par événement. Une tête de PR a deux runs :
 * `push` (branche) et `pull_request` (fusion avec `main`) ; les deux comptent. Un run dont la
 * tête est dans un autre dépôt (copie sur le même commit) est ignoré. Pure.
 */
export function latestCiRunsByEvent(runs: readonly CiRunView[], headSha: string): CiRunView[] {
  const best = new Map<string, CiRunView>();
  for (const run of runs) {
    if (!isCiRun(run) || run.headSha !== headSha) continue;
    const event = run.event ?? "";
    const current = best.get(event);
    const ms = isoMs(run.createdAt);
    if (
      current === undefined ||
      ms > isoMs(current.createdAt) ||
      (ms === isoMs(current.createdAt) && (run.id ?? 0) > (current.id ?? 0))
    ) {
      best.set(event, run);
    }
  }
  return [...best.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([, run]) => run);
}

/** Ce que retient `admin/delivery` des runs d'une tête. */
export interface CiSummary {
  /**
   * `null` : aucun run ; `completed` : tous finis ; `pending` : runs finis sans échec, mais un
   * événement de `CI_REQUIRED_EVENTS` sans run ; sinon l'état d'un run en cours.
   */
  status: string | null;
  /** Tous finis : `success` si tous verts, sinon la conclusion d'un run qui ne l'est pas. */
  conclusion: string | null;
  /** Tous finis : fin du dernier (`updatedAt`). */
  completedAt: string | null;
  /** Tous finis, `push` et `pull_request` présents, tous en `success`. */
  green: boolean;
  /** Tous finis, au moins un en `failure`, `timed_out` ou `startup_failure`. */
  red: boolean;
}

/** Résumé des derniers runs de chaque événement (`latestCiRunsByEvent`). Pure. */
export function ciSummary(latest: readonly CiRunView[]): CiSummary {
  if (latest.length === 0) {
    return { status: null, conclusion: null, completedAt: null, green: false, red: false };
  }
  const running = latest.find((r) => r.status !== "completed");
  if (running !== undefined) {
    return {
      status: running.status ?? "unknown",
      conclusion: null,
      completedAt: null,
      green: false,
      red: false,
    };
  }
  const redRun = latest.find(
    (r) => r.conclusion !== null && CI_RED_CONCLUSIONS.includes(r.conclusion),
  );
  const other = latest.find((r) => r.conclusion !== "success");
  const missing = CI_REQUIRED_EVENTS.some((e) => !latest.some((r) => r.event === e));
  if (redRun === undefined && missing) {
    // Runs finis, sans échec, mais le run de l'autre événement n'existe pas encore.
    return { status: "pending", conclusion: null, completedAt: null, green: false, red: false };
  }
  let completedAt: string | null = null;
  for (const r of latest) {
    if (r.updatedAt !== null && (completedAt === null || isoMs(r.updatedAt) > isoMs(completedAt))) {
      completedAt = r.updatedAt;
    }
  }
  return {
    status: "completed",
    conclusion: (redRun ?? other)?.conclusion ?? "success",
    completedAt,
    green: other === undefined,
    red: redRun !== undefined,
  };
}

// ── État « PR prête » (P45) ─────────────────────────────────────────────────

/**
 * Ce que `tickets/{id}/admin/delivery` retient d'une relecture (dates ISO ; écrites en
 * `Timestamp`). Aucun titre ni corps de PR (P24).
 */
export interface DeliveryState {
  eligible_pr_count: number;
  pr_number: number | null;
  /** `https://github.com/ChinaFred/KassBeer/pull/<n>` seulement, sinon `null`. */
  pr_url: string | null;
  head_sha: string | null;
  ci_status: string | null;
  ci_conclusion: string | null;
  ci_completed_at: string | null;
  /** « PR prête » : ticket En cours, une PR éligible, CI verte (P45). */
  ready: boolean;
  /** CI rouge : ticket En cours, une PR éligible, CI terminée en échec (P47). */
  relaunch_ready: boolean;
}

/** L'adresse d'une PR de ce dépôt sur github.com, ou `null`. Pure. */
export function safePullRequestUrl(url: string | null): string | null {
  if (typeof url !== "string") return null;
  const prefix = `https://github.com/${GITHUB_REPO_FULL_NAME}/pull/`;
  if (!url.startsWith(prefix)) return null;
  return /^[1-9][0-9]{0,6}$/.test(url.slice(prefix.length)) ? url : null;
}

/**
 * L'état « PR prête » d'un ticket. Une liste de PR ouvertes tronquée ne donne aucune PR
 * retenue (`pr_number` nul, `ready` et `relaunch_ready` faux) : une seconde PR éligible a pu
 * échapper à la lecture. Les fichiers sensibles ne comptent pas ici : ils se contrôlent au
 * lancement (P43). Pure.
 */
export function deliveryState(args: {
  ticketStatus: unknown;
  prListComplete: boolean;
  eligible: readonly PullRequestView[];
  /** Détail relu de la PR éligible quand elle est seule, sinon `null`. */
  pr: PullRequestView | null;
  ci: CiSummary;
}): DeliveryState {
  const single =
    args.prListComplete && args.eligible.length === 1 ? (args.pr ?? args.eligible[0]) : null;
  const ci = single === null ? ciSummary([]) : args.ci;
  const inProgress = args.ticketStatus === "in_progress";
  return {
    eligible_pr_count: args.eligible.length,
    pr_number: single?.number ?? null,
    pr_url:
      single === null
        ? null
        : safePullRequestUrl(pullRequestUrl(GITHUB_REPO_FULL_NAME, single.number)),
    head_sha: single?.headSha ?? null,
    ci_status: ci.status,
    ci_conclusion: ci.conclusion,
    ci_completed_at: ci.completedAt,
    ready: inProgress && single !== null && ci.green,
    relaunch_ready: inProgress && single !== null && ci.red,
  };
}

// ── Fichiers sensibles (P43, logique dupliquée avec le bloc L3 du prompt) ───

/**
 * Fichiers qu'une livraison ne fusionne jamais : liste d'ADR-008 « Livraison », plus les ajouts
 * des décisions de l'utilisateur du 2026-11-14 : les trois `pubspec.lock` (un nouveau paquet
 * exécute son code de construction dans le job `build` de `deploy.yml`, qui détient les
 * secrets de signature), `gradlew` et `gradlew.bat` (lancés par `flutter build apk`), les
 * build hooks Dart (`hook/`), tout dossier `.claude/`, et les fichiers qui portent le contrôle
 * des livraisons (`auth.ts`, `config.ts`, `delivery.ts`, `member_access.json`). Motifs depuis
 * la racine :
 * un motif qui commence par deux étoiles et une barre vaut pour un nom de fichier à toute
 * profondeur, un motif qui finit par une barre et deux étoiles pour tout un dossier, une étoile
 * seule pour un segment. Casse ignorée. Seule copie côté serveur ; le bloc L3 du prompt de
 * développement en est l'autre (tableau « Logique dupliquée » de `CLAUDE.md`).
 */
export const SENSITIVE_DELIVERY_PATTERNS: readonly string[] = [
  ".github/**",
  "**/.claude/**",
  "scripts/**",
  "**/CLAUDE.md",
  "**/CLAUDE.local.md",
  "**/.mcp.json",
  "firebase.json",
  "firestore.rules",
  "storage.rules",
  "firestore.indexes.json",
  "rules-tests/package.json",
  "rules-tests/package-lock.json",
  "rules-tests/prettier.config.*",
  "functions/package.json",
  "functions/package-lock.json",
  "functions/prettier.config.*",
  "ingest/package.json",
  "ingest/package-lock.json",
  "ingest/prettier.config.*",
  "app/android/**/*.gradle",
  "app/android/**/*.gradle.kts",
  "app/android/gradle.properties",
  "app/android/settings.gradle*",
  "app/android/gradle/**",
  "app/android/gradlew",
  "app/android/gradlew.bat",
  "**/hook/**",
  "app/pubspec.lock",
  "brewing/pubspec.lock",
  "exchange/pubspec.lock",
  "functions/src/auth.ts",
  "functions/src/config.ts",
  "functions/src/tickets/delivery.ts",
  "test-fixtures/member_access.json",
];

/** Un motif de `SENSITIVE_DELIVERY_PATTERNS` en expression régulière, casse ignorée. Pure. */
export function sensitivePatternRegExp(pattern: string): RegExp {
  let out = "";
  let i = 0;
  while (i < pattern.length) {
    if (pattern.startsWith("**/", i)) {
      out += "(?:.*/)?";
      i += 3;
    } else if (pattern.startsWith("/**", i) && i + 3 === pattern.length) {
      out += "/.*";
      i += 3;
    } else if (pattern[i] === "*") {
      out += "[^/]*";
      i += 1;
    } else {
      out += pattern[i].replace(/[.+?^${}()|[\]\\]/g, "\\$&");
      i += 1;
    }
  }
  return new RegExp(`^${out}$`, "i");
}

const SENSITIVE_REGEXPS = SENSITIVE_DELIVERY_PATTERNS.map(sensitivePatternRegExp);

/** Vrai si ce chemin est un fichier qu'une livraison ne fusionne jamais (casse ignorée). Pure. */
export function isSensitiveDeliveryPath(path: string): boolean {
  return SENSITIVE_REGEXPS.some((re) => re.test(path));
}

/**
 * Le premier fichier sensible que touche la PR, ancien chemin d'un renommage compris, ou
 * `null`. Pure.
 */
export function sensitiveDeliveryPath(files: readonly PullRequestFileView[]): string | null {
  for (const f of files) {
    for (const path of [f.filename, f.previousFilename]) {
      if (typeof path === "string" && isSensitiveDeliveryPath(path)) return path;
    }
  }
  return null;
}

// ── Messages des refus (P43) ────────────────────────────────────────────────

export const DELIVERY_NOTHING = "Rien n'a été lancé ni décompté.";

export const DELIVERY_NO_PR_MESSAGE = `Aucune pull request prête ne ferme cette Issue. ${DELIVERY_NOTHING}`;

export function deliveryMultiplePrMessage(count: number, issueNumber: number): string {
  return (
    `${count} pull requests ferment l'Issue #${issueNumber} : fermez sur GitHub celles à ` +
    `abandonner. ${DELIVERY_NOTHING}`
  );
}

export function deliveryFilesUnreadableMessage(prNumber: number): string {
  return (
    `La liste des fichiers de la PR #${prNumber} est trop longue pour être vérifiée. ` +
    `Fusionnez-la vous-même après relecture. ${DELIVERY_NOTHING}`
  );
}

export function deliverySensitiveMessage(prNumber: number, path: string): string {
  return (
    `La PR #${prNumber} modifie un fichier protégé (${path.slice(0, 200)}). ` +
    `Fusionnez-la vous-même après relecture. ${DELIVERY_NOTHING}`
  );
}

export function deliveryCiNotGreenMessage(prNumber: number): string {
  return `La CI de la PR #${prNumber} n'est pas verte. ${DELIVERY_NOTHING}`;
}

/**
 * Refus `delivery_running_elsewhere`. Numéro ou heure absents du verrou : la phrase s'en passe,
 * sans valeur inventée. Pure.
 */
export function deliveryRunningElsewhereMessage(
  issueNumber: number | null,
  launchedAtMs: number | null,
): string {
  const ticket = issueNumber === null ? "un autre ticket" : `le ticket #${issueNumber}`;
  const since =
    launchedAtMs === null
      ? ""
      : ` depuis le ${parisShortDate(launchedAtMs)} à ${parisHourMinute(launchedAtMs)}`;
  return (
    `Une livraison est en cours sur ${ticket}${since}. Une seule livraison à la fois. ` +
    DELIVERY_NOTHING
  );
}

/** Refus `github_actions_forbidden` : 403 sur `GET /actions/runs` (P25, P43). */
export const CI_READ_DENIED_TEXT =
  "Le jeton GitHub ne peut pas lire la CI : sur GitHub, donnez-lui le droit « Actions : lecture ».";
export const DELIVERY_ACTIONS_FORBIDDEN_MESSAGE = `${CI_READ_DENIED_TEXT} ${DELIVERY_NOTHING}`;

// ── Comptes rendus (P45) ────────────────────────────────────────────────────

export const DELIVERY_BLOCKED_TITLE = "## Livraison — blocage";
export const DELIVERY_DONE_TITLE = "## Livraison — terminée";

/** Comptes rendus gardés par ticket : les plus récents. */
export const DELIVERY_REPORT_MAX_COUNT = 10;

export type DeliveryReportKind = "blocked" | "done";

function normalizedBody(body: string): string {
  return body.normalize("NFC").replace(/\r\n?/g, "\n");
}

/**
 * Nature d'un compte rendu : auteur 16348852 (identifiant numérique, jamais le login) et
 * texte en NFC, espaces de tête retirées, qui commence par `## Livraison — blocage` ou
 * `## Livraison — terminée`. Sinon `null`. Pure.
 */
export function deliveryReportKind(
  comment: Pick<CommentView, "authorId" | "body">,
  maintainerId: number,
): DeliveryReportKind | null {
  if (comment.authorId !== maintainerId || typeof comment.body !== "string") return null;
  const text = normalizedBody(comment.body).trimStart();
  if (text.startsWith(DELIVERY_BLOCKED_TITLE)) return "blocked";
  if (text.startsWith(DELIVERY_DONE_TITLE)) return "done";
  return null;
}

/** Un compte rendu de `admin/delivery.reports` (dates ISO ; écrites en `Timestamp`). */
export interface DeliveryReport {
  comment_id: number | null;
  kind: DeliveryReportKind;
  body: string;
  created_at: string | null;
  updated_at: string | null;
  truncated: boolean;
}

/**
 * Les comptes rendus d'une Issue, ordre chronologique, les dix plus récents, 20 000
 * caractères chacun (`truncateAnalysis`). Pure.
 */
export function deliveryReportsFromComments(
  comments: readonly CommentView[],
  maintainerId: number,
): DeliveryReport[] {
  return comments
    .map((c, index) => ({ c, index, kind: deliveryReportKind(c, maintainerId) }))
    .filter(
      (e): e is { c: CommentView; index: number; kind: DeliveryReportKind } => e.kind !== null,
    )
    .sort((a, b) => isoMs(a.c.createdAt) - isoMs(b.c.createdAt) || a.index - b.index)
    .slice(-DELIVERY_REPORT_MAX_COUNT)
    .map(({ c, kind }) => {
      const { body, truncated } = truncateAnalysis(normalizedBody(c.body ?? "").trim());
      return {
        comment_id: c.id,
        kind,
        body,
        created_at: c.createdAt,
        updated_at: c.updatedAt,
        truncated,
      };
    });
}

/** Date du dernier blocage, en millisecondes, ou `null`. Pure. */
export function lastBlockedAtMs(reports: readonly DeliveryReport[]): number | null {
  let best: number | null = null;
  for (const r of reports) {
    if (r.kind !== "blocked" || r.created_at === null) continue;
    const ms = Date.parse(r.created_at);
    if (Number.isNaN(ms)) continue;
    if (best === null || ms > best) best = ms;
  }
  return best;
}

/** `ended_by` d'une entrée `livraison` close par un blocage relevé (P45). */
export const DELIVERY_ENDED_BY_BLOCKAGE = "blocked";

/**
 * L'historique après un blocage relevé à `blockedAtMs` : `endLatestEntry` sur les entrées
 * `livraison`, avec `ended_by: "blocked"`. Le client choisit son texte (« s'est arrêtée »)
 * d'après ce champ, sans comparer de dates (P46). `null` si rien ne change. Pure.
 */
export function blockedDeliveryEntries(
  entries: readonly Record<string, unknown>[],
  views: readonly LaunchEntryView[],
  blockedAtMs: number,
  nowMs: number,
  toTimestamp: (ms: number) => unknown,
): Record<string, unknown>[] | null {
  return endLatestEntry(
    entries,
    views,
    "livraison",
    DELIVERY_ENDED_BY_BLOCKAGE,
    blockedAtMs,
    nowMs,
    toTimestamp,
  );
}

// ── Verrou global (P44) ─────────────────────────────────────────────────────

/** `ticket_status/launches.delivery_running`, lu sans supposer sa forme. */
export interface DeliveryLockView {
  ticketId: string | null;
  issueNumber: number | null;
  launchedAtMs: number | null;
  retryAfterMs: number | null;
}

/** Le verrou lu, ou `null` s'il est absent ou illisible. Pure. */
export function readDeliveryLock(
  raw: unknown,
  toMillis: (v: unknown) => number | null,
): DeliveryLockView | null {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const lock: DeliveryLockView = {
    ticketId: typeof r.ticket_id === "string" && r.ticket_id.length > 0 ? r.ticket_id : null,
    issueNumber:
      typeof r.issue_number === "number" && Number.isSafeInteger(r.issue_number)
        ? r.issue_number
        : null,
    launchedAtMs: toMillis(r.launched_at),
    retryAfterMs: toMillis(r.retry_after),
  };
  return lock.ticketId === null ? null : lock;
}

/** Vrai si le verrou tient encore : échéance future. Pure. */
export function deliveryLockHeld(lock: DeliveryLockView | null, nowMs: number): boolean {
  return lock !== null && lock.retryAfterMs !== null && lock.retryAfterMs > nowMs;
}

/**
 * Vrai si un blocage relevé sur `ticketId` libère le verrou : le verrou porte ce ticket et le
 * blocage est strictement postérieur à son lancement. Pure.
 */
export function blockageReleasesLock(
  lock: DeliveryLockView | null,
  ticketId: string,
  blockedAtMs: number | null,
): boolean {
  if (lock === null || lock.ticketId !== ticketId) return false;
  if (blockedAtMs === null || lock.launchedAtMs === null) return false;
  return blockedAtMs > lock.launchedAtMs;
}

// ── File des livraisons (P44, amendement du 2026-11-22) ─────────────────────

/** Une entrée de `ticket_status/launches.delivery_queue`, lue sans supposer sa forme. */
export interface DeliveryQueueEntryView {
  ticketId: string;
  issueNumber: number | null;
  prNumber: number | null;
  headSha: string | null;
  queuedAtMs: number | null;
  byUid: string | null;
  byEmail: string | null;
}

/** La file lue : entrées brutes (réécrites telles quelles) et leur lecture, dans l'ordre. */
export interface DeliveryQueueRead {
  raw: Record<string, unknown>[];
  views: DeliveryQueueEntryView[];
}

/**
 * La file lue. Une entrée qui n'est pas un objet, ou dont `ticket_id` n'est pas un
 * identifiant de document, est écartée : elle sort à la prochaine réécriture. Pure.
 */
export function readDeliveryQueue(
  raw: unknown,
  toMillis: (v: unknown) => number | null,
): DeliveryQueueRead {
  const out: DeliveryQueueRead = { raw: [], views: [] };
  if (!Array.isArray(raw)) return out;
  const int = (v: unknown) =>
    typeof v === "number" && Number.isSafeInteger(v) && v > 0 ? v : null;
  const text = (v: unknown) => (typeof v === "string" && v.length > 0 ? v : null);
  for (const e of raw) {
    if (e === null || typeof e !== "object" || Array.isArray(e)) continue;
    const r = e as Record<string, unknown>;
    const ticketId = text(r.ticket_id);
    if (ticketId === null || !/^[A-Za-z0-9_-]{1,128}$/.test(ticketId)) continue;
    out.raw.push(r);
    out.views.push({
      ticketId,
      issueNumber: int(r.issue_number),
      prNumber: int(r.pr_number),
      headSha: text(r.head_sha),
      queuedAtMs: toMillis(r.queued_at),
      byUid: text(r.by_uid),
      byEmail: text(r.by_email),
    });
  }
  return out;
}

/** `ticket_status/launches.delivery_last`, lu sans supposer sa forme. */
export interface DeliveryLastView {
  ticketId: string;
  issueNumber: number | null;
  launchedAtMs: number | null;
  retryAfterMs: number | null;
  reportedAtMs: number | null;
}

/** La dernière livraison lancée, ou `null` si absente ou illisible. Pure. */
export function readDeliveryLast(
  raw: unknown,
  toMillis: (v: unknown) => number | null,
): DeliveryLastView | null {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.ticket_id !== "string" || r.ticket_id.length === 0) return null;
  return {
    ticketId: r.ticket_id,
    issueNumber:
      typeof r.issue_number === "number" && Number.isSafeInteger(r.issue_number)
        ? r.issue_number
        : null,
    launchedAtMs: toMillis(r.launched_at),
    retryAfterMs: toMillis(r.retry_after),
    reportedAtMs: toMillis(r.reported_at),
  };
}

/**
 * Condition de fin de la livraison précédente (point 7) : `delivery_last` absent, compte rendu
 * relevé (`reported_at`), ou échéance passée. Une échéance illisible ne bloque pas. Pure.
 */
export function deliveryLastFinished(last: DeliveryLastView | null, nowMs: number): boolean {
  if (last === null || last.reportedAtMs !== null) return true;
  return last.retryAfterMs === null || last.retryAfterMs <= nowMs;
}

/** Pourquoi `startQueuedDelivery` s'arrête sans autre lecture (point 8). */
export type DeliveryQueueStop =
  "empty" | "lock_held" | "awaiting_report" | "routine_invalid" | "queue_halted";

/**
 * Lecture de `ticket_status/launches` seule : la tête de file à tenter, ou la raison de
 * s'arrêter (file vide, verrou tenu, compte rendu attendu, jeton de la routine de développement
 * refusé, file arrêtée par un refus de la routine : `delivery_queue_halted`, décision de
 * l'utilisateur du 2026-11-22). Pure.
 */
export function deliveryQueueDeparture(
  status: Record<string, unknown>,
  nowMs: number,
  toMillis: (v: unknown) => number | null,
): { stop: DeliveryQueueStop } | { head: DeliveryQueueEntryView } {
  const queue = readDeliveryQueue(status.delivery_queue, toMillis);
  if (queue.views.length === 0) return { stop: "empty" };
  if (deliveryLockHeld(readDeliveryLock(status.delivery_running, toMillis), nowMs)) {
    return { stop: "lock_held" };
  }
  if (!deliveryLastFinished(readDeliveryLast(status.delivery_last, toMillis), nowMs)) {
    return { stop: "awaiting_report" };
  }
  const invalid = status.development_invalid_since;
  if (invalid !== null && invalid !== undefined) return { stop: "routine_invalid" };
  const halted = status.delivery_queue_halted;
  if (halted !== null && halted !== undefined) return { stop: "queue_halted" };
  return { head: queue.views[0] };
}

/** Codes de sortie de file notés dans `admin/delivery.queue_exit.code` (P45). */
export const QUEUE_EXIT_REMOVED = "delivery_queue_removed";
export const QUEUE_EXIT_CLEARED = "delivery_queue_cleared_after_blockage";
export const QUEUE_EXIT_HEAD_CHANGED = "delivery_queue_head_changed";
export const QUEUE_EXIT_NOT_ADMIN = "delivery_queue_not_admin";
export const QUEUE_EXIT_RELAUNCHED = "delivery_queue_relaunched";
export const QUEUE_EXIT_REFUSED = "delivery_queue_refused";
export const QUEUE_EXIT_CLOSED = "delivery_queue_closed";
export const QUEUE_EXIT_LEFT_IN_PROGRESS = "delivery_queue_left_in_progress";

/** Le verrou et la dernière livraison écrits ensemble à chaque prise du verrou (P44). */
export function deliveryLockFields(
  kit: Pick<FirestoreKit, "Timestamp">,
  ticketId: string,
  issueNumber: number,
  launchedAtMs: number,
): { delivery_running: Record<string, unknown>; delivery_last: Record<string, unknown> } {
  const launched_at = kit.Timestamp.fromMillis(launchedAtMs);
  const retry_after = kit.Timestamp.fromMillis(launchedAtMs + LAUNCH_RETRY_MS.livraison);
  return {
    delivery_running: { ticket_id: ticketId, issue_number: issueNumber, launched_at, retry_after },
    delivery_last: {
      ticket_id: ticketId,
      issue_number: issueNumber,
      launched_at,
      retry_after,
      reported_at: null,
    },
  };
}

// ── Firestore ───────────────────────────────────────────────────────────────

function ticketRef(kit: FirestoreKit, ticketId: string) {
  return kit.db.collection(COLL_TICKETS).doc(ticketId);
}

/** `tickets/{id}/admin/delivery` : lecture admin seule, écriture serveur seule (P45). */
export function deliveryRef(kit: FirestoreKit, ticketId: string) {
  return ticketRef(kit, ticketId).collection(TICKET_ADMIN_SUBCOLLECTION).doc(TICKET_DELIVERY_DOC);
}

function launchesRef(kit: FirestoreKit, ticketId: string) {
  return ticketRef(kit, ticketId).collection(TICKET_ADMIN_SUBCOLLECTION).doc(TICKET_LAUNCHES_DOC);
}

function statusRef(kit: FirestoreKit) {
  return kit.db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_LAUNCHES_DOC);
}

function millisOf(kit: FirestoreKit): (v: unknown) => number | null {
  return (v) => (v instanceof kit.Timestamp ? v.toMillis() : null);
}

function timestampOrNull(kit: FirestoreKit, iso: string | null) {
  if (iso === null) return null;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : kit.Timestamp.fromMillis(ms);
}

/**
 * Dans une transaction : l'historique du ticket transformé par `next` (rend `null` si rien ne
 * change). Lit `launches` : à appeler avant toute écriture de la transaction.
 */
async function rewriteDeliveryEntries(
  tx: Transaction,
  kit: FirestoreKit,
  ticketId: string,
  next: (
    entries: Record<string, unknown>[],
    views: LaunchEntryView[],
  ) => Record<string, unknown>[] | null,
): Promise<(() => void) | null> {
  const ref = launchesRef(kit, ticketId);
  const snap = await tx.get(ref);
  if (!snap.exists) return null;
  const entries = launchRawEntries(snap.data());
  const out = next(entries, launchEntryViews(kit, entries));
  if (out === null) return null;
  return () => tx.set(ref, { entries: out, updated_at: kit.FieldValue.serverTimestamp() });
}

/** Les entrées `livraison` en cours voient leur `retry_after` ramené à `nowMs`. */
async function closeDeliveryEntries(
  tx: Transaction,
  kit: FirestoreKit,
  ticketId: string,
  nowMs: number,
): Promise<(() => void) | null> {
  return rewriteDeliveryEntries(tx, kit, ticketId, (entries, views) =>
    closeRunningEntries(
      entries,
      views,
      nowMs,
      (ms) => kit.Timestamp.fromMillis(ms),
      (v) => v.action === "livraison",
    ),
  );
}

/**
 * Dans une transaction qui a déjà lu `ticket_status/launches` (`status`) : retire `ticketId` de
 * la file et note `queue_exit` (`code`, `at`) dans son `admin/delivery`. Aucune lecture : à
 * appeler après les lectures de la transaction. Rend vrai si le ticket était en file.
 */
export function dequeueInTransaction(
  tx: Transaction,
  kit: FirestoreKit,
  status: Record<string, unknown> | undefined,
  ticketId: string,
  code: string,
  nowMs: number,
): boolean {
  const queue = readDeliveryQueue(status?.delivery_queue, millisOf(kit));
  const index = queue.views.findIndex((v) => v.ticketId === ticketId);
  if (index < 0) return false;
  tx.set(
    statusRef(kit),
    { delivery_queue: queue.raw.filter((_, i) => i !== index) },
    { merge: true },
  );
  tx.set(
    deliveryRef(kit, ticketId),
    { queue_exit: { code, at: kit.Timestamp.fromMillis(nowMs) } },
    { merge: true },
  );
  return true;
}

/** Écrit l'état « PR prête » (fusion : les comptes rendus restent). Lève sur une panne. */
export async function writeDeliveryState(
  kit: FirestoreKit,
  ticketId: string,
  state: DeliveryState,
): Promise<void> {
  await deliveryRef(kit, ticketId).set(
    {
      ...state,
      ci_completed_at: timestampOrNull(kit, state.ci_completed_at),
      updated_at: kit.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * Note dans `ticket_status/launches.ci_read_denied_since` si GitHub refuse la lecture des runs
 * (403, permission « Actions : lecture » absente) ; l'efface après une lecture réussie. Écrit
 * seulement quand l'état change. Au mieux, journalisé.
 */
async function recordCiReadDenied(kit: FirestoreKit, denied: boolean): Promise<void> {
  try {
    const ref = statusRef(kit);
    const current = (await ref.get()).get("ci_read_denied_since");
    const isSet = current !== null && current !== undefined;
    if (denied === isSet) return;
    await ref.set(
      { ci_read_denied_since: denied ? kit.FieldValue.serverTimestamp() : null },
      { merge: true },
    );
  } catch (err) {
    logError({
      message: denied
        ? "Tickets : lecture de la CI refusée, non notée dans ticket_status"
        : "Tickets : lecture de la CI rétablie, non notée dans ticket_status",
      feature: "tickets",
      error: err,
    });
  }
}

/**
 * Les runs de `headSha`. Un 403 (`GithubActionsForbidden`) est noté dans
 * `ci_read_denied_since`, puis relevé tel quel : l'appelant le journalise. Une lecture réussie
 * efface la note.
 */
async function readCiRuns(
  kit: FirestoreKit,
  client: GithubClient,
  headSha: string,
): Promise<CiRunView[]> {
  let runs: CiRunView[];
  try {
    runs = await client.listRunsForCommit(headSha);
  } catch (err) {
    if (err instanceof GithubActionsForbidden) await recordCiReadDenied(kit, true);
    throw err;
  }
  await recordCiReadDenied(kit, false);
  return runs;
}

/** Les PR ouvertes du dépôt, lues une fois et partagées par une passe (P46). */
export type OpenPullRequests = { prs: PullRequestView[]; complete: boolean };

/** Ce qu'une relecture établit, avec la PR éligible quand elle est seule. */
export interface DeliveryReading {
  state: DeliveryState;
  pr: PullRequestView | null;
}

/**
 * Relit sur GitHub ce qui fait une « PR prête » pour l'Issue `issueNumber` : PR ouvertes
 * (`openPrs` de l'appelant, sinon relues), détail de la PR éligible quand elle est seule, runs
 * de sa tête. Lève une `GithubError` (`GithubActionsForbidden` pour un 403 sur les runs).
 */
export async function readDelivery(
  kit: FirestoreKit,
  client: GithubClient,
  issueNumber: number,
  ticketStatus: unknown,
  openPrs?: OpenPullRequests,
): Promise<DeliveryReading> {
  const list = openPrs ?? (await client.listOpenPullRequests());
  let eligible = list.prs.filter((pr) => isEligibleDeliveryPr(pr, issueNumber));
  let pr: PullRequestView | null = null;
  let ci = ciSummary([]);
  if (list.complete && eligible.length === 1) {
    const detail = await client.getPullRequest(eligible[0].number);
    if (isEligibleDeliveryPr(detail, issueNumber)) {
      pr = detail;
      if (detail.headSha !== null) {
        ci = ciSummary(
          latestCiRunsByEvent(await readCiRuns(kit, client, detail.headSha), detail.headSha),
        );
      }
    } else {
      eligible = [];
    }
  }
  return {
    state: deliveryState({
      ticketStatus,
      prListComplete: list.complete,
      eligible,
      pr,
      ci,
    }),
    pr,
  };
}

/**
 * Relit l'état « PR prête » d'un ticket `in_progress` et l'écrit ; ne fait rien pour un autre
 * statut (P46). Rend l'état écrit, ou `null`. Lève une `GithubError` ou une panne Firestore.
 */
export async function refreshTicketDelivery(
  kit: FirestoreKit,
  client: GithubClient,
  ticketId: string,
  issueNumber: number,
  openPrs?: OpenPullRequests,
): Promise<DeliveryState | null> {
  const snap = await ticketRef(kit, ticketId).get();
  if (!snap.exists || snap.get("status") !== "in_progress") return null;
  const reading = await readDelivery(kit, client, issueNumber, "in_progress", openPrs);
  await writeDeliveryState(kit, ticketId, reading.state);
  return reading.state;
}

/**
 * `workflow_run` de `ci.yml` sur la PR `prNumber` (P46) : la PR et les runs de sa tête sont
 * relus, jamais la liste des PR ouvertes. Seuls les tickets `in_progress` dont
 * `admin/delivery` retient déjà cette PR (une seule éligible, liste complète) sont réécrits ;
 * les autres attendent un événement `pull_request` ou la passe horaire. Rend le nombre de
 * tickets réécrits. Lève une `GithubError` ou une panne Firestore.
 */
export async function refreshDeliveryFromRun(
  kit: FirestoreKit,
  client: GithubClient,
  prNumber: number,
): Promise<number> {
  const pr = await client.getPullRequest(prNumber);
  if (!isDeliveryCandidatePr(pr)) return 0;
  const issues = closingIssueNumbers(pr.body, GITHUB_REPO_FULL_NAME).slice(0, DELIVERY_EVENT_MAX);
  let ci: CiSummary | null = null;
  let written = 0;
  for (const issueNumber of issues) {
    const snap = await kit.db
      .collection(COLL_TICKETS)
      .where("github_issue_number", "==", issueNumber)
      .limit(2)
      .get();
    for (const doc of snap.docs) {
      if (doc.get("status") !== "in_progress") continue;
      const stored = (await deliveryRef(kit, doc.id).get()).data() ?? {};
      if (stored.pr_number !== pr.number || stored.eligible_pr_count !== 1) continue;
      const eligible = isEligibleDeliveryPr(pr, issueNumber);
      if (eligible && ci === null && pr.headSha !== null) {
        ci = ciSummary(latestCiRunsByEvent(await readCiRuns(kit, client, pr.headSha), pr.headSha));
      }
      await writeDeliveryState(
        kit,
        doc.id,
        deliveryState({
          ticketStatus: "in_progress",
          prListComplete: true,
          eligible: eligible ? [pr] : [],
          pr: eligible ? pr : null,
          ci: ci ?? ciSummary([]),
        }),
      );
      written++;
    }
  }
  return written;
}

/**
 * Réécrit `reports` de `admin/delivery` depuis les commentaires de l'Issue (P45). Le document
 * n'est créé que s'il y a un compte rendu. Un blocage relevé, postérieur au lancement :
 * verrou libéré s'il porte ce ticket (P44), et dernière entrée `livraison` lancée avant le
 * blocage marquée `ended_by: "blocked"`, son `retry_after` ramené à l'heure du relevé. Sur le
 * ticket de `delivery_last`, un premier compte rendu postérieur à `launched_at` pose
 * `reported_at` ; si c'est un blocage, la file est vidée et chaque entrée sort avec
 * `delivery_queue_cleared_after_blockage` (décision 3). Une transaction. Rend le nombre de
 * comptes rendus. Lève sur une panne Firestore ; l'appelant journalise.
 */
export async function writeDeliveryReports(
  kit: FirestoreKit,
  ticketId: string,
  comments: readonly CommentView[],
  nowMs: number,
): Promise<number> {
  const reports = deliveryReportsFromComments(comments, GITHUB_MAINTAINER_ID);
  const blockedAtMs = lastBlockedAtMs(reports);
  const ref = deliveryRef(kit, ticketId);
  const ms = millisOf(kit);
  const outcome = await kit.db.runTransaction(async (tx) => {
    const [current, status] = await Promise.all([tx.get(ref), tx.get(statusRef(kit))]);
    const closeEntries =
      blockedAtMs === null
        ? null
        : await rewriteDeliveryEntries(tx, kit, ticketId, (entries, views) =>
            blockedDeliveryEntries(entries, views, blockedAtMs, nowMs, (at) =>
              kit.Timestamp.fromMillis(at),
            ),
          );
    if (reports.length === 0 && !current.exists) return { released: false, cleared: 0 };
    const statusPatch: Record<string, unknown> = {};
    const lock = readDeliveryLock(status.get("delivery_running"), ms);
    const released = blockageReleasesLock(lock, ticketId, blockedAtMs);
    if (released) statusPatch.delivery_running = null;
    // Compte rendu de la dernière livraison lancée (point 7).
    const last = readDeliveryLast(status.get("delivery_last"), ms);
    const launchedAtMs = last?.launchedAtMs ?? null;
    const after =
      last !== null &&
      last.ticketId === ticketId &&
      last.reportedAtMs === null &&
      launchedAtMs !== null
        ? reports.filter((r) => r.created_at !== null && Date.parse(r.created_at) > launchedAtMs)
        : [];
    let ownExit: Record<string, unknown> | null = null;
    let cleared = 0;
    if (after.length > 0) {
      statusPatch.delivery_last = {
        ...(status.get("delivery_last") as Record<string, unknown>),
        reported_at: kit.Timestamp.fromMillis(nowMs),
      };
      if (after.some((r) => r.kind === "blocked")) {
        const queue = readDeliveryQueue(status.get("delivery_queue"), ms);
        const exit = { code: QUEUE_EXIT_CLEARED, at: kit.Timestamp.fromMillis(nowMs) };
        for (const v of queue.views) {
          if (v.ticketId === ticketId) ownExit = exit;
          else tx.set(deliveryRef(kit, v.ticketId), { queue_exit: exit }, { merge: true });
        }
        cleared = queue.views.length;
        if (queue.raw.length > 0 || status.get("delivery_queue") !== undefined) {
          statusPatch.delivery_queue = [];
        }
      }
    }
    tx.set(
      ref,
      {
        reports: reports.map((r) => ({
          ...r,
          created_at: timestampOrNull(kit, r.created_at),
          updated_at: timestampOrNull(kit, r.updated_at),
        })),
        reports_checked_at: kit.FieldValue.serverTimestamp(),
        ...(ownExit !== null ? { queue_exit: ownExit } : {}),
      },
      { merge: true },
    );
    closeEntries?.();
    if (Object.keys(statusPatch).length > 0) tx.set(statusRef(kit), statusPatch, { merge: true });
    return { released, cleared };
  });
  if (outcome.released) {
    logInfo({
      message: "Tickets : verrou des livraisons libéré, blocage relevé",
      feature: "tickets",
      ticketId,
    });
  }
  if (outcome.cleared > 0) {
    logInfo({
      message: `Tickets : file des livraisons vidée après un blocage (${outcome.cleared} entrée(s))`,
      feature: "tickets",
      ticketId,
    });
  }
  return reports.length;
}

/**
 * Prend le verrou des livraisons pour `ticketId`, en transaction, et réécrit `delivery_last`
 * (sans `reported_at`). Refuse (`delivery_running_elsewhere`, par `refuse`) si un autre ticket
 * le tient encore : échéance future et ticket verrouillé toujours `in_progress`. Refuse
 * (`delivery_queue_ahead`, par `refuseQueueAhead`) si la file n'est pas vide : les livraisons
 * partent dans l'ordre des accords (point 5). Un verrou du même ticket est écrasé : la règle
 * « en cours » du ticket a déjà décidé. Rend la valeur précédente de `delivery_last`, remise
 * par `releaseDeliveryLock` si rien ne part.
 */
export async function claimDeliveryLock(
  kit: FirestoreKit,
  ticketId: string,
  issueNumber: number,
  launchedAtMs: number,
  refuse: (message: string, otherTicketId: string) => Error,
  refuseQueueAhead: (waiting: number) => Error,
): Promise<{ previousLast: unknown }> {
  return kit.db.runTransaction(async (tx) => {
    const snap = await tx.get(statusRef(kit));
    const lock = readDeliveryLock(snap.get("delivery_running"), millisOf(kit));
    if (lock !== null && lock.ticketId !== ticketId && deliveryLockHeld(lock, launchedAtMs)) {
      const locked = /^[A-Za-z0-9_-]{1,128}$/.test(lock.ticketId as string)
        ? await tx.get(ticketRef(kit, lock.ticketId as string))
        : null;
      if (locked?.exists === true && locked.get("status") === "in_progress") {
        throw refuse(
          deliveryRunningElsewhereMessage(lock.issueNumber, lock.launchedAtMs),
          lock.ticketId as string,
        );
      }
    }
    const waiting = readDeliveryQueue(snap.get("delivery_queue"), millisOf(kit)).views.length;
    if (waiting > 0) throw refuseQueueAhead(waiting);
    const previousLast = snap.get("delivery_last") ?? null;
    tx.set(statusRef(kit), deliveryLockFields(kit, ticketId, issueNumber, launchedAtMs), {
      merge: true,
    });
    return { previousLast };
  });
}

/**
 * Départ de la file rendu (rien n'est parti) : entrée remise en tête, et file arrêtée si
 * `halt` est donné (`delivery_queue_halted`, effacé au prochain lancement réussi de la routine
 * de développement). Absente seulement : une entrée déjà remise n'est pas doublée. La file
 * peut alors compter `DELIVERY_QUEUE_MAX` + 1 entrées : un ajout pendant le départ (décision de
 * l'utilisateur du 2026-11-22).
 */
export interface QueueRestore {
  rawEntry: Record<string, unknown>;
  halt: { code: string; atMs: number } | null;
}

/**
 * Rend le verrou d'une livraison qui n'est pas partie (refus, panne avant l'appel, refus de
 * l'API) : seulement s'il porte encore ce ticket et ce lancement. `delivery_last` reprend sa
 * valeur précédente (`previousLast`) s'il est encore celui de ce lancement. `restore` (départ
 * de la file) : entrée remise en tête dans la même transaction, sans intervalle où la file et
 * le verrou sont libres ensemble. Au mieux, journalisé : le verrou expire seul à son échéance.
 */
export async function releaseDeliveryLock(
  kit: FirestoreKit,
  ticketId: string,
  launchedAtMs: number,
  previousLast: unknown = null,
  restore: QueueRestore | null = null,
): Promise<void> {
  try {
    await kit.db.runTransaction(async (tx) => {
      const snap = await tx.get(statusRef(kit));
      const patch: Record<string, unknown> = {};
      if (restore !== null) {
        const queue = readDeliveryQueue(snap.get("delivery_queue"), millisOf(kit));
        if (!queue.views.some((v) => v.ticketId === ticketId)) {
          patch.delivery_queue = [restore.rawEntry, ...queue.raw];
        }
        if (restore.halt !== null) {
          patch.delivery_queue_halted = {
            code: restore.halt.code,
            at: kit.Timestamp.fromMillis(restore.halt.atMs),
          };
        }
      }
      const lock = readDeliveryLock(snap.get("delivery_running"), millisOf(kit));
      if (lock !== null && lock.ticketId === ticketId && lock.launchedAtMs === launchedAtMs) {
        patch.delivery_running = null;
      }
      const last = readDeliveryLast(snap.get("delivery_last"), millisOf(kit));
      if (last !== null && last.ticketId === ticketId && last.launchedAtMs === launchedAtMs) {
        patch.delivery_last = previousLast;
      }
      if (Object.keys(patch).length > 0) tx.set(statusRef(kit), patch, { merge: true });
    });
  } catch (err) {
    logError({
      message:
        restore === null
          ? "Tickets : verrou des livraisons non rendu (expire seul en 3 h)"
          : "Tickets : verrou non rendu, entrée de la file non remise en tête",
      feature: "tickets",
      ticketId,
      error: err,
    });
  }
}

/** Ce que retient l'accord « Mettre en file » (point 3). */
export interface DeliveryQueueRequest {
  ticketId: string;
  issueNumber: number;
  prNumber: number;
  headSha: string;
  byUid: string;
  /** E-mail en minuscules tiré du jeton vérifié, jamais d'un argument. */
  byEmail: string;
}

/** Refus de la mise en file, dans l'ordre des contrôles (point 4). */
export type DeliveryQueueRefusal = "already" | "running_here" | "full" | "lock_free";

/**
 * « Mettre en file » (point 4), en transaction sur `ticket_status/launches` : ticket absent de
 * la file (`already`), qui ne tient pas le verrou (`running_here`), file non pleine
 * (`DELIVERY_QUEUE_MAX`, `full`) ; verrou libre, livraison précédente finie et file vide :
 * `lock_free` (« Livrer » suffit). Sinon l'entrée est ajoutée en fin de file. Rien n'est
 * compté. Rend la position (à partir de 1) et la taille de la file.
 */
export async function enqueueDelivery(
  kit: FirestoreKit,
  request: DeliveryQueueRequest,
  nowMs: number,
  refuse: (kind: DeliveryQueueRefusal) => Error,
): Promise<{ position: number; total: number }> {
  return kit.db.runTransaction(async (tx) => {
    const snap = await tx.get(statusRef(kit));
    const ms = millisOf(kit);
    const queue = readDeliveryQueue(snap.get("delivery_queue"), ms);
    if (queue.views.some((v) => v.ticketId === request.ticketId)) throw refuse("already");
    const lock = readDeliveryLock(snap.get("delivery_running"), ms);
    const held = deliveryLockHeld(lock, nowMs);
    if (held && lock?.ticketId === request.ticketId) throw refuse("running_here");
    if (queue.views.length >= DELIVERY_QUEUE_MAX) throw refuse("full");
    const finished = deliveryLastFinished(readDeliveryLast(snap.get("delivery_last"), ms), nowMs);
    if (!held && finished && queue.views.length === 0) throw refuse("lock_free");
    const entry = {
      ticket_id: request.ticketId,
      issue_number: request.issueNumber,
      pr_number: request.prNumber,
      head_sha: request.headSha,
      queued_at: kit.Timestamp.fromMillis(nowMs),
      by_uid: request.byUid,
      by_email: request.byEmail,
    };
    tx.set(statusRef(kit), { delivery_queue: [...queue.raw, entry] }, { merge: true });
    return { position: queue.raw.length + 1, total: queue.raw.length + 1 };
  });
}

/**
 * « Retirer de la file » (point 6) : entrée retirée en transaction, `queue_exit` noté avec
 * `delivery_queue_removed`. Aucun appel à GitHub ni à la routine. Rend `false` si le ticket
 * n'était pas en file.
 */
export async function unqueueDelivery(
  kit: FirestoreKit,
  ticketId: string,
  nowMs: number,
): Promise<boolean> {
  return kit.db.runTransaction(async (tx) => {
    const snap = await tx.get(statusRef(kit));
    return dequeueInTransaction(tx, kit, snap.data(), ticketId, QUEUE_EXIT_REMOVED, nowMs);
  });
}

/**
 * « Relancer la file » (décisions 9 et 10 de l'amendement, 2026-11-22 et 2026-11-23) : efface
 * `delivery_queue_halted` et `development_invalid_since` en transaction si `ticketId` est en
 * tête de file ; jamais `analysis_invalid_since` ni `ticket_status/github.token_invalid_since`.
 * Si le jeton de la routine est encore refusé, le départ suivant reçoit un 401, 403 ou 404, qui
 * repose `development_invalid_since`, rend compteur et verrou et remet l'entrée en tête. Ne lance rien, ne
 * compte rien, n'appelle ni GitHub ni la routine : le départ se fait ensuite par
 * `startQueuedDelivery`, avec tous ses contrôles. Rend `not_head` si le ticket n'est pas en
 * tête (refus), `not_halted` si aucun des deux champs n'est posé (rien n'est écrit), `cleared`
 * sinon.
 */
export async function resumeHaltedQueue(
  kit: FirestoreKit,
  ticketId: string,
): Promise<"cleared" | "not_halted" | "not_head"> {
  return kit.db.runTransaction(async (tx) => {
    const snap = await tx.get(statusRef(kit));
    const first = readDeliveryQueue(snap.get("delivery_queue"), millisOf(kit)).views[0];
    if (first === undefined || first.ticketId !== ticketId) return "not_head";
    const posed = (v: unknown) => v !== null && v !== undefined;
    const patch: Record<string, null> = {};
    if (posed(snap.get("delivery_queue_halted"))) patch.delivery_queue_halted = null;
    if (posed(snap.get("development_invalid_since"))) patch.development_invalid_since = null;
    if (Object.keys(patch).length === 0) return "not_halted";
    tx.set(statusRef(kit), patch, { merge: true });
    return "cleared";
  });
}

/**
 * Retire la tête de file si c'est encore `head` (même ticket, même `queued_at`) et note
 * `queue_exit` (`code`). Rend vrai si retirée. Lève sur une panne Firestore.
 */
export async function dequeueHead(
  kit: FirestoreKit,
  head: DeliveryQueueEntryView,
  code: string,
  nowMs: number,
): Promise<boolean> {
  return kit.db.runTransaction(async (tx) => {
    const snap = await tx.get(statusRef(kit));
    const first = readDeliveryQueue(snap.get("delivery_queue"), millisOf(kit)).views[0];
    if (first === undefined || !sameQueueEntry(first, head)) return false;
    return dequeueInTransaction(tx, kit, snap.data(), head.ticketId, code, nowMs);
  });
}

/** Vrai si deux entrées sont le même accord : même ticket, même `queued_at`. Pure. */
export function sameQueueEntry(a: DeliveryQueueEntryView, b: DeliveryQueueEntryView): boolean {
  return a.ticketId === b.ticketId && a.queuedAtMs !== null && a.queuedAtMs === b.queuedAtMs;
}

/**
 * Ticket sorti de `in_progress` (livré, refusé, clos, revenu en arrière) : le verrou qu'il
 * tient est libéré et ses entrées `livraison` en cours sont closes (P44, question 5 A) ; s'il
 * est en file, il en sort (`delivery_queue_left_in_progress`). Avec `ticketId` nul (passe
 * horaire), le ticket verrouillé est relu et le verrou libéré s'il n'est plus `in_progress`.
 * Au mieux, journalisé.
 */
export async function releaseDeliveryLockIfLeft(
  kit: FirestoreKit,
  ticketId: string | null,
  nowMs: number,
): Promise<void> {
  try {
    const outcome = await kit.db.runTransaction(async (tx) => {
      const snap = await tx.get(statusRef(kit));
      const status = snap.data();
      const lock = readDeliveryLock(snap.get("delivery_running"), millisOf(kit));
      const lockedId =
        lock !== null &&
        (ticketId === null || lock.ticketId === ticketId) &&
        /^[A-Za-z0-9_-]{1,128}$/.test(lock.ticketId as string)
          ? (lock.ticketId as string)
          : null;
      const queuedId =
        ticketId !== null &&
        /^[A-Za-z0-9_-]{1,128}$/.test(ticketId) &&
        readDeliveryQueue(snap.get("delivery_queue"), millisOf(kit)).views.some(
          (v) => v.ticketId === ticketId,
        )
          ? ticketId
          : null;
      const targetId = lockedId ?? queuedId;
      if (targetId === null) return { released: null, dequeued: false };
      const target = await tx.get(ticketRef(kit, targetId));
      if (target.exists && target.get("status") === "in_progress") {
        return { released: null, dequeued: false };
      }
      const closeEntries =
        lockedId !== null && target.exists
          ? await closeDeliveryEntries(tx, kit, lockedId, nowMs)
          : null;
      const dequeued =
        queuedId !== null &&
        target.exists &&
        dequeueInTransaction(tx, kit, status, queuedId, QUEUE_EXIT_LEFT_IN_PROGRESS, nowMs);
      if (lockedId !== null) tx.set(statusRef(kit), { delivery_running: null }, { merge: true });
      closeEntries?.();
      return { released: lockedId, dequeued };
    });
    if (outcome.released !== null) {
      logInfo({
        message: "Tickets : verrou des livraisons libéré, ticket sorti de « En cours »",
        feature: "tickets",
        ticketId: outcome.released,
      });
    }
    if (outcome.dequeued) {
      logInfo({
        message: "Tickets : ticket sorti de la file des livraisons, sorti de « En cours »",
        feature: "tickets",
        ticketId: ticketId ?? undefined,
      });
    }
  } catch (err) {
    logError({
      message: "Tickets : verrou des livraisons non libéré après un changement de statut",
      feature: "tickets",
      ticketId: ticketId ?? undefined,
      error: err,
    });
  }
}

/**
 * Vrai si une livraison de ce ticket est en cours : verrou qui le porte, échéance future.
 * Lu dans la transaction de prise d'une décision (Refuser, Clore, P44).
 */
export async function deliveryRunningFor(
  tx: Transaction,
  kit: FirestoreKit,
  ticketId: string,
  nowMs: number,
): Promise<boolean> {
  const snap = await tx.get(statusRef(kit));
  const lock = readDeliveryLock(snap.get("delivery_running"), millisOf(kit));
  return lock !== null && lock.ticketId === ticketId && deliveryLockHeld(lock, nowMs);
}
