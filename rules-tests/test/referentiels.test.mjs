// Référentiels, recettes publiques et comptes rendus de l'ingestion (ADR-005, P19) :
// écrits par aucun client, lus par les membres (ingest_runs et import_unresolved : par
// l'admin). Cinq profils de P4, plus les connexions non conformes de P11.

import { beforeEach, describe, it } from "node:test";
import { db, FIVE_PROFILES, seed, serverTimestamp } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const PROVENANCE = [
  {
    source: "brewtarget-005",
    source_id: "Nom Fictif",
    version: "v5.2.3 ea10908",
    licence: "CC BY-SA 4.0",
    retrieved: "2026-11-08",
  },
];

/// Un document par collection, semé hors règles comme le ferait ingest/.
const DOCS = {
  "beer_fermentables/fermentable-malt-fictif": {
    name: "Malt Fictif",
    aliases: [],
    type: "grain",
    color: { value: 4, unit: "EBC" },
    provenance: PROVENANCE,
    content_sha256: "a".repeat(64),
  },
  "beer_hops/hop-houblon-fictif": {
    name: "Houblon Fictif",
    aliases: [],
    alpha_acid: { value: 7, unit: "%" },
    provenance: PROVENANCE,
    content_sha256: "b".repeat(64),
  },
  "beer_cultures/culture-labo-fictif-lf1-levure-fictive": {
    name: "Levure Fictive",
    aliases: [],
    type: "ale",
    provenance: PROVENANCE,
    content_sha256: "c".repeat(64),
  },
  "beer_miscs/misc-epice-fictive": {
    name: "Épice Fictive",
    aliases: [],
    type: "spice",
    provenance: PROVENANCE,
    content_sha256: "d".repeat(64),
  },
  "beer_styles/bjcp2021-99a": {
    name: "Style Fictif",
    style_id: "99A",
    provenance: PROVENANCE,
    content_sha256: "e".repeat(64),
  },
  "beer_index/hops": {
    count: 1,
    entries: [{ id: "hop-houblon-fictif", name: "Houblon Fictif", alpha: 7 }],
    content_sha256: "f".repeat(64),
  },
  "public_recipes/diydog-1": {
    format_version: 1,
    owner_uid: "system",
    owner_name: "DIY Dog",
    imported_from: "DIY Dog · diydog-1",
    search_name: "biere fictive",
    recipe: { name: "Bière Fictive", ingredients: {} },
    ingredient_refs: {},
    source_hop_timing: [],
    announced: {},
    provenance: PROVENANCE,
    content_sha256: "0".repeat(64),
  },
  "ingest_runs/20261111T100000Z": {
    target: "emulator",
    counts: {},
    sources: [],
    unresolved: { fermentable: 0, hop: 0, culture: 0, misc: 0 },
    report_sha256: "1".repeat(64),
  },
  [`import_unresolved/${"2".repeat(64)}`]: {
    nature: "fermentable",
    name: "Malt Inconnu",
    source: "diydog",
    count: 3,
  },
};

const LUS_PAR_LES_MEMBRES = [
  "beer_fermentables",
  "beer_hops",
  "beer_cultures",
  "beer_miscs",
  "beer_styles",
  "beer_index",
  "public_recipes",
];
const LUS_PAR_L_ADMIN = ["ingest_runs", "import_unresolved"];

const MEMBRES = ["owner", "otherBrewer", "admin"];

/// Chemin du document semé de [collection].
const cheminDe = (collection) => Object.keys(DOCS).find((p) => p.startsWith(`${collection}/`));

beforeEach(async () => {
  await seed(state.env, DOCS);
});

describe("référentiels et recettes publiques : lecture par les membres", () => {
  for (const collection of LUS_PAR_LES_MEMBRES) {
    for (const profil of FIVE_PROFILES) {
      const permis = MEMBRES.includes(profil);
      it(`${collection} : ${profil} ${permis ? "lit" : "ne lit pas"} un document (get)`, async () => {
        const fs = db(state.env, profil);
        await expectRule(permis, fs.doc(cheminDe(collection)).get());
      });
    }
  }

  for (const collection of LUS_PAR_LES_MEMBRES.filter((c) => c !== "public_recipes")) {
    for (const profil of FIVE_PROFILES) {
      it(`${collection} : ${profil} ne liste pas (get seul)`, async () => {
        const fs = db(state.env, profil);
        await expectRule(false, fs.collection(collection).limit(50).get());
        await expectRule(false, fs.collection(collection).get());
      });
    }
  }

  for (const profil of FIVE_PROFILES) {
    const permis = MEMBRES.includes(profil);
    it(`public_recipes : ${profil} ${permis ? "lit" : "ne lit pas"} une page de 50 au plus`, async () => {
      const fs = db(state.env, profil);
      await expectRule(permis, fs.collection("public_recipes").limit(50).get());
      await expectRule(permis, fs.collection("public_recipes").limit(1).get());
      await expectRule(false, fs.collection("public_recipes").limit(51).get());
      await expectRule(false, fs.collection("public_recipes").get());
    });
  }

  it("public_recipes : recherche par préfixe de search_name, page de 50", async () => {
    const fs = db(state.env, "owner");
    const q = "biere";
    await expectRule(
      true,
      fs
        .collection("public_recipes")
        .orderBy("search_name")
        .where("search_name", ">=", q)
        .where("search_name", "<", `${q}\uf8ff`)
        .limit(50)
        .get(),
    );
    await expectRule(
      false,
      fs
        .collection("public_recipes")
        .orderBy("search_name")
        .where("search_name", ">=", q)
        .where("search_name", "<", `${q}\uf8ff`)
        .get(),
    );
  });

  for (const profil of ["unverified", "passwordProvider"]) {
    it(`connexion non conforme (${profil}) : aucune lecture (P11)`, async () => {
      const fs = db(state.env, profil);
      await expectRule(false, fs.doc(cheminDe("beer_hops")).get());
      await expectRule(false, fs.collection("public_recipes").limit(50).get());
    });
  }
});

describe("ingest_runs et import_unresolved : lecture par l'admin seul", () => {
  for (const collection of LUS_PAR_L_ADMIN) {
    for (const profil of FIVE_PROFILES) {
      const permis = profil === "admin";
      it(`${collection} : ${profil} ${permis ? "lit" : "ne lit pas"}`, async () => {
        const fs = db(state.env, profil);
        await expectRule(permis, fs.doc(cheminDe(collection)).get());
        await expectRule(permis, fs.collection(collection).get());
      });
    }
  }
});

describe("aucune écriture d'un client, admin compris", () => {
  for (const collection of [...LUS_PAR_LES_MEMBRES, ...LUS_PAR_L_ADMIN]) {
    for (const profil of FIVE_PROFILES) {
      it(`${collection} : ${profil} ne crée, ne modifie ni ne supprime`, async () => {
        const fs = db(state.env, profil);
        const chemin = cheminDe(collection);
        await expectRule(
          false,
          fs
            .doc(`${collection}/nouveau-${profil}`)
            .set({ ...DOCS[chemin], updated_at: serverTimestamp() }),
        );
        await expectRule(false, fs.doc(chemin).update({ name: "Modifié" }));
        await expectRule(false, fs.doc(chemin).delete());
      });
    }
  }
});
