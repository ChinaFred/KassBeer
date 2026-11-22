// Moteur commun des textes rédigés par l'API Messages d'Anthropic depuis le poste de l'admin
// (ADR-013, ADR-017, ADR-018, ADR-019), lancé par un générateur (generer-aromes.mjs,
// generer-divers.mjs) qui lui passe sa ou ses natures (lib/<nature>/nature.mjs : poste de coût,
// fichiers, données envoyées, empreinte, prompt, contrôle ; au besoin périmètre et contexte).
// Le moteur ne nomme aucune nature ni aucun poste. Il lit le référentiel préparé
// (import/ingest/prepare/) et le dossier de la nature ; il n'importe pas firebase-admin, ne
// lit ni n'écrit Firestore. Seul accès réseau : l'API, par client.mjs (P54).
//
// Fichiers du dossier de la nature (jamais versionnés) : entrées {id, data}, liste du groupe,
// lot-<id>.json (table custom_id → entrée d'un lot de l'API Batches), brut/ (réponses de
// chaque exécution, effort dans le nom), rapport.json (poste, modèle, effort, jetons,
// montant), a-relire.md. Tarif : import/ingest/tarif.json, commun aux natures (tarif.mjs).

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { creerAccesApi, erreurLisible } from "./client.mjs";
import { borneHaute, ErreurRedaction, lireTarifCommun, montantUsage } from "./tarif.mjs";
import { EFFORTS } from "./texte.mjs";

/// Dossier du référentiel préparé par défaut, à la racine du dépôt.
export const DOSSIER_PREPARE = fileURLToPath(
  new URL("../../../import/ingest/prepare/", import.meta.url),
);

/// Entrées envoyées en appels directs, au plus (essai, --nouveaux sans --lot).
export const SEUIL_DIRECT = 20;

/// Entrées d'un essai par défaut (ADR-013, décision 5 ; ADR-018, section 5).
export const ESSAI_DEFAUT = 10;

export const EFFORT_DEFAUT = "medium";

const ID_LOT = /^[A-Za-z0-9_-]{1,128}$/;

/// Aide d'un générateur, d'après ses natures ([choix] : Map clé → nature, la première par
/// défaut).
const aide = (choix) => {
  const n = [...choix.values()][0];
  const natures =
    choix.size > 1 ? `--nature ${[...choix.keys()].join("|")} (${n.cle} par défaut), ` : "";
  return `Usage (dans ingest/) :
  node ${n.script} --essai [n] [--seulement <${n.mots.fichierExemple}>] [--effort <e>] [--budget-usd <$>]
  node ${n.script} --lot --budget-usd <$> [--seulement <${n.mots.fichierExemple}>] [--nouveaux] [--tout] [--max <n>] [--effort <e>]
  node ${n.script} --nouveaux --budget-usd <$> [--effort <e>]          (${SEUIL_DIRECT} ${n.mots.des} au plus, appels directs)
  node ${n.script} --lot|--essai --regenerer <id> [--regenerer <id>…] --budget-usd <$>
  node ${n.script} --suivre <id du lot>
  node ${n.script} --relire                                            (réécrit a-relire.md, aucun appel)
Options communes : ${natures}--dossier <prepare>, ${n.optionDossier} <dossier>. Effort : ${EFFORTS.join(", ")}.`;
};

/// Natures d'un générateur : une nature seule, ou un objet clé → nature (generer-aromes.mjs :
/// hop, culture). Rend une Map, la première nature par défaut.
function choixNatures(natures) {
  if (typeof natures?.poste === "string") return new Map([[natures.cle, natures]]);
  return new Map(Object.entries(natures));
}

