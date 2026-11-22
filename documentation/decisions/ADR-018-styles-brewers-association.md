# ADR-018 — Second guide de styles : Brewers Association, sans superposition avec le BJCP 2021

- **Statut** : proposé (décisions de l'utilisateur du 2026-11-22 intégrées ; évolutions du réseau
  à valider)
- **Date** : 2026-11-22
- **Remplace** : — (amende ADR-005 : décision 2 de `DATA_SOURCES.md`, exception à P20 pour
  la table de décisions d'un second guide ; amende ADR-017 : la liste des styles conseillés
  reste celle du BJCP 2021, filtrée sur l'identifiant ; complète ADR-015 : le style envoyé à
  l'assistant porte son guide ; amende ADR-014 au lot S3 : `--supprimer-absents beer_styles`,
  identifiants `ba-` seuls, section « Amendement proposé par ADR-018 » d'ADR-014)

Décisions de l'utilisateur du 2026-11-22 :

1. Licence : usage gratuit avec la mention de la BA, sans écrire à la BA. Le PDF et les plages
   chiffrées restent dans `import/sources/`, jamais versionnés ; seule la table de décisions est
   versionnée.
2. Imperial Pils : le guide est ajouté sans vérifier d'abord que ce style y figure (risque
   accepté, section 10).
3. Étendue : option B, tout le guide BA dédoublonné, une décision relue par style.
4. Code BeerXML : code propre à Kass'Beer, `BA` + rang de la catégorie + lettre du rang du style
   (`BA3C`), `STYLE_GUIDE` « BA 2026 » ; la table versionnée porte le code.
5. Un sous-type nommé d'un style BJCP (Black IPA dans 21B) entre comme style BA (`nouveau`), et
   sa ligne cite le code BJCP qui le contient (`contenu_dans`).
6. Reprise à chaque édition annuelle, avec extension d'ADR-014 à `beer_styles` pour les
   identifiants `ba-` seuls.

## Contexte

L'assistant de recette (ADR-015) a cité un « Imperial Pils ». La Bibliothèque ne le connaît pas :
`beer_styles` ne contient que les 110 styles BJCP 2021 du fichier 002 de Brewtarget
(`DATA_SOURCES.md`, « Décisions validées », point 2). Un style hors Bibliothèque se saisit à la
main (`ChampBibliotheque`, `app/lib/features/recipes/presentation/recipe_editor_screen.dart`,
ligne 1189), mais l'export BeerXML le refuse (ADR-005, E4 ; `kStyleHorsBibliotheque`,
`app/lib/features/library/presentation/choix_style.dart`, ligne 17).

L'utilisateur demande d'ajouter le guide de la Brewers Association (BA), sans superposition :
seuls les styles BA sans équivalent parmi les 110 styles BJCP 2021 entrent.

Faits relevés le 2026-11-22 :

- Le guide BA le plus récent est l'édition 2026, publiée en PDF le 2025-12-31. Aucune API ni
  aucun fichier structuré. La BA le révise chaque année, entre février et mars.
- La présence d'un « Imperial Pils » dans l'édition 2026 n'est pas confirmée : une recherche
  n'en trouve aucune mention, et le PDF n'a pas pu être lu depuis la session (domaines de la BA
  hors du réseau permis).
- Conditions d'usage, d'après les résultats de recherche (pages non lues directement) : usage
  gratuit permis avec la mention « Based on Brewers Association 2026 Beer Style Guidelines with
  changes. Used with permission of Brewers Association. » ; usage payant soumis à autorisation.
