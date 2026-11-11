# ADR-001 — Pile technique de la version 1

- **Statut** : accepté le 2026-11-07
- **Date** : 2026-11-06
- **Remplace** : —
- **Modifié par** : ADR-002 (dépôt public, minutes de la CI) ; ADR-005 (recettes en BeerJSON,
  référentiels, et export BeerXML avancé avant la v1, malgré les mentions « après la v1 » ci-dessous) ; ADR-006 (un serveur
  Cloud Functions Node 24 avant l'IA et le RAPT Pill, pour les tickets) ; ADR-008 (points d'accès
  publics des tickets, Cloud Storage, premier poste de coût variable)

## Contexte

Kass'Beer remplace 16 fiches Excel de brassage pour moins de 10 comptes, sur Android et le
web (`documentation/projet.md`). Quatre contraintes de la fiche décident :

- l'écran du jour de brassage fonctionne sans réseau, sur un téléphone près des cuves ;
- l'accès est réservé aux comptes invités, sur une application ouverte sur Internet ;
- le stock et les prix d'achat sont privés à chaque brasseur ; le groupe voit recettes,
  brassins, mesures et dégustations ;
- la version 1 doit servir au prochain brassin, dans quelques semaines.

Le brasseur exploite déjà Kass'Dalle (Flutter, Firebase, Cloud Functions Node 22 /
TypeScript, GitHub Actions). Il connaît cette pile et la maintient avec Claude Code.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer (Excel) | aucun effort | aucun calcul partagé, aucun usage hors ligne sur téléphone, aucun suivi du rendement | 0 € / 0 € |
| A. Flutter + Firebase, sans Cloud Functions en v1 ; import des 16 fiches préparé par une session Claude Code et relu dans l'écran Admin › Import | pile connue, code de Kass'Dalle réutilisable (auth, rapport d'erreurs, CI) ; cache hors ligne de Firestore sur Android ; aucun serveur à écrire en v1 ; aucun coût variable en v1 | règles Firestore = seul contrôle d'accès, à tester rôle par rôle ; le web ne garantit pas le hors ligne au démarrage ; IA côté serveur reportée à un ADR-002 | ≈ 0 € / ≈ 0 à 1 € par mois (Blaze, sous les quotas gratuits) |
| A'. Comme A, avec une Cloud Function d'import par IA dès la v1 | import rejouable dans l'application | Functions, Secret Manager, poste de coût, plafond et relecture `securite` en plus, pour 16 fiches importées une seule fois ; 2 à 3 jours de plus | ≈ 0 à 0,10 € / import complet ≈ 0,2 à 2 $ une fois (à vérifier) |
| B. Flutter + Supabase (Postgres, RLS, région Francfort) | SQL et RLS standard, sortie facile, données en Europe | plan gratuit mis en pause après une semaine sans activité, donc entre deux brassins ; plan Pro à 25 $ par mois ; pas de cache hors ligne fourni (PowerSync ou synchronisation à écrire) ; pile nouvelle | 0 $ avec pauses, ou ≈ 25 $ / ≈ 25 $ |
| C. Application web progressive en TypeScript + Firebase, sans APK | un seul langage avec les futures Functions : calculs partageables sans duplication | framework web nouveau pour le brasseur ; service worker à écrire ; minuteurs ralentis par Chrome Android en arrière-plan ; aucune réutilisation du code Flutter de Kass'Dalle | ≈ 0 € / ≈ 0 à 1 € |

## Décision

Option A. Flutter (Android, web) et Firebase (Auth Google, Firestore en `europe-west1`,
Hosting), sans Cloud Functions ni appel d'IA en version 1. C'est le chemin le plus court
vers un brassin suivi dans l'application : pile connue, aucun serveur à écrire, et les 16
fiches s'importent une seule fois.

Les calculs de brassage vivent dans un paquet Dart pur (`brewing/`), lu par l'application
seule. L'import des 16 fiches produit des fichiers JSON, écrits par une session Claude Code
à partir du texte des fiches, que l'administrateur relit et valide dans Admin › Import.
L'IA côté serveur, le RAPT Pill et l'export BeerXML viennent après la v1, chacun par son
ADR.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : interface et calculs sur l'appareil (Android,
   navigateur). Règles d'accès dans Firestore. Aucune fonction serveur en v1. Plus tard,
   Cloud Functions Node 22 / TypeScript en `europe-west1` pour l'IA et le webhook du RAPT
   Pill.
