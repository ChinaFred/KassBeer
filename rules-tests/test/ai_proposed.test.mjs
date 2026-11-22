// Marques « proposée par l'IA » (`ai_proposed`, ADR-015, lot A2 ; P21, P61) : champ
// de l'enveloppe de recipes/ et de la copie figée d'un brassin (`recipe_snapshot`), liste de
// 100 entrées au plus. La forme d'une entrée (`<nature>:<ingredientKey>:<champ>`) est lue par
// exchange/ : les règles n'inspectent pas les éléments d'une liste. Jamais dans `recipe`.

import { describe, it } from "node:test";
import {
  beerRecipe,
  brew,
  db,
  FIVE_PROFILES,
  fresh,
  recipe,
  serverTimestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));
const isMemberProfile = (name) => ["owner", "otherBrewer", "admin"].includes(name);

const marks = (count) => Array.from({ length: count }, (_, i) => `hop:houblon-h${i}:alpha_acid`);
const longMark = `fermentable:malt-${"a".repeat(177)}:color`;

describe("ai_proposed — cinq profils (P4)", () => {
  for (const name of FIVE_PROFILES) {
    const member = isMemberProfile(name);
    it(`${name} crée une recette à son nom avec 100 marques : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        member,
        db(state.env, name)
          .doc("recipes/marquee")
          .set(fresh(recipe(ownerFor(name), { ai_proposed: marks(100) }))),
      );
    });

    const writesA = name === "owner";
    it(`${name} pose ai_proposed sur la recette de brewer-a : ${writesA ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        writesA,
        db(state.env, name)
          .doc("recipes/r-a")
          .update({ ai_proposed: marks(3), updated_at: serverTimestamp() }),
      );
    });

    it(`${name} crée un brassin à son nom dont la copie garde les marques : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        member,
        db(state.env, name)
          .doc("brews/marque")
          .set(
            fresh(
              brew(ownerFor(name), {
                recipe_snapshot: recipe("brewer-a", { ai_proposed: marks(100) }),
              }),
            ),
          ),
      );
    });

    it(`${name} lit les marques d'une recette : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(member, db(state.env, name).doc("recipes/r-a").get());
    });
  }
});

describe("ai_proposed — forme (P21)", () => {
  const owner = uidOf("owner");
  const cases = [
    ["100 marques", { ai_proposed: marks(100) }, true],
    ["101 marques", { ai_proposed: marks(101) }, false],
    ["liste vide", { ai_proposed: [] }, true],
    ["null", { ai_proposed: null }, false],
    ["marque de 200 caractères", { ai_proposed: [longMark] }, true],
    ["nombre au lieu d'une liste", { ai_proposed: 42 }, false],
    // Risque accepté (firestore.rules, budget) : taille seule ; exchange/ lit ces valeurs
    // comme illisibles et les rapporte.
    [
      "texte de 28 caractères au lieu d'une liste",
      { ai_proposed: "hop:houblon-citra:alpha_acid" },
      true,
    ],
    ["texte de 101 caractères", { ai_proposed: "x".repeat(101) }, false],
    ["map de 3 clés (risque accepté)", { ai_proposed: { a: 1, b: 2, c: 3 } }, true],
    // Décision de l'utilisateur du 2026-11-21 : la taille d'une entrée n'est pas bornée.
    [
      "liste d'une entrée de 10 000 caractères (risque accepté)",
      { ai_proposed: ["x".repeat(10000)] },
      true,
    ],
    [
      "map dont une valeur est une map imbriquée (risque accepté)",
      { ai_proposed: { a: { b: { c: 1 } } } },
      true,
    ],
  ];
  for (const [label, extra, allowed] of cases) {
    it(`recette : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("recipes/forme-marques")
          .set(fresh(recipe(owner, extra))),
      );
    });
    it(`copie d'un brassin : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("brews/forme-marques")
          .set(fresh(brew(owner, { recipe_snapshot: recipe("brewer-a", extra) }))),
      );
    });
  }

  it("modifier la recette : 101 marques refusées", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ ai_proposed: marks(101), updated_at: serverTimestamp() }),
    );
  });

  it("ai_proposed dans `recipe` (et non dans l'enveloppe) : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/forme-marques")
        .set(fresh(recipe(owner, {}, { ai_proposed: marks(1) }))),
    );
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ recipe: beerRecipe({ ai_proposed: marks(1) }), updated_at: serverTimestamp() }),
    );
  });

  it("modifier les marques de la copie figée du brassin b-a : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/b-a")
        .update({ "recipe_snapshot.ai_proposed": marks(1), updated_at: serverTimestamp() }),
    );
  });
});
