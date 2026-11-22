# ADR-017 — Descriptions aromatiques des levures, sur le modèle d'ADR-013

- **Statut** : accepté le 2026-11-21
- **Date** : 2026-11-21
- **Remplace** : — (étend ADR-013 aux levures ; complète ADR-005 : nouvelle collection de
  référence, exception à P20 limitée à un texte généré ; amende ADR-014 : `--supprimer-absents`
  accepte `beer_culture_aromas` ; ouvre le poste de coût `culture_aroma_generation` ; relève pour
  un temps la limite de dépense commune d'ADR-013 et ADR-016)

Décision de l'utilisateur du 2026-11-21, relayée par la session principale : il accepte de
relever la limite de 20 $ par mois de l'espace de travail Kass'Beer de la Console Anthropic si
le lot l'exige. Montant et durée : section 6.

Décisions de l'utilisateur du 2026-11-21, après l'avis :

1. Périmètre : 923 levures. Toutes les levures des recettes du groupe, plus les types `ale`,
   `lager`, `wheat`, `kveik`, `brett`, `lacto`, `pedio`, `mixed-culture`, `bacteria` (mélanges
   pour bières acides) et les levures sans type. Les types `other`, `wine`, `champagne` et
   `malolactic` (37 levures de vin, cidre, hydromel et saké) restent sans texte, sauf une levure
   du groupe.
2. Effort : celui retenu pour les houblons (`import/ingest/aromes/rapport.json`), un seul essai.
3. Limite de la Console : 70 $ jusqu'à la fin du dernier lot, au plus tard le 30 novembre 2026,
   puis retour à 20 $.
4. Contenu : descripteurs, `profile`, `cool`, `warm` et styles conseillés (section 4).
5. Liste des 32 descripteurs acceptée telle quelle.
6. Essai : US-05, S-04, W-34/70, WLP001, Wyeast 3068, Wyeast 3944, Wyeast 3711, Wyeast 1968,
   Voss Kveik et une Brettanomyces.
7. Doublons d'un même producteur : un texte par document (section 5).
8. Évolutions du réseau acceptées : P19, P20, P22 et P54 étendus, nouveau P62, puce dans
   « Le projet », quatrième poste dans « Coûts variables » de `CLAUDE.md`.

## Contexte

La fiche d'une levure de la Bibliothèque (`beer_cultures/{id}`, 960 documents après la v0.1.86,
`DATA_SOURCES.md`) montre `name`, `aliases`, `type`, `form`, `producer`, `product_id`,
`attenuation` (plage `%`), `temperature_range` (plage `C`) et `flocculation`
(`exigences-techniques.md`, tableau des référentiels ; `FicheLevure` dans
`app/lib/features/library/domain/referentiel.dart`). Aucun texte ne dit ce que la levure
apporte au goût. P20 l'interdit pour les données des sources : les descriptions, notes de
dégustation et styles conseillés des fiches des fabricants ont été écartés (`DATA_SOURCES.md`,
colonnes « Écarté »). Aucune source ne donne la tolérance à l'alcool : le champ n'existe pas.

Les houblons ont un texte depuis ADR-013 (`beer_hop_aromas/`, `ingest/generer-aromes.mjs`,
`ingest/lib/aromes/`). L'utilisateur demande la même chose pour les levures, vite : il dispose
d'un crédit jusqu'au 30 novembre 2026.

Contraintes en jeu :

- ADR-013 : génération sur le poste de l'admin, collection à part, relecture des ingrédients
  du groupe, poste de coût nommé, tarif hors du code, `--budget-usd`, `--max`, confirmation.
- ADR-014 : les identifiants de `beer_cultures/` changent quand une fusion regroupe des souches
  (29 identifiants sortis à la v0.1.81, 12 à la v0.1.82, 1 à la v0.1.86). Une description rangée
  sous un identifiant absorbé devient orpheline.
- ADR-016 : même espace de travail de la Console ; la limite de 20 $ par mois est commune avec
  `hop_aroma_generation` et `recipe_assistant_turn`.
- Le code d'ADR-013 est propre aux houblons : `ID_HOUBLON`, `lireHoublons`, `hop_name`,
  `USAGES`, `COLLECTION_AROMES = "beer_hop_aromas"`, `POSTE` (`ingest/lib/aromes/generation.mjs`,
  `validation.mjs`, `tarif.mjs`).