/// Lit [argv] (sans `node` ni le script) pour [natures] (une nature, ou un objet clé →
/// nature choisie par --nature). Lève ErreurRedaction. La nature choisie est rendue dans
/// `nature`, le dossier des natures (option `nature.optionDossier`) dans `dossierNature`.
export function lireOptions(argv, natures) {
  const choix = choixNatures(natures);
  const AIDE = aide(choix);
  let cle = [...choix.keys()][0];
  const o = {
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
    dossierNature: null,
  };
  const valeur = (i, nom) => {
    const v = argv[i];
    if (v === undefined || v.startsWith("--")) {
      throw new ErreurRedaction(`${nom} demande une valeur.\n${AIDE}`);
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
          throw new ErreurRedaction(`--essai : de 1 à ${SEUIL_DIRECT} entrées.`);
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
          throw new ErreurRedaction("--suivre : identifiant de lot mal formé.");
        break;
      case "--seulement":
      case "--dossier":
        o[nom.slice(2)] = valeur(++i, nom);
        break;
      case [...choix.values()][0].optionDossier:
        o.dossierNature = valeur(++i, nom);
        break;
      case "--nature":
        if (choix.size < 2) throw new ErreurRedaction(`Option inconnue : ${nom}\n${AIDE}`);
        cle = valeur(++i, nom);
        if (!choix.has(cle)) {
          throw new ErreurRedaction(`--nature : ${[...choix.keys()].join(" ou ")}.`);
        }
        break;
      case "--budget-usd": {
        const v = Number(valeur(++i, nom));
        if (!Number.isFinite(v) || v <= 0)
          throw new ErreurRedaction("--budget-usd : montant positif attendu.");
        o.budget = v;
        break;
      }
      case "--max": {
        const v = Number(valeur(++i, nom));
        if (!Number.isInteger(v) || v < 1)
          throw new ErreurRedaction("--max : entier positif attendu.");
        o.max = v;
        break;
      }
      case "--effort":
        o.effort = valeur(++i, nom);
        if (!EFFORTS.includes(o.effort)) {
          throw new ErreurRedaction(`--effort : ${EFFORTS.join(", ")}.`);
        }
        break;
      case "--regenerer":
        o.regenerer.push(valeur(++i, nom));
        break;
      default:
        throw new ErreurRedaction(`Option inconnue : ${nom}\n${AIDE}`);
    }
  }
  const nature = choix.get(cle);
  const { mots } = nature;
  // Plafond par lancement propre à la nature (houblons et divers 500, levures 1 000),
  // contrôlé une fois --nature lu, quel que soit l'ordre des options.
  if (o.max === null) o.max = nature.maxEntrees;
  else if (o.max > nature.maxEntrees) {
    throw new ErreurRedaction(`--max : entier de 1 à ${nature.maxEntrees} pour ${mots.des}.`);
  }
  for (const id of o.regenerer) {
    if (!nature.motifId.test(id) || id.length > 200) {
      throw new ErreurRedaction(
        `--regenerer : identifiant de ${mots.un} attendu (${nature.prefixeId}…).`,
      );
    }
  }
  const modes = [o.essai !== null, o.lot, o.suivre !== null, o.relire].filter(Boolean).length;
  if (modes > 1 || (modes === 0 && !o.nouveaux)) {
    throw new ErreurRedaction(
      `Choisissez un seul de --essai, --lot, --nouveaux, --suivre, --relire.\n${AIDE}`,
    );
  }
  if ((o.suivre !== null || o.relire) && (o.nouveaux || o.tout || o.regenerer.length > 0)) {
    throw new ErreurRedaction("--suivre et --relire ne prennent aucune option de sélection.");
  }
  if (o.essai !== null && o.nouveaux) {
    throw new ErreurRedaction("--essai et --nouveaux : choisissez l'un des deux.");
  }
  if (o.tout && (o.nouveaux || o.regenerer.length > 0)) {
    throw new ErreurRedaction("--tout ne se combine ni avec --nouveaux ni avec --regenerer.");
  }
  let mode = "nouveaux";
  if (o.essai !== null) mode = "essai";
  else if (o.lot) mode = "lot";
  else if (o.suivre !== null) mode = "suivre";
  else if (o.relire) mode = "relire";
  if ((mode === "lot" || mode === "nouveaux") && o.budget === null) {
    throw new ErreurRedaction(
      `--budget-usd est obligatoire hors essai (${nature.adr}, plafond 2).`,
    );
  }
  return { ...o, mode, nature };
}

