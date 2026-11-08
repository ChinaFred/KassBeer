# Projet — fiche de démarrage

Rempli par le skill `demarrage-projet`, validé par l'utilisateur. Ce document décrit
l'intention ; il change rarement. Une modification passe par l'`architecte` si elle touche
les contraintes.

## Intention

- **Nom** : Kass'Beer.
- **Problème résolu, pour qui** : Kass'Beer remplace les fiches Excel de brassage amateur
  d'un brasseur et de quelques amis : recette, calculs, déroulé du jour de brassage, suivi
  et coût d'un brassin.
- **Visite type** :
  1. Le brasseur crée ou reprend une recette (malts, houblons, épices, sucres, levure, eau)
     et choisit son équipement. L'application calcule densités, degré, IBU, EBC et coût.
  2. Le jour du brassage, il suit la chronologie sur son téléphone : minuteurs, heures
     prévues recalculées quand une étape prend du retard, saisie des températures et des
     densités mesurées, y compris sans réseau.
  3. Après le brassage, il note la fermentation, l'embouteillage, puis ses dégustations.
- **Critère de réussite à six mois** :
  - plus aucun brassin suivi dans Excel ;
  - l'écart entre densité prévue et mesurée diminue, grâce au rendement réel mesuré sur
    chaque équipement ;
  - les dégustations reliées aux recettes conduisent à corriger des défauts (mousse qui ne
    tient pas, bière qui vieillit mal).
- **Hors périmètre** : vente ou commerce de bière ; usage par une brasserie
  professionnelle ; iOS et desktop en version 1.
- **Outil remplacé, données à reprendre** : 16 fiches Excel (exportées en PDF), de
  décembre 2022 à septembre 2025. Chaque fiche contient un en-tête (densités, degré, EBC et
  IBU visés, volumes, nombre de bouteilles, coût), une chronologie (heure prévue et réelle,
  température visée et mesurée, action, durée, densité), les matières premières avec leurs
  prix (malts, houblons, épices, sucres, eau, levure, électricité, embouteillage), et pour 3
  fiches un relevé de densité en fermentation. Les fiches contiennent des erreurs de saisie
  à corriger à l'import : quantité lue avec un point (22.4 g lu 22 400 g), densité de
  l'en-tête différente de la densité mesurée, champs copiés d'une fiche précédente, degré
  calculé sur la densité visée. Les avis de dégustation sont dans les noms de fichier.

## Utilisateurs

- **Nombre, simultanés** : le brasseur et quelques amis brasseurs, moins de 10 comptes ;
  rarement plus de 2 ou 3 connectés en même temps.
