// Socle IA (ADR-016, P57, P58) : postes de coût, politique et grille, plafond, client de
// l'API Messages (fetch simulé, aucun appel réel), coût, comptes du mois, `saveAiSettings`.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, describe, it } from "node:test";

import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import type { MemberLookup } from "../src/auth";
import { AI_MAX_TURNS } from "../src/config";
import { callClaude, messagesBody, readUsage, rejectionOf, withoutKey } from "../src/ai/claude";
import { AI_COST_CENTERS } from "../src/ai/costCenters";
import { nextParisMidnightMs, parisMidnightMs, parisMonth } from "../src/ai/parisTime";
import { callCostUsd } from "../src/ai/pricing";
import { countFor } from "../src/ai/quota";
import {
  resetRunSamplers,
  runClaudeTurn,
  type AiCaller,
  type ClaudeTurnRequest,
  type Logger,
} from "../src/ai/run";
import { handleSaveAiSettingsCall, SETTINGS_MAX_CHARS } from "../src/ai/saveAiSettings";
import {
  featurePolicy,
  policyConflict,
  pricingConflict,
  readPolicy,
  readPricing,
} from "../src/ai/settings";
import { nextCounters, usageExpiresAtMs } from "../src/ai/usage";
import type { LogEntry } from "../src/logging";
import { anthropicResponse, FEATURE, POLICY, PRICING } from "./aiFixtures";
import { FakeDb } from "./fakeFirestore";

const NOW = Date.parse("2026-11-15T10:00:00Z");
const DAY = "20261115";
const API_KEY = "sk-ant-api03-cle-secrete-du-test-AAAAAAAAAAAAAAAAAAAA";
const CC = "recipe_assistant_turn";

const BREWER: AiCaller = {
  uid: "u-brewer",
  email: "brasseur@example.com",
  isAdmin: false,
  founder: false,
};
const ADMIN: AiCaller = {
  uid: "u-admin",
  email: "admin@example.com",
  isAdmin: true,
  founder: false,
};

function errorResponse(status: number, type: string, message: string): Response {
  return new Response(JSON.stringify({ type: "error", error: { type, message } }), { status });
}

interface Harness {
  db: FakeDb;
  calls: { url: string; init: RequestInit }[];
  logs: { level: string; entry: LogEntry }[];
  run: (caller?: AiCaller, costCenter?: string) => Promise<unknown>;
}

function harness(
  respond: () => Promise<Response> | Response,
  seed: (db: FakeDb) => void = (db) => {
    db.seed("ai_config/policy", POLICY);
    db.seed("ai_config/pricing", PRICING);
  },
): Harness {
  const db = new FakeDb(() => NOW);
  seed(db);
  const calls: { url: string; init: RequestInit }[] = [];
  const logs: { level: string; entry: LogEntry }[] = [];
  const log: Logger = (level, entry) => logs.push({ level, entry });
  const request: ClaudeTurnRequest = {
    system: [{ text: "consignes", cache: true }],
    messages: [{ role: "user", content: '<DEMANDE>\n"Bonjour"\n</DEMANDE>' }],
    maxTokens: 4000,
    timeoutMs: 90_000,
    correlationId: "conv-12345678",
    promptVersion: 1,
  };
  return {
    db,
    calls,
    logs,
    run: (caller = ADMIN, costCenter = CC) =>
      runClaudeTurn(
        { costCenter, caller, build: () => request },
        {
          apiKey: () => API_KEY,
          kit: async () => db.kit(),
          fetchImpl: async (url, init) => {
            calls.push({ url, init });
            return respond();
          },
          nowMs: () => NOW,
          log,
        },
      ),
  };
}

async function refusalOf(promise: Promise<unknown>): Promise<HttpsError> {
  try {
    await promise;
  } catch (err) {
    assert.ok(err instanceof HttpsError, String(err));
    return err;
  }
  assert.fail("refus attendu");
}

function details(err: HttpsError): Record<string, unknown> {
  return err.details as Record<string, unknown>;
}

function quotaCount(db: FakeDb, uid: string): number {
  const features = db.read(`ai_quotas/${uid}`)?.features as Record<string, unknown> | undefined;
  return countFor(features?.[CC], DAY);
}

function usageOf(db: FakeDb, uid: string): Record<string, number> {
  const doc = db.read(`ai_usage/2026-11_${uid}`);
  return (doc?.features as Record<string, Record<string, number>>)[CC];
}

beforeEach(() => resetRunSamplers());

// ── Postes de coût (fixture partagée) ───────────────────────────────────────

describe("ai_cost_centers.json — AI_COST_CENTERS (logique dupliquée)", () => {
  const fixture = JSON.parse(
    readFileSync(join(__dirname, "../../../test-fixtures/ai_cost_centers.json"), "utf8"),
  ) as { cost_centers: unknown[] };
  it("liste égale à la fixture, dans l'ordre", () => {
    assert.deepEqual(
      AI_COST_CENTERS.map((c) => ({ ...c })),
      fixture.cost_centers,
    );
  });
});

