// brews/{id}/events/{eventId} : mesures et étapes du jour de brassage.

import { describe, it } from "node:test";
import {
  brew,
  db,
  deleteField,
  event,
  FIVE_PROFILES,
  seed,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
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

// Forme selon kind (v0.3). Un exemple valide par kind, puis des formes refusées.
const VALID_BY_KIND = {
  step_started: { kind: "step_started", step_key: "etape-1", measure_type: null, value: null },
  step_ended: { kind: "step_ended", step_key: "etape-1", measure_type: null, value: null },
  step_skipped: { kind: "step_skipped", step_key: "etape-1", measure_type: null, value: null },
  measurement: { kind: "measurement", step_key: "etape-1", measure_type: "gravity", value: 1.0579 },
  note: { kind: "note", step_key: null, measure_type: null, value: null, note: "Odeur de céréale" },
};

describe("events — chaque kind, cinq profils", () => {
  for (const [kind, extra] of Object.entries(VALID_BY_KIND)) {
    for (const name of FIVE_PROFILES) {
      const allowed = name === "owner";
      it(`${name} écrit un événement ${kind} sur le brassin de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(
          allowed,
          db(state.env, name)
            .doc(`${EVENTS}/ev-${kind}`)
            .set(freshEvent(ownerFor(name), extra)),
        );
      });
    }
  }

  for (const name of FIVE_PROFILES) {
    it(`${name} écrit un événement sous un brassin inexistant : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("brews/absent/events/ev-x")
          .set(freshEvent(ownerFor(name), VALID_BY_KIND.step_started)),
      );
    });
  }

  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    it(`${name} retire un saut d'étape de brewer-a (« Ne plus sauter ») : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, {
        [`${EVENTS}/ev-saut`]: event(uidOf("owner"), VALID_BY_KIND.step_skipped),
      });
      await expectRule(allowed, db(state.env, name).doc(`${EVENTS}/ev-saut`).delete());
    });
  }
});

describe("events — forme selon kind", () => {
  const write = (extra) =>
    db(state.env, "owner")
      .doc(`${EVENTS}/ev-forme`)
      .set(freshEvent(uidOf("owner"), extra));
  const without = (base, key) => {
    const { [key]: _omitted, ...rest } = base;
    return rest;
  };
  const eventWithout = (base, key) => {
    const { [key]: _omitted, ...rest } = freshEvent(uidOf("owner"), base);
    return rest;
  };

  const ACCEPTED = [
    ["mesure sans étape (step_key nul)", { ...VALID_BY_KIND.measurement, step_key: null }],
    ["note sur une étape", { ...VALID_BY_KIND.note, step_key: "etape-1" }],
    ["mesure avec note", { ...VALID_BY_KIND.measurement, note: "Après brassage" }],
    ["note de 2 000 caractères", { ...VALID_BY_KIND.note, note: "n".repeat(2000) }],
    ["température", { ...VALID_BY_KIND.measurement, measure_type: "temperature", value: 67.5 }],
    ["volume", { ...VALID_BY_KIND.measurement, measure_type: "volume", value: 23 }],
    ["pH", { ...VALID_BY_KIND.measurement, measure_type: "ph", value: 5.4 }],
    ["step_key de 100 caractères", { ...VALID_BY_KIND.step_started, step_key: "k".repeat(100) }],
  ];
  for (const [label, extra] of ACCEPTED) {
    it(`${label} : autorisé`, async () => {
      await expectRule(true, write(extra));
    });
  }

  const REFUSED = [];
  for (const kind of ["step_started", "step_ended", "step_skipped"]) {
    const base = VALID_BY_KIND[kind];
    REFUSED.push(
      [`${kind} sans étape (step_key nul)`, { ...base, step_key: null }],
      [`${kind} avec une valeur`, { ...base, value: 66 }],
      [`${kind} avec un type de mesure`, { ...base, measure_type: "temperature" }],
      [`${kind} avec step_key non textuel`, { ...base, step_key: 12 }],
      [`${kind} avec step_key vide`, { ...base, step_key: "" }],
    );
  }
  REFUSED.push(
    ["mesure avec step_key vide", { ...VALID_BY_KIND.measurement, step_key: "" }],
    ["note avec step_key vide", { ...VALID_BY_KIND.note, step_key: "" }],
    ["step_key de 101 caractères", { ...VALID_BY_KIND.step_started, step_key: "k".repeat(101) }],
    ["mesure sans type", { ...VALID_BY_KIND.measurement, measure_type: null }],
    ["mesure de type inconnu", { ...VALID_BY_KIND.measurement, measure_type: "pression" }],
    ["mesure sans valeur", { ...VALID_BY_KIND.measurement, value: null }],
    ["mesure en texte", { ...VALID_BY_KIND.measurement, value: "1057,9" }],
    ["mesure Infinity", { ...VALID_BY_KIND.measurement, value: Infinity }],
    ["mesure NaN", { ...VALID_BY_KIND.measurement, value: NaN }],
    ["mesure 999 999 999", { ...VALID_BY_KIND.measurement, value: 999999999 }],
    ["mesure 1e9", { ...VALID_BY_KIND.measurement, value: 1e9 }],
    ["mesure -1e9", { ...VALID_BY_KIND.measurement, value: -1e9 }],
    ["note sans texte (null)", { ...VALID_BY_KIND.note, note: null }],
    ["note vide", { ...VALID_BY_KIND.note, note: "" }],
    ["note de 2 001 caractères", { ...VALID_BY_KIND.note, note: "n".repeat(2001) }],
    ["note avec une valeur", { ...VALID_BY_KIND.note, value: 3 }],
    ["note avec un type de mesure", { ...VALID_BY_KIND.note, measure_type: "ph" }],
  );
  for (const [label, extra] of REFUSED) {
    it(`${label} : refusé`, async () => {
      await expectRule(false, write(extra));
    });
  }

  for (const kind of ["step_started", "step_ended", "step_skipped"]) {
    it(`${kind} sans champ step_key : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, "owner")
          .doc(`${EVENTS}/ev-forme`)
          .set(eventWithout(VALID_BY_KIND[kind], "step_key")),
      );
    });
  }

  it("mesure sans champ value : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-forme`)
        .set(eventWithout(VALID_BY_KIND.measurement, "value")),
    );
  });

  it("note sans champ note : refusé", async () => {
    await expectRule(false, write(without(VALID_BY_KIND.note, "note")));
  });

  it("note sans champs de mesure ni d'étape : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-forme`)
        .set({
          owner_uid: uidOf("owner"),
          kind: "note",
          note: "Odeur de céréale",
          measured_at: new Date(),
          created_at: serverTimestamp(),
        }),
    );
  });

  it("corriger la valeur d'une mesure en null : refusé", async () => {
    await expectRule(false, db(state.env, "owner").doc(`${EVENTS}/ev-a`).update({ value: null }));
  });

  it("ajouter une valeur à un début d'étape existant : refusé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-debut`]: event(uidOf("owner"), VALID_BY_KIND.step_started),
    });
    await expectRule(false, db(state.env, "owner").doc(`${EVENTS}/ev-debut`).update({ value: 12 }));
  });

  it("corriger l'heure d'un début d'étape : autorisé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-debut`]: event(uidOf("owner"), VALID_BY_KIND.step_started),
    });
    await expectRule(
      true,
      db(state.env, "owner").doc(`${EVENTS}/ev-debut`).update({ measured_at: new Date() }),
    );
  });
});

