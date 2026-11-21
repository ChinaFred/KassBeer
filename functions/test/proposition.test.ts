// Propositions de l'assistant de recette (ADR-015, section 6, lot A2 ; P59, P61) : format de
// sortie tiré de test-fixtures/recipe_assistant_operations.json (logique dupliquée avec
// exchange/lib/src/proposition.dart), lecture d'une proposition (`reading_cases`), sortie d'un
// tour (proposition hors format ou de plus de 30 opérations rendue null, tour compté), prompt.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, describe, it } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import type { MemberLookup } from "../src/auth";
import { resetRunSamplers } from "../src/ai/run";
import { ASSISTANT_PROMPT_VERSION, ASSISTANT_SYSTEM_PROMPT } from "../src/assistant/prompt";
import {
  MAX_OPERATIONS,
  PROPOSITION_OPERATIONS,
  RESUME_MAX_CHARS,
  assistantOutputFormat,
  readProposition,
  readTurnOutput,
} from "../src/assistant/proposition";
import { handleRecipeAssistantCall } from "../src/assistant/turn";
import { anthropicResponse, FEATURE, PRICING } from "./aiFixtures";
import { FakeDb } from "./fakeFirestore";

const fixture = JSON.parse(
  readFileSync(join(__dirname, "../../../test-fixtures/recipe_assistant_operations.json"), "utf8"),
) as {
  max_operations: number;
  resume_max_chars: number;
  operations: Record<
    string,
    { fields: Record<string, Record<string, unknown>>; required: string[] }
  >;
  reading_cases: { name: string; proposition: unknown; valid: boolean; path?: string }[];
};

interface OperationSchema {
  additionalProperties: boolean;
  required: string[];
  properties: Record<string, { type: string; enum?: string[] }> & {
    op: { type: string; enum: string[] };
  };
}

interface OutputSchema {
  required: string[];
  additionalProperties: boolean;
  properties: {
    proposition: {
      anyOf: [unknown, { properties: { operations: { items: { anyOf: OperationSchema[] } } } }];
    };
  };
}

const NOW = Date.parse("2026-11-21T10:00:00Z");
const CC = "recipe_assistant_turn";

function run(text: string, logs: string[] = []) {
  const db = new FakeDb(() => NOW);
  db.seed("ai_config/policy", { version: 1, features: { [CC]: FEATURE } });
  db.seed("ai_config/pricing", PRICING);
  const lookup: MemberLookup = async () => ({ role: "admin" });
  let calls = 0;
  const call = (data: Record<string, unknown>) =>
    handleRecipeAssistantCall(
      {
        auth: {
          uid: "u-admin",
          token: {
            email: "admin@example.com",
            email_verified: true,
            firebase: { sign_in_provider: "google.com" },
          },
        },
        data,
      },
      {
        apiKey: () => "sk-ant-api03-cle-du-test-proposition-CCCCCCCCCC",
        kit: async () => db.kit(),
        lookup,
        nowMs: () => NOW,
        log: (_level, entry) => logs.push(JSON.stringify(entry)),
        fetchImpl: async () => {
          calls++;
          return anthropicResponse(text);
        },
      },
    );
  return { db, call, calls: () => calls };
}

const ARGS = {
  conversationId: "conv_Proposition1",
  message: "Ajoute du houblon en fin d'ébullition.",
  recipe: { name: "Blonde", ingredients: {} },
};

const OP = {
  op: "add_hop",
  name: "Citra",
  form: "pellet",
  amount_g: 30,
  use: "whirlpool",
  time_min: 15,
};

beforeEach(() => resetRunSamplers());

