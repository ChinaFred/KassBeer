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
 * - fichiers : trois catégories (ADR-020, R2) écrites une seule fois ici
 *   (`FORBIDDEN_DEVELOPMENT_PATTERNS`, `NETWORK_RULES_PATTERNS`,
 *   `SENSITIVE_DELIVERY_PATTERNS`) et comparées au point 5, à L3a et à L3b du prompt de
 *   développement par `functions/test/prompts.test.ts` (P65) ;
 * - règles du réseau : fichiers et contrôles `Pn` changés, relus à chaque relecture ; accord
 *   de l'administrateur lié à la tête de la PR (`network_rules_ack`), annulé par un nouveau
 *   commit (P45).
 *
 * `tickets/{id}/admin/delivery` (P45) et `ticket_status/launches.delivery_running` (P44) sont
 * écrits par le serveur seul et lus par l'administrateur seul. Aucun titre ni corps de PR n'y
 * est écrit (P24), et du patch de `CLAUDE.md` seuls les numéros `Pn` sont gardés. Pour une
 * livraison, le serveur n'écrit sur GitHub que le commentaire d'accord du mode
 * `network_rules`, sur gabarit fixe.
 *
 * Les fonctions qui lisent ou écrivent reçoivent le client Firestore (`kit`) et le client
 * GitHub de l'appelant : rien n'est construit au chargement du module (P26).
 */

import { randomInt } from "node:crypto";

import type { Transaction } from "firebase-admin/firestore";

import {
  COLL_TICKET_STATUS,
  COLL_TICKETS,
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
  /** Règles du réseau touchées par la PR (ADR-020, P45), quatre au plus. */
  network_rules_files: string[];
  /** Numéros `Pn` changés dans `CLAUDE.md`, triés, 60 au plus. */
  network_rules_controls: number[];
  /** Faux si `CLAUDE.md` change sans `patch` rendu par GitHub. */
  network_rules_controls_complete: boolean;
  /** Premier chemin des catégories 1 ou 3, ou `null`. */
  sensitive_files: string | null;
  /** Faux si la liste des fichiers dépasse 1 000 entrées. */
  files_complete: boolean;
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
 * échapper à la lecture. Les fichiers ne changent pas `ready` : ils sont décrits à part
 * (règles du réseau, fichier sensible) et se recontrôlent au lancement (P43, P45). Pure.
 */
export function deliveryState(args: {
  ticketStatus: unknown;
  prListComplete: boolean;
  eligible: readonly PullRequestView[];
  /** Détail relu de la PR éligible quand elle est seule, sinon `null`. */
  pr: PullRequestView | null;
  ci: CiSummary;
  /** Fichiers de la PR éligible quand elle est seule, sinon `null`. */
  files?: PullRequestFiles | null;
}): DeliveryState {
  const single =
    args.prListComplete && args.eligible.length === 1 ? (args.pr ?? args.eligible[0]) : null;
  const ci = single === null ? ciSummary([]) : args.ci;
  const files = deliveryFilesState(single === null ? null : (args.files ?? null));
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
    ...files,
  };
}

// ── Trois catégories de fichiers (P43, P65, logique dupliquée avec le prompt) ─

/*
 * Motifs depuis la racine : un motif qui commence par deux étoiles et une barre vaut pour un
 * nom de fichier à toute profondeur, un motif qui finit par une barre et deux étoiles pour
 * tout un dossier, une étoile seule pour un segment. Casse ignorée. Chaque liste est écrite
 * une seule fois ici ; le point 5, L3a et L3b du prompt de développement
 * (`documentation/prompts-routines.md`) en sont les copies, comparées par
 * `functions/test/prompts.test.ts` (tableau « Logique dupliquée » de `CLAUDE.md`, P65).
 */

/**
 * Catégorie 1 (ADR-020) : fichiers que la session de développement ne touche jamais et
 * qu'une livraison ne fusionne jamais. Liste d'ADR-008 « Livraison », plus les ajouts des
 * décisions de l'utilisateur du 2026-11-14 (`gradlew`, `gradlew.bat`, build hooks Dart
 * `hook/`, tout dossier `.claude/`). Les chemins exacts de `NETWORK_RULES_PATTERNS` en sont
 * retirés (`CLAUDE.md` à la racine, les deux fichiers de `changelog-recent`) : tout autre
 * fichier de `scripts/` et tout `CLAUDE.md` d'un sous-dossier restent interdits (décision 2).
 */
