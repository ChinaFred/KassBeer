# ADR-014 — Correction du référentiel des houblons : origines et doublons

- **Statut** : accepté (2026-11-15), option B
- **Date** : 2026-11-15
- **Remplace** : — (complète ADR-005, « Exception durable » de l'ingestion, et ADR-013,
  « Idempotence »)

Décisions de l'utilisateur du 2026-11-15 :

1. Option B : liste fermée des pays, table de fusion écrite à la main, suppression contrôlée
   des documents absents de la préparation, régénération des arômes touchés.
2. `Austria/Slovenia` : origine laissée absente et listée au rapport de préparation.
3. Sultana et Denali sont la même variété (Denali est l'ancien nom commercial) : fusion.
4. Traduction des pays en français à l'affichage : lot suivant, hors de cet ADR ; ce lot
   amendera P56 (liste des pays en Dart seulement) ou lira les libellés depuis `exchange/`.
5. Dans ce lot, mesure des origines de `beer_fermentables`, `beer_cultures` et `beer_miscs`, et
   liste des pays appliquée aussi aux malts ; fusions de ces référentiels dans un lot suivant.
6. Contrôles acceptés : fin de P19 (suppression contrôlée) et P56 (table de fusion, liste des
   pays).

## Contexte

L'essai d'ADR-013 a produit pour « Saaz » un texte qui le dit américain. Le document
`hop-saaz` porte `origin: "United States"`. Mesure de la session principale sur
`import/ingest/prepare/beer_hops.json` (466 documents, sortie de
`exchange/bin/preparer_referentiels.dart`) :

- 6 documents Saaz : `hop-saaz` (United States), `hop-saaz-cz`, `hop-saaz-czech-republic`,
  `hop-saaz-late`, `hop-saaz-us`, `hop-saaz-usa` ;
- 10 groupes de même nom une fois la parenthèse retirée, 29 documents (Saaz, Magnum, Northern
  Brewer, Perle, Brewer's Gold, East Kent Goldings, Hallertau, Tettnang, Sultana,
  Columbus/Tomahawk/Zeus) ;
- 35 graphies d'origine pour une vingtaine de pays (`United States` 166, `United States of
  America (USA)` 20, `US` 3 ; `Czech Replublic (CZH)` 2 ; une origine vide).

Cause, lue dans le code. `Referentiel.fusionner`
(`exchange/lib/src/ingestion/referentiel.dart`) fusionne par identifiant
`<nature>-<cleNormalisee(nom)>` (`idDe`). Deux noms différents d'une même variété
(« Saaz (CZ) », « Saaz (Czech Republic) ») donnent deux documents. L'origine est recopiée
telle quelle (`lecture_sources.dart`, lignes 255, 275, 492, 548). La fiche l'affiche telle
quelle (`reference_entry_screen.dart`, lignes 220 et 242 : houblons et malts).

Ce qui lit un identifiant `hop-…`, relevé dans le code :

| Lecteur | Ce qu'il garde | Effet d'un identifiant fusionné ou supprimé |
|---|---|---|
| `recipes/`, `recipe_snapshot` des brassins | le nom seul ; `ingredientKey` dérive la clé du nom (`app/lib/features/recipes/domain/recipe.dart`, ligne 14) | aucun |
| `users/{uid}/prices/` | clé `ingredientKey(nature, nom)` (`price_form.dart`) | aucun |
| `import_unresolved/` | SHA-256 de `nature\|nom` (`cles.dart`, `idNonResolu`) | aucun |
| `beer_index/hops` | identifiant de chaque entrée | réécrit par l'ingestion |
| Bibliothèque, `ChampBibliotheque` | liste lue dans `beer_index/hops`, fiche par `get` (P19, P22) | un document absent de l'index n'est plus listé ; une adresse `/bibliotheque/houblons/hop-saaz-cz` gardée par un navigateur l'ouvre encore tant qu'il existe |
| Recettes › Importer (`IndexBibliotheque`, `exchange/lib/src/resolution_import.dart`) | correspondance du moment ; seules des valeurs sont recopiées dans la recette | aucun sur les recettes déjà importées ; un nom présent dans deux entrées ne se résout plus (`_seule`) |
| `public_recipes/{id}.ingredient_refs` | clé d'ingrédient → identifiant (`diydog.dart`, ligne 424) ; non lu par l'application (`recette_publique.dart`, ligne 14) | réécrit par l'ingestion ; `alpha_acid` recopié d'une entrée résolue peut changer (D4) |
| `beer_hop_aromas/{id}` (ADR-013) | même identifiant que le houblon | document orphelin si l'identifiant disparaît ; `input_sha256` change si l'origine ou les alias changent |
| `import/ingest/aromes/houblons-recettes.json`, `aromes.json` | identifiants | `ecrire.mjs` refuse une entrée d'arômes dont l'identifiant manque à `beer_hops.json` (`ingest/lib/execution.mjs`, ligne 148) |

Aucune donnée d'un membre ne référence un identifiant de référentiel. Les données touchées
sont les collections publiques de l'ingestion.

`ingest/ecrire.mjs` écrit les documents changés et ne supprime rien
(`ingest/lib/ecriture.mjs`). Un document fusionné resterait en ligne, absent de l'index.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun travail | textes d'arômes faux (Saaz américain) ; 35 graphies d'origine affichées ; « Saaz » résolu vers la variété américaine à l'import ; doublons dans les suggestions | 0 € |
| A. Origines seules (table des graphies), sans fusion | petit diff, aucune suppression | Saaz garde 6 documents ; « Saaz » reste américain (le document `hop-saaz` vient d'une source qui le dit) | 0 € / ≈ 2 $ d'arômes |
| B. Origines + table de fusion écrite à la main + suppression contrôlée des documents absents | corrige la cause ; identifiants stables pour les noms courts ; collections sans orphelins | une capacité de suppression en production à encadrer ; table à tenir | 0 € / ≈ 3 $ d'arômes, quelques dizaines d'écritures et de suppressions |
| C. B sans suppression : documents fusionnés laissés en ligne | pas de code de suppression | 15 à 20 documents et leurs arômes figés, ouverts par une ancienne adresse avec d'anciennes valeurs ; ils s'accumulent à chaque correction | 0 € |
| D. Documents « tombe » (`merged_into`) lus par l'application | ancienne adresse redirigée | change le modèle des `beer_*`, les règles et le lecteur Dart pour un cas d'adresse gardée | travail supérieur à B |

## Décision

Option B. Elle corrige la cause (fusion par nom, origine recopiée), ne touche aucune donnée de
membre, et la suppression reste un pas de l'ingestion locale déjà encadrée par ADR-005.

### 1. Origines

- Liste fermée des pays dans `exchange/lib/src/ingestion/origines.dart` : graphie canonique
  et graphies reçues (`US`, `United States of America (USA)`, `Czech Replublic (CZH)`,
  `Germany (GER)`…). La graphie canonique est la graphie anglaise la plus fréquente dans la
  mesure (`United States`, `Germany`, `Czech Republic`, `New Zealand`…), pour changer le
  moins de documents et donc le moins d'empreintes d'arômes.
- `origin` reste un texte (BeerJSON `HopVarietyType.origin`, `FermentableType.origin`) :
  aucun changement de modèle ni de règle.
- Graphie inconnue : `origin` absent, entrée listée dans `rapport.json` (identifiant, graphie
  lue). Aucune valeur inventée (« Pas de valeur de repli figée »). Origine vide : absente.
- Origine double (`Austria/Slovenia`) : absente et listée au rapport (décision 2).
- La table s'applique aux houblons et aux malts dans le même lot : la fiche affiche les deux.
- Traduction en français à l'affichage : lot suivant (décision 4).
- Mesure du 2026-11-15 (décision 5) : `beer_cultures` (845) et `beer_miscs` (122) n'ont aucune
  origine, rien à normaliser ; `beer_fermentables` (462) : 11 graphies (`US`, `United States`,
  `UK`, `United Kingdom`, `New Zealand, Canterbury`…, `Netherlands` en plus), 161 sans origine.

### 2. Table de fusion

- `exchange/lib/src/ingestion/fusions.dart`, écrite à la main, distincte de `kAlias` (qui ne
  sert qu'aux noms de DIY Dog). Une ligne : identifiant cible, nom du document, entrée qui
  donne les valeurs (`source` et `source_id`), entrées fusionnées, noms écartés des alias.
- Règle : une variété et un pays de culture font un document. Le nom court désigne la
  variété dans son pays d'origine (`Saaz` tchèque, `Hallertau` allemand). Une culture
  ailleurs garde son document, nommé avec le pays (`Saaz (US)`), car ses acides diffèrent.
  Deux noms d'une même variété (« Denali » et « Sultana », décision 3) fusionnent.
- L'identifiant d'un document reste `<nature>-<cleNormalisee(nom du document)>`.
  `Referentiel.parNomExact` cherche d'abord cet identifiant direct : un autre schéma le
  casserait. `hop-saaz` désigne donc le Saaz tchèque. Aucune recette ne garde cet
  identifiant (tableau du contexte) : le changement de sens ne touche que les arômes, qui
  sont régénérés.
- Un nom faux d'une source (« Saaz » pour une culture américaine) n'entre pas dans les
  alias de `hop-saaz-us`. Sinon le nom `saaz` désignerait deux documents, et
  `IndexBibliotheque` ne résoudrait plus « Saaz » à l'import.
- Une ligne de la table qui désigne une entrée absente des sources fait échouer la
  préparation (`StateError`, comme `Resolveur`). Chaque ligne a son cas de test dans
  `exchange/test/` (fixtures inventées, P20).
- `rapport.json` liste les groupes de noms qui restent identiques une fois la parenthèse
  retirée, pour la revue suivante.

Note du 2026-11-15 (livraison, v0.1.61) : une ligne de `fusions.dart` ne nomme pas l'entrée
qui donne les valeurs. Les valeurs viennent de l'entrée la plus prioritaire du groupe (005, puis
003 et 004, puis 001), comme pour toute fusion ; la ligne impose au besoin l'origine et ajoute ou
écarte des alias. Une entrée absorbée est désignée par source, nom et, si besoin, origine après
la table des graphies.

### 3. Suppression contrôlée

- `ecrire.mjs --supprimer-absents` : supprime les documents présents dans Firestore et
  absents de la préparation, dans `beer_hops` et `beer_hop_aromas` seulement pour ce lot.
- Garde-fous : simulation d'abord (liste des identifiants), plafond de 30 suppressions par
  lancement, refus si la préparation compte moins de 90 % des documents en ligne de la
  collection, confirmation par la saisie du nombre de suppressions, identifiant conforme au
  motif de la collection (`ingest/lib/validation.mjs`, ligne 114), rapport chiffré
  (supprimés, ignorés, en erreur) avec les identifiants. Émulateur par défaut, production
  sur `--production --projet kassbeer`, comme l'écriture.
- Sans l'option, `ecrire.mjs` ne supprime rien, comme aujourd'hui.
- Cette option amende l'exception durable d'ADR-005 : « un document inchangé n'est pas
  réécrit ; un document absent de la préparation n'est supprimé que sur option, dans les
  bornes d'ADR-014 ».

### 4. Arômes (ADR-013)

- L'empreinte `input_sha256` change pour un houblon dont l'origine ou les alias changent :
  `generer-aromes.mjs` le compte « changé ».
- Une entrée `reviewed: true` n'est jamais écrasée. Une entrée relue dont l'origine a changé
  passe par `--regenerer <id>` et une nouvelle relecture.
- Les entrées de `aromes.json` dont l'identifiant a disparu sortent du fichier avant
  `ecrire.mjs`, qui les refuse sinon.
- `houblons-recettes.json` se relance après la nouvelle préparation (7 jours au plus).

### 5. Ordre de mise en œuvre

1. Code et tests dans `exchange/` et `ingest/` ; liste des pays appliquée aux houblons et aux
   malts (décision 5) ; CI verte.
2. Préparation ; relire `rapport.json` (graphies inconnues, groupes restants, fusions).
3. `ecrire.mjs` sur l'émulateur, avec et sans `--supprimer-absents`.
4. Production : `--simulation`, puis écriture, puis `--supprimer-absents`.
5. `lister-houblons-recettes.mjs`, génération des arômes changés (`--nouveaux` ou empreintes),
   relecture des houblons du groupe, `ecrire.mjs`.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : poste de l'admin (`exchange/` en Dart, `ingest/` en
   Node). Rien dans l'application ni dans `functions/`.
2. Ce qui existera en double : rien. La table des origines et la table de fusion vivent en
   Dart dans `exchange/` seul. `ingest/lib/validation.mjs` garde un contrôle de forme sur
   `origin` (texte), sans copie de la liste.
3. Ce qui pèse au démarrage : rien ; l'application ne change pas.
4. Compilation de chaque cible : aucune dépendance ajoutée.
5. Qui voit quoi : collections publiques au groupe (P19). Aucun prix, aucun nom de membre.
   `rapport.json` reste dans `import/` (non versionné).
6. Ce qui coûte à l'usage, plafond : arômes régénérés sous le poste `hop_aroma_generation`.
   Environ 70 houblons (≈ 55 origines normalisées, ≈ 15 cibles de fusion) à ≈ 0,04 $ pièce
   (17 $ pour 466 houblons à l'effort `medium`, ADR-013, section 5) : ≈ 3 $, sous
   `--budget-usd`. Firestore : quelques centaines d'écritures et 30 suppressions au plus,
   dans le niveau gratuit.
7. Exposition : inchangée.
8. Exploitation : la table de fusion se tient à la main à chaque nouvelle source. La copie
   de sauvegarde est la préparation précédente, à garder dans `import/ingest/` avant la
   nouvelle.
9. Coût de sortie : nul ; les tables sont du code du dépôt.

## Conséquences

- Les origines affichées sont lisibles et comparables. « Saaz » se résout vers le Saaz
  tchèque à l'import.
- `public_recipes/` est réécrit en partie : `alpha_acid` recopié d'un houblon fusionné peut
  changer (DIY Dog sans attribut d'acide alpha).
- Un nouveau type d'opération en production (suppression) existe, borné par la section 3.
- Contrôles de `CLAUDE.md` (décision 6) : P19 complété (suppression contrôlée), P56 ajouté
  (table de fusion et liste des pays), P55 borné à cet ADR pour la préparation de `beer_hops`.
- `DATA_SOURCES.md` : section « Origines » et table de fusion décrites ; volumes « Après
  fusion » mis à jour.

## Note du 2026-11-15 : seuil de la suppression à 90 %

Le premier lancement en production de `--supprimer-absents beer_hops` a été refusé : la
préparation compte 442 documents pour 466 en ligne, soit 94,85 %, sous le seuil de 95 %
fixé à la section 3. Les 24 absents sont les doublons retirés par la table de fusion.
Décision de l'utilisateur : le seuil passe à 90 % (`PART_MIN_PREPAREE`,
`ingest/lib/ecriture.mjs`). Les autres garde-fous ne changent pas (30 suppressions au plus,
simulation, saisie du nombre).

## Amendement du 2026-11-15 : `beer_cultures`

Décision de l'utilisateur : `ecrire.mjs --supprimer-absents` accepte aussi `beer_cultures`.
Des fiches de fabricants renommées laissent d'anciens documents `culture-…` en ligne, car
`ecrire.mjs` n'efface rien sans cette option. Les douze variantes Omega en « + »
s'écrivent « Plus » (« Kolsch II+ » devient « Kolsch II Plus »), et des entrées Wyeast
changent aussi.

Les garde-fous de la section 3 et de la note précédente s'appliquent tels quels : simulation
d'abord, liste des identifiants avant la confirmation, 30 suppressions au plus par lancement,
refus sous 90 % des documents en ligne, saisie du nombre, identifiant conforme au motif de
`beer_cultures` (`^culture-[a-z0-9]+(-[a-z0-9]+)*$`, `ingest/lib/validation.mjs`), rapport
chiffré avec les identifiants, émulateur par défaut, production sur `--production --projet
kassbeer`, une collection par lancement. Sans l'option, rien n'est supprimé. Les identifiants
préparés sont ceux de `beer_cultures.json`, refusés compris. Les autres collections restent
refusées.

## Sources

- Code lu le 2026-11-15 sur la branche à jour de `main` (v0.1.57) : fichiers cités dans le
  texte.
- Mesure de `beer_hops.json` : relevé de la session principale du 2026-11-15, non rejoué
  par l'architecte (`import/` absent de cette copie du dépôt).
- Coût par houblon : ADR-013, section 5 (estimation, tarif à vérifier dans
  `import/ingest/aromes/tarif.json`).
- Sultana, ancien nom Denali : fusion décidée par l'utilisateur (décision 3).
