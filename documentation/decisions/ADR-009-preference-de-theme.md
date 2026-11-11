# ADR-009 — Préférence de thème gardée sur l'appareil, par un canal maison

- **Statut** : accepté (2026-11-11 : préférence sur l'appareil, option C)
- **Date** : 2026-11-11
- **Remplace** : — (suit le principe d'ADR-007, « aucun greffon » quand une API de plateforme
  suffit ; ajoute un canal au modèle d'ADR-003)

## Contexte

Le ticket #25 demande un choix de thème Clair / Sombre / Comme l'appareil dans une page
« Préférences ». `app/lib/app.dart` fixe aujourd'hui `themeMode: ThemeMode.system` (lignes 31,
56 et 84). Le choix doit être connu avant `runApp` dans `app/lib/main.dart`, sinon le premier
écran s'affiche dans le thème du système puis change.

Le moyen proposé par l'ux-designer, `shared_preferences`, ajoute une dépendance à code natif.
Elle entre dans la liste « Changement lourd » de `CLAUDE.md` : elle change la compilation de la
cible Android et la taille de l'APK.

État relevé le 2026-11-11 :

- `app/pubspec.lock` ne contient ni `shared_preferences*` ni `path_provider*`, ni
  `xdg_directories`, ni `platform`.
- Kass'Dalle (`kass_dalle/pubspec.lock`) résout `shared_preferences` 2.5.5,
  `shared_preferences_android` 2.4.23, `shared_preferences_web` 2.4.3, et avec eux
  `path_provider_linux`, `path_provider_windows`, `path_provider_platform_interface`,
  `xdg_directories` et `platform`, sous les mêmes SDK que Kass'Beer (Dart ≥ 3.12, Flutter ≥ 3.44).
- `shared_preferences_android` (branche `main` du dépôt `flutter/packages`) déclare
  `androidx.datastore:datastore` 1.2.1, `datastore-preferences` 1.2.1 et
  `androidx.preference:preference` 1.2.1, et son propre plugin Gradle Kotlin 2.3.0. Le projet
  est en AGP 9.0.1, Kotlin 2.3.20, `android.newDsl=false` (ADR-007).
- `MainActivity.kt` porte déjà le canal `fr.kassbeer/alert` (ADR-003) ; `package:web` 1.1.1 est
  déjà déclaré (ADR-003, ADR-007).

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun code | ticket #25 non traité ; le thème reste celui du système | 0 € / 0 € |
| F. Document `users/{uid}/preferences/app` | suit le compte d'un appareil à l'autre ; aucun code natif | thème connu après connexion et lecture du cache : changement visible à chaque démarrage, et sur l'écran de connexion ; règle et tests des cinq profils (P4, P5) ; une écriture par changement | 0 € / quelques écritures |
| S. `shared_preferences` 2.5.5 figé | 0,2 j ; paquet de l'équipe Flutter ; déjà compilé dans Kass'Dalle | 12 paquets ajoutés à `pubspec.lock` ; graphe Gradle Android étendu (DataStore, `androidx.preference` et ses dépendances), taille de l'APK à mesurer ; un plugin Gradle Kotlin 2.3.0 à côté du Kotlin 2.3.20 du projet ; une version de plus à suivre à chaque montée de Flutter | 0 € / 0 € |
| C. Canal `fr.kassbeer/prefs` + `localStorage` par `package:web` (recommandée) | aucune dépendance Dart ni Gradle ; `android.content.SharedPreferences` fait partie du système ; même modèle que `fr.kassbeer/alert` ; testable par `TestDefaultBinaryMessenger` (P17) | 0,5 j ; environ 30 lignes de Kotlin et 20 de Dart web à maintenir ; essai sur téléphone | 0 € / 0 € |

## Décision

Option C. Elle n'ajoute aucun paquet ni aucune dépendance Gradle pour une seule valeur de trois
états, et suit le canal déjà en place.

- **Dart** : `app/lib/core/preferences/` avec une interface `PreferencesAppareil`
  (`lireValeurTheme()`, qui rend la valeur enregistrée ou `null` et lève sur un échec, et
  `ecrireTheme(ThemeMode)`, avec le type `ThemeMode` de Flutter), une implémentation de la
  plateforme : canal sur Android, `window.localStorage` (clé `kassbeer.theme`) sur le web, et un
  stub, par import conditionnel (`if (dart.library.js_interop)`), comme `bip_web.dart`. La
  fonction `lireTheme` convertit la valeur et rend un `LectureTheme` (thème et erreur à
  rapporter) ; elle ne lève pas. Fournie par Riverpod.
- **Android** : méthodes `getTheme` et `setTheme` sur `fr.kassbeer/prefs`, fichier
  `getSharedPreferences("kassbeer_prefs", MODE_PRIVATE)`, `apply()` pour l'écriture.
- **Valeurs** : `light`, `dark`, `system`, rien d'autre. Une valeur absente vaut `system` (choix
  par défaut de l'écran, pas une donnée métier). Une valeur inconnue vaut `system` et part en
  rapport d'erreur.
- **Démarrage** : la lecture se lance en parallèle de `Firebase.initializeApp`. Son erreur est
  gardée puis remise à `ErrorReportService` une fois construit, comme `versionError` dans
  `main.dart`. Le thème vaut alors `system`.

## Réponses aux questions de l'architecte

1. Où tourne chaque morceau de code : sur l'appareil. Kotlin sur Android, `localStorage` dans
   le navigateur.
2. Ce qui existera en double : la lecture et l'écriture d'une chaîne, en Kotlin et en Dart web.
   Aucune logique métier. Les noms du canal, des méthodes et des trois valeurs existent en Dart
   et en Kotlin (P17).
3. Ce qui pèse au démarrage : un appel de canal avant `runApp`, lu en parallèle de Firebase.
   Aucun greffon enregistré en plus.
4. Compilation de chaque cible : `flutter build apk --release` (job « Android — compilation »,
   déclenché par `app/android/`) et `flutter build web --release`. Aucune dépendance Gradle
   ajoutée.
5. Qui voit quoi : la valeur reste sur l'appareil, hors Firestore. Ce n'est pas une donnée
   personnelle. Sur un ordinateur partagé, le choix vaut pour tous les comptes du navigateur.
6. Ce qui coûte à l'usage, plafond : rien.
7. Exposition : inchangée. `localStorage` est modifiable par l'utilisateur du navigateur : la
   valeur lue est une entrée non fiable, réduite à trois valeurs.
8. Exploitation, sauvegarde, mise à jour : environ 50 lignes à maintenir, aucune version de
   paquet à suivre. Le choix se perd à la désinstallation ou au nettoyage du navigateur ; rien
   à sauvegarder. Arrive par une mise à jour de l'APK et par Hosting.
9. Coût de sortie : faible. Passer à `shared_preferences` remplace les deux implémentations de
   `PreferencesAppareil` et retire les méthodes du canal ; les écrans ne changent pas.

## Conséquences

- L'écran de lancement natif Android suit `values-night/` (thème du système) : avec « Clair »
  choisi sur un téléphone en sombre, il reste sombre jusqu'à la première image Flutter. Le fond
  de `web/index.html` a la même limite.
- Une seconde préférence d'appareil réutilise ce canal (`getString` et `setString` génériques à
  envisager alors, pas avant).
- Une préférence qui doit suivre le compte d'un appareil à l'autre relève de l'option F et d'un
  nouvel ADR.
- P17 s'applique au canal ; P2 n'est pas touché (le jour de brassage ne lit pas la préférence
  par le réseau).

## Sources

- `shared_preferences_android`, `android/build.gradle.kts`, branche `main` de
  `github.com/flutter/packages`, consulté le 2026-11-11 (DataStore 1.2.1, `androidx.preference`
  1.2.1, Kotlin 2.3.0, `minSdk` 24). La version 2.4.23 peut différer : à vérifier par
  `./gradlew :app:dependencies --configuration releaseRuntimeClasspath`.
- `kass_dalle/pubspec.lock` (dépôt Kass'Dalle local), lu le 2026-11-11.
