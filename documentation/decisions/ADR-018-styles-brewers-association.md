# ADR-018 — Second guide de styles : Brewers Association, sans superposition avec le BJCP 2021

- **Statut** : proposé
- **Date** : 2026-11-22
- **Remplace** : — (amende ADR-005 : décision 2 de `DATA_SOURCES.md`, exception à P20 pour
  les styles d'un second guide ; amende ADR-017 : la liste des styles conseillés reste celle du
  BJCP 2021, filtrée sur l'identifiant ; complète ADR-015 : le style envoyé à l'assistant
  porte son guide ; ADR-014 inchangé pour le premier lot)

## Contexte

L'assistant de recette (ADR-015) a cité un « Imperial Pils ». La Bibliothèque ne le connaît pas :
`beer_styles` ne contient que les 110 styles BJCP 2021 du fichier 002 de Brewtarget
(`DATA_SOURCES.md`, « Décisions validées », point 2). Un style hors Bibliothèque se saisit à la
main (`ChampBibliotheque`, `app/lib/features/recipes/presentation/recipe_editor_screen.dart`,
ligne 1189), mais l'export BeerXML le refuse (ADR-005, E4 ; `kStyleHorsBibliotheque`,
`app/lib/features/library/presentation/choix_style.dart`).

L'utilisateur demande d'ajouter le guide de la Brewers Association (BA), sans superposition :
seuls les styles BA sans équivalent parmi les 110 styles BJCP 2021 entrent.

Faits relevés le 2026-11-22 :

- Le guide BA le plus récent est l'édition 2026, publiée en PDF le 2025-12-31. Aucune API ni
  aucun fichier structuré. La BA le révise chaque année, entre février et mars.
- La présence d'un style « Imperial Pils » ou « Imperial Pilsener » dans l'édition 2026 n'est pas
  confirmée : une recherche n'en trouve aucune mention, et le PDF n'a pas pu être lu depuis la
  session (domaines `brewersassociation.org` et `cdn.brewersassociation.org` hors du réseau
  permis). À vérifier sur le PDF avant tout code.
- Conditions d'usage, d'après les résultats de recherche (pages non lues directement) : un
  usage gratuit est permis avec la mention « Based on Brewers Association 2026 Beer Style
  Guidelines with changes. Used with permission of Brewers Association. » ; un usage payant
  ou lié à un revenu demande une autorisation. Une seconde page de la BA cite les applications et
  les bases de données parmi les usages soumis à autorisation quand ils sont payants, et demande
  une autre mention, avec un lien vers la page du guide. Les deux pages ne disent pas la même
  chose.
- Code existant : identifiant `bjcp2021-<code>` (`idStyle`, `exchange/lib/src/ingestion/cles.dart`,
  ligne 51) ; motif `^bjcp2021-…$` dans `ingest/lib/validation.mjs` (ligne 134) ; lecture du 002
  par `lire002` (`exchange/lib/src/ingestion/lecture_sources.dart`, ligne 417), SRM converti en EBC
  par `brewing/` (`valeurs.dart`, `versEbc`) ; `contexteStyles`
  (`ingest/lib/aromes/natures/culture.mjs`, ligne 103) prend **tous** les documents de
  `beer_styles.json` préparé, et leur SHA-256 entre dans `input_sha256` des levures : un style
  ajouté fait régénérer les 923 levures d'ADR-017 ; la lecture de `beer_index/styles` par
  l'application ignore un champ inconnu (`app/lib/features/library/domain/referentiel.dart`,
  ligne 10) et exige `code` (ligne 245) ; les règles de `beer_styles/{styleId}` ne listent aucun
  champ (`firestore.rules`, ligne 931).

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun travail ; aucun risque de licence | les styles absents restent en saisie libre, export BeerXML refusé pour eux | 0 € / 0 € |
| A. BA complet, sans dédoublonnage | aucune table à relire | refusé par la demande : deux entrées pour une même bière (« German Pils » et « German-Style Pilsener »), choix ambigu dans l'éditeur, deux fiches aux plages différentes | 0 € / ≈ 0 € ; 2 livraisons |
| B. BA dédoublonné par une table écrite à la main (demande) | seuls les styles manquants entrent ; chaque exclusion est justifiée et relue | relecture de chaque style BA ; jugement humain, révisable à chaque édition | 0 € / ≈ 0 € ; 2 livraisons et une relecture de la table |
| B'. Liste courte : quelques styles BA nommés par l'utilisateur | relecture de quelques lignes seulement | même code que B ; les styles non demandés restent absents | 0 € / ≈ 0 € ; 2 livraisons |
| Styles créés par le brasseur | — | écartée par l'utilisateur | — |

## Décision

Option B, sous deux conditions préalables : l'usage du guide BA est confirmé permis pour
Kass'Beer (application gratuite, dépôt public), et la liste des styles BA retenus est relue par
l'utilisateur. Les styles BA sans équivalent BJCP 2021 entrent dans `beer_styles` sous
l'identifiant `ba-<clé du nom>`, sans description, avec leur guide affiché ; tout le reste du
modèle (recette, règles, export) ne change pas.

