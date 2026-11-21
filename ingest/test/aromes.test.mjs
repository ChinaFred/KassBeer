// Descriptions aromatiques des houblons (ADR-013, P54, P55), par le moteur commun
// (lib/redaction/, ADR-018) et la nature « houblon » : contrôle des textes, tarif commun,
// budget, refus du modèle, clé jamais écrite, sélection des houblons nouveaux ou changés,
// empreinte figée, entrées relues jamais remplacées, tri par l'écrivain. Le SDK est simulé :
// aucun appel réel ne part.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { NATURE_HOUBLON } from "../lib/aromes/nature.mjs";
import { MODELE, parametresRequete, PROMPT_VERSION, SCHEMA_SORTIE } from "../lib/aromes/prompt.mjs";
import {
  controlerEntreeArome,
  controlerSortieModele,
  DESCRIPTEURS,
  donneesEnvoyees,
  empreinteEntree,
} from "../lib/aromes/validation.mjs";
import { erreurLisible, masquerCle } from "../lib/redaction/client.mjs";
import { generer, lireOptions } from "../lib/redaction/moteur.mjs";
import {
  borneHaute,
  ErreurRedaction,
  lireTarif,
  MESSAGE_TARIF_INCONNU,
} from "../lib/redaction/tarif.mjs";
import { nettoyerTexte, reglesTexte } from "../lib/redaction/texte.mjs";
import {
  compterSansDescription,
  indexAromes,
  messageSansDescription,
  trierRedigees,
} from "../lib/execution.mjs";
import { controlerDocument } from "../lib/validation.mjs";

const CLE = "sk-ant-cle-fictive-0123456789";
const lireOptionsHoublon = (argv) => lireOptions(argv, NATURE_HOUBLON);
const TEXTE =
  "Notes franches d'agrumes et de résine, amertume nette, proche du Cascade en plus doux.";
const MAINTENANT = new Date("2026-11-14T10:00:00Z");

const sortieModele = (extra = {}) => ({
  status: "described",
  confidence: "medium",
  descriptors: ["citrus", "resinous"],
  uses: {
    first_wort: null,
    bittering: TEXTE,
    late_boil: null,
    whirlpool: null,
    dry_hop: TEXTE,
  },
  ...extra,
});

const entree = (id = "hop-alpha", data = {}) => ({
  id,
  data: {
    hop_name: "Alpha",
    status: "described",
    confidence: "high",
    descriptors: [{ key: "citrus", label: "agrumes" }],
    uses: { dry_hop: { text: TEXTE } },
    reviewed: false,
    provenance: [
      {
        source: "claude-api",
        source_id: id,
        version: "claude-fable-5-2 / prompt 1 / effort medium",
        licence: "Texte généré pour Kass'Beer",
        retrieved: "2026-11-14",
      },
    ],
    input_sha256: "a".repeat(64),
    ...data,
  },
});

describe("contrôle d'un texte d'usage", () => {
  it("texte simple accepté, comparaison à un autre houblon permise", () => {
    assert.deepEqual(reglesTexte(TEXTE), []);
    assert.deepEqual(reglesTexte(`${TEXTE} Parfum de fleur et de liqueur, très européen.`), []);
  });

  for (const [cas, texte, regle] of [
    ["URL", `${TEXTE} https://exemple.fr`, "adresse web"],
    ["www.", `${TEXTE} www.exemple`, "adresse web"],
    ["domaine", `${TEXTE} voir houblons.com`, "adresse web"],
    ["@", `${TEXTE} @auteur`, "@"],
    ["€", `${TEXTE} 12 €`, "symbole monétaire"],
    ["$", `${TEXTE} 12 $`, "symbole monétaire"],
    ["EUR", `${TEXTE} 12 EUR`, "monnaie"],
    ["euro", `${TEXTE} un euro`, "monnaie"],
    ["euros", `${TEXTE} deux euros`, "monnaie"],
    ["balise", `${TEXTE} <b>`, "balisage"],
    ["accent grave", `${TEXTE} \`code\``, "balisage"],
    ["# en tête", `# ${TEXTE}`, "balisage"],
    ["* en tête", `* ${TEXTE}`, "balisage"],
    ["39 caractères", "a".repeat(39), "longueur 40 à 400"],
    ["401 caractères", "a".repeat(401), "longueur 40 à 400"],
  ]) {
    it(`${cas} : refusé`, () => assert.ok(reglesTexte(texte).includes(regle), cas));
  }

  it("40 et 400 caractères acceptés", () => {
    assert.deepEqual(reglesTexte("a".repeat(40)), []);
    assert.deepEqual(reglesTexte("é".repeat(400)), []);
  });

  it("nettoyage : NFC, contrôles et bidirectionnels retirés", () => {
    assert.equal(nettoyerTexte("Café‮ x\u0007 "), "Café x");
  });

  it("nettoyage : caractères de format invisibles retirés (U+200B–U+200D, U+2060, U+FEFF)", () => {
    assert.equal(nettoyerTexte("a\u200bb\u200cc\u200dd\u2060e\ufefff\u00adg"), "abcdefg");
  });

  for (const [cas, texte, regle] of [
    ["www avec espace sans chasse", `${TEXTE} www\u200b.exemple.shop`, "adresse web"],
    ["$ pleine chasse", `${TEXTE} 12 ＄`, "symbole monétaire"],
    ["€ avec espace sans chasse", `${TEXTE} 12\u200b€`, "symbole monétaire"],
    ["@ pleine chasse", `${TEXTE} ＠auteur`, "@"],
    ["EUR pleine chasse", `${TEXTE} 12 ＥＵＲ`, "monnaie"],
  ]) {
    it(`${cas} : refusé (forme NFKC)`, () => assert.ok(reglesTexte(texte).includes(regle), cas));
  }

  it("entrée avec un caractère invisible : « texte non nettoyé »", () => {
    const e = entree("hop-alpha", { uses: { dry_hop: { text: `${TEXTE}\u200b` } } });
    assert.ok(
      controlerEntreeArome(e).includes("uses.dry_hop.text : texte non nettoyé (NFC, contrôles)"),
    );
  });
});

