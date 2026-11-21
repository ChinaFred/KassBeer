# ADR-019 — Moteur commun des textes rédigés : houblons, levures et divers sur `ingest/lib/redaction/`

- **Statut** : proposé
- **Date** : 2026-11-21
- **Remplace** : — (amende ADR-013, section « Où vit le code » ; amende ADR-017, section 1
  « Où vit le code » et section 6 pour l'emplacement du tarif ; amende ADR-018, section 1, pour
  les listes du groupe ; ADR-018 est l'ADR des divers, numéroté ADR-017 sur la branche
  `claude/focused-brahmagupta-h8gzfh` et renuméroté par ce changement)

## Contexte

Deux branches parties de la v0.1.91 (`5ff7725`) ont chacune pris le numéro ADR-017 et le
contrôle P62, et chacune a refondu le générateur d'ADR-013 pour lui donner une seconde nature.

- `main` (v0.1.93, PR #113) : ADR-017, arômes des levures, collection `beer_culture_aromas`,
  poste `culture_aroma_generation`, P62. Le moteur reste dans `ingest/lib/aromes/generation.mjs`
  (868 lignes) ; les natures vivent dans `ingest/lib/aromes/natures/hop.mjs` (74 lignes) et
  `culture.mjs` (434 lignes : données, prompt, schéma, contrôle). Un seul script,
  `generer-aromes.mjs --nature hop|culture`. Tarif dans `import/ingest/aromes/tarif.json`.
  Listes du groupe : `ingest/lister-ingredients-recettes.mjs --nature` et
  `exchange/bin/lister_ingredients_recettes.dart --nature`. La limite de la Console est relevée à
  70 $ jusqu'à la fin du dernier lot des levures, au plus tard le 30 novembre 2026.
- `claude/focused-brahmagupta-h8gzfh` (lots D1 à D3 livrés sur la branche, D4 en cours) :
  descriptions des divers, collection `beer_misc_descriptions`, poste
  `misc_description_generation`, P62. Le moteur sort dans `ingest/lib/redaction/` :
  `moteur.mjs` (757 lignes, n'importe aucune nature), `client.mjs`, `tarif.mjs`, `texte.mjs`
  (nettoyage NFC, retrait de la catégorie Unicode Cf, contrôle sur la forme NFKC),
  `entree.mjs` (enveloppe commune), `lancer.mjs`. Natures `ingest/lib/aromes/nature.mjs` et
  `ingest/lib/divers/`. Un script par nature (`generer-aromes.mjs`, `generer-divers.mjs`).
  Tarif commun `import/ingest/tarif.json`. Listes du groupe : un script par nature en Node et en
  Dart (`lister-divers-recettes.mjs`, `lister_divers_recettes.dart`, `bin/src/lister_recettes.dart`).

Les deux refontes touchent les mêmes fichiers (`ingest/lib/execution.mjs`, `lister.mjs`,
`options.mjs`, `validation.mjs`, `ecrire.mjs`, `generer-aromes.mjs`,
`exchange/lib/src/ingestion/ingredients_recettes.dart` renommé des deux côtés,
`exchange/test/ingredients_recettes_test.dart` ajouté des deux côtés, `firestore.rules`,
`rules-tests/test/referentiels.test.mjs`, `CLAUDE.md`, `exigences-techniques.md`). Une fusion
directe produit des conflits sur chacun, et deux moteurs ne peuvent pas rester (« Pas de code
mort », ADR-013 et ADR-018 refusent tous deux la copie du moteur).

Contraintes :

- L'empreinte `input_sha256` d'un houblon ne change pas (466 houblons, ≈ 17 $ à renvoyer,
  ADR-013 section 5) ; `ingest/test/aromes.test.mjs` de la branche la fige (`2b7ca0ed…`).
- L'empreinte d'une levure ne change pas non plus : `empreinteEntreeLevure` de `main` couvre
  `{culture, prompt_version, model, effort, styles_sha256}`. Aucun test ne la fige sur `main`.
- La génération des levures doit partir avant le 30 novembre 2026 (crédit, limite de 70 $). Un
  lot de l'API Batches envoyé par le code de `main` se suit par `--suivre`, qui relit
  `import/ingest/aromes/levures/lot-<id>.json`.
- Une décision de l'utilisateur du 2026-11-21, sur la branche `claude/adr-017-fiche-levure`
  (`7f2755f`, non fusionnée), retire « relu le <date> » et « non relu » de la mention IA des
  houblons et des levures. Le lot D3 des divers affiche ces deux formes
  (`app/lib/features/library/presentation/texte_redige.dart`).

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien faire (deux ADR-017, deux P62, deux moteurs) | aucun travail | la branche des divers ne se fusionne pas : conflits sur une vingtaine de fichiers ; deux numéros pour deux décisions | 0 € / 0 € |
| A. Garder le moteur de `main` (`lib/aromes/generation.mjs`, `natures/`) et y porter les divers | moteur en service pour les levures ; un seul script `--nature` | `lib/aromes/` porterait les divers sous un nom faux (option A3 écartée par ADR-018) ; le moteur importe ses natures et `aromes/prompt.mjs`, et `natures/culture.mjs` importe les constantes du prompt des houblons ; à refaire : Cf et NFKC, enveloppe commune, tarif commun, test figé des houblons, soit le travail du lot D1 | 0 € / 0 € ; ≈ 1 lot de travail |
| **B. Garder `ingest/lib/redaction/` de la branche et y porter les levures** (retenue) | moteur qui ne nomme aucune nature ; Cf et NFKC communs aux trois ; test figé des houblons déjà écrit ; une nature par dossier | le moteur reçoit deux crochets que les levures demandent (contexte des styles, périmètre par type) ; le code des levures change pendant sa campagne si ce lot part avant le 30 novembre | 0 € / 0 € ; ≈ 1 lot de travail |
| C. Option moins lourde : renuméroter seulement, deux moteurs côte à côte (`lib/aromes/` pour houblons et levures, `lib/redaction/` pour les divers) | fusion plus courte | deux clients, deux calculs de borne, deux suivis de lot, deux règles de texte (Cf pour les divers seuls) ; P54 décrit deux codes ; contraire à ADR-013 et ADR-018 | 0 € / 0 € ; dette d'un second portage |

## Décision

Option B. Les trois natures (houblons, levures, divers) passent par `ingest/lib/redaction/`,
seul moteur ; chaque nature vit dans son dossier et ne garde que ce qui lui est propre. Le
moteur de la branche est retenu parce qu'il n'importe aucune nature et porte déjà les règles de
texte communes et le test figé des houblons ; ce que `main` a ajouté pour les levures y devient
deux crochets optionnels.

### 1. Numéros

- Divers : ADR-017 de la branche devient **ADR-018** (`git mv` vers
  `ADR-018-descriptions-des-divers.md`). Le contrôle P62 des divers devient **P63**. Les
  levures gardent ADR-017 et P62, déjà sur `main`.
- Relevé du 2026-11-21 : ADR-018, ADR-019, P63 et P64 ne figurent ni sur `origin/main` ni sur
  aucune branche distante (`git ls-tree` de chaque branche de `origin`, et
  `claude/adr-017-fiche-levure`).
- Sur la branche des divers, avant la fusion de `main`, chaque « ADR-017 » et chaque « P62 »
  désigne les divers : aucun fichier de la v0.1.91 ne les cite (`git grep` sur `5ff7725`). Le
  remplacement mécanique est donc sûr avant la fusion, et seulement avant.
- `CHANGELOG.md` : les entrées de la branche, absentes de `main`, reçoivent leur numéro de
  version définitif à la fusion et le renvoi ADR-018 ; les entrées déjà sur `main` ne changent
  pas.

### 2. Où vit le code

- `ingest/lib/redaction/` : `moteur.mjs`, `client.mjs`, `tarif.mjs`, `texte.mjs`,
  `entree.mjs`, `lancer.mjs`, tels qu'en lot D2, plus deux crochets de nature, absents par
  défaut :
  - `contexte(dossierPrepare)` : lu une fois par exécution, passé à `empreinteEntree`,
    `parametresRequete`, `controlerSortieModele`, `controlerEntree`, et à l'écrivain
    (`trierRedigees`) ; les levures y mettent la liste des styles et `stylesSha256` ;
  - `perimetre` : `{typesExclus, dansPerimetre(data)}` ; une entrée du groupe y entre
    toujours ; le rapport porte `types_exclus`.
- Houblons : `ingest/lib/aromes/` (`nature.mjs`, `prompt.mjs`, `validation.mjs`,
  `descripteurs.json`), noms gardés pour P55.
- Levures : `ingest/lib/levures/` (`nature.mjs`, `prompt.mjs`, `validation.mjs`,
  `descripteurs.json`), tirés de `ingest/lib/aromes/natures/culture.mjs` et
  `descripteurs-levures.json` sans changer le texte du prompt, `PROMPT_VERSION_LEVURES`, la
  liste des 32 descripteurs, le schéma ni `empreinteEntreeLevure`. `ingest/lib/aromes/natures/`
  et `ingest/lib/aromes/generation.mjs` sortent.
- Divers : `ingest/lib/divers/`, inchangé.
- Entrées : `ingest/generer-aromes.mjs` garde `--nature hop|culture` (hop par défaut) et ses
  commandes de `main` ; `ingest/generer-divers.mjs` reste. `lancer.mjs` reçoit la nature choisie.
- Fichiers des natures : `import/ingest/aromes/` (houblons), `import/ingest/aromes/levures/`
  (levures, emplacement de `main`, gardé), `import/ingest/divers/` (divers).
- Tarif : un seul fichier, `import/ingest/tarif.json`, pour les trois natures.
  `import/ingest/aromes/tarif.json` n'est plus lu ; s'il est seul, refus « Tarif inconnu » qui
  dit de le déplacer (comportement du lot D1). Le chemin se calcule depuis `import/ingest/`,
  jamais depuis « le dossier parent de la nature » : pour les levures, ce parent est
  `import/ingest/aromes/`, et `cheminsTarif` de la branche y lirait l'ancien fichier.
- Listes du groupe : celles de `main` restent, étendues aux divers :
  `ingest/lister-ingredients-recettes.mjs --nature hop|culture|misc` et
  `exchange/bin/lister_ingredients_recettes.dart --nature hop|culture|misc`. Sortent :
  `ingest/lister-houblons-recettes.mjs`, `ingest/lister-divers-recettes.mjs`,
  `exchange/bin/lister_houblons_recettes.dart`, `exchange/bin/lister_divers_recettes.dart`,
  `exchange/bin/src/lister_recettes.dart`. Un seul `ingredients_recettes.dart`, fixtures sous
  `exchange/test/fixtures/ingredients_recettes/`.
- Écrivain : `ingest/lib/execution.mjs` écrit les trois natures (`NATURES_REDIGEES`),
  `--aromes <dossier>` (houblons, levures dans `levures/`) et `--divers <dossier>` ;
  `relueOrphelines` de `main` vaut pour les trois. `--supprimer-absents` : `beer_hops`,
  `beer_hop_aromas`, `beer_cultures`, `beer_culture_aromas`, comme sur `main` ;
  `beer_misc_descriptions` reste hors de la liste (ADR-018, décision 5).

### 3. Ce qui se garde, ce qui change pour une nature

| Élément | Houblons | Levures | Divers |
|---|---|---|---|
| Empreinte `input_sha256` | inchangée, test figé `2b7ca0ed…` | inchangée ; test figé ajouté, valeur calculée par le code de `main` avant le portage | inchangée (aucune génération en production au 2026-11-21, à confirmer) |
| Nettoyage et règles de texte | NFC, Cf retirée, contrôle NFKC (`texte.mjs`) | passe de « contrôles et bidirectionnels » à Cf et NFKC | déjà Cf et NFKC |
| Refus d'une dose | non | non : le prompt des levures permet les chiffres des données (température, atténuation) | oui, propre aux divers (P63) |
| Tarif | `import/ingest/tarif.json` | passe de `aromes/tarif.json` à `import/ingest/tarif.json` | `import/ingest/tarif.json` |
| Poste de coût | `hop_aroma_generation` | `culture_aroma_generation` | `misc_description_generation` |
| `--supprimer-absents` | `beer_hop_aromas` | `beer_culture_aromas` | non |

Une entrée de levure déjà générée dont un texte porte un caractère de catégorie Cf est refusée
par `ecrire.mjs` (« texte non nettoyé ») et listée au rapport ; l'admin la corrige à la main. Son
empreinte ne change pas : aucun renvoi au modèle.

Un lot de levures envoyé par le code de `main` reste lisible : `--suivre` du moteur commun lit la
table `lot-<id>.json` de `main` (`nature`, `table`, `effort`), avec un test sur une table écrite
au format de `main`.

### 4. Limite de la Console

Une limite commune aux quatre postes facturés à l'appel (`hop_aroma_generation`,
`culture_aroma_generation`, `misc_description_generation`, `recipe_assistant_turn`), sur
l'espace de travail Kass'Beer : 70 $ jusqu'à la fin du dernier lot des levures, au plus tard le
30 novembre 2026, puis 20 $ (ADR-017). Le lot des levures à l'effort `medium` est estimé à
≈ 40 $ et sa marge à 10 $ ; les divers (≈ 6 $ à `medium`, borne haute 10,49 $ en lot, essais
1,80 $ au plus, ADR-018 section 6) prendraient cette marge s'ils partaient en novembre. Ce lot
ne change pas la limite ; le mois du lot des divers revient à l'utilisateur (question ouverte).

### 5. Ordre

1. Aucun préalable pour les levures : leur génération part du code de `main`, sans attendre ce
   lot.
2. Lot R1, sur la branche des divers, avant toute fusion de `main` : renumérotation (section 1).
3. Lot R2, sur une branche tirée de `main` : moteur commun pour les houblons et les levures
   (section 2, sans la nature des divers), tests figés des deux empreintes écrits avant le
   portage, contrôles P54, P55 et P62 mis à jour. Il part après le dernier `--suivre` des
   levures, sauf décision contraire de l'utilisateur.
4. Lot R3, sur la branche des divers : fusion de `main` (avec R2), nature des divers branchée sur
   le moteur déjà en place, listes du groupe ramenées à `--nature misc`, P63.
5. Livraison 2 d'ADR-017 (fiche d'une levure) après R3 : elle reprend `texte_redige.dart` du
   lot D3, sans copie.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : inchangé. Génération, contrôle, listes et écriture sur le
   poste de l'admin (`ingest/`, Node 24 ; résolution des noms en Dart dans `exchange/bin/`) ;
   l'application lit par `get`.
