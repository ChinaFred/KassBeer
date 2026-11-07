// Nombres de premier niveau (optNumber) : finis et bornés à ±1e9. Infinity et NaN
// rendraient un document illisible par l'application (revue securite v0.1.7).

import { describe, it } from "node:test";
import { db, equipment, fresh, recipe, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const CASES = [
  ["Infinity", Infinity, false],
  ["-Infinity", -Infinity, false],
  ["NaN", NaN, false],
  ["1e9", 1e9, false],
  ["-1e9", -1e9, false],
  ["999999999", 999999999, true],
  ["-999999999", -999999999, true],
  ["1,5", 1.5, true],
  ["0", 0, true],
];

describe("nombres finis et bornés", () => {
  for (const [label, value, allowed] of CASES) {
    it(`equipment.trub_loss_l = ${label} : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc(`equipment/nombre-${label}`)
          .set(fresh(equipment(uidOf("owner"), { trub_loss_l: value }))),
      );
    });
    it(`recipes.batch_volume_l = ${label} : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc(`recipes/nombre-${label}`)
          .set(fresh(recipe(uidOf("owner"), { batch_volume_l: value }))),
      );
    });
  }
});

describe("mash_efficiency_pct de 0 à 100", () => {
  for (const [value, allowed] of [
    [-1, false],
    [0, true],
    [72, true],
    [100, true],
    [150, false],
  ]) {
    it(`equipment.mash_efficiency_pct = ${value} : ${allowed ? "accepté" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc(`equipment/rendement-${value}`)
          .set(fresh(equipment(uidOf("owner"), { mash_efficiency_pct: value }))),
      );
    });
  }
});
