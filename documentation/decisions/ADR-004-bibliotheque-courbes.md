# ADR-004 — Bibliothèque de courbes pour le relevé de fermentation

- **Statut** : accepté le 2026-11-08, décision de l'utilisateur
- **Date** : 2026-11-08
- **Remplace** : — (complète ADR-001 sans le modifier)

## Contexte

L'incrément v0.4 ajoute le relevé de fermentation à la fiche d'un brassin (`/brassins/:id`).
L'utilisateur veut lire l'évolution de la densité sur une courbe. Il a choisi l'option
« Bibliothèque de courbes », en sachant qu'elle est un changement lourd (`CLAUDE.md`,
« Changement lourd » : dépendance qui pèse sur la taille livrée ou la compilation d'une cible).

Volume : 5 à 10 points par brassin en saisie manuelle (hypothèse H2 de la spécification), des
centaines de points plus tard avec le RAPT Pill. Abscisse en jours depuis le brassage, densité
en ordonnée, et la température en seconde série. Le tracé fait 160 à 200 dp, entre le
titre « Relevé de fermentation » et la liste, à partir de 2 densités. La liste reste
l'équivalent pour les lecteurs d'écran.

Contraintes :

- cibles APK et web CanvasKit (ADR-001), Flutter 3.44.6, Dart 3.12.2, SDK `^3.11.4`
  (`app/pubspec.yaml`) ;
- `main.dart.js` fait 4 153 973 octets en v0.1.8 ;
- la fiche est lue et saisie sans réseau (spécification HS1 à HS3). Elle est hors de P2, mais
  rien ne doit s'y charger par le réseau ;
- les calculs vivent dans `brewing/` (P3) ;
- la fiche est un `ListView` (`brew_detail_screen.dart`, l. 228).

## Options

Versions et dates lues sur l'API pub.dev le 2026-11-08.

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer : liste seule | aucun code ; la liste indique l'écart à la mesure précédente | aucune lecture visuelle ; ne répond pas à la demande | 0 € / 0 € |
| Sans paquet : `CustomPaint` | aucune dépendance ; 150 à 200 lignes (estimation) ; aucun octet tiers | axes, graduations et texte agrandi à écrire ; info-bulle au toucher à écrire en plus ; à reprendre pour des centaines de points | 0 € / 0 € |
| A. `fl_chart` 1.3.0 (2026-10-21), retenu | MIT ; éditeur vérifié `flchart.dev` ; 160/160 points ; 2,33 M de téléchargements en 30 jours ; aucun code natif ; aucun nouveau paquet transitif | aucune sémantique sur la courbe ; une seule échelle verticale ; rupture d'API déjà vue dans une version mineure (1.1.0) ; archive de 21,1 Mo | 0 € / 0 € |
| B. `graphic` 2.7.0 (2026-02-25) | MIT ; 160/160 points ; sources plus courtes (15 252 lignes) | éditeur non vérifié, mainteneur individuel ; dernière publication il y a 8 mois ; aucune sémantique ; ajoute `path_drawing` 1.0.1 (publié en 2022) et `path_parsing` ; API de grammaire graphique plus longue à apprendre | 0 € / 0 € |
| C. `syncfusion_flutter_charts` 35.1.43 (2026-11-03) | éditeur vérifié ; plusieurs axes verticaux | licence propriétaire à accepter (`license:unknown` sur pub.dev) : moins de 1 M USD de revenu et moins de 5 développeurs ; 134 253 lignes avec `syncfusion_flutter_core` | 0 € sous licence Community, à confirmer / 0 € |

Écartés sans étude détaillée :

- `charts_flutter` 0.12.0 : abandonné, SDK `<3.0.0` ;
- `mrx_charts` 0.1.3 : SDK `<3.0.0` ;
- `community_charts_flutter` 1.0.4 : aucune publication depuis le 2024-05-15 ;
- `d_chart` 3.0.0 : surcouche d'un fork de `community_charts` ;
- `cristalyse` 1.17.6 : tire `path_provider`, `flutter_svg` et `universal_html`.

Compatibilité de `fl_chart` 1.3.0, lue dans son `pubspec.yaml` :

- SDK `>=3.6.2 <4.0.0` et Flutter `>=3.27.4` : acceptés par Flutter 3.44.6 et Dart 3.12.2.
  La contrainte ne prouve pas la compilation : pub.dev a analysé le paquet sous Flutter 3.47.8 ;
- `equatable >=2.1.0 <4.0.0` et `vector_math ^2.2.0` : déjà dans `app/pubspec.lock`
  (2.1.0 et 2.2.0), et Flutter 3.44.6 fige `vector_math` à 2.2.0. `pubspec.lock` gagne une
  seule entrée, d'après ces contraintes, sans résolution lancée ;
