// Contrôle de chaque document avant écriture (ADR-005, « Trois validations ») : liste
// blanche de collections, identifiants, clés autorisées, unités canoniques, provenance,
// taille de beer_index, et schéma BeerJSON partiel (ajv) pour `recipe` des recettes
// publiques. Le schéma partiel est celui que rules-tests dérive des schémas officiels au
// commit figé (rules-tests/test/beerjson_partial.mjs) : aucune seconde dérivation ici.

import Ajv2020 from "ajv/dist/2020.js";
import { partialSchemas } from "../../rules-tests/test/beerjson_partial.mjs";

/// Collections écrites depuis import/ingest/prepare/, dans l'ordre d'écriture.
export const COLLECTIONS = [
  "beer_fermentables",
  "beer_hops",
  "beer_cultures",
  "beer_miscs",
  "beer_styles",
  "beer_index",
  "public_recipes",
  "import_unresolved",
];

/// Collection du compte rendu d'exécution, écrite par l'écrivain lui-même.
export const COLLECTION_EXECUTIONS = "ingest_runs";

/// Taille maximale d'un document de beer_index : 900 Ko (limite Firestore : 1 Mio).
export const TAILLE_MAX_INDEX = 900 * 1024;

const SOURCES = [
  "brewtarget-001",
  "brewtarget-002",
  "brewtarget-003",
  "brewtarget-004",
  "brewtarget-005",
  "diydog",
];
const LICENCES = ["GPL-3.0", "CC BY-SA 4.0", "BJCP (noms et plages)", "DIY Dog (usage privé)"];
const NATURES = ["fermentable", "hop", "culture", "misc"];
const INDEX = ["fermentables", "hops", "cultures", "miscs", "styles"];

const TYPES_FERMENTABLE = [
  "dry extract",
  "extract",
  "grain",
  "sugar",
  "fruit",
  "juice",
  "honey",
  "other",
];
const FORMES_HOUBLON = ["extract", "leaf", "leaf (wet)", "pellet", "powder", "plug"];
const USAGES_HOUBLON = [
  "aroma",
  "bittering",
  "flavor",
  "aroma/bittering",
  "bittering/flavor",
  "aroma/flavor",
  "aroma/bittering/flavor",
];
const TYPES_LEVURE = [
  "ale",
  "bacteria",
  "brett",
  "champagne",
  "kveik",
  "lacto",
  "lager",
  "malolactic",
  "mixed-culture",
  "other",
  "pedio",
  "spontaneous",
  "wheat",
  "wine",
];
const FORMES_LEVURE = ["liquid", "dry", "slant", "culture", "dregs"];
const FLOCULATIONS = [
  "very low",
  "low",
  "medium low",
  "medium",
  "medium high",
  "high",
  "very high",
];
const TYPES_AJOUT = ["spice", "fining", "water agent", "herb", "flavor", "wood", "other"];
const TYPES_STYLE = ["beer", "cider", "kombucha", "mead", "other", "soda", "wine"];

/// Clés de `recipe` acceptées par isBeerJsonRecipe (firestore.rules).
const CLES_RECETTE = [
  "name",
  "type",
  "author",
  "notes",
  "style",
  "batch_size",
  "boil",
  "mash",
  "ingredients",
];
const PLAFONDS = {
  fermentable_additions: 50,
  hop_additions: 50,
  miscellaneous_additions: 50,
  culture_additions: 10,
};

const ID = {
  beer_fermentables: /^fermentable-[a-z0-9]+(-[a-z0-9]+)*$/,
  beer_hops: /^hop-[a-z0-9]+(-[a-z0-9]+)*$/,
  beer_cultures: /^culture-[a-z0-9]+(-[a-z0-9]+)*$/,
  beer_miscs: /^misc-[a-z0-9]+(-[a-z0-9]+)*$/,
  beer_styles: /^bjcp2021-[a-z0-9]+(-[a-z0-9]+)*$/,
  public_recipes: /^diydog-[1-9][0-9]{0,5}$/,
  import_unresolved: /^[0-9a-f]{64}$/,
};

/// Vrai si [id] est l'identifiant d'une entrée de référentiel, de même forme que
/// l'identifiant contrôlé dans sa collection (200 caractères au plus).
function estIdReferentiel(
  id,
  collections = ["beer_fermentables", "beer_hops", "beer_cultures", "beer_miscs"],
) {
  return typeof id === "string" && id.length <= 200 && collections.some((c) => ID[c].test(id));
}