export const FORBIDDEN_DEVELOPMENT_PATTERNS: readonly string[] = [
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
];

/**
 * Catégorie 2 (ADR-020, décisions 2 et 6) : règles du réseau. Chemins exacts depuis la
 * racine, casse comprise : un `claude.md` en minuscules ou un `Scripts/…` reste dans la
 * catégorie 1. Permis à la session de développement ; livrés seulement après un accord de
 * l'administrateur lié à la tête de la PR (mode `network_rules` de `launchTicketDelivery`).
 * Liste fermée : l'étendre demande un ADR (P65).
 */
export const NETWORK_RULES_PATTERNS: readonly string[] = [
  "CLAUDE.md",
  "scripts/changelog-recent.mjs",
  "scripts/changelog-recent.test.mjs",
  "documentation/prompts-routines.md",
];

/**
 * Catégorie 3 : permis à la session de développement, jamais livrés par la routine (fusion à
 * la main). Les trois `pubspec.lock` (un nouveau paquet exécute son code de construction dans
 * le job `build` de `deploy.yml`, qui détient les secrets de signature) et les fichiers qui
 * portent le contrôle des livraisons (décisions de l'utilisateur du 2026-11-14).
 */
export const DELIVERY_ONLY_SENSITIVE_PATTERNS: readonly string[] = [
  "app/pubspec.lock",
  "brewing/pubspec.lock",
  "exchange/pubspec.lock",
  "functions/src/auth.ts",
  "functions/src/config.ts",
  "functions/src/tickets/delivery.ts",
  "test-fixtures/member_access.json",
];

/**
 * Fichiers qu'une livraison ne fusionne jamais : union des catégories 1 et 3, dans cet
 * ordre. Copie : bloc L3a du prompt.
 */
export const SENSITIVE_DELIVERY_PATTERNS: readonly string[] = [
  ...FORBIDDEN_DEVELOPMENT_PATTERNS,
  ...DELIVERY_ONLY_SENSITIVE_PATTERNS,
];

/** Un motif de ces listes en expression régulière, casse ignorée. Pure. */
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
const FORBIDDEN_REGEXPS = FORBIDDEN_DEVELOPMENT_PATTERNS.map(sensitivePatternRegExp);

/** Vrai si ce chemin est un fichier des règles du réseau (catégorie 2, chemin exact). Pure. */
export function isNetworkRulesPath(path: string): boolean {
  return NETWORK_RULES_PATTERNS.includes(path);
}

/** Vrai si la session de développement ne touche jamais ce chemin (catégorie 1). Pure. */
export function isForbiddenDevelopmentPath(path: string): boolean {
  return !isNetworkRulesPath(path) && FORBIDDEN_REGEXPS.some((re) => re.test(path));
}

/**
 * Vrai si une livraison ne fusionne jamais ce chemin (catégories 1 et 3, casse ignorée). Un
 * chemin des règles du réseau n'en est pas : il se livre après accord. Pure.
 */
