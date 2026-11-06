// Vérifie, avant une fusion, que la branche porte une version supérieure à celle
// de la branche principale, qu'aucun tag `vX.Y.Z` ne porte déjà ce numéro, et que
// CHANGELOG.md commence par l'entrée de cette version.
//
// Deux sessions parallèles partent du même numéro et l'incrémentent chacune
// (CLAUDE.md, « Version »). Sans CI, rien d'autre ne compare les deux branches.
//
//   node scripts/check-version.mjs                 compare HEAD à main et origin/main
//   node scripts/check-version.mjs --base <ref>    compare HEAD à une autre référence
//
// Les deux côtés sont lus dans Git (HEAD et la référence), pas dans le dossier
// de travail : on compare ce qui sera fusionné. Sans --base, la référence est la
// plus haute version entre `main` et `origin/main` : une fusion locale non
// poussée compte. Les tags sont ceux du dépôt local : `git fetch --tags` avant.
// Le fichier qui porte la version est déclaré dans .claude/version.json (rempli
// au démarrage du projet). Tant que `fichier` est vide, le script le dit et sort
// en 0.
//
// Sans dépendance. Lecture de la version :
//   .json         clé `version` de premier niveau (package.json…)
//   .toml         `version` de la section [package], [project] ou [tool.poetry]
//   autre (YAML)  ligne `version:` sans indentation (pubspec.yaml…)
// Un suffixe de build (`1.2.3+45`) est ignoré.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG_PATH = join(ROOT, ".claude", "version.json");
const CHANGELOG = "documentation/CHANGELOG.md";
const SEMVER = /^(\d+\.\d+\.\d+)(?:[-+].*)?$/;
const TOML_SECTIONS = ["package", "project", "tool.poetry"];

function semver(value) {
  const match = typeof value === "string" ? SEMVER.exec(value.trim()) : null;
  return match ? match[1] : null;
}

/** Version X.Y.Z lue dans le contenu de `file`, ou null. */
export function extractVersion(text, file) {
  const normalized = text.replace(/\r\n/g, "\n");
  if (file.endsWith(".json")) {
    let data;
    try {
      data = JSON.parse(normalized);
    } catch (error) {
      console.log(`check-version : ${file} n'est pas un JSON valide (${error.message}).`);
      return null;
    }
    return data && typeof data === "object" ? semver(data.version) : null;
  }
  if (file.endsWith(".toml")) {
    let section = "";
    for (const line of normalized.split("\n")) {
      const header = /^\s*\[([^\]]+)\]\s*(#.*)?$/.exec(line);
      if (header) {
        section = header[1].trim();
        continue;
      }
      const entry = /^version\s*=\s*["']([^"']+)["']/.exec(line);
      if (entry && TOML_SECTIONS.includes(section)) return semver(entry[1]);
    }
    return null;
  }
  const entry = /^version\s*:\s*["']?([^"'\s#]+)/m.exec(normalized);
  return entry ? semver(entry[1]) : null;
}

/** Négatif si a < b, 0 si égales, positif si a > b. Compare chiffre par chiffre. */
export function compareVersions(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i += 1) {
    if (pa[i] !== pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

/** Version de la première entrée `### vX.Y.Z` du changelog, ou null. */
export function firstChangelogVersion(markdown) {
  const match = /^### v(\d+\.\d+\.\d+)/m.exec(markdown);
  return match ? match[1] : null;
}

/** Chemin relatif à la racine, au format Git, ou null s'il sort du dépôt. */
export function normalizeRepoPath(file) {
  const path = posix.normalize(file.trim().replace(/\\/g, "/"));
  if (path === "." || path === ".." || path.startsWith("../") || posix.isAbsolute(path)) {
    return null;
  }
  return path;
}

function fail(message) {
  console.log(`check-version : ${message}`);
  process.exit(1);
}

function git(args) {
  const result = spawnSync("git", args, { cwd: ROOT, encoding: "utf8" });
  if (result.error) fail(`git introuvable (${result.error.message}).`);
  return result;
}

/** Contenu de `path` dans `ref`, ou null si le fichier n'y existe pas. */
// `./` résout le chemin depuis ROOT, même si ROOT est un sous-dossier du dépôt Git.
function readAt(ref, path) {
  const spec = `${ref}:./${path}`;
  if (git(["cat-file", "-e", spec]).status !== 0) return null;
  const result = git(["show", spec]);
  if (result.status !== 0) fail(`git show ${spec} a échoué : ${result.stderr.trim()}`);
  return result.stdout;
}

function refExists(ref) {
  return git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]).status === 0;
}

function parseArgs(argv) {
  let base = null;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--base") {
      if (!argv[i + 1] || argv[i + 1].startsWith("--")) fail("--base attend une référence Git.");
      base = argv[i + 1];
      i += 1;
    } else {
      fail(`argument non reconnu : \`${argv[i]}\`. Usage : check-version.mjs [--base <ref>]`);
    }
  }
  return base;
}