- Une ligne de levure d'une recette ne porte que `name`, `type`, `form`, `attenuation` et
  `amount` (`YeastLine`, `app/lib/features/recipes/domain/recipe.dart`) : ni producteur ni
  référence. La résolution d'une levure du groupe se fait par le nom seul.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun coût, P20 intact | la demande n'est pas servie ; le crédit expire le 30 novembre | 0 € / 0 € |
| A. Collection à part `beer_culture_aromas/`, même script avec `--nature culture`, schéma propre aux levures (retenue) | `beer_hop_aromas/`, son lecteur Dart, P55 et l'assistant inchangés ; moteur commun (tarif, lots, idempotence, confirmation) écrit une fois | une collection, un lecteur Dart et un contrôle de plus | 0 € / ≈ 40 $ une fois pour 960 levures en Batch à l'effort `medium` (section 6) |
| B. Collection unique `beer_aromas/{id}` pour les deux natures | une seule règle, un seul lecteur | migration des 466 documents de `beer_hop_aromas/` ; `AromesHoublon`, `section_aromes.dart`, `aromesPourAssistant`, P55, `--supprimer-absents beer_hop_aromas` et les tests des règles changent ; deux schémas dans un seul document | comme A, plus la migration |
| C. Second script `generer-aromes-levures.mjs` | aucun risque sur le code des houblons | copie du moteur (≈ 800 lignes) : deux implémentations du tarif, des lots et de l'idempotence qui divergent | comme A |
| D. Option moins lourde : A limitée aux levures des recettes du groupe | ≈ 1 à 3 $, sous la limite de 20 $ ; relecture complète | la Bibliothèque montre des fiches avec et sans texte | 0 € / ≈ 1,25 $ pour 30 levures |

## Décision

Option A. Le moteur d'ADR-013 reçoit une nature (`hop` par défaut, `culture`) ; chaque nature
a sa collection, son schéma, sa liste de descripteurs, son prompt, ses données envoyées et son
poste de coût. L'ordre suit ADR-013 : essai de 10 levures, puis les levures du groupe relues,
puis le reste dans le périmètre décidé par l'utilisateur.

### 1. Où vit le code

- **Génération** : `ingest/generer-aromes.mjs --nature culture`. Sans `--nature`, la nature est
  `hop` : les commandes actuelles de `CLAUDE.md` gardent leur effet. Le moteur commun reste dans
  `ingest/lib/aromes/` (client, tarif, lots, sélection, confirmation). Ce qui dépend de la
  nature va dans `ingest/lib/aromes/natures/hop.mjs` et `ingest/lib/aromes/natures/culture.mjs` :
  fichier préparé lu, motif d'identifiant (`^culture-[a-z0-9]+(-[a-z0-9]+)*$`), collection,
  poste, `donneesEnvoyees`, prompt, schéma de sortie, fonction de contrôle, liste des
  descripteurs, sections de `a-relire.md`. Aucune dépendance ajoutée à `ingest/package.json`.
  Note du 2026-11-21 (livraison 1, v0.1.93) : le prompt et le contrôle des houblons restent
  dans `ingest/lib/aromes/prompt.mjs` et `ingest/lib/aromes/validation.mjs`, nommés par P55 ;
  `natures/hop.mjs` les reprend sans les déplacer.
- **Fichiers** : `import/ingest/aromes/levures/` (jamais versionné) : `aromes.json`,
  `levures-recettes.json`, `noms-levures.json`, `rapport.json`, `a-relire.md`, `brut/`,
  `lot-<id>.json`. Le tarif reste `import/ingest/aromes/tarif.json`, commun aux deux natures
  (même modèle).
- **Liste des levures du groupe** : `ingest/lister-houblons-recettes.mjs` devient
  `ingest/lister-ingredients-recettes.mjs --nature hop|culture`, et
  `exchange/bin/lister_houblons_recettes.dart` devient `lister_ingredients_recettes.dart`, dans
  le même changement (aucun ancien nom gardé). Pour `culture`, le script Node lit
  `recipes/*.recipe.ingredients.culture_additions[].name` et
  `brews/*.recipe_snapshot.recipe.ingredients.culture_additions[].name` par `select`, en lecture
  seule, et n'écrit que les noms. Le script Dart résout chaque nom par
  `IndexBibliotheque.resoudre` sur `beer_cultures.json` (nom, alias, souche lue dans le nom,
  référence, producteur et référence : `exchange/lib/src/resolution_import.dart`). Un nom non
  résolu (`aucun` ou `plusieurs`) est listé avec ses candidats
  (`IndexBibliotheque.candidats`). L'admin peut ajouter à la main un identifiant à
  `resolus`, avec le nom d'origine.