export function isSensitiveDeliveryPath(path: string): boolean {
  return !isNetworkRulesPath(path) && SENSITIVE_REGEXPS.some((re) => re.test(path));
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

/**
 * Les chemins des règles du réseau que touche la PR (nouveaux et anciens chemins), sans
 * doublon, dans l'ordre de `NETWORK_RULES_PATTERNS` : quatre au plus. Pure.
 */
export function networkRulesFiles(files: readonly PullRequestFileView[]): string[] {
  const seen = new Set<string>();
  for (const f of files) {
    for (const path of [f.filename, f.previousFilename]) {
      if (typeof path === "string" && isNetworkRulesPath(path)) seen.add(path);
    }
  }
  return NETWORK_RULES_PATTERNS.filter((p) => seen.has(p));
}

/** Le fichier dont le `patch` donne les contrôles changés. */
export const NETWORK_RULES_CONTROLS_FILE = "CLAUDE.md";

/** Contrôles gardés au plus (P45). */
export const NETWORK_RULES_CONTROLS_MAX = 60;

/** Ligne ajoutée ou retirée d'une ligne du tableau « Contrôles propres au projet » (P45). */
const CONTROL_LINE = /^[+-]\| P([0-9]{1,3}) \|/;

/**
 * Les numéros des contrôles `Pn` ajoutés, retirés ou modifiés, lus dans le `patch` de
 * `CLAUDE.md` : lignes qui commencent par `+| P` ou `-| P`. Sans doublon, triés, 60 au plus.
 * Rien d'autre du patch n'est gardé (P45). `complete` faux si `CLAUDE.md` change sans `patch`
 * rendu par GitHub, s'il n'apparaît que comme ancien chemin d'un renommage, ou si plus de 60
 * numéros sont relevés. Pure.
 */
export function networkRulesControls(files: readonly PullRequestFileView[]): {
  controls: number[];
  complete: boolean;
} {
  const file = files.find((f) => f.filename === NETWORK_RULES_CONTROLS_FILE);
  if (file === undefined) {
    // `CLAUDE.md` renommé ailleurs : son patch ne dit pas les contrôles retirés.
    const renamed = files.some((f) => f.previousFilename === NETWORK_RULES_CONTROLS_FILE);
    return { controls: [], complete: !renamed };
  }
  if (typeof file.patch !== "string") return { controls: [], complete: false };
  const found = new Set<number>();
  for (const line of file.patch.split(/\r?\n/)) {
    const m = CONTROL_LINE.exec(line);
    if (m !== null) found.add(Number(m[1]));
  }
  return {
    controls: [...found].sort((a, b) => a - b).slice(0, NETWORK_RULES_CONTROLS_MAX),
    // Plus de 60 numéros : la liste affichée serait tronquée.
    complete: found.size <= NETWORK_RULES_CONTROLS_MAX,
  };
}

/** Le `patch` à garder le temps de la lecture : celui de `CLAUDE.md` à la racine seul. */
export function keepNetworkRulesPatch(filename: string): boolean {
  return filename === NETWORK_RULES_CONTROLS_FILE;
}

/** Ce que `admin/delivery` retient des fichiers de la PR éligible (P45). */
export interface DeliveryFilesState {
  network_rules_files: string[];
  network_rules_controls: number[];
  network_rules_controls_complete: boolean;
  sensitive_files: string | null;
  files_complete: boolean;
}

/** Sans PR retenue : aucune règle, rien de sensible. */
export const NO_DELIVERY_FILES: DeliveryFilesState = {
  network_rules_files: [],
  network_rules_controls: [],
  network_rules_controls_complete: true,
  sensitive_files: null,
  files_complete: true,
};

/** Fichiers de la PR lus (`listPullRequestFiles`). */
export type PullRequestFiles = { files: PullRequestFileView[]; complete: boolean };

/** L'état des fichiers d'une PR. Pure. */
export function deliveryFilesState(list: PullRequestFiles | null): DeliveryFilesState {
  if (list === null) return { ...NO_DELIVERY_FILES };
  const controls = networkRulesControls(list.files);
  return {
    network_rules_files: networkRulesFiles(list.files),
    network_rules_controls: controls.controls,
    network_rules_controls_complete: controls.complete,
    sensitive_files: sensitiveDeliveryPath(list.files),
    files_complete: list.complete,
  };
}

// ── Accord sur les règles du réseau (P24, P43, P45) ─────────────────────────

export const NETWORK_RULES_ACK_TITLE = "## Accord — règles du réseau";

/**
 * Gabarit du commentaire d'accord, fixe : aucun texte venu de la PR ni de l'Issue. Le bloc
 * L3b du prompt de développement le cite à l'identique (test de `prompts.test.ts`).
 */
export const NETWORK_RULES_ACK_TEMPLATE: readonly string[] = [
  NETWORK_RULES_ACK_TITLE,
  "",
  "PR #<M>",
  "Tête <head_sha>",
  "Fichiers : <fichiers>",
  "Contrôles : <contrôles>",
  "",
  "Accord <ack_id>",
];

/** `ack_id` : tiré par le serveur. */
export const ACK_ID_PATTERN = /^[A-Za-z0-9]{20}$/;
const HEAD_SHA_PATTERN = /^[0-9a-f]{40}$/;

/** Ligne `Accord <id>` d'un accord. */
export function ackLine(ackId: string): string {
  return `Accord ${ackId}`;
}

/** Un accord lu dans `admin/delivery.network_rules_ack`. */
export interface NetworkRulesAck {
  head_sha: string;
  ack_id: string;
  comment_id: number | null;
  files: string[];
  controls: number[];
  atMs: number | null;
}

/** L'accord stocké, ou `null` s'il est absent ou illisible. Pure. */
export function readNetworkRulesAck(
  raw: unknown,
  toMillis: (v: unknown) => number | null,
): NetworkRulesAck | null {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.head_sha !== "string" || !HEAD_SHA_PATTERN.test(r.head_sha)) return null;
  if (typeof r.ack_id !== "string" || !ACK_ID_PATTERN.test(r.ack_id)) return null;
  const files = Array.isArray(r.files) ? r.files.filter((f) => typeof f === "string") : [];
  const controls = Array.isArray(r.controls)
    ? r.controls.filter((c): c is number => typeof c === "number" && Number.isSafeInteger(c))
    : [];
  return {
    head_sha: r.head_sha,
    ack_id: r.ack_id,
    comment_id:
      typeof r.comment_id === "number" && Number.isSafeInteger(r.comment_id) ? r.comment_id : null,
    files: files as string[],
    controls,
    atMs: toMillis(r.at),
  };
}

