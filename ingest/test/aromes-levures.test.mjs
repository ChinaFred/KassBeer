// Descriptions aromatiques des levures (ADR-017, P62 et P54) : descripteurs, données
// envoyées, périmètre, contrôle des sorties et des entrées, requête, génération avec un SDK
// simulé et tri par l'écrivain. Aucun appel réel à l'API : le SDK est remplacé, et les
// levures, styles et textes sont inventés (P20).

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { genererAromes, lireOptionsAromes, perimetre } from "../lib/aromes/generation.mjs";
import {
  contexteStyles,
  controlerEntreeAromeLevure,
  controlerSortieLevure,
  DESCRIPTEURS_LEVURES,
  donneesEnvoyeesLevure,
  empreinteEntreeLevure,
  NATURE_LEVURE,
  parametresRequeteLevure,
  PROMPT_LEVURES,
  PROMPT_VERSION_LEVURES,
  TYPES_HORS_PERIMETRE,
} from "../lib/aromes/natures/culture.mjs";
import { MODELE } from "../lib/aromes/prompt.mjs";
import { ErreurAromes, MESSAGE_TARIF_INCONNU } from "../lib/aromes/tarif.mjs";
import { controlerListeGroupe, relueOrphelines, trierAromes } from "../lib/execution.mjs";
import { ErreurOptions } from "../lib/options.mjs";

const CLE = "sk-ant-cle-fictive-levures-0123456789";
const MAINTENANT = new Date("2026-11-21T10:00:00Z");
const PROFIL = "Profil inventé pour le test : fermentation nette, esters discrets, finale sèche.";
const CHAUD = "Inventé : plus chaude, la levure arrondit la bouche et pousse les esters fruités.";

const STYLES = [
  { id: "bjcp2021-99a", data: { name: "Style Fictif A" } },
  { id: "bjcp2021-99b", data: { name: "Style Fictif B" } },
];
const CONTEXTE = contexteStyles(STYLES);

const levure = (id, name, extra = {}) => ({
  id,
  data: {
    name,
    aliases: [],
    type: "ale",
    form: "dry",
    producer: "Labo Fictif",
    product_id: "LF1",
    attenuation: { minimum: { value: 70, unit: "%" }, maximum: { value: 80, unit: "%" } },
    temperature_range: { minimum: { value: 15, unit: "C" }, maximum: { value: 22, unit: "C" } },
    flocculation: "medium",
    notes: "jamais envoyé",
    provenance: [{ source: "fabricants", source_id: "provenance-jamais-envoyee" }],
    ...extra,
  },
});

const sortieModele = (extra = {}) => ({
  status: "described",
  confidence: "medium",
  descriptors: ["clean", "fruity_esters"],
  texts: { profile: PROFIL, cool: null, warm: CHAUD },
  styles: ["bjcp2021-99a"],
  ...extra,
});

const entree = (id = "culture-alpha", data = {}) => ({
  id,
  data: {
    culture_name: "Alpha",
    status: "described",
    confidence: "high",
    descriptors: [{ key: "clean", label: "neutre" }],
    texts: { profile: { text: PROFIL } },
    styles: [{ code: "bjcp2021-99a", name: "Style Fictif A" }],
    reviewed: false,
    provenance: [
      {
        source: "claude-api",
        source_id: id,
        version: "claude-fable-5-2 / prompt 1 / effort medium",
        licence: "Texte généré pour Kass'Beer",
        retrieved: "2026-11-21",
      },
    ],
    input_sha256: "a".repeat(64),
    ...data,
  },
});

describe("levures : descripteurs", () => {
  it("les 32 descripteurs de la section 4, sans doublon", () => {
    assert.equal(DESCRIPTEURS_LEVURES.length, 32);
    assert.equal(new Set(DESCRIPTEURS_LEVURES.map((d) => d.key)).size, 32);
    assert.deepEqual(DESCRIPTEURS_LEVURES[0], { key: "clean", label: "neutre" });
    assert.deepEqual(DESCRIPTEURS_LEVURES.at(-1), { key: "funky", label: "sauvage" });
    assert.ok(
      DESCRIPTEURS_LEVURES.some((d) => d.key === "diacetyl" && d.label === "beurre (diacétyle)"),
    );
  });
});