describe("events — correction par le propriétaire : champs figés", () => {
  const update = (changes) => db(state.env, "owner").doc(`${EVENTS}/ev-a`).update(changes);

  const REFUSED = [
    ["changer step_key", { step_key: "autre-etape" }],
    ["changer measure_type", { measure_type: "gravity" }],
    ["changer owner_uid", { owner_uid: uidOf("otherBrewer") }],
    ["changer created_at", { created_at: new Date() }],
    ["ajouter un champ inconnu", { lieu: "garage" }],
    ["measured_at nul", { measured_at: null }],
    ["measured_at textuel", { measured_at: "2026-11-08T09:15:00Z" }],
    ["retirer measured_at", { measured_at: deleteField() }],
  ];
  for (const [label, changes] of REFUSED) {
    it(`${label} : refusé`, async () => {
      await expectRule(false, update(changes));
    });
  }
});

// Brassin et événement à l'uid du compte non invité : seule la condition isMember()
// le refuse. Sans ces cas, retirer isMember() laisserait les tests verts.
describe("events — compte non invité, sur son propre uid", () => {
  const STRANGER_EVENTS = "brews/b-stranger/events";
  const seedStranger = () =>
    seed(state.env, {
      "brews/b-stranger": brew(uidOf("nonMember")),
      [`${STRANGER_EVENTS}/ev-stranger`]: event(uidOf("nonMember")),
    });

  it("nonMember crée un événement sur son brassin : refusé", async () => {
    await seedStranger();
    await expectRule(
      false,
      db(state.env, "nonMember")
        .doc(`${STRANGER_EVENTS}/ev-nouveau`)
        .set(freshEvent(uidOf("nonMember"))),
    );
  });

  it("nonMember corrige son événement : refusé", async () => {
    await seedStranger();
    await expectRule(
      false,
      db(state.env, "nonMember").doc(`${STRANGER_EVENTS}/ev-stranger`).update({ value: 67 }),
    );
  });

  it("nonMember supprime son événement : refusé", async () => {
    await seedStranger();
    await expectRule(
      false,
      db(state.env, "nonMember").doc(`${STRANGER_EVENTS}/ev-stranger`).delete(),
    );
  });
});

