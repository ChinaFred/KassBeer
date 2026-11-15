# ADR-016 — Socle IA côté serveur : client Claude par `fetch`, Moteur d'IA, grille tarifaire, suivi des coûts

- **Statut** : accepté le 2026-11-15
- **Date** : 2026-11-15
- **Remplace** : ADR-001, arbitrage 1 (« Aucune IA dans l'application en v1 »), en entier.
  Complète ADR-008 (liste fermée des points d'accès : `saveAiSettings`) et ADR-013 (même espace
  de travail de la Console Anthropic, seconde clé). ADR-015 (assistant de recette) est le
  premier poste branché sur ce socle.

## Contexte

L'utilisateur a demandé un assistant de recette (ADR-015). Le 2026-11-15, il a tranché :

1. La règle « Aucune IA dans l'application » d'ADR-001 est retirée en entier. D'autres
   connecteurs IA suivront.
2. Les règles de `CLAUDE.md`, « Coûts variables », restent : appel par le serveur, poste nommé
   au catalogue, plafond, un nouveau poste arrive avec son ADR.
3. Un socle commun vit dans `functions/src/ai/` dès le premier poste : client Anthropic par
   `fetch` (aucun SDK dans `functions/`, P26), nom du poste sur chaque appel, plafond par membre
   et par jour, journal des jetons.
4. Un écran Admin › Moteur d'IA choisit le modèle Claude et l'effort par poste. Une page suit
   les coûts réels par personne et par poste. Les deux s'inspirent de Kass'Dalle.
5. Claude seul. Aucun routage entre fournisseurs. Un autre fournisseur demandera son ADR.
6. Même espace de travail de la Console Anthropic qu'ADR-013 (limite de 20 $ par mois), avec
   une seconde clé réservée aux Functions, dans Secret Manager.
7. Plafonds réglables dans Moteur d'IA, sous une borne haute de 100 fixée dans le code. Sans
   réglage lisible, refus.
8. Un poste s'ouvre à l'admin seul, puis à tous les membres par un interrupteur, sans
   déploiement. Le serveur relit l'interrupteur à chaque appel.

Ce qui existe déjà :

- `functions/package.json` n'a que `firebase-admin` et `firebase-functions`. L'appel des
  routines (`functions/src/tickets/routine.ts`) passe par `fetch` (P35).
- `functions/src/config.ts` déclare six secrets et le compte d'exécution `tickets-functions`.
- `functions/src/auth.ts` porte `requireMember`, `requireAdmin` et `isFounder`, rejoués par
  `test-fixtures/member_access.json` (P31).
- `functions/src/logSampler.ts` échantillonne un journal répété.
- `firestore.rules` n'a aucune collection `ai_*` ni `app_config`.
- Kass'Dalle (`kass_dalle/functions/src/ai/`) : `anthropic.ts` (425 lignes), `pricing.ts`
  (633), `budget.ts` (888), `usage.ts` (577), `callable/aiRoutingCallable.ts` (1 077), et côté
  client `ai_routing_screen.dart` (1 997) et `ai_spend_screen.dart` (1 478). La grille
  `app_config/ai_pricing` est lue par le serveur et le client, et le calcul du coût existe en
  double (`ai_pricing.json`). Une ligne `ai_usage/{auto}` est écrite par appel.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| 0. Socle propre à l'assistant (`functions/src/assistant/`, modèle et plafonds dans `config.ts`) | moins de code au premier lot | le second poste recopie client, plafond et comptes ; un changement de modèle demande un déploiement ; aucun montant suivi dans l'application | 0 € / tarif du modèle |
| A. Socle commun, réglages dans `config.ts`, aucun écran | un seul client et un seul plafond | modèle, plafonds et ouverture aux membres passent par un déploiement ; décisions 4, 7 et 8 non servies | 0 € / tarif du modèle |
| B. Socle commun, Moteur d'IA, grille tarifaire dans Firestore, coût calculé par le serveur seul, suivi par mois (retenue) | décisions 1 à 8 servies ; aucun tarif ni modèle dans le code ; aucun calcul de coût en double | un écran d'admin, une callable d'admin et trois collections de plus | 0 € / tarif du modèle, plus quelques écritures Firestore par appel |
| C. Copie de Kass'Dalle (routage multi-fournisseur, budget en dollars, ligne par appel, calcul du coût côté client) | parité avec Kass'Dalle | routage refusé (décision 5) ; calcul du coût en double avec sa fixture ; ≈ 6 000 lignes à porter | comme B, plus une écriture par appel |

## Décision

Option B. Le socle vit dans `functions/src/ai/` et le serveur seul appelle Claude, calcule le
coût et l'écrit. Le client lit les réglages et les comptes, sans tarif, sans liste de modèles et
sans calcul de coût.

### 1. Ce qui change dans les règles du projet

- ADR-001, arbitrage 1, est retiré. L'application peut offrir une fonction d'IA, appelée par le
  serveur.
- ADR-001, réponse 2, reste : une fonction d'IA reçoit les valeurs calculées par `brewing/` et
  ne les recalcule pas (P3).
- « Coûts variables » reste entier. Chaque poste arrive avec son ADR, sa ligne au catalogue,
  son plafond et son entrée dans la liste fermée des postes (section 3).

### 2. Code serveur

`functions/src/ai/` :

| Fichier | Rôle |
|---|---|
| `claude.ts` | seul module qui appelle `https://api.anthropic.com/v1/messages`, par `fetch`, `redirect: "error"`, délai fixé par l'appelant, un seul appel, jamais rejoué ; clé lue au premier appel ; rend le texte, `stop_reason` et `usage` |
| `costCenters.ts` | liste fermée des postes (`AI_COST_CENTERS`), égale à `test-fixtures/ai_cost_centers.json` |
| `settings.ts` | lecture et validation de la politique et de la grille ; le même code sert `saveAiSettings` à l'écriture et chaque poste à la lecture |
| `quota.ts` | réservation d'un tour en transaction avant l'appel, rendu quand rien n'a été facturé |
| `pricing.ts` | coût d'un appel à partir de `usage` et de la ligne de la grille |
| `usage.ts` | écriture des comptes du mois et du journal de l'appel |
| `saveSettings.ts` | callable `saveAiSettings` |

Un poste appelle `runClaudeTurn({costCenter, uid, ...})`, qui enchaîne : politique, ouverture
du poste, plafond, appel, coût, comptes.

Aucun SDK : ni `@anthropic-ai/sdk`, ni `@google-cloud/*`. Aucun client au niveau module (P26).
Le SDK reste dans `ingest/` seul (ADR-013, P54).

### 3. Postes de coût

`AI_COST_CENTERS` liste les postes acceptés par le socle. Au premier lot :
`recipe_assistant_turn` (ADR-015). Un appel sous un autre nom est refusé avant tout `fetch`.

La liste existe en deux endroits : `costCenters.ts` (le serveur refuse un nom inconnu) et
`app/lib/features/admin/domain/postes_ia.dart` (libellé affiché par Moteur d'IA et par la page
des coûts). Les deux rejouent `test-fixtures/ai_cost_centers.json` (clé, libellé, ADR). Un
poste retiré du code reste dans ce fichier, pour que les mois passés gardent son libellé.

### 4. Politique : `ai_config/policy`

Forme :

```
{ version: 1, updated_at, updated_by_uid,
  features: { recipe_assistant_turn: {
    model, effort,                      // effort : null si le modèle n'en accepte pas
    members_enabled,                    // false : admin seul
    turns_per_day, founder_turns_per_day, turns_per_conversation } } }
```

- Écrite par `saveAiSettings` seule (`requireAdmin`), jamais par un client.
- `model` : clé de la grille (section 5). Une grille illisible refuse l'enregistrement de la
  politique.
- `effort` : valeur de `efforts` de la ligne du modèle dans la grille, ou `null` si cette liste
  est vide. Aucune liste d'efforts dans le code client.
- Plafonds : entiers de 1 à `AI_MAX_TURNS` (100), constante de `functions/src/config.ts` seule.
- `members_enabled` : booléen strict.

**Sans réglage lisible**, le poste refuse. Cas : document absent, illisible, poste absent de
`features`, valeur hors bornes, `members_enabled` non booléen. Conduite :

1. Refus `failed-precondition`, `details.reason: "ai_policy_unavailable"`, avant la réservation
   d'un tour et avant tout `fetch`. Rien n'est compté.
2. `logError` échantillonné une fois par minute et par instance (`logSampler.ts`), avec le poste
   et le motif (`missing`, `unreadable`, `out_of_bounds`), sans contenu.
3. Le client affiche : « Assistant indisponible : les réglages de l'IA manquent. L'administrateur
   les enregistre dans Admin › Moteur d'IA. »
4. Moteur d'IA affiche pour ce poste : « Aucun réglage enregistré : ce poste refuse tout
   appel. »

**Semis.** Rien n'est écrit au déploiement. Quand la politique est absente, le formulaire de
Moteur d'IA se présente prérempli : `claude-sonnet-5-5` s'il figure dans la grille, effort
`medium`, 20 tours par jour, 60 pour le fondateur, 20 par conversation, admin seul. L'en-tête
dit « Non enregistré ». Ces valeurs ne s'appliquent qu'à l'appui sur « Enregistrer ». Elles
vivent dans le formulaire Dart. Aucun serveur ne les lit.

### 5. Grille tarifaire : `ai_config/pricing`

Forme :

```
{ version: 1, checked_on: "AAAA-MM-JJ", source,          // source : 200 caractères au plus
  models: { "<id>": {
    label,
    input_usd_per_mtok, output_usd_per_mtok,
    cache_write_usd_per_mtok, cache_read_usd_per_mtok,
    efforts: ["low", "medium", "high"] } } }               // [] : modèle sans effort
```

- Identifiant de modèle conforme à `^claude-[a-z0-9-]{1,60}$` (Claude seul). Vingt modèles au
  plus. Tarifs : nombres finis de 0 à 1 000. `efforts` parmi `low`, `medium`, `high`, `xhigh`,
  `max` (liste de `settings.ts`, revue avec l'API).
- Écrite par `saveAiSettings` seule. Saisie à la main par l'admin dans Moteur d'IA, d'après la
  page des tarifs d'Anthropic. Aucun tarif dans le code TypeScript ni Dart.
- `checked_on` de plus de 90 jours : Moteur d'IA affiche « Tarifs à revérifier ». Les appels
  continuent d'être chiffrés.
- **Grille absente ou illisible, ou modèle absent de la grille** : l'appel part, sans montant.
  Le compte du mois ajoute 1 à `unpriced_calls` et n'ajoute rien à `cost_usd`. Moteur d'IA et
  la page des coûts affichent « Tarifs en panne ». Une valeur de repli n'est jamais appliquée.

**Coût d'un appel**, calculé par `pricing.ts` seul, au moment de l'appel :

```
(input_tokens × input + cache_creation_input_tokens × cache_write
 + cache_read_input_tokens × cache_read + output_tokens × output) / 1 000 000
```

`output_tokens` de l'API compte la réflexion. Le montant s'écrit une fois. Un changement de
grille ne recalcule pas les mois passés. Le client affiche le montant stocké et ne le recalcule
jamais : aucune logique de coût en double, aucune fixture de coût.

### 6. Comptes et journal

| Document | Contenu | Écrit par | Lu par |
|---|---|---|---|
| `ai_quotas/{uid}` | par poste : `day` (`AAAAMMJJ`, jour de Paris), `count`, `resets_at` (minuit suivant à Paris) | serveur, en transaction avant l'appel | le membre (`get` du sien), l'admin |
| `ai_usage/{AAAA-MM}_{uid}` | `month`, `uid`, par poste : `calls`, `failed_calls`, `unpriced_calls`, `input_tokens`, `cache_write_tokens`, `cache_read_tokens`, `output_tokens`, `cost_usd` | serveur, après l'appel | le membre (`get` du sien), l'admin (`list` par `month`, 50 au plus) |
| journal de l'appel (`logInfo`) | `cost_center`, `uid`, modèle, effort, jetons, `cost_usd` ou `unpriced: true`, durée, `stop_reason`, identifiant de corrélation fourni par le poste | serveur | l'admin, par Admin › Journaux (ADR-011) |

`resets_at` dispense le client de tout calcul de jour de Paris : un `count` dont `resets_at` est
passé vaut 0. Aucun texte de la personne ni du modèle n'entre dans un document ni un journal.
Aucune ligne Firestore par appel : le détail vit 30 jours dans Cloud Logging (rétention par
défaut, à vérifier), les comptes du mois restent.

Un membre lit ses propres comptes : tours restants du jour dans le panneau du poste, et dans
« Mon compte » une ligne « IA ce mois : N tours, ≈ X $ ». L'admin lit tout.

### 7. Règles Firestore

- `ai_config/policy` : `get` par `isMember()` (le client lit `members_enabled` et les plafonds
  pour l'affichage) ; `ai_config/pricing` : `get` par `isAdmin()` ; aucune autre clé sous
  `ai_config/` ; `list` et écriture refusées.
- `ai_quotas/{uid}` : `get` si `uid == request.auth.uid` et `isMember()`, ou `isAdmin()` ;
  `list` et écriture refusées.
- `ai_usage/{docId}` : `get` si `docId` vaut `<AAAA-MM>_` suivi de `request.auth.uid` et
  `isMember()` (un mois absent se lit sans erreur de droits), ou `isAdmin()` ; `list` par `isAdmin()` avec `request.query.limit <= 50` ; écriture refusée.
- Tests des cinq profils de P4 sur chaque chemin.

### 8. Callable `saveAiSettings`

`onCall`, `requireAdmin` (P30), `maxInstances: 1`, `timeoutSeconds: 60`, `cors` de
`CALLABLE_ORIGINS`, aucun secret. Argument `{kind: "policy" | "pricing", value}`, taille brute
bornée à 32 Ko. Validation par `settings.ts`, puis écriture en transaction avec `updated_at` et
`updated_by_uid`. Refus en `invalid-argument` avec `details.field` : le formulaire affiche le
champ en faute. Elle s'ajoute à la liste fermée d'ADR-008.

### 9. Écrans d'administration

- **Admin › Moteur d'IA** : la grille (ajouter, corriger, retirer un modèle ; date de
  vérification ; lien vers la page des tarifs d'Anthropic) ; par poste, le modèle (menu tiré des
  clés de la grille), l'effort (menu tiré de `efforts`), les trois plafonds, l'interrupteur
  « Ouvert à tous les membres ». « Enregistrer » appelle `saveAiSettings`. Hors ligne, bouton
  inactif.
- **Admin › Coûts de l'IA** : choix du mois ; total du mois ; une ligne par personne (nom lu
  dans `members/`), détaillée par poste : tours, jetons d'entrée, de cache et de sortie,
  montant ; appels sans montant affichés à part (« N appels sans montant : tarifs en panne ») ;
  lien vers la page d'usage de la Console Anthropic, qui fait foi pour la facture. Lecture par
  `get()`, aucun `snapshots()`.

### 10. Clé et espace de travail

- Espace de travail Kass'Beer de la Console Anthropic, celui d'ADR-013. Limite de dépense de
  20 $ par mois, commune aux deux usages.
- Seconde clé de cet espace, réservée aux Functions, dans Secret Manager sous le nom
  `ANTHROPIC_API_KEY`. `defineSecret` dans `functions/src/config.ts`. Montée par les seules
  callables qui appellent le socle : `recipeAssistantTurn` au premier lot.
- La clé du poste de l'admin (ADR-013) reste dans son environnement. Les deux clés se révoquent
  l'une sans l'autre.
- Jamais journalisée, jamais copiée dans `details` d'une `HttpsError` ; sa valeur exacte est
  retirée de tout texte d'erreur avant `logError`.
- Accès au secret : compte d'exécution `tickets-functions`, et `github-deploy` pour le
  déploiement (P14 étendu).
- **La limite atteinte bloque aussi la génération des arômes** (`ingest/generer-aromes.mjs`),
  et inversement : un lot d'arômes consomme le crédit de l'assistant. Le refus de l'API (400 ou
  429 de dépassement) est rendu au client « Crédit de l'IA épuisé pour ce mois. » et le tour est
  rendu.

