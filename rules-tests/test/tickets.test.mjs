// tickets/, ticket_quotas/, ticket_status/ : tickets des membres (ADR-006, P23, P4, P11).

import { describe, it } from "node:test";
import { CREATED, db, memberId, seed, serverTimestamp, Timestamp, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

/// Ticket tel que l'application le crée, pour le persona `name`.
const ticket = (name, extra = {}) => ({
  ...base(name),
  ...extra,
});

const base = (name) => ({
  type: "bug",
  title: "Le minuteur saute",
  description: "Le minuteur de l'ébullition repart à zéro.",
  screen: "/brassins/:id/jour",
  app_version: "0.2.0+21",
  platform: "android",
  author_uid: name === "anonymous" ? "anon" : uidOf(name),
  author_email: name === "anonymous" ? "anon@example.com" : memberId(name),
  created_at: serverTimestamp(),
  status: "pending",
});

/// Ticket de brewer-a déjà publié, avec ses champs serveur.
const published = {
  type: "bug",
  title: "Le minuteur saute",
  description: "Le minuteur de l'ébullition repart à zéro.",
  screen: "/brassins/:id/jour",
  app_version: "0.2.0+21",
  platform: "android",
  author_uid: "brewer-a",
  author_email: "brewer.a@example.com",
  created_at: CREATED,
  status: "received",
  github_issue_number: 12,
  github_url: "https://github.com/ChinaFred/KassBeer/issues/12",
  status_changed_at: CREATED,
};

async function seedTickets() {
  await seed(state.env, {
    "tickets/t-a": published,
    "ticket_quotas/group_20261110": { count: 3, day: "20261110", expires_at: CREATED },
    "ticket_status/github": { token_invalid_since: null, token_expires_at: CREATED },
  });
}

describe("tickets — cinq profils (P4)", () => {
  const create = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: true,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} crée un ticket à son nom : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, name).doc("tickets/nouveau").set(ticket(name)));
    });
  }

  const read = { anonymous: false, nonMember: false, owner: true, otherBrewer: false, admin: true };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit le ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await expectRule(allowed, db(state.env, name).doc("tickets/t-a").get());
    });
  }

  it("owner liste ses tickets (requête author_uid, created_at desc) : autorisé", async () => {
    await seedTickets();
    await expectRule(
      true,
      db(state.env, "owner")
        .collection("tickets")
        .where("author_uid", "==", "brewer-a")
        .orderBy("created_at", "desc")
        .get(),
    );
  });

  for (const name of ["owner", "otherBrewer"]) {
    it(`${name} liste tous les tickets sans filtre : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, name).collection("tickets").get());
    });
  }

  it("otherBrewer liste les tickets de brewer-a : refusé", async () => {
    await seedTickets();
    await expectRule(
      false,
      db(state.env, "otherBrewer")
        .collection("tickets")
        .where("author_uid", "==", "brewer-a")
        .get(),
    );
  });

  it("admin liste tous les tickets : autorisé", async () => {
    await seedTickets();
    await expectRule(true, db(state.env, "admin").collection("tickets").get());
  });

  const markSeen = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: false,
    admin: false,
  };
  for (const [name, allowed] of Object.entries(markSeen)) {
    it(`${name} marque le suivi lu sur le ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await expectRule(
        allowed,
        db(state.env, name).doc("tickets/t-a").update({ seen_by_author_at: serverTimestamp() }),
      );
    });
  }

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} supprime le ticket de brewer-a : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, name).doc("tickets/t-a").delete());
    });
  }
});

describe("tickets — P11", () => {
  for (const name of ["unverified", "passwordProvider"]) {
    it(`${name}, invité, crée un ticket : refusé`, async () => {
      await expectRule(false, db(state.env, name).doc("tickets/nouveau").set(ticket(name)));
    });
  }

  it("adresse du jeton en majuscules : author_email en minuscules autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "mixedCase")
        .doc("tickets/nouveau")
        .set(ticket("mixedCase", { author_email: "mixed.case@example.com" })),
    );
  });

  it("adresse du jeton en majuscules : author_email tel quel refusé", async () => {
    await expectRule(
      false,
      db(state.env, "mixedCase")
        .doc("tickets/nouveau")
        .set(ticket("mixedCase", { author_email: "Mixed.Case@Example.COM" })),
    );
  });

  it("membre retiré : ne crée plus de ticket et ne lit plus le sien", async () => {
    await seedTickets();
    await state.env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc("members/brewer.a@example.com").delete(),
    );
    await expectRule(false, db(state.env, "owner").doc("tickets/nouveau").set(ticket("owner")));
    await expectRule(false, db(state.env, "owner").doc("tickets/t-a").get());
  });
});