- Code existant : identifiant `bjcp2021-<code>` (`idStyle`, `exchange/lib/src/ingestion/cles.dart`,
  ligne 51) ; motif `^bjcp2021-…$` (`ingest/lib/validation.mjs`, ligne 134) ; lecture du 002 par
  `lire002` (`exchange/lib/src/ingestion/lecture_sources.dart`, ligne 417), SRM converti en EBC
  par `brewing/` (`versEbc`) ; `contexteStyles` (`ingest/lib/aromes/natures/culture.mjs`,
  ligne 103) prend tous les documents de `beer_styles.json` préparé, et leur SHA-256 entre dans
  `input_sha256` des levures ; la recette ne garde que `recipe.style.name` (ADR-005, E1) : le
  lien avec la Bibliothèque se fait par le nom exact, au moment de l'export ;
  `planifierSuppressions` (`ingest/lib/ecriture.mjs`, ligne 94) calcule le seuil de 90 % sur
  toute la collection et filtre par `motifIdentifiant(collection)`.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun travail | styles absents en saisie libre, export BeerXML refusé pour eux | 0 € / 0 € |
| A. BA complet, sans dédoublonnage | aucune table | refusé par la demande : deux entrées pour une même bière | 0 € / ≈ 0 € |
| **B. BA dédoublonné, table écrite à la main (retenue)** | seuls les styles manquants entrent ; chaque décision relue | relecture de chaque style BA, reprise à chaque édition | 0 € / ≈ 0 € ; 3 livraisons, puis une reprise par an |
| B'. Liste courte nommée par l'utilisateur | quelques lignes à relire | écartée par l'utilisateur (décision 3) | — |

## Décision

Option B. Les styles BA sans équivalent BJCP 2021 entrent dans `beer_styles` sous
l'identifiant `ba-<cleNormalisee(name)>`, sans description, avec leur guide affiché. Le modèle
de recette, `firestore.rules` et l'export BeerJSON ne changent pas.

### 1. Source : deux fichiers, un seul versionné

| Fichier | Contenu | Versionné |
|---|---|---|
| `import/sources/ba-2026/guide.pdf` | PDF de l'édition, téléchargé par l'admin ; SHA-256 noté dans `DATA_SOURCES.md` | non (P20) |
| `import/sources/ba-2026/styles.json` | plages chiffrées recopiées du PDF, BeerJSON 2.01 (`styles`), en-tête : édition, date de publication, SHA-256 du PDF | non (décision 1) |
| `exchange/donnees/styles/ba.json` | table de décisions, une ligne par style BA, toutes éditions confondues (section 2) ; aucune plage, aucune description | oui |

La recopie se fait sur le poste de l'admin, par une session Claude Code locale : `import/` n'existe
pas dans une session cloud, et le PDF n'y est pas lisible. Aucun lecteur de PDF n'entre dans
`exchange/`.

Jointure par `exchange/bin/preparer_referentiels.dart`, option `--ba <dossier>` (absente :
aucun style BA préparé, comportement actuel) :

- clé de jointure : `name` exact après NFC, et `category` ;
- chaque style de `styles.json` a une ligne de la table, pour l'édition de l'en-tête ; chaque
  ligne non retirée de la table a son style dans `styles.json` ; sinon la préparation échoue et
  liste les noms ;
- l'édition de l'en-tête est égale à `edition_courante` de la table ; sinon échec.

Les tests de `exchange/test/` rejouent la jointure et les contrôles sur une table et un fichier de
plages inventés (`exchange/test/fixtures/ingestion/ba/`, P20) : aucun nom ni aucune plage de la BA
dans le dépôt hors de la table.

### 2. Table de décisions (`exchange/donnees/styles/ba.json`)

En-tête : `edition_courante` (2026), `mention` (texte exact de la BA pour cette édition),
règle du code (section 4). Une ligne par style BA :

| Champ | Contenu |
|---|---|
| `name`, `category` | nom et catégorie BA tels que publiés |
| `decision` | `nouveau` ou `equivalent` |
| `equivalent` | pour `equivalent` : codes BJCP 2021 du fichier 002 (`["5D"]`) |
| `contenu_dans` | pour `nouveau` seulement, facultatif : code BJCP du style plus large qui nomme ce sous-type (`"21B"`) |
| `motif` | une phrase, obligatoire |
| `code` | pour `nouveau` : code Kass'Beer (section 4) |
| `editions` | éditions où le style figure (`[2026]`) |
| `retire_en` | édition qui ne le contient plus, ou absent |