// ── Politique et grille ─────────────────────────────────────────────────────

describe("settings : politique (ADR-016, section 4)", () => {
  it("politique valide lue", () => {
    const r = featurePolicy({ ...POLICY, updated_at: Timestamp.fromMillis(NOW) }, CC);
    assert.ok(r.ok);
    assert.equal(r.value.turns_per_day, 20);
  });
  it("absente : missing", () => {
    const r = featurePolicy(undefined, CC);
    assert.ok(!r.ok);
    assert.equal(r.motif, "missing");
  });
  it("poste absent : missing", () => {
    const r = featurePolicy({ version: 1, features: {} }, CC);
    assert.ok(!r.ok);
    assert.equal(r.motif, "missing");
  });
  it(`plafond ${AI_MAX_TURNS + 1} : out_of_bounds, champ nommé`, () => {
    const r = featurePolicy(
      { version: 1, features: { [CC]: { ...FEATURE, turns_per_day: AI_MAX_TURNS + 1 } } },
      CC,
    );
    assert.ok(!r.ok);
    assert.equal(r.motif, "out_of_bounds");
    assert.equal(r.field, `features.${CC}.turns_per_day`);
  });
  it("plafond 0 ou décimal refusé, 100 accepté", () => {
    for (const bad of [0, 2.5, "20"]) {
      assert.ok(
        !featurePolicy(
          { version: 1, features: { [CC]: { ...FEATURE, turns_per_conversation: bad } } },
          CC,
        ).ok,
      );
    }
    assert.ok(
      featurePolicy(
        { version: 1, features: { [CC]: { ...FEATURE, founder_turns_per_day: 100 } } },
        CC,
      ).ok,
    );
  });
  it("members_enabled en texte : unreadable", () => {
    const r = featurePolicy(
      { version: 1, features: { [CC]: { ...FEATURE, members_enabled: "true" } } },
      CC,
    );
    assert.ok(!r.ok);
    assert.equal(r.motif, "unreadable");
  });
  it("poste inconnu, clé inconnue, modèle hors motif : refusés", () => {
    assert.ok(
      !readPolicy({ version: 1, features: { autre_poste: FEATURE } }, { stored: false }).ok,
    );
    assert.ok(
      !readPolicy(
        { version: 1, features: { [CC]: { ...FEATURE, max_tokens: 9 } } },
        { stored: false },
      ).ok,
    );
    assert.ok(
      !readPolicy(
        { version: 1, features: { [CC]: { ...FEATURE, model: "gpt-5" } } },
        { stored: false },
      ).ok,
    );
    assert.ok(!readPolicy({ ...POLICY, updated_by_uid: "x" }, { stored: false }).ok);
  });
});

describe("settings : grille (ADR-016, section 5)", () => {
  it("grille valide lue", () => assert.ok(readPricing(PRICING, { stored: false }).ok));
  it("tarif de 1 001 refusé, 1 000 accepté", () => {
    const line = (v: number) => ({
      ...PRICING,
      models: { "claude-x": { ...PRICING.models["claude-sonnet-5-5"], output_usd_per_mtok: v } },
    });
    const r = readPricing(line(1001), { stored: false });
    assert.ok(!r.ok);
    assert.equal(r.field, "models.claude-x.output_usd_per_mtok");
    assert.ok(readPricing(line(1000), { stored: false }).ok);
    assert.ok(!readPricing(line(-1), { stored: false }).ok);
  });
  it("21 modèles refusés", () => {
    const models = Object.fromEntries(
      Array.from({ length: 21 }, (_, i) => [`claude-m-${i}`, PRICING.models["claude-haiku-5-5"]]),
    );
    const r = readPricing({ ...PRICING, models }, { stored: false });
    assert.ok(!r.ok);
    assert.equal(r.field, "models");
  });
  it("identifiant hors motif, effort inconnu ou en double, date fausse refusés", () => {
    const base = PRICING.models["claude-haiku-5-5"];
    assert.ok(!readPricing({ ...PRICING, models: { "gpt-5": base } }, { stored: false }).ok);
    assert.ok(
      !readPricing(
        { ...PRICING, models: { "claude-a": { ...base, efforts: ["turbo"] } } },
        { stored: false },
      ).ok,
    );
    assert.ok(
      !readPricing(
        { ...PRICING, models: { "claude-a": { ...base, efforts: ["low", "low"] } } },
        { stored: false },
      ).ok,
    );
    assert.ok(!readPricing({ ...PRICING, checked_on: "2026-02-30" }, { stored: false }).ok);
    assert.ok(!readPricing({ ...PRICING, source: "s".repeat(201) }, { stored: false }).ok);
  });
});

// ── Heures de Paris, coût, comptes ──────────────────────────────────────────

