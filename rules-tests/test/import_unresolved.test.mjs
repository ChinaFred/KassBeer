// Noms non résolus d'un import (ADR-005, E6 ; P19) : un membre crée
// import_unresolved/{empreinte} à count 1 (source import), l'empreinte étant le
// SHA-256 de « import|nature|key » (key : nom normalisé), vérifié par les règles ;
// puis un set fusionné fait monter le compte d'un, le nom pouvant changer de graphie.
// nature, key et source ne changent pas ; un document du script (source diydog,
// autre identifiant, sans key) ne se met pas à jour par un membre. Lecture par
// l'admin seul, aucune suppression. Cinq profils de P4, connexions non conformes de
// P11, et cas refusés : champ en trop, mauvaise empreinte, key modifiée, compte qui
// saute, autre source ou nature, identifiant invalide.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { beforeEach, describe, it } from "node:test";
import { db, FIVE_PROFILES, increment, seed, serverTimestamp, Timestamp } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

/// Empreinte d'un nom signalé par un import, celle que calcule l'application.
const empreinte = (nature, key) =>
  createHash("sha256").update(`import|${nature}|${key}`, "utf8").digest("hex");

const NOUVEAU = empreinte("hop", "houblon-nouveau");
const IMPORT = empreinte("hop", "houblon-inconnu");
const SCRIPT = createHash("sha256").update("fermentable|malt-inconnu").digest("hex");

const MEMBRES = ["owner", "otherBrewer", "admin"];

/// Signalement tel que l'écrit l'application (set fusionné), pour IMPORT.
const signalement = (extra = {}) => ({
  nature: "hop",
  key: "houblon-inconnu",
  name: "Houblon Inconnu",
  source: "import",
  count: increment(1),
  updated_at: serverTimestamp(),
  ...extra,
});

/// Signalement d'un nom encore jamais vu, pour NOUVEAU.
const nouveau = (extra = {}) =>
  signalement({ key: "houblon-nouveau", name: "Houblon Nouveau", ...extra });

/// Fusion de [data] dans le document [id], vu par [profil].
const fusion = (profil, id, data) =>
  db(state.env, profil).doc(`import_unresolved/${id}`).set(data, { merge: true });

beforeEach(async () => {
  await seed(state.env, {
    [`import_unresolved/${SCRIPT}`]: {
      nature: "fermentable",
      name: "Malt Inconnu",
      source: "diydog",
      count: 3,
      updated_at: Timestamp.fromDate(new Date("2026-11-11T12:49:00Z")),
    },
    [`import_unresolved/${IMPORT}`]: {
      nature: "hop",
      key: "houblon-inconnu",
      name: "Houblon Inconnu",
      source: "import",
      count: 1,
      updated_at: Timestamp.fromDate(new Date("2026-11-11T13:00:00Z")),
    },
  });
});

/// Document [id], lu hors règles.
async function lire(id) {
  let data;
  await state.env.withSecurityRulesDisabled(async (ctx) => {
    data = (await ctx.firestore().doc(`import_unresolved/${id}`).get()).data();
  });
  return data;
}

describe("import_unresolved : écriture par un membre (E6)", () => {
  for (const profil of FIVE_PROFILES) {
    const permis = MEMBRES.includes(profil);
    it(`${profil} ${permis ? "crée" : "ne crée pas"} un nom non résolu, bonne empreinte`, async () => {
      await expectRule(permis, fusion(profil, NOUVEAU, nouveau()));
      if (permis) assert.equal((await lire(NOUVEAU)).count, 1);
    });

    it(`${profil} ${permis ? "fait" : "ne fait pas"} monter le compte d'un import`, async () => {
      await expectRule(permis, fusion(profil, IMPORT, signalement()));
      if (permis) assert.equal((await lire(IMPORT)).count, 2);
    });

    it(`${profil} : seconde fusion d'une autre graphie ${permis ? "acceptée" : "refusée"}`, async () => {
      await expectRule(permis, fusion(profil, IMPORT, signalement({ name: "HOUBLON inconnu" })));
      if (permis) {
        const doc = await lire(IMPORT);
        assert.equal(doc.count, 2);
        assert.equal(doc.name, "HOUBLON inconnu");
        assert.equal(doc.key, "houblon-inconnu");
        assert.equal(doc.source, "import");
      }
    });

    it(`${profil} ne met pas à jour un document du script`, async () => {
      await expectRule(
        false,
        fusion(
          profil,
          SCRIPT,
          signalement({ nature: "fermentable", key: "malt-inconnu", name: "Malt Inconnu" }),
        ),
      );
      await expectRule(
        false,
        db(state.env, profil)
          .doc(`import_unresolved/${SCRIPT}`)
          .update({ count: increment(1), updated_at: serverTimestamp() }),
      );
      assert.equal((await lire(SCRIPT)).count, 3);
    });

    it(`${profil} ne supprime pas`, async () => {
      const fs = db(state.env, profil);
      await expectRule(false, fs.doc(`import_unresolved/${IMPORT}`).delete());
      await expectRule(false, fs.doc(`import_unresolved/${SCRIPT}`).delete());
    });
  }

  for (const profil of ["unverified", "passwordProvider"]) {
    it(`connexion non conforme (${profil}) : aucune écriture (P11)`, async () => {
      await expectRule(false, fusion(profil, NOUVEAU, nouveau()));
      await expectRule(false, fusion(profil, IMPORT, signalement()));
    });
  }
});

