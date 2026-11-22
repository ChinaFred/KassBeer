// Génération des descriptions aromatiques des houblons (ADR-013) et des levures (ADR-017),
// lancée par generer-aromes.mjs sur le poste de l'admin. Moteur commun aux deux natures
// (--nature hop|culture, hop par défaut) ; ce qui dépend de la nature vit dans natures/.
// Lit import/ingest/prepare/ et import/ingest/aromes/ ; n'importe pas firebase-admin, ne lit
// ni n'écrit Firestore. Seul accès réseau : l'API Messages d'Anthropic, par client.mjs (P54).
//
// Fichiers de import/ingest/aromes/ (jamais versionnés), houblons à la racine, levures dans
// levures/ :
//   tarif.json               écrit par l'admin : modèle, date, source, prix par million de
//                            jetons ; commun aux deux natures, à la racine seulement
//   aromes.json              entrées {id, data}, copie de référence, corrigée à la main
//   houblons-recettes.json   houblons des recettes du groupe ; levures-recettes.json dans
//                            levures/ (exchange/bin/lister_ingredients_recettes.dart)
//   lot-<id>.json            table custom_id → élément d'un lot de l'API Batches
//   brut/                    réponses de chaque exécution, effort dans le nom
//   rapport.json             dernière exécution : poste, modèle, effort, jetons, montant
//   a-relire.md              éléments du groupe à relire

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { creerAccesApi, erreurLisible } from "./client.mjs";
import { NATURE_LEVURE } from "./natures/culture.mjs";
import { NATURE_HOUBLON } from "./natures/hop.mjs";
import { MAX_TOKENS, MODELE } from "./prompt.mjs";
import { borneHaute, ErreurAromes, lireTarif, montantUsage } from "./tarif.mjs";
import { EFFORTS, LICENCE_PROVENANCE, SOURCE_PROVENANCE } from "./validation.mjs";

/// Natures acceptées par --nature.
export const NATURES = { hop: NATURE_HOUBLON, culture: NATURE_LEVURE };

/// Dossiers par défaut, à la racine du dépôt.
export const DOSSIER_PREPARE = fileURLToPath(
  new URL("../../../import/ingest/prepare/", import.meta.url),
);
export const DOSSIER_AROMES = fileURLToPath(
  new URL("../../../import/ingest/aromes/", import.meta.url),
);

/// Éléments envoyés en appels directs, au plus (essai, --nouveaux sans --lot).
export const SEUIL_DIRECT = 20;

/// Éléments d'un essai par défaut (ADR-013, décision 5 ; ADR-017, décision 6).
export const ESSAI_DEFAUT = 10;

export const EFFORT_DEFAUT = "medium";

const ID_LOT = /^[A-Za-z0-9_-]{1,128}$/;

const AIDE = `Usage (dans ingest/) :
  node generer-aromes.mjs --essai [n] [--seulement <liste.json>] [--effort <e>] [--budget-usd <$>]
  node generer-aromes.mjs --lot --budget-usd <$> [--seulement <liste.json>] [--nouveaux] [--tout] [--max <n>] [--effort <e>]
  node generer-aromes.mjs --nouveaux --budget-usd <$> [--effort <e>]          (${SEUIL_DIRECT} au plus, appels directs)
  node generer-aromes.mjs --lot|--essai --regenerer <id> [--regenerer <id>…] --budget-usd <$>
  node generer-aromes.mjs --suivre <id du lot>
  node generer-aromes.mjs --relire                                            (réécrit a-relire.md, aucun appel)
Options communes : --nature hop|culture (hop par défaut), --dossier <prepare>, --aromes <dossier>.
Effort : ${EFFORTS.join(", ")}.`;