/**
 * Vrai si l'accord vaut pour la tête `headSha` : même tête, commentaire publié. Un nouveau
 * commit change la tête et annule l'accord sans écriture de plus. Pure.
 */
export function networkRulesAckValid(ack: NetworkRulesAck | null, headSha: string | null): boolean {
  return ack !== null && headSha !== null && ack.head_sha === headSha && ack.comment_id !== null;
}

/** Vrai si l'accord stocké porte la même tête, les mêmes fichiers et les mêmes contrôles. */
export function sameNetworkRulesAck(
  ack: NetworkRulesAck | null,
  headSha: string,
  files: readonly string[],
  controls: readonly number[],
): boolean {
  return (
    ack !== null &&
    ack.head_sha === headSha &&
    ack.files.length === files.length &&
    ack.files.every((f, i) => f === files[i]) &&
    ack.controls.length === controls.length &&
    ack.controls.every((c, i) => c === controls[i])
  );
}

/**
 * Le corps du commentaire d'accord, sur `NETWORK_RULES_ACK_TEMPLATE`. Les chemins viennent de
 * la liste fermée de la catégorie 2, les contrôles sont des nombres, la tête et `ack_id` sont
 * contrôlés par leur motif : lève sinon. Pure.
 */
export function networkRulesAckBody(args: {
  prNumber: number;
  headSha: string;
  files: readonly string[];
  controls: readonly number[];
  ackId: string;
}): string {
  if (!Number.isSafeInteger(args.prNumber) || args.prNumber < 1) {
    throw new Error("Accord : numéro de PR illisible");
  }
  if (!HEAD_SHA_PATTERN.test(args.headSha)) throw new Error("Accord : tête illisible");
  if (!ACK_ID_PATTERN.test(args.ackId)) throw new Error("Accord : identifiant illisible");
  if (args.files.length === 0 || !args.files.every((f) => isNetworkRulesPath(f))) {
    throw new Error("Accord : fichier hors des règles du réseau");
  }
  if (!args.controls.every((c) => Number.isSafeInteger(c) && c >= 0 && c <= 999)) {
    throw new Error("Accord : contrôle illisible");
  }
  const controls =
    args.controls.length === 0 ? "aucun" : args.controls.map((c) => `P${c}`).join(", ");
  const values: Record<string, string> = {
    "<M>": String(args.prNumber),
    "<head_sha>": args.headSha,
    "<fichiers>": args.files.join(", "),
    "<contrôles>": controls,
    "<ack_id>": args.ackId,
  };
  return NETWORK_RULES_ACK_TEMPLATE.map((line) =>
    line.replace(/<[^>]+>/, (key) => values[key] ?? key),
  ).join("\n");
}

/**
 * Vrai si un commentaire du compte `maintainerId` porte la ligne `Accord <id>` : un essai
 * précédent l'a déjà publié (P26). Pure.
 */
export function commentCarriesAck(
  comment: Pick<CommentView, "authorId" | "body">,
  ackId: string,
  maintainerId: number,
): boolean {
  if (comment.authorId !== maintainerId || typeof comment.body !== "string") return false;
  const marker = ackLine(ackId);
  return comment.body.split(/\r?\n/).some((line) => line.trim() === marker);
}

