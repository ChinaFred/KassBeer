// v0.1.15 — recettes en BeerJSON partiel (ADR-005) : enveloppe, format_version, sous-arbre
// `recipe`, unités canoniques, plafonds des listes. Mêmes contrôles sur la copie figée
// d'un brassin, qui reste immuable (P4, cinq profils).

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  beerRecipe,
  brew,
  brewSteps,
  CREATED,
  db,
  deleteField,
  equipment,
  FIVE_PROFILES,
  flatRecipe,
  fresh,
  nameOf,
  recipe,
  seed,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));
const isMemberProfile = (name) => ["owner", "otherBrewer", "admin"].includes(name);

const n = (count, make) => Array.from({ length: count }, (_, i) => make(i));
const fermentable = (i) => ({ name: `Malt ${i}`, type: "grain", amount: { value: 1, unit: "g" } });
const hop = (i) => ({
  name: `Houblon ${i}`,
  form: "pellet",
  amount: { value: 1, unit: "g" },
  timing: { use: "add_to_boil", time: { value: 10, unit: "min" } },
});
const misc = (i) => ({ name: `Ajout ${i}`, amount: { value: 1, unit: "g" } });
const culture = (i) => ({ name: `Levure ${i}` });
const step = (i) => ({
  name: `Palier ${i}`,
  step_temperature: { value: 65, unit: "C" },
  step_time: { value: 10, unit: "min" },
});
const withIngredients = (list, items) =>
  beerRecipe({ ingredients: { ...beerRecipe().ingredients, [list]: items } });
const withSteps = (count) => beerRecipe({ mash: { name: "Empâtage", mash_steps: n(count, step) } });

// Valeurs refusées dans les maps fermées de `recipe` : [libellé, champs de `recipe`].
const CLOSED_MAP_VALUES = [
  ["style avec price_eur", { style: { name: "IPA", price_eur: 12 } }],
  ["style en texte", { style: "IPA" }],
  ["boil avec cost_eur", { boil: { boil_time: { value: 60, unit: "min" }, cost_eur: 5 } }],
  ["boil en liste", { boil: ["x", { price_eur: 3 }] }],
  ["boil en texte", { boil: "texte" }],
  ["mash avec stock_g", { mash: { name: "Empâtage", stock_g: 1000 } }],
  ["mash en liste", { mash: [{ price_eur: 3 }] }],
  ["mash.name en map", { mash: { name: { price_eur: 1 } } }],
  ["mash.name de 121 caractères", { mash: { name: "m".repeat(121) } }],
  ["mash_steps nul", { mash: { name: "Empâtage", mash_steps: null } }],
  ["hop_additions nul", { ingredients: { ...beerRecipe().ingredients, hop_additions: null } }],
  [
    "fermentable_additions en map",
    { ingredients: { ...beerRecipe().ingredients, fermentable_additions: { a: 1 } } },
  ],
];
const CLOSED_MAPS = CLOSED_MAP_VALUES.map(([label, extra]) => [
  label,
  (o) => recipe(o, {}, extra),
  false,
]);

