// Client de l'API Messages d'Anthropic des textes rédigés depuis le poste de l'admin
// (ADR-013, ADR-017, P54), commun à toutes les natures. Le SDK officiel se charge au premier appel, par un import dynamique, et le client est
// mémorisé : importer ce fichier ne charge pas le SDK. La clé ANTHROPIC_API_KEY est lue
// dans l'environnement au premier appel ; elle n'est jamais écrite, et sa valeur est
// retirée de tout texte d'erreur avant affichage.

import { ErreurRedaction } from "./tarif.mjs";

export const MESSAGE_CLE_RETIREE = "[clé retirée]";

/// [texte] sans aucune occurrence de [cle].
export function masquerCle(texte, cle) {
  const t = String(texte);
  return cle ? t.split(cle).join(MESSAGE_CLE_RETIREE) : t;
}

/// Erreur d'un appel, ramenée à des champs sans secret : nom, statut HTTP, identifiant de
/// requête, code d'erreur et message, clé retirée.
export function erreurLisible(erreur, cle) {
  const parties = [erreur?.name ?? "Erreur"];
  if (typeof erreur?.status === "number") parties.push(`HTTP ${erreur.status}`);
  if (erreur?.errorCode) parties.push(erreur.errorCode);
  if (erreur?.requestID) parties.push(`requête ${erreur.requestID}`);
  const message = masquerCle(erreur?.message ?? String(erreur), cle);
  return `${parties.join(", ")} : ${message}`;
}

/// Crée l'accès à l'API. [env] : environnement du processus ; [chargerSdk] : import du SDK
/// (remplacé dans les tests). Rien n'est chargé avant le premier appel d'une méthode.
export function creerAccesApi({ env, chargerSdk = () => import("@anthropic-ai/sdk") }) {
  let client = null;
  let cle = null;
  const obtenir = async () => {
    if (client !== null) return client;
    cle = env.ANTHROPIC_API_KEY ?? "";
    if (cle.trim() === "") {
      throw new ErreurRedaction(
        "ANTHROPIC_API_KEY absente : définissez la clé de l'espace de travail Kass'Beer de " +
          "la Console Anthropic dans l'environnement du terminal.",
      );
    }
    const sdk = await chargerSdk();
    const Anthropic = sdk.default ?? sdk.Anthropic;
    // maxRetries 0 sur les envois facturés (create, batches.create) : aucun envoi rejoué.
    client = new Anthropic({ apiKey: cle, maxRetries: 2 });
    return client;
  };
  return {
    /// Clé lue, pour masquer un message d'erreur ; null avant le premier appel.
    cle: () => cle,
    async compterJetons(params) {
      const c = await obtenir();
      const { max_tokens: _ignore, ...reste } = params;
      const r = await c.messages.countTokens(reste);
      return r.input_tokens;
    },
    async creerMessage(params) {
      const c = await obtenir();
      return c.messages.create(params, { maxRetries: 0 });
    },
    async creerLot(requetes) {
      const c = await obtenir();
      return c.messages.batches.create({ requests: requetes }, { maxRetries: 0 });
    },
    async lireLot(id) {
      const c = await obtenir();
      return c.messages.batches.retrieve(id);
    },
    async resultatsLot(id) {
      const c = await obtenir();
      const resultats = [];
      for await (const r of await c.messages.batches.results(id)) resultats.push(r);
      return resultats;
    },
  };
}
