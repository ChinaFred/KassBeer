# ADR-013 — Descriptions aromatiques des houblons, rédigées par l'API Claude depuis le poste de l'admin

- **Statut** : accepté (2026-11-14)
- **Date** : 2026-11-14
- **Remplace** : — (complète ADR-005 : nouvelle collection de référence, exception à P20
  limitée à un texte généré ; complète ADR-001 : l'application reste sans IA, la génération
  vit hors de l'application ; ouvre un poste de coût variable)
- **Amendé par** : ADR-017 (2026-11-21) : moteur commun `ingest/lib/redaction/` et tarif
  commun `import/ingest/tarif.json` ; l'ancien `import/ingest/aromes/tarif.json` n'est plus lu.

Décisions de l'utilisateur du 2026-11-14 :

1. Réflexion toujours active sur `claude-fable-5-2` : aucun mode « sans réflexion », aucune
   option `--reflexion`. La profondeur se règle par `output_config.effort`. Défaut `medium`,
   comparé sur l'essai de 10 houblons ; option `--effort`.
2. Client : SDK officiel `@anthropic-ai/sdk`, construit au premier usage. Sortie par les
   sorties structurées (`output_config.format`), sans outil ni clé `tools`, sans
   préremplissage. `stop_reason == "refusal"` compté en erreur, jamais réessayé sur un autre
   modèle sans décision.
3. Compte Console Anthropic à part de l'abonnement Claude, crédit acheté, espace de travail
   Kass'Beer limité à 20 $ de dépense. Rétention des données à 30 jours (pas de ZDR) : seules
   des données publiques partent.
4. Cinq usages : `bittering`, `late_boil`, `whirlpool`, `dry_hop`, `first_wort`.
5. Ordre : essai sur 10 houblons, puis houblons des recettes du groupe (`recipes/`), puis le
   reste si l'essai convient.
6. API Batches par défaut ; appels directs pour l'essai.
7. Seuls les houblons des recettes du groupe sont relus ; les autres s'affichent « non relu ».
8. Un texte qui compare à un autre houblon (« proche du Cascade ») est permis.

Corrections du cadrage, décidées le 2026-11-14 (l'utilisateur a délégué ces choix à la session
principale) :

9. L'export JSON d'Admin n'existe pas encore. Les noms des houblons du groupe viennent d'un
   script en lecture seule, `ingest/lister-houblons-recettes.mjs` (Admin SDK, ADC), qui lit
   `recipes/*.recipe.ingredients.hop_additions[].name` et `brews/*.recipe_snapshot` (même
   chemin) et n'écrit que la liste des noms, sans identifiant de recette, de brassin ni de
   membre.
10. Les houblons des brassins comptent, y compris ceux d'une recette supprimée depuis.
11. La résolution d'un nom vers `beer_hops/{id}` passe par `IndexBibliotheque.resoudre`
    (`exchange/lib/src/resolution_import.dart`, nom et alias), comme Recettes › Importer.
    `ingredientKey` ne convient pas : il rend `houblon-<clé>`, et les documents s'appellent
    `hop-<clé>`. Zéro ou plusieurs correspondances : « non résolu », avec la raison.
12. La fiche affiche « Confiance faible » quand `confidence` vaut `low`.
13. L'essai porte sur une liste de noms donnée par l'admin (`--seulement`), résolue comme
    en 11. Liste proposée : Cascade, Citra, Mosaic, Saaz, Hallertauer Mittelfrüh, East Kent
    Golding, Magnum, Nelson Sauvin, Sorachi Ace, Bullion.

## Contexte

La Bibliothèque montre pour un houblon (`beer_hops/{id}`, 466 documents après fusion,
`DATA_SOURCES.md`, relevé du 2026-11-11) : `name`, `aliases`, `label_fr`, `form`,
`alpha_acid`, `beta_acid`, `origin`, `purpose` (`exigences-techniques.md`, « Référentiels et
recettes publiques » ; `app/lib/features/library/presentation/reference_entry_screen.dart`).
Aucun texte ne dit ce que le houblon apporte à l'amertume, au whirlpool ou au houblonnage à
cru.

L'utilisateur demande une description aromatique par usage. Il choisit qu'un modèle Claude
la rédige (`claude-fable-5-2`), par un appel à l'API facturé sur un compte de la Console
Anthropic, hors d'une session Claude Code. Il accepte le coût.

Contraintes en jeu :

- ADR-001 et `CLAUDE.md` : aucune IA dans l'application en version 1 ; une API facturée
  n'est jamais appelée depuis le client.
- ADR-005 et P20 : les référentiels gardent noms et valeurs techniques seuls, aucun `notes`,
  description ou URL d'une source. Ils sont écrits par l'ingestion seule (`allow write: if
  false`, P19).
- `ingest/ecrire.mjs` écrit chaque document en entier (`set` sans fusion) à partir de
  `import/ingest/prepare/`, produit par `exchange/bin/preparer_referentiels.dart`
  (`exigences-techniques.md`, « Écriture »). Un champ ajouté à `beer_hops/` par un autre
  outil serait effacé à la prochaine ingestion des référentiels.
- `CLAUDE.md`, « Coûts variables » : un nouveau poste arrive avec son ADR, sa ligne au
  catalogue, son nom et son plafond.
- Dépôt public (ADR-002, P15) : aucune clé, aucun texte privé.
- Un texte rendu par un modèle est une entrée non fiable : il se borne, se valide et se
  relit avant la production.
- L'abonnement Claude de l'administrateur ne couvre pas l'API. Les sessions Claude Code des
  tickets (`ticket_routine_launch`) restent sur l'abonnement ; ce poste est facturé à part.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun coût, P20 intact | la demande n'est pas servie | 0 € / 0 € |
| Textes écrits par le groupe | aucun coût d'API, textes sous contrôle | 466 textes à écrire ; écriture client à ouvrir sur un référentiel | 0 € / temps du groupe |
| A. Génération locale, collection à part `beer_hop_aromas/`, API Batches, relecture des houblons du groupe | référentiels et ingestion inchangés ; texte des houblons utilisés relu ; aucune IA dans l'application | un script de plus ; une dépendance Node ajoutée à `ingest/` | 0 € / ≈ 10 à 29 $ une fois pour 466 houblons en Batch selon l'effort, ≈ 17 $ à l'effort `medium` (section 5) |
| B. Même génération, champ `aroma` dans `beer_hops/{id}` | une seule lecture par fiche | la préparation Dart doit relire la sortie générée pour ne pas l'effacer ; `content_sha256` des référentiels change à chaque nouvelle génération ; P20 assoupli sur la collection elle-même | comme A |
| C. Option minimale : A limitée aux houblons cités par les recettes du groupe | coût et relecture divisés par le rapport des volumes | la Bibliothèque montre des fiches avec et sans texte ; nouvelle exécution à chaque houblon ajouté | 0 € / ≈ 1 à 3 $ pour 30 à 80 houblons en Batch |
| D. A avec l'outil de recherche web du modèle | moins d'invention sur les houblons rares | coût multiplié par 10 environ ; risque de recopie de textes commerciaux protégés | 0 € / ≈ 180 à 200 $, plus le prix des recherches (à vérifier) |

## Décision

Option A, dans l'ordre décidé par l'utilisateur : essai de 10 houblons en appels directs,
puis les houblons des recettes du groupe (option C) en Batch, puis le reste en Batch si
l'essai convient. Une collection à part garde l'ingestion des référentiels et P20 inchangés
pour `beer_hops/`, et le script local garde l'application sans IA.

### 1. Où vit le code

- **Génération** : `ingest/generer-aromes.mjs` et `ingest/lib/aromes/`, Node 24. Le script
  lit `import/ingest/prepare/beer_hops.json` (sortie de la préparation, valeurs techniques
  seules) et n'importe pas `firebase-admin` : il ne lit ni n'écrit Firestore.
- **Client** : SDK officiel `@anthropic-ai/sdk`, en version exacte dans
  `ingest/package.json` et `ingest/package-lock.json`. Ces deux fichiers sont dans la liste
  de P10 : le diff qui ajoute la dépendance est signalé à l'utilisateur avant la fusion.
  Le client est construit au premier appel, par un `await import()` dans une fonction qui le
  mémorise, jamais au niveau module : `ecrire.mjs` et les tests qui importent
  `ingest/lib/aromes/validation.mjs` ne chargent pas le SDK. Appels directs par
  `client.messages.create`, comptage par `client.messages.countTokens`, lots par
  `client.messages.batches.create`, `.retrieve` et `.results`.
- **Liste des houblons du groupe** (décisions 9 à 11) : `ingest/lister-houblons-recettes.mjs`
  lit `recipes/` et `brews/` en lecture seule et écrit `import/ingest/aromes/noms-houblons.json`
  (noms seuls, triés, sans doublon). Puis `exchange/bin/lister_houblons_recettes.dart` résout
  chaque nom par `IndexBibliotheque.resoudre` sur `import/ingest/prepare/beer_hops.json` et
  écrit `import/ingest/aromes/houblons-recettes.json` : identifiants résolus, et liste « non
  résolus » (nom, raison `aucun` ou `plusieurs`). La résolution reste en Dart : aucune copie
  en Node.
- **Écriture** : `ingest/ecrire.mjs`, liste blanche étendue à `beer_hop_aromas`, mêmes
  garde-fous (émulateur par défaut, `--production --projet kassbeer`, saisie du nom du
  projet, ADC `authorized_user`).
- **Pas dans `exchange/lib/`** : paquet Dart pur, importé par `app/`, sans réseau ; il n'a
  pas de SDK officiel Anthropic.

### 2. Déroulé

1. `node generer-aromes.mjs --essai 10 [--effort medium]` : estimation, confirmation,
   appels directs, sortie sous `import/ingest/aromes/brut/`. L'essai part à l'effort
   `medium`. Pour comparer, l'admin le rejoue sur les mêmes 10 houblons avec `--effort low`
   et `--effort high` ; chaque sortie garde son effort dans son nom de fichier et dans le
   rapport. L'utilisateur lit les textes, choisit l'effort retenu et ajuste le prompt.
2. `node lister-houblons-recettes.mjs` dans `ingest/`, puis
   `dart run bin/lister_houblons_recettes.dart` dans `exchange/`, puis
   `node generer-aromes.mjs --lot --seulement import/ingest/aromes/houblons-recettes.json
   --budget-usd <montant>` : lot de l'API Batches (− 50 %, résultat en 24 h au plus), repris
   par `--suivre <id du lot>`.
3. Si l'essai convient : `node generer-aromes.mjs --lot --budget-usd <montant>` pour le
   reste, découpé en plusieurs lots si la borne haute dépasse le crédit restant (section 5).
4. Contrôle de chaque réponse (section 4). Les refus vont dans `rapport.json`, avec
   l'identifiant du houblon et la raison, sans le texte.
5. Relecture des seuls houblons de `houblons-recettes.json` : le script écrit
   `import/ingest/aromes/a-relire.md` (un houblon par section, données d'entrée et texte).
   L'admin corrige `import/ingest/aromes/aromes.json` à la main et passe `reviewed` à vrai
   pour chaque entrée relue. Les autres entrées partent avec `reviewed: false`.
6. `node ecrire.mjs` (émulateur), puis en production, comme l'ingestion. `ecrire.mjs`
   refuse d'écrire une entrée d'un houblon de `houblons-recettes.json` dont `reviewed` est
   faux, et la nomme dans son rapport.

**Idempotence.** Chaque entrée porte `input_sha256` : SHA-256 du JSON canonique des champs
envoyés (nom, alias, origine, acides, usage), de `prompt_version`, du modèle et de l'effort.
Un houblon dont l'empreinte n'a pas changé n'est pas renvoyé. `--regenerer <id>` force une
entrée ; `--tout` force le lot entier et l'estimation l'affiche. Une entrée `reviewed: true`
n'est jamais écrasée par une génération : la nouvelle réponse va dans `brut/` et le rapport
la signale.

**Identifiant de requête.** `custom_id` d'un lot accepte 64 caractères
(`^[a-zA-Z0-9_-]{1,64}$`, à vérifier). Un identifiant de houblon en compte jusqu'à 104
(`hop-` et 100). Le script emploie un numéro (`h0001`…) et garde la table de
correspondance dans `import/ingest/aromes/lot-<id>.json`.

### 3. Requête envoyée

- Modèle `claude-fable-5-2`, un houblon par requête.
- Sortie au format JSON imposé par les sorties structurées : `output_config.format` porte le
  schéma JSON de la section 4. Aucune clé `tools` ni `tool_choice` (Fable 5.2 refuse
  `tool_choice` `any` et `tool`), ni `web_search`, ni `web_fetch`. Aucun message
  `assistant` prérempli (refusé par le modèle).
- Réflexion : toujours active sur ce modèle. La requête ne contient ni `thinking` ni
  `budget_tokens` (`thinking: {type: "disabled"}` et `budget_tokens` rendent une erreur
  400). La profondeur se règle par `output_config.effort`, parmi `low`, `medium`, `high`,
  `xhigh`, `max`. Défaut `medium` ; `--effort` le change, et l'estimation en tient compte.
- `max_tokens` fixé à 4 000. Il borne la réflexion et la réponse ensemble, et la borne
  haute de l'estimation. Une réponse arrêtée par `stop_reason == "max_tokens"` est comptée
  en erreur.
- `stop_reason == "refusal"` : entrée comptée en erreur dans `rapport.json` (identifiant,
  raison `refusal`, sans texte). Elle n'est jamais réessayée sur un autre modèle sans
  décision de l'utilisateur.
- Données envoyées : `name`, `aliases`, `origin`, `alpha_acid`, `beta_acid`, `purpose`. Rien
  d'autre : ni `notes` de Brewtarget (P20 : jamais lues), ni prix, ni recette, ni donnée
  d'un membre. Le modèle exige une rétention de 30 jours chez Anthropic, sans rétention
  nulle (ZDR) : seules ces données publiques partent.
- Prompt versionné (`prompt_version`, entier), écrit dans `exigences-techniques.md`,
  « Descriptions aromatiques », et lu par le script depuis `ingest/lib/aromes/prompt.mjs`.
  Il demande : un texte original en français ; aucune citation de fournisseur ou de
  catalogue ; aucune marque de bière ; `unknown` quand le modèle ne reconnaît pas le
  houblon de façon sûre ou qu'un homonyme est possible ; une confiance `high`, `medium` ou
  `low` ; des descripteurs pris dans la liste fermée seule. Une comparaison à un autre
  houblon (« proche du Cascade ») est permise.
- Partie fixe du prompt en cache (`cache_control`), pour l'essai en appels directs.

### 4. Modèle de données

`beer_hop_aromas/{id}`, `id` égal à celui du houblon dans `beer_hops/` (`hop-<clé>`).

| Champ | Contenu |
|---|---|
| `hop_name` | copie de `beer_hops/{id}.name` au moment de la génération |
| `status` | `described` ou `unknown` |
| `confidence` | `high`, `medium` ou `low` ; absent si `unknown` |
| `descriptors` | liste de 1 à 8 `{key, label}`, `key` dans la liste fermée `ingest/lib/aromes/descripteurs.json` (40 entrées environ : agrumes, pamplemousse, fruits tropicaux, fruits à noyau, fruits rouges, floral, herbacé, épicé, résineux, terreux, boisé…), `label` en français recopié de cette liste ; vide si `unknown` |
| `uses` | map aux clés `bittering` (amérisant, ébullition longue), `late_boil` (fin d'ébullition, 10 min et moins), `whirlpool`, `dry_hop` (houblonnage à cru), `first_wort` (premier moût) ; chaque valeur : `{text}` de 40 à 400 caractères, ou absente quand l'usage ne convient pas au houblon ; vide si `unknown` |
| `reviewed` | booléen, `true` après relecture de l'admin ; `false` pour un houblon hors des recettes du groupe |
| `reviewed_at` | date `AAAA-MM-JJ` de la relecture, ou absent |
| `provenance` | une ligne `{source: 'claude-api', source_id: <id>, version: 'claude-fable-5-2 / prompt <n> / effort <e>', licence: 'Texte généré pour Kass\'Beer', retrieved: <date de génération>}` |
| `input_sha256` | empreinte des entrées (section 2) |
| `content_sha256`, `updated_at` | comme les référentiels |

L'application affiche `label` tel quel : la liste fermée ne vit qu'en Node, aucune copie en
Dart (aucune ligne au tableau « Logique dupliquée »).

**Contrôle de chaque réponse**, par le générateur puis par `ecrire.mjs`, avec la même
fonction (`ingest/lib/aromes/validation.mjs`, qui n'importe pas le SDK) :

- JSON conforme au schéma, clés en liste blanche ;
- `key` dans la liste fermée, sans doublon ; `label` égal à celui de la liste ;
- clés de `uses` parmi les cinq usages ; longueurs bornées ; texte en NFC ; caractères de
  contrôle et bidirectionnels retirés ;
- refus d'un texte qui contient une URL, `www.`, `@`, du balisage (`<`, `` ` ``, `#`, `*` en
  tête de ligne), « € », « EUR », « euro », « $ » ;
- `unknown` accepté sans texte ; un `described` sans aucun usage refusé.

Un texte du modèle n'est jamais exécuté ni interprété comme une consigne.

**Règles Firestore** : `match /beer_hop_aromas/{entryId} { allow get: if isMember(); allow
write: if false; }`, tests des cinq profils de P4.

**Affichage** (fiche d'un houblon, Bibliothèque) : une section « Arômes », lue par `get` à
l'ouverture de la fiche, aucun écouteur (P22). Elle montre les descripteurs, puis un
paragraphe par usage présent, dans l'ordre premier moût, amérisant, fin d'ébullition,
whirlpool, houblonnage à cru. Sous la section : « Texte rédigé par une IA (Claude), relu le
14 novembre 2026 » (date longue, `formatDateLongue`) ou « Texte rédigé par une IA (Claude), non relu ». `unknown` : « Aucune
description : houblon trop peu documenté. ». Document absent : rien ne s'affiche, et aucune
valeur de remplacement. Document illisible : panne affichée et `reportError`.

### 5. Coût, plafond, nom du poste

Poste `hop_aroma_generation`, inscrit au catalogue « Coûts variables » de
`exigences-techniques.md`. Chaque rapport d'exécution (`import/ingest/aromes/rapport.json`)
porte ce nom, le modèle, l'effort, les jetons d'entrée et de sortie relus dans `usage`, et
le montant calculé.

Tarif de `claude-fable-5-2` : 8 $ et 40 $ par million de jetons en entrée et en sortie,
4 $ et 20 $ en Batch (grille tarifaire d'Anthropic, relevée le 2026-11-03). La réflexion
est facturée en jetons de sortie.

Hypothèses : 1 800 jetons d'entrée par houblon (prompt fixe et liste fermée 1 500, données
300). Sortie par houblon, réflexion comprise : 700 jetons à l'effort `low` (cinq textes
d'environ 250 caractères et le JSON, peu de réflexion), 1 500 à l'effort `medium`, 2 700 à
l'effort `high`. Ces volumes de réflexion sont des estimations ; l'essai de 10 houblons les
mesure par `usage`, et le rapport de l'essai remplace ces chiffres.

| Cas | Entrée | Sortie | Appels directs | Batch |
|---|---|---|---|---|
| Essai, 10 houblons, `low` | 18 000 | 7 000 | 0,42 $ | — |
| Essai, 10 houblons, `medium` | 18 000 | 15 000 | 0,74 $ | — |
| Essai, 10 houblons, `high` | 18 000 | 27 000 | 1,22 $ | — |
| 80 houblons du groupe, `medium` | 144 000 | 120 000 | 5,95 $ | 2,98 $ |
| 466 houblons, `low` | 838 800 | 326 200 | 19,76 $ | 9,88 $ |
| 466 houblons, `medium` | 838 800 | 699 000 | 34,67 $ | 17,34 $ |
| 466 houblons, `high` | 838 800 | 1 258 200 | 57,04 $ | 28,52 $ |
| 466 houblons, borne haute (`max_tokens` 4 000 atteint partout) | 838 800 | 1 864 000 | 81,27 $ | 40,64 $ |
| 466 houblons, recherche web (3 recherches de 15 000 jetons chacune) | ≈ 21 800 000 | 326 200 | ≈ 187 $, plus le prix des recherches | non retenu |

À l'effort `medium`, l'essai, les houblons du groupe et le reste en Batch coûtent environ
18 $, sous la limite de 20 $. Les efforts `high` et au-delà la dépassent pour les 466
houblons.

Plafonds, du plus fort au plus faible :

1. **Limite de dépense de l'espace de travail Kass'Beer** dans la Console Anthropic : 20 $.
   Le compte est à part de l'abonnement Claude, alimenté par un crédit acheté. C'est le seul
   plafond que le fournisseur applique.
2. **`--budget-usd`**, obligatoire hors essai : le script calcule la borne haute (nombre de
   houblons × (jetons d'entrée comptés par `countTokens` × tarif d'entrée + `max_tokens` ×
   tarif de sortie)) et refuse de partir au-delà. La borne haute des 466 houblons en Batch
   (40,64 $) dépasse 20 $ : le reste part en plusieurs lots, chacun sous le crédit restant.
3. **`--max`**, 500 houblons par lancement au plus.
4. **Confirmation** : le script affiche le nombre de houblons, le mode (direct ou Batch),
   l'effort et l'estimation, puis attend la saisie de `oui`.

Le tarif vient de `import/ingest/aromes/tarif.json` (non versionné), écrit par l'admin avec
sa date et sa source. Sans ce fichier, ou s'il a plus de 90 jours, le script affiche
« Tarif inconnu : estimation impossible » et refuse le lot. Aucun tarif n'est écrit dans le
code.

### 6. Clé

`ANTHROPIC_API_KEY`, clé de l'espace de travail Kass'Beer de la Console, distincte de celle
de Kass'Dalle. Lue dans l'environnement du poste de l'admin et passée au client à sa
construction, au premier appel. Jamais dans le dépôt, dans `import/`, dans un rapport, dans
un journal ni dans un message d'erreur ; sa valeur exacte est retirée de tout texte avant
affichage, y compris du message d'une erreur du SDK. Aucun secret Firebase ni GitHub : le
script ne tourne ni en CI ni dans les Functions.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : génération et contrôle sur le poste de l'admin
   (`ingest/`, Node 24) ; liste des houblons du groupe en Dart (`exchange/bin/`) sur le même
   poste ; écriture par `ecrire.mjs`, depuis le même poste ; lecture par l'application
   (Android et web), `get` d'un document. Aucun code dans `functions/` ni dans `app/`
   n'appelle l'API.
2. Ce qui existera en double : rien. La liste fermée des descripteurs vit dans un seul
   fichier Node ; le document porte le libellé, l'application ne fait que l'afficher. La
   fonction de contrôle est partagée par le générateur et l'écrivain, dans le même paquet.
   La résolution d'un nom de houblon reste en Dart (`IndexBibliotheque.resoudre`).
3. Ce qui pèse au démarrage : rien côté application (un `get` à l'ouverture d'une fiche).
   Le SDK ne se charge que dans `generer-aromes.mjs`, au premier appel.
4. Compilation de chaque cible : aucune dépendance Dart ajoutée ; l'APK et le web ne
   changent que par l'écran de la fiche. `ingest/` reçoit `@anthropic-ai/sdk`, contrôlé
   par `(cd ingest && npm run format:check && npm test)`.
5. Qui voit quoi : tout membre lit les descriptions ; personne n'écrit depuis un client.
   Part vers Anthropic : nom, alias, origine, acides et usage de chaque houblon, données
   publiques, gardées 30 jours par Anthropic. Ni nom de membre, ni e-mail, ni prix, ni
   recette.
6. Ce qui coûte à l'usage, plafond : poste `hop_aroma_generation`, environ 18 $ à l'effort
   `medium` pour l'ensemble (essai, groupe, reste) ; fourchette de 10 à 29 $ en Batch selon
   l'effort ; limite de 20 $ de l'espace de travail, `--budget-usd`, `--max`, confirmation.
   Lecture Firestore : 466 documents de moins de 3 Ko, dans le niveau gratuit.
7. Exposition : inchangée. Le script n'ouvre aucun point d'accès. La collection est fermée
   en écriture.
8. Exploitation, sauvegarde, mise à jour : l'admin relance le script quand un houblon arrive
   ou que le prompt change. `import/ingest/aromes/aromes.json` est la copie de référence,
   hors dépôt : à sauvegarder avec `import/`. Une correction de texte passe par ce fichier
   et `ecrire.mjs`. L'application lit le document au moment où la fiche s'ouvre. Le crédit
   de la Console se recharge à la main.
9. Coût de sortie : faible. Les textes sont des documents Firestore et un fichier JSON
   local ; changer de modèle ou de fournisseur ne touche que `ingest/lib/aromes/` et la
   dépendance de `ingest/package.json`.

## Conséquences

Plus simple : `beer_hops/`, sa préparation Dart et son empreinte ne changent pas. P20 garde
son sens pour les données des sources.

Plus difficile : une relecture humaine des houblons du groupe (30 à 80 textes). Les autres
textes sont publiés « non relu ». Un texte faux sur un houblon rare reste possible ; la
mention « non relu » et le statut `unknown` le rendent visible. Une correction depuis
l'application n'existe pas : elle demanderait une écriture admin sur une collection fermée,
et un nouvel ADR.

Un houblon ajouté plus tard à une recette du groupe garde un texte « non relu » jusqu'à la
prochaine liste et la relecture.

Le modèle peut reproduire de mémoire une formule de catalogue. Le prompt l'interdit, la
recherche web est exclue, les textes sont courts. Le risque reste non nul et se traite à la
relecture.

Documents touchés : `exigences-techniques.md` (collection, règles d'accès, prompt,
« Écriture », catalogue des coûts), `exigences-fonctionnelles.md` (fiche d'un houblon,
écran « Sources des données »), `DATA_SOURCES.md` (ligne « Descriptions aromatiques »),
`CLAUDE.md` (« Le projet », « Coûts variables », « Structure » pour
`exchange/bin/lister_houblons_recettes.dart`, P19, P20, P22, contrôles P54 et P55),
`ADR-005` (note qui renvoie ici), `guide-reseau.md` si un contrôle change.

## Sources

- Tarif de `claude-fable-5-2` : 8 $ et 40 $ par million de jetons, 4 $ et 20 $ en Batch ;
  réflexion facturée en jetons de sortie. Grille tarifaire d'Anthropic, relevée le
  2026-11-03.
- Réflexion toujours active, erreur 400 sur `thinking: {type: "disabled"}` et
  `budget_tokens`, niveaux de `output_config.effort`, refus de `tool_choice` `any` et
  `tool` et du préremplissage, rétention de 30 jours sans ZDR : décisions de l'utilisateur
  du 2026-11-14, d'après la documentation d'Anthropic.
- Remise de 50 % de l'API Batches et délai de 24 h : documentation d'Anthropic, à vérifier
  à la date de l'exécution.
- Format de `custom_id` (64 caractères) et prix de l'outil de recherche web : à vérifier.
- Volumes de réflexion par effort (800 et 2 000 jetons de plus que l'effort `low`) :
  estimation de l'architecte, mesurée par l'essai.
- Volumes : `documentation/DATA_SOURCES.md`, relevé du 2026-11-11 (466 houblons).

## Note du 2026-11-15

ADR-016 utilise le même espace de travail de la Console Anthropic, avec une seconde clé rangée
dans Secret Manager pour les Functions. La limite de 20 $ par mois est commune : quand
l'assistant de recette (ADR-015) l'atteint, la génération des arômes est bloquée aussi.