describe("recipe_assistant_operations.json — PROPOSITION_OPERATIONS (logique dupliquée)", () => {
  it("copie égale à la fixture : opérations, plafond, résumé", () => {
    assert.deepEqual(JSON.parse(JSON.stringify(PROPOSITION_OPERATIONS)), fixture.operations);
    assert.equal(MAX_OPERATIONS, fixture.max_operations);
    assert.equal(RESUME_MAX_CHARS, fixture.resume_max_chars);
  });
  it("format de sortie tiré de la fixture : une branche par opération, champs et requis", () => {
    const format = assistantOutputFormat();
    assert.equal(format.type, "json_schema");
    const schema = format.schema as OutputSchema;
    assert.deepEqual(schema.required, ["reponse", "proposition"]);
    assert.equal(schema.additionalProperties, false);
    const branches = schema.properties.proposition.anyOf;
    assert.deepEqual(branches[0], { type: "null" });
    const operations = branches[1].properties.operations.items.anyOf;
    assert.deepEqual(
      operations.map((o) => o.properties.op.enum[0]),
      Object.keys(fixture.operations),
    );
    for (const o of operations) {
      const spec = fixture.operations[o.properties.op.enum[0]];
      assert.equal(o.additionalProperties, false);
      assert.deepEqual(o.required, ["op", ...spec.required]);
      assert.deepEqual(Object.keys(o.properties), ["op", ...Object.keys(spec.fields)]);
      for (const [key, field] of Object.entries(spec.fields)) {
        const expected =
          field.type === "enum"
            ? { type: "string", enum: field.values }
            : { type: field.type as string };
        // Bornes absentes du format : le client refuse l'opération seule.
        assert.deepEqual(o.properties[key], expected, key);
      }
    }
  });
  it("aucune opération ni champ sur notes, author, brew_steps, prix ou stock", () => {
    const text = JSON.stringify(assistantOutputFormat());
    for (const forbidden of ["notes", "author", "brew_steps", "price", "stock", "cost"]) {
      assert.ok(!text.includes(forbidden), forbidden);
    }
  });
});

describe("lecture d'une proposition (reading_cases de la fixture)", () => {
  for (const c of fixture.reading_cases) {
    it(c.name, () => {
      const read = readProposition(c.proposition);
      assert.equal(read.ok, c.valid);
      if (c.path !== undefined && !read.ok) assert.equal(read.path, c.path);
      if (c.path !== undefined) assert.equal(read.ok, false);
    });
  }
  it("30 opérations acceptées, 31 refusées", () => {
    const of = (n: number) => ({
      resume: "R.",
      operations: Array.from({ length: n }, (_, i) => ({ op: "set_boil_time_min", value: i })),
    });
    assert.equal(readProposition(of(30)).ok, true);
    assert.deepEqual(readProposition(of(31)), { ok: false, path: "operations" });
  });
  it("résumé de 500 caractères accepté, 501 refusé", () => {
    const of = (n: number) => ({ resume: "r".repeat(n), operations: [OP] });
    assert.equal(readProposition(of(500)).ok, true);
    assert.equal(readProposition(of(501)).ok, false);
  });
});