### 11. Plafonds communs

Du plus fort au plus faible :

1. Limite de 20 $ par mois de l'espace de travail : seul plafond appliqué par le fournisseur.
2. Tours par membre et par jour de Paris, par poste (`turns_per_day`, `founder_turns_per_day`
   pour le compte `members/{email}.founder`). Réservés en transaction avant l'appel ; rendus
   (− 1, sans passer sous 0) seulement sur une réponse 4xx reçue ou une erreur de connexion
   avant l'envoi ; gardés sur un délai dépassé, un 5xx ou un 529 (`failed_calls` + 1), et dès
   que le modèle a répondu, même illisible.
3. Plafonds propres au poste (tours par conversation pour un poste conversationnel).
4. `maxInstances` de chaque callable.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : appel de Claude, politique, plafond, coût et comptes dans
   Cloud Functions (`europe-west1`) ; écrans d'admin et lecture des comptes sur l'appareil ;
   inférence chez Anthropic.
2. Ce qui existera en double : la liste des postes (clé et libellé), valeurs seules, dans
   `test-fixtures/ai_cost_centers.json`. Le calcul du coût n'existe qu'en TypeScript ; la grille
   et le montant vivent dans Firestore. Les bornes des plafonds n'existent qu'en TypeScript.
3. Ce qui pèse au démarrage : rien. `fetch`, aucun SDK, aucun client au niveau module. Côté
   client, aucun paquet ajouté ; deux écrans d'admin dans `main.dart.js`, mesurés (P6).
