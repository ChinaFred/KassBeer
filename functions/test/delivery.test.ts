// Livraison et reprise du développement (ADR-008, T5) : PR éligible, fichiers sensibles, CI
// (P43, P45), verrou des livraisons (P44), comptes rendus (P45), reprise (P47), décisions
// permises (P42), événements du webhook (P29). Firestore en mémoire, GitHub et l'API Routines
// par des `fetch` simulés.

import assert from "node:assert/strict";
import { afterEach, describe, it, mock } from "node:test";

import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import * as firestoreModule from "../src/firestore";
import type { LogEntry } from "../src/logging";
import { allowedDecisions, REJECT_DELIVERY_RUNNING } from "../src/tickets/decisionModel";
import { decideTicket } from "../src/tickets/decisions";
import {
  DELIVERY_ONLY_SENSITIVE_PATTERNS,
  FORBIDDEN_DEVELOPMENT_PATTERNS,
  NETWORK_RULES_ACK_TITLE,
  NETWORK_RULES_PATTERNS,
  SENSITIVE_DELIVERY_PATTERNS,
  commentCarriesAck,
  isForbiddenDevelopmentPath,
  isNetworkRulesPath,
  networkRulesAckBody,
  networkRulesAckValid,
  networkRulesControls,
  networkRulesFiles,
  readNetworkRulesAck,
  writeDeliveryState,
  ciSummary,
  deliveryReportsFromComments,
  deliveryRunningElsewhereMessage,
  deliveryState,
  isEligibleDeliveryPr,
  isSensitiveDeliveryPath,
  latestCiRunsByEvent,
  refreshDeliveryFromRun,
  releaseDeliveryLockIfLeft,
  sensitiveDeliveryPath,
  writeDeliveryReports,
} from "../src/tickets/delivery";
import {
  githubClient,
  readCiRun,
  readPullRequest,
  type CiRunView,
  type FetchLike,
} from "../src/tickets/github";
import {
  DELIVERY_LEASE_MS,
  LAUNCH_LEASE_MS,
  handleDeliveryCall,
  handleDevelopmentCall,
  handleLaunchCall,
  readDeliveryArgs,
  launchLeaseMs,
  launchTicketSession,
  readLaunchMode,
  type LaunchDeps,
} from "../src/tickets/launch";
import {
  LAUNCH_IN_PROGRESS_NOT_BY_APP_MESSAGE,
  launchCommandText,
  runningLaunch,
} from "../src/tickets/launchModel";
import { ALLOWED_DECISIONS_VERSION, backfillAllowedDecisions } from "../src/tickets/sync";
import { deliveryRefreshFromEvent } from "../src/tickets/webhookModel";
import { FakeDb } from "./fakeFirestore";

const OWNER = 16348852;
const REPO = "ChinaFred/KassBeer";
const NOW = Date.parse("2026-11-14T09:00:00Z");
const DAY = "20261114";
const HOUR = 3_600_000;
const HEAD = "a".repeat(40);
const ROUTINE_TOKEN = "sk-ant-oat01-routine-secret-AAAAAAAAAAAAAAAAAAAAAAAA";
const ROUTINE_ID = "trig_01ABCdef";
const GH_TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";
const SESSION = "https://claude.ai/code/session_01XYZ";
const BY_APP = Timestamp.fromMillis(NOW - 24 * HOUR);

afterEach(() => mock.restoreAll());

// ── Données GitHub simulées ─────────────────────────────────────────────────

function rawPr(number: number, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    number,
    state: "open",
    draft: false,
    body: "Corrige le calcul.\n\nCloses #12",
    user: { id: OWNER },
    head: { ref: `claude/ticket-12-x`, sha: HEAD, repo: { full_name: REPO } },
    ...extra,
  };
}

function rawRun(
  event: string,
  status: string,
  conclusion: string | null,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: event === "push" ? 1 : 2,
    name: "CI",
    path: ".github/workflows/ci.yml",
    event,
    head_sha: HEAD,
    head_repository: { full_name: REPO },
    status,
    conclusion,
    created_at: "2026-11-14T08:00:00Z",
    updated_at: "2026-11-14T08:20:00Z",
    ...extra,
  };
}

const GREEN = [
  rawRun("push", "completed", "success"),
  rawRun("pull_request", "completed", "success"),
];
const RED = [
  rawRun("push", "completed", "success"),
  rawRun("pull_request", "completed", "failure"),
];

interface Scene {
  labels?: string[];
  prs?: Record<string, unknown>[];
  files?: Record<string, unknown>[];
  runs?: Record<string, unknown>[];
  /** Code HTTP rendu par `GET /actions/runs` (200 par défaut). */
  runsStatus?: number;
  /** Code HTTP rendu par `GET /issues/{n}` (200 par défaut). */
  issueStatus?: number;
  /** Commentaires de l'Issue (ADR-020 : accord) ; un `POST` y ajoute le sien. */
  comments?: Record<string, unknown>[];
  /** Code HTTP rendu par `POST /issues/{n}/comments` (201 par défaut). */
  commentStatus?: number;
}

function githubFetch(scene: Scene, calls: string[]): FetchLike {
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  return async (url, init) => {
    const u = new URL(url);
    const path = u.pathname.replace(`/repos/${REPO}`, "");
    const method = init?.method ?? "GET";
    calls.push(`${method === "GET" ? "" : `${method} `}${path}${u.search}`);
    const comments = /^\/issues\/\d+\/comments$/.test(path);
    if (comments && method === "POST") {
      if (scene.commentStatus !== undefined) return json(scene.commentStatus, { message: "panne" });
      const list = (scene.comments ??= []);
      const id = 9000 + list.length;
      const body = (JSON.parse(String(init?.body)) as { body: string }).body;
      list.push({ id, user: { id: OWNER }, body, created_at: "2026-11-14T09:00:00Z" });
      return json(201, { id });
    }
    if (comments) {
      const page = Number(u.searchParams.get("page") ?? "1");
      return json(200, (scene.comments ?? []).slice((page - 1) * 100, page * 100));
    }
    if (/^\/issues\/\d+$/.test(path)) {
      if (scene.issueStatus !== undefined) return json(scene.issueStatus, { message: "panne" });
      return json(200, {
        number: Number(path.split("/").pop()),
        state: "open",
        state_reason: null,
        labels: (scene.labels ?? ["source:app", "validé", "statut:en-cours"]).map((name) => ({
          name,
        })),
        comments: (scene.comments ?? []).length,
        updated_at: "2026-11-14T08:00:00Z",
      });
    }
    const prs = scene.prs ?? [rawPr(34)];
    if (path === "/pulls") return json(200, prs);
    const detail = /^\/pulls\/(\d+)$/.exec(path);
    if (detail !== null) {
      const pr = prs.find((p) => p.number === Number(detail[1]));
      return pr === undefined ? json(404, { message: "Not Found" }) : json(200, pr);
    }
    if (/^\/pulls\/\d+\/files$/.test(path)) {
      const files = scene.files ?? [{ filename: "app/lib/main.dart" }];
      const page = Number(u.searchParams.get("page") ?? "1");
      return json(200, files.slice((page - 1) * 100, page * 100));
    }
    if (path === "/actions/runs") {
      if (scene.runsStatus !== undefined) {
        return json(scene.runsStatus, {
          message: "Resource not accessible by personal access token",
        });
      }
      return json(200, { workflow_runs: scene.runs ?? GREEN });
    }
    return json(500, { message: `inattendu ${path}` });
  };
}

// ── Base en mémoire et lancement ────────────────────────────────────────────

interface Harness {
  db: FakeDb;
  logs: { level: string; entry: LogEntry }[];
  routineCalls: { url: string; body: unknown }[];
  githubCalls: string[];
  clock: { now: number };
  deps: (over?: Partial<LaunchDeps>) => LaunchDeps;
}

function harness(
  scene: Scene = {},
  routine: (n: number) => Promise<Response> = async () =>
    new Response(JSON.stringify({ claude_code_session_url: SESSION }), { status: 200 }),
): Harness {
  const clock = { now: NOW };
  const db = new FakeDb(() => clock.now);
  const logs: Harness["logs"] = [];
  const routineCalls: Harness["routineCalls"] = [];
  const githubCalls: string[] = [];
  const deps = (over: Partial<LaunchDeps> = {}): LaunchDeps => ({
    routine: () => ({ id: ROUTINE_ID, token: ROUTINE_TOKEN }),
    githubToken: () => GH_TOKEN,
    kit: async () => db.kit(),
    nowMs: () => clock.now,
    log: (level, entry) => logs.push({ level, entry }),
    fetchRoutine: async (url, init) => {
      routineCalls.push({ url, body: init.body });
      return routine(routineCalls.length);
    },
    fetchGithub: githubFetch(scene, githubCalls),
    applyIssue: async () => undefined,
    markTokenInvalid: async () => undefined,
    recordTokenAccepted: async () => undefined,
    ...over,
  });
  return { db, logs, routineCalls, githubCalls, clock, deps };
}

function seedTicket(h: Harness, id = "t-1", extra: Record<string, unknown> = {}): void {
  h.db.seed(`tickets/${id}`, {
    status: "in_progress",
    github_issue_number: 12,
    validated_by_app_at: BY_APP,
    ...extra,
  });
}

const quota = (h: Harness) => h.db.read(`ticket_quotas/launch_${DAY}`)?.count ?? 0;
const lock = (h: Harness) =>
  h.db.read("ticket_status/launches")?.delivery_running as
    Record<string, unknown> | null | undefined;
