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
- **Infrastructure imposée** : aucune. Projet Firebase séparé de celui de Kass'Dalle. Dépôt GitHub `ChinaFred/KassBeer`, privé.
- **Pile connue** : le brasseur exploite déjà Kass'Dalle sur Firebase
  (Auth Google, Firestore, Storage, Hosting, Cloud Functions) et connaît cette pile.

### Données

- **Nature, données sensibles** : recettes, brassins, mesures, dégustations, prix
  d'achat. Données personnelles limitées au nom et à l'e-mail des comptes.
- **Réglementation** : RGPD pour les comptes (nom, e-mail).
- **Données privées à un utilisateur** : le stock d'ingrédients, les prix d'achat et le
  coût réel d'un brassin. Le groupe voit les recettes, les profils d'équipement et les
  brassins hors coût (mesures et dégustations comprises).
- **Conservation, sauvegarde, export** : conservation sans limite ; sauvegarde gérée de
  Firestore ; export JSON dans Admin (ce que le groupe voit, plus les prix de
  l'administrateur) ; export BeerXML après la v1 (ADR-001).

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

Après la version 1 : RAPT Pill, stock, eau (sels et pH), conditionnement (sucre de
resucrage), dégustations notées, assistant IA.

## Questions ouvertes

Tranchées le 2026-11-07 : voir `decisions/ADR-001-pile-technique.md`, « Arbitrages de
l'utilisateur ».

- Format du webhook RAPT Pill, à vérifier sur `docs.rapt.io` avant l'ADR dédié.
