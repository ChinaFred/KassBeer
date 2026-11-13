/**
 * Règles pures des analyses et de « Répondre » (ADR-008, lot T3), reprises de Kass'Dalle
 * (`functions/src/tickets/rules.ts`). Aucune lecture ni écriture ici : `analyses.ts` et
 * `answer.ts` lisent et écrivent.
 *
 * Relevé (P32) : seuls comptent les commentaires du compte `maintainerId` (identifiant
 * numérique, jamais le login), dont le texte en NFC, espaces de tête retirées, commence par
 * `## Analyse` (`analysis`) ou `## Précisions` (`reply` si l'identifiant figure dans
 * `answer_comment_ids`, écrit par le serveur seul, sinon `unverified_reply`). Dix entrées
 * au plus, les plus récentes, 20 000 caractères chacune, coupées à une ligne vide.
 *
 * « Répondre » (P34) : texte de 5 à 4 000 caractères après nettoyage, publié par
 * `publicText` sous `## Précisions de l'administrateur` (P24).
 */

import type { CommentView, TicketStatus } from "./model";
import { cleanMultiline, publicText } from "./text";

/** Entrées gardées par ticket : les plus récentes. */
export const ANALYSIS_MAX_COUNT = 10;

/** Longueur maximale d'une entrée stockée, en unités UTF-16 (limite de 1 Mo du document). */
export const ANALYSIS_MAX_CHARS = 20_000;

const ANALYSIS_PREFIX = "## Analyse";
const ANSWER_PREFIX = "## Précisions";

/** Titre du commentaire publié par « Répondre ». */
export const ANSWER_TITLE = "## Précisions de l'administrateur";

export type TicketAnalysisKind = "analysis" | "reply" | "unverified_reply";

/** Une entrée de `tickets/{id}/admin/analysis.analyses`, dates en ISO (écrites en `Timestamp`). */
export interface TicketAnalysis {
  comment_id: number | null;
  kind: TicketAnalysisKind;
  body: string;
  created_at: string | null;
  updated_at: string | null;
  truncated: boolean;
}

/** Texte d'un commentaire, NFC, fins de ligne Unix. */
function normalizedBody(body: string): string {
  return body.normalize("NFC").replace(/\r\n?/g, "\n");
}

function startsWithTitle(
  comment: Pick<CommentView, "authorId" | "body">,
  maintainerId: number,
  prefix: string,
): boolean {
  if (comment.authorId !== maintainerId || typeof comment.body !== "string") return false;
  return normalizedBody(comment.body).trimStart().startsWith(prefix);
}

/** Vrai si ce commentaire est une analyse du compte `maintainerId`. Pure. */
export function isAnalysisComment(
  comment: Pick<CommentView, "authorId" | "body">,
  maintainerId: number,
): boolean {
  return startsWithTitle(comment, maintainerId, ANALYSIS_PREFIX);
}

/** Vrai si ce commentaire porte des précisions du compte `maintainerId`. Pure. */
export function isAnswerComment(
  comment: Pick<CommentView, "authorId" | "body">,
  maintainerId: number,
): boolean {
  return startsWithTitle(comment, maintainerId, ANSWER_PREFIX);
}

/**
 * Coupe une entrée trop longue à la dernière ligne vide avant `max` : un paragraphe, un
 * tableau ou un bloc de code n'est pas tranché au milieu. Sans ligne vide avant la limite,
 * coupe à la limite sans séparer une paire de substitution UTF-16. Pure.
 */
export function truncateAnalysis(
  body: string,
  max: number = ANALYSIS_MAX_CHARS,
): { body: string; truncated: boolean } {
  if (body.length <= max) return { body, truncated: false };
  const head = body.slice(0, max);
  let cut = -1;
  for (const match of head.matchAll(/\n[ \t]*\n/g)) {
    if (match.index !== undefined && match.index > 0) cut = match.index;
  }
  if (cut <= 0) {
    cut = max;
    const code = body.charCodeAt(cut - 1);
    if (code >= 0xd800 && code <= 0xdbff) cut -= 1;
  }
  return { body: body.slice(0, cut).trimEnd(), truncated: true };
}

