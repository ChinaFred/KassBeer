// storage.rules (ADR-008, T6) : capture d'écran jointe à un ticket,
// `tickets/{uid}/{ticketId}/screenshot.png|jpg`. Cinq profils de P4, cas de P11, et la
// fixture partagée test-fixtures/member_access.json (P31), rejouée ici contre la copie
// de isMember et isAdmin de storage.rules.
//
// Environnement propre à ce fichier : Firestore (tickets/, members/, lus par
// `firestore.get`) et Storage, tous deux sur l'émulateur du projet demo-kassbeer.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import "firebase/compat/storage";
import { CREATED, PERSONAS, PROJECT_ID, Timestamp, memberDocs, seed, uidOf } from "./helpers.mjs";

const state = { env: null };

before(async () => {
  state.env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
    },
    storage: {
      rules: readFileSync(new URL("../../storage.rules", import.meta.url), "utf8"),
    },
  });
});
after(async () => {
  await state.env.cleanup();
});
beforeEach(async () => {
  await state.env.clearFirestore();
  await state.env.clearStorage();
  await seed(state.env, {
    ...memberDocs(),
    "tickets/t-a": ticketOf("brewer-a"),
    "tickets/t-b": ticketOf("brewer-b"),
    "tickets/t-admin": ticketOf("admin"),
  });
});

function ticketOf(uid) {
  return {
    type: "bug",
    title: "Le minuteur saute",
    description: "Le minuteur de l'ébullition repart à zéro.",
    screen: "/brassins/:id/jour",
    platform: "android",
    author_uid: uid,
    author_email: `${uid}@example.com`,
    created_at: CREATED,
    status: "received",
  };
}

const PNG = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const MAX = 5 * 1024 * 1024;

async function expectRule(allowed, promise) {
  if (allowed) await assertSucceeds(promise);
  else await assertFails(promise);
}

/// Storage vu par un persona ; `anonymous` = sans jeton.
function storage(name) {
  const persona = PERSONAS[name];
  const ctx =
    persona === null
      ? state.env.unauthenticatedContext()
      : state.env.authenticatedContext(persona.uid, persona.token);
  return ctx.storage();
}

const upload = (name, path, { bytes = PNG, contentType = "image/png" } = {}) =>
  storage(name).ref(path).put(bytes, { contentType });

/// Dépose un fichier en contournant les règles.
async function seedFile(path, bytes = PNG, contentType = "image/png") {
  await state.env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.storage().ref(path).put(bytes, { contentType });
  });
}

const OWN = "tickets/brewer-a/t-a/screenshot.png";

describe("storage.rules — dépôt d'une capture, cinq profils (P4)", () => {
  // Chacun dépose sous son propre uid, pour le ticket de brewer-a.
  const ownPath = (name) =>
    `tickets/${name === "anonymous" ? "anon" : uidOf(name)}/t-a/screenshot.png`;
  const allowed = {
    anonymous: false,
    nonMember: false,
    owner: true,
    otherBrewer: false,
    admin: false,
  };
  for (const [name, ok] of Object.entries(allowed)) {
    it(`${name} dépose la capture du ticket de brewer-a : ${ok ? "autorisé" : "refusé"}`, async () => {
      await expectRule(ok, upload(name, ownPath(name)));
    });
  }

  for (const name of ["anonymous", "nonMember", "otherBrewer", "admin"]) {
    it(`${name} dépose sous le dossier de brewer-a : refusé`, async () => {
      await expectRule(false, upload(name, OWN));
    });
  }

  it("admin dépose la capture de son propre ticket : autorisé", async () => {
    await expectRule(true, upload("admin", "tickets/admin/t-admin/screenshot.png"));
  });

  it("otherBrewer dépose la capture de son propre ticket : autorisé", async () => {
    await expectRule(true, upload("otherBrewer", "tickets/brewer-b/t-b/screenshot.png"));
  });

  it("owner remplace sa capture : autorisé", async () => {
    await seedFile(OWN);
    await expectRule(true, upload("owner", OWN));
  });
});