- **Rôles** : un administrateur (le brasseur à l'origine du projet) ; des brasseurs égaux,
  qui créent leurs recettes et leurs brassins et partagent leurs recettes avec le groupe.
- **Appareils et conditions d'usage** : téléphone Android posé près des cuves le jour du
  brassage (mains occupées, réseau incertain) ; navigateur web pour préparer une recette
  et relire l'historique.
- **Langue, accessibilité** : français. Écran du jour de brassage lisible à distance
  (gros chiffres, minuteurs visibles).

## Équipements

- Le brasseur : installation à plusieurs cuves (empâtage, filtration, cuisson).
- Ses amis : Grainfather (cuve tout-en-un).
- Chaque équipement a son profil : volumes, rendement d'empâtage, pertes, évaporation.
- Densimètre connecté : RAPT Pill (KegLand). Son intégration vient après la version 1.

## Contraintes

### Exposition et environnement

- **Mode** : ouvert sur Internet (application web publique et APK Android), accès réservé
  aux comptes invités.
- **Création des comptes** : sur invitation de l'administrateur ; connexion par compte
  Google, comme Kass'Dalle.
- **Infrastructure imposée** : aucune. Projet Firebase séparé de celui de Kass'Dalle. Dépôt GitHub `ChinaFred/KassBeer`, public depuis le 2026-11-07 (ADR-002).
- **Pile connue** : le brasseur exploite déjà Kass'Dalle sur Firebase
  (Auth Google, Firestore, Storage, Hosting, Cloud Functions) et connaît cette pile.

### Données

- **Nature, données sensibles** : recettes, brassins, mesures, dégustations, prix
  d'achat. Données personnelles limitées au nom et à l'e-mail des comptes.
- **Réglementation** : RGPD pour les comptes (nom, e-mail).
- **Données privées à un utilisateur** : le stock d'ingrédients, les prix d'achat et le
  coût réel d'un brassin. Le groupe voit les recettes, les profils d'équipement et les
  brassins hors coût (mesures et dégustations comprises). Exception : les prix et coûts de
  test de `brewing/test/fixtures/cost.json` sont publics (ADR-002).
- **Conservation, sauvegarde, export** : conservation sans limite ; sauvegarde gérée de
  Firestore ; export JSON dans Admin (ce que le groupe voit, plus les prix de
  l'administrateur) ; import et export BeerJSON et BeerXML à venir (ADR-005).

### Plateformes et exploitation

- **Cibles** : Android et web.
- **Hors connexion** : obligatoire pour l'écran du jour de brassage (chronologie,
  minuteurs, saisie des mesures), synchronisé au retour du réseau.
- **Maintenance, compétences** : le brasseur, avec des sessions Claude Code ; il connaît
  Flutter, Firebase et TypeScript par Kass'Dalle.
- **Distribution des mises à jour** : web sur Firebase Hosting ; APK signé distribué par
  Firebase App Distribution (ADR-001).

### Coûts et délais

- **Budget mensuel (à l'arrêt / à l'usage)** : du même ordre que Kass'Dalle.
- **IA ou API facturée, pour quoi** : aucune dans l'application en version 1 (ADR-001).
  L'import des 16 fiches est préparé par une session Claude Code et validé dans Admin ›
  Import. Ensuite, côté serveur seulement : substitution d'un ingrédient manquant,
  explication d'un écart prévu / mesuré, diagnostic d'un défaut de dégustation.
- **Échéance de la première version** : le prochain brassin, dans quelques semaines. La
  version 1 peut être réduite pour tenir ce délai.

## Périmètre de la version 1

- Recette et calculs : densités initiale et finale, degré (avant et après refermentation
  en bouteille), IBU, EBC, coût total et par bouteille.
- Profils d'équipement.
- Jour de brassage hors ligne : chronologie, minuteurs, saisie des mesures, rendement réel.
- Import des 16 fiches.

Après la version 1 : RAPT Pill, stock, eau (sels et pH), conditionnement (calcul du sucre de
resucrage), dégustations notées, assistant IA. La masse et la nature du sucre de resucrage sont
notées dès la v0.4, sans calcul.

### Découpage en incréments

Proposé par `product-owner`, validé par l'utilisateur le 2026-11-07. Un incrément « v0.N »
est une étape de la planification. Il ne change pas la règle de numérotation du dépôt
(CLAUDE.md, « Version ») : l'incrément v0.2 est livré sous la version 0.1.7 (D7).

| Incrément | Contenu | Critère de fin |
|---|---|---|
| v0.2 | Équipements et recettes, avec les calculs affichés (densités initiale et finale, degré, IBU, EBC) et la liste des données à compléter | la recette du prochain brassin est saisie ; un autre brasseur la lit sans pouvoir la modifier |
| v0.3 | Brassin (création depuis une recette et un équipement, copie figée), « Préparer le brassage », jour de brassage hors ligne : chronologie (`brew_steps`), minuteurs, heures recalculées, mesures, écran allumé | un brassage à blanc complet sur l'APK en mode avion, application tuée puis relancée, minuteur juste, mesures arrivées au retour du réseau |
| v0.4 | Après le brassage : fermentation, densité finale et degré mesurés, rendement réel, bouteilles, statut jusqu'à « terminé » | un brassin va de « prévu » à « terminé » sans Excel : seuil du prochain brassin (D1) |
| Socle BeerJSON (ADR-005, ajouté le 2026-11-08) | Recettes en BeerJSON partiel (L1), puis échange BeerJSON et BeerXML, référentiels d'ingrédients, 415 recettes publiques (L2 à L4) | L1 : brassage à blanc réussi sur l'APK en mode avion, recettes et brassins au nouveau format ; L2 à L4 : voir ADR-005 |
| v0.5 | Mes prix, coût d'une recette (total et par bouteille), coût réel figé d'un brassin | un prix manquant affiche la panne ; le coût d'une fiche connue est retrouvé |
| v0.6 | Admin › Import des 16 fiches | 16 fiches créées, 0 en erreur, divergences listées, aucun doublon au second import |

### Décisions du découpage

Validées par l'utilisateur le 2026-11-07, sur recommandation de `product-owner`.

- D1 : le prochain brassin a lieu dans moins de quatre semaines ; la v0.4 est le seuil.
- D2 : le coût (v0.5) et l'import (v0.6) passent après le prochain brassin.
- D3 : la chronologie du jour vit dans un champ `brew_steps` de la recette (nom, durée,
  température), prérempli depuis les paliers et l'ébullition ; il arrive en v0.3, avec ses
  règles et ses tests.
- D4 : la densité finale prévue se calcule par l'atténuation de la levure, avec une fixture
  tirée des fiches (fait en v0.2).
- D5 : le degré après refermentation en bouteille sort de la v1, avec le conditionnement.
- D6 : seul le propriétaire d'un brassin écrit ses mesures, comme le disent les règles.
- D7 : les incréments v0.2 à v0.6 sont des étapes de planification, distinctes des numéros
  de version du dépôt.
- D8 : un ré-import identifie une fiche par un identifiant tiré de son nom et ignore ce qui
  existe déjà.

## Questions ouvertes

Tranchées le 2026-11-07 : voir `decisions/ADR-001-pile-technique.md`, « Arbitrages de
l'utilisateur ».

- Format du webhook RAPT Pill, à vérifier sur `docs.rapt.io` avant l'ADR dédié.
