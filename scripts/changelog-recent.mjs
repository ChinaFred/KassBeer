#!/usr/bin/env node
// Extrait de documentation/CHANGELOG.md les dernières versions qui portent une
// entrée « fonctionnel », pour l'écran « Nouveautés » de l'application.
//
// Usage, depuis la racine du dépôt :
//   node scripts/changelog-recent.mjs
//
// Écrit app/assets/changelog_recent.json :
//   { "versions": [ { "version": "0.1.13", "date": "2026-11-10", "paragraphs": ["…"] } ] }
//
// Le texte est simple : les accents graves et les « ** » du Markdown sont retirés,
// chaque paragraphe devient une chaîne, chaque puce « - » un paragraphe qui commence
// par « • ». Le fichier est régénéré par la CI et par deploy.yml avant chaque build
// web ou APK ; la copie versionnée sert aux builds locaux.
//
// Échoue (code 1) si le CHANGELOG ne donne aucune version « fonctionnel », ou si
// une entrée « fonctionnel » n'a pas de date au-dessus d'elle.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** Nombre maximal de versions écrites dans l'asset. */
export const COUNT = 6;

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

/**
 * Les [count] dernières versions ayant une entrée « fonctionnel », de la plus
 * récente à la plus ancienne (ordre du fichier). Une version qui n'a qu'une entrée
 * « technique » est ignorée. Deux entrées « fonctionnel » d'une même version
 * mettent leurs paragraphes bout à bout.
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
    const paragraphs = toParagraphs(entry.lines.join("\n"));
    if (paragraphs.length === 0) return;
    const known = byVersion.get(entry.version);
    if (known) {
      known.paragraphs.push(...paragraphs);
      return;
    }
    const added = { version: entry.version, date: entry.date, paragraphs };
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
