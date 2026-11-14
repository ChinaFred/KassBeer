/**
 * Règles pures des tickets (ADR-006) : gabarit de l'Issue, statut lu sur GitHub, plafond
 * du jour, réponse de l'administrateur, PR de livraison et version à son commit.
 * Aucune lecture ni écriture ici : `publish.ts` et `sync.ts` lisent et écrivent.
 */

import { publicText, singleLine, storedReplyText } from "./text";

// ── Types, statuts, étiquettes ──────────────────────────────────────────────

export const TICKET_TYPES = ["bug", "evolution", "feature"] as const;
export type TicketType = (typeof TICKET_TYPES)[number];

export const TICKET_PLATFORMS = ["android", "web"] as const;
export type TicketPlatform = (typeof TICKET_PLATFORMS)[number];

export const TICKET_STATUSES = [
  "pending",
  "received",
  "analyzed",
  "validated",
  "in_progress",
  "delivered",
  "refused",
  "closed",
  "send_failed",
  "over_quota",
] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];

/** Statuts d'un ticket publié, que la tâche horaire relit sur GitHub. */
export type PublishedStatus =
  "received" | "analyzed" | "validated" | "in_progress" | "delivered" | "refused" | "closed";

/** Statuts d'une Issue ouverte, relus aussi pour reconnaître une Issue disparue. */
export const OPEN_STATUSES: readonly PublishedStatus[] = [
  "received",
  "analyzed",
  "validated",
  "in_progress",
];

const FINAL_STATUSES: readonly PublishedStatus[] = ["delivered", "refused", "closed"];

const OPEN_RANK: Record<string, number> = {
  received: 1,
  analyzed: 2,
  validated: 3,
  in_progress: 4,
};

export function isTicketType(value: unknown): value is TicketType {
  return typeof value === "string" && (TICKET_TYPES as readonly string[]).includes(value);
}

export function isTicketPlatform(value: unknown): value is TicketPlatform {
  return typeof value === "string" && (TICKET_PLATFORMS as readonly string[]).includes(value);
}

export function isPublishedStatus(value: unknown): value is PublishedStatus {
  return (
    typeof value === "string" &&
    ((OPEN_STATUSES as readonly string[]).includes(value) ||
      (FINAL_STATUSES as readonly string[]).includes(value))
  );
}

export const LABEL_SOURCE_APP = "source:app";
/** Posée à la publication, et de nouveau par « Répondre » (ADR-008). */
export const LABEL_TO_ANALYZE = "statut:à-analyser";
/** Posée par la session d'analyse : le ticket passe `analyzed` (ADR-008). */
export const LABEL_ANALYZED = "statut:analysé";
export const LABEL_VALIDATED = "validé";
export const LABEL_IN_PROGRESS = "statut:en-cours";
export const LABEL_CLOSED = "statut:clos";

/** Étiquettes posées à la création de l'Issue. */
export function creationLabels(type: TicketType): string[] {
  return [LABEL_SOURCE_APP, `type:${type}`, LABEL_TO_ANALYZE];
}

// ── Corps de l'Issue (P24) ──────────────────────────────────────────────────

const TYPE_LABELS: Record<TicketType, string> = {
  bug: "Bug",
  evolution: "Évolution",
  feature: "Nouvelle fonctionnalité",
};

const PLATFORM_LABELS: Record<TicketPlatform, string> = { android: "Android", web: "Web" };

export const SCREEN_OTHER = "autre";
export const SCREEN_UNKNOWN = "inconnu";

const SCREEN_SEGMENT = /^(?:[a-z][a-z-]{0,39}|:[A-Za-z][A-Za-z0-9]{0,39})$/;

/**
 * Le modèle de route go_router, `autre` ou `inconnu`, ou `null` s'il n'en a pas la forme.
 * Les règles Firestore font le même contrôle à la création ; le serveur le refait avant
 * publication : un identifiant réel ne part jamais sur le dépôt public.
 */
export function routeTemplateOrNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  if (value === SCREEN_OTHER || value === SCREEN_UNKNOWN || value === "/") return value;
  if (!value.startsWith("/") || value.length > 100) return null;
  return value
    .slice(1)
    .split("/")
    .every((s) => SCREEN_SEGMENT.test(s))
    ? value
    : null;
}

function screenLabel(screen: string): string {
  if (screen === SCREEN_OTHER) return "Autre écran";
  if (screen === SCREEN_UNKNOWN) return "Non précisé";
  return `\`${screen}\``;
}