/// Lit [argv] (sans `node` ni le script). Lève ErreurAromes.
export function lireOptionsAromes(argv) {
  const o = {
    nature: "hop",
    essai: null,
    lot: false,
    nouveaux: false,
    suivre: null,
    relire: false,
    seulement: null,
    budget: null,
    max: null,
    effort: EFFORT_DEFAUT,
    regenerer: [],
    tout: false,
    dossier: null,
    aromes: null,
  };
  const valeur = (i, nom) => {
    const v = argv[i];
    if (v === undefined || v.startsWith("--")) {
      throw new ErreurAromes(`${nom} demande une valeur.\n${AIDE}`);
    }
    return v;
  };
  for (let i = 0; i < argv.length; i++) {
    const nom = argv[i];
    switch (nom) {
      case "--essai": {
        o.essai = ESSAI_DEFAUT;
        if (/^[0-9]+$/.test(argv[i + 1] ?? "")) o.essai = Number(argv[++i]);
        if (!Number.isInteger(o.essai) || o.essai < 1 || o.essai > SEUIL_DIRECT) {
          throw new ErreurAromes(`--essai : de 1 à ${SEUIL_DIRECT} éléments.`);
        }
        break;
      }
      case "--lot":
        o.lot = true;
        break;
      case "--nouveaux":
        o.nouveaux = true;
        break;
      case "--relire":
        o.relire = true;
        break;
      case "--tout":
        o.tout = true;
        break;
      case "--suivre":
        o.suivre = valeur(++i, nom);
        if (!ID_LOT.test(o.suivre))
          throw new ErreurAromes("--suivre : identifiant de lot mal formé.");
        break;
      case "--nature":
        o.nature = valeur(++i, nom);
        if (!(o.nature in NATURES)) {
          throw new ErreurAromes(`--nature : ${Object.keys(NATURES).join(" ou ")}.`);
        }
        break;
      case "--seulement":
      case "--dossier":
      case "--aromes":
        o[nom.slice(2)] = valeur(++i, nom);
        break;
      case "--budget-usd": {
        const v = Number(valeur(++i, nom));
        if (!Number.isFinite(v) || v <= 0)
          throw new ErreurAromes("--budget-usd : montant positif attendu.");
        o.budget = v;
        break;
      }
      case "--max": {
        const v = Number(valeur(++i, nom));
        if (!Number.isInteger(v) || v < 1) {
          throw new ErreurAromes("--max : entier positif attendu.");
        }
        o.max = v;
        break;
      }
      case "--effort":
        o.effort = valeur(++i, nom);
        if (!EFFORTS.includes(o.effort)) {
          throw new ErreurAromes(`--effort : ${EFFORTS.join(", ")}.`);
        }
        break;
      case "--regenerer":
        o.regenerer.push(valeur(++i, nom));
        break;
      default:
        throw new ErreurAromes(`Option inconnue : ${nom}\n${AIDE}`);
    }
  }
  const nature = NATURES[o.nature];
  // Plafond par lancement propre à la nature (houblons 500, levures 1 000), contrôlé une
  // fois --nature lu, quel que soit l'ordre des options.
  if (o.max === null) o.max = nature.maxElements;
  else if (o.max > nature.maxElements) {
    throw new ErreurAromes(`--max : entier de 1 à ${nature.maxElements} pour ${nature.mots.des}.`);
  }
  for (const id of o.regenerer) {
    if (!nature.motifId.test(id) || id.length > 200) {
      throw new ErreurAromes(
        `--regenerer : identifiant ${nature.mots.de} attendu (${nature.prefixeId}).`,
      );
    }
  }
  const modes = [o.essai !== null, o.lot, o.suivre !== null, o.relire].filter(Boolean).length;
  if (modes > 1 || (modes === 0 && !o.nouveaux)) {
    throw new ErreurAromes(
      `Choisissez un seul de --essai, --lot, --nouveaux, --suivre, --relire.\n${AIDE}`,
    );
  }
  if ((o.suivre !== null || o.relire) && (o.nouveaux || o.tout || o.regenerer.length > 0)) {
    throw new ErreurAromes("--suivre et --relire ne prennent aucune option de sélection.");
  }
  if (o.essai !== null && o.nouveaux) {
    throw new ErreurAromes("--essai et --nouveaux : choisissez l'un des deux.");
  }
  if (o.tout && (o.nouveaux || o.regenerer.length > 0)) {
    throw new ErreurAromes("--tout ne se combine ni avec --nouveaux ni avec --regenerer.");
  }
  let mode = "nouveaux";
  if (o.essai !== null) mode = "essai";
  else if (o.lot) mode = "lot";
  else if (o.suivre !== null) mode = "suivre";
  else if (o.relire) mode = "relire";
  if ((mode === "lot" || mode === "nouveaux") && o.budget === null) {
    throw new ErreurAromes("--budget-usd est obligatoire hors essai (ADR-013, plafond 2).");
  }
  return { ...o, mode, nature };
}

/// Lit un fichier JSON ; un fichier absent rend [absent].
function lireJson(chemin, absent) {
  if (!existsSync(chemin)) return absent;
  return JSON.parse(readFileSync(chemin, "utf8"));
}

/// Éléments du fichier préparé de [nature] (beer_hops.json, beer_cultures.json) : Map id →
/// data.
export function lireReferentiel(dossierPrepare, nature) {
  const nom = nature.referentiel;
  const liste = JSON.parse(readFileSync(join(dossierPrepare, nom), "utf8"));
  if (!Array.isArray(liste)) throw new Error(`${nom} : liste attendue`);
  return new Map(liste.map((d) => [d.id, d.data]));
}

/// Entrées de aromes.json : Map id → data (vide si le fichier manque).
export function lireAromes(dossierAromes) {
  const liste = lireJson(join(dossierAromes, "aromes.json"), []);
  if (!Array.isArray(liste)) throw new Error("aromes.json : liste attendue");
  return new Map(liste.map((d) => [d.id, d.data]));
}

