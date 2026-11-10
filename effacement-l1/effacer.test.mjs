// Tests de effacer.mjs contre l'émulateur Firestore seulement (projet demo-kassbeer).
// Lancement, depuis rules-tests/ :
//   npx firebase --config ../firebase.json emulators:exec --only firestore \
//     --project demo-kassbeer "node --test ../effacement-l1/effacer.test.mjs"

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import {
  dossierSauvegarde,
  effacer,
  rapport,
  Refus,
  verifierLancement,
} from "./effacer.mjs";

const PROJET = "demo-kassbeer";
const HOTE = process.env.FIRESTORE_EMULATOR_HOST;
const SCRIPT = fileURLToPath(new URL("./effacer.mjs", import.meta.url));
const RACINE = resolve(fileURLToPath(new URL("../", import.meta.url)));

// Garde : jamais sans émulateur, jamais un autre projet que demo-.
if (!HOTE || !PROJET.startsWith("demo-")) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST absent : ces tests ne tournent que contre l'émulateur.",
  );
}

const db = getFirestore(
  initializeApp({ projectId: PROJET }, "tests-effacement"),
);
const at = (iso) => Timestamp.fromDate(new Date(iso));

async function vider() {
  const reponse = await fetch(
    `http://${HOTE}/emulator/v1/projects/${PROJET}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  assert.ok(reponse.ok, `vidage de l'émulateur : ${reponse.status}`);
}

async function semer({ statut = "fermenting" } = {}) {
  const docs = {
    "recipes/plate": {
      owner_uid: "brewer-a",
      name: "Ancienne",
      batch_volume_l: 20,
    },
    "recipes/beerjson": {
      format_version: 1,
      owner_uid: "brewer-a",
      recipe: { name: "Nouvelle", ingredients: {} },
      created_at: at("2026-11-02T08:00:00Z"),
    },
    "brews/b1": {
      owner_uid: "brewer-a",
      name: "Blonde #1",
      status: statut,
      brewed_at: at("2026-11-03T09:00:00Z"),
    },
    "brews/b1/events/e1": {
      owner_uid: "brewer-a",
      kind: "step_started",
      step_key: "k",
    },
    "brews/b1/events/e2": {
      owner_uid: "brewer-a",
      kind: "measurement",
      value: 66,
    },
    "brews/b1/events/e3": { owner_uid: "brewer-a", kind: "note", note: "ok" },
    "brews/b2": {
      owner_uid: "brewer-b",
      name: "Stout",
      status: "planned",
      planned_for: at("2026-11-22T08:00:00Z"),
    },
    "equipment/e1": { owner_uid: "brewer-a", name: "Cuve", kind: "all_in_one" },
    "members/brewer.a@example.com": {
      email: "brewer.a@example.com",
      role: "brewer",
    },
    "members/admin@example.com": { email: "admin@example.com", role: "admin" },
    // users/brewer-a n'existe pas : seules ses sous-collections sont comptées.
    "users/brewer-a/prices/malt-pils": { name: "Pils", price_eur: 52 },
    // Coût figé de b1 par son propriétaire : effacé avec le brassin, jamais copié.
    "users/brewer-a/brew_costs/b1": { brew_id: "b1", total_eur: 31.4 },
    // Ni le coût d'un brassin déjà supprimé, ni celui d'un autre compte : intacts.
    "users/brewer-a/brew_costs/ancien": { brew_id: "ancien", total_eur: 12 },
    "users/brewer-b/brew_costs/b1": { brew_id: "b1", total_eur: 5 },
    "error_reports/r1": {
      uid: "brewer-a",
      feature: "recipes.read",
      error: "x",
    },
  };
  for (const [chemin, data] of Object.entries(docs))
    await db.doc(chemin).set(data);
}

/// Lance effacer.mjs ; [reponse] est écrite sur l'entrée standard. [env] complète ou
/// retire (undefined) des variables d'environnement.
function lancer(args, reponse = "", env = {}) {
  return new Promise((ok) => {
    const variables = {
      ...process.env,
      FIRESTORE_EMULATOR_HOST: HOTE,
      // Pas de recherche du serveur de métadonnées de Google Cloud : émulateur seul.
      METADATA_SERVER_DETECTION: "none",
      ...env,
    };
    delete variables.GOOGLE_APPLICATION_CREDENTIALS;
    if (env.GOOGLE_APPLICATION_CREDENTIALS) {
      variables.GOOGLE_APPLICATION_CREDENTIALS =
        env.GOOGLE_APPLICATION_CREDENTIALS;
    }
    for (const [cle, valeur] of Object.entries(env))
      if (valeur === undefined) delete variables[cle];
    const enfant = spawn(process.execPath, [SCRIPT, ...args], {
      env: variables,
    });
    let sortie = "";
    let erreurs = "";
    enfant.stdout.on("data", (d) => (sortie += d));
    enfant.stderr.on("data", (d) => (erreurs += d));
    enfant.on("close", (code) => ok({ code, sortie, erreurs }));
    enfant.stdin.end(reponse);
  });
}

async function nombre(chemin) {
  return (await db.collection(chemin).count().get()).data().count;
}

describe("effacer.mjs contre l'émulateur", () => {
  let dossier;
  before(() => {
    dossier = mkdtempSync(join(tmpdir(), "kassbeer-effacement-"));
  });
  after(() => rmSync(dossier, { recursive: true, force: true }));
  beforeEach(async () => {
    await vider();
    rmSync(dossier, { recursive: true, force: true });
  });

  it("rapport : nombres et brassins, rien d'écrit", async () => {
    await semer();
    const { code, sortie } = await lancer(["rapport", "--projet", PROJET]);
    assert.equal(code, 0);
    assert.match(sortie, /Cible : émulateur/);
    assert.match(sortie, /Recettes : 2/);
    assert.match(
      sortie,
      /b1 · fermenting · brewed_at 2026-11-03T09:00:00.000Z · 3 événement\(s\) · coût figé/,
    );
    assert.match(
      sortie,
      /b2 · planned · planned_for 2026-11-22T08:00:00.000Z · 0 événement\(s\) · sans coût figé/,
    );
    assert.match(sortie, /Coûts figés : 1/);
    assert.match(sortie, /Événements orphelins \(brassin absent\) : 0/);
    assert.equal(await nombre("recipes"), 2);
    assert.equal(await nombre("brews"), 2);
  });

  it("brassin en cours : refusé, rien d'effacé ni copié", async () => {
    await semer({ statut: "brewing" });
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", dossier],
      `${PROJET}\n`,
    );
    assert.equal(r.code, 2, r.erreurs);
    assert.match(r.erreurs, /Brassin en cours \(b1\)/);
    assert.equal(await nombre("recipes"), 2);
    assert.equal(await nombre("brews/b1/events"), 3);
    assert.equal(await nombre("users/brewer-a/brew_costs"), 2);
    assert.throws(() => readdirSync(dossier));
  });

  it("nom du projet différent : refusé, rien d'effacé, copie faite", async () => {
    await semer();
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", dossier],
      "kassbeer\n",
    );
    assert.equal(r.code, 3, r.erreurs);
    assert.equal(await nombre("recipes"), 2);
    assert.equal(await nombre("brews"), 2);
    assert.equal(readdirSync(dossier).length, 1);
  });

  it("effacement : recipes/, brews/ et events/ vidés, le reste intact", async () => {
    await semer();
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", dossier],
      `${PROJET}\n`,
    );
    assert.equal(r.code, 0, r.erreurs);
    assert.match(
      r.sortie,
      /Effacés : 2 recette\(s\), 2 brassin\(s\), 3 événement\(s\), 1 coût\(s\) figé\(s\)\./,
    );
    assert.match(
      r.sortie,
      /users \(hors coûts figés effacés\) : 3 avant, 3 après\./,
    );
    assert.equal(await nombre("recipes"), 0);
    assert.equal(await nombre("brews"), 0);
    assert.equal(
      (await db.collectionGroup("events").count().get()).data().count,
      0,
    );
    assert.equal(await nombre("equipment"), 1);
    assert.equal(await nombre("members"), 2);
    assert.equal(await nombre("error_reports"), 1);
    assert.equal(await nombre("users/brewer-a/prices"), 1);
    assert.equal(
      (await db.doc("users/brewer-a/brew_costs/b1").get()).exists,
      false,
    );
    assert.equal(
      (await db.doc("users/brewer-a/brew_costs/ancien").get()).exists,
      true,
    );
    assert.equal(
      (await db.doc("users/brewer-b/brew_costs/b1").get()).exists,
      true,
    );
    const [fichier] = readdirSync(dossier);
    const texte = readFileSync(join(dossier, fichier), "utf8");
    const copie = JSON.parse(texte);
    assert.equal(copie.projet, PROJET);
    // Aucun coût figé copié (décision du 2026-11-10) : aucun document sous users/.
    assert.deepEqual(Object.keys(copie.documents).sort(), [
      "brews/b1",
      "brews/b1/events/e1",
      "brews/b1/events/e2",
      "brews/b1/events/e3",
      "brews/b2",
      "recipes/beerjson",
      "recipes/plate",
    ]);
    assert.ok(
      Object.keys(copie.documents).every(
        (chemin) => !chemin.startsWith("users/"),
      ),
    );
    assert.doesNotMatch(texte, /total_eur|price_eur/);
    assert.match(r.sortie, /Copie : 7 documents/);
    assert.deepEqual(copie.documents["brews/b1"].brewed_at, {
      __timestamp__: "2026-11-03T09:00:00.000Z",
    });
  });

  it("projet demo- sans émulateur : refusé avant toute connexion", async () => {
    const enfant = await new Promise((ok) => {
      const env = { ...process.env };
      delete env.FIRESTORE_EMULATOR_HOST;
      const p = spawn(
        process.execPath,
        [SCRIPT, "rapport", "--projet", PROJET],
        { env },
      );
      let erreurs = "";
      p.stderr.on("data", (d) => (erreurs += d));
      p.on("close", (code) => ok({ code, erreurs }));
    });
    assert.equal(enfant.code, 1);
    assert.match(enfant.erreurs, /sans FIRESTORE_EMULATOR_HOST : refusé/);
  });

  it("autre projet sans émulateur : refusé avant toute connexion", async () => {
    const r = await lancer(["effacer", "--projet", "autre"], "autre\n", {
      FIRESTORE_EMULATOR_HOST: undefined,
    });
    assert.equal(r.code, 1);
    assert.match(r.erreurs, /Projet autre refusé/);
    assert.doesNotMatch(r.sortie, /Cible/);
  });

  it("autre projet avec l'émulateur : refusé", async () => {
    await semer();
    const r = await lancer(
      ["effacer", "--projet", "autre", "--sauvegarde", dossier],
      "autre\n",
    );
    assert.equal(r.code, 1);
    assert.match(r.erreurs, /Projet autre refusé/);
    assert.equal(await nombre("recipes"), 2);
  });

  it("GOOGLE_APPLICATION_CREDENTIALS posé : refusé", async () => {
    await semer();
    const r = await lancer(["rapport", "--projet", PROJET], "", {
      GOOGLE_APPLICATION_CREDENTIALS: join(dossier, "cle.json"),
    });
    assert.equal(r.code, 1);
    assert.match(r.erreurs, /GOOGLE_APPLICATION_CREDENTIALS posé : refusé/);
    assert.doesNotMatch(r.sortie, /Cible/);
  });

  it("production : effacement refusé sans terminal, permis dans un terminal", () => {
    // verifierLancement ne se connecte à rien : aucun appel vers le projet kassbeer.
    const args = { commande: "effacer", projet: "kassbeer" };
    assert.throws(
      () => verifierLancement(args, {}, false),
      (e) => e instanceof Refus && e.code === 1 && /terminal/.test(e.message),
    );
    assert.equal(
      verifierLancement(args, {}, true),
      join(RACINE, "import", "backup"),
    );
    assert.equal(
      verifierLancement({ commande: "rapport", projet: "kassbeer" }, {}, false),
      join(RACINE, "import", "backup"),
    );
  });

  it("sauvegarde dans le dépôt hors de import/ : refusée avant toute connexion", async () => {
    await semer();
    const ailleurs = join(RACINE, "app", "sauvegarde-test");
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", ailleurs],
      `${PROJET}\n`,
    );
    assert.equal(r.code, 1, r.erreurs);
    assert.match(r.erreurs, /hors de import\/ .*refusé/);
    assert.throws(() => readdirSync(ailleurs));
    assert.equal(await nombre("recipes"), 2);
    assert.throws(() => dossierSauvegarde(RACINE, PROJET), Refus);
    // relative() rend "..copie" pour ce dossier du dépôt : il n'est pas hors du dépôt.
    assert.throws(
      () => dossierSauvegarde(join(RACINE, "..copie"), PROJET),
      (e) =>
        e instanceof Refus &&
        e.code === 1 &&
        /hors de import\//.test(e.message),
    );
    assert.equal(
      dossierSauvegarde(join(RACINE, "import", "x"), PROJET),
      join(RACINE, "import", "x"),
    );
    assert.equal(
      dossierSauvegarde(join(RACINE, "import", "backup"), PROJET),
      join(RACINE, "import", "backup"),
    );
    // tmpdir() est hors de tout arbre Git.
    assert.equal(dossierSauvegarde(dossier, PROJET), dossier);
  });

  it("sauvegarde dans un autre arbre Git : refusée, même si Git y ignore la copie", async () => {
    await semer();
    const depot = mkdtempSync(join(tmpdir(), "kassbeer-autre-depot-"));
    const globale = process.env.GIT_CONFIG_GLOBAL;
    try {
      const init = spawnSync("git", ["init", "-q", depot], {
        encoding: "utf8",
      });
      assert.equal(init.status, 0, init.stderr);
      const copie = join(depot, "backup");
      const refusAutreDepot = (e) =>
        e instanceof Refus &&
        e.code === 1 &&
        /hors de import\/ de ce dépôt/.test(e.message);
      assert.throws(() => dossierSauvegarde(copie, PROJET), refusAutreDepot);
      const r = await lancer(
        ["effacer", "--projet", PROJET, "--sauvegarde", copie],
        `${PROJET}\n`,
      );
      assert.equal(r.code, 1, r.erreurs);
      assert.match(r.erreurs, /hors de import\/ de ce dépôt/);
      assert.doesNotMatch(r.sortie, /Cible/);
      assert.throws(() => readdirSync(copie));
      assert.equal(await nombre("recipes"), 2);
      // Ignoré par le .gitignore de l'autre dépôt : toujours refusé.
      writeFileSync(join(depot, ".gitignore"), "backup/\n");
      assert.throws(() => dossierSauvegarde(copie, PROJET), refusAutreDepot);
      // Ignoré par un fichier d'exclusion global (GIT_CONFIG_GLOBAL) : toujours refusé ;
      // import/backup/ de ce dépôt reste accepté.
      const exclusions = join(depot, "exclusions-globales");
      writeFileSync(exclusions, "*\n");
      const config = join(depot, "config-globale");
      writeFileSync(
        config,
        `[core]\n\texcludesFile = ${exclusions.replaceAll("\\", "/")}\n`,
      );
      process.env.GIT_CONFIG_GLOBAL = config;
      assert.throws(() => dossierSauvegarde(copie, PROJET), refusAutreDepot);
      const importBackup = join(RACINE, "import", "backup");
      assert.equal(dossierSauvegarde(importBackup, PROJET), importBackup);
    } finally {
      if (globale === undefined) delete process.env.GIT_CONFIG_GLOBAL;
      else process.env.GIT_CONFIG_GLOBAL = globale;
      rmSync(depot, { recursive: true, force: true });
    }
  });

  it("sauvegarde dans un arbre Git : GIT_DIR posé ou chemin trop long, refusée", () => {
    const depot = mkdtempSync(join(tmpdir(), "kassbeer-depot-git-"));
    const gitDir = process.env.GIT_DIR;
    try {
      const init = spawnSync("git", ["init", "-q", depot], {
        encoding: "utf8",
      });
      assert.equal(init.status, 0, init.stderr);
      const refusCode1 = (e) => e instanceof Refus && e.code === 1;
      // GIT_DIR vers un chemin absent : git répondrait « hors d'un dépôt » si l'outil lui
      // transmettait la variable.
      process.env.GIT_DIR = join(tmpdir(), "kassbeer-nulle-part");
      assert.throws(
        () => dossierSauvegarde(join(depot, "backup"), PROJET),
        refusCode1,
      );
      if (gitDir === undefined) delete process.env.GIT_DIR;
      else process.env.GIT_DIR = gitDir;
      // Dossier existant au chemin de plus de 260 caractères : sous Windows, git -C échoue
      // (« Filename too long ») ; ailleurs, le dossier est dans un autre arbre Git. Refusé dans les deux cas.
      let long = depot;
      while (long.length <= 300) long = join(long, "d".repeat(40));
      mkdirSync(long, { recursive: true });
      assert.throws(() => dossierSauvegarde(long, PROJET), refusCode1);
    } finally {
      if (gitDir === undefined) delete process.env.GIT_DIR;
      else process.env.GIT_DIR = gitDir;
      rmSync(depot, { recursive: true, force: true });
    }
  });

  it("écriture pendant la confirmation : refusé, rien d'effacé", async () => {
    await semer();
    const sortie = [];
    await assert.rejects(
      effacer(db, PROJET, {
        dossier,
        ecrire: (l) => sortie.push(l),
        demander: async () => {
          await db
            .doc("recipes/tardive")
            .set({ owner_uid: "brewer-a", name: "Tardive" });
          return PROJET;
        },
      }),
      (e) =>
        e instanceof Refus &&
        e.code === 5 &&
        /3 recette\(s\)/.test(e.message) &&
        /recipes\/tardive ajouté/.test(e.message),
    );
    assert.equal(await nombre("recipes"), 3);
    assert.equal(await nombre("brews"), 2);
  });

  // Relecture après la confirmation : le rapport est refait avant tout effacement.
  const confirmerApres = (ecrireEntreTemps) =>
    effacer(db, PROJET, {
      dossier,
      ecrire: () => {},
      demander: async () => {
        await ecrireEntreTemps();
        return PROJET;
      },
    });

  it("brassin passé en brewing pendant la confirmation : code 2, rien d'effacé", async () => {
    await semer();
    await assert.rejects(
      confirmerApres(() => db.doc("brews/b2").update({ status: "brewing" })),
      (e) =>
        e instanceof Refus &&
        e.code === 2 &&
        /Brassin en cours depuis la copie \(b2\)/.test(e.message),
    );
    assert.equal(await nombre("recipes"), 2);
    assert.equal(await nombre("brews"), 2);
    assert.equal(await nombre("brews/b1/events"), 3);
    assert.equal(
      (await db.doc("users/brewer-a/brew_costs/b1").get()).exists,
      true,
    );
  });

  it("document modifié pendant la confirmation, mêmes nombres : code 5, rien d'effacé", async () => {
    await semer();
    await assert.rejects(
      confirmerApres(() =>
        db.doc("brews/b2").update({ name: "Stout renommé" }),
      ),
      (e) =>
        e instanceof Refus &&
        e.code === 5 &&
        /brews\/b2 modifié/.test(e.message),
    );
    assert.equal(await nombre("brews"), 2);
    assert.equal(await nombre("recipes"), 2);
  });

  it("coût figé modifié pendant la confirmation : code 5, rien d'effacé", async () => {
    await semer();
    await assert.rejects(
      confirmerApres(() =>
        db.doc("users/brewer-a/brew_costs/b1").update({ total_eur: 40 }),
      ),
      (e) =>
        e instanceof Refus &&
        e.code === 5 &&
        /users\/brewer-a\/brew_costs\/b1 modifié/.test(e.message),
    );
    assert.equal(await nombre("brews"), 2);
    assert.equal(
      (await db.doc("users/brewer-a/brew_costs/b1").get()).data().total_eur,
      40,
    );
  });

  it("coûts figés lus sans champ : aucun prix dans le relevé", async () => {
    await semer();
    const releve = await rapport(db);
    assert.deepEqual(
      [...releve.coutsFiges.keys()],
      ["users/brewer-a/brew_costs/b1"],
    );
    const snap = releve.coutsFiges.get("users/brewer-a/brew_costs/b1");
    assert.equal(snap.exists, true);
    assert.deepEqual(snap.data(), {});
    assert.ok(snap.updateTime);
    assert.ok(
      [...releve.documents.keys()].every(
        (chemin) => !chemin.startsWith("users/"),
      ),
    );
  });

  // Base dont la suppression du coût figé de b1 échoue : [avant] tourne d'abord, puis
  // l'erreur est levée. Le relevé et les comptes passent par la vraie base.
  const COUT = "users/brewer-a/brew_costs/b1";
  const baseEnEchec = (avant) => {
    let effacementLance = false;
    return new Proxy(db, {
      get(cible, cle) {
        if (cle === "recursiveDelete") {
          return (...args) => {
            effacementLance = true;
            return cible.recursiveDelete(...args);
          };
        }
        if (cle === "doc") {
          return (chemin) => {
            const ref = cible.doc(chemin);
            if (!effacementLance || chemin !== COUT) return ref;
            effacementLance = false;
            return {
              delete: async () => {
                await avant(ref);
                throw new Error("échec simulé");
              },
            };
          };
        }
        const valeur = Reflect.get(cible, cle, cible);
        return typeof valeur === "function" ? valeur.bind(cible) : valeur;
      },
    });
  };

  it("suppression d'un coût figé en échec, coût resté : écrite, code 4", async () => {
    await semer();
    const sortie = [];
    await assert.rejects(
      effacer(
        baseEnEchec(async () => {}),
        PROJET,
        {
          dossier,
          ecrire: (l) => sortie.push(l),
          demander: async () => PROJET,
        },
      ),
      (e) =>
        e instanceof Refus && e.code === 4 && /coûts figés 1/.test(e.message),
    );
    assert.ok(
      sortie.includes(`Coûts figés non effacés : ${COUT} (échec simulé).`),
      sortie.join("\n"),
    );
    assert.equal((await db.doc(COUT).get()).exists, true);
  });

  it("suppression d'un coût figé en échec, coût disparu : écrite, code 0", async () => {
    await semer();
    const sortie = [];
    const resultat = await effacer(
      baseEnEchec((ref) => ref.delete()),
      PROJET,
      { dossier, ecrire: (l) => sortie.push(l), demander: async () => PROJET },
    );
    assert.equal(resultat.avant.couts, 1);
    assert.ok(
      sortie.includes(`Coûts figés non effacés : ${COUT} (échec simulé).`),
      sortie.join("\n"),
    );
    assert.equal((await db.doc(COUT).get()).exists, false);
  });

  it("événement retiré pendant la confirmation : code 5, rien d'effacé", async () => {
    await semer();
    await assert.rejects(
      confirmerApres(() => db.doc("brews/b1/events/e3").delete()),
      (e) =>
        e instanceof Refus &&
        e.code === 5 &&
        /brews\/b1\/events\/e3 retiré/.test(e.message),
    );
    assert.equal(await nombre("brews/b1/events"), 2);
    assert.equal(await nombre("recipes"), 2);
  });

  it("document hors modèle (sous-collection inconnue) : code 5, rien de copié ni d'effacé", async () => {
    await semer();
    await db.doc("brews/b1/notes/n1").set({ texte: "x" });
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", dossier],
      `${PROJET}\n`,
    );
    assert.equal(r.code, 5, r.erreurs);
    assert.match(
      r.sortie,
      /Documents hors modèle : 1\r?\n {2}brews\/b1\/notes\/n1/,
    );
    assert.match(r.erreurs, /Documents hors modèle \(brews\/b1\/notes\/n1\)/);
    assert.equal(await nombre("brews"), 2);
    assert.throws(() => readdirSync(dossier));
  });

  it("événement orphelin (brassin absent) : nommé, copié et effacé", async () => {
    await semer();
    await db
      .doc("brews/absent/events/e9")
      .set({ owner_uid: "brewer-a", kind: "note", note: "x" });
    const seul = await lancer(["rapport", "--projet", PROJET]);
    assert.equal(seul.code, 0, seul.erreurs);
    assert.match(
      seul.sortie,
      /Événements orphelins \(brassin absent\) : 1\r?\n {2}brews\/absent\/events\/e9/,
    );
    assert.match(seul.sortie, /Brassins : 2\r?\n/);
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", dossier],
      `${PROJET}\n`,
    );
    assert.equal(r.code, 0, r.erreurs);
    assert.match(
      r.sortie,
      /2 brassin\(s\), 4 événement\(s\), 1 coût\(s\) figé\(s\)\./,
    );
    assert.equal(await nombre("brews/absent/events"), 0);
    assert.equal(
      (await db.collectionGroup("events").count().get()).data().count,
      0,
    );
    const [fichier] = readdirSync(dossier);
    const copie = JSON.parse(readFileSync(join(dossier, fichier), "utf8"));
    assert.ok("brews/absent/events/e9" in copie.documents);
  });

  it("events/ sous users/ : ni compté ni effacé", async () => {
    await semer();
    await db.doc("users/brewer-a/events/e9").set({ kind: "note" });
    const r = await lancer(
      ["effacer", "--projet", PROJET, "--sauvegarde", dossier],
      `${PROJET}\n`,
    );
    assert.equal(r.code, 0, r.erreurs);
    assert.match(r.sortie, /3 événement\(s\), 1 coût\(s\) figé\(s\)\./);
    assert.match(
      r.sortie,
      /users \(hors coûts figés effacés\) : 4 avant, 4 après\./,
    );
    assert.equal(await nombre("users/brewer-a/events"), 1);
  });

  it("arguments manquants : usage", async () => {
    const r = await lancer(["effacer"]);
    assert.equal(r.code, 1);
    assert.match(r.erreurs, /Usage/);
  });
});