/// Champs permis d'une entrée de beer_index, par document : collection de son
/// identifiant, puis type de chaque champ facultatif (liste de valeurs permises,
/// « texte », « nombre » fini, « aliases », « plage » [min, max] de nombres finis).
const ENTREES_INDEX = {
  fermentables: {
    collection: "beer_fermentables",
    champs: {
      aliases: "aliases",
      label_fr: "texte",
      type: TYPES_FERMENTABLE,
      yield: "nombre",
      color: "nombre",
    },
  },
  hops: {
    collection: "beer_hops",
    champs: { aliases: "aliases", form: FORMES_HOUBLON, alpha: "nombre" },
  },
  cultures: {
    collection: "beer_cultures",
    champs: {
      aliases: "aliases",
      producer: "texte",
      product_id: "texte",
      type: TYPES_LEVURE,
      form: FORMES_LEVURE,
      attenuation: "nombre",
    },
  },
  miscs: {
    collection: "beer_miscs",
    champs: { aliases: "aliases", label_fr: "texte", type: TYPES_AJOUT },
  },
  styles: {
    collection: "beer_styles",
    obligatoires: ["code"],
    champs: {
      code: "code",
      category: "texte",
      og: "plage",
      fg: "plage",
      ibu: "plage",
      ebc: "plage",
      abv: "plage",
    },
  },
};

const estNombre = (v) => typeof v === "number" && Number.isFinite(v);

const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const estTexte = (v, max) => typeof v === "string" && v.length >= 1 && v.length <= max;

/// Taille d'un document Firestore (documentation « Storage size calculations ») :
/// nom du document (segments + 16 octets), champs, 32 octets fixes. Texte : octets
/// UTF-8 + 1 ; nombre, horodatage : 8 ; booléen, null : 1 ; tableau et map : somme.
export function tailleFirestore(chemin, data) {
  const octets = (texte) => Buffer.byteLength(texte, "utf8");
  const valeur = (v) => {
    if (v === null || typeof v === "boolean") return 1;
    if (typeof v === "number") return 8;
    if (typeof v === "string") return octets(v) + 1;
    if (Array.isArray(v)) return v.reduce((n, e) => n + valeur(e), 0);
    if (estObjet(v)) {
      return Object.entries(v).reduce((n, [k, e]) => n + octets(k) + 1 + valeur(e), 0);
    }
    return 8;
  };
  const nom = chemin.split("/").reduce((n, s) => n + octets(s) + 1, 0) + 16;
  return nom + valeur(data) + 32;
}

/// Contrôleur d'un document : rend la liste des erreurs (vide si le document est bon).
class Controle {
  constructor() {
    this.erreurs = [];
  }

  erreur(chemin, message) {
    this.erreurs.push(`${chemin} : ${message}`);
  }

  cles(chemin, objet, permises, obligatoires = []) {
    if (!estObjet(objet)) {
      this.erreur(chemin, "objet attendu");
      return false;
    }
    for (const cle of Object.keys(objet)) {
      if (!permises.includes(cle)) this.erreur(chemin, `clé non permise « ${cle} »`);
    }
    for (const cle of obligatoires) {
      if (!(cle in objet)) this.erreur(chemin, `clé absente « ${cle} »`);
    }
    return true;
  }

  texte(chemin, v, max = 120) {
    if (!estTexte(v, max)) this.erreur(chemin, `texte de 1 à ${max} caractères attendu`);
  }

  valeurDe(chemin, v, permises) {
    if (!permises.includes(v)) this.erreur(chemin, "valeur hors de la liste");
  }

  mesure(chemin, v, unite) {
    if (!this.cles(chemin, v, ["value", "unit"], ["value", "unit"])) return;
    if (typeof v.value !== "number" || !Number.isFinite(v.value)) {
      this.erreur(chemin, "nombre fini attendu");
    }
    if (v.unit !== unite) this.erreur(chemin, `unité ${unite} attendue`);
  }

  plage(chemin, v, unite) {
    if (!this.cles(chemin, v, ["minimum", "maximum"], ["minimum", "maximum"])) return;
    this.mesure(`${chemin}.minimum`, v.minimum, unite);
    this.mesure(`${chemin}.maximum`, v.maximum, unite);
    if (v.minimum?.value > v.maximum?.value) this.erreur(chemin, "minimum au-dessus du maximum");
  }