4. Compilation de chaque cible : aucune dépendance Dart ni npm ajoutée. Contrôles :
   `(cd functions && npm run lint && npm run build && npm test)`, `(cd rules-tests && npm test)`,
   `(cd app && flutter test)`, `flutter build web --release`.
5. Qui voit quoi : la grille et les comptes de tous, l'admin seul ; la politique, tout membre
   (modèle, plafonds, ouverture) ; ses propres comptes, chaque membre. Vers Anthropic : ce que
   chaque poste envoie, défini par son ADR ; gardé 30 jours (ADR-013, décision 3). Règles d'accès
   côté serveur : `requireMember` ou `requireAdmin`, ouverture du poste relue à chaque appel.
6. Ce qui coûte à l'usage, plafond : chaque poste, au tarif de son modèle (ADR-015 pour
   l'assistant). Firestore : 4 lectures (membre, politique, grille, compteur) et 2 écritures par appel, dans le niveau gratuit.
   Plafonds de la section 11.
7. Exposition : une callable d'admin de plus (`saveAiSettings`), sans secret. Un compte admin
   volé peut ouvrir un poste à tous et monter les plafonds à 100 ; la limite de 20 $ de la
   Console reste la borne de la dépense.
8. Exploitation : l'admin crée la seconde clé et le secret une fois, saisit la grille, enregistre
   la politique, recharge le crédit de la Console. Sauvegarde : `ai_config/` se recrée à la main
   en cinq minutes ; les comptes ne se restaurent pas, la Console garde la facture. Un changement
   de modèle part sans déploiement.