/** Les identifiants de `answer_comment_ids`, lus sans supposer leur forme. Pure. */
export function readAnswerCommentIds(raw: unknown): Set<number> {
  const ids = new Set<number>();
  if (!Array.isArray(raw)) return ids;
  for (const v of raw) if (typeof v === "number" && Number.isSafeInteger(v)) ids.add(v);
  return ids;
}

function isoMillis(iso: string | null): number {
  if (iso === null) return Number.POSITIVE_INFINITY;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? Number.POSITIVE_INFINITY : ms;
}

function commentKind(
  c: CommentView,
  maintainerId: number,
  answerIds: ReadonlySet<number>,
): TicketAnalysisKind | null {
  if (isAnalysisComment(c, maintainerId)) return "analysis";
  if (isAnswerComment(c, maintainerId)) {
    return c.id !== null && answerIds.has(c.id) ? "reply" : "unverified_reply";
  }
  return null;
}

function orderedEntries(
  comments: readonly CommentView[],
  maintainerId: number,
  answerIds: ReadonlySet<number>,
): Array<{ c: CommentView; kind: TicketAnalysisKind }> {
  return comments
    .map((c, index) => ({ c, index, kind: commentKind(c, maintainerId, answerIds) }))
    .filter(
      (e): e is { c: CommentView; index: number; kind: TicketAnalysisKind } => e.kind !== null,
    )
    .sort((a, b) => isoMillis(a.c.createdAt) - isoMillis(b.c.createdAt) || a.index - b.index);
}

/**
 * Les analyses et précisions d'une Issue, dans l'ordre chronologique, les
 * `ANALYSIS_MAX_COUNT` plus récentes, chacune coupée (`truncateAnalysis`). `skipped` compte
 * les entrées reconnues écartées au-delà de dix (ajout de Kass'Beer). Le texte garde sa ligne
 * de titre : le client la retire à l'affichage. Pure.
 */
export function analysesFromComments(
  comments: readonly CommentView[],
  maintainerId: number,
  answerIds: ReadonlySet<number> = new Set(),
): { entries: TicketAnalysis[]; skipped: number } {
  const all = orderedEntries(comments, maintainerId, answerIds);
  const kept = all.slice(-ANALYSIS_MAX_COUNT);
  return {
    skipped: all.length - kept.length,
    entries: kept.map(({ c, kind }) => {
      const { body, truncated } = truncateAnalysis(normalizedBody(c.body ?? "").trim());
      return {
        comment_id: c.id,
        kind,
        body,
        created_at: c.createdAt,
        updated_at: c.updatedAt,
        truncated,
      };
    }),
  };
}

/** Précision du compte `maintainerId` qui porte déjà le texte à publier. */
export interface SameAnswer {
  commentId: number | null;
  /** Identifiant dans `answer_comment_ids` (`reply`) ; sinon `unverified_reply`. */
  verified: boolean;
}

/**
 * Où en est la dernière analyse, lue dans les commentaires :
 * - `hasAnalysis` : au moins une analyse du compte `maintainerId` ;
 * - `same` : une précision du compte `maintainerId` qui suit la dernière analyse (n'importe
 *   où sans analyse) porte déjà `expectedBody`, publiée depuis l'application (`reply`) ou
 *   non enregistrée (`unverified_reply` : la création a réussi, mais GitHub n'a pas répondu
 *   ou l'identifiant n'a pas été écrit). `reply` passe avant `unverified_reply` ;
 * - `samePublished` : `same` existe. Un second appel, ou un nouvel essai après un délai
 *   dépassé, ne publie alors rien (P26). Pure.
 */