La table contient des noms de styles et de catégories, aucun chiffre du guide.

### 3. Règle de dédoublonnage

`equivalent` seulement quand un style BJCP 2021 désigne la même bière que le style BA lui-même :

1. même mode de fermentation et même tradition ou origine ;
2. le style BJCP est ce style, pas une famille plus large qui le contient comme sous-type nommé
   ou comme variante ; un style BA qui regroupe exactement plusieurs styles BJCP cite chacun ;
3. les plages ne se contredisent pas : le milieu des plages BA de densité initiale, d'amertume et
   de couleur tombe dans les plages BJCP, ou l'écart est écrit dans `motif`.

Un sous-type nommé d'un style BJCP plus large (Black IPA dans 21B Specialty IPA) est `nouveau`,
avec `contenu_dans`. Un style BA sans style BJCP proche est `nouveau` sans `contenu_dans`.

La décision est écrite à la main et relue par l'utilisateur. La préparation ne décide pas ; elle
contrôle :

- chaque ligne a une `decision` et un `motif` ; `equivalent` cite des codes du 002 préparé ;
  `contenu_dans` cite un code du 002 et n'existe que sur un `nouveau` ;
- aucun nom BA retenu n'est égal, exactement ou après `cleNormalisee`, au nom d'un style BJCP ou
  d'un autre style BA ;
- pour chaque `nouveau`, `rapport.json` liste les styles BJCP dont les plages chevauchent, à
  revoir. Ce contrôle compare des intervalles ; il ne calcule aucune grandeur de brassage.

### 4. Code et export BeerXML

- Code : `BA` + rang de la catégorie BA dans l'ordre du PDF de la première édition où elle
  paraît + lettre du rang du style parmi les styles `nouveau` de sa catégorie, dans l'ordre du
  PDF (A à Z, puis AA, AB…). Motif `^BA[1-9][0-9]?[A-Z]{1,2}$`.
- Le code est attribué une fois, à l'entrée du style dans la table, puis figé. Une nouvelle
  édition ne recalcule rien : un style ajouté prend la lettre libre suivante de sa catégorie, une
  catégorie nouvelle le rang suivant. Un style déplacé de catégorie garde son code. Un code
  retiré n'est jamais réattribué (la ligne reste, avec `retire_en`).
- Un code ne change que par une décision de l'utilisateur à la relecture. Effet : seuls les
  exports BeerXML suivants portent le nouveau code ; aucune recette ni aucun brassin ne stocke le
  code (E1).
- Export : `STYLE_GUIDE` « BA 2026 » (« BA <édition> »), `CATEGORY` la catégorie BA,
  `CATEGORY_NUMBER` et `STYLE_LETTER` tirés du code. `TYPE` suit E7. Export BeerJSON inchangé
  (perte `StyleNonExporte`).

### 5. Modèle de données

- `beer_styles/ba-<cleNormalisee(name)>` : mêmes champs que les styles BJCP, `code` de la table,
  `style_guide` `BA<édition courante>`, `provenance[]` avec `source: brewers-association`,
  `version: <édition>`, `licence: BA (usage gratuit, mention de la BA)`. L'identifiant ne porte
  pas l'édition.
- `beer_index/styles` : chaque entrée reçoit `guide` (`BJCP2021` ou `BA2026`). Une version
  installée ignore ce champ.
- `ingest/lib/validation.mjs` : motif `^(bjcp2021|ba)-[a-z0-9]+(-[a-z0-9]+)*$` pour l'écriture,
  source et licence ajoutées, `guide` permis dans l'index.
- `firestore.rules` ne change pas (P19) ; budget des règles inchangé.
- Taille de `beer_index/styles` : estimation sous 60 Ko pour tout le guide, sous la borne de
  900 Ko de l'écrivain (à mesurer à S1).

### 6. Styles conseillés des levures (ADR-017)