// Heures estimées à l'import d'une fiche (v0.1.69) : time_estimated et
// date_estimated, booléens vrais seulement ; seul passage permis, vrai → absent,
// avec measured_at changé.
describe("events — heure estimée, cinq profils", () => {
  const ESTIMEE = `${EVENTS}/ev-estimee`;
  const seedEstimee = (extra = {}) =>
    seed(state.env, {
      [ESTIMEE]: event("brewer-a", {
        time_estimated: true,
        phase: "fermentation",
        step_key: null,
        measure_type: "gravity",
        value: 1.023,
        date_estimated: true,
        ...extra,
      }),
    });
  const create = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: false,
    admin: false,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} crée une mesure à heure estimée sur le brassin de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`${EVENTS}/ev-nouveau`)
          .set(freshEvent(ownerFor(name), { time_estimated: true })),
      );
    });
    it(`${name} corrige l'heure d'une mesure estimée de brewer-a et retire l'estimation : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedEstimee();
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(ESTIMEE)
          .update({
            measured_at: Timestamp.fromDate(new Date("2024-08-10T10:00:00Z")),
            time_estimated: deleteField(),
            date_estimated: deleteField(),
          }),
      );
    });
  }
  const read = { anonymous: false, nonMember: false, owner: true, otherBrewer: true, admin: true };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit une mesure estimée de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedEstimee();
      await expectRule(allowed, db(state.env, name).doc(ESTIMEE).get());
    });
  }
});

describe("events — heure estimée, forme et passages", () => {
  const ESTIMEE = `${EVENTS}/ev-estimee`;
  const owner = () => db(state.env, "owner");
  const at = (iso) => Timestamp.fromDate(new Date(iso));
  const seedEstimee = (extra = {}) =>
    seed(state.env, { [ESTIMEE]: event("brewer-a", { time_estimated: true, ...extra }) });

  const permis = [
    [
      "début d'étape estimé",
      { kind: "step_started", measure_type: null, value: null, time_estimated: true },
    ],
    ["mesure estimée", { time_estimated: true }],
    [
      "note estimée",
      {
        kind: "note",
        note: "Fermentation lente.",
        measure_type: null,
        value: null,
        step_key: null,
        phase: "fermentation",
        time_estimated: true,
      },
    ],
    [
      "relevé J+28 : date et heure estimées",
      {
        step_key: null,
        measure_type: "gravity",
        value: 1.023,
        phase: "fermentation",
        time_estimated: true,
        date_estimated: true,
      },
    ],
  ];
  for (const [label, extra] of permis) {
    it(`${label} : autorisé`, async () => {
      await expectRule(
        true,
        owner()
          .doc(`${EVENTS}/ev-forme`)
          .set(freshEvent(uidOf("owner"), extra)),
      );
    });
  }

  const refuses = [
    ["time_estimated à false", { time_estimated: false }],
    ["time_estimated en texte", { time_estimated: "oui" }],
    [
      "fin d'étape estimée",
      { kind: "step_ended", measure_type: null, value: null, time_estimated: true },
    ],
    [
      "saut d'étape estimé",
      { kind: "step_skipped", measure_type: null, value: null, time_estimated: true },
    ],
    ["date_estimated sans time_estimated", { date_estimated: true }],
    [
      "date_estimated sur un début d'étape",
      {
        kind: "step_started",
        measure_type: null,
        value: null,
        time_estimated: true,
        date_estimated: true,
      },
    ],
    ["date_estimated à false", { time_estimated: true, date_estimated: false }],
  ];
  for (const [label, extra] of refuses) {
    it(`${label} : refusé`, async () => {
      await expectRule(
        false,
        owner()
          .doc(`${EVENTS}/ev-forme`)
          .set(freshEvent(uidOf("owner"), extra)),
      );
    });
  }

  it("retirer time_estimated sans changer l'heure : refusé", async () => {
    await seedEstimee();
    await expectRule(false, owner().doc(ESTIMEE).update({ time_estimated: deleteField() }));
  });

  it("changer l'heure en gardant time_estimated : autorisé", async () => {
    await seedEstimee();
    await expectRule(
      true,
      owner()
        .doc(ESTIMEE)
        .update({ measured_at: at("2026-11-03T09:30:00Z") }),
    );
  });

  it("corriger la valeur d'une mesure estimée : autorisé, estimation gardée", async () => {
    await seedEstimee();
    await expectRule(true, owner().doc(ESTIMEE).update({ value: 67 }));
  });

  it("ajouter time_estimated à une heure notée, même avec l'heure changée : refusé", async () => {
    await expectRule(
      false,
      owner()
        .doc(`${EVENTS}/ev-a`)
        .update({ time_estimated: true, measured_at: at("2026-11-03T09:30:00Z") }),
    );
  });

  it("retirer time_estimated en gardant date_estimated : refusé", async () => {
    await seedEstimee({
      step_key: null,
      measure_type: "gravity",
      value: 1.023,
      phase: "fermentation",
      date_estimated: true,
    });
    await expectRule(
      false,
      owner()
        .doc(ESTIMEE)
        .update({ time_estimated: deleteField(), measured_at: at("2026-11-03T09:30:00Z") }),
    );
  });

  it("retirer l'estimation avec l'heure changée : autorisé", async () => {
    await seedEstimee();
    await expectRule(
      true,
      owner()
        .doc(ESTIMEE)
        .update({ time_estimated: deleteField(), measured_at: at("2026-11-03T09:30:00Z") }),
    );
  });
});
