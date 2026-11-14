// tickets/, tickets/{id}/decisions/, tickets/{id}/admin/, ticket_quotas/, ticket_status/ :
// tickets des membres, historique des décisions écrit par le serveur, analyses et lancements
// lus par l'admin (ADR-006, T1 et T2 ; ADR-008, T3, T4 et T7 ; P23, P4, P11, P41).

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
    "écran avec fenêtre /brassins/:id/fenetre/embouteillage": {
      screen: "/brassins/:id/fenetre/embouteillage",
    },
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
    "champ serveur validated_by_app_at": { validated_by_app_at: serverTimestamp() },
    "champ serveur screenshot_path (T6)": {
      screenshot_path: "tickets/brewer-a/nouveau/screenshot.png",
    },
    "champ serveur screenshot_expires_at (T6)": {
      screenshot_expires_at: Timestamp.fromDate(new Date("2027-05-13T09:00:00Z")),
    },
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

  for (const name of ["owner", "admin"]) {
    it(`${name} passe le ticket au statut analyzed : refusé`, async () => {
      await seedTickets();
      await expectRule(
        false,
        db(state.env, name).doc("tickets/t-a").update({ status: "analyzed" }),
      );
    });
  }

  // screenshot_path (ADR-008, T6) : écrit par attachTicketScreenshot seul (SDK Admin).
  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} écrit screenshot_path sur le ticket de brewer-a : refusé`, async () => {
      await seedTickets();
      await expectRule(
        false,
        db(state.env, name)
          .doc("tickets/t-a")
          .update({ screenshot_path: "tickets/brewer-a/t-a/screenshot.png" }),
      );
    });
  }

  // screenshot_expires_at (complément du 2026-11-14) : écrit avec screenshot_path, par le
  // serveur seul.
  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} écrit screenshot_expires_at sur le ticket de brewer-a : refusé`, async () => {
      await seed(state.env, {
        "tickets/t-a": {
          ...published,
          screenshot_path: "tickets/brewer-a/t-a/screenshot.png",
          screenshot_expires_at: Timestamp.fromDate(new Date("2027-05-13T09:00:00Z")),
        },
      });
      await expectRule(
        false,
        db(state.env, name)
          .doc("tickets/t-a")
          .update({ screenshot_expires_at: Timestamp.fromDate(new Date("2030-01-01T00:00:00Z")) }),
      );
    });
  }

  it("owner marque le suivi lu et pose screenshot_path : refusé", async () => {
    await seedTickets();
    await expectRule(
      false,
      db(state.env, "owner").doc("tickets/t-a").update({
        seen_by_author_at: serverTimestamp(),
        screenshot_path: "tickets/brewer-a/t-a/screenshot.png",
      }),
    );
  });

  it("owner marque lu un ticket qui porte déjà screenshot_path : autorisé", async () => {
    await seed(state.env, {
      "tickets/t-a": { ...published, screenshot_path: "tickets/brewer-a/t-a/screenshot.png" },
    });
    await expectRule(
      true,
      db(state.env, "owner").doc("tickets/t-a").update({ seen_by_author_at: serverTimestamp() }),
    );
  });

  for (const field of ["answer_reset_at", "allowed_decisions"]) {
    it(`admin écrit ${field} (champ serveur de T3) : refusé`, async () => {
      await seedTickets();
      const value = field === "answer_reset_at" ? serverTimestamp() : ["answer"];
      await expectRule(
        false,
        db(state.env, "admin")
          .doc("tickets/t-a")
          .update({ [field]: value }),
      );
    });
  }

  it("owner crée un ticket au statut analyzed : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("tickets/nouveau")
        .set(ticket("owner", { status: "analyzed" })),
    );
  });

  it("admin modifie le statut d'un ticket : refusé", async () => {
    await seedTickets();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/t-a").update({ status: "validated" }),
    );
  });
});

/// Décision telle que l'écran Admin › Tickets la créait avant T7 : les règles la refusent.
const decision = (name, extra = {}) => ({
  action: "refuse",
  text: "Hors du périmètre de l'application.",
  state: "pending",
  requested_by_uid: name === "anonymous" ? "anon" : uidOf(name),
  requested_at: serverTimestamp(),
  ...extra,
});

