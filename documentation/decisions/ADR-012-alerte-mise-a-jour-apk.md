# ADR-012 — Mise à jour de l'APK depuis l'application : APK et manifeste sur Firebase Hosting

- **Statut** : accepté le 2026-11-14 (option A ; arbitrages de l'utilisateur ci-dessous)
- **Date** : 2026-11-14
- **Remplace** : — (complète ADR-001, arbitrage 2 : App Distribution reste en parallèle ;
  complète ADR-007 : second `FileProvider`, limité aux mises à jour)

## Contexte

Le ticket #36 demande que l'APK signale au lancement qu'une nouvelle version existe et
propose de l'installer, comme Kass'Dalle. Il demande aussi une explication du mode de
déploiement actuel.

Mode actuel (`.github/workflows/deploy.yml`, lu le 2026-11-14) :

- après une CI verte sur `main`, le job `plan` lit par l'API App Distribution le
  `buildVersion` de la dernière version publiée ; un APK se construit si le build `N` de
  `app/pubspec.yaml` le dépasse, ou si la version publiée a expiré (150 jours) ;
- le job `deploy` déploie Hosting, les règles et les index, puis les Functions, puis publie
  l'APK sur App Distribution, groupe `brasseurs`, avec l'entrée du `CHANGELOG.md` en notes ;
- le brasseur reçoit un e-mail d'App Distribution et installe par l'application App Tester
  ou par le lien (`exigences-techniques.md`, « Firebase App Distribution ») ;
- l'application ne lit aucune version publiée.

Limites du mode actuel :

1. Le brasseur ne voit une nouvelle version que par l'e-mail ou en ouvrant App Tester.
2. Hosting est déployé avant la publication de l'APK : un échec de
   `appdistribution:distribute` laisse le web en avance sur l'APK publié.
3. App Tester exige une connexion Google avec l'adresse invitée, et l'autorisation
   « installer des applications inconnues » accordée à App Tester.
4. Une version publiée expire après 150 jours ; `plan` la republie au déploiement suivant.

Kass'Dalle (`/home/user/KassDalle`, lu le 2026-11-14) héberge l'APK sur Hosting à côté d'un
manifeste `apk_release.json` (`version`, `build_number`, `file`, `size_bytes`, `built_at`),
tous deux en `no-cache` (`kass_dalle/firebase.json`). L'application lit le manifeste au
lancement (`kass_dalle/lib/core/services/app_update_service.dart`), télécharge l'APK dans
`cacheDir/updates/`, contrôle sa taille, et ouvre l'installateur du système par le canal
`dev.kassbi.kass_dalle/app_installer` (`MainActivity.kt` : `downloadDir`,
`canRequestInstall`, `openInstallSettings`, `installApk`). La fenêtre
(`kass_dalle/lib/core/presentation/app_update_dialog.dart`) enchaîne offre, autorisation,
téléchargement avec progression et annulation, installation, échec. Le manifeste Android
déclare `REQUEST_INSTALL_PACKAGES` et un `FileProvider` d'autorité `.updateprovider`
limité à `<cache-path name="app_updates" path="updates/"/>`. Un déploiement Hosting
remplace tout le site : `.github/scripts/keep-online-apk.sh` recopie la paire APK +
manifeste en ligne quand l'APK n'est pas reconstruit, et refuse une paire incohérente.
Kass'Dalle lisait d'abord `version.json` : l'application annonçait une version que le
téléchargement ne rendait pas (`TechnicalRequirements.md`, « Le manifeste n'est pas
`version.json` »).

## Options

| Option | Ce que voit le brasseur | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|---|
| Ne rien changer | l'e-mail d'App Distribution | aucun code | limites 1 et 2 | 0 € / 0 € |
| **A. APK + manifeste sur Hosting (Kass'Dalle)** | fenêtre « Nouvelle version », téléchargement dans l'application, écran d'installation du système | tout dans l'application ; modèle éprouvé sur Kass'Dalle | APK public ; `REQUEST_INSTALL_PACKAGES` ; second canal Kotlin et second `FileProvider` ; paire APK + manifeste à restaurer dans `deploy.yml` ; transfert Hosting facturé au-delà du quota | 0 € / 0 à ≈ 2 € par mois |
| B. SDK Android App Distribution par un canal Kotlin | fenêtre du SDK, connexion du testeur dans le navigateur | aucun fichier sur Hosting | SDK en bêta (16.0.0-beta21) ; son manifeste ajoute `READ_EXTERNAL_STORAGE` et `WRITE_EXTERNAL_STORAGE`, contraires à P28, et une activité exportée ; dépendances Firebase natives dans Gradle (leçon 4) | 0 € / 0 € |
| C. Lire `version.json` et renvoyer vers App Tester | message seul | aucun changement de déploiement | annonce une version absente d'App Distribution quand la publication échoue après Hosting | 0 € / 0 € |
| C′. Manifeste écrit depuis l'API App Distribution, installation par App Tester | message, puis App Tester | aucun binaire public, aucune permission | le brasseur passe encore par App Tester | 0 € / 0 € |

## Décision

Option A, choisie par l'utilisateur le 2026-11-14. L'APK signé et son manifeste
`apk_release.json` sont publiés sur Firebase Hosting à chaque nouvel APK. L'application
Android lit le manifeste au lancement, télécharge l'APK et ouvre l'installateur du système.

App Distribution reste en parallèle, publié depuis le même APK. Raisons :

- les APK installés aujourd'hui ne vérifient rien : la première version qui porte la
  vérification ne peut atteindre les brasseurs que par App Distribution ;
- App Tester reste le chemin de première installation par invitation, et le secours si la
  paire en ligne est refusée par `deploy.yml`.

Son retrait est une décision séparée de l'utilisateur, à prendre quand chaque brasseur a
installé une version qui porte la vérification (question ouverte 1).

### Arbitrages de l'utilisateur (2026-11-14)

1. Option A acceptée en connaissance de cause : APK public sur Hosting, permission
   `REQUEST_INSTALL_PACKAGES`, canal Kotlin d'installation, coût Hosting de 0 à ≈ 2 € par
   mois.
2. Un échec réseau de la vérification ne produit pas de rapport d'erreur. Seule une réponse
   reçue et illisible (corps non JSON, `version`, `build_number`, `size_bytes` ou `sha256`
   absents ou mal formés) en produit un. C'est une exception écrite à « Aucun `catch`
   silencieux ».
3. « Plus tard » ferme la fenêtre ; elle revient au lancement suivant. Rien n'est mémorisé.
4. Web : aucune vérification, aucune fenêtre, aucun lien vers l'APK.
5. Aucune vérification ni fenêtre sur l'écran du jour de brassage et les journées du
   déroulé (P2).
6. Téléchargement : une coupure de réseau (ou une annulation) ne produit pas de rapport ; la
   fenêtre affiche l'échec et « Réessayer ». Un fichier reçu faux (taille ou SHA-256 différents
   du manifeste, paquet ou `versionCode` refusés) en produit un. Seconde partie de l'exception
   à « Aucun `catch` silencieux ».
7. App Distribution reste en parallèle ; son retrait sera un ticket à part.
8. APK complet, sans découpage par ABI ; sa taille est mesurée et notée au `CHANGELOG.md`.
9. Le script de restauration fait un contrôle minimal (forme du manifeste, `PK`, taille,
   SHA-256) ; aucune fixture partagée ni ligne au tableau « Logique dupliquée ».

### Détail retenu

**Manifeste** `https://kassbeer.web.app/apk_release.json` :

```json
{"version": "0.1.40", "build_number": 41, "file": "app-release.apk",
 "size_bytes": 52428800, "sha256": "<64 chiffres hexadécimaux>", "built_at": "2026-11-14T10:00:00Z"}
```

Écrit par le job `build` au moment où l'APK est construit, jamais ailleurs. `file` vaut
toujours `app-release.apk` : l'application ne lit pas ce champ pour construire une URL.

**Client Dart**

- `app/lib/core/services/app_update_service.dart` : `check()` et `download()`. Android seul :
  `kIsWeb` ou une autre plateforme rendent `null` avant tout appel. Lecture par `dart:io`
  `HttpClient` derrière un import conditionnel (stub sur le web) : aucun paquet `http`
  ajouté. URL constantes : manifeste (avec `?t=<horodatage>`) et
  `https://kassbeer.web.app/app-release.apk`. Délai de 8 s pour le manifeste, corps lu
  jusqu'à 4 096 octets.
- **Lecture du manifeste** : `version` de forme `^\d+\.\d+\.\d+$`, `build_number` entier
  de 1 à 2 100 000 000, `size_bytes` entier de 1 à 200 000 000, `sha256` de 64 caractères
  `[0-9a-f]`. Un champ hors forme rend la réponse illisible.
- **Comparaison** : `build_number` contre `buildNumber` de `package_info_plus`. P7 garantit
  que `N` monte d'un à chaque version. Aucune comparaison de `X.Y.Z`.
- **Erreurs de `check()`** (arbitrage 2) : absence de réseau, délai, erreur de connexion ou
  de TLS (`SocketException`, `TimeoutException`, `HttpException`, `HandshakeException`), ou
  code HTTP différent de 200 : rien ne s'affiche et aucun rapport ne part. Réponse 200
  illisible : `reportError(feature: 'app_update_check', context: {'reason': …})`, puis rien
  ne s'affiche. Hosting sert `index.html` en 200 pour un fichier absent : un manifeste
  manquant passe donc par le cas illisible et produit un rapport. Aucun repli sur
  `version.json`.
- **Téléchargement** : écrit `kass-beer-update.apk` dans le dossier rendu par le canal.
  Refusé au-delà de `size_bytes` octets reçus (lecture arrêtée à `size_bytes + 1`). Taille
  finale égale à `size_bytes` et SHA-256 égal à `sha256`, sinon fichier effacé et rapport.
  Annulation lue sur un drapeau, sans exception attrapée. Une erreur réseau du téléchargement
  (mêmes exceptions que `check()`, code HTTP différent de 200) ne produit pas de rapport
  (arbitrage 6) ; un fichier faux passe par `reportError(feature: 'app_update_download')`,
  sans chemin ni contenu. `sha256` vient de
  `package:crypto`, déjà résolu en dépendance indirecte (`exchange/`) ; il est déclaré dans
  `app/pubspec.yaml` en version exacte.
- **Fenêtre** `app/lib/core/presentation/app_update_dialog.dart`, reprise de Kass'Dalle :
  étapes offre, autorisation, téléchargement (progression, « Annuler »), installation,
  échec. Offre : « Kass'Beer X.Y.Z est disponible (vous avez X.Y.Z). » et la taille, boutons
  « Plus tard » et « Mettre à jour ». Autorisation : « Autorisez Kass'Beer à installer des
  applications », bouton « Ouvrir les réglages », puis nouvelle lecture de
  `canRequestInstall` au retour. Échec : « Réessayer » et « Plus tard ». Pas de repli vers
  le navigateur.
- **Moment** : une fois par lancement, après la connexion d'un membre, depuis
  `app/lib/core/presentation/app_shell.dart`. Si la route courante est l'écran du jour
  (`/brassins/:id/jour`) ou une journée (`/brassins/:id/jour/:journee`), la fenêtre attend
  que le brasseur quitte ces routes. Aucun code appelé par ces écrans n'importe
  `app_update_service.dart`.

**Canal Kotlin `fr.kassbeer/updates`** (`MisesAJour.kt`, branché par `MainActivity.kt`)

- `updatesDir()` : crée et rend `cacheDir/updates/`.
- `canRequestInstall()` : `packageManager.canRequestPackageInstalls()` (Android 8 et plus ;
  `minSdk` 24 : sous Android 8, vrai).
- `openInstallSettings()` : `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` sur
  `package:fr.kassbeer…`.
- `installApk(expectedBuild)` : aucun chemin reçu du Dart. Lit `cacheDir/updates/
  kass-beer-update.apk`, hors du thread principal ; `getPackageArchiveInfo` doit rendre le
  `packageName` de l'application et un `longVersionCode` égal à `expectedBuild`, sinon
  refus `apk_invalid`. Puis `FileProvider.getUriForFile` sur l'autorité
  `${applicationId}.updates`, `ACTION_VIEW` de type
  `application/vnd.android.package-archive`, `FLAG_GRANT_READ_URI_PERMISSION`. Résultat
  rendu sur le thread principal. Second appel pendant un appel en cours refusé.
- Lancement neuf (`savedInstanceState == null`) : `cacheDir/updates/` est vidé, comme
  `exports/`.
- Aucun message d'erreur ne contient de chemin.

**Manifeste Android**

- `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />`.
  Elle permet de demander l'installation. Android affiche toujours son écran de
  confirmation, après l'autorisation « installer des applications inconnues » accordée par
  le brasseur à Kass'Beer.
- Second `<provider>` : sous-classe `MisesAJourFileProvider`, autorité
  `${applicationId}.updates`, `exported="false"`, `grantUriPermissions="true"`,
  `res/xml/updates_paths.xml` réduit à `<cache-path name="updates" path="updates/"/>`.
  `ExportsFileProvider` et `exports_paths.xml` d'ADR-007 restent inchangés : les deux
  dossiers ne se partagent pas une autorité.
- Aucune permission de stockage (P28 inchangé sur ce point).

**Hosting** (`firebase.json`)

```json
{
  "source": "app-release.apk",
  "headers": [
    { "key": "Content-Type", "value": "application/vnd.android.package-archive" },
    { "key": "Content-Disposition", "value": "attachment; filename=\"kass-beer.apk\"" },
    { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
  ]
},
{
  "source": "apk_release.json",
  "headers": [{ "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }]
}
```

**Déploiement** (`deploy.yml`)

- Job `plan` : lit en plus `https://kassbeer.web.app/apk_release.json` (sans jeton). Un APK
  se construit si le build `N` dépasse celui du manifeste en ligne ou celui d'App
  Distribution, ou si la version d'App Distribution a expiré, ou si le manifeste en ligne
  est illisible ou absent.
- Job `build` : après `flutter build apk --release`, copie l'APK dans
  `app/build/web/app-release.apk` et écrit `app/build/web/apk_release.json` (`jq -n`,
  version et build tirés de `app/pubspec.yaml`, `size_bytes` par `stat`, `sha256` par
  `sha256sum`). L'APK part aussi dans l'artefact `apk` pour App Distribution.
- Job `deploy`, quand aucun APK n'est construit : nouveau script
  `scripts/garder-apk-en-ligne.sh`, lancé avant l'authentification Google. Il télécharge la
  paire en ligne et la recopie dans `app/build/web` si elle est cohérente : manifeste
  conforme aux formes ci-dessus, APK qui commence par `PK`, taille égale à `size_bytes`,
  SHA-256 égal à `sha256`. Paire absente : rien n'est recopié, avertissement (l'application
  ne propose rien). APK seul : recopié sans manifeste, avertissement. Manifeste seul ou
  paire incohérente : échec du déploiement.
