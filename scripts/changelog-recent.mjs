#!/usr/bin/env node
// Extrait de documentation/CHANGELOG.md les dernières versions qui portent une
// entrée « fonctionnel », pour l'écran « Nouveautés » de l'application.
//
// Usage, depuis la racine du dépôt :
//   node scripts/changelog-recent.mjs
//
// Écrit app/assets/changelog_recent.json :
//   { "versions": [ { "version": "0.2.1", "date": "2026-11-22",
//                     "summaries": ["…"], "paragraphs": ["…"] } ] }
//
// Une entrée « fonctionnel » commence par une ligne « Résumé : … » de
// SUMMARY_MAX_LENGTH caractères au plus (ticket #114) : le texte qui suit devient
// le résumé de l'entrée, le reste son détail. Obligatoire à partir de la version
// SUMMARY_REQUIRED_FROM ; les entrées antérieures n'en ont pas et ne se
// réécrivent pas.
//
// Le texte est simple : les accents graves et les « ** » du Markdown sont retirés,
// chaque paragraphe devient une chaîne, chaque puce « - » un paragraphe qui commence
// par « • ». Le fichier est régénéré par la CI et par deploy.yml avant chaque build
// web ou APK ; la copie versionnée sert aux builds locaux.
//
// Échoue (code 1) si le CHANGELOG ne donne aucune version « fonctionnel », si
// une entrée « fonctionnel » n'a pas de date au-dessus d'elle, si un résumé est
// vide, dépasse SUMMARY_MAX_LENGTH caractères ou n'ouvre pas l'entrée, ou si une
// entrée d'une version au moins égale à SUMMARY_REQUIRED_FROM n'en a pas.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** Nombre maximal de versions écrites dans l'asset. */
export const COUNT = 6;

/** Longueur maximale d'un résumé, en caractères (points de code). */
export const SUMMARY_MAX_LENGTH = 120;

/** Première version dont chaque entrée « fonctionnel » porte un résumé. */
export const SUMMARY_REQUIRED_FROM = "0.2.1";

const SUMMARY_RE = /^Résumé\s*:\s*(.*)$/;

const DATE_RE = /^## (\d{4}-\d{2}-\d{2})\s*$/;
const ENTRY_RE = /^### v(\d+\.\d+\.\d+) — (fonctionnel|technique)\s*$/;
const BULLET_RE = /^\s*[-*] +(.*)$/;

/** [text] sans accents graves ni « ** », espaces multiples réduits. */
export function cleanInline(text) {
  return text.replaceAll("`", "").replaceAll("**", "").replace(/\s+/g, " ").trim();
}

/**
 * Paragraphes de [text] : un bloc séparé par une ligne vide donne un paragraphe,
 * ses lignes jointes par une espace. Une puce « - » ouvre un paragraphe « • … » ;
 * ses lignes de suite (indentées) s'y ajoutent.
 */
export function toParagraphs(text) {
  const paragraphs = [];
  let current = null;
  const flush = () => {
    if (current === null) return;
    const cleaned = cleanInline(current.join(" "));
    if (cleaned !== "" && cleaned !== "•") paragraphs.push(cleaned);
    current = null;
  };
  for (const line of text.split(/\r?\n/)) {
    if (line.trim() === "") {
      flush();
      continue;
    }
    const bullet = BULLET_RE.exec(line);
    if (bullet) {
      flush();
      current = [`• ${bullet[1]}`];
      continue;
    }
    if (current === null) current = [];
    current.push(line.trim());
  }
  flush();
  return paragraphs;
}

/** Vrai si la version « X.Y.Z » [a] précède [b]. */
export function versionBefore(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] < pb[i];
  }
  return false;
}

/**
 * Sépare le résumé du détail d'une entrée « fonctionnel » de [version] :
 * `{ summary, paragraphs }`, `summary` à `null` sans ligne « Résumé : ».
 * Lève si le résumé est vide, trop long ou placé après le premier paragraphe,
 * ou s'il manque à une version au moins égale à SUMMARY_REQUIRED_FROM.
 */