// Enveloppes et recettes : [libellé, document recipes/ de owner, accepté].
const SHAPES = [
  ["recette complète", (o) => recipe(o), true],
  [
    "recette minimale (nom et ingrédients vides)",
    (o) => ({ ...recipe(o), recipe: { name: "Minimale", ingredients: {} } }),
    true,
  ],
  [
    "température du grain sans palier",
    (o) =>
      recipe(o, {}, { mash: { name: "Empâtage", grain_temperature: { value: 18, unit: "C" } } }),
    true,
  ],
  ["document plat de la v0.1.14", (o) => flatRecipe(o), false],
  [
    "sans format_version",
    (o) => {
      const d = recipe(o);
      delete d.format_version;
      return d;
    },
    false,
  ],
  ["format_version 2", (o) => recipe(o, { format_version: 2 }), false],
  ["format_version en texte", (o) => recipe(o, { format_version: "1" }), false],
  ["sans recipe", (o) => recipe(o, { recipe: null }), false],
  ["batch_size en kg", (o) => recipe(o, {}, { batch_size: { value: 20, unit: "kg" } }), false],
  ["batch_size sans valeur", (o) => recipe(o, {}, { batch_size: { unit: "l" } }), false],
  [
    "boil_time en heures",
    (o) => recipe(o, {}, { boil: { boil_time: { value: 1, unit: "h" } } }),
    false,
  ],
  [
    "boil_time décimal",
    (o) => recipe(o, {}, { boil: { boil_time: { value: 60.5, unit: "min" } } }),
    false,
  ],
  [
    "grain_temperature en °F",
    (o) =>
      recipe(o, {}, { mash: { name: "Empâtage", grain_temperature: { value: 64, unit: "F" } } }),
    false,
  ],
  // Maps fermées du sous-arbre `recipe` (style, boil, mash) et valeur de `type`.
  ["type de recette hors schéma", (o) => recipe(o, {}, { type: "bière" }), false],
  ["type de recette du schéma non proposé (cider)", (o) => recipe(o, {}, { type: "cider" }), true],
  ["type de recette en map", (o) => recipe(o, {}, { type: { price_eur: 1 } }), false],
  [
    "sans type de recette",
    (o) => {
      const d = recipe(o);
      delete d.recipe.type;
      return d;
    },
    true,
  ],
  ...CLOSED_MAPS,
  ["champ hors liste dans recipe (efficiency)", (o) => recipe(o, {}, { efficiency: {} }), false],
  ["notes de 10 001 caractères", (o) => recipe(o, {}, { notes: "n".repeat(10001) }), false],
  ["style de 121 caractères", (o) => recipe(o, {}, { style: { name: "s".repeat(121) } }), false],
  [
    "sans ingredients",
    (o) => {
      const d = recipe(o);
      delete d.recipe.ingredients;
      return d;
    },
    false,
  ],
  [
    "water_additions",
    (o) => recipe(o, {}, { ingredients: { ...beerRecipe().ingredients, water_additions: [] } }),
    false,
  ],
  [
    "50 malts",
    (o) => ({ ...recipe(o), recipe: withIngredients("fermentable_additions", n(50, fermentable)) }),
    true,
  ],
  [
    "51 malts",
    (o) => ({ ...recipe(o), recipe: withIngredients("fermentable_additions", n(51, fermentable)) }),
    false,
  ],
  [
    "51 houblons",
    (o) => ({ ...recipe(o), recipe: withIngredients("hop_additions", n(51, hop)) }),
    false,
  ],
  [
    "51 ajouts",
    (o) => ({ ...recipe(o), recipe: withIngredients("miscellaneous_additions", n(51, misc)) }),
    false,
  ],
  [
    "10 levures",
    (o) => ({ ...recipe(o), recipe: withIngredients("culture_additions", n(10, culture)) }),
    true,
  ],
  [
    "11 levures",
    (o) => ({ ...recipe(o), recipe: withIngredients("culture_additions", n(11, culture)) }),
    false,
  ],
  ["20 paliers", (o) => ({ ...recipe(o), recipe: withSteps(20) }), true],
  ["21 paliers", (o) => ({ ...recipe(o), recipe: withSteps(21) }), false],
];

describe("recipes — format BeerJSON partiel", () => {
  for (const [label, make, allowed] of SHAPES) {
    it(`${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("recipes/forme")
          .set(fresh(make(uidOf("owner")))),
      );
    });
  }

  it("modifier une recette pour la passer au format plat : refusé", async () => {
    const { created_at, ...flat } = flatRecipe(uidOf("owner"));
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .set({ ...flat, created_at, updated_at: serverTimestamp() }),
    );
  });

  it("modifier `recipe` d'un bloc, unités canoniques : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ recipe: beerRecipe({ name: "Révisée" }), updated_at: serverTimestamp() }),
    );
  });

  it("modifier `recipe` d'un bloc : les champs absents disparaissent", async () => {
    const ref = db(state.env, "owner").doc("recipes/r-a");
    const { batch_size, boil, ...rest } = beerRecipe({ name: "Révisée" });
    await expectRule(true, ref.update({ recipe: rest, updated_at: serverTimestamp() }));
    const stored = (await ref.get()).data().recipe;
    assert.equal(stored.name, "Révisée");
    assert.equal("batch_size" in stored, false);
    assert.equal("boil" in stored, false);
    assert.ok(batch_size && boil);
  });

  for (const [label, extra] of CLOSED_MAP_VALUES) {
    it("modifier recipe : " + label + " : refusé", async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc("recipes/r-a")
          .update({ recipe: beerRecipe(extra), updated_at: serverTimestamp() }),
      );
    });
  }

  it("modifier `recipe.type` hors schéma : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ "recipe.type": "bière", updated_at: serverTimestamp() }),
    );
  });

  it("ajouter `recipe.style.price_eur` : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ "recipe.style.price_eur": 12, updated_at: serverTimestamp() }),
    );
  });

  it("modifier une unité en kg : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({
          "recipe.batch_size": { value: 20, unit: "kg" },
          updated_at: serverTimestamp(),
        }),
    );
  });
});

describe("brews — copie figée au format BeerJSON partiel", () => {
  for (const [label, make, allowed] of SHAPES) {
    it(`copie : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("brews/forme")
          .set(fresh(brew(uidOf("owner"), { recipe_snapshot: make("brewer-a") }))),
      );
    });
  }
});

