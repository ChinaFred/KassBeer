// Base Firestore en mémoire pour les tests des lancements (ADR-008, T4 et T5) et des
// décisions (T7). Elle couvre ce que lit et écrit `src/tickets/launch.ts`,
// `src/tickets/delivery.ts` et `src/tickets/decisions.ts` (et, dans `validatedByApp.test.ts`,
// la réponse, `applyIssue` et le report de `sync.ts`) : documents et sous-collections,
// identifiant tiré par `doc()`, `where(champ, "==", valeur)`, `orderBy(champ, "desc")` sur un
// `Timestamp`, `get` (requête lue aussi en transaction), `set` (fusion de premier niveau),
// `update`, transactions exécutées l'une après l'autre (deux appels simultanés se suivent,
// comme deux transactions Firestore qui se rejouent), `Timestamp`, `FieldValue.delete()` et
// `FieldValue.serverTimestamp()` du SDK Admin.

import { FieldPath, FieldValue, Timestamp } from "firebase-admin/firestore";

import type { FirestoreKit } from "../src/firestore";

type Data = Record<string, unknown>;

const DELETE = FieldValue.delete();
const SERVER_TIME = FieldValue.serverTimestamp();

export class FakeDb {
  readonly docs = new Map<string, Data>();
  /** Écritures validées, dans l'ordre (chemin du document). */
  readonly writes: string[] = [];
  private queue: Promise<unknown> = Promise.resolve();
  private nextId = 0;

  constructor(private readonly now: () => number = Date.now) {}

  collection(name: string): FakeCollection {
    return new FakeCollection(this, name);
  }

  read(path: string): Data | undefined {
    const d = this.docs.get(path);
    return d === undefined ? undefined : { ...d };
  }

  /** Identifiant tiré par `doc()` sans argument : `auto-1`, `auto-2`… */
  newId(): string {
    this.nextId += 1;
    return `auto-${this.nextId}`;
  }

  seed(path: string, data: Data): void {
    this.docs.set(path, { ...data });
  }

  apply(path: string, data: Data, mode: "set" | "merge" | "update"): void {
    const current = this.docs.get(path);
    if (mode === "update" && current === undefined) {
      throw new Error(`NOT_FOUND: ${path}`);
    }
    const next: Data = mode === "set" ? {} : { ...(current ?? {}) };
    for (const [k, v] of Object.entries(data)) {
      if (v instanceof FieldValue && v.isEqual(DELETE)) delete next[k];
      else if (v instanceof FieldValue && v.isEqual(SERVER_TIME)) {
        next[k] = Timestamp.fromMillis(this.now());
      } else next[k] = v;
    }
    this.docs.set(path, next);
    this.writes.push(path);
  }

  runTransaction<T>(fn: (tx: FakeTx) => Promise<T>): Promise<T> {
    const run = this.queue.then(async () => {
      const tx = new FakeTx(this);
      const result = await fn(tx);
      for (const w of tx.pending) this.apply(w.path, w.data, w.mode);
      return result;
    });
    // La file continue après un échec : la transaction suivante part quand même.
    this.queue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  kit(): FirestoreKit {
    return {
      db: this as unknown as FirestoreKit["db"],
      FieldValue,
      Timestamp,
      FieldPath,
    };
  }
}

export class FakeCollection {
  constructor(
    private readonly db: FakeDb,
    readonly path: string,
  ) {}

  doc(id?: string): FakeDocRef {
    const docId = id ?? this.db.newId();
    return new FakeDocRef(this.db, `${this.path}/${docId}`, docId);
  }

  /**
   * Requête par identifiant de document (report de `sync.ts`), ou par un champ `Timestamp`
   * en ordre décroissant (décision la plus récente, `decisions.ts`).
   */
  orderBy(field: unknown, direction?: string): FakeQuery {
    if (typeof field === "string" && direction === "desc") {
      return new FakeQuery(this.db, this, null, null, [], field);
    }
    if (!(field instanceof FieldPath) || !field.isEqual(FieldPath.documentId())) {
      throw new Error('FakeCollection : orderBy(documentId) ou orderBy(champ, "desc") seuls');
    }
    return new FakeQuery(this.db, this, null, null);
  }