describe("sortie du modèle", () => {
  it("bonne sortie : descripteurs avec leur libellé, usages null écartés", () => {
    const { regles, resultat } = controlerSortieModele(sortieModele());
    assert.deepEqual(regles, []);
    assert.deepEqual(resultat.descriptors, [
      { key: "citrus", label: "agrumes" },
      { key: "resinous", label: "résineux" },
    ]);
    assert.deepEqual(Object.keys(resultat.uses).sort(), ["bittering", "dry_hop"]);
  });

  it("unknown sans texte accepté", () => {
    const u = {
      first_wort: null,
      bittering: null,
      late_boil: null,
      whirlpool: null,
      dry_hop: null,
    };
    const { regles, resultat } = controlerSortieModele({
      status: "unknown",
      confidence: null,
      descriptors: [],
      uses: u,
    });
    assert.deepEqual(regles, []);
    assert.deepEqual(resultat, { status: "unknown", descriptors: [], uses: {} });
  });

  it("refus : described sans usage, unknown avec texte, descripteur hors liste ou en double", () => {
    const sansUsage = {
      first_wort: null,
      bittering: null,
      late_boil: null,
      whirlpool: null,
      dry_hop: null,
    };
    assert.notDeepEqual(controlerSortieModele(sortieModele({ uses: sansUsage })).regles, []);
    assert.notDeepEqual(
      controlerSortieModele(sortieModele({ status: "unknown", confidence: null, descriptors: [] }))
        .regles,
      [],
    );
    assert.notDeepEqual(
      controlerSortieModele(sortieModele({ descriptors: ["vanille"] })).regles,
      [],
    );
    assert.notDeepEqual(
      controlerSortieModele(sortieModele({ descriptors: ["citrus", "citrus"] })).regles,
      [],
    );
    assert.notDeepEqual(controlerSortieModele(sortieModele({ descriptors: [] })).regles, []);
    const neuf = DESCRIPTEURS.slice(0, 9).map((d) => d.key);
    assert.notDeepEqual(controlerSortieModele(sortieModele({ descriptors: neuf })).regles, []);
    assert.notDeepEqual(controlerSortieModele({ ...sortieModele(), extra: 1 }).regles, []);
  });

  it("une erreur ne recopie pas le texte", () => {
    const texte = `${TEXTE} https://exemple.fr/secret-de-texte`;
    const { regles } = controlerSortieModele(
      sortieModele({ uses: { ...sortieModele().uses, dry_hop: texte } }),
    );
    assert.ok(regles.length > 0);
    assert.ok(regles.every((r) => !r.includes("secret-de-texte")));
  });
});

describe("entrée de aromes.json", () => {
  it("entrée bonne acceptée ; relue avec sa date acceptée", () => {
    assert.deepEqual(controlerEntreeArome(entree()), []);
    assert.deepEqual(
      controlerEntreeArome(entree("hop-alpha", { reviewed: true, reviewed_at: "2026-11-15" })),
      [],
    );
  });

  it("reviewed: true sans reviewed_at, ou date fausse : refusé", () => {
    assert.notDeepEqual(controlerEntreeArome(entree("hop-alpha", { reviewed: true })), []);
    assert.notDeepEqual(
      controlerEntreeArome(entree("hop-alpha", { reviewed: true, reviewed_at: "2026-02-30" })),
      [],
    );
    assert.notDeepEqual(
      controlerEntreeArome(entree("hop-alpha", { reviewed_at: "2026-11-15" })),
      [],
    );
  });

  it("label différent de la liste, clé non permise, provenance d'un autre houblon : refusé", () => {
    assert.notDeepEqual(
      controlerEntreeArome(
        entree("hop-alpha", { descriptors: [{ key: "citrus", label: "citrons" }] }),
      ),
      [],
    );
    assert.notDeepEqual(controlerEntreeArome(entree("hop-alpha", { notes: "x" })), []);
    assert.notDeepEqual(controlerEntreeArome({ ...entree(), id: "hop-beta" }), []);
    assert.notDeepEqual(controlerEntreeArome({ ...entree(), id: "fermentable-x" }), []);
  });
});