/// Écrit aromes.json, entrées triées par identifiant, par un fichier temporaire renommé.
export function ecrireAromes(dossierAromes, aromes) {
  const liste = [...aromes.keys()].sort().map((id) => ({ id, data: aromes.get(id) }));
  const chemin = join(dossierAromes, "aromes.json");
  writeFileSync(`${chemin}.tmp`, `${JSON.stringify(liste, null, 2)}\n`);
  renameSync(`${chemin}.tmp`, chemin);
}

/// Identifiants résolus d'un fichier houblons-recettes.json ou levures-recettes.json
/// (exchange/bin/lister_ingredients_recettes.dart) de [nature], ou null s'il manque.
export function lireGroupe(chemin, nature) {
  const f = lireJson(chemin, null);
  if (f === null) return null;
  if (f?.format !== nature.formatGroupe || !Array.isArray(f.resolus)) {
    throw new ErreurAromes(`${chemin} : fichier de ${nature.scriptGroupe} attendu.`);
  }
  return {
    ids: f.resolus.map((r) => r.id),
    nonResolus: Array.isArray(f.non_resolus) ? f.non_resolus : [],
  };
}

/// Périmètre de [nature] sur [elements] (Map id → data) : les éléments du groupe
/// ([groupeIds]) toujours, les autres si leur type est dans le périmètre (ADR-017,
/// décision 1). Rend `{ids, hors}` : identifiants triés retenus, et ceux écartés.
export function perimetre(elements, groupeIds, nature) {
  const ids = [];
  const hors = [];
  for (const id of [...elements.keys()].sort()) {
    if (groupeIds.has(id) || nature.dansPerimetre(elements.get(id))) ids.push(id);
    else hors.push(id);
  }
  return { ids, hors };
}

/// Sélection d'un lancement. Rend `{envoi: [{id, donnees, empreinte, categorie, relue}],
/// nouveaux, changes, inchanges, relues: [{id, raison}]}` ; `categorie` : `nouveau`,
/// `change` ou `force`.
export function selectionner({ elements, aromes, options, base, contexte }) {
  const forces = new Set(options.regenerer);
  const envoi = [];
  const relues = [];
  let nouveaux = 0;
  let changes = 0;
  let inchanges = 0;
  for (const id of base) {
    const data = elements.get(id);
    const donnees = options.nature.donneesEnvoyees(data);
    const empreinte = options.nature.empreinte(donnees, { effort: options.effort, contexte });
    const existante = aromes.get(id);
    const relue = existante?.reviewed === true;
    const categorie =
      existante === undefined
        ? "nouveau"
        : existante.input_sha256 === empreinte
          ? "inchange"
          : "change";
    if (categorie === "nouveau") nouveaux++;
    else if (categorie === "change") changes++;
    else inchanges++;
    const force = options.tout || forces.has(id);
    if (options.nouveaux && categorie !== "nouveau" && !force) continue;
    if (relue && !force) {
      if (categorie === "change") relues.push({ id, raison: "relue, entrées changées" });
      continue;
    }
    if (categorie === "inchange" && !force) continue;
    envoi.push({
      id,
      nom: data.name,
      donnees,
      empreinte,
      categorie: force ? "force" : categorie,
      relue,
    });
  }
  return { envoi, nouveaux, changes, inchanges, relues };
}

/// Ligne de provenance d'une entrée générée.
function provenance(id, effort, date, promptVersion) {
  return [
    {
      source: SOURCE_PROVENANCE,
      source_id: id,
      version: `${MODELE} / prompt ${promptVersion} / effort ${effort}`,
      licence: LICENCE_PROVENANCE,
      retrieved: date,
    },
  ];
}

/// Lecture d'une réponse de l'API pour l'élément [cible] (`{id, nom, empreinte}`) de
/// [nature]. Rend `{etat: 'ok', data}`, `{etat: 'erreur', raison}` (refusal, max_tokens,
/// JSON illisible) ou `{etat: 'refus', regles}` (contrôle). Aucun texte dans `raison` ni
/// `regles`.
export function lireReponse(message, cible, { effort, date, nature, contexte }) {
  if (message?.stop_reason === "refusal") return { etat: "erreur", raison: "refusal" };
  if (message?.stop_reason === "max_tokens") return { etat: "erreur", raison: "max_tokens" };
  if (message?.stop_reason !== "end_turn") {
    return { etat: "erreur", raison: `stop_reason ${String(message?.stop_reason).slice(0, 40)}` };
  }
  const texte = (message.content ?? [])
    .filter((b) => b?.type === "text")
    .map((b) => b.text)
    .join("");
  let sortie;
  try {
    sortie = JSON.parse(texte);
  } catch (erreur) {
    return { etat: "erreur", raison: `json_illisible (${erreur.name})` };
  }
  const { regles, resultat } = nature.controlerSortie(sortie, contexte);
  if (regles.length > 0) return { etat: "refus", regles, sortie };
  const data = {
    [nature.champNom]: cible.nom,
    ...resultat,
    reviewed: false,
    provenance: provenance(cible.id, effort, date, nature.promptVersion),
    input_sha256: cible.empreinte,
  };
  const erreurs = nature.controlerEntree({ id: cible.id, data }, contexte);
  if (erreurs.length > 0) return { etat: "refus", regles: erreurs, sortie };
  return { etat: "ok", data, sortie };
}

