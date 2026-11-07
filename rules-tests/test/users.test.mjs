// users/{uid}/** : prix, stock et coût réel d'un brassin, privés à leur propriétaire (P5).

import { describe, it } from "node:test";
import { db, serverTimestamp } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

// Ce que chacun des cinq profils obtient sur les données privées de brewer-a.
const ACCESS = {
  anonymous: false,
  nonMember: false,
  owner: true,
  otherBrewer: false,
  admin: false,
};

const PATHS = {
  prices: "users/brewer-a/prices/malt-pilsner",
  stock: "users/brewer-a/stock/malt-pilsner",
  brew_costs: "users/brewer-a/brew_costs/b-a",
};

for (const [label, path] of Object.entries(PATHS)) {
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
      it(`${name} écrit chez brewer-a : ${verdict}`, async () => {
        await expectRule(
          allowed,
          db(state.env, name).doc(path).set({ name: "x", updated_at: serverTimestamp() }),
        );
      });
      it(`${name} supprime chez brewer-a : ${verdict}`, async () => {
        await expectRule(allowed, db(state.env, name).doc(path).delete());
      });
    }
  });
}

describe("users/{uid} — propres données", () => {
  for (const name of ["otherBrewer", "admin"]) {
    it(`${name} écrit ses propres prix : autorisé`, async () => {
      await expectRule(
        true,
        db(state.env, name)
          .doc(`users/${name === "admin" ? "admin" : "brewer-b"}/prices/houblon-saaz`)
          .set({ name: "Saaz", price_eur: 8, quantity: 100, unit: "g" }),
      );
    });
  }

  it("non membre écrit sous son propre uid : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "nonMember").doc("users/stranger/prices/x").set({ price_eur: 1 }),
    );
  });

  it("adresse non vérifiée écrit sous son propre uid : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "unverified").doc("users/unverified/prices/x").set({ price_eur: 1 }),
    );
  });
});