describe("requête", () => {
  it("ni thinking, ni temperature, ni tools, ni tool_choice, ni message assistant", () => {
    const p = parametresRequete({ name: "Alpha" }, { effort: "medium", cache: true });
    for (const cle of ["thinking", "temperature", "tools", "tool_choice", "budget_tokens"]) {
      assert.equal(cle in p, false, cle);
    }
    assert.equal(p.model, MODELE);
    assert.deepEqual(
      p.messages.map((m) => m.role),
      ["user"],
    );
    assert.deepEqual(p.output_config, {
      effort: "medium",
      format: { type: "json_schema", schema: SCHEMA_SORTIE },
    });
    assert.deepEqual(p.system[0].cache_control, { type: "ephemeral" });
    assert.equal(
      "cache_control" in parametresRequete({}, { effort: "low", cache: false }).system[0],
      false,
    );
  });
});

describe("tarif et borne haute", () => {
  const tarifValide = {
    model: MODELE,
    date: "2026-11-03",
    source: "grille tarifaire d'Anthropic",
    usd_per_million_tokens: {
      input: 8,
      output: 40,
      cache_write: 10,
      cache_read: 0.8,
      batch_input: 4,
      batch_output: 20,
    },
  };
  const lire = (t) => () => JSON.stringify(t);

  it("tarif absent, d'un autre modèle, ou de plus de 90 jours : « Tarif inconnu »", () => {
    const absent = () => {
      throw Object.assign(new Error("absent"), { code: "ENOENT" });
    };
    for (const l of [
      absent,
      lire({ ...tarifValide, model: "autre" }),
      lire({ ...tarifValide, date: "2026-08-01" }),
      lire({ ...tarifValide, usd_per_million_tokens: { input: 8 } }),
    ]) {
      assert.throws(
        () => lireTarif("tarif.json", MODELE, MAINTENANT, l),
        (e) => e instanceof ErreurRedaction && e.message.startsWith(MESSAGE_TARIF_INCONNU),
      );
    }
    assert.equal(lireTarif("tarif.json", MODELE, MAINTENANT, lire(tarifValide)).date, "2026-11-03");
  });

  it("borne haute : jetons comptés × entrée + max_tokens × sortie, par houblon", () => {
    const tarif = lireTarif("t", MODELE, MAINTENANT, lire(tarifValide));
    // Lot : 2 × (1 000 × 4 + 4 000 × 20) / 1e6 = 0,168 $.
    assert.deepEqual(
      borneHaute([1000, 1000], { tarif, mode: "lot", maxTokens: 4000, budget: 0.1 }),
      {
        montant: 0.168,
        tiennent: 1,
      },
    );
    // Direct : entrée au prix de l'écriture du cache, plus cher ; 1 000 × 10 + 4 000 × 40.
    assert.equal(borneHaute([1000], { tarif, mode: "direct", maxTokens: 4000 }).montant, 0.17);
  });
});

describe("options", () => {
  it("--lot et --nouveaux sans --budget-usd : refusés ; essai sans budget accepté", () => {
    assert.throws(() => lireOptionsHoublon(["--lot"]), ErreurRedaction);
    assert.throws(() => lireOptionsHoublon(["--nouveaux"]), ErreurRedaction);
    assert.equal(lireOptionsHoublon(["--essai"]).essai, 10);
    assert.equal(lireOptionsHoublon(["--essai", "3"]).essai, 3);
  });

  it("--max au-delà de 500, effort inconnu, deux modes : refusés", () => {
    assert.throws(
      () => lireOptionsHoublon(["--lot", "--budget-usd", "1", "--max", "501"]),
      ErreurRedaction,
    );
    assert.throws(() => lireOptionsHoublon(["--essai", "--effort", "aucun"]), ErreurRedaction);
    assert.throws(
      () => lireOptionsHoublon(["--essai", "--lot", "--budget-usd", "1"]),
      ErreurRedaction,
    );
    assert.throws(() => lireOptionsHoublon([]), ErreurRedaction);
  });
});

describe("clé", () => {
  it("masquée dans un message d'erreur du SDK", () => {
    const e = Object.assign(new Error(`invalid x-api-key ${CLE}`), {
      name: "AuthenticationError",
      status: 401,
    });
    const t = erreurLisible(e, CLE);
    assert.equal(t.includes(CLE), false);
    assert.ok(t.includes("HTTP 401"));
    assert.equal(masquerCle(`a${CLE}b${CLE}`, CLE), "a[clé retirée]b[clé retirée]");
  });
});

