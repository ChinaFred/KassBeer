// Capture d'écran jointe à un ticket (ADR-008, T6) : garde de la callable (P30), chemin,
// auteur, fichier déposé (type, taille, signature) et écriture de `screenshot_path`.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import type { MemberLookup, TokenClaims } from "../src/auth";
import type { ScreenshotStore, StoredFile } from "../src/storage";
import {
  SCREENSHOT_MAX_BYTES,
  handleScreenshotCall,
  screenshotBytesMatch,
  screenshotContentType,
  screenshotPaths,
} from "../src/tickets/screenshot";
import { FakeDb } from "./fakeFirestore";

const PNG = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46]);
const GIF = Uint8Array.from([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0]);

const google = (email: string, extra: Record<string, unknown> = {}): TokenClaims => ({
  email,
  email_verified: true,
  firebase: { sign_in_provider: "google.com" },
  ...extra,
});

const MEMBERS: Record<string, Record<string, unknown>> = {
  "brewer.a@example.com": { role: "brewer" },
  "brewer.b@example.com": { role: "brewer" },
  "admin@example.com": { role: "admin" },
};
const lookup: MemberLookup = async (key) => MEMBERS[key] ?? null;

const PROFILES = {
  owner: { uid: "brewer-a", token: google("brewer.a@example.com") },
  otherBrewer: { uid: "brewer-b", token: google("brewer.b@example.com") },
  admin: { uid: "admin", token: google("admin@example.com") },
  nonMember: { uid: "stranger", token: google("stranger@example.com") },
  unverified: {
    uid: "unverified",
    token: google("brewer.a@example.com", { email_verified: false }),
  },
  passwordProvider: {
    uid: "password",
    token: google("brewer.a@example.com", { firebase: { sign_in_provider: "password" } }),
  },
};

const PNG_PATH = "tickets/brewer-a/t1/screenshot.png";
const JPG_PATH = "tickets/brewer-a/t1/screenshot.jpg";

/** Bucket en mémoire ; compte les lectures. */
class FakeStore implements ScreenshotStore {
  readonly files = new Map<string, { file: StoredFile; bytes: Uint8Array }>();
  calls = 0;
  failWith: Error | null = null;

  put(path: string, bytes: Uint8Array, contentType: string, size = bytes.length): void {
    this.files.set(path, { file: { exists: true, size, contentType }, bytes });
  }

  async stat(path: string): Promise<StoredFile> {
    this.calls++;
    if (this.failWith !== null) throw this.failWith;
    return this.files.get(path)?.file ?? { exists: false, size: Number.NaN, contentType: "" };
  }

  async head(path: string, count: number): Promise<Uint8Array> {
    this.calls++;
    return (this.files.get(path)?.bytes ?? new Uint8Array()).slice(0, count);
  }
}

function setup() {
  const db = new FakeDb(() => Date.parse("2026-11-14T09:00:00Z"));
  db.seed("tickets/t1", { author_uid: "brewer-a", status: "received" });
  db.seed("tickets/t2", { author_uid: "brewer-b", status: "received" });
  const store = new FakeStore();
  store.put(PNG_PATH, PNG, "image/png", 120_000);
  const deps = { lookup, kit: async () => db.kit(), store };
  return { db, store, deps };
}

function call(
  profile: keyof typeof PROFILES | "anonymous",
  data: unknown,
  deps: ReturnType<typeof setup>["deps"],
) {
  const req = profile === "anonymous" ? { data } : { auth: PROFILES[profile], data };
  return handleScreenshotCall(req, deps);
}

/** Rejette avec ce code d'HttpsError et, s'il est donné, ce `details.code`. */
async function rejectsWith(p: Promise<unknown>, code: string, machine?: string): Promise<void> {
  await assert.rejects(p, (err: unknown) => {
    assert.ok(err instanceof HttpsError, String(err));
    assert.equal(err.code, code);
    if (machine !== undefined) {
      assert.equal((err.details as { code?: string } | undefined)?.code, machine);
    }
    return true;
  });
}

describe("chemins, types et signatures", () => {
  it("deux chemins par ticket, sous l'uid de l'auteur", () => {
    assert.deepEqual(screenshotPaths("u", "t"), [
      "tickets/u/t/screenshot.png",
      "tickets/u/t/screenshot.jpg",
    ]);
    assert.equal(screenshotContentType(PNG_PATH), "image/png");
    assert.equal(screenshotContentType(JPG_PATH), "image/jpeg");
  });

  it("signature PNG sur 8 octets, JPEG sur 3", () => {
    assert.ok(screenshotBytesMatch(PNG, "image/png"));
    assert.ok(screenshotBytesMatch(JPEG, "image/jpeg"));
    assert.ok(!screenshotBytesMatch(JPEG, "image/png"));
    assert.ok(!screenshotBytesMatch(PNG, "image/jpeg"));
    assert.ok(!screenshotBytesMatch(GIF, "image/png"));
    assert.ok(!screenshotBytesMatch(PNG.slice(0, 7), "image/png"));
    assert.ok(!screenshotBytesMatch(PNG, "image/gif"));
  });
});