/// Lit un fichier JSON ; un fichier absent rend [absent].
function lireJson(chemin, absent) {
  if (!existsSync(chemin)) return absent;
  return JSON.parse(readFileSync(chemin, "utf8"));
}

/// Référentiel préparé de [nature] : Map id → data.
function lireReferentiel(dossierPrepare, nature) {
  const liste = JSON.parse(readFileSync(join(dossierPrepare, nature.referentiel), "utf8"));
  if (!Array.isArray(liste)) throw new Error(`${nature.referentiel} : liste attendue`);
  return new Map(liste.map((d) => [d.id, d.data]));
}

/// Entrées du fichier de la nature : Map id → data (vide si le fichier manque).
function lireEntrees(dossierNature, nature) {
  const liste = lireJson(join(dossierNature, nature.fichierEntrees), []);
  if (!Array.isArray(liste)) throw new Error(`${nature.fichierEntrees} : liste attendue`);
  return new Map(liste.map((d) => [d.id, d.data]));
}

/// Écrit le fichier des entrées, triées par identifiant, par un fichier temporaire renommé.
function ecrireEntrees(dossierNature, nature, entrees) {
  const liste = [...entrees.keys()].sort().map((id) => ({ id, data: entrees.get(id) }));
  const chemin = join(dossierNature, nature.fichierEntrees);
  writeFileSync(`${chemin}.tmp`, `${JSON.stringify(liste, null, 2)}\n`);
  renameSync(`${chemin}.tmp`, chemin);
}

/// Identifiants résolus d'une liste du groupe (format `nature.formatGroupe`, écrite par
/// `nature.scriptGroupe`), ou null si elle manque.
function lireGroupe(chemin, nature) {
  const f = lireJson(chemin, null);
  if (f === null) return null;
  if (f?.format !== nature.formatGroupe || !Array.isArray(f.resolus)) {
    throw new ErreurRedaction(`${chemin} : fichier de ${nature.scriptGroupe} attendu.`);
  }
  return {
    ids: f.resolus.map((r) => r.id),
    nonResolus: Array.isArray(f.non_resolus) ? f.non_resolus : [],
  };
}

/// Périmètre de [nature] sur [referentiel] (Map id → data) : les entrées du groupe
/// ([groupeIds]) toujours, les autres si la nature n'a pas de périmètre ou si leur type y est
/// (ADR-017, décision 1). Rend `{ids, hors}` : identifiants triés retenus, et Set des écartés.
export function calculerPerimetre(referentiel, groupeIds, nature) {
  const ids = [];
  const hors = new Set();
  for (const id of [...referentiel.keys()].sort()) {
    const dedans =
      nature.perimetre === undefined ||
      groupeIds.has(id) ||
      nature.perimetre.dansPerimetre(referentiel.get(id));
    if (dedans) ids.push(id);
    else hors.add(id);
  }
  return { ids, hors };
}

