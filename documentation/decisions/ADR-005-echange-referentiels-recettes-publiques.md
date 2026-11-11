# ADR-005 — Recettes en BeerJSON, échange, référentiels et recettes publiques, sans Cloud Functions

- **Statut** : accepté le 2026-11-08 (révisé le même jour après treize décisions de l'utilisateur)
- **Date** : 2026-11-08
- **Remplace** : — (modifie ADR-001, qui renvoyait l'export BeerXML après la v1)

## Contexte

Le ticket « Socle données » demande un format d'échange (BeerJSON et BeerXML, import et export),
cinq référentiels, une base de recettes publiques et des scripts d'ingestion. Il veut remplir
l'application et échanger des recettes avec Brewfather, Brewer's Friend, BeerSmith et
Brewtarget.

Contraintes : moins de 10 comptes (`projet.md`), Firestore en production, aucun dossier
`functions/`, dépôt public (ADR-002), calculs dans `brewing/` seul (P3), jour de brassage sans
réseau (P2), dépense visée ≈ 0 € par mois.

L'utilisateur a tranché le 2026-11-08 :

1. Import et export en Dart (`exchange/`), scripts locaux pour l'ingestion, aucune Cloud Function.
2. BeerJSON en base pour les recettes, contre la recommandation de l'architecte.
3. Kaggle : statistiques par style seulement, licence vérifiée avant l'ingestion.
4. Licences : DIY Dog en usage privé, Brewtarget 001 à 005 en noms et valeurs techniques seuls,
   styles BJCP en nom, code, classement (catégorie, type, guide) et plages seuls.
5. Aucune migration : recettes, équipements et brassins actuels peuvent être effacés, sur
   confirmation de l'utilisateur au moment de l'exécution.
6. Évolutions du réseau acceptées après adaptation.

Puis, au cadrage (L0), le même jour :

7. BeerJSON figé sur le commit `4370892d44` de `main`, pour la base et l'export.
8. Rendement de brassage exporté calculé par `brewing/`, avec sa fixture (P3).
9. Base publique : les 415 recettes DIY Dog seules. Les 38 recettes de Brewtarget sont écartées.
10. Tout passe en Node 24 à la livraison L3 : `ingest/`, `rules-tests/` et la CI (P10).
11. Recettes › Importer pour tout brasseur (50 recettes au plus par fichier, sous son compte) ;
    Admin › Import pour les 16 fiches.
12. Nouveaux champs de saisie facultatifs à l'enregistrement, bloquants à l'export.
13. Prochain brassin vers le 22 novembre 2026, donc décision de passage vers le 15 novembre.

La table de correspondance de chaque source est dans `documentation/DATA_SOURCES.md`.

Faits relevés le 2026-11-08 :

- `@beerjson/beerjson` 1.0.2 (npm, octobre 2021) est en JSON Schema Draft-07. La branche `main`
  de `beerjson/beerjson` est en Draft 2020-12, `package.json` 3.0.0 non publié, versions de format
  acceptées 2.01, 2.06 et 3.
- Les deux diffèrent sur le temps d'un ajout à l'ébullition. En 1.0.2, `duration` porte les
  minutes d'ébullition. Sur `main`, `time` les porte, mesuré depuis la fin de l'ébullition, et
  `duration` donne le temps d'infusion d'un ajout en fin d'ébullition.
- Dans les deux, `RecipeType` refuse tout champ inconnu. Sur `main`, les additions aussi. `RecipeType` exige `name`, `type`, `author`,
  `efficiency`, `batch_size` et `ingredients`. `FermentableBase` exige `yield` et `color`,
  `HopVarietyBase` `alpha_acid`, `CultureBase` `type` et `form`, `MiscellaneousBase` `type`.
  `MashProcedureType` exige `name`, `grain_temperature` et `mash_steps`.
- `TimeType.value` est un entier. Les unités canoniques du projet existent toutes dans le schéma :
  `g`, `l`, `C`, `min`, `EBC`, `sg`, `%`.
- La lecture du modèle est concentrée dans `recipe.dart`. `brew.dart` lit `recipe_snapshot` par
  `RecipeContent.fromFirestore`. Aucun code ne relit le champ `key` d'un ingrédient.
- Avec le cache persistant, un écouteur coupé plus de 30 minutes est facturé comme une nouvelle
  requête. Après les décisions ci-dessus, les référentiels comptent 2 994 entrées brutes, dont 110
  styles, soit environ 1 950 noms uniques.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| A. Ne pas le faire | aucun effort | application vide, aucun échange | 0 € / 0 € |
| B. Pipeline en Dart pur, scripts locaux (décision 1) | une seule implémentation ; P3 respecté ; aucun point d'accès public ; aucun rôle ajouté à la CI | ajv seulement en CI et dans les scripts ; deux langages dans l'ingestion | 0 € / 0 € sous quotas |
| C. Cloud Functions pour l'import et l'export | ajv sur chaque fichier reçu | copies de `ingredientKey` et de P11 ; point d'accès public (plafond ≈ 124 $ par mois sous attaque continue) ; `github-deploy` obtient un accès indirect aux données | ≈ 0 à 0,05 $ / ≈ 0 $ |
| D. Socle Functions d'abord | prépare l'IA | aucun service rendu au ticket, « Pas de code mort » | ≈ 0 à 0,05 $ / ≈ 0 $ |

Modèle de `recipes/` : BeerJSON en base (décision 2). Sans cette décision, l'architecte
recommandait le modèle plat avec BeerJSON à la frontière. Il en coûte la réécriture décrite
ci-dessous, soit 4 à 5 jours.

## Décision

Option B. Les recettes sont stockées en BeerJSON partiel, dans une enveloppe propre à Kass'Beer.
Le pipeline d'échange est écrit une fois en Dart et sert à l'application comme à l'ingestion.

### Version de référence

La référence est le commit `4370892d44` de `beerjson/beerjson` (branche `main`) : ses
descriptions distinguent `time` et `duration`, et Brewtarget écrit en version 2.01. Le commit est
figé, comme les autres sources. L'import accepte les fichiers 1.x, 2.x et 3, et lit `time`, sinon
`duration`, pour un ajout à l'ébullition. Le ticket disait « BeerJSON 1.0 » ; l'utilisateur a
retenu ce commit le 2026-11-08. La version écrite par l'export se fixe en L2, après un essai
d'import dans Brewtarget ; 2.01 est la version candidate.

### Document `recipes/{id}`

```json
{
  "format_version": 1,
  "owner_uid": "…", "owner_name": "…", "equipment_id": "…", "style_id": "…",
  "imported_from": "…", "created_at": "…", "updated_at": "…",
  "brew_steps": [{ "key": "…", "name": "…", "duration_min": 60, "temp_c": 65 }],
  "ingredient_refs": { "malt-pils": "<id de beer_fermentables>" },
  "recipe": {
    "name": "Ale blonde", "type": "all grain", "notes": "…",
    "batch_size": { "value": 20, "unit": "l" },
    "boil": { "boil_time": { "value": 60, "unit": "min" } },
    "mash": {
      "name": "Empâtage",
      "grain_temperature": { "value": 18, "unit": "C" },
      "mash_steps": [{
        "name": "Palier", "type": "infusion",
        "step_temperature": { "value": 65, "unit": "C" },
        "step_time": { "value": 60, "unit": "min" }
      }]
    },
    "ingredients": {
      "fermentable_additions": [{
        "name": "Pils", "type": "grain",
        "yield": { "fine_grind": { "value": 80, "unit": "%" } },
        "color": { "value": 4, "unit": "EBC" },
        "amount": { "value": 5000, "unit": "g" }
      }],
      "hop_additions": [{
        "name": "Cascade", "form": "pellet",
        "alpha_acid": { "value": 7, "unit": "%" },
        "amount": { "value": 20, "unit": "g" },
        "timing": { "use": "add_to_boil", "time": { "value": 60, "unit": "min" } }
      }],
      "miscellaneous_additions": [],
      "culture_additions": [{
        "name": "S-04", "type": "ale", "form": "dry",
        "attenuation": { "value": 75, "unit": "%" }
      }]
    }
  }
}
```

- `recipe` suit la structure et les noms de `RecipeType`. Tout ce que BeerJSON refuse vit dans
  l'enveloppe.
- `format_version` : entier. Un `recipe_snapshot` ne se récrit pas depuis un client. Une valeur
  inconnue rend le document illisible et évite une lecture fausse.
- `key` n'est plus stockée : les additions refusent tout champ inconnu, et la clé se dérive du
  nom et de la nature par `ingredientKey`. `ingredient_refs` associe cette clé à l'entrée résolue
  du référentiel, pour les seules lignes résolues. Deux lignes de même nom partagent la clé,
  comme aujourd'hui. Aucun tableau parallèle.
- `{value, unit}` : un seul couple autorisé par grandeur, `g`, `l`, `C`, `min`, `EBC`, `sg`, `%`.
  La conversion a lieu à l'import. Une autre unité en base rend le document illisible. L'objet
  est absent ou complet, jamais une unité sans valeur.
- Durées en minutes entières (`TimeType`) : l'éditeur refuse une durée décimale.
- La masse des malts reste saisie en kilogrammes et stockée en grammes.
- `source_hop_timing` (enveloppe, `public_recipes` et leurs copies) : liste de `{hop_index, label}`,
  pour les seules lignes de `hop_additions` dont le libellé d'origine ne dit pas la durée (`start`,
  `middle`, `Whirlpool`…). « Dupliquer » la copie. L'éditeur retire une entrée quand sa durée est
  saisie. C'est la seule exception à « aucun tableau parallèle », car `ingredientKey` ne distingue
  pas deux lignes de même nom. L'éditeur met `hop_index` à jour quand une ligne se déplace, et
  retire l'entrée quand sa ligne est supprimée.

### Recette incomplète et validation

La base stocke un **sous-ensemble partiel** de BeerJSON. Seule différence avec le schéma : une
liste fermée de champs obligatoires peut manquer. Aucune valeur n'est inventée.

| Champ absent permis | Rempli à l'enregistrement | À l'export, s'il manque |
|---|---|---|
| `recipe.type` | choix dans l'éditeur | export bloqué |
| `recipe.author` | conservé d'un import | `owner_name` de l'enveloppe, sinon bloqué |
| `recipe.efficiency` | jamais stocké (amendement de L2 du 2026-11-10 : un contrôle de plus dépasse le budget des règles à la création d'un brassin, et l'export ne le lit pas) | rendement d'empâtage de l'équipement de la recette, sinon bloqué |
| `recipe.batch_size`, `boil`, `boil.boil_time` | saisie | bloqué |
| `mash` (sans palier), `grain_temperature`, type d'un palier | saisie ; `name` est un libellé | bloqué |
| `yield`, `color`, `alpha_acid` | saisie, ou référentiel résolu à l'import | bloqué |
| `culture.type`, `culture.form`, `misc.type` | choix dans l'éditeur | bloqué |
| `culture.amount` | saisie facultative, en grammes (décision du 2026-11-10) | bloqué |
| `mash.mash_steps` | absent quand aucun palier n'est saisi, jamais une liste vide ; `grain_temperature` s'enregistre seule | bloqué |
| `style.category`, `style_guide`, `type` | style résolu dans `beer_styles` | BeerJSON : `style` omis ; BeerXML : bloqué |

L'export d'une recette bloquée liste les valeurs à compléter (`MissingInput` et équivalents). Une
valeur tirée du référentiel à l'import est une donnée, comptée au compte rendu.

Trois validations :

1. **Schémas officiels au commit figé (ajv, `ajv/dist/2020`)** : en CI sur les sorties de l'export,
   et dans l'ingestion sur les fichiers BeerJSON des sources.
2. **Schéma partiel**, produit en CI à partir des schémas officiels : les `required` de la liste
   ci-dessus retirés, les unités réduites aux unités canoniques. Il valide en CI les documents
   écrits par `toFirestore`, et dans l'écrivain Node chaque document avant écriture.
3. **Lecture typée en Dart** dans l'application (`LecteurChamps`) : champs, types, unités et
   valeurs connues. ajv ne tourne pas dans l'application.

`firestore.rules` contrôle l'enveloppe, puis `recipe` : `hasOnly` sur ses champs, nom borné,
unités des grandeurs de premier niveau, plafonds de listes (50, 50, 50, 10, 20 paliers). Les
éléments des listes restent hors de portée des règles. `water_additions` est refusé.

### Valeurs sans équivalent direct

- **Whirlpool** : `use: add_to_boil`, `time` à 0 minute, `duration` à la durée d'infusion. L'éditeur
  rend cette durée obligatoire pour un whirlpool : c'est la seule exception à la décision 12, car
  sans elle un whirlpool se lit comme un ajout en fin d'ébullition. Un `add_to_boil` à 0 minute sans
  `duration` est un ajout en fin d'ébullition. Le moment `after_boil` d'un autre ajout suit la même
  règle. Un whirlpool importé sans durée garde son libellé dans `source_hop_timing`.
- **À cru** : `use: add_to_fermentation`, `duration` en minutes (jours saisis × 1 440). `time`, quand
  une source le donne, porte le jour d'ajout en minutes depuis le début de la fermentation.
  `brewing/` ne le lit pas.
- **`extract`** : les valeurs du schéma (`extract`, `dry extract`, `honey`, `fruit`, `juice`) sont
  conservées dans `type`. Elles se lisent comme `FermentableKind.sugar` (rendement 1, sans
  empâtage), ce qui est exact pour un extrait. Aucune valeur n'est ajoutée à l'énumération de
  `brewing/`, et aucune formule ne change. `Adjunct` (BeerXML) donne `grain`. `other` reste tel quel
  au référentiel ; une ligne de recette de ce type demande une nature connue pour être calculée.
- **`first_wort`** : reste retiré (A5). BeerJSON n'a pas cette valeur. Un `First Wort` BeerXML
  devient `add_to_boil` à la durée complète d'ébullition, et la perte est listée au compte rendu.
- **Autres valeurs** (houblon `add_to_mash`, `add_to_package`, formes `plug`, `powder`, `extract`) :
  table de correspondance de `documentation/DATA_SOURCES.md`.

### Code à réécrire

`RecipeContent`, ses lignes et `toInput` restent le type de travail de l'application. `brewing/`,
`computeRecipe` et l'écran du jour ne changent pas en L1, ce qui préserve P2 et P3 (L2a les
étend : voir « Amendements de L2 »).