const history = (h: Harness, id = "t-1") =>
  (h.db.read(`tickets/${id}/admin/launches`)?.entries ?? []) as Record<string, unknown>[];
const details = (err: HttpsError) => err.details as Record<string, unknown>;

async function refusal(promise: Promise<unknown>): Promise<HttpsError> {
  try {
    await promise;
  } catch (err) {
    assert.ok(err instanceof HttpsError, String(err));
    return err;
  }
  assert.fail("refus attendu");
}

/** Refus sans décompte, sans appel de la routine, sans verrou ni entrée d'historique. */
async function refusedWithoutCount(
  h: Harness,
  action: "livraison" | "reprise",
  code: string,
): Promise<HttpsError> {
  const err = await refusal(launchTicketSession("t-1", action, "admin-uid", h.deps()));
  assert.equal(details(err).code, code, String(details(err).reason));
  assert.equal(err.code, "failed-precondition");
  assert.equal(h.routineCalls.length, 0);
  assert.equal(quota(h), 0);
  assert.ok(lock(h) === undefined || lock(h) === null, "verrou rendu");
  assert.equal(history(h).length, 0);
  assert.equal(h.db.read("tickets/t-1")?.decision_lease_until, undefined);
  return err;
}

// ── Fichiers sensibles (P43) ────────────────────────────────────────────────

describe("livraison : fichiers sensibles (P43)", () => {
  it("chemins sensibles, casse ignorée, à toute profondeur pour les noms", () => {
    for (const path of [
      ".github/workflows/ci.yml",
      ".GitHub/x",
      ".claude/settings.json",
      "app/.claude/settings.json",
      "app/.claude/skills/x/SKILL.md",
      "scripts/check-version.mjs",
      "scripts/check-agents.mjs",
      "scripts/garder-apk-en-ligne.sh",
      "Scripts/changelog-recent.mjs",
      "claude.md",
      "docs/CLAUDE.md",
      "app/lib/features/CLAUDE.md",
      "docs/claude.local.md",
      "x/.mcp.json",
      "firebase.json",
      "FIRESTORE.RULES",
      "functions/package-lock.json",
      "functions/prettier.config.mjs",
      "ingest/prettier.config.js",
      "app/android/build.gradle",
      "app/android/app/build.gradle.kts",
      "app/android/settings.gradle.kts",
      "app/android/gradle.properties",
      "app/android/gradle/wrapper/gradle-wrapper.properties",
      "app/pubspec.lock",
      "brewing/pubspec.lock",
      "exchange/pubspec.lock",
      "app/android/gradlew",
      "app/android/GRADLEW.bat",
      "app/hook/build.dart",
      "brewing/hook/build.dart",
      "exchange/hook/link.dart",
      "hook/build.dart",
      "functions/src/auth.ts",
      "functions/src/config.ts",
      "functions/src/tickets/delivery.ts",
      "test-fixtures/member_access.json",
    ]) {
      assert.equal(isSensitiveDeliveryPath(path), true, path);
    }
  });

  it("chemins ordinaires : permis", () => {
    for (const path of [
      "app/lib/main.dart",
      "app/pubspec.yaml",
      "functions/src/index.ts",
      "functions/test/x.test.ts",
      "docs/github/x.md",
      "scripts.md",
      "app/android/app/src/main/AndroidManifest.xml",
      "app/android/app/src/main/kotlin/fr/kassbeer/MainActivity.kt",
      "documentation/CHANGELOG.md",
      "sub/firebase.json",
      "functions/src/tickets/launch.ts",
      "functions/test/auth.test.ts",
      "app/lib/hooks.dart",
      "test-fixtures/autre.json",
      "app/android/gradlew.kts",
    ]) {
      assert.equal(isSensitiveDeliveryPath(path), false, path);
    }
  });

  it("renommage depuis .github/x : refusé par l'ancien chemin", () =>
    assert.equal(
      sensitiveDeliveryPath([{ filename: "docs/x.yml", previousFilename: ".github/x" }]),
      ".github/x",
    ));

  it("liste écrite une fois : 34 motifs, sans doublon", () => {
    assert.equal(new Set(SENSITIVE_DELIVERY_PATTERNS).size, SENSITIVE_DELIVERY_PATTERNS.length);
    assert.equal(SENSITIVE_DELIVERY_PATTERNS.length, 34);
  });
});

// ── PR éligible, CI, état (P43, P45) ────────────────────────────────────────

describe("livraison : PR éligible et CI (P43, P45)", () => {
  const pr = (extra: Record<string, unknown> = {}) => readPullRequest(rawPr(34, extra))!;

  it("PR du compte 16348852, branche claude/ de ce dépôt, Closes #12 seul : éligible", () =>
    assert.equal(isEligibleDeliveryPr(pr(), 12), true));

  it("copie du dépôt, autre auteur, brouillon, autre branche, deux Issues : non éligible", () => {
    const cases: Record<string, unknown>[] = [
      { head: { ref: "claude/x", sha: HEAD, repo: { full_name: "Autre/KassBeer" } } },
      { user: { id: 1 } },
      { user: { id: String(OWNER) } },
      { draft: true },
      { state: "closed" },
      { head: { ref: "feature/x", sha: HEAD, repo: { full_name: REPO } } },
      { body: "Closes #12, closes #13" },
      { body: "Voir #12" },
    ];
    for (const extra of cases) assert.equal(isEligibleDeliveryPr(pr(extra), 12), false);
  });

  const runs = (raw: Record<string, unknown>[]): CiRunView[] => raw.map(readCiRun);

  it("deux événements verts : verte ; run push vert et run pull_request rouge : rouge", () => {
    const green = ciSummary(latestCiRunsByEvent(runs(GREEN), HEAD));
    assert.equal(green.green, true);
    assert.equal(green.red, false);
    assert.equal(green.status, "completed");
    const red = ciSummary(latestCiRunsByEvent(runs(RED), HEAD));
    assert.equal(red.green, false);
    assert.equal(red.red, true);
    assert.equal(red.conclusion, "failure");
  });

  it("dernier run de chaque événement : un run relancé vert remplace l'ancien rouge", () => {
    const later = rawRun("pull_request", "completed", "success", {
      id: 3,
      created_at: "2026-11-14T08:30:00Z",
    });
    const s = ciSummary(latestCiRunsByEvent(runs([...RED, later]), HEAD));
    assert.equal(s.green, true);
  });

  it("run en cours : ni verte ni rouge ; cancelled : ni verte ni rouge", () => {
    const running = ciSummary(
      latestCiRunsByEvent(runs([GREEN[0], rawRun("pull_request", "in_progress", null)]), HEAD),
    );
    assert.deepEqual([running.status, running.green, running.red], ["in_progress", false, false]);
    const cancelled = ciSummary(
      latestCiRunsByEvent(runs([GREEN[0], rawRun("pull_request", "completed", "cancelled")]), HEAD),
    );
    assert.deepEqual(
      [cancelled.green, cancelled.red, cancelled.conclusion],
      [false, false, "cancelled"],
    );
    for (const c of ["timed_out", "startup_failure"]) {
      // Run rouge : la CI est rouge même sans le run de l'autre événement.
      const s = ciSummary(latestCiRunsByEvent(runs([rawRun("push", "completed", c)]), HEAD));
      assert.equal(s.red, true, c);
    }
  });

  it("un seul run push vert, sans run pull_request : ni verte ni rouge, en attente", () => {
    for (const only of [[GREEN[0]], [GREEN[1]]]) {
      const s = ciSummary(latestCiRunsByEvent(runs(only), HEAD));
      assert.deepEqual([s.status, s.green, s.red], ["pending", false, false]);
    }
  });

  it("run d'une copie du dépôt sur le même commit : ignoré", () => {
    const fork = rawRun("pull_request", "completed", "success", {
      id: 9,
      created_at: "2026-11-14T08:40:00Z",
      head_repository: { full_name: "Autre/KassBeer" },
    });
    const s = ciSummary(latestCiRunsByEvent(runs([...RED, fork]), HEAD));
    assert.deepEqual([s.green, s.red], [false, true]);
    const noRepo = rawRun("push", "completed", "success", { head_repository: null });
    assert.deepEqual(latestCiRunsByEvent(runs([noRepo]), HEAD), []);
  });

  it("autre workflow (« Déploiement », ou nommé CI à un autre chemin) et autre tête : ignorés", () => {
    const other = [
      rawRun("push", "completed", "failure", {
        name: "Déploiement",
        path: ".github/workflows/deploy.yml",
      }),
      rawRun("push", "completed", "failure", { path: ".github/workflows/autre.yml" }),
      rawRun("push", "completed", "failure", { head_sha: "b".repeat(40) }),
    ];
    assert.deepEqual(latestCiRunsByEvent(runs(other), HEAD), []);
    assert.equal(ciSummary([]).status, null);
  });

  it("liste des PR tronquée : aucune PR retenue, ni prête ni à relancer", () => {
    const s = deliveryState({
      ticketStatus: "in_progress",
      prListComplete: false,
      eligible: [pr()],
      pr: pr(),
      ci: ciSummary(latestCiRunsByEvent(runs(GREEN), HEAD)),
    });
    assert.deepEqual(
      [s.ready, s.relaunch_ready, s.pr_number, s.eligible_pr_count],
      [false, false, null, 1],
    );
  });

  it("état écrit : adresse reconstruite depuis le numéro, aucun titre ni corps", () => {
    const s = deliveryState({
      ticketStatus: "in_progress",
      prListComplete: true,
      eligible: [pr()],
      pr: pr(),
      ci: ciSummary(latestCiRunsByEvent(runs(GREEN), HEAD)),
    });
    assert.equal(s.pr_url, `https://github.com/${REPO}/pull/34`);
    assert.equal(s.ready, true);
    assert.deepEqual(Object.keys(s).sort(), [
      "ci_completed_at",
      "ci_conclusion",
      "ci_status",
      "eligible_pr_count",
      "files_complete",
      "head_sha",
      "network_rules_controls",
      "network_rules_controls_complete",
      "network_rules_files",
      "pr_number",
      "pr_url",
      "ready",
      "relaunch_ready",
      "sensitive_files",
    ]);
    const notInProgress = deliveryState({
      ticketStatus: "validated",
      prListComplete: true,
      eligible: [pr()],
      pr: pr(),
      ci: ciSummary(latestCiRunsByEvent(runs(GREEN), HEAD)),
    });
    assert.equal(notInProgress.ready, false);
  });
});