9. Coût de sortie : changer de fournisseur touche `claude.ts`, la forme de la grille et la
   validation des identifiants ; un ADR qui remplace celui-ci.

## Conséquences

Plus simple : un second poste réutilise client, plafond, coût et comptes ; le modèle et les
plafonds changent sans déploiement ; la dépense se lit par personne dans l'application.

Plus difficile : la dépense mensuelle sort de ≈ 0 € (quelques dollars, ADR-015) ; une grille
tarifaire à tenir à jour à la main ; le montant affiché est une estimation que la Console
corrige ; une limite de 20 $ partagée avec les arômes.

Coût, inclus dans le lot A1 d'ADR-015 (estimations, en lignes) :

| Partie | Serveur avec tests | Client | Règles et tests |
|---|---|---|---|
| `functions/src/ai/`, `saveAiSettings` | 900 à 1 300 | — | — |
| `ai_config/`, `ai_quotas/`, `ai_usage/` | — | — | 150 à 250 |
| Moteur d'IA | — | 450 à 650 | — |
| Coûts de l'IA, ligne de « Mon compte » | — | 300 à 450 | — |

Documents : `exigences-techniques.md` (socle, collections, règles, `saveAiSettings`, catalogue
« Coûts variables », « Réglages faits une fois »), `exigences-fonctionnelles.md` (deux écrans
d'admin, ligne de « Mon compte »), `projet.md` (IA dans l'application), `CLAUDE.md` (« Le
projet », « Structure », « Coûts variables », « Logique dupliquée », P14, P25, P35, P54 et
contrôles nouveaux), note de renvoi dans ADR-001 (arbitrage 1 remplacé), ADR-008 et ADR-013.
Aucune migration.