describe("import_unresolved : cas refusés", () => {
  const creer = (data, id = NOUVEAU) =>
    db(state.env, "owner").doc(`import_unresolved/${id}`).set(data);

  it("création conforme écrite sans fusion : acceptée", async () => {
    await expectRule(true, creer({ ...nouveau(), count: 1 }));
  });

  it("mauvaise empreinte : refusée", async () => {
    // key d'un autre nom, autre nature, empreinte de l'ingestion, empreinte arbitraire.
    await expectRule(false, creer(nouveau({ key: "autre-houblon" })));
    await expectRule(false, creer(nouveau({ nature: "misc" })));
    await expectRule(
      false,
      creer(nouveau(), createHash("sha256").update("hop|houblon-nouveau").digest("hex")),
    );
    await expectRule(false, creer(nouveau(), "d".repeat(64)));
  });

  it("key hors de la forme normalisée : refusée, même avec son empreinte", async () => {
    for (const key of [
      "Houblon Nouveau",
      "houblon nouveau",
      "-houblon",
      "houblon-",
      "houblon--nouveau",
      "houblon_nouveau",
      "éte",
    ]) {
      await expectRule(false, creer(nouveau({ key }), empreinte("hop", key)));
    }
    await expectRule(true, creer(nouveau({ key: "houblon-nouveau" }), NOUVEAU));
  });

  it("key vide, trop longue ou non textuelle : refusée", async () => {
    await expectRule(false, creer(nouveau({ key: "" }), empreinte("hop", "")));
    const longue = "k".repeat(101);
    await expectRule(false, creer(nouveau({ key: longue }), empreinte("hop", longue)));
    await expectRule(false, creer(nouveau({ key: 42 })));
    const limite = "k".repeat(100);
    await expectRule(true, creer(nouveau({ key: limite }), empreinte("hop", limite)));
  });

  it("champ en trop (uid, e-mail, fichier) : refusée", async () => {
    for (const extra of [{ uid: "brewer-a" }, { email: "x@example.com" }, { file: "a.xml" }]) {
      await expectRule(false, creer(nouveau(extra)));
    }
  });

  it("champ manquant : refusée", async () => {
    for (const cle of ["nature", "key", "name", "source", "count", "updated_at"]) {
      const data = nouveau();
      delete data[cle];
      await expectRule(false, creer(data));
    }
  });

  it("compte qui ne part pas de 1 : refusée", async () => {
    await expectRule(false, creer({ ...nouveau(), count: 2 }));
    await expectRule(false, creer({ ...nouveau(), count: 0 }));
    await expectRule(false, creer({ ...nouveau(), count: 1.5 }));
  });

  it("autre source : refusée", async () => {
    await expectRule(false, creer(nouveau({ source: "diydog" })));
    await expectRule(false, creer(nouveau({ source: "autre" })));
  });

  it("nature inconnue, nom vide ou trop long : refusée", async () => {
    await expectRule(
      false,
      creer(nouveau({ nature: "style" }), empreinte("style", "houblon-nouveau")),
    );
    await expectRule(false, creer(nouveau({ name: "" })));
    await expectRule(false, creer(nouveau({ name: 42 })));
    await expectRule(false, creer(nouveau({ name: "N".repeat(121) })));
    await expectRule(true, creer(nouveau({ name: "N".repeat(120) })));
  });

  it("heure posée par le client : refusée", async () => {
    await expectRule(
      false,
      creer(nouveau({ updated_at: Timestamp.fromDate(new Date("2026-11-11T00:00:00Z")) })),
    );
  });

  it("identifiant non hexadécimal ou d'une autre longueur : refusée", async () => {
    for (const id of ["nouveau", NOUVEAU.toUpperCase(), NOUVEAU.slice(1), `${NOUVEAU}a`]) {
      await expectRule(false, creer(nouveau(), id));
    }
  });

  it("mise à jour : compte + 2, compte fixé, compte inchangé, heure absente : refusée", async () => {
    await expectRule(false, fusion("owner", IMPORT, signalement({ count: increment(2) })));
    await expectRule(false, fusion("owner", IMPORT, signalement({ count: 5 })));
    const doc = db(state.env, "owner").doc(`import_unresolved/${IMPORT}`);
    await expectRule(false, doc.update({ updated_at: serverTimestamp() }));
    await expectRule(false, doc.update({ count: increment(1) }));
  });

  it("mise à jour : key, source ou nature changées, nom vide ou trop long, champ ajouté : refusée", async () => {
    for (const extra of [
      { key: "autre-houblon" },
      { source: "diydog" },
      { nature: "misc" },
      { name: "" },
      { name: "N".repeat(121) },
      { uid: "brewer-a" },
    ]) {
      await expectRule(false, fusion("owner", IMPORT, signalement(extra)));
    }
  });
});