describe("tickets — forme à la création (P23)", () => {
  const valid = {
    "type evolution": { type: "evolution" },
    "type feature": { type: "feature" },
    "plateforme web": { platform: "web" },
    "titre de 5 caractères": { title: "12345" },
    "titre de 100 caractères": { title: "t".repeat(100) },
    "description de 10 caractères": { description: "d".repeat(10) },
    "description de 2 000 caractères": { description: "d".repeat(2000) },
    "écran autre": { screen: "autre" },
    "écran inconnu": { screen: "inconnu" },
    "écran racine": { screen: "/" },
    "écran /recettes/:id/modifier": { screen: "/recettes/:id/modifier" },
    "écran /admin/membres": { screen: "/admin/membres" },
    "version absente": { app_version: undefined },
    "version de 40 caractères": { app_version: "v".repeat(40) },
  };
  for (const [name, extra] of Object.entries(valid)) {
    it(`${name} : autorisé`, async () => {
      const data = ticket("owner", extra);
      for (const [k, v] of Object.entries(extra)) if (v === undefined) delete data[k];
      await expectRule(true, db(state.env, "owner").doc("tickets/nouveau").set(data));
    });
  }

  const invalid = {
    "author_uid d'un autre compte": { author_uid: "brewer-b" },
    "author_email d'un autre compte": { author_email: "brewer.b@example.com" },
    "author_email absent": { author_email: undefined },
    "created_at fixé par l'appareil": { created_at: CREATED },
    "statut received": { status: "received" },
    "statut absent": { status: undefined },
    "type question": { type: "question" },
    "type absent": { type: undefined },
    "titre de 4 caractères": { title: "1234" },
    "titre de 101 caractères": { title: "t".repeat(101) },
    "titre sur deux lignes": { title: "Ligne une\nligne deux" },
    "titre non textuel": { title: 12345 },
    "description de 9 caractères": { description: "d".repeat(9) },
    "description de 2 001 caractères": { description: "d".repeat(2001) },
    "écran avec identifiant réel": { screen: "/recettes/aB3xYz9" },
    "écran avec chiffres": { screen: "/recettes/123" },
    "écran sans barre": { screen: "recettes" },
    "écran avec requête": { screen: "/recettes?id=aB3" },
    "écran de 101 caractères": { screen: `/${"a".repeat(100)}` },
    "écran absent": { screen: undefined },
    "version vide": { app_version: "" },
    "version de 41 caractères": { app_version: "v".repeat(41) },
    "plateforme ios": { platform: "ios" },
    "champ serveur github_issue_number": { github_issue_number: 3 },
    "champ serveur github_url": { github_url: "https://github.com/x/y/issues/1" },
    "champ serveur send_attempts": { send_attempts: 0 },
    "champ serveur status_changed_at": { status_changed_at: serverTimestamp() },
    "champ serveur reply_text": { reply_text: "Réponse" },
    "champ serveur delivered_version": { delivered_version: "9.9.9" },
    "champ serveur allowed_decisions": { allowed_decisions: ["validate"] },
    "seen_by_author_at à la création": { seen_by_author_at: serverTimestamp() },
    "champ hors liste (display_name)": { display_name: "Brasseur A" },
    "champ hors liste (price_eur)": { price_eur: 3 },
  };
  for (const [name, extra] of Object.entries(invalid)) {
    it(`${name} : refusé`, async () => {
      const data = ticket("owner", extra);
      for (const [k, v] of Object.entries(extra)) if (v === undefined) delete data[k];
      await expectRule(false, db(state.env, "owner").doc("tickets/nouveau").set(data));
    });
  }

  it("identifiant de document hors [A-Za-z0-9_-] : refusé", async () => {
    await expectRule(false, db(state.env, "owner").doc("tickets/a.b").set(ticket("owner")));
  });
});

describe("tickets — mise à jour par l'auteur", () => {
  const refused = {
    "seen_by_author_at à l'heure de l'appareil": {
      seen_by_author_at: Timestamp.fromDate(new Date("2026-11-10T10:00:00Z")),
    },
    statut: { status: "delivered" },
    titre: { title: "Nouveau titre" },
    réponse: { reply_text: "Fausse réponse" },
    "numéro d'Issue": { github_issue_number: 99 },
    status_changed_at: { status_changed_at: serverTimestamp() },
    "seen_by_author_at et statut": { seen_by_author_at: serverTimestamp(), status: "closed" },
    "retry_requested_at (T2)": { retry_requested_at: serverTimestamp() },
  };
  for (const [name, change] of Object.entries(refused)) {
    it(`owner modifie ${name} : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, "owner").doc("tickets/t-a").update(change));
    });
  }

  it("admin modifie le statut d'un ticket : refusé", async () => {
    await seedTickets();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/t-a").update({ status: "validated" }),
    );
  });
});

describe("tickets — décisions (lot T2, absentes de T1)", () => {
  for (const name of ["owner", "admin"]) {
    it(`${name} crée une décision : refusé`, async () => {
      await seedTickets();
      await expectRule(
        false,
        db(state.env, name)
          .doc("tickets/t-a/decisions/d-1")
          .set({ action: "validate", state: "pending" }),
      );
    });
  }
});

describe("ticket_quotas et ticket_status", () => {
  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} lit un compteur de plafond : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, name).doc("ticket_quotas/group_20261110").get());
    });
    it(`${name} écrit un compteur de plafond : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name).doc("ticket_quotas/group_20261110").set({ count: 0 }),
      );
    });
    it(`${name} écrit l'état du jeton : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name).doc("ticket_status/github").set({ token_invalid_since: null }),
      );
    });
  }

  const readStatus = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(readStatus)) {
    it(`${name} lit l'état du jeton : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await expectRule(allowed, db(state.env, name).doc("ticket_status/github").get());
    });
  }
});
