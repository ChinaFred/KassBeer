// v0.4 — après le brassage : champs ajoutés à brews/, phase sur events/, statuts jusqu'à
// done et abandoned (P4, cinq profils ; P5, aucun prix ni coût).

import { describe, it } from "node:test";
import {
  brew,
  db,
  deleteField,
  event,
  FIVE_PROFILES,
  fresh,
  seed,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const BOTTLED_AT = Timestamp.fromDate(new Date("2026-11-20T18:30:00Z"));
const BREW = "brews/b-a";
const EVENTS = `${BREW}/events`;
const ownerFor = (name) => (name === "anonymous" ? "anon" : uidOf(name));
const stamped = (changes) => ({ ...changes, updated_at: serverTimestamp() });
const owner = () => db(state.env, "owner").doc(BREW);

const VALID_FIELDS = [
  ["bottled_at", BOTTLED_AT],
  ["bottles_count", 60],
  ["packaged_volume_l", 19.5],
  ["priming_sugar_g", 120],
  ["priming_sugar_name", "Saccharose"],
  ["og_event_id", "ev-a"],
  ["fg_event_id", "ev-a"],
  ["fermenter_volume_event_id", "ev-a"],
  ["sugars_in_wort", true],
];

describe("brews — champs d'après brassage, cinq profils", () => {
  for (const [field, value] of VALID_FIELDS) {
    for (const name of FIVE_PROFILES) {
      const allowed = name === "owner";
      it(`${name} écrit ${field} sur le brassin de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
        await expectRule(
          allowed,
          db(state.env, name)
            .doc(BREW)
            .update(stamped({ [field]: value })),
        );
      });
    }
  }
});

describe("brews — valeurs invalides des champs d'après brassage", () => {
  const INVALID = [
    ["bottled_at textuel", { bottled_at: "2026-11-20" }],
    ["bottled_at nombre", { bottled_at: 12 }],
    ["bottles_count textuel", { bottles_count: "60" }],
    ["packaged_volume_l textuel", { packaged_volume_l: "20" }],
    ["packaged_volume_l trop grand", { packaged_volume_l: 1e10 }],
    ["priming_sugar_g textuel", { priming_sugar_g: "120" }],
    ["priming_sugar_name trop long", { priming_sugar_name: "S".repeat(81) }],
    ["priming_sugar_name nombre", { priming_sugar_name: 5 }],
    ["og_event_id trop long", { og_event_id: "i".repeat(129) }],
    ["fg_event_id nombre", { fg_event_id: 1 }],
    ["fermenter_volume_event_id trop long", { fermenter_volume_event_id: "i".repeat(129) }],
    ["sugars_in_wort textuel", { sugars_in_wort: "oui" }],
    ["sugars_in_wort nombre", { sugars_in_wort: 1 }],
    ["champ de prix inconnu", { bottle_price_eur: 2 }],
    ["champ de coût inconnu", { total_cost_eur: 31 }],
  ];
  for (const [label, changes] of INVALID) {
    it(`${label} : refusé`, async () => {
      await expectRule(false, owner().update(stamped(changes)));
    });
  }

  it("champ facultatif retiré ou nul : autorisé", async () => {
    await expectRule(true, owner().update(stamped({ bottled_at: BOTTLED_AT })));
    await expectRule(
      true,
      owner().update(stamped({ bottled_at: deleteField(), sugars_in_wort: null })),
    );
  });
});

describe("brews — bornes de l'embouteillage", () => {
  const BOUNDS = [
    ["bottles_count", 0, false],
    ["bottles_count", -5, false],
    ["bottles_count", 1.5, false],
    ["bottles_count", 10000, false],
    ["bottles_count", 1, true],
    ["bottles_count", 9999, true],
    ["packaged_volume_l", 0, false],
    ["packaged_volume_l", -1, false],
    ["packaged_volume_l", 1000.5, false],
    ["packaged_volume_l", 1000, true],
    ["packaged_volume_l", 0.5, true],
    ["priming_sugar_g", -1, false],
    ["priming_sugar_g", 100001, false],
    ["priming_sugar_g", 0, true],
    ["priming_sugar_g", 100000, true],
  ];
  for (const [field, value, allowed] of BOUNDS) {
    it(`owner écrit ${field} = ${value} : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, owner().update(stamped({ [field]: value })));
    });
  }

  it("création d'un brassin avec priming_sugar_g textuel : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("brews/nouveau")
        .set(fresh(brew(uidOf("owner"), { priming_sugar_g: "120" }))),
    );
  });
});