// ── Comptes rendus (P45) ────────────────────────────────────────────────────

describe("livraison : comptes rendus (P45)", () => {
  const c = (id: number, authorId: number, body: string, at: string) => ({
    id,
    authorId,
    body,
    createdAt: at,
    updatedAt: at,
  });

  it("compte 16348852 seul, titres exacts, NFC, espaces de tête retirées", () => {
    const reports = deliveryReportsFromComments(
      [
        c(1, OWNER, "  ## Livraison — blocage\n\nCI rouge.", "2026-11-14T10:00:00Z"),
        c(2, 999, "## Livraison — terminée\n\nfaux", "2026-11-14T11:00:00Z"),
        c(3, OWNER, "## Livraison — terminée\r\n\r\nv0.1.40", "2026-11-14T12:00:00Z"),
        c(4, OWNER, "## Analyse\n\nautre chose", "2026-11-14T12:30:00Z"),
      ],
      OWNER,
    );
    assert.deepEqual(
      reports.map((r) => [r.comment_id, r.kind]),
      [
        [1, "blocked"],
        [3, "done"],
      ],
    );
    assert.equal(reports[1].body, "## Livraison — terminée\n\nv0.1.40");
  });

  it("dix au plus, les plus récents ; 20 000 caractères, truncated noté", () => {
    const many = Array.from({ length: 12 }, (_, i) =>
      c(
        i + 1,
        OWNER,
        `## Livraison — blocage\n\n${"x".repeat(i === 11 ? 25_000 : 5)}`,
        `2026-11-14T${String(i + 10).padStart(2, "0")}:00:00Z`,
      ),
    );
    const reports = deliveryReportsFromComments(many, OWNER);
    assert.equal(reports.length, 10);
    assert.equal(reports[0].comment_id, 3);
    assert.equal(reports[9].truncated, true);
    assert.ok(reports[9].body.length <= 20_000);
  });
});

// ── Livraison de bout en bout (P43, P44, P36) ───────────────────────────────

describe("livraison : chemin nominal (P43, P44)", () => {
  it("livrée : livraison #12 <tête>, comptée, verrou pris 3 h, état écrit, bail de 210 s", async () => {
    const h = harness();
    seedTicket(h);
    const out = await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    assert.deepEqual(out, { outcome: "launched", sessionUrl: SESSION });
    assert.equal(h.routineCalls.length, 1);
    assert.equal(h.routineCalls[0].body, `{"text":"livraison #12 ${HEAD}"}`);
    assert.equal(quota(h), 1);
    const l = lock(h)!;
    assert.equal(l.ticket_id, "t-1");
    assert.equal(l.issue_number, 12);
    assert.equal((l.launched_at as Timestamp).toMillis(), NOW);
    assert.equal((l.retry_after as Timestamp).toMillis(), NOW + 3 * HOUR);
    const [entry] = history(h);
    assert.equal(entry.action, "livraison");
    assert.equal((entry.at as Timestamp).toMillis(), NOW);
    assert.equal((entry.retry_after as Timestamp).toMillis(), NOW + 3 * HOUR);
    const state = h.db.read("tickets/t-1/admin/delivery") ?? {};
    assert.equal(state.ready, true);
    assert.equal(state.pr_number, 34);
    assert.equal(state.body, undefined);
    assert.equal(launchLeaseMs("livraison"), DELIVERY_LEASE_MS);
    assert.ok(DELIVERY_LEASE_MS >= 210_000);
    assert.equal(launchLeaseMs("reprise"), LAUNCH_LEASE_MS);
    // « Livrer » n'écrit rien sur GitHub : lectures seules (l'accord est propre au mode network_rules).
    assert.ok(h.githubCalls.every((c) => !c.includes("/comments") && !c.includes("/labels")));
  });

  it("ticket in_progress validé sur GitHub seul : refusé sans décompte", async () => {
    const h = harness();
    seedTicket(h, "t-1", { validated_by_app_at: null });
    const err = await refusedWithoutCount(h, "livraison", "not_launchable");
    assert.equal(details(err).reason, LAUNCH_IN_PROGRESS_NOT_BY_APP_MESSAGE);
    assert.equal(h.githubCalls.length, 0);
  });
});

