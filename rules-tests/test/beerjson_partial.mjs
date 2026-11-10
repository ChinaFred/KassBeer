// Schéma BeerJSON partiel (ADR-005, « Trois validations ») : dérivé ici, à chaque
// lancement, des schémas officiels au commit figé 4370892d44 (schemas/, licence MIT).
// Deux différences avec le schéma officiel, et deux seulement :
//   1. les champs obligatoires de la liste fermée d'ADR-005 peuvent manquer ;
//   2. une seule unité par grandeur (g, l, C, min, EBC, %, sg) ; les autres grandeurs
//      n'ont aucune unité permise.
// ajv ne tourne pas dans l'application : la lecture typée de recipe.dart y suffit.

import { readdirSync, readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";

export const SCHEMAS_DIR = new URL("../../schemas/beerjson-4370892d44/", import.meta.url);

const RECIPE_TYPE =
  "https://raw.githubusercontent.com/beerjson/beerjson/main/json/recipe.json#/$defs/RecipeType";

/// Champs obligatoires du schéma dont l'absence est permise en base (ADR-005, tableau
/// « Champ absent permis »). Fichier → définition → champs.
export const ABSENCES_PERMISES = {
  "recipe.json": { RecipeType: ["type", "author", "efficiency", "batch_size"] },
  "boil.json": { BoilProcedureType: ["boil_time"] },
  "mash.json": { MashProcedureType: ["grain_temperature", "mash_steps"] },
  "mash_step.json": { MashStepType: ["type"] },
  "fermentable.json": { FermentableBase: ["yield", "color"] },
  "hop.json": { HopVarietyBase: ["alpha_acid"] },
  "culture.json": { CultureBase: ["type", "form"], CultureAdditionType: ["amount"] },
  "misc.json": { MiscellaneousBase: ["type"] },
  "style.json": { StyleBase: ["category", "style_guide", "type"] },
};

/// Unité canonique de chaque type d'unité de measureable_units.json.
export const UNITES_CANONIQUES = {
  MassUnitType: "g",
  VolumeUnitType: "l",
  TemperatureUnitType: "C",
  TimeUnitType: "min",
  ColorUnitType: "EBC",
  PercentUnitType: "%",
  GravityUnitType: "sg",
};

/// Schémas officiels, par nom de fichier.
export function officialSchemas() {
  const schemas = {};
  for (const file of readdirSync(SCHEMAS_DIR)) {
    if (file.endsWith(".json")) {
      schemas[file] = JSON.parse(readFileSync(new URL(file, SCHEMAS_DIR), "utf8"));
    }
  }
  return schemas;
}

function withoutRequired(definition, names, where) {
  let removed = 0;
  const strip = (node) => {
    if (Array.isArray(node.required)) {
      const before = node.required.length;
      node.required = node.required.filter((name) => !names.includes(name));
      removed += before - node.required.length;
    }
    for (const part of node.allOf ?? []) strip(part);
  };
  strip(definition);
  // Un champ de la liste absent du schéma veut dire que le schéma a changé : la liste
  // d'ADR-005 se relit avant de continuer.
  if (removed !== names.length) {
    throw new Error(`${where} : ${names.length} champs attendus, ${removed} retirés`);
  }
}

/// Schémas partiels, par nom de fichier.
export function partialSchemas() {
  const schemas = structuredClone(officialSchemas());
  for (const [file, definitions] of Object.entries(ABSENCES_PERMISES)) {
    for (const [name, fields] of Object.entries(definitions)) {
      withoutRequired(schemas[file].$defs[name], fields, `${file}#${name}`);
    }
  }
  const units = schemas["measureable_units.json"].$defs;
  for (const name of Object.keys(units)) {
    if (!name.endsWith("UnitType")) continue;
    const canonical = UNITES_CANONIQUES[name];
    if (canonical === undefined) {
      units[name] = false;
    } else if (!units[name].enum?.includes(canonical)) {
      throw new Error(`${name} : unité ${canonical} absente du schéma`);
    } else {
      units[name] = { ...units[name], enum: [canonical] };
    }
  }
  return schemas;
}

/// Validateur de `RecipeType` sur [schemas].
export function recipeValidator(schemas) {
  const ajv = new Ajv2020({ allErrors: true });
  for (const schema of Object.values(schemas)) ajv.addSchema(schema);
  return ajv.compile({ $ref: RECIPE_TYPE });
}
