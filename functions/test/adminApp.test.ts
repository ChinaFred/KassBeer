// Application par défaut du SDK Admin : créée même quand `firebase-functions` a déjà créé
// son application nommée pour vérifier le jeton d'une callable (panne `app/no-app`).

import assert from "node:assert/strict";
import { after, describe, it } from "node:test";

import * as AdminApp from "firebase-admin/app";

import { DEFAULT_APP_NAME, ensureDefaultApp } from "../src/adminApp";

describe("ensureDefaultApp", () => {
  after(async () => {
    await Promise.all(AdminApp.getApps().map((a) => AdminApp.deleteApp(a)));
  });

  it("crée l'application par défaut quand une application nommée existe déjà", () => {
    AdminApp.initializeApp({ projectId: "demo-kassbeer" }, "__FIREBASE_FUNCTIONS_SDK__");
    assert.equal(AdminApp.getApps().length, 1);
    ensureDefaultApp(AdminApp);
    assert.equal(AdminApp.getApp().name, DEFAULT_APP_NAME);
    assert.equal(AdminApp.getApps().length, 2);
  });

  it("ne crée pas une seconde application par défaut", () => {
    ensureDefaultApp(AdminApp);
    ensureDefaultApp(AdminApp);
    assert.equal(AdminApp.getApps().filter((a) => a.name === DEFAULT_APP_NAME).length, 1);
  });
});
