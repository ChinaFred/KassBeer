// brews/{id}/events/{eventId} : mesures et étapes du jour de brassage.

import { describe, it } from "node:test";
import { db, event, seed, serverTimestamp, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const EVENTS = "brews/b-a/events";
const freshEvent = (owner, extra = {}) => ({
  ...event(owner, extra),
  created_at: serverTimestamp(),
});
const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));

describe("events — cinq profils", () => {
  const read = { anonymous: false, nonMember: false, owner: true, otherBrewer: true, admin: true };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit les événements d'un brassin : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, name).collection(EVENTS).get());
    });
  }

  const create = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: false,
    admin: false,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} ajoute une mesure au brassin de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`${EVENTS}/ev-nouveau`)
          .set(freshEvent(ownerFor(name))),
      );
    });
  }

  const write = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: false,
    admin: false,
  };
  for (const [name, allowed] of Object.entries(write)) {
    it(`${name} corrige une mesure de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, name).doc(`${EVENTS}/ev-a`).update({ value: 67 }));
    });
    it(`${name} supprime une mesure de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, name).doc(`${EVENTS}/ev-a`).delete());
    });
  }
});

describe("events — forme", () => {
  it("début d'étape sans valeur : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-etape`)
        .set(
          freshEvent(uidOf("owner"), {
            kind: "step_started",
            measure_type: null,
            value: null,
          }),
        ),
    );
  });

  it("événement au nom d'un autre : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-nouveau`)
        .set(freshEvent(uidOf("otherBrewer"))),
    );
  });

  it("created_at posée par le client : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-nouveau`)
        .set(event(uidOf("owner"), { created_at: new Date() })),
    );
  });

  it("measured_at absente : refusé", async () => {
    const { measured_at: _omitted, ...data } = freshEvent(uidOf("owner"));
    await expectRule(false, db(state.env, "owner").doc(`${EVENTS}/ev-nouveau`).set(data));
  });

  it("type d'événement inconnu : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-nouveau`)
        .set(freshEvent(uidOf("owner"), { kind: "party" })),
    );
  });

  it("changer le type d'un événement existant : refusé", async () => {
    await expectRule(false, db(state.env, "owner").doc(`${EVENTS}/ev-a`).update({ kind: "note" }));
  });

  it("corriger l'heure de mesure : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner").doc(`${EVENTS}/ev-a`).update({ measured_at: new Date() }),
    );
  });

  it("événement sous un brassin absent : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/absent/events/ev-x")
        .set(freshEvent(uidOf("owner"))),
    );
  });

  it("supprimer son événement après la suppression du brassin : autorisé", async () => {
    await seed(state.env, { "brews/parti/events/ev-o": event(uidOf("owner")) });
    await expectRule(true, db(state.env, "owner").doc("brews/parti/events/ev-o").delete());
  });
});