## Sources

- Tarifs par million de jetons (entrée / sortie) : `claude-sonnet-5-5` 2 $ / 10 $,
  `claude-opus-5-5` 4 $ / 20 $, `claude-haiku-5-5` 0,10 $ / 0,50 $, `claude-fable-5-2` 8 $ /
  40 $ : donnés par l'utilisateur le 2026-11-15. Identifiants exacts de Sonnet 5.5 et Haiku 5.5,
  tarifs du cache et efforts acceptés par chaque modèle : à vérifier sur la page des tarifs
  d'Anthropic avant la saisie de la grille.
- Limite de dépense par espace de travail et rétention de 30 jours : ADR-013.
- Six versions de secret gratuites, ≈ 0,06 $ par version de plus et par mois : ADR-008, à
  vérifier.
- Rétention par défaut de Cloud Logging (30 jours) : à vérifier.
- Kass'Dalle, relu le 2026-11-15 : `kass_dalle/functions/src/ai/usage.ts`, `pricing.ts`,
  `anthropic.ts`, `budget.ts`, `kass_dalle/firestore.rules` (`app_config`, `ai_usage`,
  `ai_daily_spend`), `kass_dalle/lib/features/admin/presentation/ai_routing_screen.dart`,
  `ai_spend_screen.dart`.
- Kass'Beer : `functions/src/config.ts`, `functions/src/auth.ts`, `functions/src/logSampler.ts`,
  `functions/package.json`, `firestore.rules`.

## Amendement du 2026-11-15 : relecture de sécurité

- **Tour rendu ou gardé** : le tour est rendu seulement sur une réponse 4xx reçue, ou sur une
  erreur de connexion avant l'envoi. Il est gardé sur un délai dépassé, un 5xx ou un 529, parce
  qu'Anthropic a pu facturer la réponse ; `failed_calls` + 1 sur le document du mois. Il est
  aussi gardé dès que le modèle a répondu.
- **Erreurs** : le client ne reçoit jamais le corps brut d'une erreur d'Anthropic, seulement
  `details.reason` et un code stable.
- **`ai_usage/{AAAA-MM}_{uid}`** : la règle `get` compare l'identifiant du document à
  `<mois>_` suivi de `request.auth.uid`. Un membre lit son mois absent sans erreur de droits, et
  le mois d'un autre lui est refusé.
- **Concurrence** : test de 20 appels simultanés au 20e tour restant, dont un seul est accepté.
