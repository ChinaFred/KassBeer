// Instrument de densité : lecture brute d'une mesure (gravity_instrument, brix,
// sample_temperature, refractometer_factor, correct) sur brews/{id}/events/, et
// préférence du brasseur (users/{uid}/preferences/measurement). Cinq profils (P4),
// formes refusées, correction (ME5). Aucun prix (P5).

import { describe, it } from "node:test";
import {
  CREATED,
  db,
  deleteField,
  event,
  FIVE_PROFILES,
  seed,
  serverTimestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const EVENTS = "brews/b-a/events";
const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));
const gravity = (owner, extra = {}) => ({
  ...event(owner, { measure_type: "gravity", value: 1.05, ...extra }),
  created_at: serverTimestamp(),
});
const HYDROMETER = { gravity_instrument: "hydrometer_20c", sample_temperature: 68, correct: true };
const REFRACTOMETER = {
  gravity_instrument: "refractometer",
  value: null,
  brix: 12.4,
  refractometer_factor: 1.04,
  correct: true,
};

describe("densité avec instrument — cinq profils", () => {
  const create = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: false,
    admin: false,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} ajoute une lecture de flottant au brassin de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`${EVENTS}/ev-flottant`)
          .set(gravity(ownerFor(name), HYDROMETER)),
      );
    });
    it(`${name} ajoute une lecture de réfractomètre au brassin de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`${EVENTS}/ev-refracto`)
          .set(gravity(ownerFor(name), REFRACTOMETER)),
      );
    });
    it(`${name} corrige l'instrument d'une densité de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, {
        [`${EVENTS}/ev-densite`]: event("brewer-a", { measure_type: "gravity", value: 1.05 }),
      });
      await expectRule(allowed, db(state.env, name).doc(`${EVENTS}/ev-densite`).update(HYDROMETER));
    });
  }
});