  /** Égalité seule (livraison : tickets d'une Issue, tickets `in_progress`). */
  where(field: string, op: string, value: unknown): FakeQuery {
    if (op !== "==") throw new Error(`FakeCollection : opérateur ${op} non pris en charge`);
    return new FakeQuery(this.db, this, null, null, [{ field, value }]);
  }
}

/** `orderBy(documentId)`, `select`, `limit`, `startAfter`, `get` : assez pour un parcours paginé. */
export class FakeQuery {
  constructor(
    private readonly db: FakeDb,
    private readonly coll: FakeCollection,
    private readonly max: number | null,
    private readonly afterId: string | null,
    private readonly filters: readonly { field: string; value: unknown }[] = [],
    private readonly descBy: string | null = null,
  ) {}

  select(..._fields: string[]): FakeQuery {
    return this;
  }

  limit(n: number): FakeQuery {
    return new FakeQuery(this.db, this.coll, n, this.afterId, this.filters, this.descBy);
  }

  startAfter(snap: FakeSnapshot): FakeQuery {
    return new FakeQuery(this.db, this.coll, this.max, snap.id, this.filters, this.descBy);
  }

  async get(): Promise<{ docs: FakeSnapshot[] }> {
    const prefix = `${this.coll.path}/`;
    const ids = [...this.db.docs.keys()]
      .filter((p) => p.startsWith(prefix) && !p.slice(prefix.length).includes("/"))
      .map((p) => p.slice(prefix.length))
      .sort()
      .filter((id) => this.afterId === null || id > this.afterId)
      .filter((id) => {
        const data = this.db.read(`${this.coll.path}/${id}`) ?? {};
        return this.filters.every((f) => data[f.field] === f.value);
      });
    const descBy = this.descBy;
    if (descBy !== null) {
      // Comme Firestore : un document sans le champ trié n'est pas rendu.
      const at = (id: string) => this.db.read(`${this.coll.path}/${id}`)?.[descBy];
      ids.splice(0, ids.length, ...ids.filter((id) => at(id) instanceof Timestamp));
      ids.sort((a, b) => (at(b) as Timestamp).toMillis() - (at(a) as Timestamp).toMillis());
    }
    const page = this.max === null ? ids : ids.slice(0, this.max);
    const docs = page.map((id) => {
      const ref = this.coll.doc(id);
      return new FakeSnapshot(ref, this.db.read(ref.path));
    });
    return { docs, size: docs.length, empty: docs.length === 0 } as {
      docs: FakeSnapshot[];
    };
  }
}

export class FakeSnapshot {
  constructor(
    readonly ref: FakeDocRef,
    private readonly value: Data | undefined,
  ) {}

  get id(): string {
    return this.ref.id;
  }

  get exists(): boolean {
    return this.value !== undefined;
  }

  data(): Data | undefined {
    return this.value === undefined ? undefined : { ...this.value };
  }

  get(field: string): unknown {
    return this.value?.[field];
  }
}

export class FakeDocRef {
  constructor(
    private readonly db: FakeDb,
    readonly path: string,
    readonly id: string,
  ) {}

  collection(name: string): FakeCollection {
    return new FakeCollection(this.db, `${this.path}/${name}`);
  }

  async get(): Promise<FakeSnapshot> {
    return new FakeSnapshot(this, this.db.read(this.path));
  }

  async set(data: Data, opts: { merge?: boolean } = {}): Promise<void> {
    this.db.apply(this.path, data, opts.merge === true ? "merge" : "set");
  }

  async update(data: Data): Promise<void> {
    this.db.apply(this.path, data, "update");
  }
}

export class FakeTx {
  readonly pending: { path: string; data: Data; mode: "set" | "merge" | "update" }[] = [];

  constructor(private readonly db: FakeDb) {}

  get(ref: FakeDocRef): Promise<FakeSnapshot>;
  get(query: FakeQuery): Promise<{ docs: FakeSnapshot[] }>;
  async get(target: FakeDocRef | FakeQuery): Promise<FakeSnapshot | { docs: FakeSnapshot[] }> {
    if (target instanceof FakeQuery) return target.get();
    return new FakeSnapshot(target, this.db.read(target.path));
  }

  set(ref: FakeDocRef, data: Data, opts: { merge?: boolean } = {}): void {
    this.pending.push({ path: ref.path, data, mode: opts.merge === true ? "merge" : "set" });
  }

  update(ref: FakeDocRef, data: Data): void {
    if (this.db.read(ref.path) === undefined) throw new Error(`NOT_FOUND: ${ref.path}`);
    this.pending.push({ path: ref.path, data, mode: "update" });
  }
}
