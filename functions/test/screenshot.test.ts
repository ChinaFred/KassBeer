// Capture d'écran jointe à un ticket (ADR-008, T6) : garde de la callable (P30), chemin,
// auteur, fichier déposé (type, taille, signature) et écriture de `screenshot_path`.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import type { MemberLookup, TokenClaims } from "../src/auth";
import type { ScreenshotStore, StoredFile } from "../src/storage";
import type { LogEntry } from "../src/logging";
import {
  SCREENSHOT_HEAD_BYTES,
  SCREENSHOT_MAX_BYTES,
  handleScreenshotCall,
  pngDimensions,
  screenshotBytesMatch,
  screenshotPath,
  storageErrorCode,
} from "../src/tickets/screenshot";
import { FakeDb } from "./fakeFirestore";

const SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** Tête d'un PNG : signature, bloc IHDR de 13 octets, largeur, hauteur, puis la suite. */
function pngHead(width: number, height: number, type = "IHDR", length = 13): Uint8Array {
  const bytes = new Uint8Array(33);
  bytes.set(SIGNATURE, 0);
  const view = new DataView(bytes.buffer);
  view.setUint32(8, length);
  for (let i = 0; i < 4; i++) bytes[12 + i] = type.charCodeAt(i);
  view.setUint32(16, width);
  view.setUint32(20, height);
  bytes[24] = 8; // profondeur
  bytes[25] = 6; // RGBA
  return bytes;
}

const PNG = pngHead(1080, 2000);
const NOW = Date.parse("2026-11-14T09:00:00Z");
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
  /** Nombre d'octets demandés à chaque lecture de tête. */
  readonly headCounts: number[] = [];
  failWith: unknown = null;

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
    this.headCounts.push(count);
    return (this.files.get(path)?.bytes ?? new Uint8Array()).slice(0, count);
  }
}