describe("jours et mois de Paris", () => {
  it("minuit suivant : heure d'hiver et d'été", () => {
    assert.equal(new Date(nextParisMidnightMs(NOW)).toISOString(), "2026-11-15T23:00:00.000Z");
    assert.equal(
      new Date(nextParisMidnightMs(Date.parse("2026-07-01T21:30:00Z"))).toISOString(),
      "2026-07-01T22:00:00.000Z",
    );
    // 23 h 30 à Paris le 31 décembre : minuit du 1er janvier.
    assert.equal(
      new Date(nextParisMidnightMs(Date.parse("2026-12-31T22:30:00Z"))).toISOString(),
      "2026-12-31T23:00:00.000Z",
    );
  });
  it("mois de Paris au changement de mois", () => {
    assert.equal(parisMonth(Date.parse("2026-11-30T23:30:00Z")), "2026-12");
    assert.equal(parisMonth(NOW), "2026-11");
  });
  it("expires_at du mois 2026-12 : 2028-01-01 à minuit de Paris", () => {
    assert.equal(usageExpiresAtMs("2026-12"), parisMidnightMs(2028, 1, 1));
    assert.equal(new Date(usageExpiresAtMs("2026-12")).toISOString(), "2027-12-31T23:00:00.000Z");
    assert.equal(new Date(usageExpiresAtMs("2026-05")).toISOString(), "2027-05-31T22:00:00.000Z");
  });
});

describe("pricing : coût d'un appel (ADR-016, section 5)", () => {
  it("jetons × tarifs de la ligne / 1 000 000", () => {
    const cost = callCostUsd(
      {
        input_tokens: 1000,
        output_tokens: 500,
        cache_creation_input_tokens: 200,
        cache_read_input_tokens: 2000,
      },
      PRICING.models["claude-sonnet-5-5"] as never,
    );
    // 1000×2 + 200×2,5 + 2000×0,2 + 500×10 = 7 900 → 0,0079 $
    assert.equal(cost, 0.0079);
  });
  it("compteurs : appel sans montant, appel en échec", () => {
    const priced = nextCounters(undefined, {
      kind: "answered",
      usage: {
        input_tokens: 10,
        output_tokens: 5,
        cache_creation_input_tokens: 1,
        cache_read_input_tokens: 2,
      },
      costUsd: 0.5,
    });
    assert.equal(priced.calls, 1);
    assert.equal(priced.cost_usd, 0.5);
    const unpriced = nextCounters(priced, { kind: "answered", usage: null, costUsd: null });
    assert.equal(unpriced.unpriced_calls, 1);
    assert.equal(unpriced.cost_usd, 0.5);
    const failed = nextCounters(unpriced, { kind: "failed" });
    assert.deepEqual([failed.calls, failed.failed_calls], [3, 1]);
  });
});

// ── Client de l'API Messages ────────────────────────────────────────────────

describe("claude : requête et réponses (P57)", () => {
  const req = {
    model: "claude-sonnet-5-5",
    effort: "medium" as const,
    system: [
      { text: "fixe", cache: true },
      { text: "contexte", cache: false },
    ],
    messages: [{ role: "user" as const, content: "q" }],
    maxTokens: 4000,
    timeoutMs: 1000,
  };
  it("corps : effort dans output_config, aucune clé thinking ni tools, cache sur la partie fixe", () => {
    const body = messagesBody(req);
    assert.deepEqual(body.output_config, { effort: "medium" });
    assert.ok(!("thinking" in body) && !("tools" in body) && !("tool_choice" in body));
    const system = body.system as Record<string, unknown>[];
    assert.deepEqual(system[0].cache_control, { type: "ephemeral" });
    assert.ok(!("cache_control" in system[1]));
    assert.ok(!("output_config" in messagesBody({ ...req, effort: null })));
  });
  it("un seul fetch : URL, en-têtes, redirect error, délai", async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const out = await callClaude(req, API_KEY, {
      fetchImpl: async (url, init) => {
        calls.push({ url, init });
        return anthropicResponse("Bonjour");
      },
    });
    assert.equal(out.kind, "answered");
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, "https://api.anthropic.com/v1/messages");
    const headers = calls[0].init.headers as Record<string, string>;
    assert.equal(headers["x-api-key"], API_KEY);
    assert.equal(headers["anthropic-version"], "2023-06-01");
    assert.equal(calls[0].init.redirect, "error");
    assert.ok(calls[0].init.signal instanceof AbortSignal);
  });
  it("refus 4xx classés ; crédit épuisé reconnu", () => {
    assert.equal(
      rejectionOf(400, "Your credit balance is too low to access the API."),
      "credit_exhausted",
    );
    assert.equal(
      rejectionOf(429, "You have reached your specified workspace API usage limits."),
      "credit_exhausted",
    );
    assert.equal(
      rejectionOf(429, "Number of request tokens has exceeded your rate limit"),
      "rate_limited",
    );
    assert.equal(rejectionOf(401, "invalid x-api-key"), "key_invalid");
    assert.equal(rejectionOf(404, "model: claude-x"), "model_unavailable");
    assert.equal(rejectionOf(400, "messages: field required"), "request_rejected");
  });
  it("usage illisible : null", () => {
    assert.equal(readUsage({ input_tokens: "1" }), null);
    assert.deepEqual(readUsage({ input_tokens: 1, output_tokens: 2 }), {
      input_tokens: 1,
      output_tokens: 2,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
    });
  });
  it("clé retirée de tout texte d'erreur", async () => {
    const logs: LogEntry[] = [];
    const out = await callClaude(req, API_KEY, {
      fetchImpl: async () => {
        throw new Error(`échec avec ${API_KEY}`);
      },
      log: (e) => logs.push(e),
    });
    assert.equal(out.kind, "failed");
    assert.ok(!JSON.stringify(out).includes(API_KEY));
    assert.ok(!JSON.stringify(logs).includes(API_KEY));
    assert.equal(withoutKey(`a ${API_KEY} b`, API_KEY), "a [clé retirée] b");
  });
  it("connexion refusée avant l'envoi : not_sent ; redirection : failed (tour gardé)", async () => {
    const refused = await callClaude(req, API_KEY, {
      fetchImpl: async () => {
        throw new TypeError("fetch failed", {
          cause: Object.assign(new Error("x"), { code: "ECONNREFUSED" }),
        });
      },
      log: () => undefined,
    });
    assert.equal(refused.kind, "not_sent");
    const redirect = await callClaude(req, API_KEY, {
      fetchImpl: async () => {
        throw new TypeError("fetch failed", { cause: new Error("unexpected redirect") });
      },
      log: () => undefined,
    });
    assert.equal(redirect.kind, "failed");
  });
});

