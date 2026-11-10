/**
 * Nettoyage de tout texte publié sur le dépôt public (P24, ADR-002), repris de Kass'Dalle
 * (`functions/src/tickets/rules.ts`) avec une différence : une adresse e-mail est
 * remplacée par « [adresse retirée] » au lieu de faire refuser le ticket (ADR-006,
 * question 2). Toutes les fonctions sont pures et testées.
 *
 * Ordre de `publicText` :
 *  1. commentaires HTML retirés : invisibles sur GitHub, ils restent transmis par l'API,
 *     et `jean<!-- x -->@exemple.fr` cacherait une adresse ;
 *  2. caractères invisibles retirés, puis forme NFKC : `jean＠exemple．fr` devient une
 *     adresse reconnue ; les commentaires sont retirés une seconde fois, car NFKC change
 *     `＜!--` en `<!--` ;
 *  3. adresses e-mail remplacées ;
 *  4. balisage neutralisé (HTML brut, images, pièces jointes intégrées, définitions de
 *     référence) ;
 *  5. mentions `@nom` et renvois `#N` neutralisés.
 */

/** Espace sans chasse : coupe `@nom` ou `#12` sans changer ce qu'on lit. */
const ZWSP = String.fromCharCode(0x200b);

export const EMAIL_REPLACEMENT = "[adresse retirée]";

/** Espaces sans chasse, joints, marque d'ordre des octets, trait d'union conditionnel. */
const INVISIBLE_CHARS = /[\u00AD\u200B-\u200D\u2060\uFEFF]/g;

const EMAIL_PATTERN =
  /[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}/g;

const HTML_COMMENT = /<!--[\s\S]*?-->/g;

/**
 * Pièces jointes que GitHub intègre quand leur adresse est seule sur une ligne
 * (`user-attachments`, anciens hébergements d'images).
 */
const EMBEDDED_ASSET_URL =
  /(https?:)\/\/(?=(?:github\.com\/user-attachments\/|github\.com\/[^/\s]+\/[^/\s]+\/assets\/|(?:private-)?user-images\.githubusercontent\.com\/))/gi;

/** Espaces, retours à la ligne et tabulations ramenés à une espace. */
export function singleLine(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

/**
 * Caractères de contrôle retirés, sauf retour à la ligne et tabulation ; fins de ligne
 * Windows ramenées à `\n`.
 */
export function cleanMultiline(value: string): string {
  const unixLines = value.replace(/\r\n?/g, "\n");
  let out = "";
  for (const char of unixLines) {
    const code = char.charCodeAt(0);
    const isControl = code < 0x20 || code === 0x7f;
    if (!isControl || char === "\n" || char === "\t") out += char;
  }
  return out;
}

function removeHtmlComments(text: string): string {
  return text.replace(HTML_COMMENT, "").replace(/<!--/g, "");
}

/** Le texte sans caractères invisibles, en forme NFKC. */
export function normalizeForPublication(text: string): string {
  return removeHtmlComments(
    removeHtmlComments(text).replace(INVISIBLE_CHARS, "").normalize("NFKC"),
  );
}

/** Chaque adresse e-mail remplacée par « [adresse retirée] ». À appliquer après NFKC. */
export function replaceEmailAddresses(text: string): string {
  return text.replace(EMAIL_PATTERN, EMAIL_REPLACEMENT);
}

/**
 * HTML brut, images Markdown, pièces jointes intégrées et définitions de référence
 * (`[x]: …`, `[//]: # (caché)`, notes `[^1]: …`) rendus en texte visible qui ne charge rien.
 */
export function neutralizeMarkup(text: string): string {
  return removeHtmlComments(text)
    .replace(/</g, `<${ZWSP}`)
    .replace(/!\[/g, `!${ZWSP}[`)
    .replace(/\]:/g, `]${ZWSP}:`)
    .replace(EMBEDDED_ASSET_URL, `$1//${ZWSP}`);
}

/** Mentions `@nom` et `@org/équipe` : GitHub ne notifie personne. */
export function neutralizeMentions(text: string): string {
  return text.replace(/@(?=[A-Za-z0-9-])/g, `@${ZWSP}`);
}

/** Adresse d'une Issue ou d'une PR GitHub, avec ou sans schéma. */
const GITHUB_ITEM_URL =
  /(?:(https?:)\/\/)?((?:www\.)?github)(\.com\/[^\s/]+\/[^\s/]+\/(?:issues|pull)\/\d)/gi;

/**
 * Renvois `#12`, `owner/repo#12`, `GH-12` et adresses `github.com/<x>/<y>/issues/N` ou
 * `/pull/N` : aucun lien, aucun « mentioned this » ailleurs. Une espace sans chasse coupe
 * `#` du chiffre, `GH` du tiret, le schéma de l'hôte et l'hôte de `.com`.
 */
export function neutralizeIssueReferences(text: string): string {
  return text
    .replace(
      GITHUB_ITEM_URL,
      (_m, scheme: string | undefined, host: string, rest: string) =>
        `${scheme ? `${scheme}//${ZWSP}` : ""}${host}${ZWSP}${rest}`,
    )
    .replace(/\b(GH)-(?=\d)/gi, `$1${ZWSP}-`)
    .replace(/#(?=\d)/g, `#${ZWSP}`);
}

/** Texte publié sur le dépôt public (titre, description, et en T2 motif et commentaire). */
export function publicText(text: string): string {
  const normalized = normalizeForPublication(cleanMultiline(text));
  return neutralizeIssueReferences(
    neutralizeMentions(neutralizeMarkup(replaceEmailAddresses(normalized))),
  );
}

/**
 * Texte lu sur GitHub et montré au membre (réponse de l'administrateur) : contrôles
 * retirés, adresses e-mail remplacées, longueur bornée. Il n'est pas republié : le
 * balisage n'est pas touché, l'application l'affiche en texte simple.
 */
export function storedReplyText(text: string, maxChars: number): string {
  const cleaned = replaceEmailAddresses(normalizeForPublication(cleanMultiline(text))).trim();
  const chars = Array.from(cleaned);
  if (chars.length <= maxChars) return cleaned;
  return `${chars
    .slice(0, maxChars - 1)
    .join("")
    .trimEnd()}…`;
}