describe("levures : données envoyées", () => {
  it("champs de la section 2 seuls : ni notes, ni provenance", () => {
    const d = donneesEnvoyeesLevure(levure("culture-alpha", "Alpha").data);
    assert.deepEqual(d, {
      name: "Alpha",
      aliases: [],
      producer: "Labo Fictif",
      product_id: "LF1",
      type: "ale",
      form: "dry",
      attenuation_pct: [70, 80],
      temperature_c: [15, 22],
      flocculation: "medium",
    });
    assert.equal(JSON.stringify(d).includes("jamais"), false);
  });

  it("valeurs inconnues à null, plage sans bornes à null", () => {
    const d = donneesEnvoyeesLevure({ name: "Beta" });
    assert.deepEqual(d, {
      name: "Beta",
      aliases: [],
      producer: null,
      product_id: null,
      type: null,
      form: null,
      attenuation_pct: null,
      temperature_c: null,
      flocculation: null,
    });
  });
});

describe("levures : périmètre (décision 1 du 2026-11-21)", () => {
  it("types exclus : other, wine, champagne, malolactic", () => {
    assert.deepEqual(TYPES_HORS_PERIMETRE, ["other", "wine", "champagne", "malolactic"]);
  });

  it("923 retenues sur 960 : 37 hors périmètre, type absent inclus, levure du groupe gardée", () => {
    const elements = new Map();
    const types = ["ale", "lager", "wheat", "kveik", "brett", "lacto", "pedio"];
    const autres = ["mixed-culture", "bacteria", "spontaneous", undefined];
    const retenus = [...types, ...autres];
    for (let i = 0; i < 922; i++) {
      elements.set(`culture-r${String(i).padStart(3, "0")}`, {
        name: `R${i}`,
        ...(retenus[i % retenus.length] === undefined ? {} : { type: retenus[i % retenus.length] }),
      });
    }
    for (let i = 0; i < 38; i++) {
      elements.set(`culture-x${String(i).padStart(2, "0")}`, {
        name: `X${i}`,
        type: TYPES_HORS_PERIMETRE[i % 4],
      });
    }
    assert.equal(elements.size, 960);
    // Une levure de vin des recettes du groupe entre dans le périmètre.
    const { ids, hors } = perimetre(elements, new Set(["culture-x00"]), NATURE_LEVURE);
    assert.equal(ids.length, 923);
    assert.equal(hors.length, 37);
    assert.ok(ids.includes("culture-x00"));
    assert.equal(elements.get("culture-r010").type, undefined);
    assert.ok(ids.includes("culture-r010"), "type absent : inclus");
    assert.equal(
      hors.every((id) => TYPES_HORS_PERIMETRE.includes(elements.get(id).type)),
      true,
    );
  });
});