const usageVide = () => ({
  input_tokens: 0,
  cache_creation_input_tokens: 0,
  cache_read_input_tokens: 0,
  output_tokens: 0,
  thinking_tokens: 0,
});

function cumuler(total, usage) {
  if (!usage) return;
  total.input_tokens += usage.input_tokens ?? 0;
  total.cache_creation_input_tokens += usage.cache_creation_input_tokens ?? 0;
  total.cache_read_input_tokens += usage.cache_read_input_tokens ?? 0;
  total.output_tokens += usage.output_tokens ?? 0;
  total.thinking_tokens += usage.output_tokens_details?.thinking_tokens ?? 0;
}

/// Identifiant d'une exécution : horodatage ISO compact en UTC.
const idExecution = (date) =>
  date
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");

/// Applique un résultat lu à [aromes] et au compte rendu [cr]. Une entrée relue n'est
/// jamais remplacée : la réponse reste dans brut/ et le rapport la signale.
function appliquer(lu, cible, aromes, cr) {
  if (lu.etat === "erreur") {
    cr.erreurs.push({ id: cible.id, raison: lu.raison });
  } else if (lu.etat === "refus") {
    cr.refus.push({ id: cible.id, regles: lu.regles });
  } else if (aromes.get(cible.id)?.reviewed === true) {
    cr.relues.push({ id: cible.id, raison: "relue, non remplacée" });
  } else {
    aromes.set(cible.id, lu.data);
    cr.generes++;
  }
}

/// Saisie de `oui` sur un terminal ; refus sans terminal.
export async function confirmerTerminal(question, entree, sortie) {
  if (!entree.isTTY || !sortie.isTTY) {
    throw new ErreurAromes("Aucun terminal : la confirmation est impossible, rien n'est envoyé.");
  }
  const { createInterface } = await import("node:readline/promises");
  const rl = createInterface({ input: entree, output: sortie });
  try {
    return (await rl.question(`${question} Saisissez « oui » pour envoyer : `)).trim() === "oui";
  } finally {
    rl.close();
  }
}

/// Écrit a-relire.md : un élément du groupe par section, données d'entrée et texte.
export function ecrireARelire(dossierAromes, elements, aromes, groupe, nature) {
  const ids = [...new Set(groupe.ids)].sort();
  const lignes = [
    "# Descriptions aromatiques à relire",
    "",
    `${nature.mots.Des} des recettes du groupe (${nature.fichierGroupe}). Corrigez aromes.json, puis posez`,
    '`reviewed: true` et `reviewed_at: "AAAA-MM-JJ"` sur chaque entrée relue.',
    "",
  ];
  let aRelire = 0;
  for (const id of ids) {
    const h = elements.get(id);
    const a = aromes.get(id);
    lignes.push(`## ${h?.name ?? id} (\`${id}\`)`, "");
    if (h === undefined) {
      lignes.push(`Absent de ${nature.referentiel}.`, "");
      continue;
    }
    lignes.push(nature.ligneDonnees(h));
    if (a === undefined) {
      lignes.push("- Aucune entrée : lancez la génération.", "");
      continue;
    }
    if (a.reviewed !== true) aRelire++;
    lignes.push(
      `- État : ${a.reviewed === true ? `relu le ${a.reviewed_at}` : "à relire"} ; statut ${a.status}` +
        (a.confidence ? ` ; confiance ${a.confidence}` : ""),
    );
    if (Array.isArray(a.descriptors) && a.descriptors.length > 0) {
      lignes.push(`- Descripteurs : ${a.descriptors.map((x) => x.label).join(", ")}`);
    }
    lignes.push(...nature.lignesTextes(a));
    lignes.push("");
  }
  if (groupe.nonResolus.length > 0) {
    lignes.push("## Noms non résolus", "");
    for (const n of groupe.nonResolus) {
      const candidats = Array.isArray(n.candidats) && n.candidats.length > 0;
      lignes.push(`- ${n.nom} : ${n.raison}${candidats ? ` (${n.candidats.join(", ")})` : ""}`);
    }
    lignes.push("");
  }
  writeFileSync(join(dossierAromes, "a-relire.md"), lignes.join("\n"));
  return { [nature.mots.des]: ids.length, aRelire };
}

