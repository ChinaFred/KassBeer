// v0.6 — Admin › Import des fiches Excel : sans règle nouvelle, les écritures d'une
// fiche importée (FirestoreImportFichesRepository, CR3) passent sous le compte de celui
// qui importe, pour les cinq profils de P4, et le plus grand brassin importé tient dans
// le budget de 1 000 expressions (P21). Fiche fictive (P15).

import { describe, it } from "node:test";
import {
  brewSteps,
  db,
  FIVE_PROFILES,
  fresh,
  nameOf,
  recipe,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const at = (iso) => Timestamp.fromDate(new Date(iso));
const n = (count, make) => Array.from({ length: count }, (_, i) => make(i));
const RECIPE = "recipes/fiche-blonde-essai";
const BREW = "brews/fiche-2024-07-14-blonde-essai";
const MARQUE = `Fiche Excel · 2024-07-14-blonde-essai · sha256:${"a".repeat(64)}`;

/// Recette d'une fiche : chronologie, `imported_from`, sans équipement (EQ1).
const ficheRecipe = (owner, extra = {}, recipeExtra = {}) =>
  recipe(
    owner,
    {
      imported_from: "Fiche Excel · 2024-07-14-blonde-essai",
      brew_steps: brewSteps(37),
      ...extra,
    },
    recipeExtra,
  );

/// Brassin d'une fiche à sa création : statut done, copie d'équipement neutre (EQ2).
const ficheBrew = (owner, name, extra = {}) => ({
  owner_uid: owner,
  ...(name === undefined ? {} : { owner_name: name }),
  recipe_id: "fiche-blonde-essai",
  name: "Blonde d'essai",
  status: "done",
  planned_for: at("2024-07-13T22:00:00Z"),
  recipe_snapshot: ficheRecipe(owner),
  equipment_snapshot: {
    name: "Installation à cuves (fiches Excel)",
    kind: "multi_vessel",
    owner_uid: owner,
  },
  created_at: serverTimestamp(),
  updated_at: serverTimestamp(),
  ...extra,
});

/// Événements datés de la fiche, identifiants fixés par la préparation.
const ficheEvents = (owner, note = undefined) => [
  ...n(8, (i) => [
    `e0${i}`,
    {
      owner_uid: owner,
      kind: i % 2 === 0 ? "step_started" : "measurement",
      step_key: "etape000000000000000",
      measure_type: i % 2 === 0 ? null : "temperature",
      value: i % 2 === 0 ? null : 66.5,
      ...(note === undefined ? {} : { note }),
      measured_at: at(`2024-07-14T0${7 + Math.floor(i / 2)}:15:00Z`),
      created_at: serverTimestamp(),
    },
  ]),
  [
    "e08",
    {
      owner_uid: owner,
      kind: "measurement",
      step_key: null,
      measure_type: "gravity",
      value: 1.052,
      measured_at: at("2024-07-14T10:05:00Z"),
      created_at: serverTimestamp(),
    },
  ],
  [
    // Densité finale de l'en-tête, datée J+28 par la préparation (CR12).
    "e09",
    {
      owner_uid: owner,
      kind: "measurement",
      step_key: null,
      measure_type: "gravity",
      value: 1.023,
      note: "Date estimée : jour du brassage + 28 jours.",
      measured_at: at("2024-08-11T10:00:00Z"),
      phase: "fermentation",
      created_at: serverTimestamp(),
    },
  ],
];

const ficheCost = (lines = 3) => ({
  brew_id: "fiche-2024-07-14-blonde-essai",
  total_eur: 17.5,
  lines: n(lines, (i) => ({
    key: `malt-essai-${i}`,
    name: `Malt ${i}`,
    quantity: 1000,
    unit: "g",
    cost_eur: 1,
  })),
  computed_at: at("2024-07-14T07:15:00Z"),
  freeze_kind: "initial",
  bottles_count: 50,
  packaged_volume_l: 17,
  priming_sugar_name: "Sucre blanc",
});

const stamped = (name, champs) => ({
  ...champs,
  ...(nameOf(name) === undefined ? {} : { owner_name: nameOf(name) }),
  updated_at: serverTimestamp(),
});

/// Écritures d'une fiche, dans l'ordre de CR3, chacune après l'accusé de la précédente.
async function importerFiche(fs, name, { notes = "Notes de la fiche Excel.", note, lines } = {}) {
  const uid = name === "anonymous" ? "anon" : uidOf(name);
  await fs.doc(RECIPE).set({
    ...ficheRecipe(uid),
    ...(nameOf(name) === undefined ? {} : { owner_name: nameOf(name) }),
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  });
  await fs.doc(BREW).set(ficheBrew(uid, nameOf(name)));
  const brew = fs.doc(BREW);
  await brew.update(stamped(name, { brewed_at: at("2024-07-14T07:15:00Z") }));
  await brew.update(
    stamped(name, { bottles_count: 50, packaged_volume_l: 17, priming_sugar_name: "Sucre blanc" }),
  );
  await brew.update(stamped(name, { notes }));
  const batch = fs.batch();
  for (const [id, data] of ficheEvents(uid, note)) {
    batch.set(fs.doc(`${BREW}/events/${id}`), data);
  }
  await batch.commit();
  await brew.update(stamped(name, { og_event_id: "e08", fermenter_volume_event_id: null }));
  await fs.doc(`users/${uid}/brew_costs/fiche-2024-07-14-blonde-essai`).set(ficheCost(lines));
  await brew.update(stamped(name, { imported_from: MARQUE }));
}

describe("import des fiches — parcours d'une fiche sous son propre compte, cinq profils", () => {
  for (const name of FIVE_PROFILES) {
    const allowed = ["owner", "otherBrewer", "admin"].includes(name);
    it(`${name} importe une fiche : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, importerFiche(db(state.env, name), name));
    });
  }
});

describe("import des fiches — brassin importé de l'admin, cinq profils", () => {
  const importe = async () => importerFiche(db(state.env, "admin"), "admin");

  for (const name of FIVE_PROFILES) {
    const allowed = name === "admin";
    it(`${name} ajoute un relevé au brassin importé : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await importe();
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`${BREW}/events/e10`)
          .set({
            owner_uid: name === "anonymous" ? "anon" : uidOf(name),
            kind: "measurement",
            step_key: null,
            measure_type: "gravity",
            value: 1.012,
            measured_at: at("2024-08-20T10:00:00Z"),
            phase: "fermentation",
            created_at: serverTimestamp(),
          }),
      );
    });

    const lit = name !== "anonymous" && name !== "nonMember";
    it(`${name} lit le brassin importé : ${lit ? "autorisé" : "refusé"}`, async () => {
      await importe();
      await expectRule(lit, db(state.env, name).doc(BREW).get());
    });

    it(`${name} lit le coût figé de l'admin : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await importe();
      await expectRule(
        allowed,
        db(state.env, name).doc("users/admin/brew_costs/fiche-2024-07-14-blonde-essai").get(),
      );
    });
  }

  // S3 : un autre membre ne réécrit ni le brassin ni la recette importés.
  for (const name of ["otherBrewer", "owner"]) {
    it(`${name} réécrit le brassin importé par un set : refusé`, async () => {
      await importe();
      await expectRule(
        false,
        db(state.env, name)
          .doc(BREW)
          .set(ficheBrew(uidOf(name), nameOf(name))),
      );
    });

    it(`${name} réécrit la recette importée par un set : refusé`, async () => {
      await importe();
      await expectRule(
        false,
        db(state.env, name)
          .doc(RECIPE)
          .set({ ...fresh(ficheRecipe(uidOf(name))), owner_name: nameOf(name) }),
      );
    });
  }

  it("second coût figé initial (rejeu) : refusé, le premier reste", async () => {
    await importe();
    await expectRule(
      false,
      db(state.env, "admin")
        .doc("users/admin/brew_costs/fiche-2024-07-14-blonde-essai")
        .set(ficheCost()),
    );
  });

  it("événement déjà écrit réécrit à la reprise : refusé (la reprise lit les existants)", async () => {
    await importe();
    const [id, data] = ficheEvents("admin")[0];
    await expectRule(false, db(state.env, "admin").doc(`${BREW}/events/${id}`).set(data));
  });
});

// Plus grand brassin importé : recette la plus grande des fiches (37 étapes), notes de
// 10 000 caractères, lots de 10 événements à notes de 2 000 caractères, coût de 200
// lignes. Chaque écriture de CR3 tient dans le budget de 1 000 expressions.
describe("import des fiches — budget des règles sur le plus grand brassin importé", () => {
  it("toutes les écritures de la fiche : autorisé", async () => {
    const fs = db(state.env, "admin");
    const big = {
      ...ficheRecipe(
        "admin",
        {
          owner_name: nameOf("admin"),
          imported_from: "f".repeat(200),
          brew_steps: brewSteps(60),
        },
        {
          author: "a".repeat(120),
          notes: "n".repeat(10000),
          ingredients: {
            fermentable_additions: n(50, (i) => ({
              name: `Malt ${i}`,
              type: "grain",
              amount: { value: 1, unit: "g" },
            })),
            hop_additions: n(50, (i) => ({
              name: `Houblon ${i}`,
              amount: { value: 1, unit: "g" },
            })),
            miscellaneous_additions: n(50, (i) => ({
              name: `Ajout ${i}`,
              amount: { value: 1, unit: "g" },
            })),
            culture_additions: n(10, (i) => ({ name: `Levure ${i}` })),
          },
        },
      ),
    };
    await expectRule(
      true,
      (async () => {
        await fs.doc(BREW).set(
          ficheBrew("admin", nameOf("admin"), {
            notes: "n".repeat(10000),
            recipe_snapshot: big,
            equipment_snapshot: {
              name: "Brew in bag (fiches Excel)",
              kind: "all_in_one",
              owner_uid: "admin",
              owner_name: nameOf("admin"),
            },
          }),
        );
        const brew = fs.doc(BREW);
        await brew.update(stamped("admin", { brewed_at: at("2024-07-14T07:15:00Z") }));
        await brew.update(
          stamped("admin", {
            bottles_count: 9999,
            packaged_volume_l: 1000,
            priming_sugar_name: "s".repeat(80),
          }),
        );
        await brew.update(stamped("admin", { notes: "m".repeat(10000) }));
        const batch = fs.batch();
        for (const [id, data] of ficheEvents("admin", "n".repeat(2000))) {
          batch.set(fs.doc(`${BREW}/events/${id}`), data);
        }
        await batch.commit();
        await brew.update(
          stamped("admin", {
            og_event_id: "e08",
            fg_event_id: "e09",
            fermenter_volume_event_id: "x".repeat(128),
          }),
        );
        await fs.doc("users/admin/brew_costs/fiche-2024-07-14-blonde-essai").set(ficheCost(200));
        await brew.update(stamped("admin", { imported_from: "i".repeat(200) }));
      })(),
    );
  });
});

// Le brassin importé naît « done » : la création porte la copie figée et le statut ;
// les champs d'après brassage restent refusés à la création (`brewCreateFields`). Copie
// de recette minimale : le refus vient de la liste des champs, pas du budget (S5).
describe("import des fiches — création du brassin", () => {
  const minimal = (extra = {}) =>
    ficheBrew("admin", nameOf("admin"), { recipe_snapshot: recipe("admin"), ...extra });

  it("brassin done, copie minimale, sans brewed_at : autorisé", async () => {
    await expectRule(true, db(state.env, "admin").doc(BREW).set(minimal()));
  });

  it("brassin done avec brewed_at à la création : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "admin")
        .doc(BREW)
        .set(minimal({ brewed_at: at("2024-07-14T07:15:00Z") })),
    );
  });

  it("recette déjà créée, recréée à la reprise : refusé (la reprise ne la réécrit pas)", async () => {
    const fs = db(state.env, "admin");
    const data = { ...fresh(ficheRecipe("admin")), owner_name: nameOf("admin") };
    await fs.doc(RECIPE).set(data);
    await expectRule(false, fs.doc(RECIPE).set(data));
  });
});