describe("events — bornes de value selon measure_type", () => {
  const BOUNDS = [
    ["temperature", -1, false],
    ["temperature", 110.5, false],
    ["temperature", 0, true],
    ["temperature", 110, true],
    ["gravity", 5, false],
    ["gravity", 0.5, false],
    ["gravity", 0.979, false],
    ["gravity", 1.21, false],
    ["gravity", 1.02, true],
    ["gravity", 0.98, true],
    ["gravity", 1.2, true],
    ["volume", 0, false],
    ["volume", -1, false],
    ["volume", 1000.5, false],
    ["volume", 0.5, true],
    ["volume", 1000, true],
    ["ph", -0.1, false],
    ["ph", 14.1, false],
    ["ph", 0, true],
    ["ph", 14, true],
  ];
  const measure = (type, value) => ({
    ...event(uidOf("owner"), { step_key: null, measure_type: type, value }),
    created_at: serverTimestamp(),
  });

  for (const [type, value, allowed] of BOUNDS) {
    const result = allowed ? "autorisé" : "refusé";
    it(`création ${type} = ${value} : ${result}`, async () => {
      await expectRule(
        allowed,
        db(state.env, "owner").doc(`${EVENTS}/ev-borne`).set(measure(type, value)),
      );
    });
    it(`correction ${type} = ${value} : ${result}`, async () => {
      const valid = { temperature: 20, gravity: 1.05, volume: 20, ph: 5 }[type];
      await seed(state.env, {
        [`${EVENTS}/ev-seme`]: event(uidOf("owner"), {
          step_key: null,
          measure_type: type,
          value: valid,
        }),
      });
      await expectRule(allowed, db(state.env, "owner").doc(`${EVENTS}/ev-seme`).update({ value }));
    });
  }
});

describe("events — relevé de fermentation semé, cinq profils", () => {
  const RELEVE = `${EVENTS}/ev-releve`;
  const seedReleve = () =>
    seed(state.env, {
      [RELEVE]: event(uidOf("owner"), {
        step_key: null,
        measure_type: "gravity",
        value: 1.02,
        phase: "fermentation",
      }),
    });

  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    const result = allowed ? "autorisé" : "refusé";
    it(`${name} corrige la valeur du relevé : ${result}`, async () => {
      await seedReleve();
      await expectRule(allowed, db(state.env, name).doc(RELEVE).update({ value: 1.018 }));
    });
    it(`${name} supprime le relevé : ${result}`, async () => {
      await seedReleve();
      await expectRule(allowed, db(state.env, name).doc(RELEVE).delete());
    });
  }

  const REFUSED = [
    ["{phase: null}", { phase: null }],
    ["{phase: deleteField()}", { phase: deleteField() }],
    ['{phase: "garde"}', { phase: "garde" }],
  ];
  for (const [label, changes] of REFUSED) {
    it(`owner écrit ${label} : refusé`, async () => {
      await seedReleve();
      await expectRule(false, db(state.env, "owner").doc(RELEVE).update(changes));
    });
  }
});