- pas de `plugin:`, pas de dossier `android/`, pas de `hook/` : aucun effet sur Gradle ni sur
  AGP 9.0.1 ;
- Android et web annoncés par pub.dev.

## Décision

Option A, `fl_chart` figé en 1.3.0, pour la densité et la température en v0.4. C'est le seul
candidat libre, suivi et sans nouvelle dépendance transitive.

Avis de l'architecte : favorable sous conditions, pour la densité seule.

Arbitrages de l'utilisateur, le 2026-11-08 :

- la température est tracée aussi, contre la recommandation de l'architecte. `fl_chart` n'a
  qu'une échelle verticale : `trace_courbe.dart` recale la température sur l'échelle de la
  densité et dessine lui-même les libellés de la seconde échelle ;
- une info-bulle au toucher affiche la date, la densité et la température d'un point. Si elle
  gêne le défilement à l'essai sur téléphone, elle est retirée sur téléphone, et l'utilisateur
  en est informé ;
- les seuils de 400 Ko et de 2 Mo sont acceptés, et la courbe est construite en dernier ;
- le contrôle P18 et l'extension de P1 sont acceptés.

1. **Version exacte** : `fl_chart: 1.3.0`, sans `^`. Le changelog de la 1.1.0 annonce une
   rupture d'API dans une version mineure.
2. **Mesure avant la fusion** : `flutter build web --release` et `flutter build apk --release`,
   avant et après, valeurs notées au `CHANGELOG.md`. Au-delà de 400 Ko de `main.dart.js` ou de
   2 Mo d'APK, la session s'arrête et revient à l'utilisateur.
3. **Un seul fichier importe `fl_chart`** (voir « Isolement du tracé »).
4. **Accessibilité** : `Semantics(label: résumé)` autour d'un `ExcludeSemantics`. Le résumé
   suit la proposition UX : « Densité de 1058,0 à 1014,0 en 12 jours. », complété par la
   température quand elle existe.
5. **Thèmes et texte** : chaque couleur vient de `Theme.of(context).colorScheme`, aucune valeur
   par défaut du paquet. `reservedSize` se multiplie par l'échelle du texte.
6. **Aucun `deferred as`** (voir « Chargement différé »).
7. **Courbe livrée en dernier dans la v0.4.** Elle ne fait pas partie du critère de fin
   (D1) : elle peut sortir de l'incrément sans bloquer le prochain brassin.

### Isolement du tracé (plan de repli)

```
brewing/lib/src/fermentation.dart                              FermentationPoint, série ordonnée
app/lib/features/brews/presentation/courbe_fermentation.dart   seuil, résumé, sémantique
app/lib/features/brews/presentation/trace_courbe.dart          seul import de package:fl_chart
```

`TraceCourbe` reçoit une `List<FermentationPoint>` et des fonctions de libellé. Aucun type de
`fl_chart` ne sort de ce fichier. Les tests de la fiche passent par `CourbeFermentation` et par
le libellé sémantique, jamais par `find.byType(LineChart)`.

Abandon du paquet : réécrire `trace_courbe.dart` en `CustomPaint` (150 à 200 lignes, estimation)
et retirer la ligne de `pubspec.yaml`. Rien d'autre ne change.

### Ce qui vit où

`brewing/` :

- `FermentationPoint(dayOffset, dayNumber, gravity, temperature)`, densité et température facultatives, et la fonction qui construit la série
  depuis `brewedAt` et les relevés, triée par heure de mesure ;
- `dayOffset` = jours calendaires depuis `brewedAt` + fraction de la journée locale. Sa partie
  entière vaut le J+N de la liste (FE7) : liste et courbe lisent le même nombre. Un jour de
  changement d'heure compte pour un jour ;
- cas ajoutés à `brewing/test/fixtures/` avant le code (P3) : ordre, densité absente, changement
  d'heure, deux relevés le même jour.

`app/` :

- le seuil de 2 densités, le résumé sémantique, la hauteur ;
- la conversion en `FlSpot`, les bornes et le pas des axes, le recalage de la température sur
  l'échelle du tracé, qui sont de la mise en page ;
- les libellés, par `formats.dart` (`formatDensite`) ;
- sans `brewed_at`, aucune courbe : la liste s'affiche seule (FE7).

### Chargement différé

`deferred as` est possible. Il n'est pas retenu.

- Android : `app/pubspec.yaml` n'a pas d'entrée `deferred-components`. Tout le code Dart reste
  dans une seule bibliothèque et `loadLibrary()` se termine au prochain tour de boucle. Le gain
  est nul.