- Ordre du job `deploy` inchangé : Hosting (avec la paire), règles et index, Functions, puis
  App Distribution. Un échec d'App Distribution après Hosting laisse l'application à jour
  par Hosting ; App Tester a une version de retard.
- Aucun rôle ajouté au compte `github-deploy`.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : écriture de la paire dans le job `build`,
   restauration dans le job `deploy` (bash, `curl`, `jq`, `sha256sum`) ; vérification,
   téléchargement et contrôle du SHA-256 dans l'APK, en Dart ; contrôle du paquet et
   installation en Kotlin. Rien sur le web.
2. **Ce qui existera en double** : la comparaison de builds existe en bash (`plan`) et en
   Dart (client). La lecture du manifeste existe en bash (`garder-apk-en-ligne.sh`, contrôle
   minimal) et en Dart. Arbitrage 9 : aucune fixture partagée, aucune ligne au tableau
   « Logique dupliquée » ; le script refuse une paire incohérente et le client refuse un
   fichier faux, chacun de son côté.
3. **Ce qui pèse au démarrage** : un `GET` de moins de 4 Ko après le premier écran, sans
   attente. `dart:io` est déjà chargé sur Android. Rien sur le web : l'import conditionnel
   n'y charge que le stub. `package:crypto` ne se charge qu'à la fin d'un téléchargement.