describe("livraison : refus avant tout décompte (P43)", () => {
  const cases: Array<[string, Scene, string]> = [
    ["aucune PR", { prs: [] }, "delivery_no_pr"],
    ["deux PR", { prs: [rawPr(34), rawPr(35)] }, "delivery_multiple_prs"],
    [
      "PR d'une copie du dépôt : ignorée",
      {
        prs: [
          rawPr(34, {
            head: { ref: "claude/x", sha: HEAD, repo: { full_name: "Tiers/KassBeer" } },
          }),
        ],
      },
      "delivery_no_pr",
    ],
    [
      "PR d'un autre auteur : ignorée",
      { prs: [rawPr(34, { user: { id: 42 } })] },
      "delivery_no_pr",
    ],
    [
      "renommage depuis .github/x",
      { files: [{ filename: "docs/x.yml", previous_filename: ".github/x" }] },
      "delivery_sensitive_files",
    ],
    [
      "CLAUDE.md d'un sous-dossier",
      { files: [{ filename: "app/lib/CLAUDE.md" }] },
      "delivery_sensitive_files",
    ],
    [".GitHub/", { files: [{ filename: ".GitHub/workflows/x.yml" }] }, "delivery_sensitive_files"],
    ...[
      "app/pubspec.lock",
      "app/android/gradlew",
      "app/android/gradlew.bat",
      "app/hook/build.dart",
      "app/.claude/settings.json",
      "functions/src/auth.ts",
      "functions/src/config.ts",
      "functions/src/tickets/delivery.ts",
      "test-fixtures/member_access.json",
    ].map((filename): [string, Scene, string] => [
      filename,
      { files: [{ filename: "app/lib/main.dart" }, { filename }] },
      "delivery_sensitive_files",
    ]),
    [
      "1 001 fichiers",
      { files: Array.from({ length: 1001 }, (_, i) => ({ filename: `app/lib/f${i}.dart` })) },
      "delivery_files_unreadable",
    ],
    ["run push vert, run pull_request rouge", { runs: RED }, "delivery_ci_not_green"],
    ["CI en cours", { runs: [rawRun("push", "in_progress", null)] }, "delivery_ci_not_green"],
    ["un seul run push vert", { runs: [GREEN[0]] }, "delivery_ci_not_green"],
    [
      "run pull_request vert d'une copie du dépôt, run push seul de ce dépôt",
      {
        runs: [
          GREEN[0],
          rawRun("pull_request", "completed", "success", {
            head_repository: { full_name: "Tiers/KassBeer" },
          }),
        ],
      },
      "delivery_ci_not_green",
    ],
  ];
  for (const [name, scene, code] of cases) {
    it(`${name} : ${code}, rien compté, rien envoyé`, async () => {
      const h = harness(scene);
      seedTicket(h);
      await refusedWithoutCount(h, "livraison", code);
    });
  }

  it("refus sensible : le message dit de fusionner à la main", async () => {
    const h = harness({ files: [{ filename: "app/pubspec.lock" }] });
    seedTicket(h);
    const err = await refusedWithoutCount(h, "livraison", "delivery_sensitive_files");
    assert.match(String(details(err).reason), /Fusionnez-la vous-même après relecture/);
    assert.match(String(details(err).reason), /Rien n'a été lancé ni décompté/);
  });

  it("403 sur /actions/runs : github_actions_forbidden, sans token_invalid_since, noté puis effacé", async () => {
    const h = harness({ runsStatus: 403 });
    seedTicket(h);
    let marked = 0;
    const err = await refusal(
      launchTicketSession(
        "t-1",
        "livraison",
        "admin-uid",
        h.deps({
          markTokenInvalid: async () => {
            marked++;
          },
        }),
      ),
    );
    assert.equal(details(err).code, "github_actions_forbidden");
    assert.equal(err.code, "failed-precondition");
    assert.equal(
      details(err).reason,
      "Le jeton GitHub ne peut pas lire la CI : sur GitHub, donnez-lui le droit « Actions : lecture ». Rien n'a été lancé ni décompté.",
    );
    assert.equal(marked, 0);
    assert.equal(h.routineCalls.length, 0);
    assert.equal(quota(h), 0);
    assert.equal(history(h).length, 0);
    const status = h.db.read("ticket_status/launches") ?? {};
    assert.ok(status.ci_read_denied_since instanceof Timestamp);
    assert.equal(status.token_invalid_since, undefined);
    assert.ok(status.delivery_running === undefined || status.delivery_running === null);

    // Lecture suivante réussie : la note est effacée.
    const ok = harness();
    ok.db.seed("tickets/t-1", h.db.read("tickets/t-1") ?? {});
    ok.db.seed("ticket_status/launches", status);
    await launchTicketSession("t-1", "livraison", "admin-uid", ok.deps());
    assert.equal(ok.db.read("ticket_status/launches")?.ci_read_denied_since, null);
  });

  it("Issue relue en échec après la prise du verrou : verrou et compteur rendus", async () => {
    const h = harness({ issueStatus: 500 });
    seedTicket(h);
    const err = await refusal(launchTicketSession("t-1", "livraison", "admin-uid", h.deps()));
    assert.equal(details(err).code, "github_unavailable");
    assert.ok(
      h.githubCalls.some((c) => /^\/issues\/12$/.test(c)),
      "Issue relue",
    );
    assert.equal(lock(h), null);
    assert.equal(quota(h), 0);
    assert.equal(h.routineCalls.length, 0);
    assert.equal(history(h).length, 0);
  });

  it("jetons absents des journaux : refus de GitHub et 401 de l'API (P35)", async () => {
    const scenes: Array<[Scene, (n: number) => Promise<Response>]> = [
      [{ runsStatus: 403 }, async () => new Response("{}", { status: 200 })],
      [{ issueStatus: 500 }, async () => new Response("{}", { status: 200 })],
      [
        {},
        async () =>
          new Response(JSON.stringify({ error: `bad token ${ROUTINE_TOKEN}` }), { status: 401 }),
      ],
    ];
    for (const [scene, routine] of scenes) {
      const h = harness(scene, routine);
      seedTicket(h);
      await refusal(launchTicketSession("t-1", "livraison", "admin-uid", h.deps()));
      assert.ok(h.logs.length > 0);
      const text = JSON.stringify(
        h.logs.map(({ entry }) => ({
          ...entry,
          error:
            entry.error instanceof Error
              ? `${entry.error.message} ${entry.error.stack ?? ""}`
              : entry.error,
        })),
      );
      assert.ok(!text.includes(GH_TOKEN), "jeton GitHub journalisé");
      assert.ok(!text.includes(ROUTINE_TOKEN), "jeton de la routine journalisé");
    }
  });

  it("reprise de ce ticket en cours : reprise_running", async () => {
    const h = harness();
    seedTicket(h);
    h.db.seed("tickets/t-1/admin/launches", {
      entries: [
        {
          id: "r-1",
          action: "reprise",
          state: "launched",
          at: Timestamp.fromMillis(NOW - HOUR),
          retry_after: Timestamp.fromMillis(NOW + 2 * HOUR),
        },
      ],
    });
    const err = await refusal(launchTicketSession("t-1", "livraison", "admin-uid", h.deps()));
    assert.equal(details(err).code, "reprise_running");
    assert.equal(h.routineCalls.length, 0);
    assert.equal(quota(h), 0);
    assert.equal(h.githubCalls.length, 0);
  });

  it("premier développement en cours : ne bloque pas la livraison (décision 12)", async () => {
    const h = harness();
    seedTicket(h);
    h.db.seed("tickets/t-1/admin/launches", {
      entries: [
        {
          id: "d-1",
          action: "developpement",
          state: "launched",
          at: Timestamp.fromMillis(NOW - HOUR),
          retry_after: Timestamp.fromMillis(NOW + 2 * HOUR),
        },
      ],
    });
    const out = await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    assert.equal(out.outcome, "launched");
  });
});

describe("livraison : verrou (P44)", () => {
  it("deux livraisons simultanées sur deux tickets : une seule passe", async () => {
    const h = harness({
      prs: [
        rawPr(34),
        rawPr(35, {
          body: "Closes #13",
          head: { ref: "claude/t13", sha: HEAD, repo: { full_name: REPO } },
        }),
      ],
    });
    seedTicket(h, "t-1");
    seedTicket(h, "t-2", { github_issue_number: 13 });
    const results = await Promise.allSettled([
      launchTicketSession("t-1", "livraison", "admin-uid", h.deps()),
      launchTicketSession("t-2", "livraison", "admin-uid", h.deps()),
    ]);
    const ok = results.filter((r) => r.status === "fulfilled");
    const ko = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
    assert.equal(ok.length, 1);
    assert.equal(ko.length, 1);
    assert.equal(details(ko[0].reason as HttpsError).code, "delivery_running_elsewhere");
    assert.equal(h.routineCalls.length, 1);
    assert.equal(quota(h), 1);
  });

  it("verrou d'un ticket sorti de « En cours » : écrasé", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    seedTicket(h, "t-9", { status: "delivered", github_issue_number: 9 });
    h.db.seed("ticket_status/launches", {
      delivery_running: {
        ticket_id: "t-9",
        issue_number: 9,
        launched_at: Timestamp.fromMillis(NOW - HOUR),
        retry_after: Timestamp.fromMillis(NOW + 2 * HOUR),
      },
    });
    await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    assert.equal(lock(h)?.ticket_id, "t-1");
  });

  it("400 de l'API : verrou rendu, compteur rendu", async () => {
    const h = harness({}, async () => new Response('{"error":"bad"}', { status: 400 }));
    seedTicket(h);
    const err = await refusal(launchTicketSession("t-1", "livraison", "admin-uid", h.deps()));
    assert.equal(details(err).code, "routine_failed");
    assert.equal(lock(h), null);
    assert.equal(quota(h), 0);
  });

  it("délai dépassé : unknown, verrou gardé, compté", async () => {
    const h = harness({}, async () => {
      throw new DOMException("timeout", "TimeoutError");
    });
    seedTicket(h);
    const out = await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    assert.equal(out.outcome, "unknown");
    assert.equal(lock(h)?.ticket_id, "t-1");
    assert.equal(quota(h), 1);
  });

  it("401 d'une livraison : development_invalid_since posé", async () => {
    const h = harness({}, async () => new Response("{}", { status: 401 }));
    seedTicket(h);
    await refusal(launchTicketSession("t-1", "livraison", "admin-uid", h.deps()));
    assert.ok(h.db.read("ticket_status/launches")?.development_invalid_since instanceof Timestamp);
    assert.equal(h.db.read("ticket_status/launches")?.analysis_invalid_since, undefined);
  });

  it("blocage relevé après le lancement : verrou libéré, échéance ramenée à l'heure du relevé", async () => {
    const h = harness();
    seedTicket(h);
    await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    const relevé = NOW + HOUR;
    h.clock.now = relevé;
    const count = await writeDeliveryReports(
      h.db.kit(),
      "t-1",
      [
        {
          id: 77,
          authorId: OWNER,
          body: "## Livraison — blocage\n\nL7 : CI rouge.",
          createdAt: new Date(NOW + 30 * 60_000).toISOString(),
          updatedAt: null,
        },
      ],
      relevé,
    );
    assert.equal(count, 1);
    assert.equal(lock(h), null);
    assert.equal((history(h)[0].retry_after as Timestamp).toMillis(), relevé);
    assert.equal(history(h)[0].ended_by, "blocked");
    assert.equal(runningLaunch([], "livraison", relevé), null);
    const reports = h.db.read("tickets/t-1/admin/delivery")?.reports as Record<string, unknown>[];
    assert.equal(reports[0].kind, "blocked");
  });

  it("blocage relevé après l'échéance : livraison marquée ended_by, échéance inchangée", async () => {
    const h = harness();
    seedTicket(h);
    await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    const relevé = NOW + 4 * HOUR;
    await writeDeliveryReports(
      h.db.kit(),
      "t-1",
      [
        {
          id: 78,
          authorId: OWNER,
          body: "## Livraison — blocage\n\nL8.",
          createdAt: new Date(NOW + 3.5 * HOUR).toISOString(),
          updatedAt: null,
        },
      ],
      relevé,
    );
    assert.equal(history(h)[0].ended_by, "blocked");
    assert.equal((history(h)[0].retry_after as Timestamp).toMillis(), NOW + 3 * HOUR);
  });

  it("aucun blocage : livraison sans ended_by", async () => {
    const h = harness();
    seedTicket(h);
    await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    await writeDeliveryReports(h.db.kit(), "t-1", [], NOW + 4 * HOUR);
    assert.equal(history(h)[0].ended_by, undefined);
  });

  it("verrou sans numéro ni heure : message sans valeur inventée", () => {
    const m = deliveryRunningElsewhereMessage(null, null);
    assert.equal(
      m,
      "Une livraison est en cours sur un autre ticket. Une seule livraison à la fois. " +
        "Rien n'a été lancé ni décompté.",
    );
    assert.doesNotMatch(m, /#0/);
    assert.match(deliveryRunningElsewhereMessage(9, NOW), /le ticket #9 depuis le 14\/11/);
  });

  it("blocage antérieur au lancement : verrou gardé", async () => {
    const h = harness();
    seedTicket(h);
    await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    await writeDeliveryReports(
      h.db.kit(),
      "t-1",
      [
        {
          id: 70,
          authorId: OWNER,
          body: "## Livraison — blocage",
          createdAt: new Date(NOW - HOUR).toISOString(),
          updatedAt: null,
        },
      ],
      NOW + HOUR,
    );
    assert.equal(lock(h)?.ticket_id, "t-1");
  });

  it("aucun compte rendu et aucun document : rien écrit", async () => {
    const h = harness();
    await writeDeliveryReports(h.db.kit(), "t-1", [], NOW);
    assert.equal(h.db.read("tickets/t-1/admin/delivery"), undefined);
  });

  it("ticket sorti de « En cours » : verrou libéré et livraison close", async () => {
    const h = harness();
    seedTicket(h);
    await launchTicketSession("t-1", "livraison", "admin-uid", h.deps());
    h.db.seed("tickets/t-1", { status: "delivered", github_issue_number: 12 });
    await releaseDeliveryLockIfLeft(h.db.kit(), null, NOW + HOUR);
    assert.equal(lock(h), null);
    assert.equal((history(h)[0].retry_after as Timestamp).toMillis(), NOW + HOUR);
  });
});

// ── Refuser et Clore pendant la livraison (P44) ─────────────────────────────

describe("décisions pendant une livraison (P44)", () => {
  for (const action of ["refuse", "close"] as const) {
    it(`decideTicket : ${action} refusé sans appel GitHub ni décision écrite tant que le verrou tient`, async () => {
      const db = new FakeDb();
      mock.method(firestoreModule, "firestore", async () => db.kit());
      db.seed("tickets/t-1", {
        status: "in_progress",
        github_issue_number: 12,
        validated_by_app_at: BY_APP,
        allowed_decisions: allowedDecisions("in_progress", true),
      });
      db.seed("ticket_status/launches", {
        delivery_running: {
          ticket_id: "t-1",
          issue_number: 12,
          launched_at: Timestamp.fromMillis(Date.now() - HOUR),
          retry_after: Timestamp.fromMillis(Date.now() + HOUR),
        },
      });
      const calls: string[] = [];
      await assert.rejects(
        decideTicket("t-1", action, "Plus utile.", "admin-uid", GH_TOKEN, githubFetch({}, calls)),
        (err: HttpsError) =>
          err.code === "failed-precondition" &&
          (err.details as { code: string; reason: string }).code === "delivery_running" &&
          (err.details as { reason: string }).reason === REJECT_DELIVERY_RUNNING,
      );
      assert.equal(calls.length, 0);
      assert.deepEqual(
        [...db.docs.keys()].filter((k) => k.includes("/decisions/")),
        [],
      );
      assert.equal(db.read("tickets/t-1")?.decision_lease_until, undefined);
    });
  }
});

// ── Décisions permises (P42) ────────────────────────────────────────────────

describe("décisions permises d'un ticket En cours (P42, T5)", () => {
  it("validé dans l'application : livrer et relancer ; sinon refuser et clore seuls", () => {
    assert.deepEqual(allowedDecisions("in_progress", true), [
      "refuse",
      "close",
      "launch_delivery",
      "relaunch_development",
    ]);
    assert.deepEqual(allowedDecisions("in_progress", false), ["refuse", "close"]);
  });

  it("passe horaire : liste in_progress sans livraison réécrite (version 5)", async () => {
    const db = new FakeDb();
    mock.method(firestoreModule, "firestore", async () => db.kit());
    db.seed("ticket_status/github", { allowed_decisions_backfill_version: 4 });
    db.seed("tickets/t-1", {
      status: "in_progress",
      validated_by_app_at: BY_APP,
      allowed_decisions: ["refuse", "close"],
    });
    db.seed("tickets/t-2", { status: "in_progress", allowed_decisions: ["refuse", "close"] });
    await backfillAllowedDecisions();
    assert.equal(ALLOWED_DECISIONS_VERSION, 5);
    assert.deepEqual(
      db.read("tickets/t-1")?.allowed_decisions,
      allowedDecisions("in_progress", true),
    );
    assert.deepEqual(db.read("tickets/t-2")?.allowed_decisions, ["refuse", "close"]);
  });
});

// ── Reprise du développement (P47) ──────────────────────────────────────────

describe("reprise : préconditions (P47)", () => {
  function seedRelaunchable(h: Harness, extra: Record<string, unknown> = {}): void {
    seedTicket(h, "t-1", extra);
    h.db.seed("tickets/t-1/admin/delivery", {
      eligible_pr_count: 1,
      pr_number: 34,
      ready: false,
      relaunch_ready: true,
    });
  }

  it("acceptée : reprise #12, comptée, échéance 3 h", async () => {
    const h = harness({ runs: RED });
    seedRelaunchable(h);
    const out = await launchTicketSession("t-1", "reprise", "admin-uid", h.deps());
    assert.equal(out.outcome, "launched");
    assert.equal(h.routineCalls[0].body, '{"text":"reprise #12"}');
    assert.equal(quota(h), 1);
    assert.equal((history(h)[0].retry_after as Timestamp).toMillis(), NOW + 3 * HOUR);
    assert.equal(lock(h), undefined);
  });

  it("CI pas rouge (relaunch_ready faux) : reprise_ci_not_red", async () => {
    const h = harness();
    seedRelaunchable(h);
    h.db.seed("tickets/t-1/admin/delivery", { relaunch_ready: false, ready: true });
    await refusedWithoutCount(h, "reprise", "reprise_ci_not_red");
  });

  it("ticket validated, ou in_progress validé sur GitHub : not_launchable", async () => {
    const h = harness();
    seedRelaunchable(h, { status: "validated" });
    await refusedWithoutCount(h, "reprise", "not_launchable");
    const g = harness();
    seedRelaunchable(g, { validated_by_app_at: null });
    await refusedWithoutCount(g, "reprise", "not_launchable");
  });

  for (const action of ["developpement", "reprise", "livraison"]) {
    it(`${action} lancé il y a moins de 3 h : refusée`, async () => {
      const h = harness();
      seedRelaunchable(h);
      h.db.seed("tickets/t-1/admin/launches", {
        entries: [
          {
            id: "x",
            action,
            state: "unknown",
            at: Timestamp.fromMillis(NOW - HOUR),
            retry_after: Timestamp.fromMillis(NOW + 2 * HOUR),
          },
        ],
      });
      const err = await refusal(launchTicketSession("t-1", "reprise", "admin-uid", h.deps()));
      assert.equal(err.code, "failed-precondition");
      assert.equal(
        details(err).code,
        action === "livraison" ? "reprise_blocked_by_delivery" : "running",
      );
      assert.equal(h.routineCalls.length, 0);
      assert.equal(quota(h), 0);
    });
  }

  it("livraison de ce ticket en cours (verrou) : reprise_blocked_by_delivery", async () => {
    const h = harness();
    seedRelaunchable(h);
    h.db.seed("ticket_status/launches", {
      delivery_running: {
        ticket_id: "t-1",
        issue_number: 12,
        launched_at: Timestamp.fromMillis(NOW - HOUR),
        retry_after: Timestamp.fromMillis(NOW + 2 * HOUR),
      },
    });
    const err = await refusal(launchTicketSession("t-1", "reprise", "admin-uid", h.deps()));
    assert.equal(details(err).code, "reprise_blocked_by_delivery");
    assert.equal(quota(h), 0);
  });

  it("401 d'une reprise : development_invalid_since posé", async () => {
    const h = harness({}, async () => new Response("{}", { status: 401 }));
    seedRelaunchable(h);
    await refusal(launchTicketSession("t-1", "reprise", "admin-uid", h.deps()));
    assert.ok(h.db.read("ticket_status/launches")?.development_invalid_since instanceof Timestamp);
  });
});

describe("reprise : argument mode de launchTicketDevelopment (P47)", () => {
  const admin = {
    uid: "admin-uid",
    token: {
      email: "admin@example.com",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" },
    },
  };
  const lookup = async () => ({ role: "admin" });

  it("mode absent ou start : developpement ; resume : reprise ; autre : refusé", () => {
    assert.equal(readLaunchMode({ ticketId: "t-1" }), "start");
    assert.equal(readLaunchMode({ mode: "start" }), "start");
    assert.equal(readLaunchMode({ mode: "resume" }), "resume");
    for (const bad of ["Resume", "", "x".repeat(17), 3]) {
      assert.throws(
        () => readLaunchMode({ mode: bad }),
        (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
      );
    }
  });

  it("appel sans mode : developpement #N, comme avant T5", async () => {
    const h = harness({ labels: ["source:app", "statut:analysé", "validé"] });
    seedTicket(h, "t-1", { status: "validated" });
    await handleDevelopmentCall(
      { auth: admin, data: { ticketId: "t-1" } },
      { ...h.deps(), lookup },
    );
    assert.equal(h.routineCalls[0].body, '{"text":"developpement #12"}');
  });

  it("mode inconnu : refusé avant toute lecture ; brasseur refusé avant le mode", async () => {
    const h = harness();
    seedTicket(h);
    const bad = await refusal(
      handleDevelopmentCall(
        { auth: admin, data: { ticketId: "t-1", mode: "x" } },
        { ...h.deps(), lookup },
      ),
    );
    assert.equal(bad.code, "invalid-argument");
    assert.equal(details(bad).field, "mode");
    assert.equal(h.db.writes.length, 0);
    const brewer = await refusal(
      handleDevelopmentCall(
        {
          auth: { ...admin, token: { ...admin.token, email: "b@example.com" } },
          data: { mode: "x" },
        },
        { ...h.deps(), lookup: async () => ({ role: "brewer" }) },
      ),
    );
    assert.equal(brewer.code, "permission-denied");
  });

  it("launchTicketDelivery : livraison #N <tête> par handleLaunchCall", async () => {
    const h = harness();
    seedTicket(h);
    await handleLaunchCall({ auth: admin, data: { ticketId: "t-1" } }, "livraison", {
      ...h.deps(),
      lookup,
    });
    assert.equal(h.routineCalls[0].body, `{"text":"${launchCommandText("livraison", 12, HEAD)}"}`);
  });
});

// ── Webhook et passe horaire (P29, P46) ─────────────────────────────────────

describe("livraison : événements du webhook (P29)", () => {
  const prEvent = (extra: Record<string, unknown> = {}, action = "opened") => ({
    action,
    repository: { full_name: REPO },
    pull_request: rawPr(34, extra),
  });
  const apiRepo = (name: string) => ({ id: 1, url: `https://api.github.com/repos/${name}`, name });
  const runPr = (number: number, base = REPO, head = REPO) => ({
    number,
    base: { ref: "main", sha: "b".repeat(40), repo: apiRepo(base) },
    head: { ref: "claude/x", sha: HEAD, repo: apiRepo(head) },
  });
  const runEvent = (run: Record<string, unknown>, action = "completed") => ({
    action,
    repository: { full_name: REPO },
    workflow_run: {
      ...rawRun("pull_request", "completed", "success"),
      pull_requests: [runPr(34)],
      ...run,
    },
  });

  it("PR du compte 16348852 : Issues citées par le corps et l'ancien corps", () => {
    assert.deepEqual(deliveryRefreshFromEvent("pull_request", prEvent(), REPO), {
      issueNumbers: [12],
      prNumbers: [],
    });
    const edited = {
      ...prEvent({ body: "Closes #13" }, "edited"),
      changes: { body: { from: "Closes #12" } },
    };
    assert.deepEqual(
      deliveryRefreshFromEvent("pull_request", edited, REPO)?.issueNumbers,
      [12, 13],
    );
  });

  it("PR d'une copie du dépôt ou d'un autre auteur : ignorée", () => {
    assert.equal(
      deliveryRefreshFromEvent(
        "pull_request",
        prEvent({ head: { ref: "claude/x", sha: HEAD, repo: { full_name: "Tiers/KassBeer" } } }),
        REPO,
      ),
      null,
    );
    assert.equal(
      deliveryRefreshFromEvent("pull_request", prEvent({ user: { id: 1 } }), REPO),
      null,
    );
  });

  it("corps qui cite six Issues : borné à cinq", () => {
    const body = "Closes #1, closes #2, closes #3, closes #4, closes #5, closes #6";
    assert.deepEqual(
      deliveryRefreshFromEvent("pull_request", prEvent({ body }), REPO)?.issueNumbers,
      [1, 2, 3, 4, 5],
    );
  });

  it("workflow_run de ci.yml : PR portées, cinq au plus", () => {
    const prs = Array.from({ length: 7 }, (_, i) => runPr(i + 1));
    assert.deepEqual(
      deliveryRefreshFromEvent("workflow_run", runEvent({ pull_requests: prs }), REPO)?.prNumbers,
      [1, 2, 3, 4, 5],
    );
  });

  it("workflow_run : PR dont la base ou la tête est hors de ce dépôt ignorée, sans appel", () => {
    const run = runEvent({
      pull_requests: [
        runPr(40, "Tiers/KassBeer", REPO),
        runPr(41, REPO, "Tiers/KassBeer"),
        { number: 42 },
        runPr(34, "chinafred/kassbeer", REPO),
      ],
    });
    assert.deepEqual(deliveryRefreshFromEvent("workflow_run", run, REPO)?.prNumbers, [34]);
    assert.equal(
      deliveryRefreshFromEvent(
        "workflow_run",
        runEvent({ pull_requests: [runPr(40, "Tiers/KassBeer", "Tiers/KassBeer")] }),
        REPO,
      ),
      null,
    );
  });

  it("workflow_run de « Déploiement », d'un autre chemin, sans PR, autre dépôt : ignoré", () => {
    for (const run of [
      { name: "Déploiement", path: ".github/workflows/deploy.yml" },
      { path: ".github/workflows/autre.yml" },
      { pull_requests: [] },
    ]) {
      assert.equal(deliveryRefreshFromEvent("workflow_run", runEvent(run), REPO), null);
    }
    assert.equal(
      deliveryRefreshFromEvent(
        "workflow_run",
        { ...runEvent({}), repository: { full_name: "Tiers/KassBeer" } },
        REPO,
      ),
      null,
    );
    assert.equal(deliveryRefreshFromEvent("workflow_run", runEvent({}, "queued"), REPO), null);
  });

  it("workflow_run : la PR et ses runs relus, jamais la liste des PR ouvertes", async () => {
    const db = new FakeDb(() => NOW);
    seedTicketDb(db);
    db.seed("tickets/t-1/admin/delivery", { eligible_pr_count: 1, pr_number: 34, ready: false });
    const calls: string[] = [];
    const client = githubClient(GH_TOKEN, githubFetch({ runs: RED }, calls));
    const written = await refreshDeliveryFromRun(db.kit(), client, 34);
    assert.equal(written, 1);
    assert.ok(
      calls.every((c) => !c.startsWith("/pulls?")),
      calls.join(","),
    );
    const state = db.read("tickets/t-1/admin/delivery") ?? {};
    assert.equal(state.relaunch_ready, true);
    assert.equal(state.ready, false);
  });
  it("workflow_run : fichiers relus, accord d'une autre tête annulé (ADR-020, P45)", async () => {
    const db = new FakeDb(() => NOW);
    seedTicketDb(db);
    db.seed("tickets/t-1/admin/delivery", {
      eligible_pr_count: 1,
      pr_number: 34,
      network_rules_ack: {
        head_sha: "c".repeat(40),
        at: Timestamp.fromMillis(NOW - HOUR),
        ack_id: "AckAckAckAckAckAck01",
        comment_id: 77,
        files: ["CLAUDE.md"],
        controls: [],
      },
      network_rules_ack_valid: true,
    });
    const calls: string[] = [];
    const client = githubClient(
      GH_TOKEN,
      githubFetch({ files: [{ filename: "CLAUDE.md", patch: "+| P7 | x |" }] }, calls),
    );
    assert.equal(await refreshDeliveryFromRun(db.kit(), client, 34), 1);
    assert.ok(calls.some((c) => c.startsWith("/pulls/34/files")));
    const state = db.read("tickets/t-1/admin/delivery") ?? {};
    assert.deepEqual(state.network_rules_files, ["CLAUDE.md"]);
    assert.deepEqual(state.network_rules_controls, [7]);
    assert.equal(state.network_rules_ack_valid, false);
    assert.equal((state.network_rules_ack as Record<string, unknown>).comment_id, 77);
  });
});

function seedTicketDb(db: FakeDb): void {
  db.seed("tickets/t-1", {
    status: "in_progress",
    github_issue_number: 12,
    validated_by_app_at: BY_APP,
  });
}

// ── Règles du réseau et accord (ADR-020, lot R2 : P43, P44, P45, P65) ───────

const HEAD_B = "b".repeat(40);
const ACK_ID = "AckAckAckAckAckAck01";
const PATCH = [
  "@@ -1,3 +1,4 @@",
  " | N° | Contrôle | Agent | Origine |",
  "-| P10 | ancien | relecteur-regles | ADR-001 |",
  "+| P10 | nouveau | relecteur-regles | ADR-001 |",
  "+| P65 | catégories | relecteur-regles | ADR-020 |",
  " | P3 | inchangé | relecteur-regles | ADR-001 |",
  "+| P1000 | hors motif |",
  "+texte | P12 | hors tableau",
].join("\n");
const RULES_FILES = [
  { filename: "app/lib/main.dart" },
  { filename: "CLAUDE.md", patch: PATCH },
  { filename: "scripts/changelog-recent.mjs" },
];

describe("règles du réseau : trois catégories (P65)", () => {
  it("catégorie 2 : quatre chemins exacts, casse comprise", () => {
    assert.deepEqual(NETWORK_RULES_PATTERNS, [
      "CLAUDE.md",
      "scripts/changelog-recent.mjs",
      "scripts/changelog-recent.test.mjs",
      "documentation/prompts-routines.md",
    ]);
    for (const p of NETWORK_RULES_PATTERNS) {
      assert.equal(isNetworkRulesPath(p), true, p);
      assert.equal(isSensitiveDeliveryPath(p), false, p);
      assert.equal(isForbiddenDevelopmentPath(p), false, p);
    }
    for (const p of ["claude.md", "Scripts/changelog-recent.mjs", "docs/CLAUDE.md"]) {
      assert.equal(isNetworkRulesPath(p), false, p);
      assert.equal(isForbiddenDevelopmentPath(p), true, p);
    }
  });

  it("le reste de scripts/ et tout CLAUDE.md hors racine restent interdits (décision 2)", () => {
    for (const p of [
      "scripts/check-version.mjs",
      "scripts/check-agents.mjs",
      "scripts/garder-apk-en-ligne.sh",
      "scripts/changelog-recent.mjs.bak",
      "app/CLAUDE.md",
    ]) {
      assert.equal(isForbiddenDevelopmentPath(p), true, p);
      assert.equal(isSensitiveDeliveryPath(p), true, p);
    }
  });

  it("catégorie 3 : permise au développement, refusée à la livraison", () => {
    for (const p of DELIVERY_ONLY_SENSITIVE_PATTERNS) {
      assert.equal(isForbiddenDevelopmentPath(p), false, p);
      assert.equal(isSensitiveDeliveryPath(p), true, p);
    }
  });

  it("SENSITIVE_DELIVERY_PATTERNS : union des catégories 1 et 3, sans recoupement avec 2", () => {
    assert.deepEqual(SENSITIVE_DELIVERY_PATTERNS, [
      ...FORBIDDEN_DEVELOPMENT_PATTERNS,
      ...DELIVERY_ONLY_SENSITIVE_PATTERNS,
    ]);
    for (const p of NETWORK_RULES_PATTERNS) {
      assert.ok(!SENSITIVE_DELIVERY_PATTERNS.includes(p), p);
    }
  });

  it("fichiers de la PR : anciens chemins compris, ordre de la liste, sans doublon", () => {
    assert.deepEqual(
      networkRulesFiles([
        { filename: "scripts/changelog-recent.test.mjs", previousFilename: null },
        { filename: "doc.md", previousFilename: "CLAUDE.md" },
        { filename: "CLAUDE.md", previousFilename: null },
      ]),
      ["CLAUDE.md", "scripts/changelog-recent.test.mjs"],
    );
  });
});

describe("règles du réseau : contrôles lus dans le patch (P45)", () => {
  it("lignes +| Pn | et -| Pn | seules, sans doublon, triées", () => {
    assert.deepEqual(
      networkRulesControls([{ filename: "CLAUDE.md", previousFilename: null, patch: PATCH }]),
      { controls: [10, 65], complete: true },
    );
  });

  it("patch absent : liste illisible ; CLAUDE.md inchangé : liste vide et complète", () => {
    assert.deepEqual(
      networkRulesControls([{ filename: "CLAUDE.md", previousFilename: null, patch: null }]),
      { controls: [], complete: false },
    );
    assert.deepEqual(
      networkRulesControls([{ filename: "scripts/changelog-recent.mjs", previousFilename: null }]),
      { controls: [], complete: true },
    );
  });

  it("60 contrôles au plus ; au-delà, liste incomplète", () => {
    const patch = (n: number) =>
      Array.from({ length: n }, (_, i) => `+| P${i + 1} | x |`).join("\n");
    const over = networkRulesControls([
      { filename: "CLAUDE.md", previousFilename: null, patch: patch(80) },
    ]);
    assert.equal(over.controls.length, 60);
    assert.equal(over.complete, false);
    const exact = networkRulesControls([
      { filename: "CLAUDE.md", previousFilename: null, patch: patch(60) },
    ]);
    assert.equal(exact.controls.length, 60);
    assert.equal(exact.complete, true);
  });

  it("CLAUDE.md seulement en ancien chemin d'un renommage : liste incomplète", () => {
    assert.deepEqual(
      networkRulesControls([
        { filename: "documentation/ancien.md", previousFilename: "CLAUDE.md", patch: null },
      ]),
      { controls: [], complete: false },
    );
  });

  it("état relu : fichiers, contrôles, fichier sensible ; aucune ligne du patch gardée", async () => {
    const h = harness({ files: [...RULES_FILES, { filename: "functions/src/auth.ts" }] });
    seedTicket(h);
    await refusal(launchTicketSession("t-1", "livraison", "admin-uid", h.deps()));
    const state = h.db.read("tickets/t-1/admin/delivery") ?? {};
    assert.deepEqual(state.network_rules_files, ["CLAUDE.md", "scripts/changelog-recent.mjs"]);
    assert.deepEqual(state.network_rules_controls, [10, 65]);
    assert.equal(state.network_rules_controls_complete, true);
    assert.equal(state.sensitive_files, "functions/src/auth.ts");
    assert.equal(state.files_complete, true);
    assert.ok(!JSON.stringify(state).includes("nouveau"), "texte du patch écrit");
  });
});

describe("règles du réseau : accord lié à la tête (P24, P45)", () => {
  it("gabarit fixe : PR, tête, fichiers, contrôles ou « aucun », ligne Accord", () => {
    assert.equal(
      networkRulesAckBody({
        prNumber: 34,
        headSha: HEAD,
        files: ["CLAUDE.md", "scripts/changelog-recent.mjs"],
        controls: [10, 65],
        ackId: ACK_ID,
      }),
      [
        "## Accord — règles du réseau",
        "",
        "PR #34",
        `Tête ${HEAD}`,
        "Fichiers : CLAUDE.md, scripts/changelog-recent.mjs",
        "Contrôles : P10, P65",
        "",
        `Accord ${ACK_ID}`,
      ].join("\n"),
    );
    const none = networkRulesAckBody({
      prNumber: 34,
      headSha: HEAD,
      files: ["documentation/prompts-routines.md"],
      controls: [],
      ackId: ACK_ID,
    });
    assert.match(none, /^Contrôles : aucun$/m);
  });

  it("gabarit : fichier hors catégorie 2, tête ou identifiant hors motif refusés", () => {
    const ok = { prNumber: 34, headSha: HEAD, files: ["CLAUDE.md"], controls: [], ackId: ACK_ID };
    assert.throws(() => networkRulesAckBody({ ...ok, files: ["@x <img>"] }));
    assert.throws(() => networkRulesAckBody({ ...ok, files: [] }));
    assert.throws(() => networkRulesAckBody({ ...ok, headSha: "HEAD" }));
    assert.throws(() => networkRulesAckBody({ ...ok, ackId: "court" }));
  });

  it("accord reconnu par sa ligne, du compte 16348852 seul ; ni analyse ni compte rendu", () => {
    const body = `${NETWORK_RULES_ACK_TITLE}\n\nPR #34\n\nAccord ${ACK_ID}`;
    assert.equal(commentCarriesAck({ authorId: OWNER, body }, ACK_ID, OWNER), true);
    assert.equal(commentCarriesAck({ authorId: 42, body }, ACK_ID, OWNER), false);
    assert.equal(
      commentCarriesAck({ authorId: OWNER, body: "Accord autre" }, ACK_ID, OWNER),
      false,
    );
    const c = { id: 1, authorId: OWNER, body, createdAt: null, updatedAt: null };
    assert.deepEqual(deliveryReportsFromComments([c], OWNER), []);
  });

  it("accord valide sur sa tête, annulé par une nouvelle tête sans autre écriture", async () => {
    const h = harness();
    const ack = {
      head_sha: HEAD,
      at: Timestamp.fromMillis(NOW),
      ack_id: ACK_ID,
      comment_id: 77,
      files: ["CLAUDE.md"],
      controls: [65],
    };
    h.db.seed("tickets/t-1/admin/delivery", { network_rules_ack: ack });
    const kit = h.db.kit();
    const state = deliveryState({
      ticketStatus: "in_progress",
      prListComplete: true,
      eligible: [readPullRequest(rawPr(34))!],
      pr: readPullRequest(rawPr(34))!,
      ci: ciSummary([]),
    });
    await writeDeliveryState(kit, "t-1", state);
    assert.equal(h.db.read("tickets/t-1/admin/delivery")?.network_rules_ack_valid, true);
    await writeDeliveryState(kit, "t-1", { ...state, head_sha: HEAD_B });
    const after = h.db.read("tickets/t-1/admin/delivery") ?? {};
    assert.equal(after.network_rules_ack_valid, false);
    assert.deepEqual(after.network_rules_ack, ack);
  });

  it("accord sans comment_id : invalide", () => {
    const read = readNetworkRulesAck(
      { head_sha: HEAD, ack_id: ACK_ID, comment_id: null, files: [], controls: [] },
      () => null,
    );
    assert.notEqual(read, null);
    assert.equal(networkRulesAckValid(read, HEAD), false);
    assert.equal(networkRulesAckValid(null, HEAD), false);
  });
});

describe("règles du réseau : livraison (P43, P44)", () => {
  const RULES: { mode: "network_rules"; headSha: string } = {
    mode: "network_rules",
    headSha: HEAD,
  };
  const launchRules = (h: Harness, over: Partial<LaunchDeps> = {}, args = RULES) =>
    launchTicketSession(
      "t-1",
      "livraison",
      "admin-uid",
      { newAckId: () => ACK_ID, ...h.deps(over) },
      "group",
      args,
    );
  const posts = (h: Harness) => h.githubCalls.filter((c) => c.startsWith("POST "));

  async function rulesRefused(h: Harness, code: string, args = RULES): Promise<HttpsError> {
    const err = await refusal(launchRules(h, {}, args));
    assert.equal(details(err).code, code, String(details(err).reason));
    assert.equal(err.code, "failed-precondition");
    assert.match(String(details(err).reason), /Rien n'a été lancé ni décompté/);
    assert.equal(h.routineCalls.length, 0);
    assert.equal(quota(h), 0);
    assert.ok(lock(h) === undefined || lock(h) === null, "verrou rendu");
    assert.equal(history(h).length, 0);
    return err;
  }

  it("Livrer sur une PR de règles : delivery_network_rules, rien compté", async () => {
    const h = harness({ files: RULES_FILES });
    seedTicket(h);
    const err = await refusedWithoutCount(h, "livraison", "delivery_network_rules");
    assert.match(String(details(err).reason), /Approuver les règles et livrer/);
  });

  it("accord publié sur le gabarit, puis livraison #12 comptée une fois", async () => {
    const h = harness({ files: RULES_FILES });
    seedTicket(h);
    const out = await launchRules(h);
    assert.deepEqual(out, { outcome: "launched", sessionUrl: SESSION });
    assert.equal(h.routineCalls[0].body, `{"text":"livraison #12 ${HEAD}"}`);
    assert.equal(quota(h), 1);
    assert.equal(lock(h)?.ticket_id, "t-1");
    assert.deepEqual(posts(h), ["POST /issues/12/comments"]);
    const state = h.db.read("tickets/t-1/admin/delivery") ?? {};
    const ack = state.network_rules_ack as Record<string, unknown>;
    assert.equal(ack.head_sha, HEAD);
    assert.equal(ack.ack_id, ACK_ID);
    assert.equal(ack.comment_id, 9000);
    assert.deepEqual(ack.files, ["CLAUDE.md", "scripts/changelog-recent.mjs"]);
    assert.deepEqual(ack.controls, [10, 65]);
    assert.equal(state.network_rules_ack_valid, true);
  });

  it("deux appels : accord publié une seule fois (ligne Accord <id> reconnue)", async () => {
    const scene: Scene = { files: RULES_FILES };
    const h = harness(scene, async (n) =>
      n === 1
        ? new Response(JSON.stringify({ error: "bad" }), { status: 400 })
        : new Response(JSON.stringify({ claude_code_session_url: SESSION }), { status: 200 }),
    );
    seedTicket(h);
    await refusal(launchRules(h));
    // L'accord est publié et noté ; le second appel le reprend sans republier.
    assert.equal(posts(h).length, 1);
    await launchRules(h, { newAckId: () => "Autre0000000000000001" });
    assert.equal(posts(h).length, 1);
    assert.equal(quota(h), 1);
    // Accord publié mais non noté (fonction coupée) : reconnu sur l'Issue, pas republié.
    const h2 = harness({
      files: RULES_FILES,
      comments: [
        {
          id: 555,
          user: { id: OWNER },
          body: `${NETWORK_RULES_ACK_TITLE}\n\nAccord ${ACK_ID}`,
          created_at: "2026-11-14T08:59:00Z",
        },
      ],
    });
    seedTicket(h2);
    h2.db.seed("tickets/t-1/admin/delivery", {
      network_rules_ack: {
        head_sha: HEAD,
        at: Timestamp.fromMillis(NOW),
        ack_id: ACK_ID,
        comment_id: null,
        files: ["CLAUDE.md", "scripts/changelog-recent.mjs"],
        controls: [10, 65],
      },
    });
    await launchRules(h2, { newAckId: () => "Autre0000000000000001" });
    assert.equal(posts(h2).length, 0);
    const ack = h2.db.read("tickets/t-1/admin/delivery")?.network_rules_ack as Record<
      string,
      unknown
    >;
    assert.equal(ack.comment_id, 555);
  });

  it("tête changée entre l'affichage et l'appel : delivery_head_changed", async () => {
    const h = harness({ files: RULES_FILES });
    seedTicket(h);
    await rulesRefused(h, "delivery_head_changed", { mode: "network_rules", headSha: HEAD_B });
    assert.equal(posts(h).length, 0);
  });

  it("CLAUDE.md et functions/src/auth.ts : delivery_sensitive_files", async () => {
    const h = harness({ files: [...RULES_FILES, { filename: "functions/src/auth.ts" }] });
    seedTicket(h);
    await rulesRefused(h, "delivery_sensitive_files");
  });

  for (const filename of ["docs/CLAUDE.md", "scripts/check-version.mjs"]) {
    it(`${filename} : delivery_sensitive_files`, async () => {
      const h = harness({ files: [...RULES_FILES, { filename }] });
      seedTicket(h);
      await rulesRefused(h, "delivery_sensitive_files");
    });
  }

  it("aucune règle du réseau : delivery_no_network_rules", async () => {
    const h = harness();
    seedTicket(h);
    const err = await rulesRefused(h, "delivery_no_network_rules");
    assert.match(String(details(err).reason), /utilisez « Livrer »/);
  });

  it("CLAUDE.md sans patch : delivery_network_rules_unreadable", async () => {
    const h = harness({ files: [{ filename: "CLAUDE.md" }] });
    seedTicket(h);
    await rulesRefused(h, "delivery_network_rules_unreadable");
  });

  it("1 001 fichiers : delivery_files_unreadable", async () => {
    const h = harness({
      files: [
        { filename: "CLAUDE.md", patch: PATCH },
        ...Array.from({ length: 1000 }, (_, i) => ({ filename: `app/lib/f${i}.dart` })),
      ],
    });
    seedTicket(h);
    await rulesRefused(h, "delivery_files_unreadable");
  });

  it("CI rouge : delivery_ci_not_green", async () => {
    const h = harness({ files: RULES_FILES, runs: RED });
    seedTicket(h);
    await rulesRefused(h, "delivery_ci_not_green");
  });

  it("scripts/changelog-recent.mjs seul : accepté après accord, « Contrôles : aucun »", async () => {
    const scene: Scene = { files: [{ filename: "scripts/changelog-recent.mjs" }] };
    const h = harness(scene);
    seedTicket(h);
    await launchRules(h);
    assert.equal(quota(h), 1);
    const body = String(scene.comments?.[0]?.body);
    assert.match(body, /^Fichiers : scripts\/changelog-recent\.mjs$/m);
    assert.match(body, /^Contrôles : aucun$/m);
  });

  it("verrou tenu par un autre ticket : delivery_running_elsewhere, aucun accord publié", async () => {
    const h = harness({ files: RULES_FILES });
    seedTicket(h);
    seedTicket(h, "t-2", { github_issue_number: 13 });
    h.db.seed("ticket_status/launches", {
      delivery_running: {
        ticket_id: "t-2",
        issue_number: 13,
        launched_at: Timestamp.fromMillis(NOW - HOUR),
        retry_after: Timestamp.fromMillis(NOW + 2 * HOUR),
      },
    });
    const err = await refusal(launchRules(h));
    assert.equal(details(err).code, "delivery_running_elsewhere");
    assert.equal(posts(h).length, 0);
    assert.equal(quota(h), 0);
  });

  it("publication en échec : delivery_ack_publish_failed, verrou rendu, rien compté (P44)", async () => {
    const h = harness({ files: RULES_FILES, commentStatus: 500 });
    seedTicket(h);
    await rulesRefused(h, "delivery_ack_publish_failed");
    // Un seul journal d'erreur pour ce refus : celui de l'appel GitHub en échec.
    const errors = h.logs.filter(
      (l) => l.level === "error" && /accord|commentaire/.test(l.entry.message),
    );
    assert.equal(errors.length, 1, errors.map((l) => l.entry.message).join(" | "));
    const state = h.db.read("tickets/t-1/admin/delivery") ?? {};
    const ack = state.network_rules_ack as Record<string, unknown>;
    assert.equal(ack.comment_id, null);
    assert.equal(state.network_rules_ack_valid, false);
    assert.equal(h.db.read("tickets/t-1")?.decision_lease_until, undefined);
  });
});

describe("règles du réseau : arguments de launchTicketDelivery (P25, P30)", () => {
  it("mode absent ou deliver ; network_rules avec headSha ; le reste refusé", () => {
    assert.deepEqual(readDeliveryArgs({ ticketId: "t-1" }), { mode: "deliver", headSha: null });
    assert.deepEqual(readDeliveryArgs({ ticketId: "t-1", mode: "deliver" }), {
      mode: "deliver",
      headSha: null,
    });
    assert.deepEqual(readDeliveryArgs({ ticketId: "t-1", mode: "network_rules", headSha: HEAD }), {
      mode: "network_rules",
      headSha: HEAD,
    });
    const field = (data: unknown) => {
      try {
        readDeliveryArgs(data);
      } catch (err) {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, "invalid-argument");
        return (err.details as Record<string, unknown>).field;
      }
      return assert.fail("refus attendu");
    };
    assert.equal(field({ ticketId: "t", mode: "deliver", headSha: HEAD }), "headSha");
    assert.equal(field({ ticketId: "t", mode: "network_rules" }), "headSha");
    assert.equal(
      field({ ticketId: "t", mode: "network_rules", headSha: HEAD.toUpperCase() }),
      "headSha",
    );
    assert.equal(
      field({ ticketId: "t", mode: "network_rules", headSha: "a".repeat(39) }),
      "headSha",
    );
    assert.equal(field({ ticketId: "t", mode: "autre" }), "mode");
    assert.equal(field({ ticketId: "t", mode: 1 }), "mode");
    assert.equal(field({ ticketId: "t", model: "x" }), "model");
  });

  it("brasseur refusé avant la lecture des arguments ; admin : network_rules jusqu'à l'accord", async () => {
    const h = harness({ files: RULES_FILES });
    seedTicket(h);
    const req = (data: unknown) => ({
      auth: {
        uid: "admin-uid",
        token: {
          email: "admin@exemple.fr",
          email_verified: true,
          firebase: { sign_in_provider: "google.com" },
        },
      },
      data,
    });
    const brewer = await refusal(
      handleDeliveryCall(req({ ticketId: "t-1", mode: "x" }), {
        ...h.deps(),
        lookup: async () => ({ role: "brewer" }),
      }),
    );
    assert.equal(brewer.code, "permission-denied");
    const out = await handleDeliveryCall(
      req({ ticketId: "t-1", mode: "network_rules", headSha: HEAD }),
      { ...h.deps(), newAckId: () => ACK_ID, lookup: async () => ({ role: "admin" }) },
    );
    assert.equal(out.outcome, "launched");
    assert.equal(h.githubCalls.filter((c) => c.startsWith("POST ")).length, 1);
  });
});