| Fichier | Changement |
|---|---|
| `features/recipes/domain/recipe.dart` (513 lignes) | `fromFirestore` et `toFirestore` lisent et écrivent le sous-arbre ; `recipe` s'écrit d'un bloc, sans `FieldValue.delete()` |
| `features/brews/domain/brew.dart` | `recipeSnapshot` et `updated_at` de la copie, lus dans l'enveloppe ; même forme pour `recipe_snapshot` |
| `ingredient_forms.dart`, `recipe_editor_screen.dart` | nouveaux choix (type de recette, culture, ajout, palier, température du grain), durée entière, durée de whirlpool |
| `firestore.rules` | `recipeFields()`, `isRecipeShape`, contrôle de la copie figée |
| `rules-tests/` | `helpers.mjs`, `content`, `owner_name`, `brew_day`, `after_brew` |
| `app/test/` | `recipe_conversion_test`, `content_repositories_test`, `after_brew_domain_test`, `after_brew_repository_test`, `brew_domain_test`, `brews_repository_test` |
| CI | schéma partiel et ajv |

### Équipements

`equipment/` reste plat, et `equipment_snapshot` aussi. Le ticket ne porte que sur les recettes,
et l'export en lit seulement le rendement, les volumes et les pertes, pour `BOIL_SIZE` et
`efficiency.brewhouse`. Passer les profils en BeerJSON n'apporterait rien avant un échange
d'équipements. Par conséquent, leur effacement n'est pas nécessaire.