2. Ce qui existera en double : moins qu'avant. Un moteur, un client, un tarif, une règle de
   texte pour trois natures ; la résolution des noms reste en Dart seul ; aucune logique entre
   client et serveur.
3. Ce qui pèse au démarrage : rien côté application ; le SDK se charge au premier appel, dans
   `redaction/client.mjs`.
4. Compilation de chaque cible : aucune dépendance ajoutée ni retirée. R2 ne touche pas `app/` ;
   R3 apporte `app/` des lots D3 et D4. `(cd ingest && npm run format:check && npm test)`,
   `(cd exchange && dart analyze --fatal-infos && dart test)`, `(cd rules-tests && npm test)`,
   `(cd app && flutter analyze && flutter test)`.
5. Qui voit quoi : inchangé. Données envoyées par nature inchangées (ADR-013, ADR-017
   section 2, ADR-018 section 2).
6. Ce qui coûte à l'usage, plafond : aucun appel de plus. Le risque est une empreinte changée
   par erreur : 466 houblons (≈ 17 $) ou 923 levures (≈ 40 $) renvoyés. Les deux tests figés
   l'empêchent ; la borne haute et `--budget-usd` restent.
7. Exposition : inchangée.
8. Exploitation : l'admin déplace une fois `import/ingest/aromes/tarif.json` vers
   `import/ingest/tarif.json` ; les fichiers des levures restent où ils sont. Les commandes de
   `main` gardent leur effet ; les commandes `lister-divers-recettes.mjs` et
   `lister_divers_recettes.dart` de la branche deviennent `--nature misc`.