// Budget de 1 000 expressions par requête (firestore.rules, brews/) : la recette la plus
// grande que les règles acceptent passe aussi dans la copie figée d'un brassin qui porte
// tous les champs permis à la création.
describe("recipes et brews — budget des règles", () => {
  const g = (value) => ({ value, unit: "g" });
  const largest = (owner) =>
    recipe(
      owner,
      {
        owner_name: "Brasseur A",
        equipment_id: "e".repeat(128),
        imported_from: "f".repeat(200),
        brew_steps: brewSteps(60),
      },
      {
        notes: "n".repeat(10000),
        style: { name: "s".repeat(120) },
        ingredients: {
          fermentable_additions: n(50, fermentable),
          hop_additions: n(50, hop),
          miscellaneous_additions: n(50, (i) => ({ ...misc(i), type: "spice" })),
          culture_additions: n(10, (i) => ({ ...culture(i), type: "ale", amount: g(11) })),
        },
        mash: {
          name: "Empâtage",
          grain_temperature: { value: 18, unit: "C" },
          mash_steps: n(20, step),
        },
      },
    );

  it("recette la plus grande permise : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/budget")
        .set(fresh({ ...largest(uidOf("owner")), owner_name: nameOf("owner") })),
    );
  });

  it("brassin dont la copie est la plus grande permise, tous champs de création : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/budget")
        .set(
          fresh(
            brew(uidOf("owner"), {
              owner_name: nameOf("owner"),
              planned_for: Timestamp.fromDate(new Date("2026-11-22T08:00:00Z")),
              notes: "n".repeat(10000),
              imported_from: "f".repeat(200),
              recipe_snapshot: largest("brewer-a"),
              // Équipement dont tous les champs sont remplis.
              equipment_snapshot: equipment("brewer-a", {
                owner_name: "Brasseur A",
                mash_tun_volume_l: 40,
                kettle_volume_l: 40,
                mash_tun_dead_space_l: 1,
                kettle_dead_space_l: 1,
                trub_loss_l: 1,
                fermenter_loss_l: 1,
                grain_absorption_l_per_kg: 0.8,
                notes: "n".repeat(10000),
              }),
            }),
          ),
        ),
    );
  });

  it("modification de ce brassin (statut, ajustement) : autorisé", async () => {
    const fs = db(state.env, "owner");
    const ref = fs.doc("brews/budget");
    await ref.set(fresh(brew(uidOf("owner"), { recipe_snapshot: largest("brewer-a") })));
    await expectRule(
      true,
      ref.update({
        status: "brewing",
        brewed_at: Timestamp.fromDate(new Date("2026-11-22T09:00:00Z")),
        adjustments: { boil_time_min: 75, mash_efficiency_pct: 70 },
        updated_at: serverTimestamp(),
      }),
    );
  });

  // Brassin du 22 novembre rempli normalement après le brassage : date de brassage,
  // notes, embouteillage, trois mesures retenues, sugars_in_wort, équipement complet.
  // Contrôler tous ses champs à chaque modification dépassait 1 000 expressions avec
  // 5 ajustements (v0.1.15) : la modification ne contrôle que les champs changés.
  const at = (iso) => Timestamp.fromDate(new Date(iso));
  const adjustments11 = {
    batch_volume_l: 20,
    mash_water_l: 15,
    sparge_water_l: 12,
    pre_boil_volume_l: 25,
    post_boil_volume_l: 22,
    fermenter_volume_l: 21,
    boil_off_l_per_h: 3,
    mash_temp_c: 66,
    mash_time_min: 60,
    boil_time_min: 60,
    mash_efficiency_pct: 72,
  };
  const brew22 = (extra = {}) =>
    brew(uidOf("owner"), {
      owner_name: nameOf("owner"),
      status: "fermenting",
      planned_for: at("2026-11-22T08:00:00Z"),
      brewed_at: at("2026-11-22T08:30:00Z"),
      notes: "Brassin du 22 novembre.",
      bottled_at: at("2026-12-06T10:00:00Z"),
      bottles_count: 52,
      packaged_volume_l: 18.5,
      priming_sugar_g: 120,
      priming_sugar_name: "Sucre blanc",
      og_event_id: "o".repeat(20),
      fg_event_id: "f".repeat(20),
      fermenter_volume_event_id: "v".repeat(20),
      sugars_in_wort: false,
      equipment_snapshot: equipment("brewer-a", {
        owner_name: "Brasseur A",
        kind: "multi_vessel",
        mash_tun_volume_l: 30,
        kettle_volume_l: 40,
        mash_tun_dead_space_l: 1,
        kettle_dead_space_l: 1,
        trub_loss_l: 1,
        fermenter_loss_l: 0.5,
        grain_absorption_l_per_kg: 0.8,
        notes: "Cuve maison",
      }),
      ...extra,
    });
  const seed22 = (extra) => seed(state.env, { "brews/b-22": brew22(extra) });

  it("brassin du 22 novembre avec 11 ajustements, statut modifié : autorisé", async () => {
    await seed22({ adjustments: adjustments11 });
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/b-22")
        .update({
          status: "conditioning",
          owner_name: nameOf("owner"),
          updated_at: serverTimestamp(),
        }),
    );
  });

  it("brassin du 22 novembre avec 11 ajustements, embouteillage modifié : autorisé", async () => {
    await seed22({ adjustments: adjustments11 });
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/b-22")
        .update({
          bottled_at: at("2026-12-07T10:00:00Z"),
          bottles_count: 50,
          packaged_volume_l: 18,
          priming_sugar_g: 110,
          priming_sugar_name: "Dextrose",
          status: "conditioning",
          owner_name: nameOf("owner"),
          updated_at: serverTimestamp(),
        }),
    );
  });

  it("brassin du 22 novembre : écriture de 11 ajustements valides : autorisé", async () => {
    await seed22();
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/b-22")
        .update({
          adjustments: adjustments11,
          owner_name: nameOf("owner"),
          updated_at: serverTimestamp(),
        }),
    );
  });

  for (const [label, adjustments] of [
    ["volume en texte", { ...adjustments11, mash_water_l: "15" }],
    ["clé hors liste (price_eur)", { ...adjustments11, price_eur: 3 }],
    ["rendement à 150 %", { ...adjustments11, mash_efficiency_pct: 150 }],
    ["ajustements en liste", [20, 15]],
  ]) {
    it(`brassin du 22 novembre : ajustement mal formé (${label}) : refusé`, async () => {
      await seed22({ adjustments: adjustments11 });
      await expectRule(
        false,
        db(state.env, "owner")
          .doc("brews/b-22")
          .update({
            adjustments,
            owner_name: nameOf("owner"),
            updated_at: serverTimestamp(),
          }),
      );
    });
  }

  for (const [label, fields] of [
    ["bottles_count en texte", { bottles_count: "52" }],
    ["bottles_count décimal", { bottles_count: 52.5 }],
    ["bottled_at en texte", { bottled_at: "2026-12-06" }],
    ["packaged_volume_l nul ou négatif", { packaged_volume_l: 0 }],
    ["priming_sugar_name de 81 caractères", { priming_sugar_name: "s".repeat(81) }],
  ]) {
    it(`brassin du 22 novembre : champ d'embouteillage mal typé (${label}) : refusé`, async () => {
      await seed22({ adjustments: adjustments11 });
      await expectRule(
        false,
        db(state.env, "owner")
          .doc("brews/b-22")
          .update({ ...fields, owner_name: nameOf("owner"), updated_at: serverTimestamp() }),
      );
    });
  }

  for (const [label, fields] of [
    ["statut hors liste", { status: "bu" }],
    ["statut retiré", { status: deleteField() }],
    ["nom vide", { name: "" }],
    ["nom retiré", { name: deleteField() }],
    ["mesure retenue en nombre", { og_event_id: 12 }],
    ["sugars_in_wort en texte", { sugars_in_wort: "non" }],
    ["notes de 10 001 caractères", { notes: "n".repeat(10001) }],
    ["brewed_at en texte", { brewed_at: "2026-11-22" }],
    ["champ hors liste (cost_eur)", { cost_eur: 31.4 }],
    ["copie de l'équipement retirée", { equipment_snapshot: deleteField() }],
    // brew22() sème recipe_id "r-a" : la recette d'origine ne se retire pas.
    ["recette d'origine retirée (recipe_id)", { recipe_id: deleteField() }],
  ]) {
    it(`brassin du 22 novembre : ${label} : refusé`, async () => {
      await seed22({ adjustments: adjustments11 });
      await expectRule(
        false,
        db(state.env, "owner")
          .doc("brews/b-22")
          .update({ ...fields, owner_name: nameOf("owner"), updated_at: serverTimestamp() }),
      );
    });
  }

  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    it(`${name} modifie le statut du brassin du 22 novembre (11 ajustements) : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seed22({ adjustments: adjustments11 });
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("brews/b-22")
          .update({
            status: "conditioning",
            ...(nameOf(name) ? { owner_name: nameOf(name) } : {}),
            updated_at: serverTimestamp(),
          }),
      );
    });
  }
});

describe("brews — copie figée immuable", () => {
  it("owner remplace par set() son brassin b-a avec une autre copie figée : refusé", async () => {
    const data = brew(uidOf("owner"), {
      recipe_snapshot: recipe("brewer-a", {}, { name: "Autre recette" }),
    });
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .set({ ...data, created_at: CREATED, updated_at: serverTimestamp() }),
    );
  });

  it("owner réécrit par set() son brassin b-a avec la même copie figée : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/b-a")
        .set({ ...brew(uidOf("owner")), name: "Renommé", updated_at: serverTimestamp() }),
    );
  });

  it("owner remplace par set() la copie de l'équipement de b-a : refusé", async () => {
    const data = brew(uidOf("owner"), {
      equipment_snapshot: equipment("brewer-a", { name: "Autre cuve" }),
    });
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .set({ ...data, created_at: CREATED, updated_at: serverTimestamp() }),
    );
  });
});

describe("brews — champs permis à la création", () => {
  // Les dates de brassage, les ajustements et les champs d'après brassage arrivent par
  // des modifications : une création qui les porte est refusée (budget, voir brews/).
  for (const [label, extra] of [
    ["brewed_at", { brewed_at: Timestamp.fromDate(new Date("2026-11-22T09:00:00Z")) }],
    ["adjustments", { adjustments: { boil_time_min: 75 } }],
    ["bottles_count", { bottles_count: 20 }],
  ]) {
    it(`création avec ${label} : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc("brews/champs")
          .set(fresh(brew(uidOf("owner"), extra))),
      );
    });
  }

  // Un champ obligatoire absent rend la lecture en erreur : l'écriture est refusée.
  for (const champ of ["status", "name", "recipe_snapshot", "equipment_snapshot"]) {
    it(`création sans ${champ} : refusé`, async () => {
      const data = brew(uidOf("owner"));
      delete data[champ];
      await expectRule(false, db(state.env, "owner").doc("brews/champs").set(fresh(data)));
    });
  }
});

describe("recipes et brews — cinq profils", () => {
  for (const name of FIVE_PROFILES) {
    const member = isMemberProfile(name);
    it(`${name} crée une recette au format BeerJSON : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        member,
        db(state.env, name)
          .doc("recipes/profil")
          .set(fresh(recipe(ownerFor(name)))),
      );
    });

    it(`${name} crée une recette au format plat : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("recipes/profil")
          .set(fresh(flatRecipe(ownerFor(name)))),
      );
    });

    it(`${name} crée un brassin dont la copie est plate : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("brews/profil")
          .set(fresh(brew(ownerFor(name), { recipe_snapshot: flatRecipe("brewer-a") }))),
      );
    });

    it(`${name} modifie la recette copiée de brews/b-a : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("brews/b-a")
          .update({
            "recipe_snapshot.recipe.batch_size": { value: 25, unit: "l" },
            updated_at: serverTimestamp(),
          }),
      );
    });

    const writesA = name === "owner";
    it(`${name} réécrit la recette de brewer-a au format BeerJSON : ${writesA ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        writesA,
        db(state.env, name)
          .doc("recipes/r-a")
          .update({ recipe: beerRecipe({ name: "Révisée" }), updated_at: serverTimestamp() }),
      );
    });
  }
});
