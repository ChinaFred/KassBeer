// Vérifie que Claude Code peut charger chaque agent et chaque skill du dépôt.
//
// Claude Code écarte sans message un agent ou un skill dont l'en-tête YAML est
// invalide. Sur le projet qui a servi de base à agent-starter, deux relecteurs
// ont manqué à toutes les sessions pendant six jours à cause d'un « : » dans
// une description non guillemetée. Ce script rend l'écart visible.
//
//   node scripts/check-agents.mjs          sort en 1 sur une anomalie
//   node scripts/check-agents.mjs --warn   hook de démarrage : avertit, sort en 0
//
// Sans dépendance : l'en-tête est contrôlé par un lecteur du sous-ensemble YAML
// que ce dépôt emploie (une clé par ligne, valeur simple, entre guillemets, ou
// bloc `|` / `>`). Un en-tête plus riche est signalé comme non vérifiable.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Agents qui ne se retirent pas (CLAUDE.md, « Agents »).
export const REQUIRED_AGENTS = ["architecte", "relecteur-regles", "securite"];

/** En-tête YAML d'un fichier Markdown, ou null s'il n'en a pas. */
export function extractFrontmatter(text) {
  const normalized = text.replace(/\r\n/g, "\n");
  const match = /^---\n([\s\S]*?)\n---(\n|$)/.exec(normalized);
  return match ? match[1] : null;
}

function closesQuote(value, quote) {
  if (quote === "'") return /^'(?:[^']|'')*'\s*(#.*)?$/.test(value);
  return /^"(?:[^"\\]|\\.)*"\s*(#.*)?$/.test(value);
}