// ── runClaudeTurn ───────────────────────────────────────────────────────────

describe("runClaudeTurn : refus avant l'appel (P57)", () => {
  it("poste inconnu : refusé sans appel ni décompte", async () => {
    const h = harness(() => anthropicResponse("x"));
    const err = await refusalOf(h.run(ADMIN, "autre_poste"));
    assert.equal(details(err).reason, "ai_cost_center_unknown");
    assert.equal(h.calls.length, 0);
    assert.equal(h.db.read(`ai_quotas/${ADMIN.uid}`), undefined);
  });
  it("politique absente : ai_policy_unavailable, rien compté, journal échantillonné", async () => {
    const h = harness(
      () => anthropicResponse("x"),
      () => undefined,
    );
    const err = await refusalOf(h.run());
    assert.equal(err.code, "failed-precondition");
    assert.equal(details(err).reason, "ai_policy_unavailable");
    assert.equal(h.calls.length, 0);
    assert.equal(h.db.read(`ai_quotas/${ADMIN.uid}`), undefined);
    await refusalOf(h.run());
    const policyLogs = h.logs.filter((l) => l.entry.message.includes("politique"));
    assert.equal(policyLogs.length, 1);
    assert.equal(policyLogs[0].level, "error");
    assert.equal(policyLogs[0].entry.extra?.motif, "missing");
  });
  it(`plafond ${AI_MAX_TURNS + 1} dans la politique : refusé sans décompte`, async () => {
    const h = harness(
      () => anthropicResponse("x"),
      (db) =>
        db.seed("ai_config/policy", {
          version: 1,
          features: { [CC]: { ...FEATURE, turns_per_day: AI_MAX_TURNS + 1 } },
        }),
    );
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_policy_unavailable");
    assert.equal(h.calls.length, 0);
  });
  it("poste fermé : refusé au brasseur avant la réservation, accepté pour l'admin", async () => {
    const h = harness(() => anthropicResponse("Bonjour"));
    const err = await refusalOf(h.run(BREWER));
    assert.equal(err.code, "permission-denied");
    assert.equal(details(err).reason, "ai_feature_closed");
    assert.equal(h.db.read(`ai_quotas/${BREWER.uid}`), undefined);
    assert.equal(h.calls.length, 0);
    const ok = (await h.run(ADMIN)) as { text: string };
    assert.equal(ok.text, "Bonjour");
  });
  it("poste ouvert : accepté pour le brasseur", async () => {
    const h = harness(
      () => anthropicResponse("Bonjour"),
      (db) => {
        db.seed("ai_config/policy", {
          version: 1,
          features: { [CC]: { ...FEATURE, members_enabled: true } },
        });
        db.seed("ai_config/pricing", PRICING);
      },
    );
    await h.run(BREWER);
    assert.equal(quotaCount(h.db, BREWER.uid), 1);
  });
});

