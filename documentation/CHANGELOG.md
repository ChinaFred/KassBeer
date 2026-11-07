# Changelog

Une entrée par version, la plus récente en tête, sous la date du jour. Titre
`### vX.Y.Z — fonctionnel` (ce que voit l'utilisateur) ou `— technique` (architecture,
données, outillage), ou les deux.

## 2026-11-07

### v0.1.3 — technique

Le dépôt GitHub est public depuis le 2026-11-07 (ADR-002), pour obtenir les rulesets sans
plan payant. Un ruleset protège `main` (PR requise, quatre contrôles, ni force push ni
suppression) et un autre les tags `v*`. Approbation des workflows de forks, actions
limitées, secret scanning, push protection et alertes Dependabot sont actifs.
Les noms de personnes sortent des fixtures de `brewing/`, et le cas `mansart` devient
`ale-blonde-21-04-25` ; ils restent dans l'historique. Les prix d'achat de `cost.json`
restent publics par décision de l'utilisateur : `CLAUDE.md` l'écrit en exception à la règle
des prix, et P5 cite ADR-002. Les tags
`v0.1.0` et `v0.1.1`, oubliés, sont posés. `exigences-techniques.md` décrit le premier
déploiement et le clic « Commencer » d'App Distribution, sans lequel l'API des versions
répond 404. `.vscode/settings.json` (couleurs de VS Code) est versionné.

### v0.1.2 — technique

Mise en place de la production et du poste de développement. Projet Firebase `kassbeer`
créé en plan Blaze, avec un budget de 5 € et ses alertes. Firestore `(default)` en
`europe-west1`, protégé contre la suppression, sauvegardé chaque jour pendant 7 jours.
Applications web et Android enregistrées, empreintes de la clé de release déclarées (P8),
connexion Google seule, clés d'API restreintes au site, au paquet Android et aux API
Firebase. Workload Identity Federation et environnement GitHub `production` configurés
pour `deploy.yml` ; les secrets de signature restent à poser depuis le poste. Deux
exceptions servent au développement : le référent `localhost` sur la clé web et la SHA-1
de débogage du poste sur la clé Android. La documentation de GitHub réserve les secrets
d'environnement aux plans payants sur un dépôt privé : leur lecture reste à constater. La
protection de `main` est indisponible en plan GitHub Free sur un dépôt privé.
`.firebaserc` pointe sur `kassbeer`. Les commandes de lancement passent
`--dart-define-from-file=firebase.env.json`, sans quoi l'application affiche
« Configuration Firebase absente ». `exigences-techniques.md` reçoit l'état de la
production et le poste de développement.

### v0.1.1 — fonctionnel

Premier socle utilisable de l'application, sur Android et le web. Connexion par compte
Google, réservée aux adresses invitées ; un compte non invité voit son adresse pour la
transmettre ; une panne n'est jamais présentée comme un refus. Accueil avec la navigation
Recettes, Brassins, Équipements (écrans à venir) et Admin. Admin › Membres invite et retire
les brasseurs ; un administrateur ne se retire pas lui-même et n'en retire pas un autre (la
console Firebase le fait). Bandeau hors ligne.

### v0.1.1 — technique

Paquet Dart pur `brewing/` : densités, densité initiale prévue, rendement, degré (avant et
après resucrage, sans hausse forfaitaire), IBU de Tinseth, EBC de Morey, coût, planning du
jour de brassage ; 29 tests rejouent des cas tirés des 16 fiches Excel, avec leurs erreurs
rangées dans `divergences`. `firestore.rules` (membres sur invitation, compte Google
vérifié, données privées sous `users/`, brassin figé, ajustements en liste blanche, journal
d'erreurs borné) et 296 tests sur l'émulateur. `firebase.json` : cache et en-têtes de
sécurité. `ErrorReportService` : rapports dédoublonnés, plafonnés à 20 par minute et 200 par
session, sans e-mail ni URL. CI GitHub Actions (version, Flutter et `brewing/`, règles,
compilation Android) et déploiement (Hosting, règles, App Distribution) par Workload
Identity Federation, inactif tant que le projet Firebase n'est pas configuré. `CLAUDE.md` :
exception à `debugPrint` quand aucun rapport ne peut partir.

Paquets (nouveaux lockfiles) — `app/pubspec.lock` : firebase_core 4.15.0, firebase_auth
6.7.0, cloud_firestore 6.8.0, google_sign_in 7.2.0, flutter_riverpod 3.3.1, go_router
17.2.3, package_info_plus 9.0.1 ; développement : flutter_lints 6.0.0, fake_cloud_firestore
4.4.0, fake_async 1.3.3 ; plateformes : firebase_core_web 3.12.0,
firebase_core_platform_interface 8.1.1, firebase_auth_web 6.3.0,
firebase_auth_platform_interface 9.1.0, cloud_firestore_web 5.7.3,
cloud_firestore_platform_interface 8.0.7, google_sign_in_android 7.2.18, google_sign_in_web
1.1.3, google_sign_in_platform_interface 3.1.0. `brewing/pubspec.lock` : lints 6.1.0, test
1.33.0. `rules-tests/package-lock.json` : firebase-tools 15.35.0,
@firebase/rules-unit-testing 5.0.2, firebase 12.19.0, prettier 3.9.6. APK : compilé par le
job « Android — compilation » de la PR (pas de SDK Android en session cloud).

### v0.1.0 — technique

Démarrage du projet. Pile retenue (ADR-001) : Flutter pour Android et le web, Firebase
(Auth Google, Firestore `europe-west1`, Hosting, App Distribution), sans serveur ni IA en
version 1. Les calculs de brassage vivront dans le paquet Dart pur `brewing/`. `CLAUDE.md`
reçoit les sections du projet, les règles du jour de brassage hors ligne, des unités, des
prix privés et du cache web, et quatorze contrôles (P1 à P10 de l'architecte, P11 à P14
de `securite`). Les JSON d'import des fiches, qui contiennent des prix, ne sont pas
versionnés. Outillage : formateurs Dart et
Prettier, version portée par `app/pubspec.yaml`, installation de Flutter 3.44.6 en session
cloud. Le bac à sable et son skill sont retirés : le projet est petit et le délai court.

