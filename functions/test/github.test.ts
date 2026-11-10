import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  classifyGithubFailure,
  GithubError,
  githubClient,
  isIssueOfTicket,
  type FetchLike,
} from "../src/tickets/github";
import { describeError, redactSecrets } from "../src/logging";
import { tokenInvalidReason } from "../src/tickets/tokenStatus";
import { nextCursor } from "../src/tickets/sync";
import { isPlausibleTicketId, issueUrl, lookupSince } from "../src/tickets/publish";

const OWNER_ID = 16348852;
const TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";

function reply(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

describe("classement des échecs (P25)", () => {
  const none = { rateLimitRemaining: null, retryAfter: null };
  it("401 : jeton", () => assert.equal(classifyGithubFailure(401, none, "", false), "token"));
  it("403 hors limite : jeton", () =>
    assert.equal(
      classifyGithubFailure(
        403,
        { rateLimitRemaining: "4000", retryAfter: null },
        "Resource not accessible",
        false,
      ),
      "token",
    ));
  it("403 quota épuisé : limite de débit", () =>
    assert.equal(
      classifyGithubFailure(403, { rateLimitRemaining: "0", retryAfter: null }, "", false),
      "rate_limit",
    ));
  it("403 limite secondaire : limite de débit", () => {
    assert.equal(
      classifyGithubFailure(403, { rateLimitRemaining: null, retryAfter: "60" }, "", false),
      "rate_limit",
    );
    assert.equal(
      classifyGithubFailure(403, none, "You have exceeded a secondary rate limit", false),
      "rate_limit",
    );
  });
  it("429 : limite de débit", () =>
    assert.equal(classifyGithubFailure(429, none, "", false), "rate_limit"));
  it("404 sur le dépôt : jeton ; sur une Issue : absente", () => {
    assert.equal(classifyGithubFailure(404, none, "", true), "token");
    assert.equal(classifyGithubFailure(404, none, "", false), "not_found");
  });
  it("410 : Issue absente", () =>
    assert.equal(classifyGithubFailure(410, none, "", false), "not_found"));
  it("500 : autre", () => assert.equal(classifyGithubFailure(500, none, "", false), "other"));
  it("code court du refus, jamais le jeton", () => {
    assert.equal(tokenInvalidReason(null), "secret_vide");
    assert.equal(tokenInvalidReason(new GithubError("token", 401, "x")), "http_401");
  });
});

describe("client GitHub", () => {
  it("crée l'Issue avec le jeton en en-tête et lit l'échéance du jeton", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fake: FetchLike = async (url, init) => {
      calls.push({ url, init });
      return reply(
        201,
        { number: 42, html_url: "https://github.com/ChinaFred/KassBeer/issues/42" },
        { "github-authentication-token-expiration": "2026-12-31 00:00:00 UTC" },
      );
    };
    const client = githubClient(TOKEN, fake);
    assert.equal(client.tokenExpirationHeader, undefined);
    const created = await client.createIssue({
      title: "t",
      body: "b",
      labels: ["source:app", "type:bug"],
    });
    assert.deepEqual(created, {
      number: 42,
      url: "https://github.com/ChinaFred/KassBeer/issues/42",
    });
    assert.equal(calls[0].url, "https://api.github.com/repos/ChinaFred/KassBeer/issues");
    assert.equal(calls[0].init.method, "POST");
    assert.equal(
      (calls[0].init.headers as Record<string, string>).authorization,
      `Bearer ${TOKEN}`,
    );
    assert.deepEqual(JSON.parse(String(calls[0].init.body)).labels, ["source:app", "type:bug"]);
    assert.equal(client.tokenExpirationHeader, "2026-12-31 00:00:00 UTC");
  });

  it("réponse sans en-tête d'échéance : null", async () => {
    const client = githubClient(TOKEN, async () =>
      reply(200, { number: 3, state: "open", labels: [] }),
    );
    await client.getIssue(3);
    assert.equal(client.tokenExpirationHeader, null);
  });

  it("404 à la création : jeton refusé ; le message ne contient pas le jeton", async () => {
    const client = githubClient(TOKEN, async () => reply(404, { message: "Not Found" }));
    await assert.rejects(
      client.createIssue({ title: "t", body: "b", labels: [] }),
      (err: unknown) => {
        assert.ok(err instanceof GithubError);
        assert.equal(err.kind, "token");
        assert.ok(!err.message.includes(TOKEN));
        return true;
      },
    );
  });

  it("404 sur une Issue : absente", async () => {
    const client = githubClient(TOKEN, async () => reply(404, { message: "Not Found" }));
    await assert.rejects(
      client.getIssue(9),
      (err: unknown) => err instanceof GithubError && err.kind === "not_found",
    );
  });

  it("réseau coupé : network", async () => {
    const client = githubClient(TOKEN, async () => {
      throw new TypeError("fetch failed");
    });
    await assert.rejects(
      client.getIssue(9),
      (err: unknown) => err instanceof GithubError && err.kind === "network",
    );
  });

  it("liste des Issues : PR écartées, filtre par étiquette et curseur", async () => {
    let url = "";
    const client = githubClient(TOKEN, async (u) => {
      url = u;
      return reply(200, [
        {
          number: 1,
          state: "open",
          labels: [{ name: "source:app" }],
          updated_at: "2026-11-10T10:00:00Z",
          comments: 2,
        },
        { number: 2, state: "open", labels: [], pull_request: {} },
      ]);
    });
    const issues = await client.listIssuesUpdatedSince(
      "source:app",
      "2026-11-10T09:00:00.000Z",
      30,
    );
    assert.deepEqual(
      issues.map((i) => i.number),
      [1],
    );
    assert.equal(issues[0].comments, 2);
    const params = new URL(url).searchParams;
    assert.equal(params.get("labels"), "source:app");
    assert.equal(params.get("since"), "2026-11-10T09:00:00.000Z");
    assert.equal(params.get("direction"), "asc");
  });

  it("reconnaissance d'une Issue déjà créée : liste source:app depuis created_at, sans recherche", async () => {
    const urls: string[] = [];
    const ref = "**Référence :** `abc123`";
    const item = (number: number, extra: Record<string, unknown>) => ({
      number,
      html_url: `https://github.com/ChinaFred/KassBeer/issues/${number}`,
      user: { id: OWNER_ID },
      body: ref,
      ...extra,
    });
    const page1 = [
      item(4, { body: "abc123 cité" }),
      item(5, { user: { id: 999 } }),
      item(6, { pull_request: {} }),
      ...Array.from({ length: 97 }, (_, i) => item(100 + i, { body: "autre" })),
    ];
    const page2 = [item(7, { body: `**Type :** Bug\n${ref}\n` })];
    const client = githubClient(TOKEN, async (u) => {
      urls.push(u);
      return reply(200, new URL(u).searchParams.get("page") === "1" ? page1 : page2);
    });
    assert.deepEqual(await client.findIssueByReference("abc123", "2026-11-10T09:50:00.000Z"), {
      number: 7,
      url: "https://github.com/ChinaFred/KassBeer/issues/7",
    });
    assert.equal(urls.length, 2);
    for (const u of urls) {
      const url = new URL(u);
      assert.equal(url.pathname, "/repos/ChinaFred/KassBeer/issues");
      assert.equal(url.searchParams.get("labels"), "source:app");
      assert.equal(url.searchParams.get("state"), "all");
      assert.equal(url.searchParams.get("since"), "2026-11-10T09:50:00.000Z");
    }
  });

  it("reconnaissance bornée à 5 pages, rien trouvé : null", async () => {
    let calls = 0;
    const full = Array.from({ length: 100 }, (_, i) => ({
      number: i + 1,
      html_url: "https://github.com/ChinaFred/KassBeer/issues/1",
      user: { id: OWNER_ID },
      body: "autre",
    }));
    const client = githubClient(TOKEN, async () => {
      calls++;
      return reply(200, full);
    });
    assert.equal(await client.findIssueByReference("abc123", null), null);
    assert.equal(calls, 5);
  });

  it("isIssueOfTicket : compte propriétaire, ligne exacte, pas une PR", () => {
    const base = {
      number: 3,
      html_url: "https://github.com/ChinaFred/KassBeer/issues/3",
      user: { id: OWNER_ID },
      body: "x\n**Référence :** `abc123`\ny",
    };
    assert.ok(isIssueOfTicket(base, "abc123", OWNER_ID));
    assert.ok(!isIssueOfTicket({ ...base, user: { id: 1 } }, "abc123", OWNER_ID));
    assert.ok(!isIssueOfTicket({ ...base, user: null }, "abc123", OWNER_ID));
    assert.ok(!isIssueOfTicket({ ...base, pull_request: {} }, "abc123", OWNER_ID));
    assert.ok(!isIssueOfTicket({ ...base, body: "**Référence :** `abc1234`" }, "abc123", OWNER_ID));
    assert.ok(
      !isIssueOfTicket({ ...base, body: "voir **Référence :** `abc123`" }, "abc123", OWNER_ID),
    );
  });

  it("lookupSince : created_at moins dix minutes, null s'il est illisible", () => {
    const ts = { toMillis: () => Date.parse("2026-11-10T10:00:00Z") };
    assert.equal(lookupSince(ts), "2026-11-10T09:50:00.000Z");
    assert.equal(lookupSince(undefined), null);
    assert.equal(lookupSince("2026-11-10"), null);
  });

  it("commentaires lus de la dernière page vers la première", async () => {
    const pages: string[] = [];
    const client = githubClient(TOKEN, async (u) => {
      pages.push(new URL(u).searchParams.get("page") ?? "");
      return reply(200, []);
    });
    for await (const _page of client.lastCommentsFirst(7, 250)) {
      void _page;
    }
    assert.deepEqual(pages, ["3", "2", "1"]);
  });

  it("fichier au commit : décodé du base64", async () => {
    const client = githubClient(TOKEN, async () =>
      reply(200, {
        encoding: "base64",
        content: Buffer.from("version: 0.3.1+50\n").toString("base64"),
      }),
    );
    assert.equal(await client.fileAtCommit("app/pubspec.yaml", "abcdef1"), "version: 0.3.1+50\n");
  });
});

