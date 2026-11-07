// Outillage commun aux tests de firestore.rules.
//
// Les règles testées sont celles du dépôt, lues sur disque (../firestore.rules) :
// un test ne passe que contre les règles qui partiront en production.
//
// Projet `demo-kassbeer` : le préfixe `demo-` interdit à l'émulateur et au SDK
// tout appel vers un vrai projet.

import { readFileSync } from "node:fs";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

export const PROJECT_ID = "demo-kassbeer";

const google = (email, verified = true) => ({
  email,
  email_verified: verified,
  firebase: { sign_in_provider: "google.com" },
});

/// Comptes de test. `member` : document members/{email} semé avant chaque test
/// (null = compte non invité).
export const PERSONAS = {
  // Les cinq profils de P4.
  anonymous: null,
  nonMember: { uid: "stranger", token: google("stranger@example.com"), member: null },
  owner: {
    uid: "brewer-a",
    token: google("brewer.a@example.com"),
    member: { role: "brewer" },
  },
  otherBrewer: {
    uid: "brewer-b",
    token: google("brewer.b@example.com"),
    member: { role: "brewer" },
  },
  admin: { uid: "admin", token: google("admin@example.com"), member: { role: "admin" } },
  // Cas de P11 : invités, mais connexion non conforme.
  unverified: {
    uid: "unverified",
    token: google("unverified@example.com", false),
    member: { role: "brewer" },
  },
  passwordProvider: {
    uid: "password",
    token: {
      email: "password@example.com",
      email_verified: true,
      firebase: { sign_in_provider: "password" },
    },
    member: { role: "brewer" },
  },
  // Adresse du jeton en majuscules : members/ est lu en minuscules.
  mixedCase: {
    uid: "mixed",
    token: google("Mixed.Case@Example.COM"),
    member: { role: "brewer" },
  },
};

export const FIVE_PROFILES = ["anonymous", "nonMember", "owner", "otherBrewer", "admin"];

export const memberId = (name) => PERSONAS[name].token.email.toLowerCase();

export const uidOf = (name) => PERSONAS[name].uid;

export async function createEnv() {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
    },
  });
}

/// Firestore (SDK compat) vu par un persona ; `anonymous` = sans jeton.
export function db(env, name) {
  const persona = PERSONAS[name];
  const ctx =
    persona === null
      ? env.unauthenticatedContext()
      : env.authenticatedContext(persona.uid, persona.token);
  return ctx.firestore();
}

export const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();
export const Timestamp = firebase.firestore.Timestamp;

/// Écrit des documents en contournant les règles.
export async function seed(env, docs) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    for (const [path, data] of Object.entries(docs)) {
      await fs.doc(path).set(data);
    }
  });
}

/// Sème members/ pour chaque persona invité.
export function memberDocs() {
  const docs = {};
  for (const [name, persona] of Object.entries(PERSONAS)) {
    if (persona?.member) {
      docs[`members/${memberId(name)}`] = {
        email: memberId(name),
        role: persona.member.role,
        display_name: name,
        invited_at: Timestamp.fromDate(new Date("2026-11-01T10:00:00Z")),
        invited_by: "admin",
      };
    }
  }
  return docs;
}

export const CREATED = Timestamp.fromDate(new Date("2026-11-02T08:00:00Z"));

export const recipe = (owner, extra = {}) => ({
  owner_uid: owner,
  name: "Blonde de Noël",
  style: "Belgian Blond Ale",
  batch_volume_l: 20,
  boil_time_min: 60,
  fermentables: [{ key: "malt-pilsner", name: "Pilsner", weight_g: 4500, ebc: 3.5 }],
  hops: [{ key: "houblon-saaz", name: "Saaz", weight_g: 30, alpha_pct: 3.5, time_min: 60 }],
  created_at: CREATED,
  updated_at: CREATED,
  ...extra,
});

export const equipment = (owner, extra = {}) => ({
  owner_uid: owner,
  name: "Grainfather G30",
  kind: "all_in_one",
  mash_efficiency_pct: 72,
  boil_off_l_per_h: 3,
  created_at: CREATED,
  updated_at: CREATED,
  ...extra,
});

// La copie figée reprend la recette r-a et l'équipement e-a de brewer-a.
export const brew = (owner, extra = {}) => ({
  owner_uid: owner,
  recipe_id: "r-a",
  name: "Blonde de Noël #1",
  status: "planned",
  recipe_snapshot: recipe("brewer-a"),
  equipment_snapshot: equipment("brewer-a"),
  created_at: CREATED,
  updated_at: CREATED,
  ...extra,
});

export const event = (owner, extra = {}) => ({
  owner_uid: owner,
  kind: "measurement",
  step_key: "mash-1",
  measure_type: "temperature",
  value: 66.5,
  measured_at: Timestamp.fromDate(new Date("2026-11-03T09:12:00Z")),
  created_at: CREATED,
  ...extra,
});

/// Champs posés par serverTimestamp() à la création.
export const fresh = (data) => ({
  ...data,
  created_at: serverTimestamp(),
  updated_at: serverTimestamp(),
});