describe("brews — statuts d'après brassage", () => {
  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    it(`${name} passe le brassin à abandoned : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(BREW)
          .update(stamped({ status: "abandoned" })),
      );
    });
  }

  for (const [from, to] of [
    ["fermenting", "conditioning"],
    ["conditioning", "done"],
    ["done", "conditioning"],
    ["conditioning", "fermenting"],
    ["fermenting", "brewing"],
    ["abandoned", "conditioning"],
  ]) {
    it(`owner passe de ${from} à ${to} : autorisé`, async () => {
      await seed(state.env, { [BREW]: statusSeed(from) });
      await expectRule(true, owner().update(stamped({ status: to })));
    });
  }

  it("statut inconnu : refusé", async () => {
    await expectRule(false, owner().update(stamped({ status: "bu" })));
  });
});

function statusSeed(status) {
  return { ...briefBrew(), status };
}

function briefBrew() {
  return {
    owner_uid: uidOf("owner"),
    name: "Blonde",
    status: "planned",
    recipe_snapshot: { owner_uid: uidOf("owner"), name: "Blonde" },
    equipment_snapshot: { owner_uid: uidOf("owner"), name: "Cuve", kind: "all_in_one" },
    created_at: Timestamp.fromDate(new Date("2026-11-02T08:00:00Z")),
    updated_at: Timestamp.fromDate(new Date("2026-11-02T08:00:00Z")),
  };
}

describe("brews — embouteillage en un lot", () => {
  it("owner : statut, données et relevé de densité dans un WriteBatch : autorisé", async () => {
    const fs = db(state.env, "owner");
    const batch = fs.batch();
    batch.update(
      fs.doc(BREW),
      stamped({ status: "conditioning", bottled_at: BOTTLED_AT, bottles_count: 60 }),
    );
    batch.set(fs.doc(`${EVENTS}/ev-densite-finale`), {
      ...event(uidOf("owner"), {
        step_key: null,
        measure_type: "gravity",
        value: 1.012,
        measured_at: BOTTLED_AT,
        phase: "fermentation",
      }),
      created_at: serverTimestamp(),
    });
    await expectRule(true, batch.commit());
  });

  for (const name of ["otherBrewer", "admin"]) {
    it(`${name} : lot refusé`, async () => {
      const fs = db(state.env, name);
      const batch = fs.batch();
      batch.update(fs.doc(BREW), stamped({ status: "conditioning", bottled_at: BOTTLED_AT }));
      await expectRule(false, batch.commit());
    });
  }
});

describe("events — phase, cinq profils", () => {
  const measure = (name, extra = {}) => ({
    ...event(ownerFor(name), {
      step_key: null,
      measure_type: "gravity",
      value: 1.02,
      phase: "fermentation",
      ...extra,
    }),
    created_at: serverTimestamp(),
  });

  for (const name of FIVE_PROFILES) {
    const allowed = name === "owner";
    it(`${name} ajoute une densité de fermentation : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, name).doc(`${EVENTS}/ev-releve`).set(measure(name)));
    });
    it(`${name} ajoute une note de fermentation : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`${EVENTS}/ev-note`)
          .set(
            measure(name, {
              kind: "note",
              measure_type: null,
              value: null,
              note: "Bonne odeur",
            }),
          ),
      );
    });
  }

  it("phase nulle sur une mesure : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-sans`)
        .set(measure("owner", { phase: null })),
    );
  });

  it("phase inconnue : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-autre`)
        .set(measure("owner", { phase: "garde" })),
    );
  });

  it("phase sur un début d'étape : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`${EVENTS}/ev-etape`)
        .set(
          measure("owner", {
            kind: "step_started",
            step_key: "etape-1",
            measure_type: null,
            value: null,
          }),
        ),
    );
  });

  it("changer la phase d'un événement existant : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner").doc(`${EVENTS}/ev-a`).update({ phase: "fermentation" }),
    );
  });

  it("corriger la valeur d'un relevé sans toucher la phase : autorisé", async () => {
    await seed(state.env, {
      [`${EVENTS}/ev-rel`]: event(uidOf("owner"), {
        step_key: null,
        measure_type: "gravity",
        value: 1.02,
        phase: "fermentation",
      }),
    });
    await expectRule(true, db(state.env, "owner").doc(`${EVENTS}/ev-rel`).update({ value: 1.018 }));
  });
});