4. **Compilation de chaque cible** : `flutter build apk --release` (manifeste, provider,
   Kotlin) et `flutter build web --release` (stub). Le job « Android — compilation » se
   lance déjà sur un diff de `app/android/` et de `app/pubspec.yaml`.
5. **Qui voit quoi** : l'APK est téléchargeable par toute personne qui connaît l'URL. Il ne
   contient aucun secret : la configuration Firebase y est la même que celle du web, déjà
   publique, et le code est dans le dépôt public (ADR-002). Sans invitation dans
   `members/`, l'APK ne donne accès à aucune donnée (P11). Intégrité : HTTPS ; taille et
   SHA-256 contrôlés contre le manifeste, ce qui écarte un fichier tronqué ou une paire
   désaccordée, pas une compromission de Hosting ; paquet et `versionCode` contrôlés avant
   l'installation ; Android refuse une mise à jour signée par une autre clé que la clé de
   release (P8). La requête ne porte ni e-mail ni uid.
6. **Ce qui coûte à l'usage, plafond** : transfert Hosting d'un APK par brasseur et par
   mise à jour installée. Hypothèse : 10 brasseurs, 40 versions par mois, APK de 50 Mo
   (taille non mesurée) : 20 Go par mois, soit 10 Go au-delà du quota gratuit, facturés
   0,15 $ le Go : ≈ 1,5 $ par mois (tarifs à vérifier). Stockage : chaque version de
   Hosting garde son APK ; la rétention des versions est à régler dans la console. Aucun
   plafond technique possible sur Hosting : un téléchargement répété de l'APK par un tiers
   est facturé au même tarif (100 Go = 15 $, à vérifier). L'alerte budgétaire à 5 €
   signale l'écart, elle ne l'arrête pas. Risque accepté par l'arbitrage 1.
