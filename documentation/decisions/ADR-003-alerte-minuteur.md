# ADR-003 — Alerte de fin de minuteur et dépendances du jour de brassage

- **Statut** : accepté le 2026-11-08, décision de l'utilisateur
- **Date** : 2026-11-08
- **Remplace** : — (précise ADR-001, arbitrage 9, sans le modifier)

## Contexte

L'incrément v0.3 livre l'écran du jour de brassage. À la fin d'un minuteur, écran du jour
ouvert, l'utilisateur veut une vibration et un bip. Écran verrouillé, rien ne se déclenche :
l'alarme écran verrouillé reste après la v1 (ADR-001, arbitrage 9), et l'écran est maintenu
allumé.

Le SDK Flutter ne fournit pas ce besoin (documentation lue le 2026-11-08) :

- `SystemSoundType.alert` n'existe que sur desktop. Il est ignoré sur Android, sur iOS et
  sur le web. Sur Android, il reste `click`, le son d'une touche.
- `HapticFeedback.vibrate` appelle `HapticFeedbackConstants.LONG_PRESS` sur Android : une
  impulsion courte. Sur le web, il ne fait rien.

L'alerte doit marcher sans réseau (`CLAUDE.md`, « Le jour de brassage marche sans réseau »).
L'APK compile avec AGP 9.0.1 (`app/android/settings.gradle.kts`) et `minSdk` vaut 24
(`flutter.minSdkVersion`, `FlutterExtension.kt` de Flutter 3.44.6).

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer : `HapticFeedback` seul | aucun code natif | pas de bip ; impulsion courte ; rien sur le web | 0 € / 0 € |
| A. `flutter_ringtone_player` 4.0.0+4 (2025-02-21) | son du système en un appel | aucune implémentation web ; pas de version stable depuis 21 mois ; `build.gradle` avec AGP 8.1.3, `compileSdkVersion 33`, `lintOptions` et Java 1.8, compilation sous AGP 9.0.1 non vérifiée ; tire `path_provider` puis `jni` et `jni_flutter` | 0 € / 0 € |
| B. `audioplayers` 6.8.1 (2026-06-27) + fichier son embarqué | paquet suivi, Android et web | six sous-paquets, plus `path_provider`, `jni`, `http`, `uuid`, `file`, `synchronized` ; fichier son à livrer ; sur le web, le fichier se charge au premier `play` et échoue dans un onglet hors ligne sans préchargement | 0 € / 0 € |
| C. Canal Kotlin + Web Audio (retenu) | aucune dépendance ; aucun fichier ; aucune requête réseau ; volume et vibration maîtrisés | code natif au projet, testé côté Dart seulement ; pas de vibration sur le web | 0 € / 0 € |

## Décision

Option C. Elle n'ajoute aucune dépendance, compile sur les deux cibles et ne lit rien sur
le réseau.

Sur Android, `MainActivity.kt` expose `MethodChannel('fr.kassbeer/alert')` :

- **Son** : `RingtoneManager.getDefaultUri(TYPE_NOTIFICATION)`, joué par `Ringtone` avec
  `AudioAttributes` en `USAGE_ALARM`. Le bip sonne en mode silencieux, au volume de l'alarme.
- **Vibration** : `Vibrator`, environ une seconde, avec la permission
  `android.permission.VIBRATE`. `VibrationEffect` existe à partir de l'API 26 ; les API 24
  et 25 passent par `Vibrator.vibrate(long)`.

Sur le web, un oscillateur Web Audio (`package:web`) joue un bip, sans URL ni fichier.
L'`AudioContext` se crée sur un tap de l'utilisateur, à cause des règles de lecture
automatique des navigateurs. Le web ne vibre pas.

Arbitrages de l'utilisateur, rapportés par la session principale le 2026-11-08 : le bip
sonne même en mode silencieux, au volume de l'alarme, et la vibration est une vraie
vibration d'environ une seconde.

Dépendances de l'incrément :

- `wakelock_plus` 1.8.2 avec `package_info_plus` ^10.2.2, montés dans la même commande. La
  version 1.3.3 citée par ADR-001 exige `package_info_plus` <9.0.0 et ne se résout pas avec
  la version 9.0.1 de `app/pubspec.lock`. Repli si le résolveur refuse `win32` 6 :
  `wakelock_plus` 1.5.2, sans autre montée.
- `flutter_localizations` (paquet du SDK), locale `fr`, sur les trois `MaterialApp` de
  `app/lib/app.dart`.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : sur l'appareil. Le son et la vibration Android
   en Kotlin, le bip web dans le navigateur, le déclenchement en Dart.