describe("attachTicketScreenshot — garde (P30)", () => {
  for (const profile of ["anonymous", "nonMember", "unverified", "passwordProvider"] as const) {
    it(`${profile} : refusé avant toute lecture`, async () => {
      const { store, deps, db } = setup();
      // Arguments faux : la garde passe avant leur lecture.
      await rejectsWith(
        call(profile, { ticketId: 42, path: "x".repeat(10_000) }, deps),
        profile === "anonymous" ? "unauthenticated" : "permission-denied",
      );
      assert.equal(store.calls, 0);
      assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
    });
  }

  it("brasseur auteur : capture jointe", async () => {
    const { db, deps } = setup();
    assert.deepEqual(await call("owner", { ticketId: "t1", path: PNG_PATH }, deps), {
      ok: true,
    });
    assert.equal(db.read("tickets/t1")?.screenshot_path, PNG_PATH);
  });

  it("administrateur auteur de son ticket : capture jointe", async () => {
    const { db, store, deps } = setup();
    db.seed("tickets/t3", { author_uid: "admin" });
    store.put("tickets/admin/t3/screenshot.jpg", JPEG, "image/jpeg");
    await call("admin", { ticketId: "t3", path: "tickets/admin/t3/screenshot.jpg" }, deps);
    assert.equal(db.read("tickets/t3")?.screenshot_path, "tickets/admin/t3/screenshot.jpg");
  });

  it("administrateur sur le ticket d'un brasseur : refusé", async () => {
    const { deps } = setup();
    // Le chemin admis est celui de l'appelant : celui du brasseur est hors motif.
    await rejectsWith(
      call("admin", { ticketId: "t1", path: PNG_PATH }, deps),
      "invalid-argument",
      "path_invalid",
    );
    await rejectsWith(
      call("admin", { ticketId: "t1", path: "tickets/admin/t1/screenshot.png" }, deps),
      "permission-denied",
      "not_author",
    );
  });

  it("autre brasseur : refusé, rien écrit", async () => {
    const { db, deps } = setup();
    await rejectsWith(
      call("otherBrewer", { ticketId: "t1", path: "tickets/brewer-b/t1/screenshot.png" }, deps),
      "permission-denied",
      "not_author",
    );
    assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
  });
});

describe("attachTicketScreenshot — arguments", () => {
  it("ticketId absent, non textuel, trop long ou hors motif", async () => {
    const { deps } = setup();
    for (const ticketId of [undefined, 7, "a".repeat(129), "t/1", "../t1"]) {
      await rejectsWith(call("owner", { ticketId, path: PNG_PATH }, deps), "invalid-argument");
    }
  });

  it("chemin trop long refusé avant la comparaison", async () => {
    const { deps } = setup();
    await assert.rejects(
      call("owner", { ticketId: "t1", path: "a".repeat(301) }, deps),
      (err: unknown) =>
        err instanceof HttpsError &&
        (err.details as { field?: string }).field === "path" &&
        err.message === "Chemin de la capture : texte trop long.",
    );
  });

  it("chemin hors motif : autre uid, autre ticket, autre nom, remontée", async () => {
    const { store, deps } = setup();
    for (const path of [
      "tickets/brewer-b/t1/screenshot.png",
      "tickets/brewer-a/t2/screenshot.png",
      "tickets/brewer-a/t1/screenshot.gif",
      "tickets/brewer-a/t1/capture.png",
      "tickets/brewer-a/t1/../t2/screenshot.png",
      "/tickets/brewer-a/t1/screenshot.png",
      42,
    ]) {
      await rejectsWith(call("owner", { ticketId: "t1", path }, deps), "invalid-argument");
    }
    assert.equal(store.calls, 0);
  });
});

describe("attachTicketScreenshot — ticket et fichier", () => {
  it("ticket absent", async () => {
    const { deps } = setup();
    await rejectsWith(
      call("owner", { ticketId: "t9", path: "tickets/brewer-a/t9/screenshot.png" }, deps),
      "not-found",
      "ticket_missing",
    );
  });

  it("fichier absent", async () => {
    const { deps } = setup();
    await rejectsWith(
      call("owner", { ticketId: "t1", path: JPG_PATH }, deps),
      "not-found",
      "file_missing",
    );
  });

  it("type annoncé autre que celui de l'extension", async () => {
    const { store, deps } = setup();
    store.put(JPG_PATH, JPEG, "image/png");
    await rejectsWith(
      call("owner", { ticketId: "t1", path: JPG_PATH }, deps),
      "invalid-argument",
      "file_refused",
    );
  });

  for (const [label, size, ok] of [
    ["0 octet", 0, false],
    ["5 Mo exactement", SCREENSHOT_MAX_BYTES, true],
    ["5 Mo + 1 octet", SCREENSHOT_MAX_BYTES + 1, false],
    ["taille illisible", Number.NaN, false],
  ] as const) {
    it(`taille : ${label}`, async () => {
      const { db, store, deps } = setup();
      store.put(PNG_PATH, PNG, "image/png", size);
      const p = call("owner", { ticketId: "t1", path: PNG_PATH }, deps);
      if (ok) {
        await p;
        assert.equal(db.read("tickets/t1")?.screenshot_path, PNG_PATH);
      } else {
        await rejectsWith(p, "invalid-argument", "file_refused");
        assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
      }
    });
  }

  it("premiers octets ni PNG ni JPEG : refusé", async () => {
    const { db, store, deps } = setup();
    store.put(PNG_PATH, GIF, "image/png");
    await rejectsWith(
      call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
      "invalid-argument",
      "file_refused",
    );
    store.put(JPG_PATH, PNG, "image/jpeg");
    await rejectsWith(
      call("owner", { ticketId: "t1", path: JPG_PATH }, deps),
      "invalid-argument",
      "file_refused",
    );
    assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
  });

  it("panne du bucket : erreur interne, rien écrit", async () => {
    const { db, store, deps } = setup();
    store.failWith = new Error("bucket indisponible");
    await rejectsWith(
      call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
      "internal",
      "internal",
    );
    assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
  });

  it("second appel : même chemin réécrit", async () => {
    const { db, deps } = setup();
    await call("owner", { ticketId: "t1", path: PNG_PATH }, deps);
    await call("owner", { ticketId: "t1", path: PNG_PATH }, deps);
    assert.equal(db.read("tickets/t1")?.screenshot_path, PNG_PATH);
  });
});
