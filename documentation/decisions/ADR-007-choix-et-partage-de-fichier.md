# ADR-007 — Choix et partage d'un fichier : canal de plateforme sur Android, `package:web` sur le web

- **Statut** : accepté le 2026-11-10 (option B, avec « Enregistrer » ; évolutions du réseau acceptées)
- **Date** : 2026-11-10
- **Remplace** : — (complète ADR-005, livraison L2 ; reprend le modèle d'ADR-003)

## Contexte

La livraison L2 d'ADR-005 ouvre « Recettes › Importer » à tout brasseur (décision 11 : 50 recettes
et 2 Mio au plus par fichier, portés à 500 recettes et 10 Mo le 2026-11-10) et ajoute « Exporter » sur la fiche d'une recette. Il faut :

- choisir un fichier BeerXML ou BeerJSON sur l'appareil (Téléchargements, Drive, autres
  fournisseurs du système) et le refuser avant lecture s'il dépasse 10 Mo (cadrage L2, cas
  limites ; P9 réécrit par ADR-005) ;
- sur le web, télécharger le fichier exporté ; sur Android, l'envoyer par la feuille de partage
  du système (cadrage L2, question 6, réponse recommandée A).

Admin › Import (v0.6) charge aussi son fichier « par un sélecteur » (P12) : le même moyen lui
servira.

Ni le SDK Flutter ni `app/pubspec.yaml` ne fournissent ce moyen sur Android. Sur le web,
`package:web` 1.1.1, déjà déclaré pour le bip d'ADR-003, donne `<input type="file">`, `Blob` et
le lien de téléchargement.

État du dépôt relevé le 2026-11-10 :

- `app/android/settings.gradle.kts` : AGP 9.0.1, Kotlin 2.3.20 ; `gradle-wrapper.properties` :
  Gradle 9.1.0 ; `gradle.properties` : `android.newDsl=false`, `android.builtInKotlin=false`.
- `app/android/app/build.gradle.kts` : `minSdk = flutter.minSdkVersion` (24, ADR-003), Java 17,
  aucun bloc `dependencies`.
- `MainActivity.kt` porte le canal `fr.kassbeer/alert` (ADR-003, environ 70 lignes).
- `app/pubspec.lock` : `win32` 6.4.0, `ffi` 2.2.0, `web` 1.1.1, Dart ≥ 3.12, Flutter ≥ 3.44.
  `path_provider`, `jni`, `cross_file` et `uuid` en sont absents.

## Options

Effort estimé, non mesuré. Coût de 0 € à l'arrêt et à l'usage pour toutes les options : tout se
passe sur l'appareil.