describe("sortie d'un tour (P59)", () => {
  it("proposition valide rendue", async () => {
    const r = run(
      JSON.stringify({
        reponse: "Ajout d'un whirlpool.",
        proposition: { resume: "Whirlpool.", operations: [OP] },
      }),
    );
    const res = await r.call(ARGS);
    assert.deepEqual(res.proposition, { resume: "Whirlpool.", operations: [OP] });
    assert.equal(res.proposition_rejected, false);
    assert.equal(res.reponse, "Ajout d'un whirlpool.");
  });
  it("proposition hors schéma : null, tour compté, chemin journalisé sans valeur", async () => {
    const logs: string[] = [];
    const r = run(
      JSON.stringify({
        reponse: "Voici.",
        proposition: { resume: "R.", operations: [{ ...OP, price_eur: 4 }] },
      }),
      logs,
    );
    const res = await r.call(ARGS);
    assert.equal(res.proposition, null);
    assert.equal(res.proposition_rejected, true);
    assert.equal(res.quota.remaining, 19);
    assert.equal(r.calls(), 1);
    const warn = logs.find((l) => l.includes("proposition hors format"));
    assert.ok(warn?.includes("operations.0.<champ inconnu>"));
    assert.ok(!logs.join("").includes("price_eur"));
    assert.ok(!logs.join("").includes("Citra"));
  });
  it("clé de 200 caractères écrite par le modèle : absente du journal capturé", async () => {
    const logs: string[] = [];
    const key = `k${"x".repeat(199)}`;
    const r = run(
      JSON.stringify({
        reponse: "Voici.",
        proposition: { resume: "R.", operations: [{ ...OP, [key]: 1 }] },
      }),
      logs,
    );
    const res = await r.call(ARGS);
    assert.equal(res.proposition, null);
    assert.ok(!logs.join("").includes("x".repeat(50)));
    assert.deepEqual(readProposition({ resume: "R.", operations: [{ ...OP, [key]: 1 }] }), {
      ok: false,
      path: "operations.0.<champ inconnu>",
    });
  });
  it("31 opérations : null, tour compté", async () => {
    const r = run(
      JSON.stringify({
        reponse: "Beaucoup de changements.",
        proposition: { resume: "R.", operations: Array.from({ length: 31 }, () => OP) },
      }),
    );
    const res = await r.call(ARGS);
    assert.equal(res.proposition, null);
    assert.equal(res.proposition_rejected, true);
    assert.equal(res.quota.remaining, 19);
  });
  it("sortie qui n'est pas du JSON : ai_no_answer, tour compté, texte non journalisé", async () => {
    const logs: string[] = [];
    const r = run("Texte libre du modèle", logs);
    let err: unknown;
    try {
      await r.call(ARGS);
    } catch (e) {
      err = e;
    }
    assert.ok(err instanceof HttpsError);
    assert.equal((err.details as Record<string, unknown>).reason, "ai_no_answer");
    assert.equal((err.details as Record<string, unknown>).counted, true);
    assert.ok(!logs.join("").includes("Texte libre"));
  });
  it("reponse absente ou vide : sortie illisible", () => {
    const log = () => undefined;
    assert.equal(readTurnOutput(JSON.stringify({ proposition: null }), log), null);
    assert.equal(readTurnOutput(JSON.stringify({ reponse: " ", proposition: null }), log), null);
    assert.equal(readTurnOutput("[]", log), null);
  });
  it("mode summary : texte rendu tel quel, jamais de proposition", async () => {
    const text = JSON.stringify({ reponse: "x", proposition: { resume: "R.", operations: [OP] } });
    const r = run(text);
    const res = await r.call({
      conversationId: ARGS.conversationId,
      recipe: ARGS.recipe,
      mode: "summary",
      history: [
        { role: "user", text: "q" },
        { role: "assistant", text: "r" },
      ],
    });
    assert.equal(res.proposition, null);
    assert.equal(res.reponse, text);
  });
});

describe("prompt de l'assistant, version 2 (lot A2)", () => {
  it("version 2", () => assert.equal(ASSISTANT_PROMPT_VERSION, 2));
  it("valeur technique seulement en l'absence de la Bibliothèque", () => {
    assert.ok(
      ASSISTANT_SYSTEM_PROMPT.includes(
        "Kass'Beer prend d'abord la valeur de sa Bibliothèque ; la tienne n'est gardée que si la Bibliothèque n'en a pas",
      ),
    );
  });
  it("aucune opération sur les notes, l'auteur ni la chronologie", () => {
    assert.ok(
      ASSISTANT_SYSTEM_PROMPT.includes(
        "Aucune opération ne touche les notes, l'auteur ni la chronologie du jour",
      ),
    );
  });
  it("quand proposer, et plafond de 30 opérations", () => {
    assert.ok(
      ASSISTANT_SYSTEM_PROMPT.includes("Pour une analyse ou une question, proposition vaut null."),
    );
    assert.ok(ASSISTANT_SYSTEM_PROMPT.includes(`de 1 à ${MAX_OPERATIONS} opérations`));
    assert.ok(ASSISTANT_SYSTEM_PROMPT.includes(`${RESUME_MAX_CHARS} caractères au plus`));
  });
  it("chaque opération et chaque champ technique nommés dans le prompt existent", () => {
    for (const field of [
      "color_ebc",
      "yield_pct",
      "alpha_acid_pct",
      "attenuation_pct",
      "amount_g",
      "amount_l",
      "days",
      "time_min",
      "temperature_c",
    ]) {
      assert.ok(ASSISTANT_SYSTEM_PROMPT.includes(field), field);
      assert.ok(
        Object.values(PROPOSITION_OPERATIONS).some((o) => field in o.fields),
        field,
      );
    }
  });
});