/// Exécute generer-aromes.mjs. Rend le rapport de l'exécution. [chargerSdk] et
/// [confirmer] sont remplacés dans les tests. Lève ErreurAromes pour une utilisation
/// refusée.
export async function genererAromes({
  argv,
  env,
  entree,
  sortie,
  maintenant = () => new Date(),
  chargerSdk,
  confirmer = confirmerTerminal,
  ecrire = (t) => sortie.write(`${t}\n`),
}) {
  const debut = maintenant();
  const options = lireOptionsAromes(argv);
  const nature = options.nature;
  const poste = nature.poste;
  const dossierPrepare = resolve(options.dossier ?? DOSSIER_PREPARE);
  const dossierBase = resolve(options.aromes ?? DOSSIER_AROMES);
  // Tarif commun à la racine ; fichiers de la nature dans son sous-dossier (levures/).
  const dossierAromes =
    nature.sousDossier === null ? dossierBase : join(dossierBase, nature.sousDossier);
  mkdirSync(dossierAromes, { recursive: true });
  const elements = lireReferentiel(dossierPrepare, nature);
  const aromes = lireAromes(dossierAromes);
  const groupe = lireGroupe(join(dossierAromes, nature.fichierGroupe), nature);
  const runId = idExecution(debut);
  const date = debut.toISOString().slice(0, 10);
  const relire = () => {
    if (groupe === null) {
      ecrire(`${nature.fichierGroupe} absent : a-relire.md n'est pas écrit.`);
      return null;
    }
    return ecrireARelire(dossierAromes, elements, aromes, groupe, nature);
  };

  if (options.mode === "relire") {
    const r = relire();
    if (r !== null) {
      ecrire(
        `a-relire.md : ${r[nature.mots.des]} ${nature.mots.des} du groupe, ${r.aRelire} à relire.`,
      );
    }
    return { poste, mode: "relire", a_relire: r };
  }
  const contexte = nature.contexte(dossierPrepare);
  if (contexte.refuses?.length > 0) {
    ecrire(
      `beer_styles.json : ${contexte.refuses.length} styles refusés au contrôle, absents de ` +
        `la liste du prompt : ${contexte.refuses.slice(0, 20).join(", ")}.`,
    );
  }
  const api = creerAccesApi({ env, chargerSdk });
  if (options.mode === "suivre") {
    return suivre({
      options,
      dossierBase,
      dossierAromes,
      aromes,
      api,
      debut,
      runId,
      ecrire,
      relire,
      contexte,
    });
  }

  // Sélection, sans réseau. Périmètre de la nature : éléments du groupe, plus ceux dont le
  // type est retenu ; un élément nommé hors du périmètre est refusé.
  const groupeIds = new Set(groupe?.ids ?? []);
  const { ids: dansLePerimetre, hors } = perimetre(elements, groupeIds, nature);
  let base;
  if (options.regenerer.length > 0) base = options.regenerer;
  else if (options.seulement !== null) {
    const f = lireGroupe(resolve(options.seulement), nature);
    if (f === null) throw new ErreurAromes(`${options.seulement} : fichier absent.`);
    base = f.ids;
  } else base = dansLePerimetre;
  const inconnus = base.filter((id) => !elements.has(id));
  if (inconnus.length > 0) {
    throw new ErreurAromes(
      `${nature.mots.Des} absents de ${nature.referentiel} : ${inconnus.slice(0, 20).join(", ")}.`,
    );
  }
  const horsNommes = base.filter((id) => hors.includes(id));
  if (horsNommes.length > 0) {
    throw new ErreurAromes(
      `${nature.mots.Des} hors du périmètre (types ${nature.typesExclus.join(", ")}, hors du ` +
        `groupe) : ${horsNommes.slice(0, 20).join(", ")}. Rien n'est envoyé.`,
    );
  }
  base = [...new Set(base)];
  const s = selectionner({ elements, aromes, options, base, contexte });
  let envoi = s.envoi;
  if (options.mode === "essai") envoi = envoi.slice(0, options.essai);
  const direct = options.mode !== "lot";
  if (nature.typesExclus !== null) {
    ecrire(
      `Périmètre : ${dansLePerimetre.length} ${nature.mots.des} sur ${elements.size}, ` +
        `${hors.length} hors périmètre (types ${nature.typesExclus.join(", ")}).`,
    );
  }
  ecrire(
    `${nature.mots.Des} : ${s.nouveaux} nouveaux, ${s.changes} changés, ${s.inchanges} inchangés` +
      (options.tout ? " (--tout : tous renvoyés)" : "") +
      ` ; ${envoi.length} à envoyer.`,
  );
  for (const r of s.relues)
    ecrire(`  ${r.id} : ${r.raison} (--regenerer ${r.id} pour la renvoyer)`);
  const cr = {
    poste,
    run_id: runId,
    mode: options.mode,
    model: MODELE,
    effort: options.effort,
    prompt_version: nature.promptVersion,
    counts: { nouveaux: s.nouveaux, changes: s.changes, inchanges: s.inchanges, envoyes: 0 },
    generes: 0,
    erreurs: [],
    refus: [],
    relues: [...s.relues],
    non_envoyes: [],
    appels_au_resultat_inconnu: 0,
    montant_incomplet: false,
  };
  if (nature.typesExclus !== null) {
    cr.perimetre = {
      retenus: dansLePerimetre.length,
      hors: hors.length,
      types_exclus: nature.typesExclus,
    };
  }
  if (envoi.length === 0) {
    ecrire("Rien à envoyer.");
    return terminer(cr, { dossierAromes, aromes, relire, ecrire, ecrireAromesFichier: false });
  }
  if (envoi.length > options.max) {
    throw new ErreurAromes(
      `${envoi.length} ${nature.mots.des} à envoyer, --max ${options.max} au plus.`,
    );
  }
  if (direct && envoi.length > SEUIL_DIRECT) {
    throw new ErreurAromes(
      `${envoi.length} ${nature.mots.des} : au-delà de ${SEUIL_DIRECT}, passez par un lot (--lot).`,
    );
  }

  // Tarif d'abord : sans lui, aucune estimation et aucun appel.
  const tarif = lireTarif(join(dossierBase, "tarif.json"), MODELE, debut);
  const requetes = envoi.map((c) =>
    nature.requete(c.donnees, { effort: options.effort, cache: direct, contexte }),
  );
  const jetons = [];
  for (const p of requetes) jetons.push(await api.compterJetons(p));
  const borne = borneHaute(jetons, {
    tarif,
    mode: direct ? "direct" : "lot",
    maxTokens: MAX_TOKENS,
    budget: options.budget,
  });
  const totalJetons = jetons.reduce((a, b) => a + b, 0);
  cr.estimation = {
    [nature.mots.des]: envoi.length,
    mode: direct ? "direct" : "lot",
    jetons_entree: totalJetons,
    max_tokens: MAX_TOKENS,
    borne_haute_usd: borne.montant,
    budget_usd: options.budget,
    tarif: { date: tarif.date, source: tarif.source },
  };
  ecrire(
    `Envoi : ${envoi.length} ${nature.mots.des}, ${direct ? "appels directs" : "lot de l'API Batches (− 50 %, 24 h au plus)"}, ` +
      `modèle ${MODELE}, effort ${options.effort}, ${totalJetons} jetons d'entrée, ` +
      `borne haute ${borne.montant.toFixed(2)} $ (tarif du ${tarif.date}).`,
  );
  if (options.budget !== null && borne.montant > options.budget) {
    throw new ErreurAromes(
      `Borne haute ${borne.montant.toFixed(2)} $ au-delà du budget ${options.budget} $ : ` +
        `${borne.tiennent} ${nature.mots.des} tiendraient. Rien n'est envoyé.`,
    );
  }
  if (!(await confirmer(`Poste ${poste}.`, entree, sortie))) {
    throw new ErreurAromes("Envoi non confirmé : rien n'est envoyé.");
  }

  if (!direct) {
    return creerLotAromes({ envoi, requetes, options, dossierAromes, cr, api, debut, ecrire });
  }

  const brut = [];
  const usage = usageVide();
  const cheminBrut = join(dossierAromes, "brut", `${options.mode}-${runId}-${options.effort}.json`);
  mkdirSync(join(dossierAromes, "brut"), { recursive: true });
  try {
    for (let i = 0; i < envoi.length; i++) {
      const cible = envoi[i];
      let message;
      try {
        message = await api.creerMessage(requetes[i]);
      } catch (erreur) {
        // Aucun envoi rejoué : l'erreur est notée, les éléments restants ne partent pas.
        const raison = erreurLisible(erreur, api.cle());
        cr.erreurs.push({ id: cible.id, raison: `api : ${raison}` });
        cr.non_envoyes = envoi.slice(i + 1).map((c) => c.id);
        ecrire(
          `Appel en échec pour ${cible.id} : ${raison}. Les ${cr.non_envoyes.length} suivants ne partent pas.`,
        );
        if (!aRecuUneReponse(erreur)) {
          // Coupure ou délai sans réponse : la requête a pu être traitée et facturée.
          cr.appels_au_resultat_inconnu++;
          cr.montant_incomplet = true;
          ecrire(
            `Résultat inconnu pour ${cible.id} : l'appel a pu être facturé sans que la réponse ` +
              "arrive. Le montant affiché est incomplet ; vérifiez l'usage dans la Console Anthropic.",
          );
        }
        break;
      }
      cr.counts.envoyes++;
      cumuler(usage, message.usage);
      const lu = lireReponse(message, cible, { effort: options.effort, date, nature, contexte });
      brut.push({
        id: cible.id,
        stop_reason: message.stop_reason,
        usage: message.usage,
        sortie: lu.sortie ?? null,
      });
      appliquer(lu, cible, aromes, cr);
      // Réponses gardées au fil de l'eau : un essai coupé ne renvoie que les manquants.
      writeFileSync(cheminBrut, `${JSON.stringify(brut, null, 2)}\n`);
      if (lu.etat === "ok" && aromes.get(cible.id) === lu.data) ecrireAromes(dossierAromes, aromes);
    }
  } finally {
    cr.usage = usage;
    cr.montant_usd = montantUsage(usage, tarif, "direct");
    cr.brut = cheminBrut;
  }
  return terminer(cr, { dossierAromes, aromes, relire, ecrire, ecrireAromesFichier: true });
}

