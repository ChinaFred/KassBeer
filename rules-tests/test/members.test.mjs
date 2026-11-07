// members/{email} : identité des comptes invités (P11).

import { describe, it } from "node:test";
import { db, memberId, seed, serverTimestamp, uidOf } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const invitation = (email, extra = {}) => ({
  email,
  role: "brewer",
  display_name: "Ami brasseur",
  invited_at: serverTimestamp(),
  invited_by: uidOf("admin"),
  ...extra,
});

const NEW_EMAIL = "nouveau@example.com";

describe("members — lecture", () => {
  const ownGet = {
    anonymous: false,
    nonMember: true, // document absent : l'application affiche « compte non invité »
    owner: true,
    otherBrewer: true,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(ownGet)) {
    it(`${name} lit son propre members/ : ${allowed ? "autorisé" : "refusé"}`, async () => {
      const id = name === "anonymous" ? memberId("owner") : memberId(name);
      await expectRule(allowed, db(state.env, name).doc(`members/${id}`).get());
    });
  }

  for (const name of ["anonymous", "nonMember", "otherBrewer"]) {
    it(`${name} lit le members/ d'un autre : refusé`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc(`members/${memberId("owner")}`)
          .get(),
      );
    });
  }

  it("admin lit le members/ d'un autre : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "admin")
        .doc(`members/${memberId("owner")}`)
        .get(),
    );
  });

  const list = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(list)) {
    it(`${name} liste members/ : ${allowed ? "autorisé" : "refusé"}`, async () => {
      await expectRule(allowed, db(state.env, name).collection("members").get());
    });
  }

  it("adresse du jeton en majuscules : lit members/{minuscules}", async () => {
    await expectRule(
      true,
      db(state.env, "mixedCase")
        .doc(`members/${memberId("mixedCase")}`)
        .get(),
    );
  });

  it("adresse non vérifiée : ne lit pas son propre members/", async () => {
    await expectRule(
      false,
      db(state.env, "unverified")
        .doc(`members/${memberId("unverified")}`)
        .get(),
    );
  });

  it("fournisseur password : ne lit pas son propre members/", async () => {
    await expectRule(
      false,
      db(state.env, "passwordProvider")
        .doc(`members/${memberId("passwordProvider")}`)
        .get(),
    );
  });
});

describe("members — invitation", () => {
  const create = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(create)) {
    it(`${name} invite un compte : ${allowed ? "autorisé" : "refusé"}`, async () => {
      const data = invitation(NEW_EMAIL, { invited_by: name === "anonymous" ? "x" : uidOf(name) });
      await expectRule(allowed, db(state.env, name).doc(`members/${NEW_EMAIL}`).set(data));
    });
  }

  it("non membre qui crée son propre members/ : refusé", async () => {
    const id = memberId("nonMember");
    await expectRule(
      false,
      db(state.env, "nonMember")
        .doc(`members/${id}`)
        .set(invitation(id, { invited_by: uidOf("nonMember") })),
    );
  });

  it("brasseur qui se crée un members/ admin pour une autre adresse : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`members/${NEW_EMAIL}`)
        .set(invitation(NEW_EMAIL, { role: "admin", invited_by: uidOf("owner") })),
    );
  });

  it("admin invite un second admin : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "admin")
        .doc(`members/${NEW_EMAIL}`)
        .set(invitation(NEW_EMAIL, { role: "admin" })),
    );
  });

  it("admin invite sans nom : autorisé (nom facultatif)", async () => {
    const { display_name: _omitted, ...data } = invitation(NEW_EMAIL);
    await expectRule(true, db(state.env, "admin").doc(`members/${NEW_EMAIL}`).set(data));
  });

  const invalid = {
    "identifiant en majuscules": ["Nouveau@Example.com", {}],
    "rôle inconnu": [NEW_EMAIL, { role: "owner" }],
    "champ email différent de l'identifiant": [NEW_EMAIL, { email: "autre@example.com" }],
    "invited_by d'un autre compte": [NEW_EMAIL, { invited_by: "brewer-a" }],
    "invited_at posée par le client": [NEW_EMAIL, { invited_at: new Date() }],
    "champ hors liste": [NEW_EMAIL, { uid: "x" }],
    "nom trop long": [NEW_EMAIL, { display_name: "x".repeat(81) }],
    "identifiant sans @": ["nouveau", {}],
  };
  for (const [label, [id, extra]] of Object.entries(invalid)) {
    it(`admin invite avec ${label} : refusé`, async () => {
      const data = invitation(id.toLowerCase(), extra);
      await expectRule(false, db(state.env, "admin").doc(`members/${id}`).set(data));
    });
  }
});

describe("members — modification et retrait", () => {
  for (const name of ["owner", "admin"]) {
    it(`${name} modifie un rôle : refusé (pas de modification en v1)`, async () => {
      await expectRule(
        false,
        db(state.env, name)
          .doc(`members/${memberId("owner")}`)
          .update({ role: "admin" }),
      );
    });
  }

  const remove = {
    anonymous: false,
    nonMember: false,
    owner: false,
    otherBrewer: false,
    admin: true,
  };
  for (const [name, allowed] of Object.entries(remove)) {
    it(`${name} retire un autre membre : ${allowed ? "autorisé" : "refusé"}`, async () => {
      const target = name === "owner" ? "otherBrewer" : "owner";
      await expectRule(
        allowed,
        db(state.env, name)
          .doc(`members/${memberId(target)}`)
          .delete(),
      );
    });
  }

  it("admin retire son propre members/ : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "admin")
        .doc(`members/${memberId("admin")}`)
        .delete(),
    );
  });

  it("admin retire le members/ d'un autre admin : refusé (console Firebase)", async () => {
    await seed(state.env, {
      "members/second.admin@example.com": {
        email: "second.admin@example.com",
        role: "admin",
        invited_by: uidOf("admin"),
      },
    });
    await expectRule(
      false,
      db(state.env, "admin").doc("members/second.admin@example.com").delete(),
    );
  });

  it("admin retire un brasseur : autorisé", async () => {
    await expectRule(
      true,
      db(state.env, "admin")
        .doc(`members/${memberId("otherBrewer")}`)
        .delete(),
    );
  });

  it("brasseur retire son propre members/ : refusé", async () => {
    await expectRule(
      false,
      db(state.env, "owner")
        .doc(`members/${memberId("owner")}`)
        .delete(),
    );
  });
});