/// Sélection d'un lancement. Rend `{envoi: [{id, donnees, empreinte, categorie, relue}],
/// nouveaux, changes, inchanges, relues: [{id, raison}]}` ; `categorie` : `nouveau`,
/// `change` ou `force`.
function selectionner({ nature, referentiel, entrees, options, base, contexte }) {
  const forces = new Set(options.regenerer);
  const envoi = [];
  const relues = [];
  let nouveaux = 0;
  let changes = 0;
  let inchanges = 0;
  for (const id of base) {
    const data = referentiel.get(id);
    const donnees = nature.donneesEnvoyees(data);
    const empreinte = nature.empreinteEntree(donnees, {
      promptVersion: nature.promptVersion,
      modele: nature.modele,
      effort: options.effort,
      contexte,
    });
    const existante = entrees.get(id);
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

/// Lecture d'une réponse de l'API pour l'entrée [cible] (`{id, nom, empreinte}`). Rend
/// `{etat: 'ok', data}`, `{etat: 'erreur', raison}` (refusal, max_tokens, JSON illisible)
/// ou `{etat: 'refus', regles}` (contrôle). Aucun texte dans `raison` ni `regles`.
function lireReponse(nature, message, cible, { effort, date, contexte }) {
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
  const { regles, resultat } = nature.controlerSortieModele(sortie, contexte);
  if (regles.length > 0) return { etat: "refus", regles, sortie };
  const data = nature.construireEntree(cible, resultat, { effort, date });
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

/// Applique un résultat lu à [entrees] et au compte rendu [cr]. Une entrée relue n'est
/// jamais remplacée : la réponse reste dans brut/ et le rapport la signale.
function appliquer(lu, cible, entrees, cr) {
  if (lu.etat === "erreur") {
    cr.erreurs.push({ id: cible.id, raison: lu.raison });
  } else if (lu.etat === "refus") {
    cr.refus.push({ id: cible.id, regles: lu.regles });
  } else if (entrees.get(cible.id)?.reviewed === true) {
    cr.relues.push({ id: cible.id, raison: "relue, non remplacée" });
  } else {
    entrees.set(cible.id, lu.data);
    cr.generes++;
  }
}

/// Saisie de `oui` sur un terminal ; refus sans terminal.
export async function confirmerTerminal(question, entree, sortie) {
  if (!entree.isTTY || !sortie.isTTY) {
    throw new ErreurRedaction(
      "Aucun terminal : la confirmation est impossible, rien n'est envoyé.",
    );
  }
  const { createInterface } = await import("node:readline/promises");
  const rl = createInterface({ input: entree, output: sortie });
  try {
    return (await rl.question(`${question} Saisissez « oui » pour envoyer : `)).trim() === "oui";
  } finally {
    rl.close();
  }
}

/// Écrit a-relire.md : une entrée du groupe par section, données d'entrée et texte. Titre,
/// introduction et lignes propres à la nature viennent de `nature.relecture`.
function ecrireARelire(dossierNature, nature, referentiel, entrees, groupe) {
  const ids = [...new Set(groupe.ids)].sort();
  const lignes = [nature.relecture.titre, "", ...nature.relecture.intro, ""];
  let aRelire = 0;
  for (const id of ids) {
    const h = referentiel.get(id);
    const a = entrees.get(id);
    lignes.push(`## ${h?.name ?? id} (\`${id}\`)`, "");
    if (h === undefined) {
      lignes.push(`Absent de ${nature.referentiel}.`, "");
      continue;
    }
    lignes.push(nature.relecture.donnees(h));
    if (a === undefined) {
      lignes.push("- Aucune entrée : lancez la génération.", "");
      continue;
    }
    if (a.reviewed !== true) aRelire++;
    lignes.push(
      `- État : ${a.reviewed === true ? `relu le ${a.reviewed_at}` : "à relire"} ; statut ${a.status}` +
        (a.confidence ? ` ; confiance ${a.confidence}` : ""),
    );
    lignes.push(...nature.relecture.contenu(a));
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
  writeFileSync(join(dossierNature, "a-relire.md"), lignes.join("\n"));
  return { [nature.mots.des]: ids.length, aRelire };
}

/// Exécute un générateur pour [natures] (une nature, ou un objet clé → nature choisie par
/// --nature ; [nature] : une nature seule, forme courte). Rend le rapport de l'exécution.
/// [chargerSdk] et [confirmer] sont remplacés dans les tests. Lève ErreurRedaction pour une
/// utilisation refusée.
export async function generer({
  natures,
  nature: natureSeule,
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
  const options = lireOptions(argv, natures ?? natureSeule);
  const { nature } = options;
  const { mots } = nature;
  const dossierPrepare = resolve(options.dossier ?? DOSSIER_PREPARE);
  // Dossier des natures (import/ingest/aromes/, import/ingest/divers/) : le tarif se lit à
  // côté ; fichiers de la nature dans son sous-dossier (levures/).
  const dossierBase = resolve(options.dossierNature ?? nature.dossierDefaut);
  const dossierNature =
    nature.sousDossier === null ? dossierBase : join(dossierBase, nature.sousDossier);
  mkdirSync(dossierNature, { recursive: true });
  const referentiel = lireReferentiel(dossierPrepare, nature);
  const entrees = lireEntrees(dossierNature, nature);
  const groupe = lireGroupe(join(dossierNature, nature.fichierGroupe), nature);
  const runId = idExecution(debut);
  const date = debut.toISOString().slice(0, 10);
  const relire = () => {
    if (groupe === null) {
      ecrire(`${nature.fichierGroupe} absent : a-relire.md n'est pas écrit.`);
      return null;
    }
    return ecrireARelire(dossierNature, nature, referentiel, entrees, groupe);
  };
  const ctx = { nature, dossierBase, dossierNature, entrees, ecrire, relire };

  if (options.mode === "relire") {
    const r = relire();
    if (r !== null) {
      ecrire(`a-relire.md : ${r[mots.des]} ${mots.des} du groupe, ${r.aRelire} à relire.`);
    }
    return { poste: nature.poste, mode: "relire", a_relire: r };
  }
  // Contexte de la nature (styles du prompt des levures), lu une fois par exécution.
  const contexte = nature.contexte?.(dossierPrepare);
  const message = contexte === undefined ? null : (nature.messageContexte?.(contexte) ?? null);
  if (message !== null) ecrire(message);
  ctx.contexte = contexte;
  const api = creerAccesApi({ env, chargerSdk });
  if (options.mode === "suivre") {
    return suivre({ ...ctx, options, api, debut, runId });
  }

  // Sélection, sans réseau. Périmètre de la nature : entrées du groupe, plus celles dont le
  // type est retenu ; un identifiant nommé hors du périmètre est refusé.
  const perimetre = calculerPerimetre(referentiel, new Set(groupe?.ids ?? []), nature);
  let base;
  if (options.regenerer.length > 0) base = options.regenerer;
  else if (options.seulement !== null) {
    const f = lireGroupe(resolve(options.seulement), nature);
    if (f === null) throw new ErreurRedaction(`${options.seulement} : fichier absent.`);
    base = f.ids;
  } else base = perimetre.ids;
  const inconnus = base.filter((id) => !referentiel.has(id));
  if (inconnus.length > 0) {
    throw new ErreurRedaction(
      `${mots.Des} absents de ${nature.referentiel} : ${inconnus.slice(0, 20).join(", ")}.`,
    );
  }
  const horsNommes = base.filter((id) => perimetre.hors.has(id));
  if (horsNommes.length > 0) {
    throw new ErreurRedaction(
      `${mots.Des} hors du périmètre (types ${nature.perimetre.typesExclus.join(", ")}, hors du ` +
        `groupe) : ${horsNommes.slice(0, 20).join(", ")}. Rien n'est envoyé.`,
    );
  }
  base = [...new Set(base)];
  const s = selectionner({ nature, referentiel, entrees, options, base, contexte });
  let envoi = s.envoi;
  if (options.mode === "essai") envoi = envoi.slice(0, options.essai);
  const direct = options.mode !== "lot";
  if (nature.perimetre !== undefined) {
    ecrire(
      `Périmètre : ${perimetre.ids.length} ${mots.des} sur ${referentiel.size}, ` +
        `${perimetre.hors.size} hors périmètre (types ${nature.perimetre.typesExclus.join(", ")}).`,
    );
  }
  ecrire(
    `${mots.Des} : ${s.nouveaux} nouveaux, ${s.changes} changés, ${s.inchanges} inchangés` +
      (options.tout ? " (--tout : tous renvoyés)" : "") +
      ` ; ${envoi.length} à envoyer.`,
  );
  for (const r of s.relues)
    ecrire(`  ${r.id} : ${r.raison} (--regenerer ${r.id} pour la renvoyer)`);
  const cr = {
    poste: nature.poste,
    run_id: runId,
    mode: options.mode,
    model: nature.modele,
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
  if (nature.perimetre !== undefined) {
    cr.perimetre = {
      retenus: perimetre.ids.length,
      hors: perimetre.hors.size,
      types_exclus: nature.perimetre.typesExclus,
    };
  }
  if (envoi.length === 0) {
    ecrire("Rien à envoyer.");
    return terminer(cr, { ...ctx, ecrireFichier: false });
  }
  if (envoi.length > options.max) {
    throw new ErreurRedaction(
      `${envoi.length} ${mots.des} à envoyer, --max ${options.max} au plus.`,
    );
  }
  if (direct && envoi.length > SEUIL_DIRECT) {
    throw new ErreurRedaction(
      `${envoi.length} ${mots.des} : au-delà de ${SEUIL_DIRECT}, passez par un lot (--lot).`,
    );
  }

  // Tarif d'abord : sans lui, aucune estimation et aucun appel.
  const lu = lireTarifCommun(dossierBase, nature.modele, debut);
  const tarif = lu.tarif;
  if (lu.ancienIgnore) ecrire(`${lu.ancien} ignoré : seul ${lu.chemin} est lu (ADR-019).`);
  const requetes = envoi.map((c) =>
    nature.parametresRequete(c.donnees, { effort: options.effort, cache: direct, contexte }),
  );
  const jetons = [];
  for (const p of requetes) jetons.push(await api.compterJetons(p));
  const borne = borneHaute(jetons, {
    tarif,
    mode: direct ? "direct" : "lot",
    maxTokens: nature.maxTokens,
    budget: options.budget,
  });
  const totalJetons = jetons.reduce((a, b) => a + b, 0);
  cr.estimation = {
    [mots.des]: envoi.length,
    mode: direct ? "direct" : "lot",
    jetons_entree: totalJetons,
    max_tokens: nature.maxTokens,
    borne_haute_usd: borne.montant,
    budget_usd: options.budget,
    tarif: { date: tarif.date, source: tarif.source },
  };
  ecrire(
    `Envoi : ${envoi.length} ${mots.des}, ${direct ? "appels directs" : "lot de l'API Batches (− 50 %, 24 h au plus)"}, ` +
      `modèle ${nature.modele}, effort ${options.effort}, ${totalJetons} jetons d'entrée, ` +
      `borne haute ${borne.montant.toFixed(2)} $ (tarif du ${tarif.date}).`,
  );
  if (options.budget !== null && borne.montant > options.budget) {
    throw new ErreurRedaction(
      `Borne haute ${borne.montant.toFixed(2)} $ au-delà du budget ${options.budget} $ : ` +
        `${borne.tiennent} ${mots.des} tiendraient. Rien n'est envoyé.`,
    );
  }
  if (!(await confirmer(`Poste ${nature.poste}.`, entree, sortie))) {
    throw new ErreurRedaction("Envoi non confirmé : rien n'est envoyé.");
  }

  if (!direct) {
    return creerLot({ ...ctx, envoi, requetes, options, cr, api, debut });
  }

  const brut = [];
  const usage = usageVide();
  const cheminBrut = join(dossierNature, "brut", `${options.mode}-${runId}-${options.effort}.json`);
  mkdirSync(join(dossierNature, "brut"), { recursive: true });
  try {
    for (let i = 0; i < envoi.length; i++) {
      const cible = envoi[i];
      let message;
      try {
        message = await api.creerMessage(requetes[i]);
      } catch (erreur) {
        // Aucun envoi rejoué : l'erreur est notée, les entrées restantes ne partent pas.
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
      const reponse = lireReponse(nature, message, cible, {
        effort: options.effort,
        date,
        contexte,
      });
      brut.push({
        id: cible.id,
        stop_reason: message.stop_reason,
        usage: message.usage,
        sortie: reponse.sortie ?? null,
      });
      appliquer(reponse, cible, entrees, cr);
      // Réponses gardées au fil de l'eau : un essai coupé ne renvoie que les manquants.
      writeFileSync(cheminBrut, `${JSON.stringify(brut, null, 2)}\n`);
      if (reponse.etat === "ok" && entrees.get(cible.id) === reponse.data) {
        ecrireEntrees(dossierNature, nature, entrees);
      }
    }
  } finally {
    cr.usage = usage;
    cr.montant_usd = montantUsage(usage, tarif, "direct");
    cr.brut = cheminBrut;
  }
  return terminer(cr, { ...ctx, ecrireFichier: true });
}

/// Vrai si [erreur] porte un statut HTTP : l'API a répondu, la requête n'a pas abouti. Faux
/// pour une coupure ou un délai (APIConnectionError, APIConnectionTimeoutError), où la
/// requête a pu être traitée.
const aRecuUneReponse = (erreur) => typeof erreur?.status === "number";

/// Crée le lot : table custom_id écrite avant l'envoi, puis lot-<id>.json.
async function creerLot({
  nature,
  dossierNature,
  envoi,
  requetes,
  options,
  cr,
  api,
  debut,
  ecrire,
}) {
  const table = {};
  const demandes = envoi.map((c, i) => {
    const customId = `${nature.prefixeCustomId}${String(i + 1).padStart(4, "0")}`;
    table[customId] = { id: c.id, [nature.champNom]: c.nom, input_sha256: c.empreinte };
    return { custom_id: customId, params: requetes[i] };
  });
  const lot = {
    nature: nature.cle,
    created_at: debut.toISOString(),
    retrieved: debut.toISOString().slice(0, 10),
    model: nature.modele,
    effort: options.effort,
    prompt_version: nature.promptVersion,
    estimation: cr.estimation,
    table,
  };
  const attente = join(dossierNature, `lot-attente-${cr.run_id}.json`);
  writeFileSync(attente, `${JSON.stringify(lot, null, 2)}\n`);
  let cree;
  try {
    cree = await api.creerLot(demandes);
  } catch (erreur) {
    const raison = erreurLisible(erreur, api.cle());
    if (aRecuUneReponse(erreur)) {
      // L'API a répondu par une erreur : aucun lot n'a été créé. La table est gardée, marquée.
      renameSync(attente, join(dossierNature, `lot-attente-${cr.run_id}.refuse.json`));
      throw new ErreurRedaction(`Lot refusé : ${raison}. Rien n'est parti.`);
    }
    // Coupure ou délai sans réponse : le lot a pu être créé. La table reste sur le poste.
    throw new ErreurRedaction(
      `Lot au résultat inconnu : ${raison}. Résultat inconnu : vérifiez les lots dans la ` +
        "Console Anthropic avant de relancer. Table des requêtes gardée dans " +
        `${attente} (${nature.prefixeCustomId}0001 → ${nature.mots.un}).`,
    );
  }
  if (!ID_LOT.test(cree?.id ?? ""))
    throw new Error("Identifiant de lot illisible dans la réponse.");
  writeFileSync(
    join(dossierNature, `lot-${cree.id}.json`),
    `${JSON.stringify({ batch_id: cree.id, ...lot }, null, 2)}\n`,
  );
  renameSync(attente, join(dossierNature, `lot-attente-${cr.run_id}.envoye.json`));
  cr.batch_id = cree.id;
  cr.counts.envoyes = envoi.length;
  ecrire(`Lot ${cree.id} parti. Suivi : node ${nature.commande} --suivre ${cree.id}`);
  writeFileSync(join(dossierNature, "rapport.json"), `${JSON.stringify(cr, null, 2)}\n`);
  return cr;
}

/// --suivre : état d'un lot ; terminé, résultats contrôlés et fusionnés dans le fichier des
/// entrées.
async function suivre(ctx) {
  const { nature, dossierBase, dossierNature, entrees, options, api, debut, runId, ecrire } = ctx;
  const cheminLot = join(dossierNature, `lot-${options.suivre}.json`);
  if (!existsSync(cheminLot)) {
    throw new ErreurRedaction(`lot-${options.suivre}.json absent : lot inconnu de ce poste.`);
  }
  const lot = JSON.parse(readFileSync(cheminLot, "utf8"));
  // Un lot d'avant ADR-017 ne porte pas sa nature : c'est un lot de houblons, ou de divers
  // dans import/ingest/divers/ (lot D2 d'ADR-018) ; `lotsSansNature` de la nature le dit. Un
  // lot d'une autre nature est refusé.
  const accepte = lot.nature === undefined ? nature.lotsSansNature : lot.nature === nature.cle;
  if (!accepte) {
    throw new ErreurRedaction(
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
      poste: nature.poste,
      mode: "suivre",
      batch_id: options.suivre,
      processing_status: etat.processing_status,
      request_counts: c,
    };
  }
  const cr = {
    poste: nature.poste,
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
    const cible = { id: cible0.id, nom: cible0[nature.champNom], empreinte: cible0.input_sha256 };
    if (r.result?.type !== "succeeded") {
      cr.a_relancer.push({
        id: cible.id,
        raison: String(r.result?.type ?? "inconnu").slice(0, 40),
      });
      continue;
    }
    cumuler(usage, r.result.message.usage);
    const lu = lireReponse(nature, r.result.message, cible, {
      effort: lot.effort,
      date: lot.retrieved,
      contexte: ctx.contexte,
    });
    brut.push({
      id: cible.id,
      custom_id: r.custom_id,
      stop_reason: r.result.message.stop_reason,
      usage: r.result.message.usage,
      sortie: lu.sortie ?? null,
    });
    appliquer(lu, cible, entrees, cr);
  }
  for (const [customId, cible] of Object.entries(lot.table)) {
    if (!vus.has(customId)) cr.a_relancer.push({ id: cible.id, raison: "sans résultat" });
  }
  mkdirSync(join(dossierNature, "brut"), { recursive: true });
  cr.brut = join(dossierNature, "brut", `lot-${options.suivre}-${lot.effort}.json`);
  writeFileSync(cr.brut, `${JSON.stringify(brut, null, 2)}\n`);
  cr.usage = usage;
  try {
    const t = lireTarifCommun(dossierBase, lot.model, debut);
    if (t.ancienIgnore) ecrire(`${t.ancien} ignoré : seul ${t.chemin} est lu (ADR-019).`);
    cr.montant_usd = montantUsage(usage, t.tarif, "lot");
    cr.tarif = { date: t.tarif.date, source: t.tarif.source };
  } catch (erreur) {
    if (!(erreur instanceof ErreurRedaction)) throw erreur;
    // Aucun montant de remplacement : la panne figure au rapport et à l'écran.
    cr.montant_usd = null;
    cr.montant_raison = erreur.message;
    ecrire(`Montant non calculé : ${erreur.message}`);
  }
  return terminer(cr, { ...ctx, ecrireFichier: true });
}

/// Fin d'une exécution : fichier des entrées, rapport.json, a-relire.md, résumé à l'écran.
function terminer(cr, { nature, dossierNature, entrees, relire, ecrire, ecrireFichier }) {
  if (ecrireFichier) ecrireEntrees(dossierNature, nature, entrees);
  const relecture = relire();
  if (relecture !== null) cr.a_relire = relecture;
  writeFileSync(join(dossierNature, "rapport.json"), `${JSON.stringify(cr, null, 2)}\n`);
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