export function splitSummary(version, paragraphs) {
  const where = `v${version} — fonctionnel`;
  paragraphs.forEach((p, index) => {
    if (index > 0 && SUMMARY_RE.test(p)) {
      throw new Error(`${where} : la ligne « Résumé : » doit ouvrir l'entrée.`);
    }
  });
  const match = paragraphs.length > 0 ? SUMMARY_RE.exec(paragraphs[0]) : null;
  if (match === null) {
    if (!versionBefore(version, SUMMARY_REQUIRED_FROM)) {
      throw new Error(`${where} : la ligne « Résumé : » manque en tête de l'entrée.`);
    }
    return { summary: null, paragraphs };
  }
  const summary = match[1].trim();
  if (summary === "") throw new Error(`${where} : résumé vide.`);
  const length = [...summary].length;
  if (length > SUMMARY_MAX_LENGTH) {
    throw new Error(
      `${where} : résumé de ${length} caractères, ${SUMMARY_MAX_LENGTH} au plus.`,
    );
  }
  return { summary, paragraphs: paragraphs.slice(1) };
}

/**
 * Les [count] dernières versions ayant une entrée « fonctionnel », de la plus
 * récente à la plus ancienne (ordre du fichier). Une version qui n'a qu'une entrée
 * « technique » est ignorée. Deux entrées « fonctionnel » d'une même version
 * mettent leurs résumés et leurs paragraphes bout à bout.
 */
export function extractRecentVersions(markdown, count = COUNT) {
  const versions = [];
  const byVersion = new Map();
  let date = null;
  let current = null;

  const close = () => {
    if (current === null) return;
    const entry = current;
    current = null;
    const text = toParagraphs(entry.lines.join("\n"));
    if (text.length === 0) return;
    const { summary, paragraphs } = splitSummary(entry.version, text);
    const summaries = summary === null ? [] : [summary];
    const known = byVersion.get(entry.version);
    if (known) {
      known.summaries.push(...summaries);
      known.paragraphs.push(...paragraphs);
      return;
    }
    const added = { version: entry.version, date: entry.date, summaries, paragraphs };
    byVersion.set(entry.version, added);
    versions.push(added);
  };

  for (const line of markdown.split(/\r?\n/)) {
    const dateMatch = DATE_RE.exec(line);
    if (dateMatch) {
      close();
      date = dateMatch[1];
      continue;
    }
    const entry = ENTRY_RE.exec(line);
    if (entry) {
      close();
      if (entry[2] === "fonctionnel") {
        if (date === null) {
          throw new Error(`v${entry[1]} — fonctionnel : aucune date « ## AAAA-MM-JJ » au-dessus.`);
        }
        current = { version: entry[1], date, lines: [] };
      }
      continue;
    }
    if (current === null) continue;
    if (line.startsWith("#")) {
      close();
      continue;
    }
    current.lines.push(line);
  }
  close();
  return versions.slice(0, count);
}

function main() {
  const root = join(dirname(fileURLToPath(import.meta.url)), "..");
  const source = join(root, "documentation", "CHANGELOG.md");
  const target = join(root, "app", "assets", "changelog_recent.json");

  let versions;
  try {
    versions = extractRecentVersions(readFileSync(source, "utf8"));
  } catch (error) {
    console.error(`CHANGELOG.md : ${error.message}`);
    process.exit(1);
  }
  if (versions.length === 0) {
    console.error("CHANGELOG.md : aucune version « fonctionnel » trouvée.");
    process.exit(1);
  }
  writeFileSync(target, `${JSON.stringify({ versions }, null, 2)}\n`);
  console.log(`app/assets/changelog_recent.json : ${versions.map((v) => `v${v.version}`).join(", ")}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
