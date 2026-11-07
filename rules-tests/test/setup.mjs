// Environnement partagé : un émulateur, des données semées avant chaque test.

import { after, before, beforeEach } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  brew,
  createEnv,
  CREATED,
  equipment,
  event,
  memberDocs,
  recipe,
  seed,
} from "./helpers.mjs";

export const state = { env: null };

/// Documents présents avant chaque test.
export function baseDocs() {
  return {
    ...memberDocs(),
    "recipes/r-a": recipe("brewer-a"),
    "recipes/r-b": recipe("brewer-b", { name: "Stout" }),
    "equipment/e-a": equipment("brewer-a"),
    "brews/b-a": brew("brewer-a"),
    "brews/b-a/events/ev-a": event("brewer-a"),
    "users/brewer-a/prices/malt-pilsner": {
      name: "Pilsner",
      price_eur: 52,
      quantity: 25000,
      unit: "g",
      updated_at: CREATED,
    },
    "users/brewer-a/stock/malt-pilsner": {
      name: "Pilsner",
      quantity: 12000,
      unit: "g",
      updated_at: CREATED,
    },
    "users/brewer-a/brew_costs/b-a": {
      brew_id: "b-a",
      total_eur: 31.4,
      lines: [],
      computed_at: CREATED,
    },
    "error_reports/er-1": {
      uid: "brewer-a",
      feature: "recipes",
      error: "boom",
      created_at: CREATED,
    },
  };
}

export function useEnv() {
  before(async () => {
    state.env = await createEnv();
  });
  after(async () => {
    await state.env.cleanup();
  });
  beforeEach(async () => {
    await state.env.clearFirestore();
    await seed(state.env, baseDocs());
  });
}

/// Attend un succès ou un refus des règles.
export async function expectRule(allowed, promise) {
  if (allowed) {
    await assertSucceeds(promise);
  } else {
    await assertFails(promise);
  }
}
