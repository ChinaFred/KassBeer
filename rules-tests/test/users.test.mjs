// users/{uid}/** : prix, frais, stock et coût réel d'un brassin, privés à leur
// propriétaire (P5). Forme contrôlée pour prices, fees et brew_costs (v0.5, SE1, SE2).

import { beforeEach, describe, it } from "node:test";
import { db, seed, serverTimestamp, Timestamp } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const COMPUTED = Timestamp.fromDate(new Date("2026-11-12T18:30:00Z"));

/// Prix valide : 47,50 € pour 25 kg.
const price = (extra = {}) => ({
  name: "Pilsner",
  price_eur: 47.5,
  quantity: 25000,
  unit: "g",
  updated_at: serverTimestamp(),
  ...extra,
});

/// Frais valide.
const fee = (extra = {}) => ({
  name: "Électricité",
  amount_eur: 2,
  basis: "per_brew",
  updated_at: serverTimestamp(),
  ...extra,
});

const stock = (extra = {}) => ({
  name: "Pilsner",
  quantity: 12000,
  unit: "g",
  updated_at: serverTimestamp(),
  ...extra,
});

/// Coût figé valide du brassin [brewId].
const brewCost = (brewId, extra = {}) => ({
  brew_id: brewId,
  total_eur: 40.84,
  lines: [
    { key: "malt-pilsner", name: "Pilsner", quantity: 5000, unit: "g", cost_eur: 9.5 },
    { key: "levure-s-04", name: "S-04", quantity: 1, unit: "unit", cost_eur: 3.99 },
    { key: "fee-1", name: "Électricité", quantity: 1, unit: "brew", cost_eur: 2 },
    { key: "fee-2", name: "Capsules", quantity: 50, unit: "bottle", cost_eur: 1.5 },
  ],
  computed_at: COMPUTED,
  freeze_kind: "initial",
  bottles_count: 50,
  packaged_volume_l: 17,
  priming_sugar_g: 120,
  priming_sugar_name: "Saccharose",
  ...extra,
});

// Documents complets de brewer-a, semés après ceux de setup.mjs.
beforeEach(async () => {
  await seed(state.env, {
    "users/brewer-a/fees/f-1": { ...fee(), updated_at: COMPUTED },
    "users/brewer-a/brew_costs/b-a": brewCost("b-a"),
  });
});

// Ce que chacun des cinq profils obtient sur les données privées de brewer-a.
const ACCESS = {
  anonymous: false,
  nonMember: false,
  owner: true,
  otherBrewer: false,
  admin: false,
};

// Un document valide par chemin : seul l'accès est mis à l'épreuve. brew_costs/b-a
// existe déjà, donc l'écriture est une modification (« Recalculer »). Le troisième
// élément est une création sur un identifiant neuf (S1) : `allow create` est
// éprouvé à part de `allow update`.
const PATHS = {
  prices: [
    "users/brewer-a/prices/malt-pilsner",
    () => price(),
    ["users/brewer-a/prices/houblon-neuf", () => price({ name: "Neuf" })],
  ],
  fees: ["users/brewer-a/fees/f-1", () => fee(), ["users/brewer-a/fees/f-neuf", () => fee()]],
  stock: ["users/brewer-a/stock/malt-pilsner", () => stock(), null],
  brew_costs: [
    "users/brewer-a/brew_costs/b-a",
    () => brewCost("b-a", { freeze_kind: "recalculation" }),
    ["users/brewer-a/brew_costs/b-new", () => brewCost("b-new", { freeze_kind: "initial" })],
  ],
};

for (const [label, [path, valid, creation]] of Object.entries(PATHS)) {
  describe(`users/{uid}/${label} — cinq profils`, () => {
    const collection = path.split("/").slice(0, 3).join("/");
    for (const [name, allowed] of Object.entries(ACCESS)) {
      const verdict = allowed ? "autorisé" : "refusé";
      it(`${name} lit un document de brewer-a : ${verdict}`, async () => {
        await expectRule(allowed, db(state.env, name).doc(path).get());
      });
      it(`${name} liste la collection de brewer-a : ${verdict}`, async () => {
        await expectRule(allowed, db(state.env, name).collection(collection).get());
      });
      it(`${name} écrit un document valide chez brewer-a : ${verdict}`, async () => {
        await expectRule(allowed, db(state.env, name).doc(path).set(valid()));
      });
      it(`${name} supprime chez brewer-a : ${verdict}`, async () => {
        await expectRule(allowed, db(state.env, name).doc(path).delete());
      });
      if (creation) {
        const [newPath, newValid] = creation;
        it(`${name} crée un document neuf chez brewer-a : ${verdict}`, async () => {
          await expectRule(allowed, db(state.env, name).doc(newPath).set(newValid()));
        });
      }
    }
  });
}