const APP_VERSION_PATTERN = /^[0-9A-Za-z.+-]{1,40}$/;

function versionLabel(version: unknown): string {
  return typeof version === "string" && APP_VERSION_PATTERN.test(version)
    ? `\`${version}\``
    : "Version inconnue";
}

/** Titre de l'Issue : une ligne, texte nettoyé (P24). */
export function buildIssueTitle(title: string): string {
  return singleLine(publicText(title)).slice(0, 256);
}

export interface IssueBodyInput {
  ticketId: string;
  type: TicketType;
  description: string;
  screen: unknown;
  appVersion: unknown;
  platform: TicketPlatform;
}

/**
 * Phrase fixe de chaque Issue : la capture, quand le membre en joint une, reste dans
 * Cloud Storage et ne se lit que dans Admin › Tickets (ADR-008, T6).
 */
export const ISSUE_SCREENSHOT_NOTE = "Capture éventuelle disponible dans Admin › Tickets.";

/** Ligne qui porte la référence opaque du ticket, cherchée avant une republication. */
export function referenceLine(ticketId: string): string {
  return `**Référence :** \`${ticketId}\``;
}

/**
 * Corps de l'Issue, sur un gabarit fixe : type, écran (modèle de route), version,
 * plateforme, référence opaque, description nettoyée, puis [ISSUE_SCREENSHOT_NOTE] sur
 * chaque Issue, qu'une capture soit jointe ou non (ADR-008, note du 2026-11-14). Jamais le
 * nom, l'e-mail, l'uid, une recette, un prix ni la capture (P24).
 */
export function buildIssueBody(input: IssueBodyInput): string {
  const screen = routeTemplateOrNull(input.screen) ?? SCREEN_UNKNOWN;
  return [
    `**Type :** ${TYPE_LABELS[input.type]}`,
    `**Écran :** ${screenLabel(screen)}`,
    `**Version :** ${versionLabel(input.appVersion)}`,
    `**Plateforme :** ${PLATFORM_LABELS[input.platform]}`,
    referenceLine(input.ticketId),
    "",
    "### Description",
    "",
    publicText(input.description),
    "",
    "---",
    "_Ticket envoyé depuis l'application Kass'Beer._",
    "",
    ISSUE_SCREENSHOT_NOTE,
  ].join("\n");
}

// ── Statut lu sur GitHub ────────────────────────────────────────────────────

export interface IssueView {
  number: number;
  state: "open" | "closed";
  stateReason: string | null;
  labels: string[];
  isPullRequest: boolean;
  updatedAt: string | null;
  comments: number;
}

/**
 * Le statut que dit l'Issue (ADR-006, « Statuts »). Fermée : `statut:clos` → `closed` ;
 * `not_planned` ou `duplicate` → `refused` ; sinon `delivered`. Ouverte :
 * `statut:en-cours` → `in_progress` ; `validé` → `validated` ; `statut:analysé` →
 * `analyzed` (ADR-008) ; sinon `received`. Les étiquettes seules comptent, jamais le
 * texte d'un commentaire (P32).
 */
export function statusFromIssue(
  issue: Pick<IssueView, "state" | "stateReason" | "labels">,
): PublishedStatus {
  if (issue.state === "closed") {
    if (issue.labels.includes(LABEL_CLOSED)) return "closed";
    if (issue.stateReason === "not_planned" || issue.stateReason === "duplicate") return "refused";
    return "delivered";
  }
  if (issue.labels.includes(LABEL_IN_PROGRESS)) return "in_progress";
  if (issue.labels.includes(LABEL_VALIDATED)) return "validated";
  if (issue.labels.includes(LABEL_ANALYZED)) return "analyzed";
  return "received";
}

/**
 * Vrai si l'état d'Issue lu (`issueUpdatedAt`) est antérieur ou égal au retour à « Reçu »
 * écrit par « Répondre » (`answer_reset_at`) : un événement d'étiquette livré en retard ne
 * refait pas avancer le ticket. Sans date de part ou d'autre : `false`. Pure (Kass'Dalle).
 */
export function isStaleIssueSnapshot(
  issueUpdatedAt: string | null | undefined,
  answerResetAtMs: number | null,
): boolean {
  if (answerResetAtMs === null || typeof issueUpdatedAt !== "string") return false;
  const ms = Date.parse(issueUpdatedAt);
  return !Number.isNaN(ms) && ms <= answerResetAtMs;
}

