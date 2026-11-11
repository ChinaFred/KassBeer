// Options de l'écrivain : émulateur par défaut, production explicite, aucune clé JSON.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  cheminIdentifiants,
  confirmerProduction,
  controlerIdentifiants,
  ErreurOptions,
  lireOptions,
} from "../lib/options.mjs";

const EMULATEUR = { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" };

describe("lireOptions", () => {
  it("émulateur par défaut, projet demo-kassbeer", () => {
    assert.deepEqual(lireOptions([], EMULATEUR), {
      cible: "emulator",
      projet: "demo-kassbeer",
      simulation: false,
      dossier: null,
      rapports: null,
    });
  });

  it("simulation, dossiers et projet demo-*", () => {
    const o = lireOptions(
      ["--simulation", "--dossier", "a", "--rapports", "b", "--projet", "demo-x"],
      EMULATEUR,
    );
    assert.equal(o.simulation, true);
    assert.equal(o.dossier, "a");
    assert.equal(o.rapports, "b");
    assert.equal(o.projet, "demo-x");
  });

  it("sans FIRESTORE_EMULATOR_HOST ni --production : refusé", () => {
    assert.throws(() => lireOptions([], {}), ErreurOptions);
  });

  it("projet non demo-* sur l'émulateur : refusé", () => {
    assert.throws(() => lireOptions(["--projet", "kassbeer"], EMULATEUR), ErreurOptions);
  });

  it("production : --projet kassbeer exigé", () => {
    assert.throws(() => lireOptions(["--production"], {}), ErreurOptions);
    assert.throws(() => lireOptions(["--production", "--projet", "autre"], {}), ErreurOptions);
    assert.deepEqual(lireOptions(["--production", "--projet", "kassbeer"], {}), {
      cible: "production",
      projet: "kassbeer",
      simulation: false,
      dossier: null,
      rapports: null,
    });
  });

  it("production avec FIRESTORE_EMULATOR_HOST : cible ambiguë, refusé", () => {
    assert.throws(
      () => lireOptions(["--production", "--projet", "kassbeer"], EMULATEUR),
      ErreurOptions,
    );
  });

  it("GOOGLE_APPLICATION_CREDENTIALS : refusé dans les deux modes", () => {
    const cle = { GOOGLE_APPLICATION_CREDENTIALS: "cle.json" };
    assert.throws(() => lireOptions([], { ...EMULATEUR, ...cle }), ErreurOptions);
    assert.throws(() => lireOptions(["--production", "--projet", "kassbeer"], cle), ErreurOptions);
  });

  it("variable d'identifiants dans une autre casse, ou CLOUDSDK_CONFIG : refusé", () => {
    for (const cle of [
      "google_application_credentials",
      "Google_Application_Credentials",
      "CLOUDSDK_CONFIG",
      "cloudsdk_config",
    ]) {
      assert.throws(() => lireOptions([], { ...EMULATEUR, [cle]: "x" }), ErreurOptions, cle);
      assert.throws(
        () => lireOptions(["--production", "--projet", "kassbeer"], { [cle]: "" }),
        ErreurOptions,
        cle,
      );
    }
  });

  it("option inconnue ou sans valeur : refusé", () => {
    assert.throws(() => lireOptions(["--force"], EMULATEUR), ErreurOptions);
    assert.throws(() => lireOptions(["--dossier"], EMULATEUR), ErreurOptions);
    assert.throws(() => lireOptions(["--projet", "--simulation"], EMULATEUR), ErreurOptions);
  });
});

describe("confirmerProduction", () => {
  it("sans terminal : refusé avant toute question", async () => {
    await assert.rejects(
      confirmerProduction("kassbeer", { isTTY: false }, { isTTY: true }),
      ErreurOptions,
    );
    await assert.rejects(
      confirmerProduction("kassbeer", { isTTY: true }, { isTTY: undefined }),
      ErreurOptions,
    );
  });
});

describe("controlerIdentifiants", () => {
  const lireType = (type) => () => JSON.stringify({ type, client_id: "x" });

  const emprunt = (typeSource) => () =>
    JSON.stringify({
      type: "impersonated_service_account",
      service_account_impersonation_url: "https://exemple.invalid",
      ...(typeSource === undefined ? {} : { source_credentials: { type: typeSource } }),
    });

  it("compte utilisateur, ou emprunt depuis un compte utilisateur : accepté", () => {
    assert.equal(controlerIdentifiants("adc.json", lireType("authorized_user")), "authorized_user");
    assert.equal(
      controlerIdentifiants("adc.json", emprunt("authorized_user")),
      "impersonated_service_account",
    );
  });

  it("emprunt depuis une clé de compte de service ou sans source : refusé", () => {
    assert.throws(
      () => controlerIdentifiants("adc.json", emprunt("service_account")),
      ErreurOptions,
    );
    assert.throws(() => controlerIdentifiants("adc.json", emprunt(undefined)), ErreurOptions);
  });

  it("clé de compte de service, autre type, fichier absent ou illisible : refusé", () => {
    assert.throws(
      () => controlerIdentifiants("adc.json", lireType("service_account")),
      ErreurOptions,
    );
    assert.throws(
      () => controlerIdentifiants("adc.json", lireType("external_account")),
      ErreurOptions,
    );
    assert.throws(() => controlerIdentifiants("adc.json", () => "{"), ErreurOptions);
    const absent = () => {
      throw Object.assign(new Error("absent"), { code: "ENOENT" });
    };
    assert.throws(() => controlerIdentifiants("adc.json", absent), ErreurOptions);
  });

  it("chemin du fichier ADC de gcloud", () => {
    const windows = cheminIdentifiants({ APPDATA: "D:\\Profil\\Roaming" }, "win32", "D:\\Profil");
    assert.match(windows, /Roaming[\\/]gcloud[\\/]application_default_credentials\.json$/);
    const linux = cheminIdentifiants({}, "linux", "/home/x");
    assert.match(linux, /\.config[\\/]gcloud[\\/]application_default_credentials\.json$/);
  });
});
