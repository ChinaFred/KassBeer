// Appartenance et rôle (P11, P31, ADR-008) : firestore.rules (isMember, isAdmin) rejoue la
// fixture partagée test-fixtures/member_access.json, que functions/test/auth.test.ts rejoue
// aussi contre functions/src/auth.ts. Sondes : beer_index/{nature} en get (isMember() seul)
// et ticket_status/github en lecture (isAdmin() seul).

import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Timestamp, seed } from "./helpers.mjs";
import { expectRule, state, useEnv } from "./setup.mjs";

useEnv();

const fixture = JSON.parse(
  readFileSync(new URL("../../test-fixtures/member_access.json", import.meta.url), "utf8"),
);

/// Contexte Firestore du cas : anonyme, ou jeton construit depuis la fixture.
function caseDb(c, index) {
  if (c.token === null) return state.env.unauthenticatedContext().firestore();
  const token = {
    email_verified: c.token.email_verified,
    firebase: { sign_in_provider: c.token.sign_in_provider },
  };
  if (c.token.email !== null) token.email = c.token.email;
  return state.env.authenticatedContext(`fixture-${index}`, token).firestore();
}

async function seedCase(c) {
  const docs = { "ticket_status/github": { token_invalid_since: null } };
  if (c.member !== null) {
    docs[`members/${c.member_key}`] = {
      ...c.member,
      invited_at: Timestamp.fromDate(new Date("2026-11-01T10:00:00Z")),
    };
  }
  await seed(state.env, docs);
}

describe("member_access.json — firestore.rules (P31)", () => {
  fixture.cases.forEach((c, index) => {
    const member = c.expect !== "none";
    const admin = c.expect === "admin";
    it(`${c.name} : isMember ${member ? "vrai" : "faux"}`, async () => {
      await seedCase(c);
      await expectRule(member, caseDb(c, index).doc("beer_index/fermentable").get());
    });
    it(`${c.name} : isAdmin ${admin ? "vrai" : "faux"}`, async () => {
      await seedCase(c);
      await expectRule(admin, caseDb(c, index).doc("ticket_status/github").get());
    });
  });
});