function setup() {
  const db = new FakeDb(() => NOW);
  db.seed("tickets/t1", { author_uid: "brewer-a", status: "received" });
  db.seed("tickets/t2", { author_uid: "brewer-b", status: "received" });
  const store = new FakeStore();
  store.put(PNG_PATH, PNG, "image/png", 120_000);
  const logs: LogEntry[] = [];
  const deps = {
    lookup,
    kit: async () => db.kit(),
    store,
    log: (e: LogEntry) => logs.push(e),
    now: () => NOW,
  };
  return { db, store, deps, logs };
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
  it("un seul chemin par ticket, PNG, sous l'uid de l'auteur", () => {
    assert.equal(screenshotPath("u", "t"), "tickets/u/t/screenshot.png");
  });

  it("signature PNG sur 8 octets", () => {
    assert.ok(screenshotBytesMatch(PNG));
    assert.ok(!screenshotBytesMatch(JPEG));
    assert.ok(!screenshotBytesMatch(GIF));
    assert.ok(!screenshotBytesMatch(PNG.slice(0, 7)));
  });

  it("dimensions lues dans l'en-tête IHDR (octets 16 à 23)", () => {
    assert.deepEqual(pngDimensions(pngHead(1080, 2000)), { width: 1080, height: 2000 });
    assert.deepEqual(pngDimensions(pngHead(0x01020304, 1)), { width: 0x01020304, height: 1 });
    assert.equal(pngDimensions(pngHead(10, 10).slice(0, 23)), null);
    assert.equal(pngDimensions(pngHead(10, 10, "IDAT")), null);
    assert.equal(pngDimensions(pngHead(10, 10, "IHDR", 14)), null);
    assert.equal(pngDimensions(pngHead(0, 10)), null);
    assert.equal(pngDimensions(pngHead(10, 0)), null);
    assert.equal(pngDimensions(JPEG), null);
  });

  it("code d'erreur : nombre, texte court, nom de classe, jamais le message", () => {
    assert.equal(storageErrorCode(Object.assign(new Error(PNG_PATH), { code: 404 })), "404");
    assert.equal(storageErrorCode({ code: "ECONNRESET" }), "ECONNRESET");
    assert.equal(storageErrorCode({ code: PNG_PATH }), "inconnu");
    assert.equal(storageErrorCode(new TypeError(PNG_PATH)), "TypeError");
    assert.equal(storageErrorCode("texte"), "inconnu");
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

  it("brasseur auteur : capture jointe, échéance à 180 jours, 24 octets lus", async () => {
    const { db, store, deps } = setup();
    assert.deepEqual(await call("owner", { ticketId: "t1", path: PNG_PATH }, deps), {
      ok: true,
    });
    const ticket = db.read("tickets/t1");
    assert.equal(ticket?.screenshot_path, PNG_PATH);
    assert.ok(ticket?.screenshot_expires_at instanceof Timestamp);
    assert.equal((ticket?.screenshot_expires_at as Timestamp).toMillis(), NOW + 180 * 86_400_000);
    assert.deepEqual(store.headCounts, [SCREENSHOT_HEAD_BYTES]);
    assert.equal(SCREENSHOT_HEAD_BYTES, 24);
  });

  it("administrateur auteur de son ticket : capture jointe", async () => {
    const { db, store, deps } = setup();
    db.seed("tickets/t3", { author_uid: "admin" });
    store.put("tickets/admin/t3/screenshot.png", PNG, "image/png");
    await call("admin", { ticketId: "t3", path: "tickets/admin/t3/screenshot.png" }, deps);
    assert.equal(db.read("tickets/t3")?.screenshot_path, "tickets/admin/t3/screenshot.png");
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
      JPG_PATH,
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
    const { store, deps } = setup();
    store.files.clear();
    await rejectsWith(
      call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
      "not-found",
      "file_missing",
    );
  });

  it("type annoncé autre que image/png", async () => {
    const { store, deps } = setup();
    store.put(PNG_PATH, PNG, "image/jpeg");
    await rejectsWith(
      call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
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

  it("premiers octets autres que PNG : refusé", async () => {
    const { db, store, deps } = setup();
    for (const bytes of [GIF, JPEG]) {
      store.put(PNG_PATH, bytes, "image/png");
      await rejectsWith(
        call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
        "invalid-argument",
        "file_refused",
      );
    }
    assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
  });

  for (const [label, width, height, ok] of [
    ["2 000 × 2 000", 2000, 2000, true],
    ["largeur 2 001", 2001, 1000, false],
    ["hauteur 2 001", 1000, 2001, false],
    ["largeur sur 32 bits", 0xffffffff, 10, false],
  ] as const) {
    it(`dimensions : ${label}`, async () => {
      const { db, store, deps } = setup();
      store.put(PNG_PATH, pngHead(width, height), "image/png");
      const p = call("owner", { ticketId: "t1", path: PNG_PATH }, deps);
      if (ok) {
        await p;
        assert.equal(db.read("tickets/t1")?.screenshot_path, PNG_PATH);
      } else {
        await rejectsWith(p, "invalid-argument", "dimensions_refused");
        assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
        assert.equal(db.read("tickets/t1")?.screenshot_expires_at, undefined);
      }
    });
  }

  it("en-tête IHDR absent, tronqué ou à côté nul : refusé", async () => {
    const { db, store, deps } = setup();
    for (const bytes of [
      Uint8Array.from(SIGNATURE),
      pngHead(10, 10, "IDAT"),
      pngHead(0, 10),
      pngHead(10, 10).slice(0, 20),
    ]) {
      store.put(PNG_PATH, bytes, "image/png");
      await rejectsWith(
        call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
        "invalid-argument",
        "file_refused",
      );
    }
    assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
  });

  it("panne du bucket : erreur interne, rien écrit, journal sans le chemin", async () => {
    const { db, store, deps, logs } = setup();
    const gcs = Object.assign(
      new Error(`No such object: kassbeer.firebasestorage.app/${PNG_PATH}`),
      { code: 503 },
    );
    store.failWith = gcs;
    await rejectsWith(
      call("owner", { ticketId: "t1", path: PNG_PATH }, deps),
      "internal",
      "internal",
    );
    assert.equal(db.read("tickets/t1")?.screenshot_path, undefined);
    assert.equal(logs.length, 1);
    assert.equal(logs[0].error, undefined);
    assert.deepEqual(logs[0].extra, { errorCode: "503" });
    const written = JSON.stringify(logs);
    assert.ok(!written.includes(PNG_PATH), written);
    assert.ok(!written.includes("brewer-a"), written);
  });

  it("second appel : même chemin réécrit", async () => {
    const { db, deps } = setup();
    await call("owner", { ticketId: "t1", path: PNG_PATH }, deps);
    await call("owner", { ticketId: "t1", path: PNG_PATH }, deps);
    assert.equal(db.read("tickets/t1")?.screenshot_path, PNG_PATH);
  });
});
