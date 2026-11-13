import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import {
  ADMIN_DENIED_MESSAGE,
  MEMBER_DENIED_MESSAGE,
  memberAccess,
  requireAdmin,
  requireBoundedText,
  requireMember,
  type MemberLookup,
  type TokenClaims,
} from "../src/auth";

interface FixtureCase {
  name: string;
  token: { email: string | null; email_verified: unknown; sign_in_provider: string } | null;
  member_key: string | null;
  member: Record<string, unknown> | null;
  expect: "none" | "member" | "admin";
}

// Compilé dans build-test/test/ : la racine du dépôt est trois dossiers plus haut.
const fixture = JSON.parse(
  readFileSync(join(__dirname, "../../../test-fixtures/member_access.json"), "utf8"),
) as { cases: FixtureCase[] };

function tokenOf(c: FixtureCase): TokenClaims | null {
  if (c.token === null) return null;
  const token: TokenClaims = {
    email_verified: c.token.email_verified,
    firebase: { sign_in_provider: c.token.sign_in_provider },
  };
  if (c.token.email !== null) token.email = c.token.email;
  return token;
}

/** `members/` réduit au document du cas, lu par clé exacte comme Firestore. */
function lookupOf(c: FixtureCase): MemberLookup {
  return async (key) => (c.member !== null && key === c.member_key ? c.member : null);
}

describe("member_access.json — functions/src/auth.ts (P31)", () => {
  assert.ok(fixture.cases.length >= 10);
  for (const c of fixture.cases) {
    it(`${c.name} : ${c.expect}`, async () => {
      assert.equal(await memberAccess(tokenOf(c), lookupOf(c)), c.expect);
    });
    it(`${c.name} : requireMember et requireAdmin`, async () => {
      const req = c.token === null ? {} : { auth: { uid: "u", token: tokenOf(c) ?? {} } };
      const member = requireMember(req, lookupOf(c));
      const admin = requireAdmin(req, lookupOf(c));
      if (c.expect === "none") await assert.rejects(member, HttpsError);
      else assert.deepEqual(await member, { uid: "u" });
      if (c.expect === "admin") assert.deepEqual(await admin, { uid: "u" });
      else await assert.rejects(admin, HttpsError);
    });
  }
});

const google = (email: string, extra: Record<string, unknown> = {}) => ({
  email,
  email_verified: true,
  firebase: { sign_in_provider: "google.com" },
  ...extra,
});

const members: Record<string, Record<string, unknown>> = {
  "brasseur@example.com": { role: "brewer" },
  "admin@example.com": { role: "admin" },
  "nonverifie@example.com": { role: "admin" },
  "motdepasse@example.com": { role: "admin" },
};
let reads = 0;
const lookup: MemberLookup = async (key) => {
  reads++;
  return members[key] ?? null;
};

async function code(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
    return "ok";
  } catch (err) {
    assert.ok(err instanceof HttpsError);
    return err.code;
  }
}

describe("requireAdmin et requireMember, six profils (P30)", () => {
  const cases: Array<[string, object, string, string]> = [
    ["anonyme", {}, "unauthenticated", "unauthenticated"],
    [
      "e-mail non vérifié",
      { auth: { uid: "u", token: google("nonverifie@example.com", { email_verified: false }) } },
      "permission-denied",
      "permission-denied",
    ],
    [
      "autre fournisseur",
      {
        auth: {
          uid: "u",
          token: google("motdepasse@example.com", { firebase: { sign_in_provider: "password" } }),
        },
      },
      "permission-denied",
      "permission-denied",
    ],
    [
      "non membre",
      { auth: { uid: "u", token: google("inconnu@example.com") } },
      "permission-denied",
      "permission-denied",
    ],
    [
      "brasseur",
      { auth: { uid: "u", token: google("brasseur@example.com") } },
      "ok",
      "permission-denied",
    ],
    ["admin", { auth: { uid: "u", token: google("admin@example.com") } }, "ok", "ok"],
  ];
  for (const [name, req, memberCode, adminCode] of cases) {
    it(`${name} : membre ${memberCode}, admin ${adminCode}`, async () => {
      assert.equal(await code(requireMember(req, lookup)), memberCode);
      assert.equal(await code(requireAdmin(req, lookup)), adminCode);
    });
  }

  it("le refus ne dit pas si le compte existe : même message pour un non-membre et un brasseur", async () => {
    const messages: string[] = [];
    for (const email of ["inconnu@example.com", "brasseur@example.com"]) {
      try {
        await requireAdmin({ auth: { uid: "u", token: google(email) } }, lookup);
      } catch (err) {
        assert.ok(err instanceof HttpsError);
        messages.push(err.message);
        assert.deepEqual(err.details, { reason: ADMIN_DENIED_MESSAGE });
      }
    }
    assert.deepEqual(messages, [ADMIN_DENIED_MESSAGE, ADMIN_DENIED_MESSAGE]);
    await assert.rejects(
      requireMember({ auth: { uid: "u", token: google("inconnu@example.com") } }, lookup),
      (err: HttpsError) => err.message === MEMBER_DENIED_MESSAGE,
    );
  });

  it("members/ relu à chaque appel, sans cache (P26)", async () => {
    const before = reads;
    const req = { auth: { uid: "u", token: google("admin@example.com") } };
    await requireAdmin(req, lookup);
    await requireAdmin(req, lookup);
    assert.equal(reads - before, 2);
    members["admin@example.com"] = { role: "brewer" };
    assert.equal(await code(requireAdmin(req, lookup)), "permission-denied");
    members["admin@example.com"] = { role: "admin" };
  });

  it("aucun document lu pour un jeton refusé avant members/", async () => {
    const before = reads;
    await code(
      requireAdmin(
        { auth: { uid: "u", token: google("nonverifie@example.com", { email_verified: "true" }) } },
        lookup,
      ),
    );
    assert.equal(reads, before);
  });
});

describe("requireBoundedText (P30)", () => {
  const opts = { field: "answer", max: 10, label: "Réponse" };
  const fails = (value: unknown, required: boolean, reason: string) => {
    assert.throws(
      () => requireBoundedText(value, { ...opts, required }),
      (err: HttpsError) =>
        err.code === "invalid-argument" &&
        (err.details as { field: string; reason: string }).field === "answer" &&
        (err.details as { field: string; reason: string }).reason === reason,
    );
  };
  it("texte dans la borne : rendu tel quel", () =>
    assert.equal(requireBoundedText("abc", { ...opts, required: true }), "abc"));
  it("absent : refusé si requis, sinon undefined", () => {
    fails(undefined, true, "Réponse : valeur requise.");
    fails(null, true, "Réponse : valeur requise.");
    assert.equal(requireBoundedText(undefined, opts), undefined);
  });
  it("autre type que texte : refusé", () => {
    fails(42, true, "Réponse : un texte est attendu.");
    fails(["a"], false, "Réponse : un texte est attendu.");
  });
  it("au-delà de la borne : refusé avant toute lecture", () =>
    fails("x".repeat(11), true, "Réponse : texte trop long."));
});
