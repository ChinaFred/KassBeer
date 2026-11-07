// Comptes invités mais connexion non conforme, et chemins non déclarés (P11).

import { describe, it } from "node:test";
import { db, fresh, recipe, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

describe("P11 — connexion Google à l'adresse vérifiée", () => {
  for (const name of ["unverified", "passwordProvider"]) {
    it(`${name}, invité, lit une recette : refusé`, async () => {
      await expectRule(false, db(state.env, name).doc("recipes/r-a").get());
    });
    it(`${name}, invité, crée une recette : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("recipes/nouveau")
          .set(fresh(recipe(uidOf(name)))),
      );
    });
  }

  it("adresse du jeton en majuscules, invitée en minuscules : lit une recette", async () => {
    await expectRule(true, db(state.env, "mixedCase").doc("recipes/r-a").get());
  });

  it("membre retiré : ne lit plus rien", async () => {
    await state.env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc("members/brewer.b@example.com").delete(),
    );
    await expectRule(false, db(state.env, "otherBrewer").doc("recipes/r-a").get());
  });
});

describe("chemins non déclarés", () => {
  for (const name of ["owner", "admin"]) {
    it(`${name} écrit dans une collection inconnue : refusé`, async () => {
      await expectRule(false, db(state.env, name).doc("divers/x").set({ a: 1 }));
    });
    it(`${name} lit une collection inconnue : refusé`, async () => {
      await expectRule(false, db(state.env, name).doc("divers/x").get());
    });
  }

  it("admin écrit le document racine users/{uid} d'un autre : refusé", async () => {
    await expectRule(false, db(state.env, "admin").doc("users/brewer-a").set({ a: 1 }));
  });
});
