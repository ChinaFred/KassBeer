// node --test scripts/check-version.test.mjs
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  compareVersions,
  extractVersion,
  firstChangelogVersion,
  normalizeRepoPath,
} from "./check-version.mjs";

test("package.json : clé de premier niveau, pas une clé imbriquée", () => {
  const text = '{\n  "config": { "version": "9.9.9" },\n  "version": "0.1.4"\n}';
  assert.equal(extractVersion(text, "package.json"), "0.1.4");
  assert.equal(extractVersion('{"name":"a","version":"1.2.3"}', "package.json"), "1.2.3");
});

test("pubspec.yaml : suffixe de build ignoré, clé indentée ignorée", () => {
  const text = "name: app\nenvironment:\n  version: 9.9.9\nversion: 1.2.3+45\r\n";
  assert.equal(extractVersion(text, "pubspec.yaml"), "1.2.3");
});

test("Cargo.toml : version de [package], pas d'une dépendance", () => {
  const text = '[dependencies.serde]\nversion = "1.0.200"\n\n[package]\nname = "a"\nversion = "0.3.1"\n';
  assert.equal(extractVersion(text, "Cargo.toml"), "0.3.1");
});

test("pyproject.toml : section [project]", () => {
  assert.equal(extractVersion('[project]\nname = "a"\nversion = "2.0.10"\n', "pyproject.toml"), "2.0.10");
});

test("version absente ou illisible", () => {
  assert.equal(extractVersion('{ "name": "a" }', "package.json"), null);
  assert.equal(extractVersion("{ invalide", "package.json"), null);
  assert.equal(extractVersion("version: latest\n", "pubspec.yaml"), null);
});

test("comparaison chiffre par chiffre", () => {
  assert.ok(compareVersions("0.1.12", "0.1.9") > 0);
  assert.ok(compareVersions("0.2.0", "0.1.99") > 0);
  assert.equal(compareVersions("1.0.0", "1.0.0"), 0);
  assert.ok(compareVersions("0.1.4", "0.1.5") < 0);
});

test("première entrée du changelog", () => {
  const md = "# Changelog\n\nTitre `### vX.Y.Z — technique`.\n\n## 2026-10-29\n\n### v0.1.5 — technique\n\n### v0.1.4\n";
  assert.equal(firstChangelogVersion(md), "0.1.5");
  assert.equal(firstChangelogVersion("# Changelog\n\nUne entrée par version.\n"), null);
});

test("chemin normalisé, sortie du dépôt refusée", () => {
  assert.equal(normalizeRepoPath("app/../package.json"), "package.json");
  assert.equal(normalizeRepoPath("app\\pubspec.yaml"), "app/pubspec.yaml");
  assert.equal(normalizeRepoPath("../package.json"), null);
  assert.equal(normalizeRepoPath("/etc/package.json"), null);
});

// Scénarios complets dans un dépôt Git temporaire.
const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "check-version.mjs");
const repos = [];
after(() => repos.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

function repo(config, mainVersion) {
  const dir = mkdtempSync(join(tmpdir(), "check-version-"));
  repos.push(dir);
  const run = (...args) => execFileSync("git", args, { cwd: dir, stdio: "ignore" });
  mkdirSync(join(dir, "scripts"));
  mkdirSync(join(dir, ".claude"));
  mkdirSync(join(dir, "documentation"));
  copyFileSync(SCRIPT, join(dir, "scripts", "check-version.mjs"));
  writeFileSync(join(dir, ".claude", "version.json"), config);
  run("init", "-q", "-b", "main");
  run("config", "user.email", "test@example.com");
  run("config", "user.name", "test");
  const commit = (version, message) => {
    writeFileSync(join(dir, "package.json"), `{\n  "version": "${version}"\n}\n`);
    writeFileSync(join(dir, "documentation", "CHANGELOG.md"), `# Changelog\n\n### v${version} — technique\n`);
    run("add", "-A");
    run("commit", "-q", "-m", message);
  };
  commit(mainVersion, "main");
  run("checkout", "-q", "-b", "branche");
  return {
    dir,
    commit,
    write: (version) => writeFileSync(join(dir, "package.json"), `{ "version": "${version}" }`),
    check: (...args) => spawnSync("node", ["scripts/check-version.mjs", ...args], { cwd: dir, encoding: "utf8" }),
  };
}

test("même version que main : échec", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  const result = r.check();
  assert.equal(result.status, 1);
  assert.match(result.stdout, /branche 0\.1\.9, main 0\.1\.9/);
});

