// v0.1.32 — déroulé en journées (ADR-010, P38) : modèles de processus
// (process_templates/), déroulé figé d'un brassin (brews/{id}.process), choix par
// défaut (users/{uid}/preferences/processes). Cinq profils (P4), plus : process changé
// sur un brassin commencé refusé, process à la création refusé, lot de 60 step_skipped.

import { describe, it } from "node:test";
import {
  brew,
  brewProcess,
  CREATED,
  db,
  deleteField,
  event,
  FIVE_PROFILES,
  fresh,
  nameOf,
  processTemplate,
  seed,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));
const isMemberProfile = (name) => ["owner", "otherBrewer", "admin"].includes(name);
const withName = (name, data) => (nameOf(name) ? { ...data, owner_name: nameOf(name) } : data);
const BREWED_AT = Timestamp.fromDate(new Date("2026-11-22T08:30:00Z"));

const seedTemplate = () =>
  seed(state.env, { "process_templates/t-a": processTemplate(uidOf("owner")) });

describe("process_templates — cinq profils", () => {
  for (const name of FIVE_PROFILES) {
    const member = isMemberProfile(name);
    const owner = name === "owner";

    it(`${name} lit le modèle de brewer-a : ${member ? "autorisé" : "refusé"}`, async () => {
      await seedTemplate();
      await expectRule(member, db(state.env, name).doc("process_templates/t-a").get());
    });

    it(`${name} liste les modèles : ${member ? "autorisé" : "refusé"}`, async () => {
      await seedTemplate();
      await expectRule(member, db(state.env, name).collection("process_templates").get());
    });

    it(`${name} crée son modèle : ${member ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        member,
        db(state.env, name)
          .doc("process_templates/nouveau")
          .set(fresh(withName(name, processTemplate(ownerFor(name))))),
      );
    });

    it(`${name} modifie le modèle de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await seedTemplate();
      await expectRule(
        owner,
        db(state.env, name)
          .doc("process_templates/t-a")
          .update({ name: "Renommé", updated_at: serverTimestamp() }),
      );
    });

    it(`${name} supprime le modèle de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await seedTemplate();
      await expectRule(owner, db(state.env, name).doc("process_templates/t-a").delete());
    });

    if (name !== "anonymous" && name !== "nonMember") {
      it(`${name} crée un modèle au nom de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
        await expectRule(
          owner,
          db(state.env, name)
            .doc("process_templates/usurpe")
            .set(fresh(withName(name, processTemplate(uidOf("owner"))))),
        );
      });
    }
  }
});

describe("process_templates — forme", () => {
  const sessions = processTemplate("x").sessions;
  for (const [label, extra, allowed] of [
    ["modèle complet", {}, true],
    ["sans notes", { notes: null }, true],
    ["5 journées", { sessions: [0, 1, 2, 3, 4].map(() => sessions[0]) }, true],
    ["6 journées", { sessions: [0, 1, 2, 3, 4, 5].map(() => sessions[0]) }, false],
    ["aucune journée", { sessions: [] }, false],
    ["journées en map", { sessions: { a: sessions[0] } }, false],
    ["format_version 2", { format_version: 2 }, false],
    ["format_version en texte", { format_version: "1" }, false],
    ["nom vide", { name: "" }, false],
    ["nom de 121 caractères", { name: "m".repeat(121) }, false],
    ["notes de 10 001 caractères", { notes: "n".repeat(10001) }, false],
    ["champ hors liste (price_eur)", { price_eur: 3 }, false],
    ["champ hors liste (default)", { default: true }, false],
  ]) {
    it(`création : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner")
          .doc("process_templates/forme")
          .set(fresh({ ...processTemplate(uidOf("owner"), extra), owner_name: nameOf("owner") })),
      );
    });
  }

  for (const field of ["format_version", "owner_uid", "name", "sessions"]) {
    it(`création sans ${field} : refusé`, async () => {
      const data = processTemplate(uidOf("owner"));
      delete data[field];
      await expectRule(
        false,
        db(state.env, "owner").doc("process_templates/forme").set(fresh(data)),
      );
    });
  }

  it("création avec created_at du client : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("process_templates/forme")
        .set({ ...processTemplate(uidOf("owner")), updated_at: serverTimestamp() }),
    );
  });

  it("création avec le nom d'un autre brasseur (owner_name) : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("process_templates/forme")
        .set(fresh({ ...processTemplate(uidOf("owner")), owner_name: nameOf("otherBrewer") })),
    );
  });

  it("owner donne son modèle à brewer-b (owner_uid) : refusé", async () => {
    await seedTemplate();
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("process_templates/t-a")
        .update({ owner_uid: uidOf("otherBrewer"), updated_at: serverTimestamp() }),
    );
  });

  it("owner change la date de création : refusé", async () => {
    await seedTemplate();
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("process_templates/t-a")
        .update({ created_at: serverTimestamp(), updated_at: serverTimestamp() }),
    );
  });

  it("owner ajoute une journée hors bornes (6) : refusé", async () => {
    await seedTemplate();
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("process_templates/t-a")
        .update({
          sessions: [0, 1, 2, 3, 4, 5].map(() => sessions[0]),
          updated_at: serverTimestamp(),
        }),
    );
  });
});

describe("brews — déroulé figé (process), cinq profils", () => {
  for (const name of FIVE_PROFILES) {
    const owner = name === "owner";
    const member = isMemberProfile(name);

    it(`${name} écrit le déroulé du brassin prévu de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        owner,
        db(state.env, name)
          .doc("brews/b-a")
          .update({ process: brewProcess(), updated_at: serverTimestamp() }),
      );
    });

    it(`${name} lit le déroulé du brassin de brewer-a : ${member ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, { "brews/b-a": brew(uidOf("owner"), { process: brewProcess() }) });
      await expectRule(member, db(state.env, name).doc("brews/b-a").get());
    });

    it(`${name} crée un brassin avec son déroulé : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("brews/avec-deroule")
          .set(fresh(withName(name, brew(ownerFor(name), { process: brewProcess() })))),
      );
    });

    it(`${name} change le déroulé du brassin commencé de brewer-a : refusé`, async () => {
      await seed(state.env, {
        "brews/b-a": brew(uidOf("owner"), {
          status: "brewing",
          brewed_at: BREWED_AT,
          process: brewProcess(),
        }),
      });
      await expectRule(
        false,
        db(state.env, name)
          .doc("brews/b-a")
          .update({
            process: brewProcess({ template_name: "Autre" }),
            updated_at: serverTimestamp(),
          }),
      );
    });
  }
});