2. **Ce qui existera en double** : rien en v1. Densités, degré, IBU (Tinseth), EBC (Morey),
   rendement et coût n'existent qu'en Dart, dans `brewing/`. Une future fonction d'IA reçoit
   les valeurs calculées par le client avec la demande ; elle ne recalcule pas. Un calcul
   côté serveur demande un changement lourd et une fixture partagée.
3. **Ce qui pèse au démarrage** : rien de lourd côté serveur en v1. Côté web, le premier
   téléchargement Flutter (CanvasKit et `main.dart.js`, plusieurs Mo) ; acceptable pour
   l'usage de préparation. Aucun SDK d'IA dans le client.
4. **Compilation de chaque cible** : `flutter build web --release` et
   `flutter build apk --release`. Une session cloud n'a pas de SDK Android : le job
   « Android — compilation » de la CI compile l'APK dès que `pubspec.yaml`, `pubspec.lock`
   ou `android/` change.
5. **Qui voit quoi** : un compte n'accède à rien sans un document `members/{email}` créé
   par l'administrateur. Les membres lisent recettes, équipements, brassins et mesures. Seul
   le propriétaire écrit les siens. Prix et stock vivent sous `users/{uid}/…`, lisibles par
   lui seul. Le coût d'une recette se calcule à l'affichage avec les prix du lecteur.
   Aucune donnée ne part vers un service tiers depuis l'application en v1.
6. **Ce qui coûte à l'usage, plafond** : aucun poste facturé à l'usage en v1. Firestore et
   Hosting restent sous les quotas gratuits (50 000 lectures et 20 000 écritures par jour).
   Une alerte budgétaire à 5 € est posée sur le compte de facturation. La CI reste sous les
   2 000 minutes gratuites mensuelles du plan GitHub Free (caduc depuis ADR-002 : dépôt
   public, minutes gratuites).
7. **Exposition** : ouvert sur Internet. Authentification Google par Firebase Auth ;
   autorisation par les règles Firestore ; en-têtes de sécurité et de cache dans
   `firebase.json`. Les règles sont le seul contrôle d'accès, testées contre l'émulateur.