### 1. Source

- Le PDF de l'édition figée (2026) est téléchargé par l'administrateur dans `import/sources/`,
  jamais versionné (P20). Son SHA-256 est noté dans `DATA_SOURCES.md`.
- Une session Claude Code recopie à la main, depuis le PDF, un fichier
  `exchange/donnees/styles/ba-2026.json`, versionné, au format BeerJSON 2.01 (`styles`), comme
  `exchange/donnees/fabricants/cultures.json`. Aucun lecteur de PDF n'entre dans `exchange/`.
- Le fichier est versionné seulement si la condition de licence est remplie pour un dépôt
  public. Sinon il vit dans `import/sources/`, et seule la table de décisions (noms et
  équivalents, sans plages) est versionnée.
- En tête du fichier : édition, date de publication, SHA-256 du PDF, mention de la BA.

### 2. Contenu d'une entrée

Chaque style BA du PDF a une entrée, retenu ou non :

| Champ | Contenu |
|---|---|
| `name` | nom BA tel que publié (« American-Style India Pale Lager ») |
| `category` | catégorie BA telle que publiée |
| `category_id`, `style_id` | code BA (section 4) |
| `type` | `beer` |
| `style_guide` | `BA2026` |
| `original_gravity`, `final_gravity` | plages en `sg`, valeurs du PDF |
| `international_bitterness_units` | plage en `IBUs` |
| `color` | plage en `SRM`, valeurs du PDF ; conversion en EBC par `brewing/` à la préparation (P3) |
| `alcohol_by_volume` | plage en `%` (ABV, jamais ABW) |
| `kassbeer_decision` | `nouveau`, ou `{ "equivalent": ["4B"], "motif": "…" }` |

Un style BA « varie selon le style de base » reste sans plage, et l'export BeerXML le refuse
comme les 17 styles BJCP sans plage. Aucune plage n'est déduite. Aucune description, exemple,
historique ni lien n'est recopié.

### 3. Règle de dédoublonnage

Un style BA est un doublon quand un style BJCP 2021 du fichier 002 désigne la même bière :

1. même mode de fermentation (ale, lager, mixte) et même tradition ou origine ;
2. le style BJCP couvre le style BA : le style BA en est une version, un sous-type nommé, ou
   un regroupement plus large ou plus étroit ;
3. les plages ne contredisent pas : le milieu des plages BA de densité initiale, d'amertume et
   de couleur tombe dans les plages BJCP, ou l'écart est écrit dans `motif`.

La décision est écrite à la main dans `kassbeer_decision`, une par style BA, relue par
l'utilisateur. La préparation ne décide pas. Elle contrôle et signale :

- chaque style BA a une décision ; un `equivalent` cite des codes présents dans le fichier 002
  préparé ; sinon la préparation échoue ;
- aucun nom BA retenu n'est égal, exactement ou après `cleNormalisee`, au nom d'un style BJCP ou
  d'un autre style BA (l'export et `aideStyleSaisi` cherchent le style par son nom exact) ;
- pour chaque style `nouveau`, le rapport liste les styles BJCP dont les cinq plages chevauchent
  celles du style BA, à revoir. Ce signalement compare des intervalles ; il ne calcule aucune
  grandeur de brassage.

Les tests de `exchange/test/` rejouent ces contrôles sur des styles inventés (P20).

### 4. Code et export BeerXML

`STYLE_GUIDE` vaut `BA 2026`. `CATEGORY` est la catégorie BA. `CATEGORY_NUMBER` et
`STYLE_LETTER` viennent du code BA : si le PDF numérote ses styles, ce numéro ; sinon, un code
propre à Kass'Beer (`BA` suivi du rang de la catégorie, puis la lettre du rang du style dans sa
catégorie, dans l'ordre du PDF), décrit dans `DATA_SOURCES.md`. Le choix revient à
l'utilisateur (question ouverte). `TYPE` suit E7 d'ADR-005, sans changement. L'export BeerJSON
ne change pas : le style sort de la recette avec une perte listée (`StyleNonExporte`).

### 5. Modèle de données

- `beer_styles/ba-<cleNormalisee(name)>` : mêmes champs que les styles BJCP (`exigences-techniques.md`,
  « Référentiels et recettes publiques »), `provenance[]` avec `source: brewers-association`,
  `version: 2026`, `licence: BA (noms et plages, avec la mention de la BA)`. L'identifiant ne
  porte pas l'édition : un style inchangé garde son document d'une édition à l'autre.
- `beer_index/styles` : chaque entrée reçoit `guide` (`BJCP2021` ou `BA2026`). Une version
  installée de l'application ignore ce champ et affiche les styles BA à la suite.
- `ingest/lib/validation.mjs` : motif `^(bjcp2021|ba)-[a-z0-9]+(-[a-z0-9]+)*$`, source et licence
  ajoutées aux listes, `guide` permis dans l'index.
- `firestore.rules` ne change pas (P19). Le budget des règles de `recipes/` et `brews/` ne
  bouge pas : la recette garde `recipe.style.name` seul (ADR-005, E1).