describe("runClaudeTurn : plafond, rendu et garde du tour (P57)", () => {
  it("20 tours acceptés, 21e refusé sans appel", async () => {
    const h = harness(() => anthropicResponse("ok"));
    for (let i = 0; i < 20; i++) await h.run();
    const err = await refusalOf(h.run());
    assert.equal(err.code, "resource-exhausted");
    assert.equal(details(err).reason, "quota_exhausted");
    assert.equal(h.calls.length, 20);
    assert.equal(quotaCount(h.db, ADMIN.uid), 20);
    const quota = details(err).quota as Record<string, unknown>;
    assert.equal(quota.remaining, 0);
    assert.equal(quota.resets_at, "2026-11-15T23:00:00.000Z");
  });
  it("fondateur : founder_turns_per_day", async () => {
    const h = harness(() => anthropicResponse("ok"));
    const founder = { ...ADMIN, founder: true };
    const r = (await h.run(founder)) as { quota: { limit: number; remaining: number } };
    assert.deepEqual([r.quota.limit, r.quota.remaining], [60, 59]);
  });
  it("20 appels simultanés au 20e tour restant : un seul accepté", async () => {
    const h = harness(() => anthropicResponse("ok"));
    h.db.seed(`ai_quotas/${ADMIN.uid}`, {
      features: { [CC]: { day: DAY, count: 19, resets_at: Timestamp.fromMillis(NOW) } },
    });
    const results = await Promise.allSettled(Array.from({ length: 20 }, () => h.run()));
    assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
    assert.equal(h.calls.length, 1);
    assert.equal(quotaCount(h.db, ADMIN.uid), 20);
  });
  it("compteur d'un autre jour : repart de zéro", async () => {
    const h = harness(() => anthropicResponse("ok"));
    h.db.seed(`ai_quotas/${ADMIN.uid}`, {
      features: { [CC]: { day: "20261114", count: 20, resets_at: Timestamp.fromMillis(NOW) } },
    });
    await h.run();
    assert.equal(quotaCount(h.db, ADMIN.uid), 1);
  });
  it("réponse 400 : tour rendu, rien au mois", async () => {
    const h = harness(() => errorResponse(400, "invalid_request_error", "messages: bad"));
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_request_rejected");
    assert.equal(details(err).counted, false);
    assert.equal(quotaCount(h.db, ADMIN.uid), 0);
    assert.equal(h.db.read(`ai_usage/2026-11_${ADMIN.uid}`), undefined);
    assert.equal(h.calls.length, 1);
  });
  it("crédit épuisé (400) : « Crédit de l'IA épuisé pour ce mois. », tour rendu", async () => {
    const h = harness(() =>
      errorResponse(400, "invalid_request_error", "Your credit balance is too low."),
    );
    const err = await refusalOf(h.run());
    assert.equal(err.message, "Crédit de l'IA épuisé pour ce mois.");
    assert.equal(details(err).reason, "ai_credit_exhausted");
    assert.equal(quotaCount(h.db, ADMIN.uid), 0);
    assert.ok(!JSON.stringify(err.details).includes("credit balance"));
  });
  it("connexion impossible avant l'envoi : tour rendu", async () => {
    const h = harness(() => {
      throw new TypeError("fetch failed", {
        cause: Object.assign(new Error("x"), { code: "ENOTFOUND" }),
      });
    });
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_unreachable");
    assert.equal(quotaCount(h.db, ADMIN.uid), 0);
  });
  it("max_tokens : tour gardé, aucun second appel, ai_no_answer", async () => {
    const h = harness(() => anthropicResponse("coupé", { stop: "max_tokens" }));
    const err = await refusalOf(h.run());
    assert.equal(err.code, "aborted");
    assert.equal(details(err).reason, "ai_no_answer");
    assert.equal(details(err).counted, true);
    assert.equal(h.calls.length, 1);
    assert.equal(quotaCount(h.db, ADMIN.uid), 1);
    assert.equal(usageOf(h.db, ADMIN.uid).calls, 1);
    assert.ok(usageOf(h.db, ADMIN.uid).cost_usd > 0);
  });
  it("refusal : tour gardé, aucun second appel", async () => {
    const h = harness(() => anthropicResponse("", { stop: "refusal" }));
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_no_answer");
    assert.equal(h.calls.length, 1);
    assert.equal(quotaCount(h.db, ADMIN.uid), 1);
  });
  it("délai dépassé : tour gardé, failed_calls + 1", async () => {
    const h = harness(() => {
      throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
    });
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_timeout");
    assert.equal(details(err).counted, true);
    assert.equal(quotaCount(h.db, ADMIN.uid), 1);
    assert.deepEqual(
      [usageOf(h.db, ADMIN.uid).calls, usageOf(h.db, ADMIN.uid).failed_calls],
      [1, 1],
    );
  });
  it("529 et 500 : tour gardé, failed_calls + 1", async () => {
    for (const status of [529, 500]) {
      const h = harness(() => errorResponse(status, "overloaded_error", "Overloaded"));
      const err = await refusalOf(h.run());
      assert.equal(details(err).reason, "ai_failed");
      assert.equal(quotaCount(h.db, ADMIN.uid), 1);
      assert.equal(usageOf(h.db, ADMIN.uid).failed_calls, 1);
      assert.equal(h.calls.length, 1);
    }
  });
});

describe("runClaudeTurn : redirection et statuts 1xx, 3xx (P57)", () => {
  it("redirection refusée par fetch : tour gardé, failed_calls + 1", async () => {
    const h = harness(() => {
      throw new TypeError("fetch failed", { cause: new Error("unexpected redirect") });
    });
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_failed");
    assert.equal(details(err).counted, true);
    assert.equal(quotaCount(h.db, ADMIN.uid), 1);
    assert.equal(usageOf(h.db, ADMIN.uid).failed_calls, 1);
    assert.equal(h.calls.length, 1);
  });
  it("réponse 302 rendue sans erreur de fetch : tour gardé", async () => {
    const h = harness(() => new Response("", { status: 302 }));
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_failed");
    assert.equal(quotaCount(h.db, ADMIN.uid), 1);
    assert.equal(usageOf(h.db, ADMIN.uid).failed_calls, 1);
  });
});