describe("levures : sortie du modèle", () => {
  it("bonne sortie : libellés recopiés, noms de styles recopiés, textes null écartés", () => {
    const { regles, resultat } = controlerSortieLevure(sortieModele(), CONTEXTE);
    assert.deepEqual(regles, []);
    assert.deepEqual(resultat, {
      status: "described",
      confidence: "medium",
      descriptors: [
        { key: "clean", label: "neutre" },
        { key: "fruity_esters", label: "esters fruités" },
      ],
      texts: { profile: { text: PROFIL }, warm: { text: CHAUD } },
      styles: [{ code: "bjcp2021-99a", name: "Style Fictif A" }],
    });
  });

  it("unknown sans texte ni style accepté", () => {
    const { regles, resultat } = controlerSortieLevure(
      {
        status: "unknown",
        confidence: null,
        descriptors: [],
        texts: { profile: null, cool: null, warm: null },
        styles: [],
      },
      CONTEXTE,
    );
    assert.deepEqual(regles, []);
    assert.deepEqual(resultat, { status: "unknown", descriptors: [], texts: {}, styles: [] });
  });

  it("refus : sans profile, texte non permis, style hors liste, 7 styles, unknown avec style", () => {
    const refus = (s) => controlerSortieLevure(s, CONTEXTE).regles;
    assert.ok(
      refus(sortieModele({ texts: { profile: null, cool: null, warm: CHAUD } })).includes(
        "texts.profile : obligatoire pour described",
      ),
    );
    assert.ok(
      refus(sortieModele({ texts: { profile: PROFIL, cool: null, warm: null, dry_hop: PROFIL } }))
        .length > 0,
    );
    assert.ok(
      refus(sortieModele({ styles: ["bjcp2021-21a"] })).includes(
        "styles[0] : hors de la liste fermée",
      ),
    );
    const grand = contexteStyles(
      Array.from({ length: 8 }, (_, i) => ({ id: `bjcp2021-9${i}a`, data: { name: `S${i}` } })),
    );
    assert.ok(
      controlerSortieLevure(
        sortieModele({ styles: Array.from({ length: 7 }, (_, i) => `bjcp2021-9${i}a`) }),
        grand,
      ).regles.includes("styles : 6 au plus"),
    );
    assert.ok(
      refus(sortieModele({ styles: ["bjcp2021-99a", "bjcp2021-99a"] })).includes(
        "styles[1].code : en double",
      ),
    );
    assert.ok(
      refus({
        status: "unknown",
        confidence: null,
        descriptors: [],
        texts: { profile: null, cool: null, warm: null },
        styles: ["bjcp2021-99a"],
      }).includes("styles : vide attendu pour unknown"),
    );
    assert.ok(refus(sortieModele({ descriptors: ["citrus_peel"] })).length > 0);
    assert.ok(refus(sortieModele({ uses: {} })).includes("sortie : clé non permise uses"));
  });

  it("textes refusés comme P55 ; une erreur ne recopie pas le texte", () => {
    const url = "Texte inventé avec une adresse www.exemple.fr pour le test, assez long ici.";
    const regles = controlerSortieLevure(
      sortieModele({ texts: { profile: url, cool: null, warm: "Trop court." } }),
      CONTEXTE,
    ).regles;
    assert.ok(regles.includes("texts.profile.text : adresse web"));
    assert.ok(regles.includes("texts.warm.text : longueur 40 à 400"));
    assert.equal(regles.join("\n").includes("exemple"), false);
    const prix = "Texte inventé : une levure à 4 € le sachet, ce qui est interdit ici.";
    assert.ok(
      controlerSortieLevure(sortieModele({ texts: { profile: prix } }), CONTEXTE).regles.some((r) =>
        r.includes("symbole monétaire"),
      ),
    );
  });
});

describe("levures : entrée de levures/aromes.json", () => {
  it("entrée bonne acceptée ; relue avec sa date acceptée", () => {
    assert.deepEqual(controlerEntreeAromeLevure(entree(), CONTEXTE), []);
    assert.deepEqual(
      controlerEntreeAromeLevure(
        entree("culture-alpha", { reviewed: true, reviewed_at: "2026-11-21" }),
        CONTEXTE,
      ),
      [],
    );
  });

  it("refus : style inconnu, nom de style différent, clé non permise, id de houblon", () => {
    assert.deepEqual(
      controlerEntreeAromeLevure(
        entree("culture-alpha", { styles: [{ code: "bjcp2021-21a", name: "Inconnu" }] }),
        CONTEXTE,
      ),
      ["styles[0].code : style absent de beer_styles.json"],
    );
    assert.deepEqual(
      controlerEntreeAromeLevure(
        entree("culture-alpha", { styles: [{ code: "bjcp2021-99a", name: "Autre nom" }] }),
        CONTEXTE,
      ),
      ["styles[0].name : différent du nom du style"],
    );
    assert.deepEqual(controlerEntreeAromeLevure(entree("culture-alpha", { uses: {} }), CONTEXTE), [
      "data : clé non permise uses",
    ]);
    assert.ok(
      controlerEntreeAromeLevure(entree("hop-alpha"), CONTEXTE).includes(
        "id : identifiant de levure attendu",
      ),
    );
    assert.ok(
      controlerEntreeAromeLevure(entree("culture-alpha", { reviewed: true }), CONTEXTE).includes(
        "reviewed_at : date AAAA-MM-JJ attendue pour une entrée relue",
      ),
    );
  });
});