describe("le SDK n'est pas chargé à l'import", () => {
  it("moteur, tarif, texte, client, nature, validation et execution (ecrire.mjs) s'importent sans lui", () => {
    const hook = fileURLToPath(new URL("./support/interdire-sdk.mjs", import.meta.url));
    const modules = [
      "../lib/redaction/texte.mjs",
      "../lib/redaction/tarif.mjs",
      "../lib/redaction/client.mjs",
      "../lib/redaction/moteur.mjs",
      "../lib/redaction/entree.mjs",
      "../lib/redaction/lancer.mjs",
      "../lib/aromes/validation.mjs",
      "../lib/aromes/prompt.mjs",
      "../lib/aromes/nature.mjs",
      "../lib/execution.mjs",
    ].map((m) => new URL(m, import.meta.url).href);
    const code = `for (const m of ${JSON.stringify(modules)}) await import(m); console.log("ok");`;
    const sortie = execFileSync(
      process.execPath,
      ["--import", hook, "--input-type=module", "-e", code],
      {
        encoding: "utf8",
      },
    );
    assert.equal(sortie.trim(), "ok");
    // Le crochet refuse bien le SDK : sans lui, ce test ne prouverait rien.
    assert.throws(() =>
      execFileSync(
        process.execPath,
        ["--import", hook, "--input-type=module", "-e", 'await import("@anthropic-ai/sdk")'],
        {
          cwd: fileURLToPath(new URL("..", import.meta.url)),
          stdio: "pipe",
        },
      ),
    );
  });
});

/// Empreinte `input_sha256` de hop-houblon-fictif (test/fixtures/prepare/beer_hops.json),
/// modèle claude-fable-5-2, prompt 1, effort medium, calculée sur le code d'avant le moteur
/// commun (ADR-018, invariant de la refonte). Une valeur changée renverrait tous les houblons.
const EMPREINTE_FIGEE = "2b7ca0ed78301eb4aa4afd6885944fc2d4dd917b3401ac7016c92d79aa094bdb";

describe("empreinte des houblons (ADR-018, invariant)", () => {
  it("forme canonique {hop, prompt_version, model, effort} : valeur figée", () => {
    const [h] = JSON.parse(
      readFileSync(new URL("./fixtures/prepare/beer_hops.json", import.meta.url), "utf8"),
    );
    assert.equal(PROMPT_VERSION, 1);
    assert.equal(MODELE, "claude-fable-5-2");
    const options = { promptVersion: PROMPT_VERSION, modele: MODELE, effort: "medium" };
    assert.equal(empreinteEntree(donneesEnvoyees(h.data), options), EMPREINTE_FIGEE);
    assert.equal(
      NATURE_HOUBLON.empreinteEntree(NATURE_HOUBLON.donneesEnvoyees(h.data), options),
      EMPREINTE_FIGEE,
    );
  });
});

describe("moteur commun", () => {
  it("aucun nom de poste ni de nature écrit dans lib/redaction/", () => {
    const dossier = new URL("../lib/redaction/", import.meta.url);
    for (const f of readdirSync(dossier)) {
      const source = readFileSync(new URL(f, dossier), "utf8");
      for (const nom of [
        "hop_aroma_generation",
        "misc_description_generation",
        "beer_hop",
        "beer_misc",
        "hop_name",
      ]) {
        assert.equal(source.includes(nom), false, `${f} : ${nom}`);
      }
    }
  });
});

/// SDK simulé : compte les appels, rend [reponses] dans l'ordre.
function sdkSimule({ reponses = [], jetons = 1000, erreurCreate = null, erreurLot = null } = {}) {
  const appels = { charge: 0, count: 0, create: [], lots: [], options: [] };
  let n = 0;
  class Anthropic {
    constructor(opts) {
      appels.options.push(opts);
      this.messages = {
        countTokens: async () => {
          appels.count++;
          return { input_tokens: jetons };
        },
        create: async (params) => {
          appels.create.push(params);
          if (erreurCreate) throw erreurCreate;
          return reponses[n++];
        },
        batches: {
          create: async (params) => {
            appels.lots.push(params);
            if (erreurLot) throw erreurLot;
            return { id: "msgbatch_fictif01", processing_status: "in_progress" };
          },
          retrieve: async () => ({
            id: "msgbatch_fictif01",
            processing_status: "ended",
            request_counts: { processing: 0, succeeded: 1, errored: 1, canceled: 0, expired: 0 },
          }),
          results: async () =>
            (async function* () {
              yield {
                custom_id: "h0001",
                result: { type: "succeeded", message: message(sortieModele()) },
              };
              yield { custom_id: "h0002", result: { type: "errored", error: {} } };
            })(),
        },
      };
    }
  }
  return {
    appels,
    chargerSdk: async () => {
      appels.charge++;
      return { default: Anthropic };
    },
  };
}

const message = (sortie, stop = "end_turn") => ({
  stop_reason: stop,
  content: [{ type: "text", text: JSON.stringify(sortie) }],
  usage: {
    input_tokens: 1000,
    output_tokens: 1500,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
  },
});

const TARIF = {
  model: MODELE,
  date: "2026-11-03",
  source: "grille tarifaire d'Anthropic, relevée le 2026-11-03",
  usd_per_million_tokens: {
    input: 8,
    output: 40,
    cache_write: 10,
    cache_read: 0.8,
    batch_input: 4,
    batch_output: 20,
  },
};