function unquote(value) {
  const v = value.replace(/\s+#.*$/, "").trim();
  if (v.startsWith('"')) return v.slice(1, v.lastIndexOf('"')).replace(/\\"/g, '"');
  if (v.startsWith("'")) return v.slice(1, v.lastIndexOf("'")).replace(/''/g, "'");
  return v;
}

/**
 * Lit un en-tête YAML plat. Renvoie { data, problems } ; `problems` non vide
 * signifie que Claude Code risque de ne pas charger le fichier.
 */
export function parseFlatYaml(header) {
  const data = {};
  const problems = [];
  const lines = header.split("\n");
  let block = false; // dans un bloc `|` ou `>`
  let current = null;
  lines.forEach((line, index) => {
    const lineNo = index + 2; // ligne 1 = « --- »
    if (line.trim() === "" || /^\s*#/.test(line)) return;
    if (/^\s/.test(line)) {
      if (current === null) {
        problems.push(`ligne ${lineNo} : ligne indentée sans clé`);
      } else if (!block && /:\s/.test(line)) {
        problems.push(`ligne ${lineNo} : « : » dans une valeur sans guillemets`);
      } else if (block) {
        data[current] = `${data[current]}\n${line.trim()}`.trim();
      } else {
        data[current] = `${data[current]} ${line.trim()}`.trim();
      }
      return;
    }
    const match = /^([A-Za-z_][\w-]*):(?:[ \t]+(.*))?$/.exec(line);
    if (!match) {
      problems.push(`ligne ${lineNo} : attendu « clé: valeur »`);
      current = null;
      return;
    }
    const [, key, rawValue = ""] = match;
    if (key in data) problems.push(`ligne ${lineNo} : clé \`${key}\` en double`);
    current = key;
    block = false;
    const value = rawValue.trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      if (!closesQuote(value, value[0])) {
        problems.push(`ligne ${lineNo} : guillemets de \`${key}\` non refermés sur la ligne`);
      }
      data[key] = unquote(value);
    } else if (/^[|>][-+0-9]*$/.test(value)) {
      block = true;
      data[key] = "";
    } else if (/^[[{&*!%@`]/.test(value)) {
      problems.push(`ligne ${lineNo} : valeur de \`${key}\` non vérifiable (syntaxe YAML avancée)`);
      data[key] = value;
    } else {
      if (/:\s/.test(value) || value.endsWith(":")) {
        problems.push(
          `ligne ${lineNo} : « : » dans la valeur de \`${key}\` — la mettre entre guillemets doubles`,
        );
      }
      data[key] = value.replace(/\s+#.*$/, "");
    }
  });
  return { data, problems };
}

/** Anomalies d'un fichier d'agent ou de skill. `expectedName` : nom attendu. */
export function checkDefinition(text, expectedName) {
  const header = extractFrontmatter(text);
  if (header === null) return ["en-tête YAML absent (le fichier doit commencer par ---)"];
  const { data, problems } = parseFlatYaml(header);
  for (const key of ["name", "description"]) {
    if (typeof data[key] !== "string" || data[key].trim() === "") {
      problems.push(`clé \`${key}\` absente ou vide`);
    }
  }
  if (typeof data.name === "string" && data.name && data.name !== expectedName) {
    problems.push(`\`name\` diffère du nom attendu \`${expectedName}\``);
  }
  return problems;
}

/** Noms cités en première colonne du premier tableau qui suit `heading`. */
export function namesInTable(markdown, heading) {
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  const start = lines.findIndex((line) => line.startsWith(heading));
  if (start < 0) return [];
  const names = [];
  let inTable = false;
  for (const line of lines.slice(start + 1)) {
    const cell = /^\| `([^`]+)` \|/.exec(line);
    if (cell) {
      inTable = true;
      names.push(cell[1]);
    } else if (inTable && !line.startsWith("|")) {
      break;
    } else if (line.startsWith("## ")) {
      break;
    }
  }
  return names;
}

function listDefinitions() {
  const agentsDir = join(ROOT, ".claude", "agents");
  const skillsDir = join(ROOT, ".claude", "skills");
  const agents = existsSync(agentsDir)
    ? readdirSync(agentsDir)
        .filter((file) => file.endsWith(".md"))
        .map((file) => ({ kind: "agent", name: basename(file, ".md"), path: join(agentsDir, file) }))
    : [];
  const skills = existsSync(skillsDir)
    ? readdirSync(skillsDir, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => ({
          kind: "skill",
          name: entry.name,
          path: join(skillsDir, entry.name, "SKILL.md"),
        }))
    : [];
  return [...agents, ...skills];
}

function main() {
  const warnOnly = process.argv.includes("--warn");
  const problems = [];

  const definitions = listDefinitions();
  for (const { kind, name, path } of definitions) {
    const relative = path.slice(ROOT.length + 1);
    if (!existsSync(path)) {
      problems.push(`${relative} — ${kind} \`${name}\` : fichier absent`);
      continue;
    }
    for (const problem of checkDefinition(readFileSync(path, "utf8"), name)) {
      problems.push(`${relative} — ${kind} \`${name}\` non chargé : ${problem}`);
    }
  }

  for (const name of REQUIRED_AGENTS) {
    if (!definitions.some((d) => d.kind === "agent" && d.name === name)) {
      problems.push(`.claude/agents/${name}.md — agent obligatoire absent`);
    }
  }

  const claudeMdPath = join(ROOT, "CLAUDE.md");
  if (existsSync(claudeMdPath)) {
    const claudeMd = readFileSync(claudeMdPath, "utf8");
    const present = new Set(definitions.map(({ kind, name }) => `${kind}:${name}`));
    for (const name of namesInTable(claudeMd, "## Agents")) {
      if (!present.has(`agent:${name}`)) {
        problems.push(`CLAUDE.md — agent \`${name}\` cité, aucun fichier .claude/agents/${name}.md`);
      }
    }
    for (const name of namesInTable(claudeMd, "| Skill |")) {
      if (!present.has(`skill:${name}`)) {
        problems.push(`CLAUDE.md — skill \`${name}\` cité, aucun dossier .claude/skills/${name}/`);
      }
    }
  } else {
    problems.push("CLAUDE.md absent à la racine du dépôt");
  }

  if (problems.length === 0) {
    if (!warnOnly) console.log(`check-agents : ${definitions.length} agents et skills chargeables.`);
    return;
  }
  const header = warnOnly
    ? `ATTENTION — ${problems.length} agent(s) ou skill(s) absent(s) de cette session. ` +
      "Le signaler à l'utilisateur avant tout travail qui en a besoin (CLAUDE.md, « Agents ») :"
    : `check-agents : ${problems.length} anomalie(s) :`;
  console.log([header, ...problems.map((problem) => `- ${problem}`)].join("\n"));
  process.exit(warnOnly ? 0 : 1);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