- Taille de `beer_index/styles` : quelques dizaines d'entrées de plus, moins de 30 Ko
  (estimation), sous la borne de 900 Ko de l'écrivain.

### 6. Styles conseillés des levures (ADR-017)

Ils restent des styles BJCP 2021. `contexteStyles` ne garde que les documents dont
l'identifiant commence par `bjcp2021-`. Un style BA ajouté ne change ni la liste du prompt ni
`stylesSha256`, et aucune levure n'est régénérée. Ce filtre est livré avant la première
préparation qui contient un style BA.

### 7. Assistant de recette (ADR-015)

`stylePourAssistant` (`app/lib/features/recipes/domain/assistant_recette.dart`, ligne 180)
envoie aussi `style_guide`. Le serveur lit `style` comme un objet borné à 8 000 caractères
(`functions/src/assistant/request.ts`, ligne 340) : rien ne change côté serveur, sauf la ligne
du prompt qui décrit le bloc `STYLE` (« nom, code, guide, plages chiffrées »), avec son test de
prompt. `set_style_name` reste libre.

### 8. Affichage

- Feuille « Choisir un style » et Bibliothèque : styles groupés par guide, puis par catégorie ;
  le guide est écrit sur chaque ligne et sur la fiche (« BA 2026 »). Proposition d'écran par
  `ux-designer`.
- Écran « Sources des données » : section « Brewers Association 2026 », avec la mention exigée
  par la BA, les modifications (descriptions retirées, couleur convertie en EBC, styles couverts
  par le BJCP 2021 écartés) et, si la BA l'exige, le lien vers la page du guide.

### 9. Lots

| Lot | Contenu | Livraisons |
|---|---|---|
| S0 | conditions : licence confirmée, PDF téléchargé, présence de l'Imperial Pils vérifiée, choix du code ; fichier `ba-2026.json` recopié et table relue par l'utilisateur | aucune (données) |
| S1 | `exchange/` : lecteur du fichier (lecture de `lire002` partagée), `idStyleBa`, contrôles de la section 3, champ `guide` de l'index ; `ingest/` : motif, source, licence, filtre de `contexteStyles` ; documents (`DATA_SOURCES.md`, `exigences-techniques.md`) | 1, technique |
| S2 | application : guide affiché (feuille, Bibliothèque, fiche), tri par guide, écran « Sources des données », `style_guide` envoyé à l'assistant, export BeerXML vérifié sur un style BA ; puis écriture en production | 1, fonctionnel |

L'écriture en production a lieu après le déploiement de S2 : la mention de la BA doit être à
l'écran quand les styles le sont.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : lecture et contrôles du fichier sur le poste de l'admin
   (`exchange/bin/preparer_referentiels.dart`), écriture par `ingest/ecrire.mjs` ; affichage et
   export dans l'application ; aucune fonction serveur nouvelle.
2. Ce qui existera en double : rien. Le filtre `bjcp2021-` vit en Node seul ; la conversion SRM
   vers EBC reste dans `brewing/`.
3. Ce qui pèse au démarrage : rien. L'index des styles est lu à l'ouverture du champ Style, par
   `get` mémorisé, quelques Ko de plus.
4. Compilation de chaque cible : aucune dépendance ajoutée.
5. Qui voit quoi : données publiques (noms et plages), lues par tout membre en `get` ; rien de
   privé ; aucun envoi à un tiers nouveau (l'assistant reçoit déjà le style).
6. Ce qui coûte à l'usage, plafond : quelques dizaines d'écritures Firestore par ingestion,
   dans le niveau gratuit. Sans le filtre de la section 6, la régénération des 923 levures
   serait facturée sur l'espace de travail de la Console (montant : à mesurer sur le rapport du
   lot d'ADR-017) ; le filtre l'empêche.
7. Exposition : inchangée. Les noms et plages BA deviennent publics sur GitHub si le fichier est
   versionné, ce qui dépend de la licence.
8. Exploitation, sauvegarde, mise à jour : l'édition est figée. Une nouvelle édition BA demande
   une nouvelle recopie, une relecture de la table et, pour retirer un style disparu, une
   extension d'ADR-014 à `beer_styles` (préfixe `ba-` seul), décidée à ce moment.
9. Coût de sortie : retirer les documents `ba-*` et leur section de l'écran ; les recettes
   gardent leur nom de style en saisie libre, et leur export BeerXML est refusé comme
   aujourd'hui.

## Conséquences

- La Bibliothèque propose les styles BA manquants, et l'export BeerXML les accepte quand ils ont
  leurs plages.
- La table de dédoublonnage est un jugement humain, relu une fois par édition.
- `DATA_SOURCES.md`, décision 2, devient : « `beer_styles` prend les 110 styles BJCP 2021 du
  fichier 002, et les styles BA 2026 sans équivalent BJCP (ADR-018) ».
- P20 reçoit une exception pour le fichier BA ; un contrôle `relecteur-regles` couvre la table et
  ses contrôles ; P62 reçoit le filtre des styles conseillés (propositions de l'avis).

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