### Collections ajoutées

| Collection | Contenu | Volume | Écrit par | Lu par un membre |
|---|---|---|---|---|
| `beer_fermentables`, `beer_hops`, `beer_cultures`, `beer_miscs` | nom, alias, valeurs techniques, `label_fr`, `provenance[]` avec `source`, `sourceId`, `version`, `licence`, date | 2 884 entrées brutes | script | `get` d'une entrée |
| `beer_styles` | nom, code, catégorie, type, guide, plages chiffrées, `provenance[]`, sans description ni traduction | 110 | script | `get` |
| `beer_index/{nature}` | index compact : identifiant, nom, alias, valeurs de calcul | 5 documents, ≈ 200 Ko au plus (estimation) | script | `get` à l'ouverture d'un import ou d'un sélecteur |
| `public_recipes/{source}-{sourceId}` | même forme que `recipes/`, `owner_uid: system`, `provenance` | 415 | script | pages de 50 sur `recipe.name`, sans écouteur |
| `style_stats/{styleId}` | effectif, min, quartiles, médiane, max d'OG, FG, degré, IBU, EBC | 110 au plus, un style Kaggle non résolu étant compté au rapport | script | `get` |
| `ingest_runs/{runId}` | compteurs par source | 1 par exécution | script | admin |
| `import_unresolved/{empreinte}` | nature, nom, source, date | selon les imports | script ; création par un membre, champs en liste blanche | admin |

Une recette publique se copie par « Dupliquer » avant de servir à un brassin.

### Échange et ingestion

- `exchange/` : paquet Dart sans Flutter ni Firebase, dépend de `brewing/` et de `xml` 7.0.1. Il
  décode, détecte le format, lit, normalise, résout les ingrédients et produit le compte rendu.
  L'import et l'export BeerJSON sont proches de l'identité, puisque la base est déjà en BeerJSON.
- Conversions de brassage (Plato, Lovibond, SRM) dans `brewing/`, avec fixtures (P3). Livres,
  onces, gallons, °F dans `exchange/`.