/// Vrai si [erreur] porte un statut HTTP : l'API a répondu, la requête n'a pas abouti. Faux
/// pour une coupure ou un délai (APIConnectionError, APIConnectionTimeoutError), où la
/// requête a pu être traitée.
const aRecuUneReponse = (erreur) => typeof erreur?.status === "number";

/// Crée le lot : table custom_id écrite avant l'envoi, puis lot-<id>.json.
async function creerLotAromes({ envoi, requetes, options, dossierAromes, cr, api, debut, ecrire }) {
  const nature = options.nature;
  const table = {};
  const demandes = envoi.map((c, i) => {
    const customId = `${nature.prefixeLot}${String(i + 1).padStart(4, "0")}`;
    table[customId] = { id: c.id, [nature.champNom]: c.nom, input_sha256: c.empreinte };
    return { custom_id: customId, params: requetes[i] };
  });
  const lot = {
    nature: nature.cle,
    created_at: debut.toISOString(),
    retrieved: debut.toISOString().slice(0, 10),
    model: MODELE,
    effort: options.effort,
    prompt_version: nature.promptVersion,
    estimation: cr.estimation,
    table,
  };
  const attente = join(dossierAromes, `lot-attente-${cr.run_id}.json`);
  writeFileSync(attente, `${JSON.stringify(lot, null, 2)}\n`);
  let cree;
  try {
    cree = await api.creerLot(demandes);
  } catch (erreur) {
    const raison = erreurLisible(erreur, api.cle());
    if (aRecuUneReponse(erreur)) {
      // L'API a répondu par une erreur : aucun lot n'a été créé. La table est gardée, marquée.
      renameSync(attente, join(dossierAromes, `lot-attente-${cr.run_id}.refuse.json`));
      throw new ErreurAromes(`Lot refusé : ${raison}. Rien n'est parti.`);
    }
    // Coupure ou délai sans réponse : le lot a pu être créé. La table reste sur le poste.
    throw new ErreurAromes(
      `Lot au résultat inconnu : ${raison}. Résultat inconnu : vérifiez les lots dans la ` +
        "Console Anthropic avant de relancer. Table des requêtes gardée dans " +
        `${attente} (${nature.prefixeLot}0001 → ${nature.mots.un}).`,
    );
  }
  if (!ID_LOT.test(cree?.id ?? ""))
    throw new Error("Identifiant de lot illisible dans la réponse.");
  writeFileSync(
    join(dossierAromes, `lot-${cree.id}.json`),
    `${JSON.stringify({ batch_id: cree.id, ...lot }, null, 2)}\n`,
  );
  renameSync(attente, join(dossierAromes, `lot-attente-${cr.run_id}.envoye.json`));
  cr.batch_id = cree.id;
  cr.counts.envoyes = envoi.length;
  ecrire(`Lot ${cree.id} parti. Suivi : node generer-aromes.mjs --suivre ${cree.id}`);
  writeFileSync(join(dossierAromes, "rapport.json"), `${JSON.stringify(cr, null, 2)}\n`);
  return cr;
}