- Web : le code part dans un fichier `.js` séparé, pour un gain estimé de 120 à 300 Ko.
- `firebase.json` n'a aucune règle `Cache-Control` pour ce fichier : il faudrait l'ajouter à P1
  (leçon 6).
- Un onglet déjà ouvert sans réseau, seul cas hors ligne garanti sur le web, échouerait au
  chargement de ce fichier.
- Un onglet ouvert avant un déploiement demanderait le fichier de la version suivante, sans
  garantie de compatibilité.

La règle du démarrage de `CLAUDE.md` vise les SDK qui tirent une pile réseau ou
d'authentification. `fl_chart` n'importe que `dart:ui`, `dart:math`, `dart:core`, `flutter`,
`equatable` et `vector_math`, et n'a aucune variable globale à initialiser (recherche sur
`lib/`). Si la mesure dépasse le seuil de la condition 2, cette question se rouvre.

## Coût du changement

Mesuré sur l'archive de `fl_chart` 1.3.0, sans compilation :

| Mesure | Valeur |
|---|---|
| `lib/` | 68 fichiers, 21 988 lignes, 714 283 octets |
| Sources sans commentaires, tout le paquet | 512 242 octets |
| Sources sans commentaires, courbe, base des axes et utilitaires | environ 246 000 octets |
| Archive téléchargée dans le cache pub et le cache de la CI | 21 118 071 octets, dont un dossier `build/` de 49 Mo décompressés, non compilé |

Estimé, non mesuré : aucune compilation n'a été lancée pour cet avis.

| Effet | Estimation | Hypothèse |
|---|---|---|
| `main.dart.js` | +120 à 300 Ko, soit +2,9 à +7,2 % | 0,5 à 1,2 octet de JS par octet de source sans commentaires, non calibrée ; suppose que le tree shaking retire les autres types de courbes |
| APK | +0,5 à 1,5 Mo | APK universel à trois ABI (`deploy.yml` sans `--split-per-abi`) ; ordre de grandeur |
| Compilation | quelques secondes par cible | à lire dans les journaux de la CI |

Autres effets :

- **Analyse statique** : `flutter analyze` ne porte que sur le code du projet. Aucun réglage à
  changer. pub.dev note le paquet 50/50 en analyse.
- **Tests de widgets** : aucun test doré dans `app/test/`. L'animation par défaut dure 150 ms :
  `duration: Duration.zero` quand `MediaQuery.disableAnimations` est vrai, et dans les tests.
- **Texte à 200 %** : `LineChart` lit `MediaQuery.textScaler`, mais `reservedSize` vaut 22
  pixels logiques par défaut, sans lien avec l'échelle. Sans la condition 5, les libellés d'axe
  sont coupés.
- **Lecteurs d'écran** : un seul fichier de `lib/` mentionne la sémantique, celui de la courbe
  en secteurs. Le ticket 1746 du paquet (sémantique des info-bulles) est ouvert.
