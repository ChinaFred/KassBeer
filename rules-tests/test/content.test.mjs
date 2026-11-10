// recipes/, equipment/, brews/ : lus par le groupe, écrits par leur propriétaire (P4, P5).

import { describe, it } from "node:test";
import { brew, db, equipment, fresh, recipe, serverTimestamp, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

// Ce que chacun des cinq profils obtient sur un document de brewer-a.
const READ = { anonymous: false, nonMember: false, owner: true, otherBrewer: true, admin: true };
const CREATE_OWN = {
  anonymous: false,
  nonMember: false,
  owner: true,
  otherBrewer: true,
  admin: true,
};
const WRITE_A = {
  anonymous: false,
  nonMember: false,
  owner: true,
  otherBrewer: false,
  admin: false,
};

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));

// named : document de [owner] dont le nom vaut [name] (dans `recipe` pour une recette).
const COLLECTIONS = {
  recipes: {
    existing: "r-a",
    make: recipe,
    edit: { "recipe.name": "Blonde révisée" },
    named: (owner, name) => recipe(owner, {}, { name }),
  },
  equipment: {
    existing: "e-a",
    make: equipment,
    edit: { mash_efficiency_pct: 75 },
    named: (owner, name) => equipment(owner, { name }),
  },
  brews: {
    existing: "b-a",
    make: brew,
    edit: { status: "brewing" },
    named: (owner, name) => brew(owner, { name }),
  },
};

for (const [collection, { existing, make, edit, named }] of Object.entries(COLLECTIONS)) {
  describe(`${collection} — cinq profils`, () => {
    for (const [name, allowed] of Object.entries(READ)) {
      it(`${name} lit un document : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(allowed, db(state.env, name).doc(`${collection}/${existing}`).get());
      });
      it(`${name} liste la collection : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(allowed, db(state.env, name).collection(collection).get());
      });
    }

    for (const [name, allowed] of Object.entries(CREATE_OWN)) {
      it(`${name} crée un document à son nom : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(
          allowed,
          db(state.env, name)
            .doc(`${collection}/nouveau`)
            .set(fresh(make(ownerFor(name)))),
        );
      });
    }

    for (const [name, allowed] of Object.entries(WRITE_A)) {
      it(`${name} modifie le document de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(
          allowed,
          db(state.env, name)
            .doc(`${collection}/${existing}`)
            .update({ ...edit, updated_at: serverTimestamp() }),
        );
      });
      it(`${name} supprime le document de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(allowed, db(state.env, name).doc(`${collection}/${existing}`).delete());
      });
    }
  });

  describe(`${collection} — propriétaire et forme`, () => {
    it("créer au nom d'un autre brasseur : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "otherBrewer")
          .doc(`${collection}/nouveau`)
          .set(fresh(make(uidOf("owner")))),
      );
    });

    it("changer owner_uid : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${collection}/${existing}`)
          .update({ owner_uid: uidOf("otherBrewer"), updated_at: serverTimestamp() }),
      );
    });

    it("champ prix hors liste : refusé (P5)", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${collection}/nouveau`)
          .set(fresh(make(uidOf("owner"), { price_eur: 12 }))),
      );
    });

    it("created_at posée par le client : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${collection}/nouveau`)
          .set({ ...fresh(make(uidOf("owner"))), created_at: new Date() }),
      );
    });

    it("modifier sans poser updated_at : refusé", async () => {
      await expectRule(false, db(state.env, "owner").doc(`${collection}/${existing}`).update(edit));
    });

    it("changer created_at : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${collection}/${existing}`)
          .update({ created_at: new Date(), updated_at: serverTimestamp() }),
      );
    });

    it("nom vide : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${collection}/nouveau`)
          .set(fresh(named(uidOf("owner"), ""))),
      );
    });

    it("nom de 120 caractères : autorisé", async () => {
      await expectRule(
        true,
        db(state.env, "owner")
          .doc(`${collection}/nouveau`)
          .set(fresh(named(uidOf("owner"), "N".repeat(120)))),
      );
    });

    it("nom de 121 caractères : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${collection}/nouveau`)
          .set(fresh(named(uidOf("owner"), "N".repeat(121)))),
      );
    });
  });
}

describe("recipes — forme", () => {
  it("quantité en texte : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/nouveau")
        .set(fresh(recipe(uidOf("owner"), {}, { batch_size: { value: "20", unit: "l" } }))),
    );
  });
});

describe("equipment — forme", () => {
  it("type d'équipement inconnu : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("equipment/nouveau")
        .set(fresh(equipment(uidOf("owner"), { kind: "fusee" }))),
    );
  });
});

describe("brews — recette figée", () => {
  it("modifier recipe_snapshot : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ "recipe_snapshot.recipe.name": "Autre", updated_at: serverTimestamp() }),
    );
  });

  it("modifier equipment_snapshot : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ "equipment_snapshot.mash_efficiency_pct": 90, updated_at: serverTimestamp() }),
    );
  });

  it("changer recipe_id : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ recipe_id: "r-b", updated_at: serverTimestamp() }),
    );
  });

  it("noter un ajustement du jour dans le brassin : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ adjustments: { boil_time_min: 75 }, updated_at: serverTimestamp() }),
    );
  });

  it("ajustement du jour en liste blanche (volume, rendement) : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({
          adjustments: { pre_boil_volume_l: 27.5, mash_efficiency_pct: 71 },
          updated_at: serverTimestamp(),
        }),
    );
  });

  for (const [value, allowed] of [
    [150, false],
    [-1, false],
    [100, true],
  ]) {
    it(`adjustments.mash_efficiency_pct = ${value} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("brews/b-a")
          .update({ adjustments: { mash_efficiency_pct: value }, updated_at: serverTimestamp() }),
      );
    });
  }

  it("coût dans les ajustements (adjustments.cost_eur) : refusé (P5)", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ adjustments: { cost_eur: 12 }, updated_at: serverTimestamp() }),
    );
  });

  it("ajustement non numérique : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ adjustments: { boil_time_min: "75" }, updated_at: serverTimestamp() }),
    );
  });

  it("prix dans la copie de la recette : refusé (P5)", async () => {
    const data = brew(uidOf("owner"));
    data.recipe_snapshot = { ...data.recipe_snapshot, price_eur: 30 };
    await expectRule(false, db(state.env, "owner").doc("brews/nouveau").set(fresh(data)));
  });

  it("coût dans la copie de l'équipement : refusé (P5)", async () => {
    const data = brew(uidOf("owner"));
    data.equipment_snapshot = { ...data.equipment_snapshot, cost_eur: 400 };
    await expectRule(false, db(state.env, "owner").doc("brews/nouveau").set(fresh(data)));
  });

  it("coût au premier niveau du brassin : refusé (P5)", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/nouveau")
        .set(fresh(brew(uidOf("owner"), { total_cost_eur: 31 }))),
    );
  });

  it("statut inconnu : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ status: "bue", updated_at: serverTimestamp() }),
    );
  });

  it("brasser la recette d'un autre brasseur, à son nom : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "otherBrewer")
        .doc("brews/nouveau")
        .set(fresh(brew(uidOf("otherBrewer")))),
    );
  });
});