/// --suivre : état d'un lot ; terminé, résultats contrôlés et fusionnés dans aromes.json.
async function suivre({
  options,
  dossierBase,
  dossierAromes,
  aromes,
  api,
  debut,
  runId,
  ecrire,
  relire,
  contexte,
}) {
  const nature = options.nature;
  const poste = nature.poste;
  const cheminLot = join(dossierAromes, `lot-${options.suivre}.json`);
  if (!existsSync(cheminLot)) {
    throw new ErreurAromes(`lot-${options.suivre}.json absent : lot inconnu de ce poste.`);
  }
  const lot = JSON.parse(readFileSync(cheminLot, "utf8"));
  // Un lot d'avant ADR-017 ne porte pas sa nature : c'est un lot de houblons.
  if ((lot.nature ?? "hop") !== nature.cle) {
    throw new ErreurAromes(
      `lot-${options.suivre}.json : lot de nature ${lot.nature ?? "hop"}, ` +
        `--nature ${nature.cle} demandée.`,
    );
  }
  const etat = await api.lireLot(options.suivre);
  const c = etat.request_counts ?? {};
  ecrire(
    `Lot ${options.suivre} : ${etat.processing_status} ; ${c.processing ?? 0} en cours, ` +
      `${c.succeeded ?? 0} réussis, ${c.errored ?? 0} en erreur, ${c.canceled ?? 0} annulés, ` +
      `${c.expired ?? 0} expirés.`,
  );
  if (etat.processing_status !== "ended") {
    return {
      poste,
      mode: "suivre",
      batch_id: options.suivre,
      processing_status: etat.processing_status,
      request_counts: c,
    };
  }
  const cr = {
    poste,
    run_id: runId,
    mode: "suivre",
    batch_id: options.suivre,
    model: lot.model,
    effort: lot.effort,
    prompt_version: lot.prompt_version,
    counts: { envoyes: Object.keys(lot.table).length },
    generes: 0,
    erreurs: [],
    refus: [],
    relues: [],
    a_relancer: [],
  };
  const usage = usageVide();
  const vus = new Set();
  const brut = [];
  for (const r of await api.resultatsLot(options.suivre)) {
    const cible0 = lot.table[r?.custom_id];
    if (cible0 === undefined || vus.has(r.custom_id)) continue;
    vus.add(r.custom_id);
    const cible = {
      id: cible0.id,
      nom: cible0[nature.champNom],
      empreinte: cible0.input_sha256,
    };
    if (r.result?.type !== "succeeded") {
      cr.a_relancer.push({
        id: cible.id,
        raison: String(r.result?.type ?? "inconnu").slice(0, 40),
      });
      continue;
    }
    cumuler(usage, r.result.message.usage);
    const lu = lireReponse(r.result.message, cible, {
      effort: lot.effort,
      date: lot.retrieved,
      nature,
      contexte,
    });
    brut.push({
      id: cible.id,
      custom_id: r.custom_id,
      stop_reason: r.result.message.stop_reason,
      usage: r.result.message.usage,
      sortie: lu.sortie ?? null,
    });
    appliquer(lu, cible, aromes, cr);
  }
  for (const [customId, cible] of Object.entries(lot.table)) {
    if (!vus.has(customId)) cr.a_relancer.push({ id: cible.id, raison: "sans résultat" });
  }
  mkdirSync(join(dossierAromes, "brut"), { recursive: true });
  cr.brut = join(dossierAromes, "brut", `lot-${options.suivre}-${lot.effort}.json`);
  writeFileSync(cr.brut, `${JSON.stringify(brut, null, 2)}\n`);
  cr.usage = usage;
  try {
    const tarif = lireTarif(join(dossierBase, "tarif.json"), lot.model, debut);
    cr.montant_usd = montantUsage(usage, tarif, "lot");
    cr.tarif = { date: tarif.date, source: tarif.source };
  } catch (erreur) {
    if (!(erreur instanceof ErreurAromes)) throw erreur;
    // Aucun montant de remplacement : la panne figure au rapport et à l'écran.
    cr.montant_usd = null;
    cr.montant_raison = erreur.message;
    ecrire(`Montant non calculé : ${erreur.message}`);
  }
  return terminer(cr, { dossierAromes, aromes, relire, ecrire, ecrireAromesFichier: true });
}