export function analysisAnswerState(
  comments: readonly CommentView[],
  maintainerId: number,
  answerIds: ReadonlySet<number>,
  expectedBody: string,
): { hasAnalysis: boolean; samePublished: boolean; same: SameAnswer | null } {
  const ordered = orderedEntries(comments, maintainerId, answerIds);
  let lastAnalysis = -1;
  ordered.forEach((e, i) => {
    if (e.kind === "analysis") lastAnalysis = i;
  });
  const norm = (t: string) => normalizedBody(t).trim();
  const expected = norm(expectedBody);
  const matches = ordered
    .slice(lastAnalysis + 1)
    .filter((e) => e.kind !== "analysis" && norm(e.c.body ?? "") === expected);
  const match = matches.find((e) => e.kind === "reply") ?? matches[0];
  return {
    hasAnalysis: lastAnalysis >= 0,
    samePublished: match !== undefined,
    same: match === undefined ? null : { commentId: match.c.id, verified: match.kind === "reply" },
  };
}

// ── Répondre ────────────────────────────────────────────────────────────────

export const ANSWER_MIN_CHARS = 5;
export const ANSWER_MAX_CHARS = 4000;

/**
 * Taille brute admise avant toute lecture (`requireBoundedText`), en unités UTF-16 : 4 000
 * points de code de 2 unités chacun au plus, plus la place des caractères de contrôle et des
 * espaces que le nettoyage retire. 16 000 unités pèsent 64 ko au plus en UTF-8.
 */
export const ANSWER_RAW_MAX_CHARS = 16_000;

export const ANSWER_TOO_SHORT = "La réponse doit faire au moins 5 caractères.";
export const ANSWER_TOO_LONG = "La réponse ne doit pas dépasser 4 000 caractères.";

/**
 * Le texte publié de la réponse, ou le motif du refus. Caractères de contrôle retirés
 * (retours à la ligne gardés), NFC, espaces de bord retirées, 5 à 4 000 caractères comptés
 * comme l'écran (points de code). Le texte publié passe par `publicText` (P24) : adresses
 * e-mail remplacées, mentions, renvois et balisage neutralisés ; un texte qui ne publie rien
 * de lisible est trop court. Pure.
 */
export function readAnswerText(
  raw: string,
): { ok: true; text: string } | { ok: false; reason: string } {
  const text = cleanMultiline(raw).normalize("NFC").trim();
  const length = Array.from(text).length;
  if (length < ANSWER_MIN_CHARS) return { ok: false, reason: ANSWER_TOO_SHORT };
  if (length > ANSWER_MAX_CHARS) return { ok: false, reason: ANSWER_TOO_LONG };
  const published = publicText(text).trim();
  if (published.length === 0) return { ok: false, reason: ANSWER_TOO_SHORT };
  return { ok: true, text: published };
}

/** Corps du commentaire publié par « Répondre » (gabarit fixe de P24). Pure. */
export function answerCommentBody(publishedText: string): string {
  return `${ANSWER_TITLE}\n\n${publishedText}`;
}

export const ANSWER_NO_ISSUE = "Ce ticket n'a pas encore d'Issue GitHub.";
export const ANSWER_NOT_ALLOWED =
  "Seul un ticket reçu, analysé ou validé peut recevoir une réponse.";

/**
 * Ce que décide « Répondre » avant tout appel à GitHub : `null` si la réponse est permise
 * (ticket `received`, `analyzed` ou `validated`, avec une Issue), sinon le motif du refus.
 * La présence d'une analyse se vérifie ensuite sur les commentaires, sauf pour un ticket
 * `received`. Pure (`answerPrecondition` de Kass'Dalle, sans le type Question ni les
 * lancements, absents de Kass'Beer à T3).
 */
export function answerPrecondition(args: { status: unknown; hasIssue: boolean }): string | null {
  if (!args.hasIssue) return ANSWER_NO_ISSUE;
  const s = args.status as TicketStatus;
  if (s !== "received" && s !== "analyzed" && s !== "validated") return ANSWER_NOT_ALLOWED;
  return null;
}

/**
 * La date de `validated_at` à écrire, ou `null` pour ne rien écrire : elle ne recule
 * jamais. Pure.
 */
export function nextValidatedAt(storedMs: number | null, candidateMs: number): number | null {
  if (!Number.isFinite(candidateMs)) return null;
  return storedMs !== null && candidateMs <= storedMs ? null : candidateMs;
}