- **Écriture** : `ingest/ecrire.mjs` lit aussi `import/ingest/aromes/levures/aromes.json` et
  écrit `beer_culture_aromas/`, mêmes garde-fous. Il refuse une entrée dont l'identifiant manque
  à `beer_cultures.json` préparé, une entrée du groupe dont `reviewed` est faux, et une entrée
  dont un code de style manque à `beer_styles.json` préparé.
- **Application** : `app/lib/features/library/domain/aromes_levure.dart` (lecture stricte,
  comme `aromes_houblon.dart`), section « Arômes » de la fiche d'une levure, ligne de l'écran
  « Sources des données ». Rien dans `exchange/lib/`, rien dans `functions/`.

### 2. Données envoyées

`name`, `aliases`, `producer`, `product_id`, `type`, `form`, `attenuation_pct` (plage
`[min, max]`), `temperature_c` (plage `[min, max]`), `flocculation`, inconnus à `null`. Rien
d'autre : aucun `notes`, aucune `provenance`, aucun prix, aucune recette, aucune donnée de
membre. Ce sont des données publiques ; la rétention de 30 jours d'ADR-013 s'applique.

### 3. Requête

Comme ADR-013, section 3 : `claude-fable-5-2`, une levure par requête, sorties structurées,
aucune clé `tools`, `tool_choice`, `thinking` ou `budget_tokens`, aucun message `assistant`,
`max_tokens` 4 000, effort par `output_config.effort`, `refusal` et `max_tokens` comptés en
erreur sans second appel, partie fixe en cache en appels directs. `custom_id` en `c0001`…

Prompt propre aux levures, versionné (`prompt_version` de la nature `culture`, à partir de 1),
recopié dans `exigences-techniques.md`. Il demande en plus des règles d'ADR-013 :

- `unknown` quand la souche n'est pas reconnue de façon sûre, en particulier quand le nom est
  porté par plusieurs souches et que la référence manque ;