describe("densité avec instrument — forme", () => {
  const cases = [
    ["flottant 20 °C, température et case", HYDROMETER, true],
    [
      "flottant 15,6 °C sans température",
      { gravity_instrument: "hydrometer_15_6c", correct: false },
      true,
    ],
    [
      "flottant à 100 °C (gardée sans correction)",
      { ...HYDROMETER, sample_temperature: 100 },
      true,
    ],
    ["flottant à 101 °C", { ...HYDROMETER, sample_temperature: 101 }, false],
    ["flottant à −1 °C", { ...HYDROMETER, sample_temperature: -1 }, false],
    ["flottant sans case", { gravity_instrument: "hydrometer_20c" }, false],
    ["case en texte", { ...HYDROMETER, correct: "oui" }, false],
    ["flottant avec °Brix", { ...HYDROMETER, brix: 12 }, false],
    ["flottant sans value", { ...HYDROMETER, value: null }, false],
    ["réfractomètre complet", REFRACTOMETER, true],
    ["réfractomètre sans facteur", { ...REFRACTOMETER, refractometer_factor: null }, true],
    ["réfractomètre avec value", { ...REFRACTOMETER, value: 1.048 }, false],
    ["réfractomètre sans °Brix", { ...REFRACTOMETER, brix: null }, false],
    ["°Brix 40", { ...REFRACTOMETER, brix: 40 }, true],
    ["°Brix 40,1", { ...REFRACTOMETER, brix: 40.1 }, false],
    ["°Brix négatif", { ...REFRACTOMETER, brix: -0.1 }, false],
    ["facteur 0,89", { ...REFRACTOMETER, refractometer_factor: 0.89 }, false],
    ["facteur 1,21", { ...REFRACTOMETER, refractometer_factor: 1.21 }, false],
    ["réfractomètre avec température", { ...REFRACTOMETER, sample_temperature: 20 }, false],
    ["réfractomètre sans case", { ...REFRACTOMETER, correct: null }, false],
    ["électronique, densité seule", { gravity_instrument: "digital" }, true],
    ["autre instrument, densité seule", { gravity_instrument: "other" }, true],
    ["électronique avec case", { gravity_instrument: "digital", correct: true }, false],
    [
      "électronique avec température",
      { gravity_instrument: "digital", sample_temperature: 20 },
      false,
    ],
    ["instrument hors liste (RAPT Pill)", { gravity_instrument: "rapt_pill" }, false],
    ["lecture sans instrument", { brix: 12 }, false],
    ["case sans instrument", { correct: true }, false],
    ["champ hors liste (price_eur)", { ...HYDROMETER, price_eur: 3 }, false],
  ];
  for (const [label, extra, allowed] of cases) {
    it(`${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc(`${EVENTS}/ev-forme`)
          .set(gravity(uidOf("owner"), extra)),
      );
    });
  }

  it("instrument sur une température : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-temp`)
        .set({
          ...event(uidOf("owner"), { gravity_instrument: "digital" }),
          created_at: serverTimestamp(),
        }),
    );
  });

  it("instrument sur une note : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-note`)
        .set({
          ...event(uidOf("owner"), {
            kind: "note",
            measure_type: null,
            value: null,
            note: "Bulles",
            gravity_instrument: "digital",
          }),
          created_at: serverTimestamp(),
        }),
    );
  });

  it("réfractomètre en fermentation : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-fermentation`)
        .set(gravity(uidOf("owner"), { ...REFRACTOMETER, phase: "fermentation", step_key: null })),
    );
  });

  it("correction : flottant devenu réfractomètre, value retirée : autorisé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-c`]: event("brewer-a", {
        measure_type: "gravity",
        value: 1.05,
        ...HYDROMETER,
      }),
    });
    await expectRule(
      true,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-c`)
        .update({ ...REFRACTOMETER, sample_temperature: deleteField() }),
    );
  });

  it("correction : instrument retiré avec ses champs : autorisé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-c`]: event("brewer-a", {
        measure_type: "gravity",
        value: 1.05,
        ...HYDROMETER,
      }),
    });
    await expectRule(
      true,
      db(state.env, "owner").doc(`${EVENTS}/ev-c`).update({
        gravity_instrument: deleteField(),
        sample_temperature: deleteField(),
        correct: deleteField(),
      }),
    );
  });

  it("correction : instrument retiré, température gardée : refusé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-c`]: event("brewer-a", {
        measure_type: "gravity",
        value: 1.05,
        ...HYDROMETER,
      }),
    });
    await expectRule(
      false,
      db(state.env, "owner").doc(`${EVENTS}/ev-c`).update({ gravity_instrument: deleteField() }),
    );
  });

  it("correction : type de mesure changé : refusé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-c`]: event("brewer-a", {
        measure_type: "gravity",
        value: 1.05,
        ...HYDROMETER,
      }),
    });
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-c`)
        .update({ measure_type: "temperature", value: 20, gravity_instrument: deleteField() }),
    );
  });
});

describe("users/{uid}/preferences/measurement — cinq profils", () => {
  const PREF = `users/${uidOf("owner")}/preferences/measurement`;
  const pref = (extra = {}) => ({
    gravity_instrument: "refractometer",
    refractometer_factor: 1.04,
    updated_at: serverTimestamp(),
    ...extra,
  });

  for (const name of FIVE_PROFILES) {
    const owner = name === "owner";
    it(`${name} écrit l'instrument de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await expectRule(owner, db(state.env, name).doc(PREF).set(pref()));
    });
    it(`${name} lit l'instrument de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, {
        [PREF]: { gravity_instrument: "digital", updated_at: CREATED },
      });
      await expectRule(owner, db(state.env, name).doc(PREF).get());
    });
    it(`${name} supprime l'instrument de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, {
        [PREF]: { gravity_instrument: "digital", updated_at: CREATED },
      });
      await expectRule(owner, db(state.env, name).doc(PREF).delete());
    });
  }

  for (const [label, data, allowed] of [
    [
      "flottant sans facteur",
      pref({ gravity_instrument: "hydrometer_20c", refractometer_factor: null }),
      true,
    ],
    ["facteur gardé avec un autre instrument", pref({ gravity_instrument: "digital" }), true],
    ["instrument hors liste", pref({ gravity_instrument: "rapt_pill" }), false],
    ["sans instrument", pref({ gravity_instrument: null }), false],
    ["facteur 0,89", pref({ refractometer_factor: 0.89 }), false],
    ["facteur 1,21", pref({ refractometer_factor: 1.21 }), false],
    ["facteur en texte", pref({ refractometer_factor: "1,04" }), false],
    ["champ hors liste (price_eur)", pref({ price_eur: 3 }), false],
    ["sans updated_at", { gravity_instrument: "digital" }, false],
    ["updated_at du client", pref({ updated_at: CREATED }), false],
  ]) {
    it(`${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, "owner").doc(PREF).set(data));
    });
  }
});
