# Changelog

Une entrée par version, la plus récente en tête, sous la date du jour. Titre
`### vX.Y.Z — fonctionnel` (ce que voit l'utilisateur) ou `— technique` (architecture,
données, outillage), ou les deux.

## 2026-11-08

### v0.1.11 — fonctionnel

L'après-brassage arrive (incrément v0.4) : un brassin va de « Prévu » à « Terminé » sans Excel.
La fiche d'un brassin suit la fermentation, l'embouteillage et la fin, avec un retour en arrière
à chaque statut et l'abandon. Le relevé de fermentation note densité, température, date et note,
montre l'écart à la mesure précédente et trace une courbe de densité et de température. Le bloc
« Prévu et mesuré » compare densités, degré, volume et rendement réel. Une donnée absente affiche
« Indisponible » et sa raison. L'embouteillage note la date, la densité finale, les bouteilles,
le volume et le sucre, sans calcul de degré après bouteille. Ces saisies marchent sans réseau.

### v0.1.11 — technique

`brewing/` : comparaison prévu / mesuré, rendement réel sans exception (`readMashEfficiency`
remplace `measuredMashEfficiency`), `FermentationPoint`, avec leurs fixtures. Règles : champs
d'embouteillage et mesures retenues sur `brews/`, `phase` sur les événements, bornes de chaque
mesure selon sa nature, identiques à celles des formulaires. ADR-004 : `fl_chart` figé, importé
par `trace_courbe.dart` seul ; contrôle P18 ajouté, P1 étendu à `deferred as`. La courbe ajoute
93 582 octets à `main.dart.js`, de 4 242 444 à 4 336 026, corrections de relecture comprises.
L'APK release, mesuré avant et après toute la v0.4 avec une clé jetable, passe de 61 102 880 à
62 495 656 octets (+1 392 776), sous le seuil de 2 Mo fixé pour la courbe seule.

Paquets — `app/pubspec.lock` : `fl_chart` 1.3.0 ajouté, aucune autre version ne change.
### v0.1.10 — technique

Le tag d'une version se pose après la CI verte sur `main` (`CLAUDE.md`, « Chaîne de travail »,
étape 6). Posé avant, il fait échouer `check-version.mjs` sur le push de la fusion, et
`deploy.yml` ne déploie pas : c'est arrivé à la v0.1.9 (leçon 16).

### v0.1.9 — fonctionnel

L'application porte son propre logo, le médaillon Kass'Beer, sur Android et sur le web. Sur
Android, l'icône est adaptative : médaillon entier sur fond crème, sans coupe quel que soit
le masque du lanceur. Les PNG sont tirés de `assets/Kassbeer_transparent.png`, sans nouvelle
dépendance.

### v0.1.8 — fonctionnel

Le brassin et le jour de brassage hors ligne arrivent (incrément v0.3). Un brassin se crée
depuis une recette, avec une copie figée de la recette et de l'équipement. La recette reçoit
une chronologie, préremplie depuis les paliers et l'ébullition. « Préparer le brassage » charge
tout sur le téléphone. L'écran du jour affiche l'étape en cours, un minuteur lisible de loin
et les heures prévues recalculées après un retard. Il permet de sauter une étape, de corriger
une heure et de saisir températures, densités, volumes et pH. Sans réseau, les saisies restent
sur le téléphone, même application fermée, et partent au retour du réseau. L'écran reste
allumé. La fin d'un minuteur déclenche une vibration et un bip, même en mode silencieux.

### v0.1.8 — technique

`brewing/` : `recomputeSchedule` corrigé (retour en arrière, étape sautée, début en double),
`stepRecordsFromEvents`, `defaultBrewSteps`, `readGravity`. Règles : `brew_steps` (60 au plus),
`owner_name` des brassins, événement `step_skipped`, forme de chaque événement selon sa nature,
`step_key` non vide. Alerte de fin de minuteur par un canal Kotlin `fr.kassbeer/alert` et Web
Audio, sans paquet de son (ADR-003), avec la permission Android `VIBRATE`. Contrôles : P2 étendu,
P17 (canal de plateforme). `main.dart.js` passe de 3 211 502 à 4 170 391 octets, code de cet
incrément et `flutter_localizations` compris. La taille de l'APK release n'est pas mesurée sur le
poste, qui n'a plus la clé de signature : le job CI le compile.