- `BOIL_SIZE` (BeerXML) demande un calcul de volume avant ébullition, et `efficiency.brewhouse` un
  calcul de rendement de brassage. Les deux entrent dans `brewing/` avec leur fixture. (Remplacé
pour le rendement par les amendements de L2 : l'export écrit le rendement d'empâtage de
l'équipement, sans calcul.)
- Le fichier 005 est au format dotBeer : un lecteur dédié, utilisé par l'ingestion seule.
- Recettes › Importer écrit au plus 50 recettes d'un fichier, sous le compte de l'importateur. Ce
  n'est pas une écriture de masse sur les données du groupe : la règle « un seul écran » ne s'y
  applique pas (décision 11).
- Ingestion : outil Dart sans réseau, puis écrivain Node 24 avec l'Admin SDK. Émulateur par défaut,
  production sur option explicite, liste blanche de collections, identifiant source + `sourceId`,
  empreinte du contenu, rapport JSON.
- Identifiants locaux : compte de service `kassbeer-ingest` (`roles/datastore.user`), emprunté par
  `gcloud auth application-default login --impersonate-service-account`. Aucune clé JSON.

### Licences et attribution

Aucun fichier de ces sources n'entre dans le dépôt public, un asset ou l'APK. Les données vivent
dans `import/`, ignoré par Git. Les fixtures sont écrites à la main.

| Source | Retenu | Écarté |
|---|---|---|
| Brewtarget 001 à 004 (GPL-3), levures de 003 comprises | noms et valeurs techniques | `notes`, descriptions, recettes, équipements |
| Brewtarget 005 | noms et valeurs techniques, provenance entrée par entrée (`folder_path`) | `notes` et URL, recettes, styles, équipements, eaux |
| BJCP 2021, fichier 002 seul (110 styles) | nom, code, catégorie, type, guide, plages chiffrées | descriptions, traductions, tout lien vers bjcp.org, toute demande au BJCP, styles de 001 et 005 |
| DIY Dog (`alxiw/punkapi`, `e6c12ab`) | recettes, usage privé, `method.twist` dans `notes` (seul texte libre gardé) | images, textes libres (`description`, `tagline`, `food_pairing`, `brewers_tips`), `contributed_by` |
| `diydog-beerxml` (`d469275`) | tests locaux, hors CI | Firestore, dépôt |
| Kaggle | agrégats `style_stats/`, si la licence de la page le permet | lignes brutes |

Le fichier 005 est un mélange, d'après son en-tête : malts de The Swaen, éléments de la Canadian
Homebrewers Association, exemples dotBeer, et « le reste » depuis beer-analytics.com sous
CC BY-SA 4.0. Seul ce reste porte `licence: CC BY-SA 4.0`.

Ce que CC BY-SA 4.0 impose quand la matière est partagée :

- Section 3(a) : nommer le créateur désigné, garder les mentions de copyright, de licence et de
  garantie fournies, donner un lien vers la matière, signaler la modification, et indiquer la
  licence avec son lien. Un lien vers une page qui contient ces informations est admis.
- Section 3(b) : une adaptation partagée reste sous CC BY-SA 4.0 ou une licence compatible, sans
  restriction ajoutée. GPLv3 est compatible dans un seul sens : de BY-SA 4.0 vers GPLv3.
- Section 4(2) : une base qui contient une part substantielle de la matière est une adaptation.

La section 1.11 définit le partage comme une mise à disposition du public. Le statut d'un groupe
invité de moins de 10 comptes n'est pas tranché ici. L'attribution s'applique dans tous les cas :

- écran « Sources des données », ouvert à tout membre : Brewtarget (GPL-3), beer-analytics.com
  (CC BY-SA 4.0, lien vers la licence, modifications : unités normalisées, doublons fusionnés),
  DIY Dog ;
- `provenance[]` de chaque entrée ;
- `documentation/DATA_SOURCES.md` : licence, version et SHA de chaque source.

Le partage à l'identique reste sans effet tant que le référentiel n'est pas publié. Aucun export
du référentiel n'existe. Une publication future demanderait un ADR, et `provenance[]` permet
d'isoler les entrées concernées.

## Livraisons

Durées estimées, non mesurées.

| Livraison | Contenu | Critère de fin | Durée |
|---|---|---|---|
| L0 Cadrage | cet ADR, `DATA_SOURCES.md` | ADR accepté, correspondances validées | 1 j |
| L1 BeerJSON en base | réécriture du modèle, éditeurs, règles et tests, CI, brassage à blanc, passage en production | recettes et brassins au nouveau format, brassage à blanc réussi sur l'APK en mode avion | 4 à 5 j |
| L2 Échange | `exchange/`, unités et rendement de brassage dans `brewing/`, import et export BeerJSON et BeerXML, écrans | aller-retour BeerXML réussi sur les fixtures, export BeerJSON valide contre le schéma figé | 3 à 4 j |
| L3 Données | règles des collections, `ingest/`, lecteur dotBeer, table d'alias, statistiques Kaggle après vérification de sa licence, passage à Node 24 | ingestion relancée sans doublon, rapport chiffré | 3 j, table d'alias d'environ 245 noms non comptée |
| L4 Application | Admin › Sources, écran « Sources des données », recettes publiques, sélecteur | compteurs et ingrédients non résolus visibles, recette publique dupliquée | 2 j |

L2 à L4 peuvent s'intercaler avec la v0.5 et la v0.6.

**Amendements de L2 (décisions de l'utilisateur du 2026-11-10).**

- L2 se livre en trois PR : L2a (lecture et calculs), L2b (`exchange/`, BeerJSON, écrans, canal de
  fichiers d'ADR-007), L2c (BeerXML). Chacune fusionne dès que sa CI est verte ; le brassage à
  blanc de l'utilisateur porte sur l'ensemble. `effacement-l1/` reste jusqu'à ce brassage.
- Décision 8 remplacée : le rendement exporté (`efficiency.brewhouse`) est le rendement
  d'empâtage de l'équipement, tel que `brewing/` l'applique. Aucun calcul de rendement de
  brassage n'entre dans `brewing/`. Critère : le logiciel qui relit trouve une densité initiale à
  2 points près. Le rendement d'un fichier importé n'est donc pas stocké : `recipe.efficiency`
  manque toujours en base, et `recipe.author` seul est ajouté (marge des règles mesurée à la
  création d'un brassin).
- Décision 11 modifiée : Recettes › Importer lit 500 recettes et 10 Mo au plus par fichier ; au-delà
  de 500, les 500 premières, avec un avertissement. L'écriture reste sous le compte de
  l'importateur, une recette à la fois.
- Export BeerXML : bloqué tant que `beer_styles` manque (L3), avec la raison affichée ; aucune
  valeur de style inventée. (Débloqué par E4, amendements de L3 et L4.) L'import BeerXML et l'export BeerJSON marchent en L2.
- Doublon : empreinte du contenu dans `imported_from` ; recette déjà importée marquée et décochée.
- Quantités en volume : un ajout, un houblon extrait et une levure peuvent porter `amount` en `l`
  (étend la décision du 2026-11-10 sur la levure). Un houblon en volume ne compte pas dans l'IBU.
- Un whirlpool importé sans durée se lit comme un ajout à l'arrêt du feu, perte listée ; la levure
  BeerXML `Wheat` devient `wheat` ; `brewing/` convertit `potential` en % ; `source_hop_timing`
  est reporté à L3.
- P9 gagne une clause (accord de l'utilisateur du 2026-11-10) : les caractères de contrôle
  bidirectionnels (U+061C, U+200E, U+200F, U+202A à U+202E, U+2066 à U+2069) sont retirés des
  textes d'un fichier importé.
- L2a (v0.1.17) étend `computeRecipe` sans changer de formule existante : malt de nature inconnue
  (`other`) et forme de houblon hors pellets et cônes rendent la densité ou l'IBU indisponibles
  (nouveaux `MissingInputKind`), houblon à l'empâtage ou au conditionnement à 0 IBU qui rend
  l'IBU indisponible, houblon en volume hors IBU (`hopsWithoutMass`), conversions Plato, SRM,
  Lovibond et `potential` ; chaque cas a sa fixture.
- Prix au litre (décision de l'utilisateur du 2026-11-10) : « Mes prix » accepte l'unité `l`. Une
  ligne en volume se chiffre à partir d'un prix au litre et entre dans le coût figé d'un brassin.
  Une ligne en grammes face à un prix au litre reste incompatible : aucune densité n'est
  supposée.

**Écart de L1, à reprendre en L2** (repris en L2a, v0.1.17). La lecture de la v0.1.15 rend illisible un document qui
porte une valeur que « Valeurs sans équivalent direct » veut garder : malt `extract`, houblon
`add_to_mash` ou `add_to_package`, `time` sur un ajout à cru, forme de houblon `plug`, `powder`
ou `extract`. L'éditeur n'en écrit aucune, et aucun document de L1 n'en contient. L2 les lit
avant d'ouvrir l'import.

**Règles de L1.** Le contrôle d'une recette et celui d'un brassin approchent la limite de
1 000 expressions par requête. La création d'un brassin a sa propre règle, limitée aux champs
écrits par l'application, et la modification ne recontrôle pas la copie figée, qui est
immuable. Un import de brassins déjà brassés (v0.6) créera donc le brassin, puis le modifiera.
Les éléments des listes ne sont pas contrôlés par les règles : un champ inconnu y reste
possible, sous le seul compte de son auteur, et la lecture typée l'ignore.

**Amendements de L3 et L4 (décisions de la session principale du 2026-11-11, accord de
l'utilisateur de décider jusqu'à la fin de L4).** L3 et L4 avancent par étapes : les données en
base (v0.1.25), puis la consultation dans l'application, puis le reste de L4.

- D1. Kaggle (`style_stats/`) est reporté. La page déclare « CC0: Public Domain » (relevé du
  2026-11-11, API Kaggle), mais le téléchargement demande un compte Kaggle absent du poste.
  Aucune règle ni aucun code pour `style_stats` tant qu'il n'y a pas de donnée (« Pas de code
  mort »).
- D2. La CI ne change pas dans ces étapes. Node 24 et une étape `ingest/` dans `ci.yml`
  viendront plus tard : la décision 10 est maintenue, sa livraison décalée. Les tests
  d'`ingest/` tournent en local.
- D3. Les champs d'enveloppe `style_id`, `ingredient_refs` et `source_hop_timing` n'entrent pas
  dans `recipes/` à ces étapes : il reste environ 40 expressions de marge à la création d'un
  brassin. Ils existent dans `public_recipes/`, écrit par le script seul.
- D4. L'ingestion recopie dans chaque ligne d'une recette publique les valeurs techniques de
  l'entrée résolue quand la source n'en donne pas : malt `type`, `yield` et `color`, houblon
  `alpha_acid`, levure `type`, `form` et `attenuation`. Le rapport compte ces valeurs. Une
  valeur de la source n'est jamais remplacée. Un nom non résolu reste sans valeur ; une ligne
  de malt non résolue garde le type `grain`, car DIY Dog la range dans `malt` sans autre
  précision (11 lignes résolues sont du miel, du dextrose, du sucre ou du lactose).
- D5. La préparation est en Dart, dans `exchange/` : bibliothèque séparée
  `package:exchange/ingestion.dart`, jamais importée par l'application, et
  `exchange/bin/preparer_referentiels.dart`. Elle lit `import/sources/` et écrit
  `import/ingest/prepare/<collection>.json`. L'écriture est en Node 24, paquet `ingest/`
  (Admin SDK), qui lit ces fichiers.
- D6. `import_unresolved/` est écrit par le script seul (nom de DIY Dog non résolu) et lu par
  l'admin. La création par un membre arrivera avec la résolution à l'import (étape 3). (Livrée
  à l'étape 3 : voir E6.)
- D7. Première écriture en production le 2026-11-11 (12:49Z), par l'administrateur, avec ses
  ADC de compte utilisateur (`authorized_user`) : 2 525 documents écrits, 0 refusé. Le compte
  `kassbeer-ingest` est reporté. L'écrivain refuse une clé de compte de service :
  `GOOGLE_APPLICATION_CREDENTIALS` et `CLOUDSDK_CONFIG` sont refusés, et le fichier ADC doit
  être de type `authorized_user`, ou `impersonated_service_account` dont la source est
  `authorized_user`. Cette écriture a précédé la correction du type des malts (D4) : 11 lignes
  de recettes portent encore `grain` en production. La prochaine exécution, prévue après la
  fusion, réécrira ces seules recettes.
- D8. La forme d'un houblon est facultative à la lecture, parce que DIY Dog ne la donne pas.
  L'IBU d'un houblon d'ébullition sans forme est « à compléter », et l'éditeur demande la
  forme. Ce code est livré par la branche des écrans.

Décisions de l'étape 3, côté recettes (v0.1.28) :

- E1. Aucun champ n'entre dans `recipes/` ni dans `recipe_snapshot` : D3 tient, à cause du
  budget des règles. Pas de `style_id` ni d'`ingredient_refs` en base. Le style d'une recette
  reste `recipe.style.name`, et le lien avec le référentiel se retrouve par le nom, au moment
  voulu. Les règles de `recipes/` et de `brews/` ne changent pas.
- E2. Dans l'éditeur, le champ « Nom » d'un malt, d'un houblon, d'un ajout ou d'une levure propose
  les entrées de `beer_index/` de sa nature, par nom et alias, filtrées sur l'appareil. Le choix
  remplit les valeurs vides : malt `type`, rendement et couleur ; houblon acide alpha et forme ;
  levure type, forme et atténuation. Une valeur saisie n'est remplacée que par « Reprendre les
  valeurs de la Bibliothèque ». La saisie libre reste possible. L'index se lit à l'ouverture du
  champ, par `get` mémorisé ; hors ligne, il se lit dans le cache seul, et sans lui l'éditeur marche
  sans suggestions et relit à la prise du focus suivante. Un ajout reçoit son type s'il est vide.
- E3. Le champ « Style » propose les styles de `beer_index/styles`, par code ou nom, et écrit
  `recipe.style.name` avec le nom exact du style. La saisie libre reste possible.
- E4. L'export BeerXML est débloqué. Il retrouve le style par son nom exact dans
  `beer_index/styles`, puis lit `beer_styles/{id}` par `get` (catégorie, code, type, guide,
  plages). Sans style, ou avec un style introuvable sous ce nom exact, l'export est bloqué et
  demande de choisir le style dans les suggestions du champ Style. Les autres règles de `manquesExportBeerXml` restent, dont la forme du houblon
  (D8). Le type et les plages du `STYLE` suivent E7.
- E5. À l'ouverture de Recettes › Importer, les index des malts, houblons, levures et ajouts
  se lisent par `get` mémorisé. Une ligne sans valeur technique dont le nom se résout
  exactement après normalisation (nom ou alias, et pour une levure souche, référence, ou
  producteur et référence) reçoit la valeur de l'index, comme D4. Une valeur du fichier n'est
  jamais remplacée. Le compte rendu liste les valeurs reprises. Hors ligne ou index absent,
  l'import marche comme avant, avec une ligne au compte rendu. Normalisation et résolution sont
  dans `exchange/` (`noms.dart`, `resolution_import.dart`), en Dart pur, l'index reçu en
  paramètre ; `noms.dart` est commun à l'ingestion, que l'application n'importe pas.
- E6. Après un import, l'application crée ou met à jour `import_unresolved/{empreinte}` pour
  chaque nom non résolu, par un `set` fusionné : `nature`, `key` (nom normalisé, 100 caractères
  au plus), `name` (120 caractères au plus), `source: import`, `count` (1, puis + 1 par import,
  `FieldValue.increment(1)`), `updated_at` (`serverTimestamp`) ; aucun e-mail, uid ni nom de
  fichier. 200 noms au plus par import, envoyés par lots de 10 (`WriteBatch`) ; les suivants
  sont comptés au compte rendu. Écriture simple, permise hors ligne. L'empreinte d'un import
  est le SHA-256 de `import|nature|key` : elle ne croise jamais celle du script (`nature|nom
  normalisé`, sans `key`), et Admin › Sources montre les deux lignes avec leur origine. Les
  règles admettent la création par un membre (liste blanche, `source == import`, `count == 1`,
  `hashing.sha256('import|' + nature + '|' + key).toHexString().lower()` égal à l'identifiant,
  essayé dans l'émulateur) et la mise à jour d'un document d'import, où seuls `name` (texte de 1
  à 120 caractères, pour une autre casse ou d'autres accents), `count` (+ 1 exactement) et
  `updated_at` (`request.time`) changent ; `nature`, `key` et `source` restent. Lecture par
  l'admin seul, aucune suppression. Un échec de signalement est rapporté et n'empêche pas
  l'import.
- E7. Choix de l'étape 3 : décision de la session principale, sous l'accord de l'utilisateur du
  2026-11-11 de décider jusqu'à la fin de L4 ; à relire par l'utilisateur.
  - le `TYPE` du `STYLE` BeerXML d'un style BJCP de type `beer` se déduit des levures de la
    recette : `ale` et `kveik` donnent `Ale`, `lager` donne `Lager`, `wheat` donne `Wheat`,
    une levure de fermentation mixte ou bactérienne, ou deux classes différentes, donnent
    `Mixed` ; sans levure typée, ou avec une levure de vin, de champagne ou `other`, l'export
    est bloqué. `mead` et `cider` donnent `Mead` et `Cider` ;
  - un style sans catégorie, code, guide ou une plage de densité, d'amertume ou de couleur bloque
    l'export BeerXML : 17 styles BJCP n'ont aucune plage, IPA Argenta n'a pas de densités ;
    aucune plage n'est inventée ;
  - une levure importée se résout aussi par sa référence seule (`US-05`) ou par son producteur
    et sa référence (`Fermentis US-05`), quand une seule entrée correspond ;
  - la forme d'un houblon et le type d'un autre ajout sont repris à l'import, en plus des
    valeurs de D4 ; l'éditeur reprend aussi le type vide d'un ajout.

Constats de la livraison de l'étape 1 (v0.1.25) :

- Une même souche de levure chez un même producteur (`SafAle S-04` et `SafAle English Ale`,
  référence `S-04`) ne fait qu'un document : sans ce regroupement, 902 documents au lieu de 845.
- `recipe.boil` est absent des recettes publiques, et la température de fermentation de DIY
  Dog n'est pas reprise : `isBeerJsonRecipe` n'a de clé ni pour le volume avant ébullition ni
  pour `fermentation`. Un palier sans durée est écarté (57 paliers, 58 recettes sans empâtage) :
  `step_time` est obligatoire dans le schéma partiel et dans la lecture de l'application.
- Aucun houblon d'une recette publique ne porte `form` : DIY Dog ne la donne pas. La lecture
  de la v0.1.23 (`HopLine.fromFirestore`) exige `form` : D8 la rend facultative.
- Les règles n'ouvrent que `get` sur les référentiels et `beer_index`, et sur `public_recipes`
  une requête de 50 documents au plus (`request.query.limit <= 50`, P22).

## Calendrier et passage en production

Cadrage (L0) maintenant. Passage à BeerJSON (L1) juste après la fusion de la v0.4, avant la v0.5
et la v0.6, si possible avant le prochain brassin, prévu vers le 22 novembre 2026.

Ordre constaté le 2026-11-10 : la v0.5 (prix, frais et coût) a fusionné la première, en v0.1.13,
puis le menu du compte et l'écran « Nouveautés » en v0.1.14. L1 les intègre et devient la v0.1.15. Les coûts figés `users/{uid}/brew_costs/{brewId}` existent
donc au passage : l'effacement compte et efface le coût figé de chaque brassin effacé, comme la suppression
d'un brassin dans l'application (CB19), et rien d'autre sous `users/`. Ces coûts portent les prix
de chaque brasseur : l'outil ne lit pas leur contenu et ne les copie pas, y compris ceux de
l'administrateur (décision du 2026-11-10).

**Décision de passage.** Vers le 15 novembre 2026, sept jours avant le brassin, L1 doit être
prêt : CI verte. Sinon, le brassin se fait sur le modèle plat.

**Ordre retenu le 2026-11-10.** Aucun environnement ne permet le brassage à blanc avant la fusion :
les règles de production refusent le nouveau format, l'application n'a aucun branchement vers
l'émulateur, et il n'existe pas de second projet Firebase. L'utilisateur a choisi de passer
d'abord, puis de faire le brassage à blanc en production (étape 7 ci-dessous). En cas d'échec, le
retour au modèle plat est un `git revert -m 1` du commit de fusion de L1, livré en version
suivante ; les recettes et brassins créés pendant l'essai sont alors effacés.

**Effacement.** La commande efface tous les documents de `recipes/`, `brews/` et leurs `events/`,
quel que soit leur format (décision du 2026-11-10). C'est une exception ponctuelle à la règle
« Une écriture de masse a un seul écran » de `CLAUDE.md`, acceptée par l'utilisateur.

**Effacement sans perte.** Il suppose qu'aucun vrai brassin n'est enregistré. La commande
d'effacement lance d'abord un compte rendu sans écriture : nombre de recettes, liste des brassins
avec statut, date et nombre de mesures. L'utilisateur confirme ou non.

Déroulé, tous les cas :

1. Prévenir les comptes. Chacun ouvre l'application en ligne, attend la fin de « En attente du
   réseau » et n'utilise plus l'application pendant le passage. Aucun brassin en statut `brewing`.
2. Lancer le compte rendu. L'utilisateur confirme.
3. Sauvegarde : la sauvegarde quotidienne (7 jours) existe. Copier en plus `recipes/` et `brews/`
   en JSON dans `import/backup/`, dossier ignoré par Git. Les coûts figés ne sont pas copiés.
4. Fusionner L1 sur `main`. `deploy.yml` publie le site, les règles et un APK au numéro de build
   supérieur. Une fusion vaut passage : L1 ne fusionne pas avant cette étape.
5. Dès la fin du déploiement, effacer `recipes/`, `brews/` et leurs `events/` par `recursiveDelete`,
   puis le coût figé de chaque brassin effacé, après la saisie du nom du projet et une relecture.
   `equipment/` et le reste de `users/` ne sont pas touchés.
6. Vérifier : recette créée, brassin créé, aucune entrée nouvelle dans `error_reports/` depuis
   l'heure de l'effacement.
7. Brassage à blanc sur l'APK, en mode avion pour l'écran du jour. En cas d'échec : retour au
   modèle plat, comme décrit plus haut.

La commande d'effacement sort du dépôt à la livraison suivante (« Pas de code mort »).

**Si un vrai brassin existe.** Pas de passage tant qu'il est en `brewing`. Ensuite, ce brassin est
ressaisi ou converti.

- Converti, recommandé dès qu'il a des mesures : un outil à usage unique récrit `recipe_snapshot` et
  la recette source au format BeerJSON, par l'Admin SDK, avec le même identifiant de document. Les
  `events/` et les `step_key` restent valides, car `brew_steps` ne change pas. L'effacement épargne
  ces deux documents. L'outil sort du dépôt ensuite.
- Ressaisi : recette et brassin recréés à la main, mesures comprises.

**APK déjà installés (moins de 10 comptes).** Aucune mise à jour forcée n'existe.

- App Distribution envoie le nouvel APK au groupe `brasseurs`. Chaque brasseur l'installe par
  l'e-mail ou App Tester, sans désinstaller : le cache local reste compatible.
- Un ancien APK affiche « Recette illisible » sur les nouveaux documents, et ses créations sont
  refusées par les règles. Il n'efface rien.
- L'administrateur contacte chaque brasseur et vérifie `app_version` au besoin.
- Web : `index.html` est en `no-cache`, un onglet déjà ouvert se recharge à la main.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : conversion et résolution sur l'appareil, et sur le poste
   pour l'ingestion. Écriture de masse sur le poste, par l'Admin SDK. Aucun code serveur.
2. **Ce qui existera en double** : rien. ajv vérifie et ne produit rien. Le schéma partiel se
   dérive du schéma officiel en CI.
3. **Ce qui pèse au démarrage** : rien de plus au lancement. `beer_index` se lit à l'ouverture de
   l'import. Poids de `exchange/` sur le web mesuré à la livraison.
4. **Compilation de chaque cible** : `flutter build web` et `flutter build apk`. `xml` 7.1.0 exige
   Dart 3.13, `app/pubspec.lock` est en Dart 3.12 : rester sur 7.0.1 (P6).
5. **Qui voit quoi** : référentiels et recettes publiques lisibles par les membres, écrits par
   aucun client. Un import écrit sous le compte de l'importateur. Aucun prix ni stock d'un fichier
   importé n'entre en base : la lecture typée les ignore, car les règles n'inspectent pas les
   listes (P5).
6. **Ce qui coûte à l'usage, plafond** : aucun poste ajouté. Ingestion : moins de 4 000 écritures,
   20 % du quota quotidien. Effacement : suppressions sous le quota de 20 000 par jour. Session :
   5 lectures de `beer_index` et une page de 50. Alerte à 5 € inchangée.
7. **Exposition** : aucun point d'accès ajouté. Fichiers lus sur l'appareil de l'importateur (P9).
8. **Exploitation, sauvegarde, mise à jour** : ingestion relancée à la main. Données dans la
   sauvegarde quotidienne. Passage décrit ci-dessus.
9. **Coût de sortie** : `exchange/` n'a aucune dépendance Firebase. Les recettes sont déjà au format
   BeerJSON, partiel. `firebase-tools` 15.35.0 déclare un runtime `dart3`, au statut « experimental ».

## Quand revenir sur cette décision

Un ADR propose les Cloud Functions à l'arrivée de l'IA, du RAPT Pill, d'une décision que le client
ne peut pas prendre seul, ou d'une ouverture au-delà des comptes invités.

Conditions relevées dans `firebase-tools` 15.35.0, sans déploiement d'essai : `functions.yaml`
évite d'exécuter le code dans le job qui détient le jeton ; la politique de nettoyage d'Artifact
Registry se pose une fois à la main ; `roles/cloudfunctions.admin` et `roles/iam.serviceAccountUser`
sur les seuls comptes d'exécution et de build ; API `cloudfunctions`, `cloudbuild`,
`artifactregistry`, `run`, `eventarc`, `pubsub`, `storage`. La permission de `generateServiceIdentity`
reste à vérifier.

## Conséquences

Plus simple : recettes publiques, import et export partagent une forme. L'export BeerJSON est court.
Les 16 fiches de la v0.6 peuvent viser cette forme.

Plus difficile : cinq champs de saisie s'ajoutent, ou l'export reste bloqué. Chaque lecture passe
par des couples `{value, unit}`. La version du schéma est figée, et son évolution suit un ADR.
`roles/datastore.user` ne se limite pas à une collection : la liste blanche du script et l'emprunt à
la demande sont les seuls garde-fous.

Le tableau « Logique dupliquée » reste vide. La règle « Une écriture de masse » reçoit une exception.
P3, P9, P10 changent, P19 à P22 s'ajoutent.

## Évolutions du réseau acceptées

Acceptées par l'utilisateur le 2026-11-08. À appliquer par le skill `evolution-reseau`, après la
fusion de la v0.4, quand le code concerné arrive. Texte à reprendre dans `CLAUDE.md` :

- **« Une écriture de masse », exception.** L'ingestion d'une source externe passe par un script
  local (`ingest/`), lancé par l'administrateur. Il écrit dans l'émulateur par défaut, en production
  sur option explicite, dans une liste blanche de collections, avec un identifiant déterministe et un
  rapport JSON chiffré. Admin › Sources affiche les compteurs et les ingrédients non résolus.
  Recettes › Importer, limité à 500 recettes (50 avant les amendements de L2) sous le compte de l'importateur, n'est pas une écriture
  de masse.
- **« Règles de code », ajout : recettes en BeerJSON partiel.** `recipes/{id}.recipe` et
  `recipe_snapshot.recipe` suivent `RecipeType` du schéma figé (ADR-005). Unités canoniques seules,
  en couples `{value, unit}` : `g`, `l`, `C`, `min`, `EBC`, `sg`, `%`. Les unités d'une source se
  convertissent à l'import ; l'écran ne fait que présenter (« 1057,9 », saisie des malts en
  kilogrammes). Un champ obligatoire inconnu reste absent : aucune valeur inventée. L'export bloque et
  liste ce qui manque. Durées en minutes entières. `key` n'est pas stockée : `ingredientKey` la dérive.
- **« Unités » et « Le projet ».** Le modèle de `recipes/` et `recipe_snapshot` est BeerJSON partiel.
  `equipment/` reste plat. Import et export : paquet `exchange/`.
- **« Structure ».** `exchange/` : paquet Dart pur, import et export BeerJSON et BeerXML, résolution
  des ingrédients. `ingest/` : écrivain Node, Admin SDK ; données dans `import/`. À la livraison
  L3, `rules-tests/`, `ingest/` et la CI passent en Node 24 (`ci.yml`, `deploy.yml`, P10).
- **P9 (`securite`), remplacé.** Import : chaque fichier est borné (10 Mo et 500 recettes depuis les amendements de L2, au lieu de 2 Mio et 50 recettes ; plafonds de
  listes des règles), décodé en UTF-8 ou ISO-8859-1, lu champ par champ vers des types ; nombres finis
  et bornés ; aucune entité XML étendue (test) ; aucun prix ni stock lu ; une écriture d'import reste
  sous `owner_uid` de l'importateur ; un texte d'un fichier n'est jamais exécuté comme consigne.
- **P3 (`relecteur-regles`), étendu.** Conversion Plato, Lovibond ou SRM hors de `brewing/` : anomalie.
  Valeur calculée d'un export : issue de `computeRecipe`.
- **P10 (`relecteur-regles`), étendu.** Ajouter à la liste : `ingest/package.json`,
  `ingest/package-lock.json`, `ingest/prettier.config.*`.
- **P19 (`securite`), nouveau.** `beer_*`, `beer_index`, `public_recipes`, `style_stats`,
  `ingest_runs` : `allow write: if false` ; lecture membres (`ingest_runs` : admin).
  `import_unresolved` : création par un membre, champs en liste blanche, lecture admin. Tests pour les
  cinq profils de P4.
- **P20 (`relecteur-regles`), nouveau.** Aucun fichier de Brewtarget, DIY Dog, `diydog-beerxml` ou
  Kaggle dans le dépôt, un asset ou l'APK ; fixtures écrites à la main. Référentiels : noms et valeurs
  techniques seuls, aucun `notes`, description ou URL. Styles BJCP : nom, code, catégorie, type,
  guide, plages chiffrées ; aucune description, traduction ni lien vers bjcp.org. Chaque source a sa ligne dans `DATA_SOURCES.md`
  (licence, version, SHA). Toute entrée issue de la part CC BY-SA 4.0 du fichier 005 porte cette licence
  dans `provenance[]`, et l'écran « Sources des données » nomme beer-analytics.com, la licence, son lien
  et les modifications.
- **P21 (`relecteur-regles`), nouveau.** Diff du modèle de recette : `recipe` et `recipe_snapshot`
  restent BeerJSON partiel, au commit figé par ADR-005. Unités canoniques. Champ d'extension dans
  l'enveloppe, jamais dans `recipe`. `recipeFields()` et la liste des champs de `recipe` sont à jour dans
  `firestore.rules`, avec tests et copie figée. Liste des champs absents permis inchangée, ou ADR. Le
  schéma partiel passe en CI sur les documents de `toFirestore`, et le schéma officiel sur les sorties
  de l'export.
- **P22 (`relecteur-regles`), nouveau.** Aucun écouteur ni lecture entière sur `beer_*` ou
  `public_recipes` : `beer_index` par `get`, pages de 50.
- **`.claude/formatters.json`.** `{ "prefix": "exchange/", "extensions": [".dart"], "cwd": "exchange",
  "command": "dart format {file}" }`, et la même règle pour `ingest/` avec prettier.
  `setup-projet.sh` ajoute `(cd exchange && dart pub get)`.

## Sources

Consultées le 2026-11-08.

- BeerJSON (MIT) : https://github.com/beerjson/beerjson, commit `4370892d44` ; npm `@beerjson/beerjson`
  1.0.2 (2021-10-12), Draft-07.
- BeerXML 1.0 : https://www.beerxml.com/beerxml.htm
- CC BY-SA 4.0 : https://creativecommons.org/licenses/by-sa/4.0/legalcode ; compatibilité GPLv3 :
  https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/
- En-tête de `data/DefaultContent005-Fermentables-Recipes.beer`, Brewtarget v5.2.3.
- Firestore, `europe-west1` : 0,033 $ pour 100 000 lectures, 0,099 $ pour 100 000 écritures, 0,011 $
  pour 100 000 suppressions, 0,165 $ par Gio et par mois ; quotas gratuits ; écouteurs :
  https://cloud.google.com/firestore/pricing
- Cloud Run, Cloud Build, Artifact Registry (option C écartée) :
  https://cloud.google.com/run/pricing, https://cloud.google.com/build/pricing,
  https://cloud.google.com/artifact-registry/pricing
- Rôles de déploiement : https://cloud.google.com/functions/docs/reference/iam/roles
- `firebase-tools` 15.35.0 : https://github.com/firebase/firebase-tools/tree/v15.35.0/src/deploy/functions
- Dart `xml` : https://pub.dev/packages/xml
- Taille d'un document et limites des règles : https://firebase.google.com/docs/firestore/quotas,
  https://firebase.google.com/docs/firestore/security/rules-structure
- DIY Dog, aucune licence écrite trouvée : https://blog.brewdog.com/blog/diy-dog
- Licences et comptes des sources : relevés de la session principale, GitHub, 2026-11-08.
- Estimations non mesurées : taille de `beer_index`, durées de développement.