describe("users/{uid} — propres données", () => {
  for (const [name, uid] of [
    ["otherBrewer", "brewer-b"],
    ["admin", "admin"],
  ]) {
    it(`${name} écrit ses propres prix : autorisé`, async () => {
      await expectRule(
        true,
        db(state.env, name)
          .doc(`users/${uid}/prices/houblon-saaz`)
          .set(price({ name: "Saaz", price_eur: 8, quantity: 100 })),
      );
    });
    it(`${name} écrit ses propres frais : autorisé`, async () => {
      await expectRule(true, db(state.env, name).doc(`users/${uid}/fees/f-9`).set(fee()));
    });
    it(`${name} fige le coût de son brassin : autorisé`, async () => {
      await expectRule(
        true,
        db(state.env, name).doc(`users/${uid}/brew_costs/b-9`).set(brewCost("b-9")),
      );
    });
  }

  it("non membre écrit un prix valide sous son propre uid : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "nonMember").doc("users/stranger/prices/malt-pils").set(price()),
    );
  });

  it("adresse non vérifiée écrit un prix valide sous son propre uid : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "unverified").doc("users/unverified/prices/malt-pils").set(price()),
    );
  });

  it("compte par mot de passe écrit un frais valide sous son uid : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "passwordProvider").doc("users/password/fees/f-1").set(fee()),
    );
  });

  it("une collection non nommée reste en lecture seule pour le propriétaire", async () => {
    await expectRule(
      false,
      db(state.env, "owner").doc("users/brewer-a/autre/x").set({ name: "x" }),
    );
  });
});

const owner = () => db(state.env, "owner");

describe("users/{uid}/prices — forme", () => {
  const write = (data, id = "malt-pils") => owner().doc(`users/brewer-a/prices/${id}`).set(data);

  const CASES = [
    ["prix valide", price(), true],
    ["prix nul (prix connu)", price({ price_eur: 0 }), true],
    ["prix de 100 000 €", price({ price_eur: 100000 }), true],
    ["levure au sachet", price({ name: "S-04", quantity: 5, unit: "unit" }), true],
    ["quantité de 1e9", price({ quantity: 1000000000 }), true],
    ["nom de 120 caractères", price({ name: "P".repeat(120) }), true],
    ["champ inconnu", price({ stock: 3 }), false],
    ["prix en texte", price({ price_eur: "47,5" }), false],
    ["prix négatif", price({ price_eur: -0.01 }), false],
    ["prix au-delà de 100 000 €", price({ price_eur: 100000.01 }), false],
    ["prix infini", price({ price_eur: Infinity }), false],
    ["prix NaN", price({ price_eur: NaN }), false],
    ["quantité nulle", price({ quantity: 0 }), false],
    ["quantité au-delà de 1e9", price({ quantity: 1000000001 }), false],
    ["unité kg", price({ unit: "kg" }), false],
    ["unité l (retirée)", price({ unit: "l" }), false],
    ["unité kwh (retirée)", price({ unit: "kwh" }), false],
    ["nom vide", price({ name: "" }), false],
    ["nom de 121 caractères", price({ name: "P".repeat(121) }), false],
    ["updated_at de l'appareil", price({ updated_at: COMPUTED }), false],
  ];
  for (const [label, data, allowed] of CASES) {
    it(`${label} : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(allowed, write(data));
    });
  }

  for (const field of ["name", "price_eur", "quantity", "unit", "updated_at"]) {
    it(`${field} absent : refusé`, async () => {
      const data = price();
      delete data[field];
      await expectRule(false, write(data));
    });
  }

  for (const [id, allowed] of [
    ["sucre-candi-ambre", true],
    ["houblon-saaz-10", true],
    ["levure", true],
    ["ajout-coriandre", true],
    ["Pils", false],
    ["malt_pils", false],
    ["pils", false],
    ["malt-", false],
    [`malt-${"a".repeat(95)}`, true],
    [`malt-${"a".repeat(96)}`, false],
  ]) {
    it(`identifiant « ${id.slice(0, 20)} » (${id.length}) : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(allowed, write(price(), id));
    });
  }

  it("remplacer un prix existant : accepté", async () => {
    await expectRule(true, write(price({ price_eur: 52 }), "malt-pilsner"));
  });
});