7. **Exposition** : un fichier public de plus sur Hosting. Aucune fonction, aucune règle
   Firestore. `REQUEST_INSTALL_PACKAGES` n'est utilisée que sur un fichier vérifié de
   `cacheDir/updates/`.
8. **Exploitation** : rien à maintenir hors de `deploy.yml` et du script de restauration.
   Une mise à jour atteint le brasseur à son prochain lancement connecté. Si la paire en
   ligne est refusée, le déploiement s'arrête ; App Tester reste le secours.
9. **Coût de sortie** : retirer App Distribution supprime une étape et une lecture d'API.
   Revenir à App Distribution seul retire le service, la fenêtre, le canal, le provider, la
   permission et la paire.

## Conséquences

- Fichiers touchés : voir « Fichiers à toucher » dans le livrable de l'architecte.
- `CLAUDE.md` : ligne « Hébergement » de « Le projet », troisième exception à « Aucun
  `catch` silencieux » (arbitrages 2 et 6), P1, P17, P28 réécrits, P51 et P52 ajoutés.
- `exigences-techniques.md` : manifeste, paire, ordre des jobs, canal `fr.kassbeer/updates`,
  réglages hors dépôt. `exigences-fonctionnelles.md` : fenêtre « Nouvelle version » sur
  Android.
