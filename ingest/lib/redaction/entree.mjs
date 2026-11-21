// Enveloppe d'une entrée rédigée, commune aux natures (ADR-013, section 4 ; ADR-017,
// section 3) : relecture (`reviewed`, `reviewed_at`), provenance, empreinte des données
// envoyées. Le contenu propre à chaque nature (usages d'un houblon, moments d'un divers…)
// est contrôlé par lib/<nature>/validation.mjs. N'importe pas le SDK d'Anthropic (P54).

import { EFFORTS, estDate } from "./texte.mjs";

/// Ligne de provenance d'une entrée générée.
export const SOURCE_PROVENANCE = "claude-api";
export const LICENCE_PROVENANCE = "Texte généré pour Kass'Beer";

const VERSION = new RegExp(
  `^claude-[a-z0-9-]{1,60} / prompt [1-9][0-9]{0,3} / effort (${EFFORTS.join("|")})$`,
);

const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

/// Entrée tirée d'une sortie contrôlée du modèle ([resultat]) pour [cible]
/// (`{id, nom, empreinte}`) : nom copié sous [champNom], contenu, non relue, provenance.
export function construireEntree(
  cible,
  resultat,
  { champNom, modele, promptVersion, effort, date },
) {
  return {
    [champNom]: cible.nom,
    ...resultat,
    reviewed: false,
    provenance: [
      {
        source: SOURCE_PROVENANCE,
        source_id: cible.id,
        version: `${modele} / prompt ${promptVersion} / effort ${effort}`,
        licence: LICENCE_PROVENANCE,
        retrieved: date,
      },
    ],
    input_sha256: cible.empreinte,
  };
}

/// Erreurs de l'enveloppe de [doc] (`{id, data}`) : `reviewed`, `reviewed_at`,
/// `input_sha256`, `provenance`. [un] nomme l'ingrédient dans les messages (« houblon »).
export function reglesEnveloppe(doc, un) {
  const erreurs = [];
  const r = (chemin, regle) => erreurs.push(`${chemin} : ${regle}`);
  const d = doc.data;
  if (typeof d.reviewed !== "boolean") r("reviewed", "booléen attendu");
  if (d.reviewed === true && !estDate(d.reviewed_at)) {
    r("reviewed_at", "date AAAA-MM-JJ attendue pour une entrée relue");
  }
  if (d.reviewed === false && "reviewed_at" in d) r("reviewed_at", "absente attendue si non relue");
  if (!/^[0-9a-f]{64}$/.test(d.input_sha256 ?? "")) r("input_sha256", "64 hexadécimaux attendus");
  const p = d.provenance;
  if (!Array.isArray(p) || p.length !== 1 || !estObjet(p[0])) {
    r("provenance", "une ligne attendue");
  } else {
    const l = p[0];
    const cles = ["source", "source_id", "version", "licence", "retrieved"];
    if (Object.keys(l).sort().join(",") !== [...cles].sort().join(",")) {
      r("provenance[0]", "clés source, source_id, version, licence, retrieved attendues");
    } else {
      if (l.source !== SOURCE_PROVENANCE) r("provenance[0].source", `${SOURCE_PROVENANCE} attendu`);
      if (l.source_id !== doc.id) r("provenance[0].source_id", `identifiant du ${un} attendu`);
      if (typeof l.version !== "string" || !VERSION.test(l.version)) {
        r("provenance[0].version", "« <modèle> / prompt <n> / effort <e> » attendu");
      }
      if (l.licence !== LICENCE_PROVENANCE) r("provenance[0].licence", "licence attendue");
      if (!estDate(l.retrieved)) r("provenance[0].retrieved", "date AAAA-MM-JJ attendue");
    }
  }
  return erreurs;
}
