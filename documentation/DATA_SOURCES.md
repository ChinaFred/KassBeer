# Sources de données

Sources externes du socle données (ADR-005) : version figée, licence, ce qui est retenu, et
correspondance de chaque source vers le modèle de Kass'Beer.

Relevé du 2026-11-08, sur les fichiers eux-mêmes. Les licences sont des constats, pas un avis
juridique. **Statut : validé par l'utilisateur le 2026-11-08.** Reste à vérifier avant L3 : la
licence de la page Kaggle et ses colonnes.

Aucun fichier de ces sources n'entre dans le dépôt public, un asset ou l'APK. Les données vivent
dans `import/`, ignoré par Git. Les fixtures de test sont écrites à la main.

## Sources, versions et licences

| Source | Version figée | Licence constatée | Retenu | Écarté |
|---|---|---|---|---|
| Brewtarget 001, BeerXML, ISO-8859-1 | tag v5.2.3, `ea10908` | GPL-3 (`COPYRIGHT`, `Files: *`) | noms et valeurs techniques | `notes`, 29 recettes, 33 équipements, 127 styles d'anciennes éditions |
| Brewtarget 002, BeerJSON 2.01 | idem ; amont `beerjson/bjcp-json` (MIT) | texte sous copyright du BJCP | nom, code, catégorie, type, guide, plages chiffrées | descriptions, `tags`, `examples`, traductions, lien vers bjcp.org |
| Brewtarget 003, BeerJSON 2.01 | idem ; amont `brewerwall/yeasts`, sans licence | GPL-3 | noms et valeurs, 296 levures comprises (décision de l'utilisateur) | `notes`, `substitutes` |
| Brewtarget 004, BeerJSON 2.01 | idem | GPL-3 ; sources non nommées | noms et valeurs | `notes` |
| Brewtarget 005, DotBeer 1.0.0 | idem | en partie CC BY-SA 4.0 (beer-analytics.com), reste sous GPL-3 générale | noms et valeurs, licence par entrée selon `folder_path` | `notes`, URL, 9 recettes, 9 styles, équipements, eaux |
| `alxiw/punkapi` | `e6c12ab` | MIT sur le code ; aucune licence écrite pour les recettes BrewDog | 415 recettes, usage privé, avec `method.twist` dans `notes` (seul texte libre gardé) | 327 images, `description`, `tagline`, `food_pairing`, `brewers_tips`, `contributed_by` |
| dépôt GitHub `diydog-beerxml` | `d469275` | aucune | tests locaux, hors CI | Firestore, dépôt |
| Kaggle « Brewer's Friend Beer Recipes » | à télécharger | non confirmée, à vérifier avant L3 | statistiques par style | lignes brutes, CSV |
| BeerJSON | `4370892d44` | MIT | schémas pour ajv en CI et à l'ingestion | — |

Attribution : l'écran « Sources des données », ouvert à tout membre, nomme Brewtarget (GPL-3),
beer-analytics.com (CC BY-SA 4.0, lien vers la licence, modifications : unités normalisées, doublons
fusionnés) et DIY Dog. Chaque entrée porte sa licence dans `provenance[]`.

## Volumes

Entrées brutes avant dédoublonnage. Noms uniques après normalisation (casse, accents, ponctuation).

| Nature | 001 | 003 | 004 | 005 | Total brut | Noms uniques |
|---|---|---|---|---|---|---|
| Malts et sucres | 369 | — | — | 251 | 620 | 462 |
| Houblons | 126 | 282 | — | 418 | 826 | 466 |
| Levures | 37 | 296 | 275 | 703 | 1 311 | 791 |
| Divers | 84 | — | — | 43 | 127 | 122 |
| Styles | 127 | — | — | 9 | 136, plus 110 dans 002 | non mesuré |

## Unités

| Grandeur | Sources | Canonique | Conversion |
|---|---|---|---|
| Masse | BeerXML en kg ; DIY Dog en `kilograms`, `grams`, `kilogram` | `g` | `exchange/` |
| Volume | BeerXML et DIY Dog en litres | `l` | identité |
| Température | 003 et 004 surtout en `F` ; 005 en `C` | `C` | `exchange/` |
| Couleur | 005 : 169 en EBC, 82 en `Lovi` ; 001 (BeerXML) : Lovibond, SRM pour un extrait liquide | `EBC` | `brewing/` (P3) |
| Densité | DIY Dog : `1042` | `sg`, `1.042` | `exchange/` |
| Rendement | BeerXML `YIELD`, 005 `yield_fine_grind` | `%` | identité |
| Rendement en densité | BeerJSON `yield.potential` (densité d'une livre dans un gallon) | `%` | `brewing/`, `potentialToYieldPercent` (v0.1.17) |
| Quantité d'un houblon, d'un ajout, d'une levure | masse ou volume | `g` ou `l`, gardée dans son unité (décision du 2026-11-10) | `exchange/` pour les unités impériales |

Un `{value, unit}` d'une unité inconnue est rejeté et compté au rapport.

## Correspondance BeerJSON (import utilisateur) → modèle

Lecture de `exchange/` (v0.1.20), fichiers BeerJSON 1, 2 et 3 choisis par un membre dans
Recettes › Importer. Le modèle est déjà en BeerJSON : la lecture garde les champs de
`RecipeType` que l'application stocke et convertit les unités.

| Champ | Valeur source | Résultat |
|---|---|---|
| Masse, volume, température, durée | `mg`, `kg`, `lb`, `oz` ; `ml`, mesures américaines et impériales ; `F` ; `sec`, `hr`, `day`, `week` | `g`, `l`, `C`, `min` (minutes arrondies, listé) ; conversion dans `exchange/` |
| Couleur d'un fermentescible | `Lovi`, `SRM` | `EBC` par `brewing/` |
| `yield` | `fine_grind` ; sinon `potential` en `sg` ; `coarse_grind` seul | `fine_grind` ; `potentialToYieldPercent` de `brewing/` ; absent, listé |
| `yield.fine_grind`, `alpha_acid` | 0 | absent, listé |
| `HopAdditionType.timing`, `use: add_to_boil` | `time` ; sinon `duration` ; `time` 0 avec `duration` | ébullition `time` ; ébullition `duration` (ADR-005) ; après l'arrêt du feu, pour `duration` |
| `timing` d'un ajout à cru, à l'empâtage, au conditionnement | `time` en plus de `duration` | `duration` seule, simplification listée (le jour d'ajout d'un houblon à cru est gardé) |
| Quantité d'une levure | `pkg`, `each`, `unit` | absente, listée ; pour un malt, un houblon ou un ajout, recette refusée |
| `style` | objet complet | nom seul (ADR-005 : la catégorie demande `beer_styles`), listé |
| `efficiency`, valeurs annoncées, `fermentation`, `water_additions`, `packaging`, `taste` | toute valeur | non importés, listés |
| `inventory`, prix, champs inconnus | toute valeur | ignorés, comptés (P5) |
| Valeur convertie au-delà des plafonds | plus de 1 000 kg ou 1 000 L par ligne, 10 000 L de volume, 2 000 EBC, 365 jours hors ébullition, nombre non fini | quantité obligatoire : recette refusée ; valeur facultative : absente, listée |

## Correspondance BeerXML → BeerJSON

Sert à l'import utilisateur (lecture de `exchange/`, v0.1.21) et au fichier 001. BeerXML 1.0
est métrique : kilogrammes (convertis en grammes), litres, °C, minutes. Les valeurs
énumérées se lisent sans casse. Encodages : UTF-8 (par défaut), ISO-8859-1, windows-1252 et
US-ASCII déclarés, ces trois derniers décodés en windows-1252 (standard du WHATWG) ; autre
encodage, `DOCTYPE` ou entité autre que les cinq prédéfinies et les références numériques :
fichier refusé (P9). Une perte « listée » est une ligne de « Modifié à l'import ».

| Champ | Valeur source | Résultat |
|---|---|---|
| `FERMENTABLE.TYPE` | `Grain`, `Adjunct` | `grain` |
| | `Sugar` | `sugar` |
| | `Extract`, `Dry Extract` | `extract`, `dry extract` |
| `FERMENTABLE.COLOR` | Lovibond ; SRM pour un `Extract` (extrait liquide) | `EBC` par `brewing/` |
| `FERMENTABLE.YIELD` | % ; absent avec `POTENTIAL` (densité, annexe de la norme) | `yield.fine_grind` ; `potentialToYieldPercent` de `brewing/` |
| `HOP.USE` | `Boil` | `add_to_boil`, `time` = `TIME` |
| | `Aroma` avec `TIME` positif | `add_to_boil`, `time` = `TIME` ; listé (« Si c'est un whirlpool, choisissez Whirlpool dans la recette. ») |
| | `Aroma` à 0 minute | `add_to_boil` à 0, sans `duration` (arrêt du feu), sans perte |
| | `Aroma` sans `TIME` | `add_to_boil` à 0, sans `duration` ; listé |
| | `Dry Hop` | `add_to_fermentation`, `duration` = `TIME` |
| | `Mash` | `add_to_mash`, `duration` = `TIME` |
| | `First Wort` | `add_to_boil` à la durée de `BOIL_TIME` (sans `BOIL_TIME`, durée absente) ; listé |
| | `Whirlpool` (hors norme, vu dans `diydog-beerxml`) | avec `TIME` : `add_to_boil` à 0, `duration` = `TIME` ; sans `TIME` ou à 0 : `add_to_boil` à 0 sans `duration` (arrêt du feu), listé (ADR-005, amendements de L2 ; `source_hop_timing` en L3) |
| | `Secondary` (hors norme) | `add_to_fermentation`, `duration` = `TIME` ; listé (moment simplifié) |
| `HOP.FORM` absent | — | recette refusée : la forme est obligatoire dans l'application |
| `HOP.FORM` | `Pellet`, `Plug`, `Leaf` | `pellet`, `plug`, `leaf` ; pour le calcul, `plug` se lit comme `leaf` (`HopForm.ofBeerJson`) |
| Forme BeerJSON | `powder`, `extract`, `leaf (wet)` | conservée ; sans facteur d'utilisation de Tinseth, l'IBU affiche « Forme non prise en charge par le calcul » pour un houblon d'ébullition. Un extrait mesuré en volume ne compte pas dans l'IBU |
| Moment BeerJSON | `add_to_mash`, `add_to_package` | conservé (`HopUse.mash`, `HopUse.package`) ; l'IBU affiche « Moment non pris en charge par le calcul » |
| `YEAST.TYPE` | `Ale`, `Lager`, `Wine`, `Champagne` | `ale`, `lager`, `wine`, `champagne` |
| | `Wheat` | `wheat`, sans perte (décision du 2026-11-10 : la valeur existe dans `culture.json`) |
| `YEAST.FORM` | `Liquid`, `Dry`, `Slant`, `Culture` | valeur de même nom en minuscules |
| `YEAST.AMOUNT`, `MISC.AMOUNT` | litres ; kilogrammes si `AMOUNT_IS_WEIGHT` vaut `TRUE` | `l` (décision 6) ; `g` ; autre valeur que `TRUE` ou `FALSE` : recette refusée |
| `MISC.TYPE` | `Spice`, `Herb`, `Flavor`, `Fining`, `Water Agent`, `Other` | valeur de même nom en minuscules |
| `MISC.USE` | `Boil` ; `Mash` ; `Primary` ; `Secondary` ; `Bottling` | `add_to_boil` (`time`) ; `add_to_mash` ; `add_to_fermentation` ; `add_to_fermentation`, listé ; `add_to_package` (`duration` hors ébullition) |
| `MASH_STEP.TYPE` | `Infusion`, `Temperature`, `Decoction` | valeur de même nom en minuscules |
| `MASH.NAME` | autre que « Empâtage » | remplacé par « Empâtage » ; listé (nom de l'empâtage) |
| `INFUSE_AMOUNT`, rampes, `DECOCTION_AMT`, `TUN_*`, `PH`… | toute valeur | non importés ; listés (détails des paliers) |
| `RECIPE.TYPE` | `All Grain`, `Partial Mash`, `Extract` | `all grain`, `partial mash`, `extract` |
| `STYLE` | élément complet | nom seul ; listé |
| `EQUIPMENT`, `WATERS`, `EFFICIENCY`, `BOIL_SIZE`, `OG`, `FG`, `EST_*`, `IBU`, `ABV`, fermentation, carbonatation, dégustation, `ASST_BREWER`, `DATE` | élément renseigné | non importés ; listés (un élément vide ne l'est pas) |
| `VERSION`, `DISPLAY_*`, `DISP_*`, `INVENTORY` | toute valeur | jamais lus, non comptés |
| Prix, champs inconnus | toute valeur | ignorés, comptés (P5) |

Export BeerXML (`exchange/`, v0.1.21 ; bloqué dans l'application jusqu'au référentiel des
styles, L3) :

| Valeur Kass'Beer | BeerXML écrit |
|---|---|
| `add_to_boil`, `time` | `Boil`, `TIME` = `time` |
| `add_to_boil` à 0 avec `duration` (whirlpool) | `Aroma`, `TIME` = `duration` ; perte listée |
| `add_to_fermentation` ; `add_to_mash` ; `add_to_package` (houblon) | `Dry Hop` ; `Mash` ; `Dry Hop` (perte listée), `TIME` = `duration` ; jour d'ajout à cru perdu, listé |
| Ajout `add_to_fermentation` ; `add_to_package` | `Primary` ; `Bottling` |
| Malt `honey`, `fruit`, `juice` ; `other` | `Sugar` ; `Adjunct` ; perte listée |
| Forme `leaf (wet)` ; `powder`, `extract` | `Leaf` ; `Pellet` ; perte listée |
| Levure hors `ale`, `lager`, `wheat`, `wine`, `champagne` ; forme `dregs` | `Ale` ; `Culture` ; perte listée |
| Palier hors `infusion`, `temperature`, `decoction` | `Temperature` ; perte listée |
| Couleur EBC | Lovibond (SRM pour `extract`) par `brewing/` |
| Masse en grammes ; volume en litres | kilogrammes, `AMOUNT_IS_WEIGHT` `TRUE` ; litres, `FALSE` |
| Palier d'infusion | sans `INFUSE_AMOUNT`, que Kass'Beer ne stocke pas ; perte listée |
| — | `BOIL_SIZE` : `preBoilVolumeLitres` de `brewing/` ; `EFFICIENCY` : rendement d'empâtage de l'équipement |

Une recette sans moment ou sans durée d'ajout, avec un houblon en volume ou d'un type hors
`All Grain`, `Partial Mash`, `Extract` ne s'exporte pas en BeerXML : l'export liste ce qui
manque. Aucune étape de fermentation n'est écrite : Kass'Beer n'en stocke pas.

## Correspondance DotBeer (fichier 005) → référentiels

| Champ DotBeer | Champ retenu |
|---|---|
| `fermentable_type` (`grain` 180, `fruit` 48, `sugar` 17, `other` 4, `extract` 1, `honey` 1) | `type` |
| `yield_fine_grind`, `color` | `yield.fine_grind`, `color` |
| `hop_type`, `form`, `alpha_acid`, `beta_acid` | `type`, `form`, `alpha_acid`, `beta_acid` |
| `culture_type`, `form`, `producer`, `product_id`, `temperature_range`, `flocculation` | mêmes champs, `type` pour `culture_type` |
| `misc_type`, `water_agent_type` | `type` ; `water_agent_type` ignoré en v1 |
| `folder_path` | sert à fixer la licence de `provenance[]` |

## Correspondance DIY Dog (`alxiw/punkapi`) → `public_recipes/`

Enveloppe : `owner_uid: system`, identifiant `diydog-{id}`.

| Champ source | Présence sur 415 | Résultat |
|---|---|---|
| `name` | 415 | `recipe.name` |
| `volume`, `boil_volume` | 415, litres | `batch_size` ; `boil.pre_boil_size` |
| `target_og`, `target_fg` | 414 | `original_gravity`, `final_gravity`, valeurs annoncées, divisées par 1000 |
| `abv`, `ibu`, `ebc` | 415, 410, 409 | `alcohol_by_volume`, `ibu_estimate`, `color_estimate`, valeurs annoncées ; absentes si nulles |
| `srm`, `ph`, `attenuation_level` | 399, 403, 404 | écartés ; aucune conversion SRM vers EBC |
| `method.mash_temp[]` | 391 à 1 palier, 23 à 4, 1 à 3 | `mash.mash_steps[]`, type `infusion` |
| `method.fermentation.temp` | 415 | `fermentation.fermentation_steps[0]` |
| `method.twist` | 178 | `recipe.notes`, texte d'origine |
| `ingredients.malt[]` | 1 627 lignes | `fermentable_additions[]`, type `grain` |
| `ingredients.yeast` | 414 ; `null` sur `089.json` | `culture_additions[]` ; absent pour `089.json` |
| `ingredients.hops[]` | 2 255 lignes | `hop_additions[]`, ou `miscellaneous_additions[]` pour un ajout qui n'est pas un houblon |

Valeurs annoncées : gardées pour l'affichage d'une recette publique, jamais utilisées comme
résultat d'un calcul.

### Moment d'ajout du houblon (`add`, 44 valeurs distinctes)

| Valeur | Lignes | Résultat |
|---|---|---|
| un nombre (`0`, `10`, `60`, `70`, `90`…) | 477 | `add_to_boil`, `time` = ce nombre de minutes |
| `start`, `Start` | 374 | `add_to_boil`, `time` absent, libellé dans `source_hop_timing` |
| `middle`, `Middle` | 256 | `add_to_boil`, `time` absent, libellé dans `source_hop_timing` |
| `end`, `End` | 488 | `add_to_boil`, `time` = 0 |
| `Flame Out`, `Flame out` | 57 | `add_to_boil`, `time` = 0 |
| `Whirlpool`, `whirlpool`, `WHP` | 19 | `add_to_boil`, `time` = 0, `duration` absente, libellé dans `source_hop_timing` |
| `Dry Hop`, `dry hop`, `Dry hop`, `Dry Hop, at Day N`, `HD1`, `HD2`, `FV`, `fv`, `FV Addition`, `secondary`, `maturation` | 566 | `add_to_fermentation` ; `Dry Hop, at Day N` : `time` = N × 1 440 minutes ; autres libellés sans jour : `time` absent |
| `Wood Ageing` | 5 | `add_to_fermentation` |
| `Mash` | 3 | `add_to_mash` |
| `FWH`, `First Wort Hops` | 4 | `add_to_boil` à la durée complète ; perte listée |
| `Kettle`, `Additions` | 6 | rejetés et listés au rapport |

Unités rares : `kilogram` (2), `grams` sur un malt (4) convertis ; `total` (1) et `ml` (1) rejetés et
listés.

`attribute` (`bitter`, `flavour`, `aroma` et variantes) est écarté, sauf 28 lignes de la forme
`10% Alpha`, où il fournit l'acide alpha de la ligne.

## `diydog-beerxml` : à ne pas utiliser comme donnée

Le fichier d'une recette annonce `BOIL_TIME` 60 sur les 325, `EFFICIENCY` 75 sur les 325 et `YIELD`
0 sur les 1 262 malts. Chaque nom de houblon (166) n'a qu'une seule valeur `ALPHA`, alors que les
fichiers de `alxiw/punkapi` n'ont aucun acide alpha. Ces valeurs semblent ajoutées par l'outil
d'export. Le dépôt sert seulement à tester l'import BeerXML.

## Résolution des noms DIY Dog contre les référentiels

Correspondance exacte après normalisation, sans alias, sur les noms des fichiers 001 à 005.

| Nature | Lignes | Résolues | Taux | Noms distincts non résolus |
|---|---|---|---|---|
| Houblons | 2 255 | 2 025 | 90 % | 110 |
| Malts | 1 627 | 295 | 18 % | 107 |
| Levures | 414 | 6 | 1 % | 27 |

Les houblons n'ont aucun acide alpha dans la source, sauf 28 lignes. Les malts n'ont ni EBC ni
rendement. Le calcul d'une recette DIY Dog dépend donc de la résolution.

Les écarts viennent de la forme des noms : `Extra Pale`, `Pale Ale`, `Caramalt` pour les malts,
`Wyeast 1056 American Ale` pour les levures. La recherche se fera sur le producteur et `product_id`
pour les levures, et sur une table d'alias écrite à la main pour environ 245 noms. Cette table porte
aussi `label_fr`, le libellé français facultatif d'un nom générique ; les noms de variétés restent
tels quels.

Une correspondance floue ne remplace jamais une valeur de la source. Elle est marquée dans le
rapport. Un nom non résolu reste dans la recette, sans valeur technique, et apparaît dans
`import_unresolved/`.

## Correspondance BJCP (fichier 002) → `beer_styles`

| Champ | Résultat |
|---|---|
| `name`, `category`, `category_id`, `style_id`, `type`, `style_guide` | conservés |
| `original_gravity`, `final_gravity`, `international_bitterness_units`, `alcohol_by_volume`, `color` | plages chiffrées, unités canoniques |
| `category_description`, `overall_impression`, `aroma`, `appearance`, `flavor`, `mouthfeel`, `comments`, `history`, `style_comparison`, `tags`, `ingredients`, `examples` | écartés |

## Correspondance Kaggle → `style_stats/`

Colonnes à confirmer sur le fichier, qui n'est pas encore téléchargé : `Style`, `StyleID`, `OG`, `FG`,
`ABV`, `IBU`, `Color`, et l'échelle de densité. Chaque style reçoit un effectif, un minimum, des
quartiles, une médiane et un maximum. Si une colonne est en Plato ou en SRM, la conversion passe par
`brewing/`. Aucune ligne brute n'entre dans Firestore.

## Décisions validées

1. **Durée d'ébullition de DIY Dog.** La source ne la donne pas, et 256 recettes sur 415 n'ont que
   `start`, `middle` et `end`. `boil.boil_time` et `time` restent absents, le calcul de l'IBU affiche
   « à compléter » et la recette montre l'IBU annoncé. Le libellé d'origine reste dans l'enveloppe,
   `source_hop_timing` (ADR-005).
2. **Styles.** `beer_styles` ne prend que les 110 styles BJCP 2021 du fichier 002.
3. **`twist` de DIY Dog** (178 recettes). Le texte d'origine va dans `recipe.notes`. C'est la seule
   exception à l'écart des textes libres de DIY Dog.
4. **Priorité entre sources** pour un même ingrédient : 005, puis 003 et 004, puis 001. Les autres
   fichiers fournissent les alias et une ligne de `provenance[]`.
