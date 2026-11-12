// tickets/, tickets/{id}/decisions/, tickets/{id}/admin/, ticket_quotas/, ticket_status/ :
// tickets des membres, décisions et analyses lues par l'admin (ADR-006, T1 et T2 ;
// ADR-008, T3 ; P23, P4, P11).

import { describe, it } from "node:test";
import {
  CREATED,
  db,
  deleteField,
  memberId,
  seed,
  serverTimestamp,
  Timestamp,
  uidOf,
} from "./helpers.mjs";
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

/// Décision telle que l'écran Admin › Tickets la crée.
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

describe("tickets — décisions, cinq profils (P4, P23)", () => {
  const create = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} crée une décision sur le ticket de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedDecisions();
      await expectRule(
        allowed,
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

  const retry = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(retry)) {
    it(`${name} relance une décision failed : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedDecisions();
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("tickets/t-a/decisions/d-failed")
          .update({ retry_requested_at: serverTimestamp() }),
      );
    });
  }

  for (const name of ["anonymous", "nonMember", "owner", "otherBrewer", "admin"]) {
    it(`${name} supprime une décision : refusé`, async () => {
      await seedDecisions();
      await expectRule(false, db(state.env, name).doc("tickets/t-a/decisions/d-failed").delete());
    });
  }
});

describe("tickets — forme d'une décision à la création (P23)", () => {
  const valid = {
    "refuse avec motif": {},
    "close avec commentaire": { action: "close", text: "Fait dans la v0.3." },
    "validate sans texte": { action: "validate", text: undefined },
    "texte de 5 caractères": { text: "12345" },
    "texte de 2 000 caractères": { text: "m".repeat(2000) },
    "décision sur le ticket d'un autre brasseur": { __ticket: "t-b" },
  };
  for (const [name, extra] of Object.entries(valid)) {
    it(`${name} : autorisé`, async () => {
      await seedDecisions();
      const { __ticket = "t-a", ...rest } = extra;
      const data = decision("admin", rest);
      for (const [k, v] of Object.entries(rest)) if (v === undefined) delete data[k];
      await expectRule(
        true,
        db(state.env, "admin").doc(`tickets/${__ticket}/decisions/d-new`).set(data),
      );
    });
  }

  const invalid = {
    "validate avec texte": { action: "validate" },
    "refuse sans motif": { text: undefined },
    "close sans commentaire": { action: "close", text: undefined },
    "texte de 4 caractères": { text: "1234" },
    "texte de 2 001 caractères": { text: "m".repeat(2001) },
    "texte non textuel": { text: 12345 },
    "action inconnue": { action: "delete" },
    "action answer (callable seule, ADR-008)": { action: "answer" },
    "action answer avec texte": { action: "answer", text: "Précision de l'administrateur." },
    "action absente": { action: undefined },
    "état applying": { state: "applying" },
    "état applied": { state: "applied" },
    "état absent": { state: undefined },
    "requested_by_uid d'un autre compte": { requested_by_uid: "brewer-a" },
    "requested_by_uid absent": { requested_by_uid: undefined },
    "requested_at fixé par l'appareil": { requested_at: CREATED },
    "requested_at absent": { requested_at: undefined },
    "champ serveur error_reason": { error_reason: "x" },
    "champ serveur applied_at": { applied_at: serverTimestamp() },
    "champ serveur steps_done": { steps_done: [] },
    "champ serveur lease_until": { lease_until: serverTimestamp() },
    "champ serveur comment_id": { comment_id: 1 },
    "retry_requested_at à la création": { retry_requested_at: serverTimestamp() },
    "champ hors liste (author_email)": { author_email: "admin@example.com" },
  };
  for (const [name, extra] of Object.entries(invalid)) {
    it(`${name} : refusé`, async () => {
      await seedDecisions();
      const data = decision("admin", extra);
      for (const [k, v] of Object.entries(extra)) if (v === undefined) delete data[k];
      await expectRule(false, db(state.env, "admin").doc("tickets/t-a/decisions/d-new").set(data));
    });
  }

  it("identifiant de décision hors [A-Za-z0-9_-] : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/t-a/decisions/d.1").set(decision("admin")),
    );
  });

  it("décision sur un ticket absent : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/absent/decisions/d-new").set(decision("admin")),
    );
  });

  it("décision déjà existante réécrite par set : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/t-a/decisions/d-applied").set(decision("admin")),
    );
  });
});

describe("tickets — reprise d'une décision par l'admin", () => {
  it("décision applied : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin")
        .doc("tickets/t-a/decisions/d-applied")
        .update({ retry_requested_at: serverTimestamp() }),
    );
  });

  const refused = {
    "retry_requested_at à l'heure de l'appareil": { retry_requested_at: CREATED },
    "état remis à pending": { state: "pending" },
    "retry_requested_at et état": { retry_requested_at: serverTimestamp(), state: "pending" },
    "retry_requested_at et texte": {
      retry_requested_at: serverTimestamp(),
      text: "Nouveau motif publié",
    },
    "error_reason effacé": { error_reason: deleteField() },
  };
  for (const [name, change] of Object.entries(refused)) {
    it(`admin modifie ${name} sur une décision failed : refusé`, async () => {
      await seedDecisions();
      await expectRule(
        false,
        db(state.env, "admin").doc("tickets/t-a/decisions/d-failed").update(change),
      );
    });
  }
});

describe("tickets — relance d'un envoi en échec (T2)", () => {
  const retry = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(retry)) {
    it(`${name} relance l'envoi du ticket send_failed de brewer-a : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await seedDecisions();
      await expectRule(
        allowed,
        db(state.env, name)
          .doc("tickets/t-failed")
          .update({ retry_requested_at: serverTimestamp() }),
      );
    });
  }

  it("admin relance un ticket received : refusé", async () => {
    await seedDecisions();
    await expectRule(
      false,
      db(state.env, "admin").doc("tickets/t-a").update({ retry_requested_at: serverTimestamp() }),
    );
  });

  const refused = {
    "à l'heure de l'appareil": { retry_requested_at: CREATED },
    "avec le statut": { retry_requested_at: serverTimestamp(), status: "pending" },
    "avec send_attempts": { retry_requested_at: serverTimestamp(), send_attempts: 0 },
    "avec allowed_decisions": {
      retry_requested_at: serverTimestamp(),
      allowed_decisions: ["validate"],
    },
  };
  for (const [name, change] of Object.entries(refused)) {
    it(`admin relance ${name} : refusé`, async () => {
      await seedDecisions();
      await expectRule(false, db(state.env, "admin").doc("tickets/t-failed").update(change));
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