`contexteStyles` ne garde que les identifiants `bjcp2021-`. Un style BA ne change ni le prompt ni
`stylesSha256`, et aucune levure n'est régénérée. Livré à S1, avant toute préparation qui
contient un style BA.

### 7. Assistant de recette (ADR-015)

`stylePourAssistant` (`app/lib/features/recipes/domain/assistant_recette.dart`, ligne 180)
envoie aussi `style_guide`. Côté serveur, seule la ligne du prompt qui décrit le bloc `STYLE`
change (« nom, code, guide, plages chiffrées »), avec son test de prompt.

### 8. Affichage

- Feuille « Choisir un style » et Bibliothèque : styles groupés par guide, puis par catégorie ;
  guide écrit sur chaque ligne et sur la fiche (« BA 2026 »). Proposition d'écran par
  `ux-designer`.
- Écran « Sources des données » : section « Brewers Association », avec la mention de la BA et
  les modifications (descriptions retirées, couleur convertie en EBC, styles couverts par le BJCP
  2021 écartés). L'édition et la mention viennent de `beer_index/styles` (champ racine
  `ba_mention`, écrit par la préparation depuis la table) : une nouvelle édition ne demande pas
  de version de l'application. Index illisible : section en panne, aucun texte de repli.

### 9. Mise à jour annuelle

À chaque édition (février ou mars) :

1. l'admin télécharge le PDF dans `import/sources/ba-<édition>/` ;
2. une session locale recopie `styles.json`, ajoute les styles nouveaux à la table, met à jour
   `editions`, `retire_en`, `edition_courante` et `mention`, et liste les styles modifiés (nom,
   catégorie, plages) ;
3. l'utilisateur relit les décisions des styles nouveaux ou modifiés, et les seuls ;
4. préparation, simulation, écriture ; puis `--supprimer-absents beer_styles` (section 9.1).

Effets d'une édition :

- `style_guide` passe de `BA2026` à `BA2027` sur tous les documents `ba-` : chaque document est
  réécrit une fois. `guide` de l'index et `STYLE_GUIDE` suivent. Une préparation n'a qu'une
  édition BA.
- Un style inchangé de nom garde son identifiant et son code.
- Un style renommé reçoit un nouvel identifiant ; l'ancien document est supprimé. Son code est
  repris si la relecture le juge le même style (ligne renommée), sinon un nouveau code.
- Un style disparu : document supprimé, ligne gardée avec `retire_en`. Une recette qui le porte
  garde son nom, qui devient une saisie libre : l'éditeur affiche « hors Bibliothèque » et
  l'export BeerXML la refuse (E4, comportement actuel). Un brassin garde sa recette figée. Aucune
  migration de recette.

#### 9.1 Suppression (amendement d'ADR-014, lot S3)

`ecrire.mjs --supprimer-absents beer_styles` :

- candidats : identifiants en ligne conformes à `^ba-[a-z0-9]+(-[a-z0-9]+)*$` et absents de la
  préparation ; un `bjcp2021-` n'est jamais candidat ;
- seuil de 90 % calculé sur les seuls `ba-` (préparés contre en ligne), pas sur la collection ;
  une préparation sans style BA est donc refusée ;
- autres garde-fous inchangés : simulation d'abord, liste des identifiants avant la saisie,
  30 au plus, saisie du nombre, rapport chiffré, émulateur par défaut, une collection par
  lancement.

### 10. Risques acceptés

- L'Imperial Pils peut manquer au guide BA (décision 2). Dans ce cas, le cas qui a lancé la
  demande reste en saisie libre.
- Les plages ne sont pas versionnées : la CI ne vérifie pas la recopie. Une erreur de recopie
  se voit à la relecture ou dans la Bibliothèque.
- Les deux pages de conditions d'usage de la BA ne disent pas la même chose ; l'usage gratuit
  avec mention est retenu (décision 1).

### 11. Lots