Paquets — `app/pubspec.lock` : `wakelock_plus` 1.8.2, `wakelock_plus_platform_interface` 1.7.0,
`package_info_plus` 9.0.1 → 10.2.2, `package_info_plus_platform_interface` 3.2.1 → 4.1.0,
`win32` 5.15.0 → 6.4.0, `flutter_localizations` (SDK), `intl` 0.20.2, `dbus` 0.8.0,
`ffi_leak_tracker` 0.1.2, `petitparser` 7.0.2, `xml` 7.0.1 ; `web` 1.1.1 devient une dépendance
directe, sans changer de version.

### v0.1.7 — fonctionnel

Équipements et recettes arrivent, premier incrément de la version 1 (v0.2 du découpage).
Chaque brasseur décrit ses équipements et ses recettes, et lit ceux du groupe sans pouvoir
les modifier. L'éditeur de recette affiche, à chaque saisie, la densité initiale, la densité
finale, le degré, l'amertume (IBU) et la couleur (EBC). Quand une donnée manque, l'écran dit
laquelle, sans valeur de remplacement. Une recette se duplique à son nom. La suppression d'un
équipement annonce les recettes qui l'utilisent. Tout marche hors ligne sur l'APK.

### v0.1.7 — technique

`brewing/` reçoit la densité finale prévue par l'atténuation (fixture tirée de trois fiches),
la clé d'ingrédient `ingredientKey` et le diagnostic `computeRecipe`. Les valeurs stockées
passent par `fromStored` ; `extract` et `first_wort` sortent du modèle. `recipes/` et
`equipment/` reçoivent `owner_name`, libellé d'affichage égal au nom du jeton, borné aussi
dans les copies des brassins. Les règles refusent tout nombre non fini ou hors de ±1e9, et un
rendement d'empâtage hors de 0 à 100 %. `app/` dépend de `brewing` ; aucun autre paquet ne change
dans `pubspec.lock`. Le découpage de la version 1 et ses décisions D1 à D8 entrent dans
`projet.md`.

## 2026-11-07

### v0.1.6 — technique

Les actions GitHub passent sous Node 24, que GitHub impose après la fin de Node 20 :
`checkout` v7.0.1, `setup-node` v7.1.0, `setup-java` v6.1.0, `cache` v6.1.0,
`upload-artifact` v7.0.2, `download-artifact` v8.0.2, `google-github-actions/auth` v3.0.0.
Aucune option utilisée par nos workflows ne change. Les quatre alertes Dependabot de
`rules-tests/` sont tolérées par décision de l'utilisateur : aucune version de
`firebase-tools` ou de `firebase` ne les corrige encore, et notre usage n'appelle pas le
code vulnérable. `exigences-techniques.md` documente l'analyse.

### v0.1.5 — technique

`session-start.sh` avertit au démarrage d'une session quand l'adresse d'auteur du prochain commit (`git var GIT_AUTHOR_IDENT`) n'est
pas une adresse `noreply` de GitHub : le dépôt est public, et l'adresse d'un commit poussé
ne s'efface plus (proposition de l'architecte, validée par l'utilisateur). ADR-002 consigne deux
décisions de l'utilisateur : l'e-mail est masqué sur GitHub, et le code n'a pas de licence
(tous droits réservés).

### v0.1.4 — technique

Trois contrôles proposés par ADR-002 entrent dans `CLAUDE.md`, sur validation de
l'utilisateur. Sur une branche externe, P10 couvre aussi les fichiers qu'un hook exécute
(`.claude/**`, `CLAUDE.md`, `scripts/**`, les `package*.json` et la configuration prettier
de `rules-tests/`), lus avant d'ouvrir une session : les hooks s'exécutent sur le poste. P15
interdit tout prénom, nom ou e-mail réel dans ce que le dépôt public publie. P16 réserve aux
valeurs publiques toute variable lisible par le job (dépôt, organisation, environnement
`production`), car `toJSON(vars)` les
affiche dans le journal public des runs. La section « Git » de `CLAUDE.md` et
`guide-reseau.md` décrivent ces règles. `exigences-techniques.md` note que l'environnement
`production` n'autorise pas le contournement par un administrateur.

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

