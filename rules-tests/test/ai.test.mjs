// ai_config/, ai_quotas/, ai_usage/ : réglages, tours du jour et comptes du mois de l'IA,
// écrits par le serveur seul (ADR-016, section 7 ; P58), pour les cinq profils de P4 et les
// cas de P11.

import { describe, it } from "node:test";
import { CREATED, db, seed, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const FIVE = ["anonymous", "nonMember", "owner", "otherBrewer", "admin"];

const policy = {
  version: 1,
  features: {
    recipe_assistant_turn: {
      model: "claude-sonnet-5-5",
      effort: "medium",
      members_enabled: false,
      turns_per_day: 20,
      founder_turns_per_day: 60,
      turns_per_conversation: 20,
    },
  },
  updated_at: CREATED,
  updated_by_uid: "admin",
};

const pricing = {
  version: 1,
  checked_on: "2026-11-15",
  source: "Page des tarifs d'Anthropic",
  models: {
    "claude-sonnet-5-5": {
      label: "Sonnet 5.5",
      input_usd_per_mtok: 2,
      output_usd_per_mtok: 10,
      cache_write_usd_per_mtok: 2.5,
      cache_read_usd_per_mtok: 0.2,
      efforts: ["low", "medium", "high"],
    },
  },
  updated_at: CREATED,
  updated_by_uid: "admin",
};

const quota = {
  features: { recipe_assistant_turn: { day: "20261115", count: 3, resets_at: CREATED } },
};

const usage = (uid) => ({
  month: "2026-11",
  uid,
  member_email: `${uid}@example.com`,
  expires_at: CREATED,
  features: { recipe_assistant_turn: { calls: 3, failed_calls: 0, unpriced_calls: 0 } },
});

async function seedAi() {
  await seed(state.env, {
    "ai_config/policy": policy,
    "ai_config/pricing": pricing,
    "ai_config/other": { x: 1 },
    "ai_quotas/brewer-a": quota,
    "ai_quotas/brewer-b": quota,
    "ai_usage/2026-11_brewer-a": usage("brewer-a"),
    "ai_usage/2026-11_brewer-b": usage("brewer-b"),
  });
}

const table = (allowed) => Object.fromEntries(FIVE.map((n) => [n, allowed.includes(n)]));

describe("ai_config — cinq profils (P4, P58)", () => {
  const readPolicy = table(["owner", "otherBrewer", "admin"]);
  for (const [name, allowed] of Object.entries(readPolicy)) {
    it(`${name} lit la politique : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedAi();
      await expectRule(allowed, db(state.env, name).doc("ai_config/policy").get());
    });
  }
  const readPricing = table(["admin"]);
  for (const [name, allowed] of Object.entries(readPricing)) {
    it(`${name} lit la grille : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedAi();
      await expectRule(allowed, db(state.env, name).doc("ai_config/pricing").get());
    });
  }
  for (const name of FIVE) {
    it(`${name} lit une autre clé de ai_config : refusé`, async () => {
      await seedAi();
      await expectRule(false, db(state.env, name).doc("ai_config/other").get());
    });
    it(`${name} liste ai_config : refusé`, async () => {
      await seedAi();
      await expectRule(false, db(state.env, name).collection("ai_config").get());
    });
    for (const doc of ["policy", "pricing"]) {
      it(`${name} écrit ai_config/${doc} : refusé`, async () => {
        await expectRule(false, db(state.env, name).doc(`ai_config/${doc}`).set(policy));
      });
      it(`${name} supprime ai_config/${doc} : refusé`, async () => {
        await seedAi();
        await expectRule(false, db(state.env, name).doc(`ai_config/${doc}`).delete());
      });
    }
  }
  for (const name of ["unverified", "passwordProvider"]) {
    it(`${name} (P11) lit la politique : refusé`, async () => {
      await seedAi();
      await expectRule(false, db(state.env, name).doc("ai_config/policy").get());
    });
  }
});