describe("génération (SDK simulé)", () => {
  let racine;
  let prepare;
  let aromes;
  let lignes;
  let confirmations;

  const houblon = (id, name) => ({
    id,
    data: {
      name,
      aliases: [],
      alpha_acid: { value: 7, unit: "%" },
      purpose: "aroma",
      notes: "jamais envoyé",
    },
  });

  const lancer = (argv, sdk, { confirmer = true, nature = NATURE_HOUBLON } = {}) =>
    generer({
      nature,
      argv: [...argv, "--dossier", prepare, "--aromes", aromes],
      env: { ANTHROPIC_API_KEY: CLE },
      entree: {},
      sortie: {},
      maintenant: () => MAINTENANT,
      chargerSdk: sdk.chargerSdk,
      confirmer: async () => {
        confirmations++;
        return confirmer;
      },
      ecrire: (t) => lignes.push(t),
    });

  const lireAromes = () => JSON.parse(readFileSync(join(aromes, "aromes.json"), "utf8"));

  beforeEach(() => {
    racine = mkdtempSync(join(tmpdir(), "kassbeer-aromes-"));
    prepare = join(racine, "prepare");
    aromes = join(racine, "aromes");
    mkdirSync(prepare);
    mkdirSync(aromes);
    writeFileSync(
      join(prepare, "beer_hops.json"),
      JSON.stringify([houblon("hop-alpha", "Alpha"), houblon("hop-beta", "Beta")]),
    );
    // Tarif commun (ADR-018) : dossier parent de celui de la nature.
    writeFileSync(join(racine, "tarif.json"), JSON.stringify(TARIF));
    lignes = [];
    confirmations = 0;
  });
  afterEach(() => rmSync(racine, { recursive: true, force: true }));

  it("sans tarif : refus avant tout appel, SDK non chargé", async () => {
    rmSync(join(racine, "tarif.json"));
    const sdk = sdkSimule();
    await assert.rejects(lancer(["--essai"], sdk), (e) =>
      e.message.startsWith(MESSAGE_TARIF_INCONNU),
    );
    assert.equal(sdk.appels.charge, 0);
    assert.equal(confirmations, 0);
  });

  it("au-delà du budget : refus après comptage, sans confirmation ni envoi", async () => {
    const sdk = sdkSimule({ jetons: 1000 });
    await assert.rejects(
      lancer(["--lot", "--budget-usd", "0.1"], sdk),
      /au-delà du budget.*1 houblons tiendraient/s,
    );
    assert.equal(sdk.appels.count, 2);
    assert.equal(sdk.appels.lots.length, 0);
    assert.equal(confirmations, 0);
  });

  it("confirmation refusée : rien n'est envoyé", async () => {
    const sdk = sdkSimule();
    await assert.rejects(lancer(["--essai"], sdk, { confirmer: false }), ErreurRedaction);
    assert.equal(sdk.appels.create.length, 0);
  });

  it("essai : données envoyées seules, entrées écrites, rapport du poste, clé absente des sorties", async () => {
    const sdk = sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(cr.poste, "hop_aroma_generation");
    assert.equal(cr.generes, 2);
    assert.equal(cr.montant_usd, (2 * (1000 * 8 + 1500 * 40)) / 1e6);
    const envoye = sdk.appels.create[0].messages[0].content;
    assert.equal(envoye.includes("jamais envoyé"), false);
    assert.equal(sdk.appels.options[0].apiKey, CLE);
    assert.deepEqual(
      lireAromes().map((e) => e.id),
      ["hop-alpha", "hop-beta"],
    );
    const fichiers = readdirSync(aromes, { recursive: true }).map((f) => join(aromes, f));
    const brut = fichiers.filter((f) => f.includes("brut") && f.endsWith(".json"));
    assert.ok(
      brut.some((f) => f.endsWith("-medium.json")),
      "effort dans le nom du fichier brut",
    );
    for (const f of fichiers.filter((x) => x.endsWith(".json") || x.endsWith(".md"))) {
      assert.equal(readFileSync(f, "utf8").includes(CLE), false, f);
    }
    assert.equal(lignes.join("\n").includes(CLE), false);
    // Seconde exécution : empreinte inchangée, rien n'est renvoyé.
    const sdk2 = sdkSimule();
    const cr2 = await lancer(["--essai"], sdk2);
    assert.equal(cr2.counts.inchanges, 2);
    assert.equal(sdk2.appels.charge, 0);
  });

  it("refusal : compté en erreur, sans texte et sans second appel", async () => {
    const sdk = sdkSimule({
      reponses: [message({}, "refusal"), message(sortieModele(), "max_tokens")],
    });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(sdk.appels.create.length, 2);
    assert.deepEqual(cr.erreurs, [
      { id: "hop-alpha", raison: "refusal" },
      { id: "hop-beta", raison: "max_tokens" },
    ]);
    assert.equal(cr.generes, 0);
  });

  it("erreur de l'API : clé retirée du rapport et de l'écran, houblons suivants non envoyés", async () => {
    const erreur = Object.assign(new Error(`clé ${CLE} refusée`), {
      name: "AuthenticationError",
      status: 401,
    });
    const sdk = sdkSimule({ erreurCreate: erreur });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(sdk.appels.create.length, 1);
    assert.deepEqual(cr.non_envoyes, ["hop-beta"]);
    assert.equal(JSON.stringify(cr).includes(CLE), false);
    assert.equal(readFileSync(join(aromes, "rapport.json"), "utf8").includes(CLE), false);
    assert.equal(lignes.join("\n").includes(CLE), false);
  });

  it("appel coupé sans réponse : compté au résultat inconnu, montant incomplet", async () => {
    const coupure = Object.assign(new Error("Connection error."), { name: "APIConnectionError" });
    const sdk = sdkSimule({ erreurCreate: coupure });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(cr.appels_au_resultat_inconnu, 1);
    assert.equal(cr.montant_incomplet, true);
    const rapport = JSON.parse(readFileSync(join(aromes, "rapport.json"), "utf8"));
    assert.equal(rapport.appels_au_resultat_inconnu, 1);
    assert.ok(lignes.some((l) => l.startsWith("Résultat inconnu pour hop-alpha")));
    assert.ok(
      lignes.some((l) => l.includes("(incomplet)") && l.includes("appels au résultat inconnu : 1")),
    );
  });

  it("erreur HTTP en appel direct : aucun résultat inconnu compté", async () => {
    const erreur = Object.assign(new Error("overloaded"), { name: "OverloadedError", status: 529 });
    const cr = await lancer(["--essai"], sdkSimule({ erreurCreate: erreur }));
    assert.equal(cr.appels_au_resultat_inconnu, 0);
    assert.equal(cr.montant_incomplet, false);
  });

  it("lot coupé sans réponse : « Résultat inconnu », table lot-attente gardée", async () => {
    const coupure = Object.assign(new Error("Request timed out."), {
      name: "APIConnectionTimeoutError",
    });
    await assert.rejects(
      lancer(["--lot", "--budget-usd", "5"], sdkSimule({ erreurLot: coupure })),
      (e) =>
        e instanceof ErreurRedaction &&
        e.message.includes(
          "Résultat inconnu : vérifiez les lots dans la Console Anthropic avant de relancer",
        ) &&
        !e.message.includes("Rien n'est parti"),
    );
    const attente = readdirSync(aromes).filter((f) => /^lot-attente-[0-9TZ]+\.json$/.test(f));
    assert.equal(attente.length, 1);
    const table = JSON.parse(readFileSync(join(aromes, attente[0]), "utf8")).table;
    assert.equal(table.h0001.id, "hop-alpha");
  });

  it("lot refusé par l'API (statut HTTP) : « Rien n'est parti », aucune table en attente", async () => {
    const refus = Object.assign(new Error("invalid request"), {
      name: "BadRequestError",
      status: 400,
    });
    await assert.rejects(
      lancer(["--lot", "--budget-usd", "5"], sdkSimule({ erreurLot: refus })),
      /Rien n'est parti/,
    );
    assert.deepEqual(
      readdirSync(aromes).filter((f) => /^lot-attente-[0-9TZ]+\.json$/.test(f)),
      [],
    );
  });

  it("une entrée relue n'est jamais remplacée : réponse dans brut/, rapport « relue, non remplacée »", async () => {
    const relue = entree("hop-alpha", { reviewed: true, reviewed_at: "2026-11-14" });
    writeFileSync(join(aromes, "aromes.json"), JSON.stringify([relue]));
    // Sans --regenerer : empreinte différente, l'entrée relue est signalée, pas renvoyée.
    const sdk = sdkSimule({ reponses: [message(sortieModele())] });
    const cr = await lancer(["--essai"], sdk);
    assert.deepEqual(cr.relues, [{ id: "hop-alpha", raison: "relue, entrées changées" }]);
    assert.equal(sdk.appels.create.length, 1, "seul hop-beta part");
    // Avec --regenerer : la réponse part, l'entrée relue reste.
    const sdk2 = sdkSimule({ reponses: [message(sortieModele({ confidence: "low" }))] });
    const cr2 = await lancer(["--essai", "--regenerer", "hop-alpha"], sdk2);
    assert.deepEqual(cr2.relues, [{ id: "hop-alpha", raison: "relue, non remplacée" }]);
    assert.deepEqual(
      lireAromes().find((e) => e.id === "hop-alpha"),
      relue,
    );
  });

  it("nouveau houblon : détecté, et --nouveaux ne prend que lui", async () => {
    const sdk = sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] });
    await lancer(["--essai"], sdk);
    writeFileSync(
      join(prepare, "beer_hops.json"),
      JSON.stringify([
        houblon("hop-alpha", "Alpha"),
        houblon("hop-beta", "Beta"),
        houblon("hop-gamma", "Gamma"),
      ]),
    );
    const sdk2 = sdkSimule({ reponses: [message(sortieModele())] });
    const cr = await lancer(["--nouveaux", "--budget-usd", "1"], sdk2);
    assert.deepEqual(cr.counts, { nouveaux: 1, changes: 0, inchanges: 2, envoyes: 1 });
    assert.equal(sdk2.appels.create.length, 1);
    assert.ok(sdk2.appels.create[0].messages[0].content.includes("Gamma"));
    assert.ok(lignes.some((l) => l.includes("1 nouveaux, 0 changés, 2 inchangés")));
    assert.deepEqual(
      lireAromes().map((e) => e.id),
      ["hop-alpha", "hop-beta", "hop-gamma"],
    );
  });

  it("--effort différent : les houblons sont « changés » et renvoyés", async () => {
    await lancer(
      ["--essai"],
      sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] }),
    );
    const sdk = sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] });
    const cr = await lancer(["--essai", "--effort", "low"], sdk);
    assert.equal(cr.counts.changes, 2);
    assert.equal(sdk.appels.create[0].output_config.effort, "low");
  });

  it("lot : custom_id h0001…, table écrite, puis --suivre fusionne et liste les manquants", async () => {
    const sdk = sdkSimule();
    const cr = await lancer(["--lot", "--budget-usd", "5"], sdk);
    assert.equal(cr.batch_id, "msgbatch_fictif01");
    assert.deepEqual(
      sdk.appels.lots[0].requests.map((r) => r.custom_id),
      ["h0001", "h0002"],
    );
    assert.equal("cache_control" in sdk.appels.lots[0].requests[0].params.system[0], false);
    const lot = JSON.parse(readFileSync(join(aromes, "lot-msgbatch_fictif01.json"), "utf8"));
    assert.equal(lot.table.h0002.id, "hop-beta");
    const suivi = await lancer(["--suivre", "msgbatch_fictif01"], sdkSimule());
    assert.equal(suivi.generes, 1);
    assert.deepEqual(suivi.a_relancer, [{ id: "hop-beta", raison: "errored" }]);
    assert.deepEqual(
      lireAromes().map((e) => e.id),
      ["hop-alpha"],
    );
    // Rejoué : même état.
    const suivi2 = await lancer(["--suivre", "msgbatch_fictif01"], sdkSimule());
    assert.deepEqual(
      lireAromes().map((e) => e.id),
      ["hop-alpha"],
    );
    assert.equal(suivi2.generes, 1);
    await assert.rejects(lancer(["--suivre", "msgbatch_inconnu"], sdkSimule()), ErreurRedaction);
  });

  it("a-relire.md : les houblons du groupe seuls", async () => {
    writeFileSync(
      join(aromes, "houblons-recettes.json"),
      JSON.stringify({
        format: "kassbeer_houblons_recettes",
        version: 1,
        resolus: [{ id: "hop-beta", noms: ["Beta"] }],
        non_resolus: [{ nom: "Inconnu", raison: "aucun" }],
      }),
    );
    await lancer(
      ["--essai"],
      sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] }),
    );
    const md = readFileSync(join(aromes, "a-relire.md"), "utf8");
    assert.ok(md.includes("`hop-beta`"));
    assert.equal(md.includes("`hop-alpha`"), false);
    assert.ok(md.includes("Inconnu : aucun"));
  });

  it("tarif à l'ancien emplacement seul (aromes/tarif.json) : refus qui dit de le déplacer, SDK non chargé", async () => {
    rmSync(join(racine, "tarif.json"));
    writeFileSync(join(aromes, "tarif.json"), JSON.stringify(TARIF));
    const sdk = sdkSimule();
    await assert.rejects(
      lancer(["--essai"], sdk),
      (e) =>
        e instanceof ErreurRedaction &&
        e.message.startsWith(MESSAGE_TARIF_INCONNU) &&
        e.message.includes("n'est plus lu depuis ADR-018") &&
        e.message.includes(join(racine, "tarif.json")),
    );
    assert.equal(sdk.appels.charge, 0);
    assert.equal(confirmations, 0);
  });

  it("tarif aux deux emplacements : le tarif commun est lu, l'ancien signalé ignoré", async () => {
    writeFileSync(
      join(aromes, "tarif.json"),
      JSON.stringify({ ...TARIF, usd_per_million_tokens: { input: -1 } }),
    );
    const sdk = sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(cr.generes, 2);
    assert.ok(lignes.some((l) => l.includes("ignoré : seul") && l.includes("(ADR-018)")));
  });

  it("le rapport porte le poste de la nature passée au moteur", async () => {
    const nature = { ...NATURE_HOUBLON, poste: "poste_de_test" };
    const sdk = sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] });
    const cr = await lancer(["--essai"], sdk, { nature });
    assert.equal(cr.poste, "poste_de_test");
    const rapport = JSON.parse(readFileSync(join(aromes, "rapport.json"), "utf8"));
    assert.equal(rapport.poste, "poste_de_test");
    const relire = await lancer(["--relire"], sdkSimule(), { nature });
    assert.equal(relire.poste, "poste_de_test");
  });

  it("empreinte du houblon de fixture inchangée par le moteur commun (ADR-018)", async () => {
    // Valeur calculée sur le code d'avant la refonte (lib/aromes/generation.mjs, commit
    // 455f6df9) pour test/fixtures/prepare/beer_hops.json, effort medium.
    const fixture = readFileSync(
      new URL("./fixtures/prepare/beer_hops.json", import.meta.url),
      "utf8",
    );
    writeFileSync(join(prepare, "beer_hops.json"), fixture);
    const sdk = sdkSimule({ reponses: [message(sortieModele())] });
    await lancer(["--essai"], sdk);
    const [e] = lireAromes();
    assert.equal(e.id, "hop-houblon-fictif");
    assert.equal(e.data.input_sha256, EMPREINTE_FIGEE);
  });
});