  facultatif(data, cle, verifier) {
    if (cle in data) verifier(`${cle}`, data[cle]);
  }

  provenance(v) {
    if (!Array.isArray(v) || v.length === 0) {
      this.erreur("provenance", "liste non vide attendue");
      return;
    }
    v.forEach((ligne, i) => {
      const c = `provenance[${i}]`;
      const cles = ["source", "source_id", "version", "licence", "retrieved"];
      if (!this.cles(c, ligne, cles, cles)) return;
      this.valeurDe(`${c}.source`, ligne.source, SOURCES);
      this.valeurDe(`${c}.licence`, ligne.licence, LICENCES);
      this.texte(`${c}.source_id`, ligne.source_id, 200);
      this.texte(`${c}.version`, ligne.version, 40);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(ligne.retrieved))
        this.erreur(`${c}.retrieved`, "date attendue");
    });
  }

  empreinte(data) {
    if (!/^[0-9a-f]{64}$/.test(data.content_sha256 ?? "")) {
      this.erreur("content_sha256", "64 chiffres hexadécimaux attendus");
    }
  }

  entree(data, permises, verifier) {
    const communes = ["name", "aliases", "provenance", "content_sha256"];
    if (!this.cles("data", data, [...communes, ...permises], communes)) return;
    this.texte("name", data.name);
    if (!Array.isArray(data.aliases) || data.aliases.some((a) => !estTexte(a, 120))) {
      this.erreur("aliases", "liste de textes attendue");
    }
    this.facultatif(data, "label_fr", (c, v) => this.texte(c, v));
    this.provenance(data.provenance);
    this.empreinte(data);
    verifier();
  }
}

let validateurRecette = null;

/// Validateur ajv de RecipeType sur le schéma partiel, créé au premier usage.
function recetteValide() {
  if (validateurRecette === null) {
    const ajv = new Ajv2020({ allErrors: true });
    for (const schema of Object.values(partialSchemas())) ajv.addSchema(schema);
    validateurRecette = ajv.compile({
      $ref: "https://raw.githubusercontent.com/beerjson/beerjson/main/json/recipe.json#/$defs/RecipeType",
    });
  }
  return validateurRecette;
}