| Option | Pour | Contre |
|---|---|---|
| D1. Ne pas le faire | aucune dépendance, aucun code | R1, R5 et R7 du cadrage non tenus ; L2 sans écran ; Admin › Import (v0.6) reste sans sélecteur |
| D2. Web seul en L2 : `package:web`, Android affiche « Import et export depuis le site » | 0,3 j ; aucun code natif ; aucune compilation Android touchée | l'APK n'importe ni n'exporte ; le canal Android reste à faire avant v0.6 |
| A. `file_picker` 13.3.3 + `share_plus` 13.3.1 | 0,5 j ; deux appels de bibliothèque | environ 24 paquets ajoutés à `pubspec.lock`, dont `jni`, compilé en C par CMake et le NDK, une première dans l'APK ; `android_file_picker` 2.1.5 déclare son propre AGP 8.5.2 et Kotlin 1.8.22, en « contournement temporaire » d'AGP 9 avec `newDsl=false`, la configuration du projet ; `file_picker` a publié 12 versions du 2026-08-26 au 2026-11-10, dont une majeure ; la copie du fichier entier dans le cache précède le contrôle de taille ; deux paquets de plus contraints par `win32` 6 ; `cross_file` ^0.3.5 alors que 0.4.0 existe ; sur le web, `share_plus` ouvre `navigator.share` avant le téléchargement |
| C. `file_selector` 1.1.0 (équipe Flutter) pour le choix, canal maison pour le partage | 1 j ; paquet officiel ; aucune entrée de manifeste ; `minSdk` 24 | `file_selector_android` 0.5.2+11 lit le fichier entier en mémoire avant tout contrôle de taille, puis le copie dans le cache ; une taille inconnue du fournisseur rend `null`, comme une annulation ; exige Dart ≥ 3.12 et Flutter ≥ 3.44 (sa prochaine version peut exiger un Dart que `pubspec.lock` n'a pas, comme `xml` 7.1.0) ; neuf paquets ajoutés ; du Kotlin maison quand même |
| B. Canal Kotlin maison + `package:web` (recommandée) | aucune dépendance Dart ; taille contrôlée avant lecture et lecture bornée à 10 Mo + 1 octet ; même modèle qu'ADR-003 ; testable par `TestDefaultBinaryMessenger` (P17) | 1 à 1,5 j ; 150 à 200 lignes de Kotlin couvertes par la compilation et un essai sur téléphone ; un `FileProvider` à déclarer ; `androidx.core` déclaré dans `app/build.gradle.kts` |

## Décision

Option B. Elle tient la borne de 10 Mo avant lecture, n'ajoute aucun paquet Dart ni aucune
compilation native, et suit le canal déjà en place pour l'alerte de minuteur.

### Côté Dart

- `app/lib/core/fichiers/` : une interface `EchangeFichiers` avec `choisir({required int
  maxOctets})`, qui rend `null` sur une annulation ou `{nom, octets}`, et `partager({nom,
  typeMime, octets})`. Une implémentation Android (canal), une web (`package:web`), un stub
  pour l'import conditionnel (`if (dart.library.js_interop)`, comme `bip_web.dart`). Fournie
  par Riverpod, injectée dans les écrans d'import et d'export, puis dans Admin › Import.
- Garde `kIsWeb` avant tout appel du canal. Chaque `catch` appelle `reportError` avec
  `exchange.pick` ou `exchange.share`, et un `context` limité au code d'erreur et à la taille :
  ni contenu, ni nom de fichier (P13).
- Le nom du fichier exporté est nettoyé en Dart (E2 du cadrage) avant l'appel.

### Côté Android

Un fichier `EchangeFichiers.kt` dans `fr.kassbeer.kass_beer`, branché par
`MainActivity.configureFlutterEngine`, canal `fr.kassbeer/files` :

- **`pickDocument`** (`maxBytes`) : `ACTION_OPEN_DOCUMENT`, `CATEGORY_OPENABLE`, type `*/*`. Le
  format se lit au contenu (I3 du cadrage) : aucun filtre MIME, qui griserait un fichier `.xml`
  que Drive déclare `application/octet-stream`. Au retour, `OpenableColumns.SIZE` supérieur à
  `maxBytes` rend `TOO_LARGE` sans ouvrir le flux. La lecture se fait hors du thread principal
  (Drive peut télécharger le fichier à l'ouverture du flux), bornée à `maxBytes + 1` octets ; un
  dépassement rend `TOO_LARGE` quand le fournisseur ne donne pas la taille. Le résultat est
  rendu sur le thread principal. Un second appel pendant un choix en cours rend
  `ALREADY_ACTIVE`. Aucune application de choix : `NO_PICKER`. Code de requête propre au projet,
  déclaré une fois.
- **`shareFile`** (`name`, `mimeType`, `bytes`) : vide `cacheDir/exports/`, y écrit le fichier,
  rend `INVALID_NAME` pour un nom vide, de plus de 120 caractères, avec `/`, `\` ou `..`, ou dont
  le chemin canonique sort de `exports/`. Puis `FileProvider.getUriForFile`, `ACTION_SEND` avec
  `EXTRA_STREAM`, `ClipData`, `FLAG_GRANT_READ_URI_PERMISSION`, dans `Intent.createChooser`.
- **Manifeste** : un `<provider>` sous-classe de `FileProvider` (la documentation déconseille
  la classe nue), `android:authorities="${applicationId}.exports"`, `exported="false"`,
  `grantUriPermissions="true"`, et `res/xml/exports_paths.xml` réduit à
  `<cache-path name="exports" path="exports/"/>`. Aucune permission de stockage
  (`READ_EXTERNAL_STORAGE`, `READ_MEDIA_*`, `MANAGE_EXTERNAL_STORAGE`) : le sélecteur du système
  donne l'accès au seul document choisi.
- **`app/build.gradle.kts`** : `implementation("androidx.core:core:<version>")`, à une version
  qui ne dépasse pas celle que le graphe résout déjà (`./gradlew :app:dependencies
  --configuration releaseRuntimeClasspath`, à vérifier). Les greffons Firebase la tirent
  déjà ; la déclarer ne doit ajouter aucun code à l'APK.

L'utilisateur veut aussi « Enregistrer » (décision du 2026-11-10) : la méthode `saveDocument`
(`ACTION_CREATE_DOCUMENT`) s'ajoute au même canal, environ 30 lignes. Le fichier écrit dans
`cacheDir/exports/` est effacé au lancement suivant de l'application, car il porte le nom de
l'auteur. La borne de lecture vaut 10 Mo (ADR-005, amendements de L2).

### Côté web

- Choix : un `HTMLInputElement` de type `file`, créé et cliqué dans le gestionnaire du tap (le
  navigateur exige une action de l'utilisateur). `File.size` supérieur à la borne refuse le
  fichier avant `arrayBuffer()`. L'événement `cancel` rend `null` (prise en charge par les
  navigateurs à vérifier).
- Téléchargement : `Blob`, `URL.createObjectURL`, lien `download`, clic, `revokeObjectURL`.
  Rien ne part vers un serveur (S1).

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : sur l'appareil. Le choix, la lecture bornée et le
   partage en Kotlin sur Android ; dans le navigateur sur le web ; l'analyse du fichier dans
   `exchange/`, en Dart, sur les deux.
2. **Ce qui existera en double** : le choix et le téléchargement, une implémentation Android et
   une web. Ce sont deux API de plateforme, sans logique métier. La borne de 10 Mo vient du Dart
   (`maxBytes`) : aucune constante en Kotlin. Les noms du canal et des méthodes existent en Dart
   et en Kotlin (P17).
3. **Ce qui pèse au démarrage** : rien. Le canal ne fait rien avant le premier appel. Le code web
   compile dans `main.dart.js` (une centaine de lignes) et ne charge rien. Avec l'option A, trois
   greffons Android et deux greffons web s'enregistreraient au lancement.
4. **Compilation de chaque cible** : `flutter build web --release` et `flutter build apk
   --release`. Le job « Android — compilation » de `ci.yml` se déclenche sur `app/android/`, donc
   sur le Kotlin, le manifeste et `build.gradle.kts`. L'import conditionnel isole `package:web` de
   la compilation Android. Aucun CMake, aucun NDK sollicité.
5. **Qui voit quoi** : le fichier choisi reste sur l'appareil ; seules les recettes créées
   partent vers Firestore, sous `owner_uid` de l'importateur. Le fichier exporté contient
   `author` ou `owner_name` (E6 du cadrage) et part vers l'application que choisit l'utilisateur.
   Il reste dans `cacheDir/exports/`, lisible par l'application seule, jusqu'à l'export suivant
   ou au nettoyage du cache par le système. Le `FileProvider` n'expose que ce dossier.
6. **Ce qui coûte à l'usage, plafond** : rien, aucun appel facturé. Un import coûte au plus
   50 écritures Firestore (ADR-005).
7. **Exposition** : inchangée. Aucun point d'accès ajouté. Le `FileProvider` n'est pas exporté
   et n'accorde qu'une lecture temporaire de l'URI partagée.
8. **Exploitation, sauvegarde, mise à jour** : 150 à 200 lignes de Kotlin à maintenir, sans
   version de paquet à suivre. Le canal arrive avec une mise à jour de l'APK par App Distribution.
   Rien à sauvegarder.
9. **Coût de sortie** : faible. Passer à `file_picker` ou `share_plus` remplace une
   implémentation de `EchangeFichiers` et retire `EchangeFichiers.kt`, le `<provider>` et la
   ligne `androidx.core`. Les écrans ne changent pas.

## Conséquences

Plus simple : aucun paquet à faire monter avec Flutter ou `win32`, aucune bibliothèque native
dans l'APK, une borne de taille tenue avant lecture sur les deux cibles. Admin › Import (v0.6) et
un futur export d'Admin réutilisent `EchangeFichiers`.

Plus difficile : le Kotlin n'est couvert que par la compilation et un essai sur téléphone. Les
tests Dart simulent le canal : choix annulé, fichier rendu, `TOO_LARGE`, `ALREADY_ACTIVE`,
`NO_PICKER`, `INVALID_NAME`, échec de lecture. Le code web n'est pas exécuté par `flutter test`
sur la VM ; il se vérifie à la main dans Chrome.

À vérifier sur un téléphone avant la livraison : fichier pris dans Téléchargements et dans
Drive, fichier de plus de 10 Mo refusé sans attente, partage vers Gmail et Drive, choix annulé.

Le dossier `app/lib/core/fichiers/` entre dans « Structure » de `CLAUDE.md`. P17 s'étend, et P28
s'ajoute (évolutions du réseau proposées avec cet ADR).

## Évolutions du réseau acceptées

Acceptées par l'utilisateur le 2026-11-10, appliquées à `CLAUDE.md` avec L2b (v0.1.20) :
extension de P17 (appel qui lit un fichier ou attend une activité hors du thread principal, code
de requête unique, second appel refusé), P28 nouveau pour `securite` (texte dans le tableau de
`CLAUDE.md`), lignes « Le projet » et « Structure ».

## Sources

Consultées le 2026-11-10.

- API pub.dev, versions, dates et dépendances : https://pub.dev/api/packages/file_picker,
  `android_file_picker`, `file_picker_web`, `file_picker_platform_interface`,
  `windows_file_picker`, `file_picker_linux`, `file_picker_darwin`, `share_plus`,
  `share_plus_platform_interface`, `path_provider`, `path_provider_android`, `jni`,
  `jni_flutter`, `cross_file`, `cross_file_web`, `file_selector`, `file_selector_android`,
  `file_selector_web`, `file_selector_platform_interface`, `url_launcher_web`, `uuid`, `dbus`.
- Archives pub.dev lues : `android_file_picker` 2.1.5 (`android/build.gradle.kts`,
  `AndroidManifest.xml`, `FileUtils.kt`, `CHANGELOG.md` 1.0.4 et 2.0.0) ; `share_plus` 13.3.1
  (`android/build.gradle.kts`, `AndroidManifest.xml`, `lib/src/share_plus_web.dart`,
  `CHANGELOG.md`) ; `share_plus_platform_interface` 7.2.0
  (`lib/method_channel/method_channel_share.dart`) ; `jni` 1.1.2 (`android/build.gradle`) ;
  `file_selector_android` 0.5.2+11 (`build.gradle.kts`, `FileSelectorApiImpl.java`).
- Migration AGP 9 de Flutter citée par `android_file_picker` :
  https://github.com/flutter/flutter/issues/180137 (non lue).
- `FileProvider`, artefact `androidx.core:core`, sous-classe recommandée :
  https://developer.android.com/reference/androidx/core/content/FileProvider
- Décompte des paquets ajoutés (environ 24 pour A, 9 pour C) : fait à la main sur les
  `pubspec.yaml` de pub.dev et `app/pubspec.lock`, à confirmer par `flutter pub get`.
- Prise en charge de l'événement `cancel` de `<input type="file">` : à vérifier (MDN non lu).
- Durées : estimations, non mesurées.