- aucun chiffre absent des données (ni température, ni atténuation, ni taux d'alcool) ;
- des styles conseillés pris dans la liste fermée des styles BJCP 2021 donnée par le prompt
  (codes et noms de `beer_styles.json` préparé), aucun autre.

L'empreinte `input_sha256` couvre les données envoyées, `prompt_version`, le modèle, l'effort
et le SHA-256 de la liste des styles du prompt : un changement de `beer_styles` fait régénérer.

### 4. Modèle de données

`beer_culture_aromas/{id}`, `id` égal à celui de la levure (`culture-<clé>`).

| Champ | Contenu |
|---|---|
| `culture_name` | copie de `beer_cultures/{id}.name` à la génération |
| `status` | `described` ou `unknown` |
| `confidence` | `high`, `medium` ou `low` ; absent si `unknown` |
| `descriptors` | 1 à 8 `{key, label}`, `key` dans `ingest/lib/aromes/descripteurs-levures.json`, `label` recopié de cette liste ; vide si `unknown` |
| `texts` | map aux clés `profile` (profil général, obligatoire si `described`), `cool` (bas de la plage de température), `warm` (haut de la plage) ; chaque valeur `{text}` de 40 à 400 caractères, `cool` et `warm` absents quand la levure ne change pas de profil ; vide si `unknown` |
| `styles` | 0 à 6 `{code, name}`, `code` présent dans `beer_styles.json` préparé (`bjcp2021-<code>`), `name` recopié du style ; vide si `unknown` |
| `reviewed`, `reviewed_at`, `provenance`, `input_sha256`, `content_sha256`, `updated_at` | comme `beer_hop_aromas/` (ADR-013, section 4) |

Liste des descripteurs (32 entrées, clé : libellé), acceptée par l'utilisateur le 2026-11-21 :
`clean` neutre, `fruity_esters` esters fruités, `banana` banane, `pear` poire, `apple` pomme,
`stone_fruit` fruits à noyau, `citrus` agrumes, `tropical_fruit` fruits tropicaux,
`red_berries` fruits rouges, `bubblegum` bonbon, `floral` floral, `clove` clou de girofle,
`pepper` poivre, `spicy` épicé, `smoky` fumé, `sulfur` soufre, `mineral` minéral,
`diacetyl` beurre (diacétyle), `bready` pain, `malty` malté, `honey` miel, `earthy` terreux,
`barnyard` écurie, `leather` cuir, `lactic_sour` acidité lactique, `acetic` acidité acétique,
`vinous` vineux, `dry` sec, `full_body` rond, `residual_sweetness` douceur résiduelle,
`tart` acidulé, `funky` sauvage.

**Contrôle de chaque réponse** (`ingest/lib/aromes/natures/culture.mjs`, sans le SDK, partagé
par le générateur et `ecrire.mjs`) : clés en liste blanche ; descripteurs comme P55 ; clés de
`texts` parmi les trois ; `profile` présent pour un `described` ; textes nettoyés et refusés
comme P55 (NFC, contrôles et bidirectionnels, URL, `www.`, `@`, balisage, « € », « EUR »,
« euro », « $ ») ; styles sans doublon, codes présents dans la liste, 6 au plus.

**Règles Firestore** : `match /beer_culture_aromas/{entryId} { allow get: if isMember(); allow
list, write: if false; }`, tests des cinq profils de P4.

**Affichage** (fiche d'une levure) : section « Arômes » lue par `get` à l'ouverture, aucun
écouteur (P22) : descripteurs, « Profil », « En bas de plage », « En haut de plage », « Styles
conseillés » (noms stockés, aucune liste de styles en Dart). Mention et états comme P55 :
« Texte rédigé par une IA (Claude), relu le <date longue> » ou « …, non relu », « Confiance
faible », « Aucune description : levure trop peu documentée. », document absent sans valeur de
remplacement, document illisible en panne avec `reportError`. L'assistant de recette ne lit pas
ces textes : l'ajouter changerait le bloc `AROMES` et ses bornes (P59), donc un autre ADR.

### 5. Doublons d'un même producteur

Quatre noms désignent deux souches d'un même producteur (`belgian-ale`, `belgian-wit`,
`safale-american-ale`, `scottish-ale`, `DATA_SOURCES.md`, mesure du 2026-11-21), soit
8 documents. Un texte par document : chaque document est une souche distincte (M27 et M41,
US-05 et US-56…), et `product_id` part avec les données. Une ligne de recette qui ne donne que
« Belgian Ale » ne se résout pas (`plusieurs`) ; l'admin choisit l'identifiant à la main. Quand
la fusion de ces noms arrivera (ADR-014), un identifiant absorbé sort de la préparation ;
`ecrire.mjs --supprimer-absents beer_culture_aromas` retire sa description, et la souche gardée
reçoit un texte « nouveau » ou « changé » au lancement suivant.

`--supprimer-absents` accepte `beer_culture_aromas` (amendement d'ADR-014), dans les mêmes
bornes que `beer_hop_aromas` : simulation d'abord, 30 au plus, seuil de 90 %, saisie du nombre ;
la liste de référence est `levures/aromes.json`. Une description relue dont l'identifiant
change perd sa relecture : le rapport de `ecrire.mjs` liste les entrées `reviewed: true`
absentes de `beer_cultures.json`.

### 6. Coût, plafond, nom du poste, limite de la Console

Poste `culture_aroma_generation`, inscrit au catalogue « Coûts variables » de
`exigences-techniques.md`. Chaque `rapport.json` de `levures/` porte ce nom, le modèle,
l'effort, `usage` et le montant.

Tarif de `claude-fable-5-2` : 8 $ et 40 $ par million de jetons, 4 $ et 20 $ en Batch (ADR-013,
relevé du 2026-11-03 ; confirmé par l'utilisateur le 2026-11-15, ADR-016). À relire sur la
grille d'Anthropic avant le lot.

Les jetons mesurés par l'essai des houblons sont dans `import/ingest/aromes/rapport.json`, hors
du dépôt. Le dépôt ne les note pas : l'estimation ci-dessous reprend les hypothèses d'ADR-013
et reste à remplacer par la mesure de l'essai. Entrée : 2 800 jetons par levure (prompt fixe,
liste des descripteurs et liste des 110 styles 2 500, données 300). Sortie, réflexion comprise :
700 (`low`), 1 500 (`medium`), 2 700 (`high`).

| Cas | Appels directs | Batch |
|---|---|---|
| Essai, 10 levures, `medium` | 0,82 $ | — |
| 30 levures du groupe, `medium` | 2,47 $ | 1,24 $ |
| 960 levures, `low` | 48,38 $ | 24,19 $ |
| 960 levures, `medium` | 79,10 $ | 39,55 $ |
| 960 levures, `high` | 125,18 $ | 62,59 $ |
| 960 levures, borne haute (`max_tokens` partout) | 175,10 $ | 87,55 $ |

Plafonds : limite de dépense de l'espace de travail (ci-dessous) ; `--budget-usd` obligatoire
hors essai, contre la borne haute (≈ 0,091 $ par levure en Batch) ; `--max` 500 par lancement,
donc deux lots au moins pour 960 levures (porté à 1 000 le 2026-11-22, voir la note ci-dessous) ; 20 levures au plus en appels directs ; confirmation
par `oui`.

**Limite de la Console.** Le lot entier à l'effort `medium` (≈ 40 $) dépasse 20 $, et la
dépense de novembre compte déjà les houblons et l'assistant. Proposition : relever la limite de
l'espace de travail Kass'Beer à **70 $** (dépense de novembre au plus 20 $, lot ≈ 40 $, marge
de 10 $ pour les réponses à relancer) avant le premier lot, et la **ramener à 20 $ dès la fin du
dernier lot**, au plus tard le 30 novembre 2026. À l'effort `high`, le montant est 90 $. Si la
limite est atteinte pendant un lot, les appels suivants sont refusés : le lot rend ses
manquants « à relancer », et l'assistant de recette répond « Crédit de l'IA épuisé pour ce
mois. » jusqu'au relèvement ou au 1er décembre (ADR-016, section 10). Le comportement exact d'un
lot de l'API Batches qui atteint la limite est à vérifier.

### 7. Livraison

Deux livraisons, pour que la génération parte avant le 30 novembre :

1. `ingest/`, `exchange/bin/`, `firestore.rules`, `rules-tests/` et la documentation : la
   génération, la relecture et l'écriture sont possibles dès cette livraison.
2. `app/` : section « Arômes » de la fiche d'une levure, ligne de « Sources des données ».

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : génération, contrôle, liste des levures du groupe et
   écriture sur le poste de l'admin (`ingest/`, `exchange/bin/`) ; lecture par l'application,
   `get` d'un document. Aucun appel à l'API depuis `app/` ni `functions/`.
2. Ce qui existera en double : rien entre client et serveur. Le moteur de génération est commun
   aux deux natures. La liste des descripteurs et la liste des styles du prompt vivent en Node
   seul ; le document porte les libellés et les noms de styles. La résolution d'un nom reste en
   Dart. Deux lecteurs Dart à part (`aromes_houblon.dart`, `aromes_levure.dart`) lisent deux
   schémas différents.
3. Ce qui pèse au démarrage : rien côté application ; le SDK se charge au premier appel du
   générateur, comme ADR-013.
4. Compilation de chaque cible : aucune dépendance ajoutée ; l'APK et le web changent par la
   fiche d'une levure (livraison 2).
5. Qui voit quoi : tout membre lit les descriptions, personne n'écrit depuis un client. Part
   vers Anthropic : les champs techniques publics de la section 2.
6. Ce qui coûte à l'usage, plafond : poste `culture_aroma_generation`, ≈ 40 $ une fois pour
   960 levures à l'effort `medium` en Batch, ≈ 1,25 $ pour le groupe ; limite relevée à 70 $
   pour le temps du lot, `--budget-usd`, `--max`, confirmation. Lecture Firestore : un `get` par
   fiche ouverte, dans le niveau gratuit.
7. Exposition : inchangée. Collection fermée en écriture, aucun point d'accès.
8. Exploitation : `import/ingest/aromes/levures/aromes.json` est la copie de référence, à
   sauvegarder avec `import/`. L'admin relance la génération quand une levure arrive, change
   d'identifiant ou que le prompt change. La limite de la Console se remet à 20 $ à la main.
9. Coût de sortie : faible, comme ADR-013.

## Conséquences

Plus simple : `beer_cultures/` et sa préparation ne changent pas ; `beer_hop_aromas/` non plus.
Le moteur de génération sert une troisième nature au prix d'un fichier de nature.

Plus difficile : une relecture des levures du groupe ; un texte faux reste possible sur une
souche rare, rendu visible par « non relu » et `unknown`. Les fabricants publient des
descriptions courtes et très reprises : le risque qu'un texte reformule de près une fiche de
fabricant est plus haut que pour les houblons. Le prompt l'interdit, les textes sont courts, la
relecture le traite pour le groupe. Une fusion d'ADR-014 fait perdre la relecture d'une souche
absorbée.

Documents touchés : `exigences-techniques.md` (collection, règles, prompt, « Écriture »,
catalogue des coûts, limite), `exigences-fonctionnelles.md` (fiche d'une levure, « Sources des
données »), `DATA_SOURCES.md` (ligne « Descriptions aromatiques des levures »), `CLAUDE.md`
(« Le projet », « Structure », « Commandes utiles », P19, P20, P22, P54, P55, nouveau P62,
« Coûts variables »), notes de renvoi dans ADR-005, ADR-013, ADR-014 et ADR-016,
`CHANGELOG.md`.

## Sources

- Tarif de `claude-fable-5-2` : ADR-013 (grille d'Anthropic relevée le 2026-11-03) et ADR-016
  (donné par l'utilisateur le 2026-11-15). À relire avant le lot.
- Remise de 50 % et délai de 24 h de l'API Batches, comportement d'un lot à la limite de dépense
  de l'espace de travail : à vérifier.
- Volumes : `DATA_SOURCES.md` (960 documents après la v0.1.86, 4 noms en double mesurés le
  2026-11-21). Champs de `beer_cultures/` : `exigences-techniques.md`, tableau des référentiels.
- Jetons par levure : hypothèses d'ADR-013 et de l'architecte, non mesurées ; l'essai les mesure.

## Note du 2026-11-21 — fiche d'une levure (livraison 2)

Décisions de l'utilisateur du 2026-11-21, sur la proposition d'écran de l'ux-designer :

1. Chaque style conseillé est un bouton qui ouvre la fiche du style dans la Bibliothèque
   (`AppRoutes.libraryEntry('styles', code)`, par-dessus la fiche de la levure). Le nom affiché
   est `styles[].name`, sans code ; la cible fait au moins 48 px de haut.
2. La mention IA se place en tête de la section, sous le titre « Arômes », comme pour un
   houblon.
3. Les sous-titres des textes de plage portent la borne de `temperature_range` de la levure :
   « En bas de plage (15 °C) », « En haut de plage (20 °C) », au format de la ligne
   « Température de fermentation » de la fiche. Sans borne, le sous-titre reste « En bas de
   plage » ou « En haut de plage », sans valeur de remplacement. Cette décision s'écarte du
   texte de la section 4, qui nomme les sous-titres sans température. Aucune formule : la
   valeur est lue en °C.

Seconde décision de l'utilisateur du 2026-11-21 : « Relu et non relu ne doivent pas être
affichés nulle part. » Elle vaut pour les levures et les houblons (ADR-013, note du même jour).
La mention devient « Texte rédigé par une IA (Claude) », sans date ni état de relecture ; elle
remplace celle de la section 4. `reviewed` et `reviewed_at` restent dans les documents et
`ingest/ecrire.mjs` refuse toujours une levure du groupe non relue ; l'application ne les lit
pas. Le texte de « Sources des données » ne parle pas de relecture.

## Note du 2026-11-22 : un seul lot pour les levures

Décision de l'utilisateur du 2026-11-22, après l'essai de 10 levures (0,2451 $, effort `medium`,
≈ 5 884 jetons d'entrée et 420 de sortie par levure) : les 923 levures du périmètre partent en un
seul lancement. `--max` vaut 1 000 au plus pour `--nature culture`, et ce plafond est aussi la
valeur par défaut ; les houblons restent à 500. Le plafond vit dans la nature
(`maxElements` de `natures/culture.mjs` et `natures/hop.mjs`), contrôlé une fois `--nature` lu.
Coût attendu en Batch : ≈ 29,5 $ ; borne haute du script avec `max_tokens` 4 000 : ≈ 95,6 $,
d'où `--budget-usd 100`. La limite de 70 $ de l'espace de travail reste le plafond de dépense
réelle. `max_tokens` reste à 4 000 : il borne la réflexion d'une levure sans coûter plus que les
jetons produits.
