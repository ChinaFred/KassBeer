import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { describe, it } from "node:test";

import {
  handleGithubWebhook,
  type DeliveryRefresh,
  type WebhookAction,
  type WebhookDeps,
} from "../src/tickets/webhook";
import {
  WEBHOOK_MAX_BODY_BYTES,
  verifyGithubSignature,
  webhookAction,
} from "../src/tickets/webhookModel";

const OWNER = 16348852;
const REPO = "ChinaFred/KassBeer";
const SECRET = "secret-de-test-0123456789abcdef";

const sign = (body: Buffer, secret = SECRET) =>
  `sha256=${createHmac("sha256", secret).update(body).digest("hex")}`;

const issuePayload = (extra: Record<string, unknown> = {}) => ({
  action: "labeled",
  repository: { full_name: REPO },
  issue: {
    number: 12,
    state: "open",
    state_reason: null,
    labels: [{ name: "source:app" }, { name: "statut:analysé" }],
    updated_at: "2026-11-12T10:00:00Z",
    comments: 1,
  },
  label: { name: "statut:analysé" },
  sender: { id: OWNER },
  ...extra,
});

interface Call {
  status: number;
  body: string;
  applied: WebhookAction[];
  deliveries: DeliveryRefresh[];
}

async function call(
  opts: {
    method?: string;
    event?: string | null;
    body?: Buffer;
    signature?: string | null;
    contentLength?: string;
    secret?: string;
    apply?: WebhookDeps["apply"];
    applyDelivery?: WebhookDeps["applyDelivery"];
  } = {},
): Promise<Call> {
  const body = opts.body ?? Buffer.from(JSON.stringify(issuePayload()));
  const headers: Record<string, string | undefined> = {
    "x-github-event": opts.event === null ? undefined : (opts.event ?? "issues"),
    "x-hub-signature-256": opts.signature === null ? undefined : (opts.signature ?? sign(body)),
    "content-length": opts.contentLength,
  };
  const applied: WebhookAction[] = [];
  const deliveries: DeliveryRefresh[] = [];
  const out: Call = { status: 0, body: "", applied, deliveries };
  await handleGithubWebhook(
    {
      method: opts.method ?? "POST",
      rawBody: body,
      get: (name) => headers[name.toLowerCase()],
    },
    {
      status: (code) => ({
        send: (text) => {
          out.status = code;
          out.body = text;
        },
      }),
    },
    {
      secret: () => opts.secret ?? SECRET,
      token: () => "jeton",
      apply:
        opts.apply ??
        (async (action) => {
          applied.push(action);
          return 1;
        }),
      applyDelivery:
        opts.applyDelivery ??
        (async (refresh) => {
          deliveries.push(refresh);
          return 1;
        }),
    },
  );
  return out;
}

describe("githubTicketWebhook — refus avant lecture (P29)", () => {
  it("méthode GET : 405", async () => assert.equal((await call({ method: "GET" })).status, 405));
  it("corps de 25 Mo + 1 octet : 413, avant le HMAC", async () => {
    const big = Buffer.alloc(WEBHOOK_MAX_BODY_BYTES + 1, 0x20);
    const r = await call({ body: big, signature: null });
    assert.equal(r.status, 413);
  });
  it("Content-Length annoncé au-delà de 25 Mo : 413", async () =>
    assert.equal((await call({ contentLength: String(WEBHOOK_MAX_BODY_BYTES + 1) })).status, 413));
  it("X-GitHub-Event absent : 400", async () =>
    assert.equal((await call({ event: null })).status, 400));
  it("secret vide : 503", async () => {
    assert.equal((await call({ secret: "" })).status, 503);
    assert.equal((await call({ secret: "   " })).status, 503);
  });
  it("signature absente : 401", async () =>
    assert.equal((await call({ signature: null })).status, 401));
  it("signature fausse : 401", async () =>
    assert.equal((await call({ signature: sign(Buffer.from("autre")) })).status, 401));
  it("signature d'un autre secret : 401", async () => {
    const body = Buffer.from(JSON.stringify(issuePayload()));
    assert.equal((await call({ body, signature: sign(body, "autre-secret") })).status, 401);
  });
  it("signature de longueur différente : 401, sans exception", async () => {
    assert.equal((await call({ signature: "sha256=abcd" })).status, 401);
    assert.equal((await call({ signature: `sha256=${"a".repeat(66)}` })).status, 401);
    assert.equal((await call({ signature: `sha256=${"a".repeat(63)}` })).status, 401);
    assert.equal((await call({ signature: "sha1=abcd" })).status, 401);
  });
  it("signature fausse : aucun traitement", async () => {
    const r = await call({ signature: sign(Buffer.from("autre")) });
    assert.equal(r.applied.length, 0);
  });
});