describe("journal sans jeton", () => {
  it("jeton à grain fin et Bearer retirés", () => {
    assert.ok(!redactSecrets(`échec ${TOKEN}`).includes("secretsecret"));
    assert.ok(!redactSecrets("Authorization: Bearer abcdefghijkl").includes("abcdefghijkl"));
    assert.ok(!describeError(new Error(`boom ${TOKEN}`)).includes("secretsecret"));
  });
});

describe("curseur de la passe horaire", () => {
  const start = new Date("2026-11-10T12:00:00Z");
  it("page incomplète : début de la passe moins dix minutes", () => {
    assert.equal(
      nextCursor([{ updatedAt: "2026-11-10T11:00:00Z" }], 30, null, start),
      "2026-11-10T11:50:00.000Z",
    );
  });
  it("page pleine : date de la dernière Issue lue", () => {
    const issues = Array.from({ length: 30 }, (_, i) => ({
      updatedAt: `2026-11-10T10:${String(i).padStart(2, "0")}:00Z`,
    }));
    assert.equal(nextCursor(issues, 30, null, start), "2026-11-10T10:29:00.000Z");
  });
  it("page pleine qui n'avance pas : une seconde de plus", () => {
    const issues = Array.from({ length: 30 }, () => ({ updatedAt: "2026-11-10T10:00:00Z" }));
    assert.equal(
      nextCursor(issues, 30, "2026-11-10T10:00:00.000Z", start),
      "2026-11-10T10:00:01.000Z",
    );
  });
});

describe("publication", () => {
  it("identifiant de ticket plausible", () => {
    assert.ok(isPlausibleTicketId("aB3_x-9"));
    assert.ok(!isPlausibleTicketId('a" OR b'));
    assert.ok(!isPlausibleTicketId(""));
    assert.ok(!isPlausibleTicketId("x".repeat(129)));
  });
  it("adresse de l'Issue construite depuis son numéro", () => {
    assert.equal(issueUrl(12), "https://github.com/ChinaFred/KassBeer/issues/12");
  });
});