const ACK_ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

/** Un `ack_id` neuf : 20 caractères alphanumériques tirés au hasard. */
export function newAckId(): string {
  let out = "";
  for (let i = 0; i < 20; i++) out += ACK_ID_ALPHABET[randomInt(ACK_ID_ALPHABET.length)];
  return out;
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

/** Mode `deliver` sur une PR qui change les règles du réseau (`delivery_network_rules`). */
export const DELIVERY_NETWORK_RULES_MESSAGE =
  "Cette PR change les règles du réseau : utilisez « Approuver les règles et livrer ». " +
  DELIVERY_NOTHING;

/** Mode `network_rules`, tête relue différente de celle affichée (`delivery_head_changed`). */
export const DELIVERY_HEAD_CHANGED_MESSAGE =
  "La PR a changé depuis l'affichage. Relisez-la, puis approuvez à nouveau. " + DELIVERY_NOTHING;

/** Mode `network_rules` sur une PR sans règle du réseau (`delivery_no_network_rules`). */
export const DELIVERY_NO_NETWORK_RULES_MESSAGE =
  "Cette PR ne change pas les règles du réseau : utilisez « Livrer ». " + DELIVERY_NOTHING;

/** `CLAUDE.md` changé sans `patch` (`delivery_network_rules_unreadable`). */
export const DELIVERY_NETWORK_RULES_UNREADABLE_MESSAGE =
  "Les contrôles changés ne peuvent pas être lus : fusionnez-la vous-même après relecture. " +
  DELIVERY_NOTHING;

/** Accord non publié sur l'Issue (`delivery_ack_publish_failed`). */
export const DELIVERY_ACK_PUBLISH_FAILED_MESSAGE =
  "L'accord n'a pas pu être publié sur GitHub. Réessayez. " + DELIVERY_NOTHING;

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
 * Écrit l'état « PR prête » (fusion : les comptes rendus et l'accord restent), avec
 * `network_rules_ack_valid` recalculé sur la tête relue, en transaction avec l'accord stocké :
 * un nouveau commit annule l'accord sans autre écriture (P45). Lève sur une panne.
 */