| Lot | Contenu | Livraisons |
|---|---|---|
| S0 | poste de l'admin : PDF, `styles.json` recopié, brouillon de la table ; relecture de chaque ligne par l'utilisateur (nombre de styles BA : à compter sur le PDF) | aucune |
| S1 | table versionnée ; `exchange/` : `--ba`, jointure, contrôles des sections 1 à 4, codes, `idStyleBa`, `guide` et `ba_mention` de l'index, fixtures inventées ; `ingest/` : motif d'écriture, source, licence, filtre de `contexteStyles` ; `DATA_SOURCES.md`, `exigences-techniques.md` | 1, technique |
| S2 | application : guide affiché, tri par guide, « Sources des données » lue dans l'index, `style_guide` vers l'assistant et test de prompt, export BeerXML vérifié sur un style BA ; puis écriture en production | 1, fonctionnel |
| S3 | `--supprimer-absents beer_styles`, identifiants `ba-` (section 9.1) ; livré avant l'ingestion de l'édition 2027 | 1, technique |

L'écriture en production suit le déploiement de S2 : la mention de la BA est à l'écran quand les
styles le sont. S3 attend 2027 : la première édition n'a rien à supprimer.

Coût : S1 touche environ 10 fichiers de `exchange/` et 4 de `ingest/` ; S2 environ 8 fichiers de
`app/lib/` et 1 de `functions/src/assistant/` ; S3 3 fichiers de `ingest/` et leurs tests.
Aucune migration de données. Firestore : quelques centaines d'écritures par édition, dans le
niveau gratuit.

## Réponses aux questions de l'architecte

1. Où tourne le code : préparation et contrôles sur le poste de l'admin, écriture par
   `ingest/ecrire.mjs` ; affichage et export dans l'application ; aucune fonction serveur.
2. Double : rien. Le filtre `bjcp2021-` et le motif `ba-` vivent en Node ; la conversion SRM vers
   EBC reste dans `brewing/` ; les codes sont lus dans la table, jamais recalculés en Dart.
3. Démarrage : rien. `beer_index/styles` lu par `get` à l'ouverture du champ Style.
4. Compilation : aucune dépendance ajoutée.
5. Qui voit quoi : noms et plages BA lus par les membres ; seuls noms et catégories sont publics
   sur GitHub ; aucun envoi nouveau à un tiers.
6. Coût à l'usage : écritures Firestore dans le niveau gratuit ; régénération des levures évitée
   par le filtre de la section 6.
7. Exposition : inchangée.
8. Exploitation : une reprise par an (section 9), relecture limitée aux styles nouveaux ou
   modifiés ; PDF et plages à garder sur le poste de l'admin, hors de toute sauvegarde du dépôt.
9. Sortie : retirer les documents `ba-` (S3) et la section de l'écran ; les recettes gardent leur
   nom de style en saisie libre.

## Conséquences

- La Bibliothèque propose les styles BA manquants, et l'export BeerXML les accepte quand ils ont
  leurs plages.
- `DATA_SOURCES.md`, décision 2 : « `beer_styles` prend les 110 styles BJCP 2021 du fichier 002,
  et les styles BA sans équivalent BJCP (ADR-018) ; seule la table de décisions est versionnée ».
- P20, P62 et P19 sont amendés, P63 est ajouté (propositions de l'avis).

## Sources

Consultées le 2026-11-22, par moteur de recherche ; les pages de la BA n'ont pas pu être
ouvertes depuis la session.

- Brewers Association, « 2026 Brewers Association Beer Style Guidelines » :
  https://www.brewersassociation.org/edu/brewers-association-beer-style-guidelines/
- Brewers Association, PDF « 2026 Beer Style Guidelines, Updated 12/31/2025 » :
  https://cdn.brewersassociation.org/wp-content/uploads/2025/12/19140641/2026_BA_Beer_Style_Guidelines.pdf
- Brewers Association, « 2026 Beer Style Guidelines Now Available » :
  https://www.brewersassociation.org/association-news/2026-beer-style-guidelines-now-available/
- Brewers Association, page « Beer Style Guidelines » (conditions d'usage) :
  https://www.brewersassociation.org/educational-publications/beer-styles/
