// Formate le fichier qu'un outil d'édition vient d'écrire, selon les règles de
// .claude/formatters.json. Formater à l'écriture évite de découvrir l'écart au
// moment des contrôles.
//
// Hook PostToolUse sur Edit|Write|MultiEdit. En Node pour tourner sous Linux,
// macOS et Windows. Un échec du formateur ne bloque pas l'édition : il est
// écrit sur stderr, et les contrôles de « Commandes utiles » font foi.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);

let filePath;
try {
  const input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  filePath = input?.tool_input?.file_path;
} catch (err) {
  console.error(`format-on-edit : entrée illisible (${err.message})`);
  process.exit(0);
}
if (typeof filePath !== "string" || filePath.length === 0) process.exit(0);

const root = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
const configPath = path.join(root, ".claude", "formatters.json");
if (!existsSync(configPath)) process.exit(0);

let rules;
try {
  rules = JSON.parse(readFileSync(configPath, "utf8")).rules ?? [];
} catch (err) {
  console.error(`format-on-edit : .claude/formatters.json illisible (${err.message})`);
  process.exit(0);
}

const rel = path.relative(root, path.resolve(filePath)).split(path.sep).join("/");
if (path.isAbsolute(rel) || rel === ".." || rel.startsWith("../")) process.exit(0);

const rule = rules.find(
  (r) =>
    rel.startsWith(r.prefix ?? "") &&
    Array.isArray(r.extensions) &&
    r.extensions.some((ext) => rel.endsWith(ext)),
);
if (!rule || typeof rule.command !== "string") process.exit(0);

const cwdRel = (rule.cwd ?? "").replace(/\/$/, "");
const fromCwd = cwdRel && rel.startsWith(`${cwdRel}/`) ? rel.slice(cwdRel.length + 1) : rel;
// La commande passe par un shell (nécessaire sous Windows pour npx.cmd ou
// mvn.cmd). Le chemin n'est accepté que s'il ne contient que des lettres,
// chiffres, espaces et « . _ - / @ + », et le hook le met lui-même entre
// guillemets : ni « ; », ni « & », ni « $ », ni guillemet n'atteint le shell.
if (!/^[\p{L}\p{N} ._\-\/@+]+$/u.test(fromCwd)) {
  console.error(`format-on-edit : chemin ignoré, caractère non admis dans ${rel}`);
  process.exit(0);
}
if (/["']\{file\}|\{file\}["']/.test(rule.command)) {
  console.error("format-on-edit : retirer les guillemets autour de {file} dans .claude/formatters.json");
  process.exit(0);
}
const command = rule.command.replaceAll("{file}", `"${fromCwd}"`);
const result = spawnSync(command, {
  cwd: path.join(root, cwdRel),
  shell: true,
  encoding: "utf8",
});
if (result.error || result.status !== 0) {
  const detail = result.error?.message || result.stderr?.trim() || `code ${result.status}`;
  console.error(`format-on-edit : « ${command} » a échoué sur ${rel} — ${detail}`);
}