- **Thèmes** : valeurs par défaut en dur (`Colors.cyan` pour la ligne, `Colors.black` pour la
  bordure, `Colors.blueGrey` pour l'info-bulle). Une bordure noire est illisible en thème
  sombre.
- **Gestes** : le rendu ajoute des reconnaisseurs de pan, d'appui et d'appui long
  (`render_base_chart.dart`, l. 160-165) dans un `ListView`. Le défilement vertical reste à
  vérifier sur un téléphone. Repli : `IgnorePointer` autour du tracé.
- **Seconde série** : `fl_chart` n'a pas de seconde échelle verticale (ticket 429 ouvert). La
  température demande une remise à l'échelle dans `trace_courbe.dart`, et des libellés d'axe
  inversés. Le recalage reste de l'affichage : aucune valeur recalée n'est stockée. Une
  légende écrite et un trait distinct séparent les deux séries, sans s'appuyer sur la couleur
  seule.
- **Centaines de points** : non mesuré. La réduction du nombre de points se décidera avec l'ADR
  du RAPT Pill, sans changer l'interface.

Fichiers touchés : `app/pubspec.yaml`, `app/pubspec.lock`, `brewing/lib/src/fermentation.dart`,
`brewing/lib/brewing.dart`, une fixture de `brewing/test/fixtures/`, deux fichiers de
présentation, leurs tests, `brew_detail_screen.dart`, `exigences-techniques.md`,
`exigences-fonctionnelles.md`, `CHANGELOG.md`. Aucune migration de données. La spécification
v0.4 (ligne « Pas un changement lourd », Q3) est à corriger.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : sur l'appareil ou dans le navigateur. `fl_chart` ne
   dessine qu'avec `dart:ui` et Flutter.
2. **Ce qui existera en double** : rien. Le J+N de la liste et l'abscisse viennent de la même
   fonction de `brewing/`.
3. **Ce qui pèse au démarrage** : le code du paquet, inclus dans `main.dart.js`, sans
   initialisation ni réseau. Taille à mesurer (condition 2).
4. **Compilation de chaque cible** : `flutter build web --release` et
   `flutter build apk --release`. Le job « Android — compilation » de la CI se déclenche sur
   `app/pubspec.yaml` et `app/pubspec.lock`. Aucun code natif ajouté.
5. **Qui voit quoi** : la courbe affiche les mesures déjà lisibles par le groupe. Aucun prix
   (P5), aucune donnée envoyée à un tiers.
6. **Ce qui coûte à l'usage, plafond** : rien. Aucune lecture Firestore de plus : la courbe
   lit la liste déjà chargée par `watchEvents`.
7. **Exposition** : inchangée. La recherche dans `lib/` ne trouve aucun `NetworkImage`, aucun
   client HTTP, aucune police téléchargée, aucun asset. Le `pubspec.yaml` du paquet ne déclare
   ni `assets:` ni `fonts:`. La courbe marche hors ligne.
8. **Exploitation, sauvegarde, mise à jour** : une dépendance à monter à la main. Rien à
   sauvegarder. Le code arrive par `main.dart.js` (`no-cache`, P1) et par une mise à jour de
   l'APK.
9. **Coût de sortie** : un fichier à réécrire, 150 à 200 lignes (estimation), et une ligne de
   `pubspec.yaml`.

## Conséquences

Plus simple : axes, grille et info-bulle au toucher ne s'écrivent pas.

Plus difficile : une dépendance de plus à suivre, et une configuration à écrire pour la
sémantique, les thèmes et le texte agrandi. À 5 à 10 points, le gain de lignes par rapport à
`CustomPaint` est faible (la configuration est estimée à une centaine de lignes). Le paquet se
justifie par l'info-bulle et par les volumes du RAPT Pill.

À vérifier sur un téléphone avant la livraison : défilement de la fiche quand le doigt part de
la courbe, thème sombre, texte à 200 %.

Contrôles ajoutés à `CLAUDE.md`, après le « oui » de l'utilisateur :

| N° | Contrôle | Agent | Origine |
|---|---|---|---|
| P18 | `fl_chart` : `package:fl_chart` importé par le seul fichier `app/lib/features/brews/presentation/trace_courbe.dart`, aucun type du paquet dans une signature publique ; version exacte dans `pubspec.yaml` ; aucune couleur par défaut du paquet (ligne, bordure, grille, info-bulle lues dans `colorScheme`) ; `reservedSize` multiplié par l'échelle du texte ; tracé dans un `ExcludeSemantics` avec un résumé en `Semantics` | `relecteur-regles` | ADR-004 |

Extension de P1, ajoutée en fin de cellule : « Tout `deferred as` dans `app/lib/`
exige une règle `no-cache` pour ses fichiers `.part.js` dans `firebase.json`, et un nouvel ADR. »

## Sources

Consultées le 2026-11-08.

- API pub.dev (version, date, dépendances, éditeur, score) :
  https://pub.dev/api/packages/fl_chart, https://pub.dev/api/packages/graphic,
  https://pub.dev/api/packages/syncfusion_flutter_charts,
  https://pub.dev/api/packages/syncfusion_flutter_core,
  https://pub.dev/api/packages/community_charts_flutter,
  https://pub.dev/api/packages/charts_flutter, https://pub.dev/api/packages/d_chart,
  https://pub.dev/api/packages/mrx_charts, https://pub.dev/api/packages/cristalyse,
  https://pub.dev/api/packages/path_drawing
- Contenu des archives pub.dev de `fl_chart` 1.3.0, `graphic` 2.7.0,
  `syncfusion_flutter_charts` 35.1.43 et `syncfusion_flutter_core` 35.1.43 (`lib/`,
  `pubspec.yaml`, `CHANGELOG.md`, `LICENSE`).
- Analyse pub.dev sous Flutter 3.47.8 et Dart 3.13.7 :
  https://pub.dev/packages/fl_chart/score
- Licence Syncfusion : https://pub.dev/packages/syncfusion_flutter_charts/license
- Tickets 429 et 1746 du dépôt GitHub de `fl_chart`, lus par l'API GitHub.
- Chargement différé : https://docs.flutter.dev/perf/deferred-components
- Cache Firebase Hosting : https://firebase.google.com/docs/hosting/manage-cache (ne donne pas
  la durée de cache navigateur par défaut d'un fichier statique : à vérifier).
- SDK Flutter 3.44.6 local : `packages/flutter/pubspec.yaml` (`vector_math` 2.2.0).