const CONTROLES = {
  beer_fermentables(k, d) {
    k.entree(d, ["label_fr", "type", "yield", "color", "producer", "origin"], () => {
      if (!("type" in d)) k.erreur("type", "absent");
      k.facultatif(d, "type", (c, v) => k.valeurDe(c, v, TYPES_FERMENTABLE));
      k.facultatif(d, "yield", (c, v) => {
        if (k.cles(c, v, ["fine_grind"], ["fine_grind"]))
          k.mesure(`${c}.fine_grind`, v.fine_grind, "%");
      });
      k.facultatif(d, "color", (c, v) => k.mesure(c, v, "EBC"));
      k.facultatif(d, "producer", (c, v) => k.texte(c, v));
      k.facultatif(d, "origin", (c, v) => k.texte(c, v));
    });
  },
  beer_hops(k, d) {
    k.entree(d, ["label_fr", "form", "alpha_acid", "beta_acid", "origin", "purpose"], () => {
      k.facultatif(d, "form", (c, v) => k.valeurDe(c, v, FORMES_HOUBLON));
      k.facultatif(d, "alpha_acid", (c, v) => k.mesure(c, v, "%"));
      k.facultatif(d, "beta_acid", (c, v) => k.mesure(c, v, "%"));
      k.facultatif(d, "origin", (c, v) => k.texte(c, v));
      k.facultatif(d, "purpose", (c, v) => k.valeurDe(c, v, USAGES_HOUBLON));
    });
  },
  beer_cultures(k, d) {
    k.entree(
      d,
      [
        "type",
        "form",
        "producer",
        "product_id",
        "attenuation",
        "temperature_range",
        "flocculation",
      ],
      () => {
        k.facultatif(d, "type", (c, v) => k.valeurDe(c, v, TYPES_LEVURE));
        k.facultatif(d, "form", (c, v) => k.valeurDe(c, v, FORMES_LEVURE));
        k.facultatif(d, "producer", (c, v) => k.texte(c, v));
        k.facultatif(d, "product_id", (c, v) => k.texte(c, v));
        k.facultatif(d, "attenuation", (c, v) => k.plage(c, v, "%"));
        k.facultatif(d, "temperature_range", (c, v) => k.plage(c, v, "C"));
        k.facultatif(d, "flocculation", (c, v) => k.valeurDe(c, v, FLOCULATIONS));
      },
    );
  },
  beer_miscs(k, d) {
    k.entree(d, ["label_fr", "type"], () => {
      k.facultatif(d, "type", (c, v) => k.valeurDe(c, v, TYPES_AJOUT));
    });
  },
  beer_styles(k, d) {
    const plages = {
      original_gravity: "sg",
      final_gravity: "sg",
      international_bitterness_units: "IBUs",
      color: "EBC",
      alcohol_by_volume: "%",
    };
    const textes = ["category", "category_id", "type", "style_guide"];
    const obligatoires = ["name", "style_id", "provenance", "content_sha256"];
    if (!k.cles("data", d, [...obligatoires, ...textes, ...Object.keys(plages)], obligatoires)) {
      return;
    }
    k.texte("name", d.name);
    k.texte("style_id", d.style_id, 10);
    for (const cle of textes) k.facultatif(d, cle, (c, v) => k.texte(c, v));
    k.facultatif(d, "type", (c, v) => k.valeurDe(c, v, TYPES_STYLE));
    for (const [cle, unite] of Object.entries(plages)) {
      k.facultatif(d, cle, (c, v) => k.plage(c, v, unite));
    }
    k.provenance(d.provenance);
    k.empreinte(d);
  },
  beer_index(k, d, id) {
    if (
      !k.cles(
        "data",
        d,
        ["count", "entries", "content_sha256"],
        ["count", "entries", "content_sha256"],
      )
    ) {
      return;
    }
    if (!Array.isArray(d.entries)) {
      k.erreur("entries", "liste attendue");
      return;
    }
    if (d.count !== d.entries.length) k.erreur("count", "différent du nombre d'entrées");
    const forme = ENTREES_INDEX[id];
    d.entries.forEach((e, i) => {
      const c = `entries[${i}]`;
      const permis = ["id", "name", ...Object.keys(forme?.champs ?? {})];
      if (!forme || !k.cles(c, e, permis, ["id", "name", ...(forme.obligatoires ?? [])])) return;
      if (!estIdReferentiel(e.id, [forme.collection])) k.erreur(`${c}.id`, "identifiant mal formé");
      k.texte(`${c}.name`, e.name);
      for (const [cle, type] of Object.entries(forme.champs)) {
        if (!(cle in e)) continue;
        const v = e[cle];
        const ok = Array.isArray(type)
          ? type.includes(v)
          : type === "texte"
            ? estTexte(v, 120)
            : type === "code"
              ? estTexte(v, 10)
              : type === "nombre"
                ? estNombre(v)
                : type === "aliases"
                  ? Array.isArray(v) && v.every((a) => estTexte(a, 120))
                  : Array.isArray(v) && v.length === 2 && v.every(estNombre) && v[0] <= v[1];
        if (!ok) k.erreur(`${c}.${cle}`, "valeur non permise");
      }
    });
    k.empreinte(d);
    const taille = tailleFirestore(`beer_index/${id}`, { ...d, updated_at: 0 });
    if (taille >= TAILLE_MAX_INDEX)
      k.erreur("taille", `${taille} octets, ${TAILLE_MAX_INDEX} au plus`);
  },
  public_recipes(k, d) {
    const obligatoires = [
      "format_version",
      "owner_uid",
      "owner_name",
      "imported_from",
      "search_name",
      "recipe",
      "ingredient_refs",
      "source_hop_timing",
      "announced",
      "provenance",
      "content_sha256",
    ];
    if (!k.cles("data", d, [...obligatoires, "style_id"], obligatoires)) return;
    if (d.format_version !== 1) k.erreur("format_version", "1 attendu");
    if (d.owner_uid !== "system") k.erreur("owner_uid", "« system » attendu");
    k.texte("owner_name", d.owner_name, 80);
    k.texte("imported_from", d.imported_from, 200);
    if (typeof d.search_name !== "string" || !/^[a-z0-9]+( [a-z0-9]+)*$/.test(d.search_name)) {
      k.erreur("search_name", "nom normalisé attendu (minuscules, chiffres, une espace)");
    } else if (d.search_name.length > 120) {
      k.erreur("search_name", "120 caractères au plus");
    }
    k.facultatif(d, "style_id", (c, v) => {
      if (typeof v !== "string" || v.length > 200 || !ID.beer_styles.test(v)) {
        k.erreur(c, "identifiant de beer_styles attendu");
      }
    });
    const r = d.recipe;
    if (k.cles("recipe", r, CLES_RECETTE, ["name", "ingredients"])) {
      k.texte("recipe.name", r.name);
      k.facultatif(r, "author", (c, v) => k.texte(`recipe.${c}`, v));
      k.facultatif(r, "notes", (c, v) => {
        if (typeof v !== "string" || v.length > 10000)
          k.erreur(`recipe.${c}`, "10 000 caractères au plus");
      });
      for (const [liste, max] of Object.entries(PLAFONDS)) {
        const lignes = r.ingredients?.[liste];
        if (lignes !== undefined && (!Array.isArray(lignes) || lignes.length > max)) {
          k.erreur(`recipe.ingredients.${liste}`, `liste de ${max} lignes au plus attendue`);
        }
      }
      if ((r.mash?.mash_steps?.length ?? 0) > 20) k.erreur("recipe.mash.mash_steps", "20 au plus");
      const valide = recetteValide();
      if (!valide(r)) {
        for (const e of valide.errors)
          k.erreur(`recipe${e.instancePath}`, `schéma partiel : ${e.message}`);
      }
    }
    if (!estObjet(d.ingredient_refs)) {
      k.erreur("ingredient_refs", "map attendue");
    } else {
      for (const [cle, id] of Object.entries(d.ingredient_refs)) {
        if (!estTexte(cle, 100) || !estIdReferentiel(id)) {
          k.erreur(`ingredient_refs.${cle}`, "identifiant de référentiel attendu");
        }
      }
    }
    const houblons = r?.ingredients?.hop_additions?.length ?? 0;
    if (!Array.isArray(d.source_hop_timing)) {
      k.erreur("source_hop_timing", "liste attendue");
    } else {
      d.source_hop_timing.forEach((m, i) => {
        const c = `source_hop_timing[${i}]`;
        if (!k.cles(c, m, ["hop_index", "label"], ["hop_index", "label"])) return;
        if (!Number.isInteger(m.hop_index) || m.hop_index < 0 || m.hop_index >= houblons) {
          k.erreur(`${c}.hop_index`, "index d'un houblon attendu");
        }
        k.texte(`${c}.label`, m.label, 40);
      });
    }
    const annonces = {
      original_gravity: "sg",
      final_gravity: "sg",
      alcohol_by_volume: "%",
      ibu_estimate: "IBUs",
      color_estimate: "EBC",
    };
    if (k.cles("announced", d.announced, Object.keys(annonces))) {
      for (const [cle, unite] of Object.entries(annonces)) {
        k.facultatif(d.announced, cle, (c, v) => k.mesure(`announced.${c}`, v, unite));
      }
    }
    k.provenance(d.provenance);
    k.empreinte(d);
  },
  import_unresolved(k, d) {
    const cles = ["nature", "name", "source", "count"];
    if (!k.cles("data", d, cles, cles)) return;
    k.valeurDe("nature", d.nature, NATURES);
    k.texte("name", d.name);
    if (d.source !== "diydog") k.erreur("source", "« diydog » attendu");
    if (!Number.isInteger(d.count) || d.count < 1) k.erreur("count", "entier positif attendu");
  },
};

/// Erreurs du document [doc] (`{id, data}`) de [collection] ; liste vide s'il est bon.
export function controlerDocument(collection, doc) {
  const k = new Controle();
  if (!COLLECTIONS.includes(collection)) {
    k.erreur("collection", `« ${collection} » hors de la liste blanche`);
    return k.erreurs;
  }
  if (!estObjet(doc) || typeof doc.id !== "string") {
    k.erreur("document", "{id, data} attendu");
    return k.erreurs;
  }
  const bonId = collection === "beer_index" ? INDEX.includes(doc.id) : ID[collection].test(doc.id);
  if (!bonId || doc.id.length > 200) k.erreur("id", "identifiant mal formé");
  if (!estObjet(doc.data)) {
    k.erreur("data", "objet attendu");
    return k.erreurs;
  }
  if ("updated_at" in doc.data) k.erreur("data", "updated_at est posé par l'écrivain");
  CONTROLES[collection](k, doc.data, doc.id);
  return k.erreurs;
}