function readConfig() {
  if (!existsSync(CONFIG_PATH)) fail(".claude/version.json absent.");
  let config;
  try {
    config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
  } catch (error) {
    fail(`.claude/version.json n'est pas un JSON valide (${error.message}).`);
  }
  if (!config || typeof config.fichier !== "string") {
    fail(".claude/version.json : clé `fichier` absente ou qui n'est pas une chaîne.");
  }
  return config.fichier;
}

function main() {
  const requestedBase = parseArgs(process.argv.slice(2));
  const declared = readConfig();
  if (declared.trim() === "") {
    console.log(
      "check-version : aucun fichier de version déclaré dans .claude/version.json " +
        "(projet non démarré). Rien à comparer.",
    );
    return;
  }
  const file = normalizeRepoPath(declared);
  if (file === null) fail(`.claude/version.json : \`${declared}\` sort du dépôt.`);

  if (git(["rev-parse", "--git-dir"]).status !== 0) fail(`${ROOT} n'est pas un dépôt Git.`);
  if (!refExists("HEAD")) fail("aucun commit sur la branche en cours.");

  const bases = requestedBase === null ? ["main", "origin/main"].filter(refExists) : [requestedBase];
  if (requestedBase !== null && !refExists(requestedBase)) {
    fail(`branche principale \`${requestedBase}\` introuvable.`);
  }
  if (bases.length === 0) fail("ni `main` ni `origin/main` n'existent. Préciser --base <ref>.");

  const branchText = readAt("HEAD", file);
  if (branchText === null) fail(`${file} absent du dernier commit de la branche.`);
  const branchVersion = extractVersion(branchText, file);
  if (branchVersion === null) fail(`aucune version X.Y.Z lisible dans ${file} (HEAD).`);

  // Plus haute version parmi les références principales.
  let base = bases[0];
  let baseVersion = null;
  for (const ref of bases) {
    const text = readAt(ref, file);
    if (text === null) {
      console.log(`check-version : ${file} absent de \`${ref}\`.`);
      continue;
    }
    const version = extractVersion(text, file);
    if (version === null) fail(`aucune version X.Y.Z lisible dans ${file} sur \`${ref}\`.`);
    if (baseVersion === null || compareVersions(version, baseVersion) > 0) {
      base = ref;
      baseVersion = version;
    }
  }
  if (baseVersion !== null && compareVersions(branchVersion, baseVersion) <= 0) {
    fail(
      `branche ${branchVersion}, ${base} ${baseVersion} : ` +
        "incrémenter la version au-dessus de celle de la branche principale avant de fusionner.",
    );
  }

  if (refExists(`refs/tags/v${branchVersion}`)) {
    fail(`le tag v${branchVersion} existe déjà : ce numéro est pris. Incrémenter la version.`);
  }

  const changelog = readAt("HEAD", CHANGELOG);
  if (changelog === null) fail(`${CHANGELOG} absent du dernier commit de la branche.`);
  const changelogVersion = firstChangelogVersion(changelog);
  if (changelogVersion !== branchVersion) {
    fail(
      `version ${branchVersion}, première entrée de ${CHANGELOG} : ` +
        `${changelogVersion ? `v${changelogVersion}` : "aucune"}. ` +
        `Ajouter \`### v${branchVersion}\` en tête.`,
    );
  }

  const dirty = git(["status", "--porcelain", "--", file, CHANGELOG]).stdout.trim();
  if (dirty !== "") {
    console.log(`check-version : modifications non commitées, non comparées :\n${dirty}`);
  }
  console.log(
    `check-version : HEAD ${branchVersion}, ` +
      `${baseVersion === null ? "première version" : `${base} ${baseVersion}`}, ${CHANGELOG} à jour.`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