describe("tri des arômes par l'écrivain", () => {
  const ids = new Set(["hop-alpha", "hop-beta"]);

  it("bonne entrée : content_sha256 ajouté ; houblon du groupe non relu et id inconnu refusés", () => {
    const { valides, refuses } = trierRedigees(
      NATURE_HOUBLON,
      [entree("hop-alpha"), entree("hop-beta", { hop_name: "Beta" }), entree("hop-gamma")],
      ids,
      new Set(["hop-beta"]),
    );
    assert.deepEqual(
      valides.map((v) => v.id),
      ["hop-alpha"],
    );
    assert.match(valides[0].data.content_sha256, /^[0-9a-f]{64}$/);
    assert.deepEqual(
      refuses.map((r) => [r.id, r.erreurs]),
      [
        ["hop-beta", ["reviewed : houblon des recettes du groupe non relu"]],
        ["hop-gamma", ["id : houblon absent de beer_hops.json"]],
      ],
    );
  });

  it("houblon du groupe relu : accepté ; entrée en double refusée", () => {
    const relue = entree("hop-beta", { reviewed: true, reviewed_at: "2026-11-14" });
    const { valides, refuses } = trierRedigees(
      NATURE_HOUBLON,
      [relue, relue],
      ids,
      new Set(["hop-beta"]),
    );
    assert.equal(valides.length, 1);
    assert.deepEqual(refuses[0].erreurs, ["id : en double"]);
  });

  it("index des arômes : id et confiance des entrées acceptées, triés ; unknown sans confiance", () => {
    const { valides } = trierRedigees(
      NATURE_HOUBLON,
      [
        entree("hop-beta", { confidence: "low" }),
        entree("hop-alpha", {
          status: "unknown",
          confidence: undefined,
          descriptors: [],
          uses: {},
        }),
        entree("hop-gamma"),
      ].map((e) => JSON.parse(JSON.stringify(e))),
      new Set(["hop-alpha", "hop-beta"]),
      new Set(),
    );
    const index = indexAromes(valides);
    assert.equal(index.id, "hop_aromas");
    assert.deepEqual(index.data.entries, [
      { id: "hop-alpha", confidence: "unknown" },
      { id: "hop-beta", confidence: "low" },
    ]);
    assert.equal(index.data.count, 2);
    assert.match(index.data.content_sha256, /^[0-9a-f]{64}$/);
    assert.deepEqual(controlerDocument("beer_index", index), []);
    // Même contenu, même empreinte : un index inchangé n'est pas réécrit.
    assert.equal(
      indexAromes([...valides].reverse()).data.content_sha256,
      index.data.content_sha256,
    );
    // Aucun texte ni état de relecture dans l'index.
    assert.equal(JSON.stringify(index).includes("reviewed"), false);
    assert.equal(JSON.stringify(index).includes(TEXTE), false);
  });

  it("houblons sans description : compte et message", () => {
    const hops = [{ id: "hop-alpha" }, { id: "hop-beta" }, { id: "hop-gamma" }];
    assert.equal(compterSansDescription(hops, [entree("hop-alpha")]), 2);
    assert.equal(messageSansDescription(0, NATURE_HOUBLON), null);
    assert.match(
      messageSansDescription(2, NATURE_HOUBLON),
      /^2 houblons sans description aromatique : lancez `node generer-aromes\.mjs --nouveaux`/,
    );
  });
});

describe("prompt documenté", () => {
  it("exigences-techniques.md recopie PROMPT_SYSTEME à l'identique", async () => {
    const { PROMPT_SYSTEME, PROMPT_VERSION } = await import("../lib/aromes/prompt.mjs");
    const doc = readFileSync(
      new URL("../../documentation/exigences-techniques.md", import.meta.url),
      "utf8",
    );
    const titre = `### Prompt (\`prompt_version\` ${PROMPT_VERSION})`;
    const debut = doc.indexOf("```text\n", doc.indexOf(titre));
    assert.ok(doc.includes(titre) && debut > 0, "section du prompt absente");
    const fin = doc.indexOf("\n```", debut + 8);
    assert.equal(doc.slice(debut + 8, fin), PROMPT_SYSTEME);
  });
});