export async function writeDeliveryState(
  kit: FirestoreKit,
  ticketId: string,
  state: DeliveryState,
): Promise<void> {
  const ref = deliveryRef(kit, ticketId);
  await kit.db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    const ack = readNetworkRulesAck(current.get("network_rules_ack"), millisOf(kit));
    tx.set(
      ref,
      {
        ...state,
        ci_completed_at: timestampOrNull(kit, state.ci_completed_at),
        network_rules_ack_valid: networkRulesAckValid(ack, state.head_sha),
        updated_at: kit.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

/** Ce que l'accord en cours de publication retient. */
export interface PendingNetworkRulesAck {
  ackId: string;
  /** Identifiant du commentaire déjà publié pour ce même accord, ou `null`. */
  commentId: number | null;
}

/**
 * Étape 6 du mode `network_rules` (ADR-020), dans la transaction du bail : le bail du
 * lancement est relu (`leaseUntilMs`), puis l'accord stocké est repris s'il porte la même
 * tête, les mêmes fichiers et les mêmes contrôles (même `ack_id`, commentaire déjà publié
 * compris), sinon un accord neuf est écrit sans `comment_id`. `network_rules_ack_valid`
 * recalculé. Lève `refuse()` si le bail n'est plus celui du lancement.
 */
export async function claimNetworkRulesAck(
  kit: FirestoreKit,
  ticketId: string,
  args: {
    leaseUntilMs: number;
    headSha: string;
    files: readonly string[];
    controls: readonly number[];
    nowMs: number;
    newId: () => string;
  },
  refuse: () => Error,
): Promise<PendingNetworkRulesAck> {
  const ref = deliveryRef(kit, ticketId);
  const toMillis = millisOf(kit);
  return kit.db.runTransaction(async (tx) => {
    const [ticket, current] = await Promise.all([tx.get(ticketRef(kit, ticketId)), tx.get(ref)]);
    if (toMillis(ticket.get("decision_lease_until")) !== args.leaseUntilMs) throw refuse();
    const stored = readNetworkRulesAck(current.get("network_rules_ack"), toMillis);
    if (sameNetworkRulesAck(stored, args.headSha, args.files, args.controls)) {
      const ack = stored as NetworkRulesAck;
      return { ackId: ack.ack_id, commentId: ack.comment_id };
    }
    const ackId = args.newId();
    tx.set(
      ref,
      {
        network_rules_ack: {
          head_sha: args.headSha,
          at: kit.Timestamp.fromMillis(args.nowMs),
          ack_id: ackId,
          comment_id: null,
          files: [...args.files],
          controls: [...args.controls],
        },
        network_rules_ack_valid: false,
      },
      { merge: true },
    );
    return { ackId, commentId: null };
  });
}

/**
 * Note le commentaire publié de l'accord `ackId`, s'il est toujours l'accord stocké, et
 * recalcule `network_rules_ack_valid` sur la tête stockée. Lève sur une panne.
 */
export async function recordNetworkRulesAckComment(
  kit: FirestoreKit,
  ticketId: string,
  ackId: string,
  commentId: number,
): Promise<boolean> {
  const ref = deliveryRef(kit, ticketId);
  const toMillis = millisOf(kit);
  return kit.db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    const stored = readNetworkRulesAck(current.get("network_rules_ack"), toMillis);
    if (stored === null || stored.ack_id !== ackId) return false;
    const headSha = current.get("head_sha");
    const ack = { ...stored, comment_id: commentId };
    tx.set(
      ref,
      {
        network_rules_ack: { ...current.get("network_rules_ack"), comment_id: commentId },
        network_rules_ack_valid: networkRulesAckValid(
          ack,
          typeof headSha === "string" ? headSha : null,
        ),
      },
      { merge: true },
    );
    return true;
  });
}

/**
 * Commentaire d'accord déjà publié (ligne `Accord <id>` d'un commentaire du compte
 * 16348852), relu sur les dernières pages de l'Issue, ou `null`.
 */
export async function findAckComment(
  client: GithubClient,
  issueNumber: number,
  commentCount: number,
  ackId: string,
): Promise<number | null> {
  if (commentCount < 1) return null;
  for await (const page of client.lastCommentsFirst(issueNumber, commentCount)) {
    for (const comment of page) {
      if (commentCarriesAck(comment, ackId, GITHUB_MAINTAINER_ID) && comment.id !== null) {
        return comment.id;
      }
    }
  }
  return null;
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

/** Ce qu'une relecture établit, avec la PR éligible et ses fichiers quand elle est seule. */
export interface DeliveryReading {
  state: DeliveryState;
  pr: PullRequestView | null;
  files: PullRequestFiles | null;
}

/**
 * Relit sur GitHub ce qui fait une « PR prête » pour l'Issue `issueNumber` : PR ouvertes
 * (`openPrs` de l'appelant, sinon relues), détail de la PR éligible quand elle est seule, ses
 * fichiers (10 pages de 100 au plus, `patch` de `CLAUDE.md` seul gardé, ADR-020) et les runs
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
  let files: PullRequestFiles | null = null;
  let ci = ciSummary([]);
  if (list.complete && eligible.length === 1) {
    const detail = await client.getPullRequest(eligible[0].number);
    if (isEligibleDeliveryPr(detail, issueNumber)) {
      pr = detail;
      files = await client.listPullRequestFiles(detail.number, keepNetworkRulesPatch);
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
      files,
    }),
    pr,
    files,
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
  let files: PullRequestFiles | null = null;
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
      if (eligible && files === null) {
        files = await client.listPullRequestFiles(pr.number, keepNetworkRulesPatch);
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
          files: eligible ? files : null,
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
 * blocage marquée `ended_by: "blocked"`, son `retry_after` ramené à l'heure du relevé. Une
 * transaction. Rend le nombre de comptes
 * rendus. Lève sur une panne Firestore ; l'appelant journalise.
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
  const released = await kit.db.runTransaction(async (tx) => {
    const [current, status] = await Promise.all([tx.get(ref), tx.get(statusRef(kit))]);
    const closeEntries =
      blockedAtMs === null
        ? null
        : await rewriteDeliveryEntries(tx, kit, ticketId, (entries, views) =>
            blockedDeliveryEntries(entries, views, blockedAtMs, nowMs, (ms) =>
              kit.Timestamp.fromMillis(ms),
            ),
          );
    if (reports.length === 0 && !current.exists) return false;
    tx.set(
      ref,
      {
        reports: reports.map((r) => ({
          ...r,
          created_at: timestampOrNull(kit, r.created_at),
          updated_at: timestampOrNull(kit, r.updated_at),
        })),
        reports_checked_at: kit.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    closeEntries?.();
    const lock = readDeliveryLock(status.get("delivery_running"), millisOf(kit));
    if (!blockageReleasesLock(lock, ticketId, blockedAtMs)) return false;
    tx.set(statusRef(kit), { delivery_running: null }, { merge: true });
    return true;
  });
  if (released) {
    logInfo({
      message: "Tickets : verrou des livraisons libéré, blocage relevé",
      feature: "tickets",
      ticketId,
    });
  }
  return reports.length;
}

/**
 * Prend le verrou des livraisons pour `ticketId`, en transaction. Refuse
 * (`delivery_running_elsewhere`, par `refuse`) si un autre ticket le tient encore : échéance
 * future et ticket verrouillé toujours `in_progress`. Un verrou du même ticket est écrasé :
 * la règle « en cours » du ticket a déjà décidé.
 */
export async function claimDeliveryLock(
  kit: FirestoreKit,
  ticketId: string,
  issueNumber: number,
  launchedAtMs: number,
  refuse: (message: string, otherTicketId: string) => Error,
): Promise<void> {
  await kit.db.runTransaction(async (tx) => {
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
    tx.set(
      statusRef(kit),
      {
        delivery_running: {
          ticket_id: ticketId,
          issue_number: issueNumber,
          launched_at: kit.Timestamp.fromMillis(launchedAtMs),
          retry_after: kit.Timestamp.fromMillis(launchedAtMs + LAUNCH_RETRY_MS.livraison),
        },
      },
      { merge: true },
    );
  });
}

/**
 * Rend le verrou d'une livraison qui n'est pas partie (refus, panne avant l'appel, refus de
 * l'API) : seulement s'il porte encore ce ticket et ce lancement. Au mieux, journalisé : le
 * verrou expire seul à son échéance.
 */
export async function releaseDeliveryLock(
  kit: FirestoreKit,
  ticketId: string,
  launchedAtMs: number,
): Promise<void> {
  try {
    await kit.db.runTransaction(async (tx) => {
      const snap = await tx.get(statusRef(kit));
      const lock = readDeliveryLock(snap.get("delivery_running"), millisOf(kit));
      if (lock === null || lock.ticketId !== ticketId || lock.launchedAtMs !== launchedAtMs) return;
      tx.set(statusRef(kit), { delivery_running: null }, { merge: true });
    });
  } catch (err) {
    logError({
      message: "Tickets : verrou des livraisons non rendu (expire seul en 3 h)",
      feature: "tickets",
      ticketId,
      error: err,
    });
  }
}

/**
 * Ticket sorti de `in_progress` (livré, refusé, clos, revenu en arrière) : le verrou qu'il
 * tient est libéré et ses entrées `livraison` en cours sont closes (P44, question 5 A). Avec
 * `ticketId` nul (passe horaire), le ticket verrouillé est relu et le verrou libéré s'il
 * n'est plus `in_progress`. Au mieux, journalisé.
 */
export async function releaseDeliveryLockIfLeft(
  kit: FirestoreKit,
  ticketId: string | null,
  nowMs: number,
): Promise<void> {
  try {
    const released = await kit.db.runTransaction(async (tx) => {
      const snap = await tx.get(statusRef(kit));
      const lock = readDeliveryLock(snap.get("delivery_running"), millisOf(kit));
      if (lock === null || (ticketId !== null && lock.ticketId !== ticketId)) return null;
      const lockedId = lock.ticketId as string;
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(lockedId)) return null;
      const locked = await tx.get(ticketRef(kit, lockedId));
      if (locked.exists && locked.get("status") === "in_progress") return null;
      const closeEntries = locked.exists
        ? await closeDeliveryEntries(tx, kit, lockedId, nowMs)
        : null;
      tx.set(statusRef(kit), { delivery_running: null }, { merge: true });
      closeEntries?.();
      return lockedId;
    });
    if (released !== null) {
      logInfo({
        message: "Tickets : verrou des livraisons libéré, ticket sorti de « En cours »",
        feature: "tickets",
        ticketId: released,
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
