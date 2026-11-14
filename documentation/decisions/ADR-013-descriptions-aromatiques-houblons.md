# ADR-013 — Descriptions aromatiques des houblons, rédigées par l'API Claude depuis le poste de l'admin

- **Statut** : proposé
- **Date** : 2026-11-14
- **Remplace** : — (complète ADR-005 : nouvelle collection de référence, exception à P20
  limitée à un texte généré ; complète ADR-001 : l'application reste sans IA, la génération
  vit hors de l'application ; ouvre un poste de coût variable)

## Contexte

La Bibliothèque montre pour un houblon (`beer_hops/{id}`, 466 documents après fusion,
`DATA_SOURCES.md`, relevé du 2026-11-11) : `name`, `aliases`, `label_fr`, `form`,
`alpha_acid`, `beta_acid`, `origin`, `purpose` (`exigences-techniques.md`, « Référentiels et
recettes publiques » ; `app/lib/features/library/presentation/reference_entry_screen.dart`).
Aucun texte ne dit ce que le houblon apporte à l'amertume, au whirlpool ou au houblonnage à
cru.

L'utilisateur demande une description aromatique par usage. Il choisit qu'un modèle Claude
la rédige (`claude-fable-5-2`), par un appel à l'API facturé sur son compte API Anthropic,
hors d'une session Claude Code. Il accepte le coût.

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

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun coût, P20 intact | la demande n'est pas servie | 0 € / 0 € |
| Textes écrits par le groupe | aucun coût d'API, textes sous contrôle | 466 textes à écrire ; écriture client à ouvrir sur un référentiel | 0 € / temps du groupe |
| A. Génération locale, collection à part `beer_hop_aromas/`, API Batches, relecture avant écriture | référentiels et ingestion inchangés ; une seule exécution facturée ; texte relu ; aucune IA dans l'application | un script de plus ; relecture longue (environ 450 000 caractères pour 466 houblons) | 0 € / ≈ 10 $ une fois (466 houblons, Batch, sans réflexion étendue), à vérifier |
| B. Même génération, champ `aroma` dans `beer_hops/{id}` | une seule lecture par fiche | la préparation Dart doit relire la sortie générée pour ne pas l'effacer ; `content_sha256` des référentiels change à chaque nouvelle génération ; P20 assoupli sur la collection elle-même | comme A |
| C. Option minimale : A limitée aux houblons cités par les recettes du groupe | coût et relecture divisés par le rapport des volumes | la Bibliothèque montre des fiches avec et sans texte ; nouvelle exécution à chaque houblon ajouté | 0 € / ≈ 1 à 3 $ pour 30 à 80 houblons, à vérifier |
| D. A avec l'outil de recherche web du modèle | moins d'invention sur les houblons rares | coût multiplié par 10 environ ; risque de recopie de textes commerciaux protégés | 0 € / ≈ 180 à 200 $, à vérifier |

## Décision

Option A, en commençant par un essai de 10 houblons, puis l'option C, puis le reste si
l'utilisateur le décide. Une collection à part garde l'ingestion des référentiels et P20
inchangés pour `beer_hops/`, et le script local garde l'application sans IA.

### 1. Où vit le code

- **Génération** : `ingest/generer-aromes.mjs` et `ingest/lib/aromes/`, Node 24. Le script
  lit `import/ingest/prepare/beer_hops.json` (sortie de la préparation, valeurs techniques
  seules) et n'importe pas `firebase-admin` : il ne lit ni n'écrit Firestore.
- **Client HTTP** : `fetch`, sans `@anthropic-ai/sdk`. L'API Messages et l'API Batches se
  réduisent à quatre requêtes (créer un lot, lire son état, lire ses résultats, compter les
  jetons). `ingest/package.json` ne change pas. Le SDK officiel reste une alternative ; il
  ajouterait une dépendance à un fichier de P10.
- **Écriture** : `ingest/ecrire.mjs`, liste blanche étendue à `beer_hop_aromas`, mêmes
  garde-fous (émulateur par défaut, `--production --projet kassbeer`, saisie du nom du
  projet, ADC `authorized_user`).
- **Pas dans `exchange/`** : paquet Dart pur, importé par `app/`, sans réseau ; il n'a pas
  de SDK officiel Anthropic.

### 2. Déroulé

1. `node generer-aromes.mjs --essai 10` : estimation, confirmation, appels directs,
   sortie sous `import/ingest/aromes/brut/`. L'utilisateur lit les 10 textes et ajuste le
   prompt.
2. `node generer-aromes.mjs --lot [--seulement <fichier d'identifiants>]` : lot de l'API
   Batches (− 50 %, résultat en 24 h au plus), repris par `--suivre <id du lot>`.
3. Contrôle de chaque réponse (section 4). Les refus vont dans `rapport.json`, avec
   l'identifiant du houblon et la raison, sans le texte.
4. Relecture : le script écrit `import/ingest/aromes/a-relire.md` (un houblon par section,
   données d'entrée et texte). L'admin corrige `import/ingest/aromes/aromes.json` à la main
   et passe `reviewed` à vrai pour chaque entrée relue.
5. `node ecrire.mjs` (émulateur), puis en production, comme l'ingestion.

**Idempotence.** Chaque entrée porte `input_sha256` : SHA-256 du JSON canonique des champs
envoyés (nom, alias, origine, acides, usage), de `prompt_version` et du modèle. Un houblon
dont l'empreinte n'a pas changé n'est pas renvoyé. `--regenerer <id>` force une entrée ;
`--tout` force le lot entier et l'estimation l'affiche. Une entrée `reviewed: true` n'est
jamais écrasée par une génération : la nouvelle réponse va dans `brut/` et le rapport la
signale.

**Identifiant de requête.** `custom_id` d'un lot accepte 64 caractères
(`^[a-zA-Z0-9_-]{1,64}$`, à vérifier). Un identifiant de houblon en compte jusqu'à 104
(`hop-` et 100). Le script emploie un numéro (`h0001`…) et garde la table de
correspondance dans `import/ingest/aromes/lot-<id>.json`.

### 3. Requête envoyée

- Modèle `claude-fable-5-2`, un houblon par requête, sortie structurée (schéma JSON de la
  section 4).
- Données envoyées : `name`, `aliases`, `origin`, `alpha_acid`, `beta_acid`, `purpose`. Rien
  d'autre : ni `notes` de Brewtarget (P20 : jamais lues), ni prix, ni donnée d'un membre.
- Prompt versionné (`prompt_version`, entier), écrit dans `exigences-techniques.md`,
  « Descriptions aromatiques », et lu par le script depuis `ingest/lib/aromes/prompt.mjs`.
  Il demande : un texte original en français ; aucune citation de fournisseur ou de
  catalogue ; aucune marque de bière ; `unknown` quand le modèle ne reconnaît pas le
  houblon de façon sûre ou qu'un homonyme est possible ; une confiance `high`, `medium` ou
  `low` ; des descripteurs pris dans la liste fermée seule.
- Aucun outil : ni `web_search`, ni `web_fetch`. La requête ne contient pas de clé `tools`.
- Partie fixe du prompt en cache (`cache_control`), pour l'essai en appels directs.
- Réflexion étendue désactivée par défaut ; `--reflexion` l'active, et l'estimation en tient
  compte.
- `max_tokens` fixé (1 500 sans réflexion), qui borne la sortie et l'estimation haute.

### 4. Modèle de données

`beer_hop_aromas/{id}`, `id` égal à celui du houblon dans `beer_hops/` (`hop-<clé>`).

| Champ | Contenu |
|---|---|
| `hop_name` | copie de `beer_hops/{id}.name` au moment de la génération |
| `status` | `described` ou `unknown` |
| `confidence` | `high`, `medium` ou `low` ; absent si `unknown` |
| `descriptors` | liste de 1 à 8 `{key, label}`, `key` dans la liste fermée `ingest/lib/aromes/descripteurs.json` (40 entrées environ : agrumes, pamplemousse, fruits tropicaux, fruits à noyau, fruits rouges, floral, herbacé, épicé, résineux, terreux, boisé…), `label` en français recopié de cette liste ; vide si `unknown` |
| `uses` | map aux clés `bittering` (amertume, ébullition longue), `late_boil` (10 min et moins), `whirlpool`, `dry_hop` ; chaque valeur : `{text}` de 40 à 400 caractères, ou absente quand l'usage ne convient pas au houblon ; vide si `unknown` |
| `reviewed` | booléen, `true` après relecture de l'admin |
| `reviewed_at` | date `AAAA-MM-JJ` de la relecture, ou absent |
| `provenance` | une ligne `{source: 'claude-api', source_id: <id>, version: 'claude-fable-5-2 / prompt <n>', licence: 'Texte généré pour Kass\'Beer', retrieved: <date de génération>}` |
| `input_sha256` | empreinte des entrées (section 2) |
| `content_sha256`, `updated_at` | comme les référentiels |

L'application affiche `label` tel quel : la liste fermée ne vit qu'en Node, aucune copie en
Dart (aucune ligne au tableau « Logique dupliquée »).

**Contrôle de chaque réponse**, par le générateur puis par `ecrire.mjs`, avec la même
fonction (`ingest/lib/aromes/validation.mjs`) :

- JSON conforme au schéma, clés en liste blanche ;
- `key` dans la liste fermée, sans doublon ; `label` égal à celui de la liste ;
- longueurs bornées ; texte en NFC ; caractères de contrôle et bidirectionnels retirés ;
- refus d'un texte qui contient une URL, `www.`, `@`, du balisage (`<`, `` ` ``, `#`, `*` en
  tête de ligne), « € », « EUR », « euro », « $ », ou un nom de houblon absent de
  `name` et `aliases` (liste tirée de `beer_index/hops`) ;
- `unknown` accepté sans texte ; un `described` sans aucun usage refusé.

Un texte du modèle n'est jamais exécuté ni interprété comme une consigne.

**Règles Firestore** : `match /beer_hop_aromas/{entryId} { allow get: if isMember(); allow
write: if false; }`, tests des cinq profils de P4.

**Affichage** (fiche d'un houblon, Bibliothèque) : une section « Arômes », lue par `get` à
l'ouverture de la fiche, aucun écouteur (P22). Elle montre les descripteurs, puis un
paragraphe par usage présent. Sous la section : « Texte rédigé par une IA (Claude), relu
le JJ/MM/AAAA » ou « Texte rédigé par une IA (Claude), non relu ». `unknown` : « Aucune
description : houblon trop peu documenté. ». Document absent : rien ne s'affiche, et aucune
valeur de remplacement. Document illisible : panne affichée et `reportError`.

### 5. Coût, plafond, nom du poste

Poste `hop_aroma_generation`, inscrit au catalogue « Coûts variables » de
`exigences-techniques.md`. Chaque rapport d'exécution (`import/ingest/aromes/rapport.json`)
porte ce nom, le modèle, les jetons d'entrée et de sortie relus dans `usage`, et le montant
calculé.

Estimation pour 466 houblons, tarif de `claude-fable-5-2` de 8 $ et 40 $ par million de
jetons en entrée et en sortie, 4 $ et 20 $ en Batch (sources tierces, à vérifier sur la page
d'Anthropic). Hypothèses : 1 800 jetons d'entrée par houblon (prompt fixe et liste fermée
1 500, données 300) ; 700 jetons de sortie sans réflexion (quatre textes de 300 caractères
en français et le JSON) ; 2 000 jetons de réflexion en plus avec `--reflexion`.

| Cas | Entrée | Sortie | Appels directs | Batch |
|---|---|---|---|---|
| Essai, 10 houblons, sans réflexion | 18 000 | 7 000 | 0,42 $ | — |
| 466 houblons, sans réflexion | 838 800 | 326 200 | 19,76 $ | 9,88 $ |
| 466 houblons, avec réflexion | 838 800 | 1 258 200 | 57,04 $ | 28,52 $ |
| 466 houblons, borne haute (`max_tokens` 1 500 atteint partout) | 838 800 | 699 000 | 34,67 $ | 17,34 $ |
| 466 houblons, recherche web (3 recherches de 15 000 jetons chacune) | ≈ 21 800 000 | 326 200 | ≈ 187 $, plus le prix des recherches | non retenu |

Plafonds, du plus fort au plus faible :

1. **Limite de dépense du compte API**, réglée par l'utilisateur dans la Console
   Anthropic, sur un espace de travail réservé à Kass'Beer (montant à choisir, par exemple
   40 $ par mois). C'est le seul plafond que le fournisseur applique.
2. **`--budget-usd`**, obligatoire hors essai : le script calcule la borne haute (nombre de
   houblons × (jetons d'entrée comptés par `count_tokens` × tarif d'entrée + `max_tokens` ×
   tarif de sortie)) et refuse de partir au-delà.
3. **`--max`**, 500 houblons par lancement au plus.
4. **Confirmation** : le script affiche le nombre de houblons, le mode (direct ou Batch) et
   l'estimation, puis attend la saisie de `oui`.

Le tarif vient de `import/ingest/aromes/tarif.json` (non versionné), écrit par l'admin avec
sa date et sa source. Sans ce fichier, ou s'il a plus de 90 jours, le script affiche
« Tarif inconnu : estimation impossible » et refuse le lot. Aucun tarif n'est écrit dans le
code.

### 6. Clé

`ANTHROPIC_API_KEY`, lue dans l'environnement du poste de l'admin, au premier appel. Jamais
dans le dépôt, dans `import/`, dans un rapport, dans un journal ni dans un message
d'erreur ; sa valeur exacte est retirée de tout texte avant affichage. Aucun secret Firebase
ni GitHub : le script ne tourne ni en CI ni dans les Functions. Clé propre à l'espace de
travail Kass'Beer, distincte de celle de Kass'Dalle.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : génération et contrôle sur le poste de l'admin
   (`ingest/`, Node 24) ; écriture par `ecrire.mjs`, depuis le même poste ; lecture par
   l'application (Android et web), `get` d'un document. Aucun code dans `functions/` ni
   dans `app/` n'appelle l'API.
2. Ce qui existera en double : rien. La liste fermée des descripteurs vit dans un seul
   fichier Node ; le document porte le libellé, l'application ne fait que l'afficher. La
   fonction de contrôle est partagée par le générateur et l'écrivain, dans le même paquet.
3. Ce qui pèse au démarrage : rien côté application (un `get` à l'ouverture d'une fiche).
   Aucun SDK ajouté.
4. Compilation de chaque cible : aucune dépendance Dart ni Node ajoutée ; l'APK et le web
   ne changent que par l'écran de la fiche.
5. Qui voit quoi : tout membre lit les descriptions ; personne n'écrit depuis un client.
   Part vers Anthropic : nom, alias, origine, acides et usage de chaque houblon, données
   publiques. Ni nom de membre, ni e-mail, ni prix, ni recette. Les conditions d'usage des
   données de l'API sont à relire par l'utilisateur (rétention, entraînement).
6. Ce qui coûte à l'usage, plafond : poste `hop_aroma_generation`, environ 10 $ en Batch
   pour 466 houblons sans réflexion, 0,42 $ pour l'essai (à vérifier) ; plafond de la
   Console, `--budget-usd`, `--max`, confirmation. Lecture Firestore : 466 documents de
   moins de 3 Ko, dans le niveau gratuit.
7. Exposition : inchangée. Le script n'ouvre aucun point d'accès. La collection est fermée
   en écriture.
8. Exploitation, sauvegarde, mise à jour : l'admin relance le script quand un houblon arrive
   ou que le prompt change. `import/ingest/aromes/aromes.json` est la copie de référence,
   hors dépôt : à sauvegarder avec `import/`. Une correction de texte passe par ce fichier
   et `ecrire.mjs`. L'application lit le document au moment où la fiche s'ouvre.
9. Coût de sortie : faible. Les textes sont des documents Firestore et un fichier JSON
   local ; changer de modèle ou de fournisseur ne touche que `ingest/lib/aromes/`.

## Conséquences

Plus simple : `beer_hops/`, sa préparation Dart et son empreinte ne changent pas. P20 garde
son sens pour les données des sources.

Plus difficile : une relecture humaine de 466 textes. Un texte faux sur un houblon rare
reste possible ; la mention « non relu » et le statut `unknown` le rendent visible. Une
correction depuis l'application n'existe pas : elle demanderait une écriture admin sur une
collection fermée, et un nouvel ADR.

Le modèle peut reproduire de mémoire une formule de catalogue. Le prompt l'interdit, la
recherche web est exclue, les textes sont courts. Le risque reste non nul et se traite à la
relecture.

Documents touchés : `exigences-techniques.md` (collection, règles d'accès, prompt,
« Écriture », catalogue des coûts), `exigences-fonctionnelles.md` (fiche d'un houblon,
écran « Sources des données »), `DATA_SOURCES.md` (ligne « Descriptions aromatiques »),
`CLAUDE.md` (« Le projet », « Coûts variables », P19, P20, P22, nouveau contrôle),
`ADR-005` (note qui renvoie ici), `guide-reseau.md` si un contrôle change.

## Sources

- Tarif de `claude-fable-5-2` : 8 $ et 40 $ par million de jetons, 4 $ et 20 $ en Batch.
  Sources tierces, consultées le 2026-11-14 : techjacksolutions.com
  (« claude-fable-5-2 pricing and api »), productbuilder.net (« claude-fable-5-2 »),
  braindetox.kr (« Claude Fable 5.2 and Mythos 5.2 »). Page officielle d'Anthropic non
  consultée : à vérifier.
- Remise de 50 % de l'API Batches et délai de 24 h : documentation d'Anthropic, à vérifier
  à la date de l'exécution.
- Format de `custom_id` (64 caractères) et prix de l'outil de recherche web : à vérifier.
- Volumes : `documentation/DATA_SOURCES.md`, relevé du 2026-11-11 (466 houblons).