describe("ai_quotas — cinq profils (P4, P58)", () => {
  const readOwn = table(["owner", "admin"]);
  for (const [name, allowed] of Object.entries(readOwn)) {
    it(`${name} lit ai_quotas/brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedAi();
      await expectRule(allowed, db(state.env, name).doc("ai_quotas/brewer-a").get());
    });
  }
  for (const name of ["owner", "otherBrewer", "admin"]) {
    it(`${name} lit son propre compteur, absent : autorisé`, async () => {
      await expectRule(
        true,
        db(state.env, name)
          .doc(`ai_quotas/${uidOf(name)}`)
          .get(),
      );
    });
  }
  for (const name of FIVE) {
    it(`${name} liste ai_quotas : refusé`, async () => {
      await seedAi();
      await expectRule(false, db(state.env, name).collection("ai_quotas").get());
    });
    it(`${name} écrit son compteur : refusé`, async () => {
      const uid = name === "anonymous" ? "anon" : uidOf(name);
      await expectRule(
        false,
        db(state.env, name)
          .doc(`ai_quotas/${uid}`)
          .set({ features: { recipe_assistant_turn: { count: 0 } } }),
      );
    });
  }
  it("unverified (P11) lit son compteur : refusé", async () => {
    await seedAi();
    await expectRule(false, db(state.env, "unverified").doc("ai_quotas/unverified").get());
  });
});

describe("ai_usage — cinq profils (P4, P58)", () => {
  const readOwn = table(["owner", "admin"]);
  for (const [name, allowed] of Object.entries(readOwn)) {
    it(`${name} lit ai_usage/2026-11_brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedAi();
      await expectRule(allowed, db(state.env, name).doc("ai_usage/2026-11_brewer-a").get());
    });
  }
  for (const name of ["owner", "otherBrewer"]) {
    it(`${name} lit son mois absent : autorisé`, async () => {
      await expectRule(
        true,
        db(state.env, name)
          .doc(`ai_usage/2026-10_${uidOf(name)}`)
          .get(),
      );
    });
    it(`${name} lit un identifiant hors forme qui finit par son uid : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc(`ai_usage/x_${uidOf(name)}`)
          .get(),
      );
    });
    it(`${name} lit un identifiant à préfixe de mois ajouté : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc(`ai_usage/2026-11_2026-11_${uidOf(name)}`)
          .get(),
      );
    });
  }
  const list = table(["admin"]);
  for (const [name, allowed] of Object.entries(list)) {
    it(`${name} liste un mois par 50 : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedAi();
      await expectRule(
        allowed,
        db(state.env, name).collection("ai_usage").where("month", "==", "2026-11").limit(50).get(),
      );
    });
  }
  it("admin liste par 51 : refusé", async () => {
    await seedAi();
    await expectRule(
      false,
      db(state.env, "admin").collection("ai_usage").where("month", "==", "2026-11").limit(51).get(),
    );
  });
  it("admin liste sans limite : refusé", async () => {
    await seedAi();
    await expectRule(false, db(state.env, "admin").collection("ai_usage").get());
  });
  it("brasseur liste ses propres comptes : refusé", async () => {
    await seedAi();
    await expectRule(
      false,
      db(state.env, "owner").collection("ai_usage").where("uid", "==", "brewer-a").limit(10).get(),
    );
  });
  for (const name of FIVE) {
    it(`${name} écrit ses comptes du mois : refusé`, async () => {
      const uid = name === "anonymous" ? "anon" : uidOf(name);
      await expectRule(false, db(state.env, name).doc(`ai_usage/2026-11_${uid}`).set(usage(uid)));
    });
    it(`${name} supprime ai_usage/2026-11_brewer-a : refusé`, async () => {
      await seedAi();
      await expectRule(false, db(state.env, name).doc("ai_usage/2026-11_brewer-a").delete());
    });
  }
  it("passwordProvider (P11) lit son mois : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "passwordProvider").doc("ai_usage/2026-11_password").get(),
    );
  });
});