describe("users/{uid}/fees — forme", () => {
  const write = (data, id = "f-2") => owner().doc(`users/brewer-a/fees/${id}`).set(data);

  const CASES = [
    ["frais par brassin", fee(), true],
    ["frais par bouteille", fee({ name: "Capsules", amount_eur: 0.03, basis: "per_bottle" }), true],
    ["montant nul", fee({ amount_eur: 0 }), true],
    ["montant de 10 000 €", fee({ amount_eur: 10000 }), true],
    ["nom de 60 caractères", fee({ name: "F".repeat(60) }), true],
    ["champ inconnu", fee({ unit: "kwh" }), false],
    ["montant en texte", fee({ amount_eur: "2" }), false],
    ["montant négatif", fee({ amount_eur: -1 }), false],
    ["montant au-delà de 10 000 €", fee({ amount_eur: 10000.01 }), false],
    ["base inconnue", fee({ basis: "per_litre" }), false],
    ["nom vide", fee({ name: "" }), false],
    ["nom de 61 caractères", fee({ name: "F".repeat(61) }), false],
    ["updated_at de l'appareil", fee({ updated_at: COMPUTED }), false],
  ];
  for (const [label, data, allowed] of CASES) {
    it(`${label} : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(allowed, write(data));
    });
  }

  for (const field of ["name", "amount_eur", "basis", "updated_at"]) {
    it(`${field} absent : refusé`, async () => {
      const data = fee();
      delete data[field];
      await expectRule(false, write(data));
    });
  }

  it(`identifiant de 129 caractères : refusé`, async () => {
    await expectRule(false, write(fee(), "f".repeat(129)));
  });
});

describe("users/{uid}/brew_costs — figeage et forme", () => {
  const ref = (id) => owner().doc(`users/brewer-a/brew_costs/${id}`);

  it("premier figeage (initial) en création : accepté", async () => {
    await expectRule(true, ref("b-new").set(brewCost("b-new")));
  });

  it("recalculation en création : refusé", async () => {
    await expectRule(false, ref("b-new").set(brewCost("b-new", { freeze_kind: "recalculation" })));
  });

  it("recalculation sur un coût figé : accepté", async () => {
    await expectRule(true, ref("b-a").set(brewCost("b-a", { freeze_kind: "recalculation" })));
  });

  it("initial sur un coût figé (second appareil, rejeu) : refusé", async () => {
    await expectRule(false, ref("b-a").set(brewCost("b-a", { total_eur: 12 })));
  });

  it("brassin et coût supprimés dans un même lot : accepté", async () => {
    const fs = owner();
    const batch = fs.batch();
    batch.delete(fs.doc("brews/b-a"));
    batch.delete(fs.doc("users/brewer-a/brew_costs/b-a"));
    await expectRule(true, batch.commit());
  });

  const CASES = [
    [
      "sans valeur d'embouteillage",
      (() => {
        const d = brewCost("b-new");
        for (const k of [
          "bottles_count",
          "packaged_volume_l",
          "priming_sugar_g",
          "priming_sugar_name",
        ]) {
          delete d[k];
        }
        return d;
      })(),
      true,
    ],
    [
      "valeurs d'embouteillage nulles",
      brewCost("b-new", {
        bottles_count: null,
        packaged_volume_l: null,
        priming_sugar_g: null,
        priming_sugar_name: null,
      }),
      true,
    ],
    ["total nul", brewCost("b-new", { total_eur: 0 }), true],
    [
      "200 lignes",
      brewCost("b-new", { lines: Array.from({ length: 200 }, () => ({ key: "k" })) }),
      true,
    ],
    [
      "201 lignes",
      brewCost("b-new", { lines: Array.from({ length: 201 }, () => ({ key: "k" })) }),
      false,
    ],
    ["brew_id différent du chemin", brewCost("b-autre"), false],
    ["champ inconnu", brewCost("b-new", { recipe_id: "r-a" }), false],
    ["total négatif", brewCost("b-new", { total_eur: -0.01 }), false],
    ["total en texte", brewCost("b-new", { total_eur: "40,84" }), false],
    ["total infini", brewCost("b-new", { total_eur: Infinity }), false],
    ["lines n'est pas une liste", brewCost("b-new", { lines: { a: 1 } }), false],
    ["computed_at en texte", brewCost("b-new", { computed_at: "2026-11-12" }), false],
    ["freeze_kind inconnu", brewCost("b-new", { freeze_kind: "manual" }), false],
    ["0 bouteille", brewCost("b-new", { bottles_count: 0 }), false],
    ["1,5 bouteille", brewCost("b-new", { bottles_count: 1.5 }), false],
    ["10 000 bouteilles", brewCost("b-new", { bottles_count: 10000 }), false],
    ["volume conditionné nul", brewCost("b-new", { packaged_volume_l: 0 }), false],
    ["sucre de resucrage négatif", brewCost("b-new", { priming_sugar_g: -1 }), false],
    [
      "nature du sucre de 81 caractères",
      brewCost("b-new", { priming_sugar_name: "S".repeat(81) }),
      false,
    ],
  ];
  for (const [label, data, allowed] of CASES) {
    it(`${label} : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(allowed, ref("b-new").set(data));
    });
  }

  for (const field of ["brew_id", "total_eur", "lines", "computed_at", "freeze_kind"]) {
    it(`${field} absent : refusé`, async () => {
      const data = brewCost("b-new");
      delete data[field];
      await expectRule(false, ref("b-new").set(data));
    });
  }
});

describe("users/{uid}/stock — sans contrôle de forme jusqu'à son arrivée", () => {
  it("le propriétaire écrit un document libre : autorisé", async () => {
    await expectRule(
      true,
      owner().doc("users/brewer-a/stock/malt-pilsner").set({ name: "x", note: 3 }),
    );
  });
});
