// Description aromatique (`aroma_description`) : champ de l'enveloppe de recipes/, saisi par
// l'auteur, texte de 1 à 500 caractères, absent quand il est vide (P21). La copie figée d'un
// brassin (`recipe_snapshot`) ne la garde pas : les règles l'y refusent (budget de la création
// d'un brassin, firestore.rules). Jamais dans `recipe`.

import { describe, it } from "node:test";
import {
  beerRecipe,
  brew,
  db,
  deleteField,
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
const aroma = "Agrumes, pamplemousse et une touche de résine.";

describe("aroma_description — cinq profils (P4)", () => {
  for (const name of FIVE_PROFILES) {
    const member = isMemberProfile(name);
    it(`${name} crée une recette à son nom avec une description : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        member,
        db(state.env, name)
          .doc("recipes/aromatique")
          .set(fresh(recipe(ownerFor(name), { aroma_description: aroma }))),
      );
    });

    // r-a appartient à brewer-a, le profil « owner ».
    const writesA = name === "owner";
    it(`${name} écrit la description de la recette de brewer-a : ${writesA ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        writesA,
        db(state.env, name)
          .doc("recipes/r-a")
          .update({ aroma_description: aroma, updated_at: serverTimestamp() }),
      );
    });

    it(`${name} retire la description de la recette de brewer-a : ${writesA ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        writesA,
        db(state.env, name)
          .doc("recipes/r-a")
          .update({ aroma_description: deleteField(), updated_at: serverTimestamp() }),
      );
    });

    it(`${name} lit une recette qui porte une description : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(member, db(state.env, name).doc("recipes/r-a").get());
    });
  }
});

describe("aroma_description — forme (P21)", () => {
  const owner = uidOf("owner");
  const cases = [
    ["1 caractère", { aroma_description: "a" }, true],
    ["500 caractères", { aroma_description: "a".repeat(500) }, true],
    ["501 caractères", { aroma_description: "a".repeat(501) }, false],
    // size() compte des unités UTF-16 : un émoji hors du plan de base en vaut deux.
    // L'éditeur compte de même (`String.length`).
    ["250 émojis (500 unités UTF-16)", { aroma_description: "😀".repeat(250) }, true],
    ["251 émojis (502 unités UTF-16)", { aroma_description: "😀".repeat(251) }, false],
    ["500 « é » (1 000 octets en UTF-8)", { aroma_description: "é".repeat(500) }, true],
    ["chaîne vide", { aroma_description: "" }, false],
    ["espaces seuls", { aroma_description: "   " }, false],
    ["null", { aroma_description: null }, false],
    ["nombre", { aroma_description: 42 }, false],
    ["liste", { aroma_description: ["agrumes"] }, false],
    ["map", { aroma_description: { texte: "agrumes" } }, false],
  ];
  for (const [label, extra, allowed] of cases) {
    it(`création : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("recipes/forme-arome")
          .set(fresh(recipe(owner, extra))),
      );
    });
    it(`modification : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("recipes/r-a")
          .update({ ...extra, updated_at: serverTimestamp() }),
      );
    });
  }

  it("aroma_description dans `recipe` (et non dans l'enveloppe) : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/forme-arome")
        .set(fresh(recipe(owner, {}, { aroma_description: aroma }))),
    );
  });

  it("copie figée d'un brassin qui porte une description : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/arome")
        .set(
          fresh(brew(owner, { recipe_snapshot: recipe("brewer-a", { aroma_description: aroma }) })),
        ),
    );
  });

  it("copie figée d'un brassin sans description : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("brews/arome")
        .set(fresh(brew(owner, { recipe_snapshot: recipe("brewer-a") }))),
    );
  });

  it("recette sans description, puis modification sans la toucher : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ recipe: beerRecipe({ name: "Blonde" }), updated_at: serverTimestamp() }),
    );
  });
});
