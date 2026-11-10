// owner_name de recipes/, equipment/ (A1) et brews/ (v0.3) : facultatif ; présent, c'est
// le nom du jeton de celui qui écrit, de 1 à 80 caractères. Valeurs des listes du modèle (BeerJSON).

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

describe("recipes — valeurs des listes (BeerJSON, ADR-005)", () => {
  const g = (value) => ({ value, unit: "g" });
  const min = (value) => ({ value, unit: "min" });
  const ingredients = {
    fermentable_additions: [
      {
        name: "Pils",
        type: "grain",
        amount: g(5000),
        color: { value: 3.9, unit: "EBC" },
        yield: { fine_grind: { value: 80, unit: "%" } },
      },
      { name: "Candi", type: "sugar", amount: g(500) },
    ],
    hop_additions: [
      {
        name: "Magnum",
        form: "pellet",
        alpha_acid: { value: 10, unit: "%" },
        amount: g(30),
        timing: { use: "add_to_boil", time: min(60) },
      },
      {
        name: "Citra",
        form: "leaf",
        amount: g(50),
        timing: { use: "add_to_boil", time: min(0), duration: min(15) },
      },
      {
        name: "Citra",
        form: "pellet",
        amount: g(50),
        timing: { use: "add_to_fermentation", duration: min(4320) },
      },
    ],
    miscellaneous_additions: [
      ["add_to_mash", { duration: min(5) }],
      ["add_to_boil", { time: min(5) }],
      ["add_to_boil", { time: min(0), duration: min(5) }],
      ["add_to_fermentation", { duration: min(5) }],
      ["add_to_package", { duration: min(5) }],
    ].map(([use, times], i) => ({
      name: `Ajout ${i}`,
      type: "spice",
      amount: g(10),
      timing: { use, ...times },
    })),
    culture_additions: [
      {
        name: "US-05",
        type: "ale",
        form: "dry",
        attenuation: { value: 78, unit: "%" },
        amount: g(11.5),
      },
    ],
  };

  it("recette aux moments et valeurs de l'éditeur : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/nouveau")
        .set(fresh(recipe(uidOf("owner"), { owner_name: nameOf("owner") }, { ingredients }))),
    );
  });

  // Les règles n'inspectent pas les éléments des listes : une valeur que l'application
  // ne lit pas (extrait, houblon à l'empâtage) passe les règles. Le dépôt de données la
  // refuse (FermentableKind.fromStored, lecture de `timing`).
  it("valeur inconnue de l'application dans une liste : acceptée par les règles", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/nouveau")
        .set(
          fresh(
            recipe(
              uidOf("owner"),
              {},
              {
                ingredients: {
                  fermentable_additions: [{ name: "X", type: "extract", amount: g(1) }],
                  hop_additions: [
                    { name: "X", form: "pellet", amount: g(1), timing: { use: "add_to_mash" } },
                  ],
                },
              },
            ),
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