describe("levures : requête et empreinte", () => {
  it("ni thinking, ni tools, ni tool_choice, ni message assistant ; styles en liste fermée", () => {
    const p = parametresRequeteLevure(donneesEnvoyeesLevure(levure("c", "Alpha").data), {
      effort: "medium",
      cache: true,
      contexte: CONTEXTE,
    });
    assert.equal(p.model, MODELE);
    assert.equal(p.max_tokens, 4000);
    for (const cle of ["thinking", "temperature", "tools", "tool_choice"]) {
      assert.equal(cle in p, false, cle);
    }
    assert.deepEqual(
      p.messages.map((m) => m.role),
      ["user"],
    );
    assert.equal(p.output_config.effort, "medium");
    const schema = p.output_config.format.schema;
    assert.deepEqual(schema.properties.styles.items.enum, ["bjcp2021-99a", "bjcp2021-99b"]);
    assert.deepEqual(Object.keys(schema.properties.texts.properties), ["profile", "cool", "warm"]);
    assert.equal(schema.properties.descriptors.items.enum.length, 32);
    assert.ok(p.system[0].text.startsWith(PROMPT_LEVURES));
    assert.ok(p.system[0].text.endsWith("- bjcp2021-99b : Style Fictif B"));
    assert.deepEqual(p.system[0].cache_control, { type: "ephemeral" });
    assert.equal(p.messages[0].content.includes("jamais"), false);
  });

  it("prompt : unknown pour une souche incertaine, aucun chiffre absent, styles de la liste", () => {
    assert.ok(PROMPT_LEVURES.includes('"status": "unknown"'));
    assert.ok(PROMPT_LEVURES.includes("plusieurs souches et que la référence (product_id) manque"));
    assert.ok(PROMPT_LEVURES.includes("N'écris aucun chiffre absent des données"));
    assert.ok(PROMPT_LEVURES.includes("codes pris dans la liste des styles ci-dessous"));
    assert.equal(PROMPT_VERSION_LEVURES, 1);
  });

  it("empreinte : change avec la liste des styles, l'effort et les données", () => {
    const d = donneesEnvoyeesLevure(levure("c", "Alpha").data);
    const base = empreinteEntreeLevure(d, {
      effort: "medium",
      stylesSha256: CONTEXTE.stylesSha256,
    });
    const autres = contexteStyles([STYLES[0]]);
    assert.notEqual(
      empreinteEntreeLevure(d, { effort: "medium", stylesSha256: autres.stylesSha256 }),
      base,
    );
    assert.notEqual(
      empreinteEntreeLevure(d, { effort: "low", stylesSha256: CONTEXTE.stylesSha256 }),
      base,
    );
    assert.notEqual(
      empreinteEntreeLevure(
        { ...d, product_id: "LF2" },
        { effort: "medium", stylesSha256: CONTEXTE.stylesSha256 },
      ),
      base,
    );
    // Même liste dans un autre ordre : même empreinte.
    assert.equal(contexteStyles([...STYLES].reverse()).stylesSha256, CONTEXTE.stylesSha256);
  });
});

describe("levures : options", () => {
  it("--nature hop par défaut, culture acceptée, autre refusée ; --regenerer au motif culture-", () => {
    assert.equal(lireOptionsAromes(["--essai"]).nature.cle, "hop");
    assert.equal(lireOptionsAromes(["--essai", "--nature", "culture"]).nature.cle, "culture");
    assert.throws(() => lireOptionsAromes(["--essai", "--nature", "malt"]), ErreurAromes);
    assert.throws(
      () => lireOptionsAromes(["--essai", "--nature", "culture", "--regenerer", "hop-alpha"]),
      /identifiant de levure attendu \(culture-…\)/,
    );
    assert.throws(
      () => lireOptionsAromes(["--essai", "--regenerer", "culture-alpha"]),
      /identifiant de houblon attendu \(hop-…\)/,
    );
  });
});