- Réglages hors dépôt : rétention des versions de Hosting ; autorisation « installer des
  applications inconnues » accordée par chaque brasseur à Kass'Beer à la première mise à
  jour.

## Sources

- Code lu le 2026-11-14 : `/home/user/KassBeer/.github/workflows/deploy.yml`,
  `/home/user/KassBeer/firebase.json`, `/home/user/KassBeer/app/pubspec.yaml`,
  `/home/user/KassBeer/app/android/app/src/main/AndroidManifest.xml`,
  `/home/user/KassBeer/app/android/app/src/main/kotlin/fr/kassbeer/kass_beer/MainActivity.kt`,
  `/home/user/KassBeer/app/android/app/src/main/kotlin/fr/kassbeer/kass_beer/EchangeFichiers.kt`,
  `/home/user/KassDalle/kass_dalle/lib/core/services/app_update_service.dart`,
  `/home/user/KassDalle/kass_dalle/lib/core/services/app_installer.dart`,
  `/home/user/KassDalle/kass_dalle/lib/core/presentation/app_update_dialog.dart`,
  `/home/user/KassDalle/kass_dalle/android/app/src/main/kotlin/dev/kassbi/kass_dalle/MainActivity.kt`,
  `/home/user/KassDalle/kass_dalle/android/app/src/main/AndroidManifest.xml`,
  `/home/user/KassDalle/kass_dalle/android/app/src/main/res/xml/file_paths.xml`,
  `/home/user/KassDalle/kass_dalle/firebase.json`,
  `/home/user/KassDalle/.github/scripts/keep-online-apk.sh`,
  `/home/user/KassDalle/.github/scripts/build-apk.sh`,
  `/home/user/KassDalle/documentation/TechnicalRequirements.md`.
- SDK Android App Distribution (option B) : `firebase/firebase-android-sdk`, branche
  `main`, `firebase-appdistribution/gradle.properties` (`latestReleasedVersion=16.0.0-beta21`),
  `CHANGELOG.md` et `src/main/AndroidManifest.xml`, lus le 2026-11-14 sur
  https://github.com/firebase/firebase-android-sdk.
- Tarifs Hosting (10 Go stockés et 10 Go de transfert par mois sans frais, puis 0,026 $ le
  Go stocké et 0,15 $ le Go transféré) : résultat de recherche sur
  https://firebase.google.cn/docs/hosting/usage-quotas-pricing, le 2026-11-14 ;
  firebase.google.com n'était pas joignable depuis la session : à vérifier sur
  https://firebase.google.com/pricing.
- Expiration d'une version App Distribution à 150 jours : commentaire du job `plan` de
  `deploy.yml` ; à vérifier sur la documentation Firebase.