9. Coût de sortie : inchangé, faible.

## Conséquences

Plus simple : une nature de plus coûte un dossier et, au besoin, un crochet ; P54 décrit un seul
moteur. Les règles Cf et NFKC protègent aussi les textes des levures.

Plus difficile : R2 change le code des levures pendant leur campagne s'il part avant la fin des
lots. Une fusion de plus sur la branche des divers (R3), avec renumérotation des versions.

Documents touchés : ADR-013, ADR-017 et ADR-018 (note de renvoi vers cet ADR), `CLAUDE.md`
(« Le projet », « Structure », « Commandes utiles », P19, P20, P22, P54, P55, P62, P63,
« Coûts variables », « Une écriture de masse »), `exigences-techniques.md` (moteur, tarif,
listes du groupe, catalogue des coûts), `exigences-fonctionnelles.md` (fiche d'un divers),
`DATA_SOURCES.md`, `guide-reseau.md`, `CHANGELOG.md`.

## Sources

- Code relevé le 2026-11-21 : `origin/main` (`bd799ef`) et `claude/focused-brahmagupta-h8gzfh`
  (`bae432f`), base commune `5ff7725` ; `claude/adr-017-fiche-levure` (`7f2755f`).
- Montants : ADR-017 section 6 et ADR-018 section 6, estimations non mesurées ; tarif de
  `claude-fable-5-2` relevé le 2026-11-03 (ADR-013), à vérifier avant chaque lot.