/// Ticket de brewer-a en échec d'envoi, et ticket propre à l'admin.
const sendFailed = {
  ...published,
  status: "send_failed",
  github_issue_number: null,
  github_url: null,
  send_attempts: 10,
  last_send_error: "GitHub HTTP 500",
  allowed_decisions: [],
};

async function seedDecisions() {
  await seed(state.env, {
    "tickets/t-a": { ...published, allowed_decisions: ["validate", "refuse", "close"] },
    "tickets/t-failed": sendFailed,
    "tickets/t-b": { ...published, author_uid: "brewer-b", author_email: "brewer.b@example.com" },
    "tickets/t-a/decisions/d-failed": {
      action: "refuse",
      text: "Hors du périmètre de l'application.",
      state: "failed",
      requested_by_uid: "admin",
      requested_at: CREATED,
      error_reason: "Motif publié, mais l'Issue n'a pas été fermée. Réessayez.",
      steps_done: ["comment"],
    },
    "tickets/t-a/decisions/d-applied": {
      action: "validate",
      state: "applied",
      requested_by_uid: "admin",
      requested_at: CREATED,
      applied_at: CREATED,
    },
  });
}

describe("tickets — décisions, cinq profils (P4, P23, T7)", () => {
  // Les décisions sont écrites par les callables seules (ADR-008, T7) : aucune création
  // client, admin compris.
  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} crée une décision sur le ticket de brewer-a : refusé`, async () => {
      await seedDecisions();
      await expectRule(
        false,
        db(state.env, name).doc("tickets/t-a/decisions/d-new").set(decision(name)),
      );
    });
  }

  it("owner crée une décision sur son propre ticket : refusé", async () => {
    await seedDecisions();
    for (const action of ["validate", "refuse", "close"]) {
      const extra = action === "validate" ? { action, text: undefined } : { action };
      const data = decision("owner", extra);
      if (data.text === undefined) delete data.text;
      await expectRule(false, db(state.env, "owner").doc("tickets/t-a/decisions/d-own").set(data));
    }
  });

  it("admin crée une décision validate, ou à l'état d'une décision appliquée : refusé", async () => {
    await seedDecisions();
    const validate = decision("admin", { action: "validate" });
    delete validate.text;
    await expectRule(false, db(state.env, "admin").doc("tickets/t-a/decisions/d-v").set(validate));
    await expectRule(
      false,
      db(state.env, "admin")
        .doc("tickets/t-a/decisions/d-s")
        .set(decision("admin", { state: "applied", applied_at: serverTimestamp() })),
    );
  });

  const read = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit une décision : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedDecisions();
      await expectRule(allowed, db(state.env, name).doc("tickets/t-a/decisions/d-failed").get());
    });
    it(`${name} liste les décisions d'un ticket : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedDecisions();
      await expectRule(
        allowed,
        db(state.env, name)
          .collection("tickets/t-a/decisions")
          .orderBy("requested_at", "desc")
          .get(),
      );
    });
  }

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} écrit retry_requested_at sur une décision failed : refusé`, async () => {
      await seedDecisions();
      await expectRule(
        false,
        db(state.env, name)
          .doc("tickets/t-a/decisions/d-failed")
          .update({ retry_requested_at: serverTimestamp() }),
      );
    });
    it(`${name} modifie l'état d'une décision : refusé`, async () => {
      await seedDecisions();
      await expectRule(
        false,
        db(state.env, name).doc("tickets/t-a/decisions/d-failed").update({ state: "pending" }),
      );
    });
    it(`${name} supprime une décision : refusé`, async () => {
      await seedDecisions();
      await expectRule(false, db(state.env, name).doc("tickets/t-a/decisions/d-failed").delete());
    });
  }
});

describe("tickets — relance d'un envoi en échec : par la callable seule (T7)", () => {
  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} écrit retry_requested_at sur le ticket send_failed de brewer-a : refusé`, async () => {
      await seedDecisions();
      await expectRule(
        false,
        db(state.env, name)
          .doc("tickets/t-failed")
          .update({ retry_requested_at: serverTimestamp() }),
      );
    });
  }

  it("admin écrit retry_requested_at sur un ticket received : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/t-a").update({ retry_requested_at: serverTimestamp() }),
    );
  });

  it("admin remet un ticket send_failed à pending : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin")
        .doc("tickets/t-failed")
        .update({ status: "pending", send_attempts: 0 }),
    );
  });

  // Validation de l'application (ADR-008, 2026-11-13) : écrite par le serveur seul.
  it("owner écrit seen_by_author_at avec validated_by_app_at : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "owner")
        .doc("tickets/t-a")
        .update({ seen_by_author_at: serverTimestamp(), validated_by_app_at: serverTimestamp() }),
    );
  });

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} écrit validated_by_app_at sur un ticket : refusé`, async () => {
      await seedDecisions();
      await expectRule(
        false,
        db(state.env, name).doc("tickets/t-a").update({ validated_by_app_at: serverTimestamp() }),
      );
    });
  }

  for (const field of ["allowed_decisions", "decision_lease_until"]) {
    it(`admin écrit ${field} sur un ticket : refusé`, async () => {
      await seedDecisions();
      const value = field === "allowed_decisions" ? ["validate"] : serverTimestamp();
      await expectRule(
        false,
        db(state.env, "admin")
          .doc("tickets/t-a")
          .update({ [field]: value }),
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

/// Analyses relevées par le serveur (ADR-008, T3, P32).
const analysis = {
  analyses: [
    {
      comment_id: 101,
      kind: "analysis",
      body: "## Analyse\n\nLe minuteur repart de zéro.",
      created_at: CREATED,
      updated_at: CREATED,
      truncated: false,
    },
  ],
  skipped_count: 0,
  checked_at: CREATED,
  answer_comment_ids: [],
};

describe("tickets/{id}/admin/ — analyses, cinq profils (P4, P23, P32)", () => {
  const read = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit les analyses du ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/analysis": analysis });
      await expectRule(allowed, db(state.env, name).doc("tickets/t-a/admin/analysis").get());
    });
    it(`${name} liste admin/ du ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/analysis": analysis });
      await expectRule(allowed, db(state.env, name).collection("tickets/t-a/admin").get());
    });
  }

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} crée les analyses : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, name).doc("tickets/t-a/admin/analysis").set(analysis));
    });
    it(`${name} ajoute un identifiant à answer_comment_ids : refusé`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/analysis": analysis });
      await expectRule(
        false,
        db(state.env, name)
          .doc("tickets/t-a/admin/analysis")
          .update({ answer_comment_ids: [999] }),
      );
    });
    it(`${name} supprime les analyses : refusé`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/analysis": analysis });
      await expectRule(false, db(state.env, name).doc("tickets/t-a/admin/analysis").delete());
    });
  }
});