describe("brews — déroulé figé (process), règles du champ", () => {
  const update = (fields) =>
    db(state.env, "owner")
      .doc("brews/b-a")
      .update({ ...fields, updated_at: serverTimestamp() });

  for (const [label, value, allowed] of [
    ["déroulé complet", brewProcess(), true],
    ["déroulé nul", null, true],
    ["sans modèle d'origine", brewProcess({ template_id: null, template_name: null }), true],
    [
      "5 journées",
      brewProcess({ sessions: [0, 1, 2, 3, 4].map(() => brewProcess().sessions[0]) }),
      true,
    ],
    [
      "6 journées",
      brewProcess({ sessions: [0, 1, 2, 3, 4, 5].map(() => brewProcess().sessions[0]) }),
      false,
    ],
    ["aucune journée", brewProcess({ sessions: [] }), false],
    ["journées en map", brewProcess({ sessions: { a: 1 } }), false],
    ["format_version 2", brewProcess({ format_version: 2 }), false],
    ["sans format_version", (({ format_version, ...rest }) => rest)(brewProcess()), false],
    ["template_id de 129 caractères", brewProcess({ template_id: "t".repeat(129) }), false],
    ["template_name de 121 caractères", brewProcess({ template_name: "m".repeat(121) }), false],
    ["champ hors liste (cost_eur)", brewProcess({ cost_eur: 31.4 }), false],
    ["déroulé en texte", "brassage", false],
  ]) {
    it(`brassin prévu : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, update({ process: value }));
    });
  }

  it("brassin prévu : déroulé retiré : autorisé", async () => {
    await seed(state.env, { "brews/b-a": brew(uidOf("owner"), { process: brewProcess() }) });
    await expectRule(true, update({ process: deleteField() }));
  });

  it("brassin prévu : déroulé réécrit en entier : autorisé", async () => {
    await seed(state.env, { "brews/b-a": brew(uidOf("owner"), { process: brewProcess() }) });
    await expectRule(true, update({ process: brewProcess({ template_name: "Autre" }) }));
  });

  it("déroulé et brewed_at dans la même écriture : refusé", async () => {
    await expectRule(
      false,
      update({ process: brewProcess(), status: "brewing", brewed_at: BREWED_AT }),
    );
  });

  it("brassin commencé : déroulé retiré : refusé", async () => {
    await seed(state.env, {
      "brews/b-a": brew(uidOf("owner"), {
        status: "brewing",
        brewed_at: BREWED_AT,
        process: brewProcess(),
      }),
    });
    await expectRule(false, update({ process: deleteField() }));
  });

  it("brassin commencé sans déroulé : déroulé ajouté : refusé", async () => {
    await seed(state.env, {
      "brews/b-a": brew(uidOf("owner"), { status: "fermenting", brewed_at: BREWED_AT }),
    });
    await expectRule(false, update({ process: brewProcess() }));
  });

  it("brassin commencé avec déroulé : statut changé, déroulé inchangé : autorisé", async () => {
    await seed(state.env, {
      "brews/b-a": brew(uidOf("owner"), {
        status: "brewing",
        brewed_at: BREWED_AT,
        process: brewProcess(),
      }),
    });
    await expectRule(true, update({ status: "fermenting" }));
  });

  it("départ d'un brassin prévu avec déroulé (statut et brewed_at) : autorisé", async () => {
    await seed(state.env, { "brews/b-a": brew(uidOf("owner"), { process: brewProcess() }) });
    await expectRule(true, update({ status: "brewing", brewed_at: BREWED_AT }));
  });
});

describe("events — lot de 60 step_skipped", () => {
  // « Terminer la journée » et « Les sauter et commencer » écrivent jusqu'à 60
  // événements dans un WriteBatch ; chaque création lit le brassin (get) et members/
  // (exists). Si ce lot était refusé, l'application le découperait en lots de 10.
  const skipped = (i) => ({
    ...event(uidOf("owner"), {
      kind: "step_skipped",
      step_key: `etape${String(i).padStart(15, "0")}`,
      measure_type: null,
      value: null,
    }),
    created_at: serverTimestamp(),
  });

  it("owner : 60 step_skipped dans un WriteBatch : autorisé", async () => {
    const fs = db(state.env, "owner");
    const batch = fs.batch();
    for (let i = 0; i < 60; i++) {
      batch.set(fs.doc(`brews/b-a/events/saut-${String(i).padStart(2, "0")}`), skipped(i));
    }
    await expectRule(true, batch.commit());
  });

  it("owner : 60 step_skipped et le début d'étape suivant dans un WriteBatch : autorisé", async () => {
    const fs = db(state.env, "owner");
    const batch = fs.batch();
    for (let i = 0; i < 60; i++) {
      batch.set(fs.doc(`brews/b-a/events/saut-${String(i).padStart(2, "0")}`), skipped(i));
    }
    batch.set(fs.doc("brews/b-a/events/debut"), {
      ...skipped(60),
      kind: "step_started",
    });
    await expectRule(true, batch.commit());
  });

  for (const name of ["otherBrewer", "admin"]) {
    it(`${name} : 60 step_skipped sur le brassin de brewer-a : refusé`, async () => {
      const fs = db(state.env, name);
      const batch = fs.batch();
      for (let i = 0; i < 60; i++) {
        batch.set(fs.doc(`brews/b-a/events/saut-${String(i).padStart(2, "0")}`), {
          ...skipped(i),
          owner_uid: uidOf(name),
        });
      }
      await expectRule(false, batch.commit());
    });
  }
});

describe("users/{uid}/preferences/processes — cinq profils", () => {
  const PREF = `users/${uidOf("owner")}/preferences/processes`;
  const pref = (extra = {}) => ({
    default_template_id: "t-a",
    updated_at: serverTimestamp(),
    ...extra,
  });

  for (const name of FIVE_PROFILES) {
    const owner = name === "owner";
    it(`${name} écrit le choix par défaut de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await expectRule(owner, db(state.env, name).doc(PREF).set(pref()));
    });

    it(`${name} lit le choix par défaut de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, { [PREF]: { default_template_id: "t-a", updated_at: CREATED } });
      await expectRule(owner, db(state.env, name).doc(PREF).get());
    });

    it(`${name} supprime le choix par défaut de brewer-a : ${owner ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, { [PREF]: { default_template_id: "t-a", updated_at: CREATED } });
      await expectRule(owner, db(state.env, name).doc(PREF).delete());
    });
  }

  for (const [label, data, allowed] of [
    ["choix nul (chronologie de la recette seule)", pref({ default_template_id: null }), true],
    ["identifiant de 128 caractères", pref({ default_template_id: "t".repeat(128) }), true],
    ["identifiant de 129 caractères", pref({ default_template_id: "t".repeat(129) }), false],
    ["identifiant en nombre", pref({ default_template_id: 12 }), false],
    ["champ hors liste (price_eur)", pref({ price_eur: 3 }), false],
    ["sans updated_at", { default_template_id: "t-a" }, false],
    ["updated_at du client", pref({ updated_at: CREATED }), false],
  ]) {
    it(`owner : ${label} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, "owner").doc(PREF).set(data));
    });
  }

  it("owner écrit un autre document de preferences/ : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`users/${uidOf("owner")}/preferences/autre`)
        .set(pref()),
    );
  });
});