describe("storage.rules — contenu du dépôt", () => {
  it("JPEG en screenshot.jpg : autorisé", async () => {
    await expectRule(
      true,
      upload("owner", "tickets/brewer-a/t-a/screenshot.jpg", {
        bytes: Uint8Array.from([0xff, 0xd8, 0xff, 0xe0]),
        contentType: "image/jpeg",
      }),
    );
  });

  it("5 Mo exactement : autorisé", async () => {
    await expectRule(true, upload("owner", OWN, { bytes: new Uint8Array(MAX) }));
  });

  const refused = {
    "5 Mo + 1 octet": { bytes: new Uint8Array(MAX + 1) },
    "fichier vide": { bytes: new Uint8Array(0) },
    "type image/gif": { contentType: "image/gif" },
    "type text/plain": { contentType: "text/plain" },
    "JPEG annoncé en screenshot.png": { contentType: "image/jpeg" },
  };
  for (const [label, opts] of Object.entries(refused)) {
    it(`${label} : refusé`, async () => {
      await expectRule(false, upload("owner", OWN, opts));
    });
  }

  it("PNG annoncé en screenshot.jpg : refusé", async () => {
    await expectRule(false, upload("owner", "tickets/brewer-a/t-a/screenshot.jpg"));
  });

  for (const name of ["capture.png", "screenshot.gif", "screenshot.png.exe", "screenshot.PNG"]) {
    it(`nom ${name} : refusé`, async () => {
      await expectRule(false, upload("owner", `tickets/brewer-a/t-a/${name}`));
    });
  }

  it("sous-dossier supplémentaire : refusé", async () => {
    await expectRule(false, upload("owner", "tickets/brewer-a/t-a/x/screenshot.png"));
  });

  it("ticket absent de Firestore : refusé", async () => {
    await expectRule(false, upload("owner", "tickets/brewer-a/t-absent/screenshot.png"));
  });

  it("ticket d'un autre auteur, sous son propre uid : refusé", async () => {
    await expectRule(false, upload("owner", "tickets/brewer-a/t-b/screenshot.png"));
  });

  it("autre chemin du bucket : refusé", async () => {
    await expectRule(false, upload("owner", "brewer-a/screenshot.png"));
    await expectRule(false, upload("admin", "public/screenshot.png"));
  });
});

describe("storage.rules — cas de P11", () => {
  // Invités sous la clé de leur jeton, mais connexion non conforme ; chacun a son ticket.
  for (const name of ["unverified", "passwordProvider"]) {
    it(`${name} dépose la capture de son ticket : refusé`, async () => {
      const uid = uidOf(name);
      await seed(state.env, { [`tickets/t-${uid}`]: ticketOf(uid) });
      await expectRule(false, upload(name, `tickets/${uid}/t-${uid}/screenshot.png`));
    });
  }

  it("adresse du jeton en majuscules : membre, dépôt autorisé", async () => {
    await seed(state.env, { "tickets/t-mixed": ticketOf("mixed") });
    await expectRule(true, upload("mixedCase", "tickets/mixed/t-mixed/screenshot.png"));
  });
});

describe("storage.rules — lecture, liste, suppression", () => {
  const read = { anonymous: false, nonMember: false, owner: true, otherBrewer: false, admin: true };
  for (const [name, ok] of Object.entries(read)) {
    it(`${name} lit la capture de brewer-a : ${ok ? "autorisé" : "refusé"}`, async () => {
      await seedFile(OWN);
      await expectRule(ok, storage(name).ref(OWN).getMetadata());
    });
  }

  it("auteur dont le compte n'est plus membre : lecture refusée", async () => {
    await seedFile("tickets/stranger/t-s/screenshot.png");
    await expectRule(
      false,
      storage("nonMember").ref("tickets/stranger/t-s/screenshot.png").getMetadata(),
    );
  });

  for (const name of ["owner", "admin"]) {
    it(`${name} liste le dossier du ticket : refusé`, async () => {
      await seedFile(OWN);
      await expectRule(false, storage(name).ref("tickets/brewer-a/t-a").listAll());
    });
    it(`${name} supprime la capture : refusé`, async () => {
      await seedFile(OWN);
      await expectRule(false, storage(name).ref(OWN).delete());
    });
  }
});

describe("member_access.json — storage.rules (P31)", () => {
  const fixture = JSON.parse(
    readFileSync(new URL("../../test-fixtures/member_access.json", import.meta.url), "utf8"),
  );

  /// Storage du cas : anonyme, ou jeton construit depuis la fixture.
  function caseStorage(c, uid) {
    if (c.token === null) return state.env.unauthenticatedContext().storage();
    const token = {
      email_verified: c.token.email_verified,
      firebase: { sign_in_provider: c.token.sign_in_provider },
    };
    if (c.token.email !== null) token.email = c.token.email;
    return state.env.authenticatedContext(uid, token).storage();
  }

  async function seedCase(c) {
    if (c.member === null) return;
    await seed(state.env, {
      [`members/${c.member_key}`]: {
        ...c.member,
        invited_at: Timestamp.fromDate(new Date("2026-11-01T10:00:00Z")),
      },
    });
  }

  fixture.cases.forEach((c, index) => {
    const uid = `fixture-${index}`;
    const member = c.expect !== "none";
    const admin = c.expect === "admin";
    // isMember seul : l'auteur lit sa propre capture.
    it(`${c.name} : isMember ${member ? "vrai" : "faux"}`, async () => {
      await seedCase(c);
      const path = `tickets/${uid}/t/screenshot.png`;
      await seedFile(path);
      await expectRule(member, caseStorage(c, uid).ref(path).getMetadata());
    });
    // isAdmin : lecture de la capture d'un autre compte.
    it(`${c.name} : isAdmin ${admin ? "vrai" : "faux"}`, async () => {
      await seedCase(c);
      await seedFile(OWN);
      await expectRule(admin, caseStorage(c, uid).ref(OWN).getMetadata());
    });
  });
});