/**
 * Le statut à retenir. Un statut ne recule pas ; une Issue fermée donne son statut de
 * fin ; une Issue rouverte reprend le statut de ses étiquettes.
 */
export function nextStatus(current: PublishedStatus, fromGithub: PublishedStatus): PublishedStatus {
  if (FINAL_STATUSES.includes(fromGithub)) return fromGithub;
  if (FINAL_STATUSES.includes(current)) return fromGithub;
  return OPEN_RANK[fromGithub] > OPEN_RANK[current] ? fromGithub : current;
}

// ── Plafond du jour ─────────────────────────────────────────────────────────

const PARIS_DAY = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Paris",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** Jour calendaire de Paris, `AAAAMMJJ`. */
export function parisDay(at: Date): string {
  const parts = PARIS_DAY.formatToParts(at);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year")}${get("month")}${get("day")}`;
}

/** Compteur d'un membre pour un jour. L'uid ne quitte pas Firestore. */
export function memberQuotaDocId(uid: string, day: string): string {
  return `member_${uid}_${day}`;
}

/** Compteur du groupe pour un jour. */
export function groupQuotaDocId(day: string): string {
  return `group_${day}`;
}

export type QuotaReason = "member" | "group";

/**
 * Ce que décide le plafond, compteurs du jour lus : `null` si la publication passe.
 * L'administrateur n'est jamais refusé, et il ne compte pas (ADR-006, avenant 9).
 */
export function quotaRefusal(args: {
  isAdmin: boolean;
  memberCount: number;
  groupCount: number;
  memberLimit: number;
  groupLimit: number;
}): QuotaReason | null {
  if (args.isAdmin) return null;
  if (args.memberCount >= args.memberLimit) return "member";
  if (args.groupCount >= args.groupLimit) return "group";
  return null;
}

/** Valeur d'un compteur lue dans un document, 0 s'il est absent ou illisible. */
export function readCount(data: Record<string, unknown> | undefined): number {
  const count = data?.count;
  return typeof count === "number" && Number.isInteger(count) && count >= 0 ? count : 0;
}

// ── Réponse de l'administrateur ─────────────────────────────────────────────

export interface CommentView {
  id: number | null;
  authorId: number | null;
  body: string | null;
  createdAt: string | null;
  updatedAt: string | null;
}

const REPLY_PREFIX = /^Réponse\s*:\s*/u;
const DECISION_LINE = /\n?[ \t]*Décision[ \t]+[A-Za-z0-9_-]{1,128}[ \t]*$/u;

/**
 * La réponse d'un commentaire, ou `null`. Seul compte un commentaire du compte
 * `maintainerId` (identifiant numérique) qui commence par « Réponse : » ; le préfixe et
 * la ligne « Décision <id> » sont retirés, le texte est nettoyé et borné (P24).
 */
export function replyFromComment(
  comment: Pick<CommentView, "authorId" | "body">,
  maintainerId: number,
  maxChars: number,
): string | null {
  if (comment.authorId !== maintainerId || typeof comment.body !== "string") return null;
  const body = comment.body.normalize("NFC").replace(/\r\n?/g, "\n").trimStart();
  if (!REPLY_PREFIX.test(body)) return null;
  const text = storedReplyText(
    body.replace(REPLY_PREFIX, "").trimEnd().replace(DECISION_LINE, ""),
    maxChars,
  );
  return text.length > 0 ? text : null;
}

/** La dernière réponse d'une liste de commentaires (du plus ancien au plus récent). */
export function lastReply(
  comments: readonly CommentView[],
  maintainerId: number,
  maxChars: number,
): { text: string; at: string | null } | null {
  for (let i = comments.length - 1; i >= 0; i--) {
    const text = replyFromComment(comments[i], maintainerId, maxChars);
    if (text !== null) return { text, at: comments[i].createdAt };
  }
  return null;
}

// ── Livraison : PR fusionnée et version ─────────────────────────────────────

/**
 * La version `x.y.z` (sans `+N`) de la ligne `version:` d'un `pubspec.yaml`, ou `null`.
 */
export function pubspecVersionName(text: string): string | null {
  const m = /^version:[ \t]*(\d{1,4}\.\d{1,5}\.\d{1,6})(?:\+\d+)?[ \t]*$/m.exec(text);
  return m === null ? null : m[1];
}

const SHA_PATTERN = /^[0-9a-f]{7,64}$/i;

export function isCommitSha(value: unknown): value is string {
  return typeof value === "string" && SHA_PATTERN.test(value);
}

