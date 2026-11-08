// v0.3 — chronologie des recettes (brew_steps), statut des brassins, premier
// démarrage en un lot, brassin puis événement (P4, cinq profils).

import { describe, it } from "node:test";
import {
  brew,
  brewSteps,
  db,
  equipment,
  event,
  fresh,
  FIVE_PROFILES,
  recipe,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));
const isMemberProfile = (name) => ["owner", "otherBrewer", "admin"].includes(name);
const STARTED_AT = Timestamp.fromDate(new Date("2026-11-08T09:15:00Z"));

describe("recipes — brew_steps, cinq profils", () => {
  for (const name of FIVE_PROFILES) {
    const allowed = isMemberProfile(name);
    it(`${name} crée sa recette de 60 étapes : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("recipes/chronologie")
          .set(fresh(recipe(ownerFor(name), { brew_steps: brewSteps(60) }))),
      );
    });

    it(`${name} crée sa recette de 61 étapes : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("recipes/chronologie")
          .set(fresh(recipe(ownerFor(name), { brew_steps: brewSteps(61) }))),
      );
    });

    const writesA = name === "owner";
    it(`${name} écrit 60 étapes dans la recette de brewer-a : ${writesA ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        writesA,
        db(state.env, name)
          .doc("recipes/r-a")
          .update({ brew_steps: brewSteps(60), updated_at: serverTimestamp() }),
      );
    });
  }

  it("owner écrit 61 étapes dans sa recette : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ brew_steps: brewSteps(61), updated_at: serverTimestamp() }),
    );
  });

  it("chronologie nulle : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ brew_steps: null, updated_at: serverTimestamp() }),
    );
  });

  it("chronologie qui n'est pas une liste : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("recipes/r-a")
        .update({ brew_steps: { a: 1 }, updated_at: serverTimestamp() }),
    );
  });
});

describe("brews — copie d'une recette qui porte brew_steps", () => {
  for (const name of FIVE_PROFILES) {
    const allowed = isMemberProfile(name);
    it(`${name} crée un brassin dont la copie a 60 étapes : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("brews/chronologie")
          .set(
            fresh(
              brew(ownerFor(name), {
                recipe_snapshot: recipe("brewer-a", { brew_steps: brewSteps(60) }),
              }),
            ),
          ),
      );
    });
  }

  it("copie de 61 étapes : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/chronologie")
        .set(
          fresh(
            brew(uidOf("owner"), {
              recipe_snapshot: recipe("brewer-a", { brew_steps: brewSteps(61) }),
            }),
          ),
        ),
    );
  });
});

describe("brews — statut planned → brewing → fermenting", () => {
  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    it(`${name} commence le brassage de brewer-a (brewing, brewed_at) : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("brews/b-a")
          .update({ status: "brewing", brewed_at: STARTED_AT, updated_at: serverTimestamp() }),
      );
    });

    it(`${name} termine le brassage de brewer-a (fermenting) : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await state.env.withSecurityRulesDisabled((ctx) =>
        ctx.firestore().doc("brews/b-a").update({ status: "brewing", brewed_at: STARTED_AT }),
      );
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("brews/b-a")
          .update({ status: "fermenting", updated_at: serverTimestamp() }),
      );
    });
  }
});

describe("brews — premier démarrage en un WriteBatch (JB3)", () => {
  const firstStart = (name) => {
    const fs = db(state.env, name);
    const batch = fs.batch();
    batch.update(fs.doc("brews/b-a"), {
      status: "brewing",
      brewed_at: STARTED_AT,
      updated_at: serverTimestamp(),
    });
    batch.set(fs.doc("brews/b-a/events/ev-debut"), {
      ...event(ownerFor(name), {
        kind: "step_started",
        step_key: "etape000000000000000",
        measure_type: null,
        value: null,
        measured_at: STARTED_AT,
      }),
      created_at: serverTimestamp(),
    });
    return batch.commit();
  };

  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    it(`${name} écrit statut et premier début dans un lot : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, firstStart(name));
    });
  }

  it("fin d'une étape et début de la suivante dans un lot : autorisé", async () => {
    const fs = db(state.env, "owner");
    const batch = fs.batch();
    const stepEvent = (kind, step_key) => ({
      ...event(uidOf("owner"), { kind, step_key, measure_type: null, value: null }),
      created_at: serverTimestamp(),
    });
    batch.set(fs.doc("brews/b-a/events/ev-fin"), stepEvent("step_ended", "etape-1"));
    batch.set(fs.doc("brews/b-a/events/ev-suite"), stepEvent("step_started", "etape-2"));
    await expectRule(true, batch.commit());
  });
});

describe("brews — brassin puis événement, dans l'ordre de la file", () => {
  for (const name of FIVE_PROFILES) {
    const allowed = isMemberProfile(name);
    it(`${name} crée son brassin puis y ajoute une mesure : ${allowed ? "autorisé" : "refusé"}`, async () => {
      const fs = db(state.env, name);
      const created = fs
        .doc("brews/nouveau")
        .set(fresh(brew(ownerFor(name), { equipment_snapshot: equipment("brewer-a") })));
      await expectRule(allowed, created);
      await expectRule(
        allowed,
        fs
          .doc("brews/nouveau/events/ev-1")
          .set({ ...event(ownerFor(name)), created_at: serverTimestamp() }),
      );
    });
  }

  it("brassin et événement dans un même lot : refusé (get lit l'état avant le lot)", async () => {
    const fs = db(state.env, "owner");
    const batch = fs.batch();
    batch.set(fs.doc("brews/nouveau"), fresh(brew(uidOf("owner"))));
    batch.set(fs.doc("brews/nouveau/events/ev-1"), {
      ...event(uidOf("owner")),
      created_at: serverTimestamp(),
    });
    await expectRule(false, batch.commit());
  });
});