/// Historique des lancements de sessions, écrit par le serveur (ADR-008, T4, P41).
const launches = {
  entries: [
    {
      id: "0b6f4a52-5d8e-4f43-9a8e-1f0c2a3b4c5d",
      action: "analyse",
      state: "launched",
      at: CREATED,
      by_uid: "admin",
      retry_after: CREATED,
      session_url: "https://claude.ai/code/session_exemple",
    },
  ],
  updated_at: CREATED,
};

/// Compteurs des lancements, écrits par le serveur (ADR-008, T4, P36, P41).
const launchStatus = {
  day: "20261113",
  count_day: 1,
  month: "202611",
  count_month: 4,
  per_day: 10,
  analysis_invalid_since: null,
  development_invalid_since: null,
};

describe("lancements — admin/launches et ticket_status/launches, cinq profils (P4, P41)", () => {
  const read = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit l'historique des lancements du ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/launches": launches });
      await expectRule(allowed, db(state.env, name).doc("tickets/t-a/admin/launches").get());
    });
    it(`${name} lit les compteurs des lancements : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await seed(state.env, { "ticket_status/launches": launchStatus });
      await expectRule(allowed, db(state.env, name).doc("ticket_status/launches").get());
    });
  }

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} crée l'historique des lancements : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, name).doc("tickets/t-a/admin/launches").set(launches));
    });
    it(`${name} modifie l'historique des lancements : refusé`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/launches": launches });
      await expectRule(
        false,
        db(state.env, name).doc("tickets/t-a/admin/launches").update({ entries: [] }),
      );
    });
    it(`${name} supprime l'historique des lancements : refusé`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/launches": launches });
      await expectRule(false, db(state.env, name).doc("tickets/t-a/admin/launches").delete());
    });
    it(`${name} écrit les compteurs des lancements : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc("ticket_status/launches")
          .set({ ...launchStatus, count_day: 0 }),
      );
    });
    it(`${name} remet à zéro le compteur de lancements du jour : refusé`, async () => {
      await seed(state.env, {
        "ticket_quotas/launch_20261113": { day: "20261113", count: 10, expires_at: CREATED },
      });
      await expectRule(
        false,
        db(state.env, name).doc("ticket_quotas/launch_20261113").update({ count: 0 }),
      );
    });
    it(`${name} lit le compteur de lancements du jour : refusé`, async () => {
      await seed(state.env, {
        "ticket_quotas/launch_20261113": { day: "20261113", count: 10, expires_at: CREATED },
      });
      await expectRule(false, db(state.env, name).doc("ticket_quotas/launch_20261113").get());
    });
  }
});

/// État « PR prête » et comptes rendus de livraison, écrits par le serveur (ADR-008, T5, P45).
const delivery = {
  eligible_pr_count: 1,
  pr_number: 34,
  pr_url: "https://github.com/ChinaFred/KassBeer/pull/34",
  head_sha: "a".repeat(40),
  ci_status: "completed",
  ci_conclusion: "success",
  ci_completed_at: CREATED,
  ready: true,
  relaunch_ready: false,
  reports: [
    {
      comment_id: 77,
      kind: "blocked",
      body: "## Livraison — blocage\n\nL7 : CI rouge.",
      created_at: CREATED,
      updated_at: CREATED,
      truncated: false,
    },
  ],
  reports_checked_at: CREATED,
  updated_at: CREATED,
};

/// Verrou des livraisons, écrit par le serveur (ADR-008, T5, P44).
const deliveryRunning = {
  ticket_id: "t-a",
  issue_number: 12,
  launched_at: CREATED,
  retry_after: CREATED,
};

describe("livraison — admin/delivery et ticket_status/launches.delivery_running, cinq profils (P4, P41, P44, P45)", () => {
  const read = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(read)) {
    it(`${name} lit l'état de livraison du ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/delivery": delivery });
      await expectRule(allowed, db(state.env, name).doc("tickets/t-a/admin/delivery").get());
    });
    it(`${name} lit le verrou des livraisons : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seed(state.env, {
        "ticket_status/launches": { ...launchStatus, delivery_running: deliveryRunning },
      });
      await expectRule(allowed, db(state.env, name).doc("ticket_status/launches").get());
    });
  }

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} crée l'état de livraison : refusé`, async () => {
      await seedTickets();
      await expectRule(false, db(state.env, name).doc("tickets/t-a/admin/delivery").set(delivery));
    });
    it(`${name} modifie l'état de livraison (ready, comptes rendus) : refusé`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/delivery": delivery });
      await expectRule(
        false,
        db(state.env, name).doc("tickets/t-a/admin/delivery").update({ ready: false, reports: [] }),
      );
    });
    it(`${name} supprime l'état de livraison : refusé`, async () => {
      await seedTickets();
      await seed(state.env, { "tickets/t-a/admin/delivery": delivery });
      await expectRule(false, db(state.env, name).doc("tickets/t-a/admin/delivery").delete());
    });
    it(`${name} libère le verrou des livraisons : refusé`, async () => {
      await seed(state.env, {
        "ticket_status/launches": { ...launchStatus, delivery_running: deliveryRunning },
      });
      await expectRule(
        false,
        db(state.env, name).doc("ticket_status/launches").update({ delivery_running: null }),
      );
    });
    it(`${name} prend le verrou des livraisons : refusé`, async () => {
      await seed(state.env, { "ticket_status/launches": launchStatus });
      await expectRule(
        false,
        db(state.env, name)
          .doc("ticket_status/launches")
          .update({ delivery_running: { ...deliveryRunning, ticket_id: "t-b" } }),
      );
    });
  }
});
