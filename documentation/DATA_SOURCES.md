# Sources de données

Sources externes du socle données (ADR-005) : version figée, licence, ce qui est retenu, et
correspondance de chaque source vers le modèle de Kass'Beer.

Relevé du 2026-11-08, sur les fichiers eux-mêmes. Les licences sont des constats, pas un avis
juridique. **Statut : validé par l'utilisateur le 2026-11-08.** Kaggle : la page déclare « CC0:
Public Domain » (relevé du 2026-11-11), mais le téléchargement demande un compte absent du
poste ; l'ingestion de `style_stats` est reportée (ADR-005, amendements de L3, D1).

Aucun fichier de ces sources n'entre dans le dépôt public, un asset ou l'APK, sauf la table des
teintes de `srm2hex` (MIT), reprise dans `brewing/` avec sa licence, et le fichier des fiches
des fabricants, écrit à la main dans `exchange/donnees/fabricants/cultures.json` (décision de
l'utilisateur du 2026-11-15, ADR-005). Les autres données vivent dans `import/`, ignoré par Git. Les fixtures de test sont écrites à la main.

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
| Kaggle « Brewer's Friend Beer Recipes » | non téléchargé | « CC0: Public Domain » déclarée sur la page (relevé du 2026-11-11) ; ingestion reportée (ADR-005, D1) | statistiques par style | lignes brutes, CSV |
| BeerJSON | `4370892d44` | MIT | schémas pour ajv en CI et à l'ingestion | — |
| Fiches techniques Fermentis (`fermentis.com/en/product/…`), recopiées à la main dans `exchange/donnees/fabricants/cultures.json` (BeerJSON 2.01, versionné) | relevé du 2026-11-14 ; fichier écrit à la main, SHA-256 `1eb1f9ae2e05e36fc4bd2bd9b279582cde3f8907912d897ca436615fcff4dbdf` au versement | données publiées en accès libre par le fabricant ; reprise décidée par l'utilisateur le 2026-11-14 | 25 cultures (23 levures, 2 bactéries) : nom, type, forme, producteur, référence, atténuation apparente, plage de température | floculation (la fiche donne un temps de sédimentation), tolérance à l'alcool, dosage, descriptions |
| Fiches techniques Mangrove Jack's (`mangrovejacks.com/products/…`, collection « Beer Yeasts »), recopiées à la main dans le même fichier | relevé du 2026-11-15 ; SHA-256 du fichier `695254c9d80eabf56d450ed7f7904dafbf730226a80daa839b403ef0af3098f2` après l'ajout | données publiées en accès libre par le fabricant ; reprise décidée par l'utilisateur le 2026-11-15 | 16 levures de bière : nom, type, forme, producteur, référence, atténuation, plage de température, floculation | levures de vin, de cidre, d'hydromel et de hard seltzer, tolérance à l'alcool, dosage, descriptions |
| Fiches techniques Imperial Yeast (`imperialyeast.com/yeast-strains/…`), recopiées à la main dans le même fichier | relevé du 2026-11-15 ; SHA-256 du fichier `149051162efdff5de2c91b6709092eaf85c23fea778551ac51a9ed3936e50f23` après l'ajout | données publiées en accès libre par le fabricant ; reprise décidée par l'utilisateur le 2026-11-15 | 55 levures de bière : nom, type, forme, producteur, référence, atténuation, plage de température, floculation | A40 Bubbles (cidre), W01 Champion et W04 Paramount (levures de vin), tolérance à l'alcool, descripteurs, descriptions |
| Fiches techniques Omega Yeast (`omegayeast.com/products/…`), recopiées à la main dans le même fichier | relevé du 2026-11-15 ; SHA-256 du fichier `bb486777fbacd5fc0b64a17ed36e65bc7c7d7f090308e07aa8e0ba0cf1b784bd` après l'ajout et le renommage « Plus » | données publiées en accès libre par le fabricant ; reprise décidée par l'utilisateur le 2026-11-15 | 104 cultures (102 levures liquides ou sèches, 2 bactéries) : nom, type, forme, producteur, référence, atténuation, plage de température, floculation | tolérance à l'alcool, notes de dégustation, descriptions |
| Fiches techniques White Labs et The Yeast Bay (`whitelabs.com/yeast-single?id=…`), recopiées à la main dans le même fichier | relevé du 2026-11-15 ; SHA-256 du fichier `2709a66bca326bea6e8a4f13698c89e160353156ac99501dbe32c66974fdf601` après l'ajout | données publiées en accès libre par le fabricant ; reprise décidée par l'utilisateur le 2026-11-15 | 162 cultures WLP (115 White Labs, 47 The Yeast Bay) : nom, type, forme, producteur, référence, atténuation, plage de température, floculation | levures de vin, saké, hydromel, cidre et distillerie, kombucha, bactéries acétiques et malolactiques, produits d'autres marques revendus, tolérance à l'alcool, styles conseillés, descriptions |
| Fiches techniques Wyeast (`wyeastlab.com/product/…`), recopiées à la main dans le même fichier | relevé du 2026-11-15 (Crawl-delay de 10 s respecté) ; SHA-256 du fichier `4d0206ca6143b07a3e4824274b496b9f9f07843b61f5ec0c48d1ca8575826b10` après l'ajout | données publiées en accès libre par le fabricant ; reprise décidée par l'utilisateur le 2026-11-15 | 77 cultures (bière, « Wild & Sour ») : nom, type, forme, producteur, référence, atténuation, plage de température, floculation | cultures de vin, cidre, hydromel, saké et distillerie (série 4000), produits d'appoint, tolérance à l'alcool, profil, styles conseillés |
| paquet npm `srm2hex` (ticket #48) | 1.0.2, archive `https://registry.npmjs.org/srm2hex/-/srm2hex-1.0.2.tgz`, SHA-1 `d84847e600a65eaee38247e2bce6e6d33c214d14` | MIT, déclarée dans `package.json` et le README ; ni fichier LICENSE ni ligne de copyright | les 400 triplets RGB de `lookup.js` (un par dixième de SRM, de 0 à 39,9 SRM), repris à l'identique par script dans `brewing/lib/src/teintes_srm.dart`, avec le texte de la licence MIT | le code de conversion en hexadécimal (`index.js`), qui omet le zéro de tête d'une composante sous 16, et sa règle « 40 SRM et plus = noir » (Kass'Beer garde la dernière teinte de la table) |
| Descriptions aromatiques des houblons (ADR-013) | modèle `claude-fable-5-2`, prompt versionné (`prompt_version`, `ingest/lib/aromes/prompt.mjs`), effort noté dans `provenance[].version` | texte généré pour Kass'Beer par l'API Claude (Anthropic), copié d'aucune source ; données envoyées : nom, alias, origine, acides, usage de `beer_hops/` (publiques) | `beer_hop_aromas/` : descripteurs de la liste fermée, un texte par usage ; houblons des recettes du groupe relus par l'admin, les autres « non relu » ; un texte peut contenir des erreurs | `notes` des sources (jamais envoyés), recherche web, citation d'un fournisseur ou d'un catalogue |

Attribution : l'écran « Sources des données », ouvert à tout membre, nomme Brewtarget (GPL-3),
beer-analytics.com (CC BY-SA 4.0, lien vers la licence, modifications : unités normalisées, origines
ramenées à une liste de pays, doublons fusionnés et renommés), les fiches des fabricants (données
publiées en accès libre par le fabricant), DIY Dog et srm2hex (MIT, avec le texte de la licence),
et dit que les descriptions
aromatiques des houblons sont rédigées par une IA (Claude, d'Anthropic) pour Kass'Beer. Chaque
entrée de Firestore
porte sa licence dans `provenance[]` ; la licence de srm2hex est en tête de `teintes_srm.dart`
et dans l'écran.

Génération de `teintes_srm.dart` : le script, à usage unique, est resté hors du dépôt. Il lit
`package/lookup.js` de l'archive (SHA-256
`d3ed62b9bd34b3e461c0d0c6d80cfc9a4a198a9036c67c80c7b929fe2b094381`), en extrait le tableau
JSON de 400 triplets et les écrit dans le même ordre, un par dixième de SRM, sans autre
changement. `brewing/test/teinte_test.dart` vérifie la table contre une empreinte de
`lookup.js` (texte « [[r,g,b],…] » de 4 497 caractères, FNV-1a 32 bits `427e5b13`, notée dans
`brewing/test/fixtures/teinte.json`), calculée depuis l'archive et non depuis la table.

## Volumes

Entrées brutes avant dédoublonnage. Noms uniques après normalisation (casse, accents, ponctuation).

| Nature | 001 | 003 | 004 | 005 | Total brut | Noms uniques |
|---|---|---|---|---|---|---|
| Malts et sucres | 369 | — | — | 251 | 620 | 462 |
| Houblons | 126 | 282 | — | 418 | 826 | 466 |
| Levures | 37 | 296 | 275 | 703 | 1 311 | 791 |
| Divers | 84 | — | — | 43 | 127 | 122 |
| Styles | 127 | — | — | 9 | 136, plus 110 dans 002 | non mesuré |

Ces volumes du fichier 001 comptent aussi les ingrédients de ses 29 recettes. L'ingestion (L3)
ne lit que les listes du premier niveau du 001 : 248 malts et sucres, 62 houblons, 84 ajouts,
8 levures. Après fusion (relevé du 2026-11-11) : 462 malts et sucres, 466 houblons, 845
levures (une même souche chez un même producteur ne fait qu'un document, voir
`exigences-techniques.md`, « Référentiels et recettes publiques »), 122 ajouts, 110 styles.

Après la table de fusion des houblons (ADR-014, estimation sur le relevé du 2026-11-15, à
confirmer par la préparation) : 442 houblons au lieu de 466. Les 24 documents qui
disparaissent sont rattachés à un autre (table ci-dessous). Les autres référentiels ne
changent pas de nombre : seules leurs origines changent.

## Origines

`origin` d'un malt ou d'un houblon est ramené à une liste fermée de pays, en graphie anglaise,
la plus fréquente dans les sources (`exchange/lib/src/ingestion/origines.dart`, ADR-014). Mesure
du 2026-11-15 : 35 graphies d'origine pour une vingtaine de pays dans `beer_hops`
(`United States` 166, `United States of America (USA)` 20, `US` 3…), 11 graphies et 161
malts sans origine dans `beer_fermentables` ; aucune origine dans `beer_cultures` ni
`beer_miscs`.

| Graphie lue | Pays |
|---|---|
| `US`, `USA`, `United States of America (USA)` | `United States` |
| `Germany (GER)` | `Germany` |
| `United Kingdom`, `United Kingdom (UK)`, `UK`, `England` | `Great Britain` |
| `Czech Replublic (CZH)` | `Czech Republic` |
| `New Zealand (NZ)`, `New Zealand, Canterbury` | `New Zealand` |
| `Australia (AUS)`, `Poland (POL)`, `Slovenia (SLO)`, `France (FR)`, `Canada (CAN)`, `China (CN)` | le pays sans le code |

Liste des pays : Argentina, Australia, Austria, Belgium, Canada, China, Czech Republic,
France, Germany, Great Britain, Japan, Netherlands, New Zealand, Poland, Russia, Serbia,
Slovenia, South Africa, Sweden, Ukraine, United States. Le nom d'un pays de la liste est
accepté tel quel, sans casse. Une graphie absente de la table, ou qui nomme deux pays
(`Austria/Slovenia`, décision de l'utilisateur du 2026-11-15), laisse `origin` absent et part
dans `rapport.json` (`origines_inconnues`). Une origine vide reste absente. La traduction en
français à l'affichage viendra avec un lot suivant.

## Table de fusion des houblons

Écrite à la main (`exchange/lib/src/ingestion/fusions.dart`), validée par l'utilisateur le
2026-11-15 (ADR-014). Règle : une variété et un pays de culture font un document. Le nom court
désigne la variété dans son pays d'origine ; une culture ailleurs garde son document, nommé
avec le pays. Les valeurs viennent de l'entrée la plus prioritaire du groupe (005, puis 003,
puis 001) ; l'origine est imposée quand cette entrée la porte fausse.

| Document | Origine | Entrées rattachées | Alias ajoutés, noms écartés |
|---|---|---|---|
| `hop-saaz` « Saaz » | `Czech Republic` (imposée) | `Saaz (CZ)` (003), `Saaz (Czech Republic)` (001), entrées « Saaz » non américaines | — |
| `hop-saaz-us` « Saaz (US) » | `United States` | `Saaz (US)` (003), `Saaz (USA)` (001), entrées « Saaz » américaines du 005 | « Saaz » écarté |
| `hop-magnum` « Magnum » | `Germany` (imposée) | `Magnum (GR)` (003), entrées « Magnum » non américaines | — |
| `hop-magnum-us` « Magnum (US) » | `United States` | `Magnum (US)` (003), entrées « Magnum » américaines du 005 | « Magnum » écarté |
| `hop-northern-brewer` | `Germany` | `Northern Brewer (GR)` (003) ; `Northern Brewer (US)` reste seul | — |
| `hop-perle` | `Germany` | `Perle (GR)` (003) ; `Perle (US)` reste seul | — |
| `hop-brewer-s-gold` | `Germany` | `Brewer's Gold (GR)` (003) ; `Brewer's Gold (US)` reste seul | — |
| `hop-east-kent-goldings` | `Great Britain` | `East Kent Golding`, `East Kent Goldings (EKG)`, `East Kent Goldings (EKG) (1)` (005) | — |
| `hop-hallertauer-blanc`, `-gold`, `-tradition` | `Germany` | `Hallertau Blanc`, `Hallertau Gold`, `Hallertau Tradition` (003) | — |
| `hop-hallertauer-taurus` | `Germany` (imposée) | `Hallertau Taurus` (003, dit britannique) | — |
| `hop-hallertauer-mittelfruh` « Hallertauer Mittelfrüh » | `Germany` | `Hallertau Mittelfrüh` (003), `Hallertauer Mittelfrueh` (005), `Hallertau` (001) | — |
| `hop-tettnang` | `Germany` | `Tettnanger` (005, 003) ; `Tettnang (US)` reste seul | — |
| `hop-sultana` | `United States` | `Sultana (Denali)` (003) | « Denali » (ancien nom commercial) |
| `hop-columbus` | `United States` | `Columbus/Tomahawk/Zeus` (001), `Columbus/Tomahawk/Zeus (CTZ)` (005), `CTZ`, `Tomahawk`, `Zeus` (003, ajoutés le 2026-11-15 après la première préparation réelle) | « CTZ », « Tomahawk », « Zeus » |

`Hallertau (NZ)`, `Hallertau (US)`, `Saaz Late` et les autres `Hallertauer …` restent seuls.
Les noms rattachés deviennent des alias. Documents qui disparaissent (24) : `hop-saaz-cz`,
`hop-saaz-czech-republic`, `hop-saaz-usa`, `hop-magnum-gr`, `hop-northern-brewer-gr`,
`hop-perle-gr`, `hop-brewer-s-gold-gr`, `hop-east-kent-golding`,
`hop-east-kent-goldings-ekg`, `hop-east-kent-goldings-ekg-1`, `hop-hallertau`,
`hop-hallertau-blanc`, `hop-hallertau-gold`, `hop-hallertau-mittelfruh`,
`hop-hallertau-taurus`, `hop-hallertau-tradition`, `hop-hallertauer-mittelfrueh`,
`hop-tettnanger`, `hop-sultana-denali`, `hop-columbus-tomahawk-zeus`,
`hop-columbus-tomahawk-zeus-ctz`, `hop-ctz`, `hop-tomahawk`, `hop-zeus`. Ils sortent de Firestore par `ecrire.mjs
--supprimer-absents beer_hops`, avec leurs arômes (`beer_hop_aromas`). `hop-saaz` et
`hop-magnum` restent, mais désignent désormais la variété tchèque et allemande. Les
abréviations de DIY Dog `H. Blanc`, `H. Mittelfruh`, `H. Taurus` (`alias.dart`) visent les
documents `hop-hallertauer-…`.

Un nom (nom du document ou alias) porté par deux houblons arrête la préparation : la
résolution par nom d'un import ne saurait lequel choisir. `rapport.json` liste les groupes
de houblons de même nom une fois les parenthèses retirées (`groupes_sans_parenthese`) pour la
revue suivante de la table.

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
| `HopVarietyBase.form` | absente | ligne sans forme (ADR-005, D8), sans perte listée ; l'IBU d'ébullition est « à compléter » et l'export BeerXML est bloqué. Une forme hors du schéma : recette refusée |
| `HopAdditionType.timing`, `use: add_to_boil` | `time` ; sinon `duration` ; `time` 0 avec `duration` | ébullition `time` ; ébullition `duration` (ADR-005) ; après l'arrêt du feu, pour `duration` |
| `timing` d'un ajout à cru, à l'empâtage, au conditionnement | `time` en plus de `duration` | `duration` seule, simplification listée (le jour d'ajout d'un houblon à cru est gardé) |
| Quantité d'une levure | `pkg`, `each`, `unit` | absente, listée ; pour un malt, un houblon ou un ajout, recette refusée |
| `style` | objet complet | nom seul, listé ; l'export BeerXML relit la catégorie et les plages dans `beer_styles` par ce nom exact (ADR-005, E4) |
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
| `HOP.FORM` absent | — | ligne sans forme (ADR-005, D8), sans perte listée ; l'IBU d'ébullition est « à compléter » (« Forme du houblon à compléter ») et l'export BeerXML est bloqué |
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

Export BeerXML (`exchange/`, v0.1.21 ; appelé par la feuille « Exporter » depuis la v0.1.28,
style lu dans la Bibliothèque, ADR-005, E4) :

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

## Fiches des fabricants → `beer_cultures`

Fichier écrit à la main, versionné dans `exchange/donnees/fabricants/cultures.json` depuis le
2026-11-15 (lu par défaut par `bin/preparer_referentiels.dart`, option `--fabricants`), au format
BeerJSON 2.01 (liste `cultures`, mêmes champs que 003 et 004) ; en-tête en `//` avec l'adresse des
fiches. Il ne contient que noms et valeurs techniques, aucun texte des fiches.
`exchange/test/fabricants_donnees_test.dart` le lit : 439 entrées (25 Fermentis, 16 Mangrove
Jack's, 55 Imperial Yeast, 104 Omega Yeast, 115 White Labs, 47 The Yeast Bay, 77 Wyeast), aucun rejet, quatre atténuations écartées (Fermentis).
Lu par `lireFabricants` d'`exchange/` ; toute autre liste est ignorée et comptée.

Chaque fabricant a sa date de relevé, dans `kDatesReleveFabricants` (`exchange/lib/src/ingestion/sources.dart`),
par clé de producteur : Fermentis le 2026-11-14, Mangrove Jack's, Imperial Yeast,
Omega Yeast, White Labs, The Yeast Bay et Wyeast le 2026-11-15. Cette date
devient `version` et `retrieved` dans `provenance[]` de chaque fiche. Une fiche d'un producteur
absent de la table est refusée (« date du relevé inconnue »). Au rapport, la version de la source
`fabricants` est la date du relevé le plus récent.

### Fermentis

| Valeur de la fiche | Champ |
|---|---|
| nom commercial sans ™ (`SafAle US-05`), référence (`US-05`), Fermentis | `name`, `product_id`, `producer` |
| espèce et usage : *S. cerevisiae* → `ale`, et `wheat` pour une levure de bière de blé (WB-06, W-68, BW-20) ; *S. pastorianus* → `lager` ; *Brettanomyces* → `brett` ; *Lactiplantibacillus*, *Levilactobacillus* → `lacto` ; *Torulaspora* → `other` | `type` |
| levure sèche | `form` : `dry` |
| « Apparent attenuation » ; LA-01 : 15 % (valeur unique, plage de 15 à 15) | `attenuation` |
| plage « ideally » de « Dosage / Temperature » ; BR-8 et F-2 : plage optimale ou d'usage ; LP 652 : 37 °C ± 3 ; LB 1 : 32 °C ± 5 | `temperature_range` |

HA-18, DA-16, DW-17 et LD-20 (levure et enzyme) annoncent 98 à 102 % : la borne des pourcentages
(100) écarte la plage, comptée au rapport, et l'atténuation reste absente. F-2, BR-8 et les deux
bactéries n'ont pas d'atténuation sur leur fiche. La fiche, prioritaire, donne toutes les
valeurs : la floculation d'une levure déjà connue de Brewtarget n'est plus reprise.

### Mangrove Jack's

Relevé du 2026-11-15 sur `mangrovejacks.com/products/<fiche>`, collection « Beer Yeasts » :
16 levures de bière sèches. Les levures de vin, de cidre, d'hydromel et de hard seltzer ne sont
pas reprises.

| Valeur de la fiche | Champ |
|---|---|
| nom commercial sans « Yeast » ni le conditionnement (`M44 US West Coast`), référence (`M44`), Mangrove Jack's | `name`, `product_id`, `producer` |
| la fiche ne nomme pas l'espèce. Levure haute ou d'ale → `ale` ; levure basse ou « lager strain » → `lager` ; bière de blé (M20 Hefeweizen, M21 Witbier) → `wheat`, comme BW-20 ; « Kveik » dans le nom (M12) → `kveik` ; mélange levure et enzyme (M66) → `ale`, comme HA-18 | `type` |
| levure sèche | `form` : `dry` |
| « Attenuation » en pourcentage ; M76 : « High » sans chiffre | `attenuation` |
| plage « For best results » ; M12 et M24 : plage « optimal results » | `temperature_range` |
| « Flocculation » : Low, Medium, High, Very High | `flocculation` |

M76 n'a pas d'atténuation. M20 et M44 écrivent des °F qui ne correspondent pas à leurs °C
(59-86 °F pour 18-30 °C, 59-74 °F pour 18-23 °C) : les °C sont repris. Mesure sur les sources
du relevé du 2026-11-08 : 15 fiches rejoignent le document Brewtarget de même référence, M24
crée `culture-mangrove-jack-s-m24-versa-lager` ; 855 documents `beer_cultures` au lieu de 854.

### Imperial Yeast

Relevé du 2026-11-15 sur `www.imperialyeast.com/yeast-strains/<fiche>` : le site n'a pas de
`robots.txt`. 55 levures de bière liquides. A40 Bubbles (cidre), W01 Champion et W04 Paramount
(levures de vin) ne sont pas reprises : leur fiche les déconseille pour un moût.

| Valeur de la fiche | Champ |
|---|---|
| référence et nom (`A01 House`) ; i-05 et i-347 : `Liquid Brick Ale`, `Liquid Brick Lager` ; Imperial Yeast | `name`, `product_id`, `producer` |
| catégorie et usage : Lagers et i-347 → `lager` ; souche ou mélange de kveik (A37, A43, A44, A46) → `kveik` ; hefeweizen (G01) → `wheat` ; les autres (ale, Kölsch, Alt, belge, *S. cerevisiae* var. *diastaticus*, mélange de deux levures d'ale A24) → `ale` | `type` |
| levure liquide | `form` : `liquid` |
| « Attenuation » | `attenuation` |
| « Temperature » en °F, unité de la fiche, convertie en °C par le lecteur (1 décimale) | `temperature_range` |
| « Flocculation » : `low-medium` → `medium low`, `medium-high` → `medium high`, `very-high` → `very high` | `flocculation` |

Mesure sur les sources du relevé du 2026-11-08 : 36 fiches rejoignent le document Brewtarget de
même référence (B53, nommée Fish Finder chez Brewtarget, garde l'identifiant
`culture-imperial-yeast-b53-fish-finder` et prend le nom `B53 Precious`), 19 créent un
document ; 874 documents `beer_cultures` au lieu de 855.

### Omega Yeast

Relevé du 2026-11-15 sur `omegayeast.com/products/<fiche>` : 104 cultures, dont deux bactéries.
La forme est sèche pour les cinq Pinnacle et pour Dried Lutra, liquide pour les autres.

| Valeur de la fiche | Champ |
|---|---|
| nom sans la référence ni « Yeast » (`Voss Kveik`), « + » écrit « Plus » (`Kolsch II Plus`, décision de l'utilisateur du 2026-11-15) ; référence OYL du titre, sinon celle que porte la page (Belgian Ale DK : `OYL-049`) ; Omega Yeast. Les cinq Pinnacle n'ont pas de référence : identifiant tiré du nom | `name`, `product_id`, `producer` |
| « Strain Type » (Ale → `ale`, Lager → `lager`, Brett → `brett`), puis : kveik dans le nom ou la fiche (Vossa Nova) → `kveik` ; bière de blé (Hefeweizen, Bavarian Wheat, American Wheat, Wit, Grand Cru, Belgian Wheat) → `wheat` ; saison et Brettanomyces (C2C) → `mixed-culture` ; *Lactobacillus* → `lacto` ; *Pediococcus* → `pedio` ; *Lachancea* (Pinnacle Crisp Sour) → `other` | `type` |
| levure liquide ou sèche | `form` |
| plage chiffrée de « Attenuation » (`Medium: 76-82%`) | `attenuation` |
| « Temperature Range » en °F | `temperature_range` |
| « Flocculation » : `Low-Medium` → `medium low`, `Medium-High` → `medium high` | `flocculation` |

Champs absents : l'atténuation de Lacto, Pediococcus, Solsta et Pinnacle Low Alcohol ; la plage
de température de Pinnacle Low Alcohol ; la floculation des deux bactéries.

Mesure sur les sources du relevé du 2026-11-08 : 75 fiches rejoignent le document Brewtarget de
même référence, 29 créent un document ; 903 documents `beer_cultures` au lieu de 874. Les douze
variantes « + » s'écrivent « Plus » (`Kolsch II Plus`) : leur nom normalisé n'est plus celui de
la souche d'origine, et aucun nom ne désigne deux documents Omega de même nom de base. Leur
identifiant suit ce nom (`culture-omega-yeast-oyl435-kolsch-ii-plus`).

### White Labs et The Yeast Bay

Relevé du 2026-11-15 sur `www.whitelabs.com/yeast-single?id=<n>`, pages du plan du site :
162 cultures WLP liquides. Non reprises : levures de vin, de saké, d'hydromel et de cidre
(WLP700 à WLP799, WLP616), de distillerie (WLP045, 050, 065, 070, 078), kombucha (WLP600),
bactéries acétiques et malolactiques (WLP675, 685, 690), *Zygosaccharomyces* et *Debaryomyces*
(WLP686, 692), et les produits d'autres marques revendus (Lallemand, Pinnacle).

| Valeur de la fiche | Champ |
|---|---|
| nom sans « Yeast » final, ® ni ™ (`WLP001 California Ale`), référence WLP ; producteur White Labs, ou The Yeast Bay quand le titre de la fiche le nomme (47 fiches WLP4000 à WLP4684) | `name`, `product_id`, `producer` |
| « Kveik » dans le nom → `kveik` ; *Brettanomyces* seule → `brett` ; *Lactobacillus* → `lacto` ; *Pediococcus* → `pedio` ; *Torulaspora*, *Metschnikowia* → `other` ; assemblage dont la description nomme plusieurs genres → `mixed-culture` ; série 800 à 999 et lagers nommées → `lager` ; Hefeweizen, Weizen, Wit, Grodziskie → `wheat` ; les autres → `ale`. WLP631 et WLP6420 : espèce non dite, type absent | `type` |
| levure liquide | `form` : `liquid` |
| « ATTENUATION » ; `N/A` ou plage incomplète : absente (18 fiches) | `attenuation` |
| « FERMENTATION TEMPERATURE » en °F ; plage incomplète : absente (10 fiches) | `temperature_range` |
| « FLOCCULATION » : `Low to Medium` → `medium low`, `Medium to High` → `medium high` ; absente sur 10 fiches | `flocculation` |

Mesure sur les sources du relevé du 2026-11-08 : 123 fiches rejoignent le document Brewtarget de
même producteur et même référence, 39 créent un document ; 942 documents `beer_cultures` au lieu
de 903 ; aucun nom ne devient ambigu. WLP4042 et WLP4044 (Hazy Daze) restent en double : leur
fiche les donne à White Labs, Brewtarget à The Yeast Bay.

### Wyeast

Relevé du 2026-11-15 sur `wyeastlab.com/product/<fiche>`, pages du plan du site, une requête
toutes les 10 s (`Crawl-delay`) : 77 cultures liquides marquées « Beer » ou « Wild & Sour ». Les
16 cultures de vin, cidre, hydromel, saké et distillerie (série 4000, dont *Oenococcus oeni*) et
les produits d'appoint ne sont pas repris.

| Valeur de la fiche | Champ |
|---|---|
| nom sans ® (`American Ale`), numéro de « Strain » sans le suffixe `-PC` (gamme Private Collection) : `2001-PC` → `2001` ; Wyeast | `name`, `product_id`, `producer` |
| « Species » : *S. pastorianus* → `lager` ; *S. cerevisiae* → `ale`, et `wheat` pour une levure de bière de blé (Wheat, Weizen, Witbier dans le nom) ; *Brettanomyces* → `brett` ; *Lactobacillus* → `lacto` ; *Pediococcus* → `pedio` ; plusieurs genres → `mixed-culture` | `type` |
| levure liquide | `form` : `liquid` |
| « Apparent Attenuation » ; valeur unique (1275, 3763, 5151) : plage de la valeur à elle-même | `attenuation` |
| « Temperature Range » en °F | `temperature_range` |
| « Flocculation » : `Low Medium` → `medium low`, `Medium High` → `medium high` ; `Low - High` (assemblages, bactéries) : absente | `flocculation` |

Mesure sur les sources du relevé du 2026-11-08 : 74 fiches rejoignent un document Brewtarget, 3
en créent un ; 945 documents `beer_cultures` au lieu de 942. Brewtarget écrit une souche de la
Private Collection sous deux références (`WY2001-PC` dans 003 et 004, `2001` dans 005), qui
donnent deux documents : la fiche rejoint le second et lui donne son nom, et six noms désignent
désormais deux documents (`belgian-schelde-ale`, `belgian-style-blend`, `bi-re-de-garde`,
`burton-ipa-blend`, `hella-bock-lager`, `west-coast-ipa`). Une clé de référence Wyeast sans `WY`
ni `-PC` (`cleProduit`) fusionnerait ces doublons ; elle change des identifiants de documents.

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
| `volume` | 415, litres | `batch_size` |
| `boil_volume` | 415, litres | écarté : `recipe.boil` n'a pas de clé pour lui (`firestore.rules`) |
| `target_og`, `target_fg` | 414 | `original_gravity`, `final_gravity`, valeurs annoncées, divisées par 1000 |
| `abv`, `ibu`, `ebc` | 415, 410, 409 | `alcohol_by_volume`, `ibu_estimate`, `color_estimate`, valeurs annoncées ; absentes si nulles |
| `srm`, `ph`, `attenuation_level` | 399, 403, 404 | écartés ; aucune conversion SRM vers EBC |
| `method.mash_temp[]` | 391 à 1 palier, 23 à 4, 1 à 3 | `mash.mash_steps[]`, type `infusion`, nommés « Palier 1 », « Palier 2 »… ; un palier sans durée (57) ou sans température (1, `089.json`) est écarté et listé : `step_time` est obligatoire dans le schéma partiel ; 58 recettes restent sans empâtage |
| `method.fermentation.temp` | 403 valeurs | écartée, comptée au rapport : `recipe` n'a pas de clé `fermentation` (`firestore.rules`) |
| `method.twist` | 178 | `recipe.notes`, texte d'origine |
| `ingredients.malt[]` | 1 627 lignes | `fermentable_additions[]` ; `type` de l'entrée résolue (11 lignes de miel, de dextrose, de sucre ou de lactose ne sont pas du grain) ; `grain` pour une ligne non résolue, que la source range dans `malt` sans autre précision |
| `ingredients.yeast` | 414 ; `null` sur `089.json` | `culture_additions[]` ; deux souches jointes par « & » (3 recettes) donnent deux lignes ; absent pour `089.json` |
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
| `Dry Hop`, `dry hop`, `Dry hop`, `Dry Hop, at Day N`, `HD1`, `HD2`, `FV`, `fv`, `FV Addition`, `secondary`, `maturation` | 566 | `add_to_fermentation` ; `Dry Hop, at Day N` : `time` = N × 1 440 minutes ; autres libellés sans jour : `time` absent ; `HD1`, `HD2`, `FV`, `FV Addition`, `secondary`, `maturation` : libellé dans `source_hop_timing` |
| `Wood Ageing` | 5 | `add_to_fermentation`, libellé dans `source_hop_timing` |
| `Mash` | 3 | `add_to_mash` |
| `FWH`, `First Wort Hops` | 4 | `add_to_boil`, `time` absent (la durée d'ébullition manque), libellé dans `source_hop_timing` |
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

Mesure initiale (L0) : correspondance exacte après normalisation, sans alias, sur les noms des
fichiers 001 à 005.

| Nature | Lignes | Résolues | Taux | Noms distincts non résolus |
|---|---|---|---|---|
| Houblons | 2 255 | 2 025 | 90 % | 110 |
| Malts | 1 627 | 295 | 18 % | 107 |
| Levures | 414 | 6 | 1 % | 27 |

Mesure de la préparation (L3, relevé du 2026-11-11, `rapport.json`). Les 2 255 lignes de la liste
`hops` se répartissent en 2 116 houblons, 131 ajouts (épices, fruits, copeaux, sucres : nom
listé dans la table, ou nom qui ne se résout pas en houblon et se résout en ajout) et 8 lignes
rejetées. Les 414 levures donnent 417 lignes. « Avant alias » : correspondance exacte, et pour
une levure le producteur et la référence lus dans le nom (`Wyeast 1056`, `WLP099`), 81 lignes.

| Nature | Lignes | Avant alias | Après alias | Noms distincts non résolus | Lignes non résolues |
|---|---|---|---|---|---|
| Malts | 1 627 | 295 (18,1 %) | 1 391 (85,5 %) | 47 | 236 |
| Houblons | 2 116 | 2 025 (95,7 %) | 2 082 (98,4 %) | 8 | 34 |
| Levures | 417 | 386 (92,6 %) | 400 (95,9 %) | 3 | 17 |
| Ajouts | 131 | 43 (32,8 %) | 80 (61,1 %) | 42 | 51 |

Valeurs recopiées de l'entrée résolue dans les lignes des recettes (ADR-005, D4) : type, rendement et
couleur de 1 391 malts, acide alpha de 2 054 houblons (les 28 lignes `10% Alpha` gardent la
valeur de la source), type et forme de 400 levures, atténuation de 389. Lignes rejetées : 6
moments `Kettle` ou `Additions`, 2 quantités en `total` ou `ml`, 58 paliers. Libellés
d'origine perdus sur un ajout placé hors de `hop_additions` : 20.

**Table d'alias** (`exchange/lib/src/ingestion/alias.dart`, écrite à la main le 2026-11-11) :
102 alias (60 malts et sucres, 14 houblons, 23 ajouts, 5 levures par producteur et référence),
31 `label_fr`, et 65 noms de la liste `hops` qui ne sont pas des houblons. Une entrée n'est
écrite que si la correspondance est sûre :

- nom court d'un malt générique : `Extra Pale` → Extra Pale Ale Malt, `Pale Ale` → Pale Ale
  Malt, `Munich`, `Wheat` (malt de blé pâle), `Chocolate`, `Brown`, `Amber`, `Rye`,
  `Pilsner`, `Vienna`, `Black Malt`, `Dextrose`, `Lactose` ;
- produit nommé autrement : `Caramalt` et ses variantes → Simpsons Caramalt, `Dark Crystal`,
  `Medium Crystal`, `Extra Dark Crystal` → Simpsons, `Carafa Special Malt Type 1/2/3` →
  Carafa Special (Carafa sans enveloppe de Weyermann), `Munich Type 1/2` → Munich I/II ;
- faute de frappe ou abréviation : `Weyernmann Pils`, `H. Mittelfruh`, `Saphire`, `Mt.Hood`,
  `Hercules` ;
- ancien nom ou code : `Pacific Hallertau` → Pacifica, `HBC 366` → Ekuanot, `HBC 369` →
  Mosaic, `HBC 438` → Sabro ;
- levure par sa référence : `W34/70`, `Saflager S189`, `Be-134`, `WB-06` chez Fermentis,
  `WLP4000 - Vermont Ale` chez The Yeast Bay ;
- ajout : copeaux de chêne, café, coriandre, cannelle, gingembre, vanille, poivre, cacao,
  genièvre, anis étoilé, sel, habanero.

`label_fr` est posé sur l'entrée désignée par un nom générique (« Malt de Munich », « Copeaux
de chêne ») ; les noms de variétés restent tels quels. Le nom de DIY Dog s'ajoute aux
`aliases` de l'entrée.

Non écrits, faute de correspondance sûre : niveaux de crystal sans unité (`Crystal 150`,
`Crystal 120`, `Dark Crystal 350`, `Light Crystal`, `Pale Crystal`, `Crystal`), malts absents des
sources (`Simpsons T50`, `Double Roasted Crystal`, `Special W`, `Propino`, `Tipple`,
`Spring Blend`, `Smoked Warminster`), `Maris Otter Extra Pale` (plus clair que Maris Otter),
`Flaked Oat Malt`, `Dry Malt Extract`, `Lager Malt`, `White Wheat`, extraits de houblon,
`Bramling Cross/ First Gold`, `German Comet`, `EXP 366`, `Wyeast 2126` (la souche Bohemian
Lager est la 2124), `Peppercorns` et `Cardamon` (couleur non dite), levures de maison et
ingrédients absents des référentiels (fruits, jus, miels). Ils restent dans la recette, sans
valeur technique, et partent dans `import_unresolved/` (100 noms).

Une correspondance floue ne remplace jamais une valeur de la source. Un nom non résolu reste
dans la recette, sans valeur technique, et apparaît dans `import_unresolved/`.

## Résolution d'un import contre la Bibliothèque

Recettes › Importer (ADR-005, E5, v0.1.28) résout chaque ligne contre `beer_index/`, lu sur
l'appareil, par `completerRecette` d'`exchange/`. Même normalisation que l'ingestion
(`exchange/lib/src/noms.dart`), sans la table d'alias de DIY Dog en dur : ses noms sont déjà
dans les `aliases` de l'index.

| Étape | Correspondance |
|---|---|
| 1 | identifiant `<nature>-<clé du nom>` |
| 2 | seule entrée dont le nom ou un alias a la clé du nom |
| 3 (levure) | seule souche lue dans le nom : `Wyeast 1056`, `WLP001` |
| 4 (levure) | seule entrée de cette référence : `US-05`, `us05` |
| 5 (levure) | seule entrée de ce producteur et de cette référence : `Fermentis US-05` |

Deux entrées pour une même clé ne résolvent rien. Valeurs reprises, seulement si la ligne n'en a
pas : malt `type`, `yield.fine_grind`, `color` ; houblon `alpha_acid`, `form` ; levure `type`,
`form`, `attenuation` (milieu de la plage de la fiche) ; autre ajout `type`. Chaque reprise est
listée au compte rendu. Les étapes 4 et 5 et la reprise de la forme du houblon et du type d'un
ajout vont au-delà de l'ingestion (D4) : ce sont des choix de l'étape 3 (ADR-005, E7). Un nom non
résolu d'un import est signalé dans `import_unresolved/` avec `source: import` et `key` (le nom
normalisé), sous un identifiant propre à l'import (SHA-256 de `import|nature|key`, vérifié par
les règles) : il ne touche jamais un document de l'ingestion, et un même nom a une ligne par
origine. 200 noms au plus par import ; les suivants sont comptés au compte rendu.

## Correspondance `beer_styles` → `STYLE` du BeerXML

Export BeerXML (ADR-005, E4 et E7, v0.1.28). Le type déduit des levures et le blocage d'un
style sans plages sont des choix de l'étape 3 (E7). Le style est cherché par son nom exact dans
`beer_index/styles`, puis lu dans `beer_styles/{id}`.

| `STYLE` | Source |
|---|---|
| `NAME`, `CATEGORY`, `CATEGORY_NUMBER`, `STYLE_GUIDE` | `name`, `category`, `category_id`, `style_guide` (`BJCP2021`) |
| `STYLE_LETTER` | `style_id` sans `category_id` : `21A` → `A`, `X1` → `1` |
| `TYPE` | `mead` → `Mead`, `cider` → `Cider` ; `beer` (les 110 styles) : levures de la recette, `ale` et `kveik` → `Ale`, `lager` → `Lager`, `wheat` → `Wheat`, `brett`, `lacto`, `pedio`, `mixed-culture`, `spontaneous`, `bacteria`, `malolactic` ou deux classes différentes → `Mixed` ; sans levure typée, ou avec une levure `wine`, `champagne` ou `other` : export bloqué |
| `OG_MIN` à `IBU_MAX` | plages en `sg` et en `IBUs` |
| `COLOR_MIN`, `COLOR_MAX` | plage en EBC, écrite en SRM par `brewing/` |
| `ABV_MIN`, `ABV_MAX` | plage en %, facultative |

Un style sans catégorie, code, guide ou une plage de densité, d'amertume ou de couleur bloque
l'export : 17 styles n'ont aucune plage (28A à 34C), IPA Argenta (X2) n'a pas de densités.

## Correspondance BJCP (fichier 002) → `beer_styles`

| Champ | Résultat |
|---|---|
| `name`, `category`, `category_id`, `style_id`, `type`, `style_guide` | conservés |
| `original_gravity`, `final_gravity`, `international_bitterness_units`, `alcohol_by_volume`, `color` | plages chiffrées, unités canoniques |
| `category_description`, `overall_impression`, `aroma`, `appearance`, `flavor`, `mouthfeel`, `comments`, `history`, `style_comparison`, `tags`, `ingredients`, `examples` | écartés |

## Correspondance Kaggle → `style_stats/`

Reportée (ADR-005, amendements de L3, D1) : aucun code ni aucune règle pour `style_stats` tant
que le fichier n'est pas téléchargé. Prévu :

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
4. **Priorité entre sources** pour un même ingrédient : fiches des fabricants (depuis le
   2026-11-14), puis 005, puis 003 et 004, puis 001. Les autres
   fichiers fournissent les alias et une ligne de `provenance[]`.