describe("runClaudeTurn : corps d'erreur d'Anthropic hors des journaux", () => {
  const personal = "Ma recette secrète de la brasserie Dupont";
  for (const status of [400, 429, 500, 529]) {
    it(`${status} : statut et error.type journalisés, jamais error.message`, async () => {
      const h = harness(() =>
        errorResponse(status, "invalid_request_error", `champ « ${personal} »`),
      );
      const err = await refusalOf(h.run());
      const logs = JSON.stringify(h.logs);
      assert.ok(!logs.includes(personal), logs);
      assert.ok(!JSON.stringify(err.details).includes(personal));
      assert.ok(!err.message.includes(personal));
      const journal = h.logs.find((l) => l.entry.message === "IA : appel");
      assert.ok(journal);
      assert.equal(journal.entry.extra?.status, status);
      if (status < 500) {
        assert.equal(journal.entry.extra?.detail, `HTTP ${status} invalid_request_error`);
      }
    });
  }
  it("crédit épuisé reconnu par le texte, texte non journalisé", async () => {
    const h = harness(() =>
      errorResponse(400, "invalid_request_error", `Your credit balance is too low. ${personal}`),
    );
    const err = await refusalOf(h.run());
    assert.equal(details(err).reason, "ai_credit_exhausted");
    assert.ok(!JSON.stringify(h.logs).includes("credit balance"));
  });
  it("error.type hors forme : non journalisé", async () => {
    const h = harness(() => errorResponse(400, `x ${personal}`, "m"));
    await refusalOf(h.run());
    assert.ok(!JSON.stringify(h.logs).includes(personal));
  });
});

describe("runClaudeTurn : coût et comptes du mois (P57)", () => {
  it("appel chiffré : jetons, montant, member_email, expires_at", async () => {
    const h = harness(() => anthropicResponse("ok"));
    await h.run();
    const doc = h.db.read(`ai_usage/2026-11_${ADMIN.uid}`)!;
    assert.equal(doc.month, "2026-11");
    assert.equal(doc.uid, ADMIN.uid);
    assert.equal(doc.member_email, "admin@example.com");
    assert.equal((doc.expires_at as Timestamp).toMillis(), parisMidnightMs(2027, 12, 1));
    const u = usageOf(h.db, ADMIN.uid);
    assert.deepEqual(
      [
        u.calls,
        u.input_tokens,
        u.cache_write_tokens,
        u.cache_read_tokens,
        u.output_tokens,
        u.cost_usd,
        u.unpriced_calls,
      ],
      [1, 1000, 200, 2000, 500, 0.0079, 0],
    );
  });
  it("expires_at inchangé quand un appel s'ajoute au même mois", async () => {
    const h = harness(() => anthropicResponse("ok"));
    const fixed = Timestamp.fromMillis(Date.parse("2027-12-01T00:00:00Z"));
    h.db.seed(`ai_usage/2026-11_${ADMIN.uid}`, {
      month: "2026-11",
      expires_at: fixed,
      features: {},
    });
    await h.run();
    await h.run();
    const doc = h.db.read(`ai_usage/2026-11_${ADMIN.uid}`)!;
    assert.equal((doc.expires_at as Timestamp).toMillis(), fixed.toMillis());
    assert.equal(usageOf(h.db, ADMIN.uid).calls, 2);
  });
  it("grille absente : appel compté sans montant", async () => {
    const h = harness(
      () => anthropicResponse("ok"),
      (db) => db.seed("ai_config/policy", POLICY),
    );
    await h.run();
    const u = usageOf(h.db, ADMIN.uid);
    assert.deepEqual([u.calls, u.unpriced_calls, u.cost_usd], [1, 1, 0]);
    assert.ok(h.logs.some((l) => l.entry.message.includes("tarifs en panne")));
  });
  it("modèle absent de la grille : appel compté sans montant", async () => {
    const h = harness(
      () => anthropicResponse("ok"),
      (db) => {
        db.seed("ai_config/policy", POLICY);
        db.seed("ai_config/pricing", {
          ...PRICING,
          models: { "claude-haiku-5-5": PRICING.models["claude-haiku-5-5"] },
        });
      },
    );
    await h.run();
    assert.equal(usageOf(h.db, ADMIN.uid).unpriced_calls, 1);
  });
  it("journal de l'appel : poste, modèle, jetons, montant ; ni clé ni texte", async () => {
    const h = harness(() => anthropicResponse("Texte secret du modèle"));
    await h.run();
    const journal = h.logs.find((l) => l.entry.message === "IA : appel");
    assert.ok(journal);
    assert.equal(journal.entry.extra?.cost_center, CC);
    assert.equal(journal.entry.extra?.model, "claude-sonnet-5-5");
    assert.equal(journal.entry.extra?.cost_usd, 0.0079);
    assert.equal(journal.entry.extra?.correlation_id, "conv-12345678");
    const all = JSON.stringify(h.logs);
    assert.ok(!all.includes(API_KEY));
    assert.ok(!all.includes("Texte secret du modèle"));
    assert.ok(!all.includes("Bonjour"));
  });
  it("clé absente des journaux capturés, sur chaque issue", async () => {
    const responses: (() => Response)[] = [
      () => errorResponse(401, "authentication_error", `invalid x-api-key ${API_KEY}`),
      () => errorResponse(500, "api_error", `boom ${API_KEY}`),
      () => {
        throw new Error(`réseau ${API_KEY}`);
      },
    ];
    for (const respond of responses) {
      const h = harness(respond);
      const err = await refusalOf(h.run());
      assert.ok(!JSON.stringify(h.logs).includes(API_KEY));
      assert.ok(!JSON.stringify(err.details).includes(API_KEY));
      assert.ok(!err.message.includes(API_KEY));
    }
  });
});