/** Le commit qui a fermé l'Issue (dernier événement `closed` avec `commit_id`), ou `null`. */
export function closingCommitFromEvents(events: readonly unknown[]): string | null {
  let best: { sha: string; ms: number } | null = null;
  for (const raw of events) {
    if (raw === null || typeof raw !== "object") continue;
    const e = raw as Record<string, unknown>;
    if (e.event !== "closed" || !isCommitSha(e.commit_id)) continue;
    const ms = typeof e.created_at === "string" ? Date.parse(e.created_at) : Number.NaN;
    const at = Number.isNaN(ms) ? 0 : ms;
    if (best === null || at >= best.ms) best = { sha: e.commit_id, ms: at };
  }
  return best?.sha ?? null;
}

/** Numéros d'Issue fermés par un texte de PR : `Closes #12`, `fixes ChinaFred/KassBeer#12`. */
export function closingIssueNumbers(body: string | null, repoFullName: string): number[] {
  if (!body) return [];
  const pattern =
    /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+(?:([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+))?#(\d+)\b/gi;
  const numbers = new Set<number>();
  for (const match of body.matchAll(pattern)) {
    const repo = match[1];
    if (repo && repo.toLowerCase() !== repoFullName.toLowerCase()) continue;
    const n = Number(match[2]);
    if (Number.isSafeInteger(n) && n > 0) numbers.add(n);
  }
  return [...numbers].sort((a, b) => a - b);
}

const TRUSTED_ASSOCIATIONS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);

export interface MergedPrCandidate {
  number: number;
  mergedAt: string | null;
  mergeCommitSha: string | null;
  body: string | null;
  baseRepoFullName: string | null;
  authorId: number | null;
  authorAssociation: string | null;
}

/** L'adresse publique d'une PR de ce dépôt, construite depuis son numéro. */
export function pullRequestUrl(repoFullName: string, prNumber: number): string {
  return `https://github.com/${repoFullName}/pull/${prNumber}`;
}

/**
 * La PR de livraison de l'Issue : fusionnée dans ce dépôt, quelle que soit sa branche,
 * d'un auteur qui a un accès au dépôt, dont le texte ferme l'Issue. La dernière
 * fusionnée s'il y en a plusieurs, `null` sinon. L'adresse est reconstruite depuis le
 * numéro : l'application n'ouvre que `https://github.com/ChinaFred/KassBeer/pull/N`.
 */
export function pickDeliveredPr(
  candidates: readonly MergedPrCandidate[],
  issueNumber: number,
  maintainerId: number,
  repoFullName: string,
): { number: number; url: string; mergeCommitSha: string | null } | null {
  let best: { pr: MergedPrCandidate; ms: number } | null = null;
  for (const pr of candidates) {
    if (pr.mergedAt === null) continue;
    if (pr.baseRepoFullName?.toLowerCase() !== repoFullName.toLowerCase()) continue;
    const ms = Date.parse(pr.mergedAt);
    if (Number.isNaN(ms)) continue;
    const trusted =
      pr.authorId === maintainerId ||
      (pr.authorAssociation !== null && TRUSTED_ASSOCIATIONS.has(pr.authorAssociation));
    if (!trusted) continue;
    if (!closingIssueNumbers(pr.body, repoFullName).includes(issueNumber)) continue;
    if (best === null || ms >= best.ms) best = { pr, ms };
  }
  if (best === null) return null;
  return {
    number: best.pr.number,
    url: pullRequestUrl(repoFullName, best.pr.number),
    mergeCommitSha: isCommitSha(best.pr.mergeCommitSha) ? best.pr.mergeCommitSha : null,
  };
}

// ── Jeton ───────────────────────────────────────────────────────────────────

/**
 * La date de l'en-tête `github-authentication-token-expiration`
 * (« 2026-12-31 00:00:00 UTC » ou « … +0100 »), ou `null` si elle est absente ou illisible.
 */
export function parseTokenExpiration(header: string | null): Date | null {
  if (header === null) return null;
  const m = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})\s*(UTC|Z|[+-]\d{2}:?\d{2})?$/.exec(
    header.trim(),
  );
  if (m === null) return null;
  let zone = m[3] ?? "Z";
  if (zone === "UTC") zone = "Z";
  if (/^[+-]\d{4}$/.test(zone)) zone = `${zone.slice(0, 3)}:${zone.slice(3)}`;
  const ms = Date.parse(`${m[1]}T${m[2]}${zone}`);
  return Number.isNaN(ms) ? null : new Date(ms);
}
