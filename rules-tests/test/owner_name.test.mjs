// owner_name de recipes/, equipment/ (A1) et brews/ (v0.3) : facultatif ; présent, c'est
// le nom du jeton de celui qui écrit, de 1 à 80 caractères. Valeurs des listes du modèle (A5).

import { describe, it } from "node:test";
import {
  brew,
  db,
  deleteField,
  equipment,
  fresh,
  nameOf,
  recipe,
  seed,
  serverTimestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));

// Création à son nom, avec son propre owner_name, pour les cinq profils de P4.
const CREATE_WITH_NAME = {
  anonymous: false,
  nonMember: false,
  owner: true,
  otherBrewer: true,
  admin: true,
};

// Écriture de son propre nom dans le document de brewer-a.
const UPDATE_A_WITH_NAME = {
  anonymous: false,
  nonMember: false,
  owner: true,
  otherBrewer: false,
  admin: false,
};

const COLLECTIONS = {
  recipes: { existing: "r-a", make: recipe },
  equipment: { existing: "e-a", make: equipment },
  brews: { existing: "b-a", make: brew },
};

for (const [collection, { existing, make }] of Object.entries(COLLECTIONS)) {
  const create = (persona, extra) =>
    db(state.env, persona)
      .doc(`${collection}/nouveau`)
      .set(fresh(make(ownerFor(persona), extra)));

  const update = (persona, extra) =>
    db(state.env, persona)
      .doc(`${collection}/${existing}`)
      .update({ ...extra, updated_at: serverTimestamp() });

  describe(`${collection} — owner_name, cinq profils`, () => {
    for (const [name, allowed] of Object.entries(CREATE_WITH_NAME)) {
      it(`${name} crée avec son nom : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(allowed, create(name, { owner_name: nameOf(name) ?? "Anonyme" }));
      });
    }

    for (const [name, allowed] of Object.entries(UPDATE_A_WITH_NAME)) {
      it(`${name} écrit son nom dans le document de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(allowed, update(name, { owner_name: nameOf(name) ?? "Anonyme" }));
      });
    }
  });

  describe(`${collection} — owner_name, forme`, () => {
    it("nom absent : autorisé", async () => {
      await expectRule(true, create("owner", {}));
    });

    it("nom d'un autre brasseur à la création : refusé", async () => {
      await expectRule(false, create("owner", { owner_name: nameOf("otherBrewer") }));
    });

    it("nom d'un autre brasseur à la modification : refusé", async () => {
      await expectRule(false, update("owner", { owner_name: nameOf("otherBrewer") }));
    });

    it("nom de 80 caractères égal au jeton : autorisé", async () => {
      await expectRule(true, create("maxName", { owner_name: nameOf("maxName") }));
    });

    it("nom de 81 caractères égal au jeton : refusé", async () => {
      await expectRule(false, create("longName", { owner_name: nameOf("longName") }));
    });

    it("nom vide égal au jeton : refusé", async () => {
      await expectRule(false, create("emptyName", { owner_name: "" }));
    });

    it("nom non textuel égal au jeton (42) : refusé", async () => {
      await expectRule(false, create("numericName", { owner_name: 42 }));
    });

    it("nom non textuel : refusé", async () => {
      await expectRule(false, create("owner", { owner_name: 42 }));
    });

    it("nom null : refusé", async () => {
      await expectRule(false, create("owner", { owner_name: null }));
    });

    it("jeton sans nom, owner_name présent : refusé", async () => {
      await expectRule(false, create("noName", { owner_name: "Brasseur sans nom" }));
    });

    it("jeton sans nom, owner_name absent : autorisé", async () => {
      await expectRule(true, create("noName", {}));
    });

    it("modification qui garde un ancien nom, différent du jeton : refusé", async () => {
      await seed(state.env, {
        [`${collection}/${existing}`]: make(uidOf("owner"), { owner_name: "Ancien nom" }),
      });
      await expectRule(false, update("owner", { notes: "révision" }));
    });

    it("modification qui réécrit le nom actuel : autorisé", async () => {
      await seed(state.env, {
        [`${collection}/${existing}`]: make(uidOf("owner"), { owner_name: "Ancien nom" }),
      });
      await expectRule(true, update("owner", { owner_name: nameOf("owner") }));
    });

    it("modification qui retire le nom : autorisé", async () => {
      await seed(state.env, {
        [`${collection}/${existing}`]: make(uidOf("owner"), { owner_name: "Ancien nom" }),
      });
      await expectRule(true, update("owner", { owner_name: deleteField() }));
    });
  });
}