// ── saveAiSettings (P58) ────────────────────────────────────────────────────

const google = (email: string, extra: Record<string, unknown> = {}) => ({
  email,
  email_verified: true,
  firebase: { sign_in_provider: "google.com" },
  ...extra,
});

const MEMBERS: Record<string, Record<string, unknown>> = {
  "admin@example.com": { role: "admin" },
  "brasseur@example.com": { role: "brewer" },
  "nonverifie@example.com": { role: "admin" },
  "motdepasse@example.com": { role: "admin" },
};

function settingsHarness() {
  const db = new FakeDb(() => NOW);
  let reads = 0;
  const lookup: MemberLookup = async (key) => {
    reads++;
    return MEMBERS[key] ?? null;
  };
  const save = (
    data: unknown,
    token: Record<string, unknown> | null = google("admin@example.com"),
  ) =>
    handleSaveAiSettingsCall(
      token === null ? { data } : { auth: { uid: "u-admin", token }, data },
      { kit: async () => db.kit(), lookup },
    );
  return { db, save, reads: () => reads };
}

describe("saveAiSettings : garde (P30, six profils)", () => {
  const cases: [string, Record<string, unknown> | null, string][] = [
    ["anonyme", null, "unauthenticated"],
    [
      "e-mail non vérifié",
      google("nonverifie@example.com", { email_verified: false }),
      "permission-denied",
    ],
    [
      "autre fournisseur",
      google("motdepasse@example.com", { firebase: { sign_in_provider: "password" } }),
      "permission-denied",
    ],
    ["non membre", google("inconnu@example.com"), "permission-denied"],
    ["brasseur", google("brasseur@example.com"), "permission-denied"],
  ];
  for (const [name, token, code] of cases) {
    it(`${name} : ${code}, rien lu ni écrit`, async () => {
      const h = settingsHarness();
      const err = await refusalOf(h.save({ kind: "pricing", value: PRICING }, token));
      assert.equal(err.code, code);
      assert.equal(h.db.writes.length, 0);
    });
  }
  it("admin : grille enregistrée avec updated_by_uid", async () => {
    const h = settingsHarness();
    assert.deepEqual(await h.save({ kind: "pricing", value: PRICING }), {
      saved: true,
      kind: "pricing",
    });
    const doc = h.db.read("ai_config/pricing")!;
    assert.equal(doc.updated_by_uid, "u-admin");
    assert.ok(doc.updated_at instanceof Timestamp);
  });
});