test("version supérieure commitée : succès", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  r.commit("0.1.10", "v0.1.10");
  const result = r.check();
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /HEAD 0\.1\.10, main 0\.1\.9/);
});

test("version supérieure non commitée : échec", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  r.write("0.1.10");
  assert.equal(r.check().status, 1);
});

test("chemin non normalisé : même résultat que le chemin propre", () => {
  const r = repo('{ "fichier": "app/../package.json" }', "0.1.9");
  assert.equal(r.check().status, 1);
});

test("configuration vide : sortie 0 ; clé absente ou mal typée : échec", () => {
  assert.equal(repo('{ "fichier": "" }', "0.1.9").check().status, 0);
  assert.equal(repo('{ "file": "package.json" }', "0.1.9").check().status, 1);
  assert.equal(repo('{ "fichier": ["package.json"] }', "0.1.9").check().status, 1);
  assert.equal(repo("{ invalide", "0.1.9").check().status, 1);
});

test("argument inconnu ou base introuvable : échec", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  r.commit("0.1.10", "v0.1.10");
  assert.equal(r.check("--base=main").status, 1);
  assert.equal(r.check("--base", "inconnue").status, 1);
  assert.equal(r.check("--base", "main").status, 0);
});

test("CHANGELOG.md sans l'entrée de la version : échec", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  r.write("0.1.10");
  execFileSync("git", ["commit", "-q", "-am", "version seule"], { cwd: r.dir });
  const result = r.check();
  assert.equal(result.status, 1);
  assert.match(result.stdout, /Ajouter `### v0\.1\.10`/);
});

test("main local en avance sur origin/main : comparaison à main", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.5");
  execFileSync("git", ["update-ref", "refs/remotes/origin/main", "main"], { cwd: r.dir });
  r.commit("0.1.6", "v0.1.6");
  execFileSync("git", ["branch", "-f", "main", "HEAD"], { cwd: r.dir });
  const result = r.check();
  assert.equal(result.status, 1);
  assert.match(result.stdout, /branche 0\.1\.6, main 0\.1\.6/);
});

test("projet dans un sous-dossier du dépôt Git : fichiers du sous-dossier", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  r.commit("0.1.10", "v0.1.10");
  const outer = mkdtempSync(join(tmpdir(), "check-version-outer-"));
  repos.push(outer);
  const run = (...args) => execFileSync("git", args, { cwd: outer, stdio: "ignore" });
  run("init", "-q", "-b", "main");
  run("config", "user.email", "test@example.com");
  run("config", "user.name", "test");
  writeFileSync(join(outer, "package.json"), '{ "version": "9.0.0" }');
  mkdirSync(join(outer, "sub"));
  for (const path of ["scripts/check-version.mjs", ".claude/version.json", "package.json", "documentation/CHANGELOG.md"]) {
    mkdirSync(dirname(join(outer, "sub", path)), { recursive: true });
    copyFileSync(join(r.dir, path), join(outer, "sub", path));
  }
  run("add", "-A");
  run("commit", "-q", "-m", "base");
  const result = spawnSync("node", ["scripts/check-version.mjs"], { cwd: join(outer, "sub"), encoding: "utf8" });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /branche 0\.1\.10, main 0\.1\.10/);
});

test("--base sans référence : message dédié", () => {
  const result = repo('{ "fichier": "package.json" }', "0.1.9").check("--base");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /--base attend une référence/);
});

test("tag du numéro déjà posé : échec", () => {
  const r = repo('{ "fichier": "package.json" }', "0.1.9");
  r.commit("0.1.10", "v0.1.10");
  execFileSync("git", ["tag", "-a", "v0.1.10", "-m", "v0.1.10"], { cwd: r.dir });
  const result = r.check();
  assert.equal(result.status, 1);
  assert.match(result.stdout, /tag v0\.1\.10 existe déjà/);
});
