// error_reports/ : journal d'erreurs (P13).

import { describe, it } from "node:test";
import { db, serverTimestamp, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const report = (uid, extra = {}) => ({
  uid,
  feature: "brew_day",
  error: "StateError: boom",
  stack_trace: "#0 main (file.dart:1)",
  context: "step=mash-1",
  app_version: "0.1.1+2",
  platform: "android",
  created_at: serverTimestamp(),
  ...extra,
});

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));

describe("error_reports — cinq profils", () => {
  const create = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: true,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} crée un rapport à son uid : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .collection("error_reports")
          .add(report(ownerFor(name))),
      );
    });
  }

  const read = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(read)) {
    const verdict = allowed ? "autorisé" : "refusé";
    it(`${name} lit un rapport : ${verdict}`, async () => {
      await expectRule(allowed, db(state.env, name).doc("error_reports/er-1").get());
    });
    it(`${name} liste les rapports : ${verdict}`, async () => {
      await expectRule(allowed, db(state.env, name).collection("error_reports").get());
    });
    it(`${name} supprime un rapport : ${verdict}`, async () => {
      await expectRule(allowed, db(state.env, name).doc("error_reports/er-1").delete());
    });
  }

  for (const name of ["owner", "admin"]) {
    it(`${name} modifie un rapport : refusé`, async () => {
      await expectRule(false, db(state.env, name).doc("error_reports/er-1").update({ error: "x" }));
    });
  }
});

describe("error_reports — forme", () => {
  const minimal = { uid: "brewer-a", feature: "recipes", error: "", created_at: serverTimestamp() };
  it("rapport minimal (uid, feature, error, created_at) : autorisé", async () => {
    await expectRule(true, db(state.env, "owner").collection("error_reports").add(minimal));
  });

  const invalid = {
    "uid d'un autre compte": { uid: "brewer-b" },
    "champ hors liste (email)": { email: "brewer.a@example.com" },
    "champ hors liste (price_eur)": { price_eur: 3 },
    "feature vide": { feature: "" },
    "feature de 101 caractères": { feature: "x".repeat(101) },
    "error de 2 001 caractères": { error: "x".repeat(2001) },
    "stack_trace de 8 001 caractères": { stack_trace: "x".repeat(8001) },
    "context de 2 001 caractères": { context: "x".repeat(2001) },
    "context en objet": { context: { price_eur: 3 } },
    "app_version de 41 caractères": { app_version: "x".repeat(41) },
    "plateforme inconnue": { platform: "ios" },
    "created_at posée par le client": { created_at: new Date() },
  };
  for (const [label, extra] of Object.entries(invalid)) {
    it(`${label} : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .collection("error_reports")
          .add(report(uidOf("owner"), extra)),
      );
    });
  }

  it("bornes atteintes sans les dépasser : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .collection("error_reports")
        .add(
          report(uidOf("owner"), {
            feature: "x".repeat(100),
            error: "x".repeat(2000),
            stack_trace: "x".repeat(8000),
            context: "x".repeat(2000),
          }),
        ),
    );
  });

  it("champ obligatoire absent (feature) : refusé", async () => {
    const { feature: _omitted, ...data } = report(uidOf("owner"));
    await expectRule(false, db(state.env, "owner").collection("error_reports").add(data));
  });
});