describe("levures : le SDK n'est pas chargé à l'import", () => {
  it("natures/culture.mjs et natures/hop.mjs s'importent sans lui", () => {
    const hook = fileURLToPath(new URL("./support/interdire-sdk.mjs", import.meta.url));
    const modules = ["../lib/aromes/natures/culture.mjs", "../lib/aromes/natures/hop.mjs"].map(
      (m) => new URL(m, import.meta.url).href,
    );
    const code = `for (const m of ${JSON.stringify(modules)}) await import(m); console.log("ok");`;
    const sortie = execFileSync(
      process.execPath,
      ["--import", hook, "--input-type=module", "-e", code],
      { encoding: "utf8" },
    );
    assert.equal(sortie.trim(), "ok");
  });
});

/// SDK simulé : compte les appels, rend [reponses] dans l'ordre.
function sdkSimule({ reponses = [], jetons = 1000 } = {}) {
  const appels = { charge: 0, count: 0, create: [], lots: [] };
  let n = 0;
  class Anthropic {
    constructor() {
      this.messages = {
        countTokens: async () => {
          appels.count++;
          return { input_tokens: jetons };
        },
        create: async (params) => {
          appels.create.push(params);
          return reponses[n++];
        },
        batches: {
          create: async (params) => {
            appels.lots.push(params);
            return { id: "msgbatch_levures01", processing_status: "in_progress" };
          },
          retrieve: async () => ({
            id: "msgbatch_levures01",
            processing_status: "ended",
            request_counts: { processing: 0, succeeded: 1, errored: 0, canceled: 0, expired: 0 },
          }),
          results: async () =>
            (async function* () {
              yield {
                custom_id: "c0001",
                result: { type: "succeeded", message: message(sortieModele()) },
              };
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
  date: "2026-11-15",
  source: "grille tarifaire d'Anthropic, relevée le 2026-11-15",
  usd_per_million_tokens: {
    input: 8,
    output: 40,
    cache_write: 10,
    cache_read: 0.8,
    batch_input: 4,
    batch_output: 20,
  },
};

describe("levures : génération (SDK simulé)", () => {
  let racine;
  let prepare;
  let aromes;
  let levures;
  let lignes;
  let confirmations;

  const lancer = (argv, sdk, { confirmer = true } = {}) =>
    genererAromes({
      argv: ["--nature", "culture", ...argv, "--dossier", prepare, "--aromes", aromes],
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

  const lireAromes = () => JSON.parse(readFileSync(join(levures, "aromes.json"), "utf8"));
  const ecrireGroupe = (nom, ids) =>
    writeFileSync(
      join(levures, nom),
      JSON.stringify({
        format: "kassbeer_levures_recettes",
        version: 1,
        resolus: ids.map((id) => ({ id, noms: [id] })),
        non_resolus: [
          { nom: "Belgian Ale", raison: "plusieurs", candidats: ["culture-a", "culture-b"] },
        ],
      }),
    );

  beforeEach(() => {
    racine = mkdtempSync(join(tmpdir(), "kassbeer-aromes-levures-"));
    prepare = join(racine, "prepare");
    aromes = join(racine, "aromes");
    levures = join(aromes, "levures");
    mkdirSync(prepare);
    mkdirSync(levures, { recursive: true });
    writeFileSync(
      join(prepare, "beer_cultures.json"),
      JSON.stringify([
        levure("culture-alpha", "Alpha"),
        levure("culture-beta", "Beta", { type: "lager" }),
        levure("culture-vin", "Vin", { type: "wine" }),
      ]),
    );
    writeFileSync(join(prepare, "beer_styles.json"), JSON.stringify(STYLES));
    // Tarif commun, à la racine de aromes/ (ADR-017, section 1).
    writeFileSync(join(aromes, "tarif.json"), JSON.stringify(TARIF));
    lignes = [];
    confirmations = 0;
  });
  afterEach(() => rmSync(racine, { recursive: true, force: true }));

  it("essai par --seulement : données envoyées seules, levures/aromes.json, poste du rapport", async () => {
    ecrireGroupe("levures-essai.json", ["culture-alpha"]);
    const sdk = sdkSimule({ reponses: [message(sortieModele())] });
    const cr = await lancer(["--essai", "--seulement", join(levures, "levures-essai.json")], sdk);
    assert.equal(cr.poste, "culture_aroma_generation");
    assert.equal(cr.prompt_version, 1);
    assert.equal(cr.generes, 1);
    const envoye = sdk.appels.create[0].messages[0].content;
    assert.equal(envoye.includes("jamais"), false, "ni notes ni provenance");
    assert.ok(envoye.startsWith("Levure :\n"));
    const [e] = lireAromes();
    assert.equal(e.id, "culture-alpha");
    assert.equal(e.data.culture_name, "Alpha");
    assert.deepEqual(e.data.styles, [{ code: "bjcp2021-99a", name: "Style Fictif A" }]);
    assert.equal(e.data.provenance[0].version, "claude-fable-5-2 / prompt 1 / effort medium");
    assert.deepEqual(controlerEntreeAromeLevure(e, CONTEXTE), []);
    // Fichiers des levures dans levures/ ; rien de levure à la racine des arômes.
    assert.ok(readdirSync(levures).includes("rapport.json"));
    assert.equal(readdirSync(aromes).includes("aromes.json"), false);
    for (const f of readdirSync(aromes, { recursive: true })) {
      if (!String(f).endsWith(".json")) continue;
      assert.equal(readFileSync(join(aromes, f), "utf8").includes(CLE), false, f);
    }
    assert.equal(lignes.join("\n").includes(CLE), false);
  });

  it("périmètre : la levure de vin n'est pas envoyée, sauf si elle est du groupe", async () => {
    const sdk = sdkSimule();
    const cr = await lancer(["--lot", "--budget-usd", "5"], sdk);
    assert.deepEqual(cr.perimetre, {
      retenus: 2,
      hors: 1,
      types_exclus: ["other", "wine", "champagne", "malolactic"],
    });
    const lot = JSON.parse(readFileSync(join(levures, "lot-msgbatch_levures01.json"), "utf8"));
    assert.equal(lot.nature, "culture");
    assert.deepEqual(
      sdk.appels.lots[0].requests.map((r) => r.custom_id),
      ["c0001", "c0002"],
    );
    assert.deepEqual(
      Object.values(lot.table).map((c) => [c.id, c.culture_name]),
      [
        ["culture-alpha", "Alpha"],
        ["culture-beta", "Beta"],
      ],
    );
    assert.ok(lignes.some((l) => l.startsWith("Périmètre : 2 levures sur 3, 1 hors périmètre")));

    // Levure de vin dans une recette du groupe : elle entre.
    rmSync(join(levures, "lot-msgbatch_levures01.json"));
    ecrireGroupe("levures-recettes.json", ["culture-vin"]);
    const sdk2 = sdkSimule();
    const cr2 = await lancer(["--lot", "--budget-usd", "5"], sdk2);
    assert.equal(cr2.perimetre.retenus, 3);
    assert.equal(sdk2.appels.lots[0].requests.length, 3);
  });

  it("--seulement ou --regenerer d'une levure hors périmètre : refusé sans appel", async () => {
    const sdk = sdkSimule();
    await assert.rejects(
      lancer(["--essai", "--regenerer", "culture-vin"], sdk),
      (e) => e instanceof ErreurAromes && /hors du périmètre/.test(e.message),
    );
    assert.equal(sdk.appels.charge, 0);
    assert.equal(confirmations, 0);
  });

  it("sans tarif commun : « Tarif inconnu », SDK non chargé", async () => {
    rmSync(join(aromes, "tarif.json"));
    const sdk = sdkSimule();
    await assert.rejects(lancer(["--essai"], sdk), (e) =>
      e.message.startsWith(MESSAGE_TARIF_INCONNU),
    );
    assert.equal(sdk.appels.charge, 0);
  });

  it("au-delà du budget : refus après comptage, sans confirmation ni envoi", async () => {
    const sdk = sdkSimule();
    await assert.rejects(
      lancer(["--lot", "--budget-usd", "0.1"], sdk),
      /au-delà du budget.*1 levures tiendraient/s,
    );
    assert.equal(sdk.appels.lots.length, 0);
    assert.equal(confirmations, 0);
  });

  it("--lot sans --budget-usd : refusé", async () => {
    await assert.rejects(lancer(["--lot"], sdkSimule()), /--budget-usd est obligatoire/);
  });

  it("refusal et max_tokens : comptés en erreur, sans second appel", async () => {
    const sdk = sdkSimule({
      reponses: [message({}, "refusal"), message(sortieModele(), "max_tokens")],
    });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(sdk.appels.create.length, 2);
    assert.deepEqual(cr.erreurs, [
      { id: "culture-alpha", raison: "refusal" },
      { id: "culture-beta", raison: "max_tokens" },
    ]);
  });

  it("sortie hors contrôle (style inconnu) : refusée au contrôle, rien écrit", async () => {
    const sdk = sdkSimule({
      reponses: [
        message(sortieModele({ styles: ["bjcp2021-21a"] })),
        message(sortieModele({ texts: { profile: null, cool: null, warm: CHAUD } })),
      ],
    });
    const cr = await lancer(["--essai"], sdk);
    assert.equal(cr.refus.length, 2);
    assert.deepEqual(lireAromes(), []);
  });

  it("une entrée relue n'est jamais remplacée", async () => {
    const relue = entree("culture-alpha", { reviewed: true, reviewed_at: "2026-11-21" });
    writeFileSync(join(levures, "aromes.json"), JSON.stringify([relue]));
    const sdk = sdkSimule({ reponses: [message(sortieModele({ confidence: "low" }))] });
    const cr = await lancer(["--essai", "--regenerer", "culture-alpha"], sdk);
    assert.deepEqual(cr.relues, [{ id: "culture-alpha", raison: "relue, non remplacée" }]);
    assert.deepEqual(
      lireAromes().find((e) => e.id === "culture-alpha"),
      relue,
    );
  });

  it("liste des styles changée : les levures sont « changées »", async () => {
    await lancer(
      ["--essai"],
      sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] }),
    );
    writeFileSync(
      join(prepare, "beer_styles.json"),
      JSON.stringify([
        ...STYLES,
        {
          id: "bjcp2021-99c",
          data: { name: "Style Fictif C" },
        },
      ]),
    );
    const cr = await lancer(["--essai"], sdkSimule({ reponses: [] }), { confirmer: false }).catch(
      (e) => e,
    );
    assert.ok(cr instanceof ErreurAromes, "envoi non confirmé");
    assert.ok(lignes.some((l) => l.includes("0 nouveaux, 2 changés, 0 inchangés")));
  });

  it("lot puis --suivre ; un lot de houblons n'est pas suivi en --nature culture", async () => {
    await lancer(["--lot", "--budget-usd", "5"], sdkSimule());
    const suivi = await lancer(["--suivre", "msgbatch_levures01"], sdkSimule());
    assert.equal(suivi.generes, 1);
    assert.equal(suivi.poste, "culture_aroma_generation");
    assert.deepEqual(
      lireAromes().map((e) => e.id),
      ["culture-alpha"],
    );
    writeFileSync(
      join(levures, "lot-msgbatch_houblons01.json"),
      JSON.stringify({ batch_id: "msgbatch_houblons01", table: {} }),
    );
    await assert.rejects(
      lancer(["--suivre", "msgbatch_houblons01"], sdkSimule()),
      /lot de nature hop, --nature culture demandée/,
    );
  });

  it("a-relire.md : levures du groupe, textes et styles, candidats d'un nom non résolu", async () => {
    ecrireGroupe("levures-recettes.json", ["culture-beta"]);
    await lancer(
      ["--essai"],
      sdkSimule({ reponses: [message(sortieModele()), message(sortieModele())] }),
    );
    const md = readFileSync(join(levures, "a-relire.md"), "utf8");
    assert.ok(md.includes("Levures des recettes du groupe (levures-recettes.json)"));
    assert.ok(md.includes("`culture-beta`"));
    assert.equal(md.includes("`culture-alpha`"), false);
    assert.ok(md.includes("- Profil : "));
    assert.ok(md.includes("- En haut de plage : "));
    assert.ok(md.includes("- Styles conseillés : Style Fictif A"));
    assert.ok(md.includes("atténuation 70 à 80 %"));
    assert.ok(md.includes("- Belgian Ale : plusieurs (culture-a, culture-b)"));
  });
});

describe("levures : tri par l'écrivain", () => {
  const ids = new Set(["culture-alpha", "culture-beta"]);

  it("refus : levure absente de beer_cultures.json, du groupe non relue, style inconnu", () => {
    const { valides, refuses } = trierAromes(
      [
        entree("culture-alpha"),
        entree("culture-beta", { culture_name: "Beta" }),
        entree("culture-gamma"),
        entree("culture-alpha", { styles: [{ code: "bjcp2021-21a", name: "Inconnu" }] }),
      ],
      ids,
      new Set(["culture-beta"]),
      NATURE_LEVURE,
      CONTEXTE,
    );
    assert.deepEqual(
      valides.map((v) => v.id),
      ["culture-alpha"],
    );
    assert.match(valides[0].data.content_sha256, /^[0-9a-f]{64}$/);
    assert.deepEqual(
      refuses.map((r) => [r.collection, r.id, r.erreurs]),
      [
        [
          "beer_culture_aromas",
          "culture-beta",
          ["reviewed : levure des recettes du groupe non relue"],
        ],
        ["beer_culture_aromas", "culture-gamma", ["id : levure absente de beer_cultures.json"]],
        [
          "beer_culture_aromas",
          "culture-alpha",
          ["styles[0].code : style absent de beer_styles.json", "id : en double"],
        ],
      ],
    );
  });

  it("entrées relues orphelines : relues et absentes du référentiel préparé, triées", () => {
    const relue = (id) => entree(id, { reviewed: true, reviewed_at: "2026-11-21" });
    assert.deepEqual(
      relueOrphelines(
        [
          relue("culture-zeta"),
          relue("culture-alpha"),
          entree("culture-gamma"),
          relue("culture-eta"),
        ],
        ids,
      ),
      ["culture-eta", "culture-zeta"],
    );
  });
});

describe("levures : liste du groupe en production", () => {
  it("liste d'émulateur ou de plus de 7 jours refusée, commande --nature culture donnée", () => {
    assert.throws(
      () =>
        controlerListeGroupe(
          { target: "emulator", generated_at: "2026-11-21T09:00:00.000Z" },
          MAINTENANT,
          NATURE_LEVURE,
        ),
      (e) =>
        e instanceof ErreurOptions &&
        e.message.startsWith("levures-recettes.json vient de la cible « emulator »") &&
        e.message.includes("lister-ingredients-recettes.mjs --nature culture"),
    );
    assert.throws(
      () =>
        controlerListeGroupe(
          { target: "production", generated_at: "2026-11-10T09:00:00.000Z" },
          MAINTENANT,
          NATURE_LEVURE,
        ),
      /plus de 7 jours/,
    );
    controlerListeGroupe(
      { target: "production", generated_at: "2026-11-20T09:00:00.000Z" },
      MAINTENANT,
      NATURE_LEVURE,
    );
  });
});

describe("levures : prompt documenté", () => {
  it("exigences-techniques.md recopie PROMPT_LEVURES à l'identique", () => {
    const doc = readFileSync(
      new URL("../../documentation/exigences-techniques.md", import.meta.url),
      "utf8",
    );
    const titre = `### Prompt des levures (\`prompt_version\` ${PROMPT_VERSION_LEVURES})`;
    const debut = doc.indexOf("```text\n", doc.indexOf(titre));
    assert.ok(doc.includes(titre) && debut > 0, "section du prompt des levures absente");
    const fin = doc.indexOf("\n```", debut + 8);
    assert.equal(doc.slice(debut + 8, fin), PROMPT_LEVURES);
  });
});