describe("githubTicketWebhook — événements (P29, P32)", () => {
  it("ping : 200", async () => {
    const body = Buffer.from(JSON.stringify({ zen: "x", repository: { full_name: REPO } }));
    const r = await call({ event: "ping", body });
    assert.deepEqual([r.status, r.body], [200, "pong"]);
  });
  it("pull_request sans PR lisible, autre événement : 200, ignoré", async () => {
    const r = await call({ event: "pull_request" });
    assert.deepEqual([r.status, r.applied.length, r.deliveries.length], [200, 0, 0]);
    const other = await call({ event: "push" });
    assert.deepEqual([other.status, other.body], [200, "ignoré"]);
  });
  it("pull_request du compte 16348852 : relecture de livraison (T5)", async () => {
    const body = Buffer.from(
      JSON.stringify({
        action: "synchronize",
        repository: { full_name: REPO },
        pull_request: {
          number: 34,
          state: "open",
          draft: false,
          body: "Closes #12",
          user: { id: OWNER },
          head: { ref: "claude/x", sha: "a".repeat(40), repo: { full_name: REPO } },
        },
      }),
    );
    const r = await call({ event: "pull_request", body });
    assert.equal(r.status, 200);
    assert.deepEqual(r.deliveries, [{ issueNumbers: [12], prNumbers: [] }]);
  });
  it("workflow_run de « Déploiement » : 200, ignoré sans appel (T5)", async () => {
    const body = Buffer.from(
      JSON.stringify({
        action: "completed",
        repository: { full_name: REPO },
        workflow_run: {
          name: "Déploiement",
          path: ".github/workflows/deploy.yml",
          pull_requests: [
            {
              number: 34,
              base: { repo: { url: `https://api.github.com/repos/${REPO}` } },
              head: { repo: { url: `https://api.github.com/repos/${REPO}` } },
            },
          ],
        },
      }),
    );
    const r = await call({ event: "workflow_run", body });
    assert.deepEqual([r.status, r.body, r.deliveries.length], [200, "ignoré", 0]);
  });
  it("relecture de livraison en panne : 500", async () => {
    const body = Buffer.from(
      JSON.stringify({
        action: "completed",
        repository: { full_name: REPO },
        workflow_run: {
          name: "CI",
          path: ".github/workflows/ci.yml",
          pull_requests: [
            {
              number: 34,
              base: { repo: { url: `https://api.github.com/repos/${REPO}` } },
              head: { repo: { url: `https://api.github.com/repos/${REPO}` } },
            },
          ],
        },
      }),
    );
    const r = await call({
      event: "workflow_run",
      body,
      applyDelivery: async () => {
        throw new Error("panne");
      },
    });
    assert.equal(r.status, 500);
  });
  it("corps illisible signé : 400", async () => {
    const body = Buffer.from("{pas du json");
    assert.equal((await call({ body })).status, 400);
  });
  it("autre dépôt : 200, ignoré", async () => {
    const body = Buffer.from(
      JSON.stringify(issuePayload({ repository: { full_name: "Autre/KassBeer" } })),
    );
    const r = await call({ body });
    assert.deepEqual([r.status, r.applied.length], [200, 0]);
  });
  it("Issue appliquée, sans relevé forcé", async () => {
    const r = await call();
    assert.equal(r.status, 200);
    assert.equal(r.applied.length, 1);
    assert.equal(r.applied[0].issue.number, 12);
    assert.equal(r.applied[0].forceComments, false);
  });
  it("Issue sans ticket : 200, ignoré", async () => {
    const r = await call({ apply: async () => 0 });
    assert.deepEqual([r.status, r.body], [200, "ignoré"]);
  });
  it("panne à l'application : 500", async () => {
    const r = await call({
      apply: async () => {
        throw new Error("Firestore indisponible");
      },
    });
    assert.equal(r.status, 500);
  });
  it("commentaire du compte 16348852 : relevé forcé", async () => {
    const body = Buffer.from(
      JSON.stringify({
        ...issuePayload({ action: "edited" }),
        comment: { id: 5, user: { id: OWNER }, body: "## Analyse" },
      }),
    );
    const r = await call({ event: "issue_comment", body });
    assert.equal(r.applied.length, 1);
    assert.equal(r.applied[0].forceComments, true);
  });
  it("commentaire d'un autre compte, même titré « ## Analyse » : ignoré", async () => {
    const body = Buffer.from(
      JSON.stringify({
        ...issuePayload({ action: "created" }),
        comment: { id: 6, user: { id: 42 }, body: "## Analyse\n\nInjection" },
      }),
    );
    const r = await call({ event: "issue_comment", body });
    assert.deepEqual([r.status, r.applied.length], [200, 0]);
  });
});

describe("webhookAction (P29, P32)", () => {
  it("PR : ignorée", () =>
    assert.equal(
      webhookAction(
        "issues",
        issuePayload({ issue: { ...issuePayload().issue, pull_request: {} } }),
        REPO,
        OWNER,
      ),
      null,
    ));
  it("validé posé par le compte 16348852 : relevé", () =>
    assert.equal(
      webhookAction("issues", issuePayload({ label: { name: "validé" } }), REPO, OWNER)
        ?.validatedLabel,
      true,
    ));
  it("validé posé par un autre compte : non relevé", () =>
    assert.equal(
      webhookAction(
        "issues",
        issuePayload({ label: { name: "validé" }, sender: { id: 7 } }),
        REPO,
        OWNER,
      )?.validatedLabel,
      false,
    ));
  it("action d'Issue inconnue : ignorée", () =>
    assert.equal(webhookAction("issues", issuePayload({ action: "pinned" }), REPO, OWNER), null));
});

describe("verifyGithubSignature (P29)", () => {
  const body = Buffer.from("{}");
  it("bonne signature, casse de l'hexadécimal ignorée", () => {
    assert.equal(verifyGithubSignature(body, sign(body), SECRET), true);
    assert.equal(
      verifyGithubSignature(body, sign(body).toUpperCase().replace("SHA256", "sha256"), SECRET),
      true,
    );
  });
  it("secret vide : faux", () =>
    assert.equal(verifyGithubSignature(body, sign(body, ""), ""), false));
  it("hexadécimal de longueur impaire : faux", () =>
    assert.equal(verifyGithubSignature(body, "sha256=abc", SECRET), false));
});