describe("saveAiSettings : validation et cohérence (P58)", () => {
  it("argument de plus de 32 Ko refusé", async () => {
    const h = settingsHarness();
    const err = await refusalOf(
      h.save({ kind: "pricing", value: { ...PRICING, source: "x".repeat(SETTINGS_MAX_CHARS) } }),
    );
    assert.equal(err.code, "invalid-argument");
    assert.equal(details(err).field, "");
  });
  it("clé inconnue, kind inconnu refusés", async () => {
    const h = settingsHarness();
    assert.equal(
      details(await refusalOf(h.save({ kind: "policy", value: POLICY, x: 1 }))).field,
      "x",
    );
    assert.equal(details(await refusalOf(h.save({ kind: "autre", value: POLICY }))).field, "kind");
  });
  it(`politique à ${AI_MAX_TURNS + 1} tours refusée, champ nommé`, async () => {
    const h = settingsHarness();
    await h.save({ kind: "pricing", value: PRICING });
    const err = await refusalOf(
      h.save({
        kind: "policy",
        value: { version: 1, features: { [CC]: { ...FEATURE, turns_per_conversation: 101 } } },
      }),
    );
    assert.equal(details(err).field, `features.${CC}.turns_per_conversation`);
    assert.equal(h.db.read("ai_config/policy"), undefined);
  });
  it("politique sans grille lisible : refusée", async () => {
    const h = settingsHarness();
    const err = await refusalOf(h.save({ kind: "policy", value: POLICY }));
    assert.equal(err.code, "failed-precondition");
    assert.equal(details(err).reason, "ai_pricing_unavailable");
  });
  it("modèle hors grille, effort hors efforts du modèle : refusés", async () => {
    const h = settingsHarness();
    await h.save({ kind: "pricing", value: PRICING });
    const model = await refusalOf(
      h.save({
        kind: "policy",
        value: { version: 1, features: { [CC]: { ...FEATURE, model: "claude-x" } } },
      }),
    );
    assert.equal(details(model).field, `features.${CC}.model`);
    const effort = await refusalOf(
      h.save({
        kind: "policy",
        value: { version: 1, features: { [CC]: { ...FEATURE, effort: "max" } } },
      }),
    );
    assert.equal(details(effort).field, `features.${CC}.effort`);
    const noEffort = await refusalOf(
      h.save({
        kind: "policy",
        value: {
          version: 1,
          features: { [CC]: { ...FEATURE, model: "claude-haiku-5-5", effort: "low" } },
        },
      }),
    );
    assert.equal(details(noEffort).field, `features.${CC}.effort`);
    assert.deepEqual(
      await h.save({
        kind: "policy",
        value: {
          version: 1,
          features: { [CC]: { ...FEATURE, model: "claude-haiku-5-5", effort: null } },
        },
      }),
      { saved: true, kind: "policy" },
    );
  });
  it("grille qui retire un modèle cité par un poste : refusée", async () => {
    const h = settingsHarness();
    await h.save({ kind: "pricing", value: PRICING });
    await h.save({ kind: "policy", value: POLICY });
    const err = await refusalOf(
      h.save({
        kind: "pricing",
        value: { ...PRICING, models: { "claude-haiku-5-5": PRICING.models["claude-haiku-5-5"] } },
      }),
    );
    assert.equal(details(err).field, "models.claude-sonnet-5-5");
    assert.equal(
      err.message,
      "Ce modèle sert au poste « Assistant de recette » : choisissez-en un autre d'abord.",
    );
  });
  it("grille qui ajoute des efforts à un modèle utilisé sans effort : refusée", async () => {
    const h = settingsHarness();
    await h.save({ kind: "pricing", value: PRICING });
    const haikuPolicy = {
      version: 1,
      features: { [CC]: { ...FEATURE, model: "claude-haiku-5-5", effort: null } },
    };
    await h.save({ kind: "policy", value: haikuPolicy });
    const haiku = { ...PRICING.models["claude-haiku-5-5"], efforts: ["low"] };
    const err = await refusalOf(
      h.save({
        kind: "pricing",
        value: { ...PRICING, models: { ...PRICING.models, "claude-haiku-5-5": haiku } },
      }),
    );
    assert.equal(err.code, "invalid-argument");
    assert.equal(details(err).field, "models.claude-haiku-5-5.efforts");
    assert.match(err.message, /utilise ce modèle sans effort/);
    assert.deepEqual(h.db.read("ai_config/pricing")?.models, PRICING.models);
  });
  it("pricingConflict nul : la politique enregistrée reste valide (policyConflict nul)", () => {
    const policies = [
      POLICY,
      { version: 1, features: { [CC]: { ...FEATURE, model: "claude-haiku-5-5", effort: null } } },
    ];
    const grids = [
      PRICING,
      { ...PRICING, models: { "claude-haiku-5-5": PRICING.models["claude-haiku-5-5"] } },
      {
        ...PRICING,
        models: {
          ...PRICING.models,
          "claude-haiku-5-5": { ...PRICING.models["claude-haiku-5-5"], efforts: ["low"] },
        },
      },
      {
        ...PRICING,
        models: {
          ...PRICING.models,
          "claude-sonnet-5-5": { ...PRICING.models["claude-sonnet-5-5"], efforts: [] },
        },
      },
    ];
    for (const rawPolicy of policies) {
      for (const rawGrid of grids) {
        const policy = readPolicy(rawPolicy, { stored: false });
        const grid = readPricing(rawGrid, { stored: false });
        assert.ok(policy.ok && grid.ok);
        assert.equal(
          pricingConflict(policy.value, grid.value) === null,
          policyConflict(policy.value, grid.value) === null,
        );
      }
    }
  });
  it("grille qui retire l'effort d'un poste : refusée", async () => {
    const h = settingsHarness();
    await h.save({ kind: "pricing", value: PRICING });
    await h.save({ kind: "policy", value: POLICY });
    const sonnet = { ...PRICING.models["claude-sonnet-5-5"], efforts: ["low", "high"] };
    const err = await refusalOf(
      h.save({
        kind: "pricing",
        value: { ...PRICING, models: { ...PRICING.models, "claude-sonnet-5-5": sonnet } },
      }),
    );
    assert.equal(details(err).field, "models.claude-sonnet-5-5.efforts");
    assert.equal(
      err.message,
      "L'effort « medium » sert au poste « Assistant de recette » : changez-le d'abord.",
    );
  });
});