/// Fin d'une exécution : aromes.json, rapport.json, a-relire.md, résumé à l'écran.
function terminer(cr, { dossierAromes, aromes, relire, ecrire, ecrireAromesFichier }) {
  if (ecrireAromesFichier) ecrireAromes(dossierAromes, aromes);
  const relecture = relire();
  if (relecture !== null) cr.a_relire = relecture;
  writeFileSync(join(dossierAromes, "rapport.json"), `${JSON.stringify(cr, null, 2)}\n`);
  ecrire(
    `Générés : ${cr.generes} ; erreurs : ${cr.erreurs.length} ; refusés au contrôle : ${cr.refus.length} ; ` +
      `relues non remplacées : ${cr.relues.filter((r) => r.raison === "relue, non remplacée").length}` +
      (cr.a_relancer ? ` ; à relancer : ${cr.a_relancer.length}` : "") +
      (cr.appels_au_resultat_inconnu > 0
        ? ` ; appels au résultat inconnu : ${cr.appels_au_resultat_inconnu}`
        : "") +
      (cr.montant_usd !== undefined && cr.montant_usd !== null
        ? ` ; montant ${cr.montant_usd} $${cr.montant_incomplet ? " (incomplet)" : ""}`
        : "") +
      ".",
  );
  return cr;
}