describe("recipes — valeurs des listes (A5)", () => {
  const a5 = {
    fermentables: [
      { key: "malt-pils", name: "Pils", kind: "grain", weight_g: 5000, ebc: 3.9, yield_pct: 80 },
      { key: "sucre-candi", name: "Candi", kind: "sugar", weight_g: 500, ebc: 2, yield_pct: 100 },
    ],
    hops: [
      {
        key: "houblon-magnum",
        name: "Magnum",
        weight_g: 30,
        alpha_pct: 10,
        use: "boil",
        time_min: 60,
        form: "pellet",
      },
      {
        key: "houblon-citra",
        name: "Citra",
        weight_g: 50,
        use: "whirlpool",
        time_min: 15,
        form: "leaf",
      },
      {
        key: "houblon-citra",
        name: "Citra",
        weight_g: 50,
        use: "dry_hop",
        time_min: 4320,
        form: "pellet",
      },
    ],
    others: ["mash", "boil", "after_boil", "fermentation", "bottling"].map((use, i) => ({
      key: `ajout-${i}`,
      name: `Ajout ${i}`,
      weight_g: 10,
      use,
      time_min: 5,
    })),
    yeasts: [{ key: "levure-us-05", name: "US-05", attenuation_pct: 78, form: "dry" }],
  };

  it("recette aux valeurs A5 : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/nouveau")
        .set(fresh(recipe(uidOf("owner"), { ...a5, owner_name: nameOf("owner") }))),
    );
  });

  // Les règles n'inspectent pas les éléments des listes : une valeur retirée du
  // modèle (extract, first_wort) passe les règles. Le dépôt de données et brewing/
  // (FermentableKind.fromStored, HopUse.fromStored) la refusent.
  it("valeur retirée du modèle dans une liste : acceptée par les règles", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/nouveau")
        .set(
          fresh(
            recipe(uidOf("owner"), {
              fermentables: [{ key: "malt-x", name: "X", kind: "extract", weight_g: 1 }],
              hops: [{ key: "houblon-x", name: "X", weight_g: 1, use: "first_wort" }],
            }),
          ),
        ),
    );
  });
});

describe("brews — copie d'une recette qui porte owner_name", () => {
  it("brasser la recette d'un autre, copie avec le nom de son auteur : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "otherBrewer")
        .doc("brews/nouveau")
        .set(
          fresh(
            brew(uidOf("otherBrewer"), {
              recipe_snapshot: recipe(uidOf("owner"), { owner_name: nameOf("owner") }),
              equipment_snapshot: equipment(uidOf("owner"), { owner_name: nameOf("owner") }),
            }),
          ),
        ),
    );
  });
});

describe("brews — owner_name d'une copie borné en type et en taille", () => {
  for (const [label, value] of [
    ["nombre", 42],
    ["81 caractères", "x".repeat(81)],
    ["chaîne vide", ""],
  ]) {
    for (const snapshot of ["recipe_snapshot", "equipment_snapshot"]) {
      it(`${snapshot}.owner_name ${label} : refusé`, async () => {
        const base =
          snapshot === "recipe_snapshot"
            ? recipe(uidOf("owner"), { owner_name: value })
            : equipment(uidOf("owner"), { owner_name: value });
        await expectRule(
          false,
          db(state.env, "owner")
            .doc("brews/borne")
            .set(fresh(brew(uidOf("owner"), { [snapshot]: base }))),
        );
      });
    }
  }
});