8. **Exploitation, sauvegarde, mise à jour** : maintenu par le brasseur avec Claude Code.
   Sauvegarde quotidienne gérée de Firestore (rétention 7 jours), et export JSON depuis
   Admin (ce que le groupe voit, plus les prix de l'administrateur, arbitrage 13). Mise à jour web par Firebase Hosting, avec `index.html` et les fichiers
   d'amorçage en `no-cache`. APK signé, distribué par Firebase App Distribution, construit
   par GitHub Actions sur un push de la branche principale. La clé de signature vit dans
   les secrets GitHub et dans une copie hors ligne.
9. **Coût de sortie** : moyen. Les règles et le modèle de données sont propres à
   Firestore. Le paquet `brewing/` est du Dart pur, indépendant de Firebase. L'export JSON
   d'Admin, puis BeerXML après la v1, rendent les données portables.

## Arbitrages de l'utilisateur (2026-11-07)

L'utilisateur a retenu toutes les recommandations du livrable « Démarrage » :

1. Import des 16 fiches par une session Claude Code, relu et écrit par Admin › Import.
   Aucune IA dans l'application en v1.
2. APK distribué par Firebase App Distribution.
3. Plan Blaze dès la v1, sauvegarde gérée de Firestore, alerte budgétaire à 5 €.
4. Coût d'un brassin privé à son brasseur (`users/{uid}/brew_costs/`).
5. Profils d'équipement lisibles par le groupe.
6. Hors ligne garanti sur l'APK seulement.
7. JSON d'import non versionnés : `import/` est dans `.gitignore`, et Admin › Import
   charge le fichier par un sélecteur (révisé le 2026-11-07, après la relecture de
   `securite` : un fichier retiré reste dans l'historique Git).
8. Flutter 3.44.6, comme Kass'Dalle.
9. Alarme des minuteurs écran verrouillé après la v1 ; écran maintenu allumé en v1.
10. Résidence de Firebase Auth en Europe non vérifiée : acceptée.
11. `docs.rapt.io` à autoriser dans le réseau de la session avant l'ADR du RAPT Pill.
12. Formule d'adresse : celle du modèle (« Maître », « Seigneur », « Majesté »).

13. Export JSON d'Admin : ce que le groupe voit, plus les seuls prix de l'administrateur.
    Les prix des autres brasseurs restent privés (P5).

Contrôles P1 à P10 inscrits dans `CLAUDE.md`, puis P11 à P14 proposés par `securite` à la
relecture (comptes vérifiés et invités, en-têtes web, journal d'erreurs, secrets de la CI). Section « Bac à sable » et skill
`experience-sandbox` retirés.

## Conséquences

Plus simple : aucune fonction serveur, aucun secret, aucun coût variable en v1. Le hors
ligne repose sur le cache persistant de Firestore, sans code de synchronisation.

Plus difficile : les règles Firestore portent seules les droits ; chaque changement de
`firestore.rules` arrive avec son test dans `rules-tests/`. Le hors ligne n'est garanti que
sur l'APK Android : sans service worker, le web ne démarre pas sans réseau. L'écran du jour
de brassage n'emploie ni transaction, ni appel serveur, ni minuteur en mémoire comme source
de vérité.

Le projet passe au plan Blaze dès la v1, pour la sauvegarde gérée de Firestore et pour
l'IA à venir. Il dépense ≈ 0 € tant que l'usage reste sous les quotas.

Règles et contrôles proposés pour `CLAUDE.md` : hors ligne du jour de brassage, calculs
dans `brewing/` seulement, prix privés, tests des règles, cache web, compilation de l'APK,
numéro de build, clé de signature, validation du JSON d'import, signalement des
changements de CI (livrable de l'architecte, contrôles P1 à P10).

## Sources

Consultées le 2026-11-06.

- Quotas gratuits Firestore (50 000 lectures, 20 000 écritures par jour) :
  https://firebase.google.com/docs/projects/billing/firebase-pricing-plans
- Cloud Storage : plan Blaze exigé pour un bucket par défaut depuis le 30 octobre 2024 ;
  niveau gratuit en `us-central1`, `us-east1`, `us-west1` seulement :
  https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024
- GitHub Actions, plan Free : 2 000 minutes par mois sur dépôt privé ; Linux 2 cœurs à
  0,006 $ la minute au-delà : https://docs.github.com/en/billing/reference/actions-runner-pricing
  (lu sur la copie Enterprise Server 3.17 de la page ; tarif à vérifier sur github.com).
  Caduc depuis ADR-002 : dépôt public, minutes gratuites.
- Supabase : pause d'un projet gratuit après une semaine d'inactivité ; Pro à partir de
  25 $ par mois : https://supabase.com/pricing
- Flutter web : retrait du service worker par défaut annoncé en octobre 2024 :
  https://groups.google.com/g/flutter-announce/c/0Vv-j_TyrdI
- Firebase App Distribution : 500 testeurs par projet, 200 par groupe :
  https://firebase.google.com/docs/app-distribution/add-remove-testers?platform=android
  (gratuité : à vérifier sur la page de tarifs Firebase).
- RAPT : webhooks de télémétrie et API `api.rapt.io` à jeton, déclarée non supportée par
  KegLand : https://docs.rapt.io/integrations/web-hooks,
  https://docs.rapt.io/equipment/external-device (lus par un résultat de recherche ; le
  site n'était pas joignable depuis la session ; format du webhook à vérifier).
- Prix des modèles (option A') : Gemini 2.5 Flash 0,30 $ / 2,50 $ par million de jetons,
  Claude Sonnet ≈ 3 $ / 15 $ par million de jetons, d'après des agrégateurs ; à vérifier
  sur https://ai.google.dev/gemini-api/docs/pricing et
  https://platform.claude.com/docs/en/about-claude/pricing.
- Versions de référence lues dans `/home/user/KassDalle` : Flutter 3.44.6
  (`.github/workflows/ci.yml`), `firebase_core` 4.15.0, `firebase_auth` 6.7.0,
  `cloud_firestore` 6.8.0, `google_sign_in` 7.2.0, `flutter_riverpod` 3.3.1, `go_router`
  17.2.3, `wakelock_plus` 1.3.3 (`kass_dalle/pubspec.lock`).