2. **Ce qui existera en double** : le bip, une implémentation Android et une web. Ce sont
   deux API de plateforme distinctes, sans logique métier commune. Le nom du canal et de la
   méthode existe en Dart et en Kotlin (P17).
3. **Ce qui pèse au démarrage** : le canal ne fait rien avant le premier appel.
   `wakelock_plus` s'enregistre au lancement sans réseau ni authentification ; sur le web,
   `no_sleep.js` (13 669 octets) se charge au premier `toggle`. `flutter_localizations` se
   charge sans réseau au premier `build` et initialise les tables de dates de toutes les
   langues. Toutes les langues restent compilées : 2,3 Mo de sources Dart dans le SDK, surcoût
   de `main.dart.js` et de l'APK à mesurer.
4. **Compilation de chaque cible** : `flutter build web` et `flutter build apk`. Le job
   « Android — compilation » de `ci.yml` se déclenche sur `app/android/`, donc sur le code
   Kotlin. L'import conditionnel Dart isole `package:web` de la compilation Android.
5. **Qui voit quoi** : aucune donnée n'est lue ni envoyée. La permission `VIBRATE` ne donne
   accès à aucune donnée de l'utilisateur.
6. **Ce qui coûte à l'usage, plafond** : rien, aucun appel facturé.
7. **Exposition** : inchangée. Aucune requête réseau ajoutée.
8. **Exploitation, sauvegarde, mise à jour** : environ 70 lignes de Kotlin à maintenir au
   projet. La permission ajoutée arrive avec une mise à jour de l'APK par App Distribution.
   Rien à sauvegarder.
9. **Coût de sortie** : faible. Le canal se remplace par un paquet en changeant une classe
   côté Dart et en retirant le code de `MainActivity.kt`.

## Conséquences

Plus simple : aucun paquet audio à faire monter avec Flutter, aucun fichier son à livrer,
aucune bibliothèque `jni` ajoutée à l'APK.

Plus difficile : le Kotlin n'est couvert que par la compilation, et le comportement se
vérifie sur un téléphone. Les tests Dart simulent le canal.

À vérifier sur un téléphone avant la livraison : le bip et la vibration en mode silencieux,
et le comportement en mode « Ne pas déranger ».

Le verrou d'écran se prend à l'ouverture de l'écran du jour. Sur le web, `no_sleep.js` se
charge à ce moment-là ; dans un onglet déjà hors ligne, le chargement échoue et l'erreur est
journalisée, une seule fois par session.

Le commentaire de `app/pubspec.yaml` qui cite `package_info_plus` (^9.0.0) change avec la
montée, et chaque paquet modifié dans `pubspec.lock` est nommé au `CHANGELOG.md` (P6).

Contrôles nés de cette décision, dans `CLAUDE.md` : P2 étendu (le son et la vibration de fin
de minuteur ne chargent rien par le réseau, et le verrou d'écran est pris à l'ouverture de
l'écran du jour) et P17 (canal de plateforme : noms identiques en Dart et en Kotlin, garde
`kIsWeb`, `catch` qui appelle `reportError`, test avec `TestDefaultBinaryMessenger`, APK
compilé).

## Sources

Consultées le 2026-11-08.

- Versions, dates de publication et contraintes de dépendances, API pub.dev :
  https://pub.dev/api/packages/wakelock_plus, https://pub.dev/api/packages/package_info_plus,
  https://pub.dev/api/packages/flutter_ringtone_player,
  https://pub.dev/api/packages/audioplayers,
  https://pub.dev/api/packages/path_provider_android
- Contenu des archives pub.dev de `wakelock_plus` 1.8.2, `flutter_ringtone_player` 4.0.0+4
  et `audioplayers` 6.8.1 (`CHANGELOG.md`, `build.gradle`, `AndroidManifest.xml`).
- Changelog de `package_info_plus` : https://pub.dev/packages/package_info_plus/changelog
- `SystemSoundType` : https://api.flutter.dev/flutter/services/SystemSoundType.html
- `HapticFeedback.vibrate` :
  https://api.flutter.dev/flutter/services/HapticFeedback/vibrate.html
- `VibrationEffect`, API 26 : https://developer.android.com/reference/android/os/VibrationEffect
- `Ringtone.setAudioAttributes`, API 21 :
  https://developer.android.com/reference/android/media/Ringtone
- Permission `VIBRATE` : https://developer.android.com/reference/android/Manifest.permission
  (niveau de protection « normal » à vérifier, section non lue).
- SDK Flutter 3.44.6 local : `packages/flutter_localizations/lib/src/l10n/` (tailles des
  fichiers) et `packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`
  (`minSdkVersion`).
- Aucune mesure publiée de la taille ajoutée par `flutter_localizations` n'a été trouvée.
