# Exigences techniques

État actuel. Les choix et leurs raisons vivent dans `decisions/`.

## Architecture

Application Flutter (`app/`, Android et web) qui lit et écrit Cloud Firestore `(default)`
directement, avec le cache hors ligne persistant. Aucun serveur en version 1 (ADR-001) :
`firestore.rules` est le seul contrôle d'accès.

| Fichier | Rôle |
|---|---|
| `firestore.rules` | règles d'accès, appliquant le modèle ci-dessous |
| `firestore.indexes.json` | index composites ; vide tant qu'aucune requête n'en demande |
| `firebase.json` | Firestore, émulateurs (auth 9099, firestore 8080), Hosting |
| `.firebaserc` | alias `default` : `kassbeer`, le projet Firebase de production |
| `rules-tests/` | tests des règles contre l'émulateur, projet `demo-kassbeer` |

### Hosting

Dossier publié : `app/build/web`. Toute URL sans fichier correspondant est réécrite vers
`/index.html` (navigation go_router).

| Chemin | `Cache-Control` |
|---|---|
| `canvaskit/**` | `public, max-age=31536000, immutable` (seul chemin immuable, P1) |
| `/`, toute URL sans extension (`**/!(*.*)`), `index.html` | `no-cache, no-store, must-revalidate`, plus `Pragma: no-cache` et `Expires: 0` |
| `flutter_bootstrap.js`, `flutter.js`, `main.dart.js`, `version.json` | `no-cache, no-store, must-revalidate` |
| autres fichiers | réglage par défaut de Hosting |

Les URL sans extension (`/`, `/recettes/12`) reçoivent l'en-tête de `index.html` : Hosting
compare les en-têtes au chemin demandé, pas au fichier servi après réécriture.

Sur `**` (P12) : `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
`Referrer-Policy: strict-origin-when-cross-origin`. Aucun JSON d'import n'est publié : le
dossier `import/` n'est ni dans `app/build/web`, ni versionné.

### Application Flutter (`app/`)

Projet `kass_beer`, plateformes Android et web, `applicationId` `fr.kassbeer.kass_beer`.
État par Riverpod, navigation par go_router. Chaque feature suit les couches `data/`
(dépôts de données), `domain/` (types), `presentation/` (écrans, providers).

| Dossier | Contenu |
|---|---|
| `lib/main.dart` | démarrage : configuration, Firebase, cache Firestore, version, journal d'erreurs, `google_sign_in` (Android), `ProviderScope` |
| `lib/app.dart` | `KassBeerApp` (thème, routeur), `MissingConfigurationApp`, `StartupFailureApp` |
| `lib/firebase_options.dart` | `FirebaseEnv` : configuration lue par `String.fromEnvironment` |
| `lib/core/providers.dart` | providers des services, fournis par `main.dart` ou par les tests |
| `lib/core/services/error_report_service.dart` | `ErrorReportService`, `ErrorReportFields` |
| `lib/core/router/` | `routes.dart` (chemins), `app_router.dart` (routeur, `redirectFor`) |
| `lib/core/presentation/` | `AppShell` (rail défilable), `breakpoints.dart` (seuils 600 / 840 et largeurs `kFormMaxWidth` 400, `kDialogMaxWidth` 480, `kMessageMaxWidth` 480, `kAccountMenuMaxWidth` 280, `kContentMaxWidth` 840), `etats.dart` (`EtatChargement`, `EtatVide` avec action facultative, `EtatErreur`, `IndicateurBouton`), `BandeauHorsLigne`, `LogoKassBeer` |
| `lib/core/theme/app_theme.dart` | thème Material 3, seul fichier où une couleur est écrite |
| `lib/features/auth/` | `AuthRepository` (Firebase Auth, Google), état d'accès, écrans Chargement, Connexion, Compte non invité, Erreur |
| `lib/features/members/` | `MembersRepository` (`members/`), `Member`, Admin › Membres |
| `lib/features/admin/`, `recipes/`, `brews/`, `equipment/` | écran Admin ; écrans à venir |

**Configuration Firebase.** Aucune valeur dans le code. `firebase_options.dart` lit, par
`--dart-define-from-file=firebase.env.json` (fichier ignoré par Git ; modèle
`app/firebase.env.example.json`) : `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
pour le web `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID`, `FIREBASE_AUTH_DOMAIN`, pour
Android `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `GOOGLE_SERVER_CLIENT_ID`.
Le web et Android ont chacun leur clé d'API et leur identifiant d'application dans Firebase.
`GOOGLE_SERVER_CLIENT_ID` est l'identifiant du client OAuth « Web » du projet :
`google_sign_in` 7 l'exige sur Android pour rendre un jeton d'identité, faute de
`google-services.json` (non versionné, non utilisé). Une clé vide pour la plateforme affiche
« Configuration Firebase absente » et la liste des clés manquantes. Un échec de
`Firebase.initializeApp` affiche « Kass'Beer n'a pas pu démarrer » ; le message part sur la
console, faute de Firestore.

**Démarrage.** Dans l'ordre : configuration, `Firebase.initializeApp`, réglage de Firestore
(`persistenceEnabled: true`, `cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED`), version lue par
`package_info_plus` (`version.json` sur le web), `ErrorReportService`, branchement de
`FlutterError.onError` et `PlatformDispatcher.instance.onError`, puis
`GoogleSignIn.instance.initialize(serverClientId:)` sur Android.

**Connexion.** Web : `signInWithPopup` (`prompt: select_account`). Android :
`GoogleSignIn.instance.authenticate()`, puis `signInWithCredential` avec le jeton
d'identité. Fenêtre fermée (`popup-closed-by-user`, `cancelled-popup-request`,
`web-context-canceled`, `GoogleSignInExceptionCode.canceled`) : aucun message. Tout autre
échec est rapporté et levé en `SignInFailure` ; `network-request-failed` donne le message
réseau. La déconnexion ferme aussi la session `google_sign_in` sur Android.

**Signature Android.** `app/android/app/build.gradle.kts` lit `app/android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword` ; jamais versionné, P8). Sans ce
fichier, une compilation de release échoue avec un message ; aucune release n'est signée par
la clé de débogage. Le manifeste principal déclare `INTERNET`.

#### Providers

| Provider | Type | Rôle |
|---|---|---|
| `errorReportServiceProvider`, `authRepositoryProvider`, `membersRepositoryProvider`, `appVersionProvider` | `Provider` | services fournis par `main.dart` (`overrides`) ou par les tests ; sans valeur par défaut |
| `sessionUserProvider` | `StreamProvider<SessionUser?>` | `authStateChanges()` |
| `memberLookupProvider(emailKey)` | `StreamProvider.family<MemberLookup, String>` | `members/{email en minuscules}`, avec les métadonnées |
| `accessStateProvider` | `Provider<AccessState>` | `AccessLoading`, `AccessSignedOut`, `AccessNotInvited`, `AccessFailed`, `AccessGranted(user, member, offline)` |
| `accessRefreshingProvider` | `Provider<bool>` | nouvelle lecture en cours (boutons « Réessayer », « Vérifier à nouveau ») |
| `membersListProvider` | `StreamProvider.autoDispose<List<Member>>` | `members/` entier, admin seul |
| `routerProvider` | `Provider<GoRouter>` | routeur, rafraîchi à chaque changement de `accessStateProvider` |

Aucun de ces providers ne réessaie seul (`retry` rend `null`) : une panne s'affiche, et
« Réessayer » invalide le provider.

**Lecture du membre.** `watchMember` écoute `members/{email}` avec
`includeMetadataChanges: true`. Document présent : membre, `offline` = `isFromCache`.
Document absent d'une réponse du serveur : non invité. Document absent du cache seul : rien
n'est émis, et sans réponse du serveur en 10 s (`kMemberServerWait`), le flux lève
`MemberLookupUnavailable`, rapportée : écran Erreur. Un rôle autre que `admin` ou `brewer`
se lit `null` et n'ouvre pas Admin.

**Écritures hors ligne.** `invite` et `remove` écrivent dans le cache dès l'appel ;
l'écran se ferme sans attendre le serveur. La ligne porte « En attente du réseau » tant
que `hasPendingWrites` est vrai. Un refus du serveur est rapporté par le dépôt et annoncé à
l'écran. L'invitation écrit `email`, `role`, `display_name` (omis s'il est vide),
`invited_at` = `FieldValue.serverTimestamp()`, `invited_by` = uid de l'admin. Le doublon se
vérifie sur la liste déjà lue ; les règles refusent de toute façon de récrire un membre.

**Journal d'erreurs.** `ErrorReportService.reportError(feature:, error:, stackTrace:,
context:)` écrit `error_reports/` sans attendre le serveur, avec les seuls champs des règles
(`uid`, `feature`, `error`, `stack_trace`, `context`, `app_version`, `platform`,
`created_at` = `serverTimestamp()`), coupés à leurs bornes. `context` est une chaîne. Toute
URL (`schéma://…`) est remplacée par `<url>` et toute adresse e-mail par `<e-mail>` dans
`error`, `stack_trace` et `context` : l'adresse d'une photo Google ou un jeton ne partent
pas. L'erreur de l'avatar ne rapporte que son type et le code HTTP.

Écritures bornées par session (une instance du service) : un rapport identique (même
`feature`, même type d'erreur, même premier cadre de pile) n'est écrit qu'une fois ; au plus
20 écritures par minute glissante (`maxPerMinute`) et 200 par session (`maxPerSession`). Le
surplus part sur la console avec le compte des rapports écartés (`skippedCount`).

Sans compte connecté, au-delà des plafonds, ou si l'écriture est refusée (compte non
invité), le rapport part sur la console (`debugPrint`), dernier recours documenté.

#### Routes (go_router)

| Chemin | Écran | Accès |
|---|---|---|
| `/chargement` | Chargement | état `AccessLoading` |
| `/connexion` | Connexion | sans session |
| `/non-invite` | Compte non invité | connecté, sans `members/{email}` |
| `/erreur-acces` | Erreur d'accès | lecture impossible |
| `/` | redirige vers `/recettes` | membre |
| `/recettes`, `/brassins`, `/equipements` | écrans à venir, dans la coquille | membre |
| `/admin` | Admin | admin |
| `/admin/membres` | Admin › Membres | admin |

`redirectFor(access, uri)` (fonction pure, testée) envoie chaque état sur son écran. Un
chemin demandé pendant un écran d'accès est gardé dans `?depuis=` et retrouvé une fois le
membre lu ; seuls les chemins internes (`/…`, pas `//…`) sont suivis, et une page d'Admin ne
s'ouvre pas pour un brasseur. Un chemin inconnu affiche « Cette page n'existe pas. » et
« Revenir à l'accueil ». Le routeur ne protège aucune donnée : `firestore.rules` le fait.

**Tests.** `app/test/` : écrans et contrôle d'accès avec des doubles des dépôts
(`test/support/fakes.dart`, sans Firebase), `redirectFor`, `ErrorReportFields`,
`FirestoreMembersRepository` sur `fake_cloud_firestore`, attente du serveur sous
`fake_async`, `FirebaseEnv`.

## Modèle de données

Unités du système international : masses en grammes (`_g`), volumes en litres (`_l`),
températures en °C (`_c`), densités en SG décimal, couleur en EBC, durées en minutes
(`_min`), pourcentages de 0 à 100 (`_pct`). Les dates `created_at` et `updated_at` sont
posées par `serverTimestamp()` ; les règles vérifient qu'elles valent l'heure de la requête.

Les règles refusent tout champ de premier niveau absent des listes ci-dessous. Les éléments
d'une liste (ingrédients, paliers) ne peuvent pas être inspectés par les règles : le dépôt
de données les écrit à partir des types de `brewing/`, sans prix (P5).

### `members/{email}`

Identifiant : l'e-mail du compte Google, en minuscules. Écrit par l'admin seul. Le premier
admin se crée dans la console Firebase.

| Champ | Type | Règle |
|---|---|---|
| `email` | string | égal à l'identifiant |
| `role` | string | `admin` ou `brewer` |
| `display_name` | string \| null, facultatif | saisi par l'admin à l'invitation, 80 caractères au plus |
| `invited_at` | timestamp | `serverTimestamp()` |
| `invited_by` | string | uid de l'admin qui invite ; `console` pour le premier admin, créé hors de l'application |

Aucune modification en v1 : pour changer le rôle d'un brasseur, l'admin le retire puis le
réinvite. Un admin ne retire ni son propre document ni celui d'un autre admin : un
administrateur se retire depuis la console Firebase.

### `recipes/{recipeId}`

Lisible par tous les membres (partagée au groupe). Aucun prix.

| Champ | Type |
|---|---|
| `owner_uid` | string, obligatoire, uid de l'auteur, immuable |
| `name` | string, obligatoire, 1 à 120 caractères |
| `style` | string \| null (120) |
| `notes` | string \| null (10 000) |
| `batch_volume_l` | number \| null : volume visé en fermenteur |
| `boil_time_min` | number \| null |
| `equipment_id` | string \| null : profil d'équipement prévu |
| `fermentables` | list<map> \| null (50) : `key`, `name`, `kind` (`grain`, `sugar`, `extract`), `weight_g`, `ebc`, `yield_pct` |
| `hops` | list<map> \| null (50) : `key`, `name`, `weight_g`, `alpha_pct`, `use` (`boil`, `whirlpool`, `dry_hop`, `first_wort`), `time_min`, `form` (`pellet`, `leaf`) |
| `others` | list<map> \| null (50) : épices et ajouts, `key`, `name`, `weight_g`, `use`, `time_min` |
| `yeasts` | list<map> \| null (10) : `key`, `name`, `attenuation_pct`, `form` |
| `mash_steps` | list<map> \| null (20) : `name`, `temp_c`, `duration_min` |
| `imported_from` | string \| null (200) : nom de la fiche Excel d'origine |
| `created_at`, `updated_at` | timestamp, obligatoires |

`key` est la clé d'ingrédient (`ingredientKey`) : nature et nom normalisés, en minuscules,
sans accents, mots reliés par des tirets (`malt-pilsner`, `houblon-saaz`). Elle relie
l'ingrédient au prix et au stock du lecteur. Densités, degré, IBU, EBC et coût ne sont pas
stockés : `brewing/` les calcule à l'affichage.

### `equipment/{equipmentId}`

Lisible par le groupe (ADR-001, arbitrage 5).

| Champ | Type |
|---|---|
| `owner_uid` | string, obligatoire, immuable |
| `name` | string, obligatoire (120) |
| `kind` | string, obligatoire : `multi_vessel` (cuves séparées) ou `all_in_one` (Grainfather) |
| `mash_efficiency_pct` | number \| null : rendement d'empâtage |
| `mash_tun_volume_l`, `kettle_volume_l` | number \| null |
| `mash_tun_dead_space_l`, `kettle_dead_space_l` | number \| null : pertes de cuve |
| `boil_off_l_per_h` | number \| null : évaporation |
| `trub_loss_l`, `fermenter_loss_l` | number \| null |
| `grain_absorption_l_per_kg` | number \| null |
| `notes` | string \| null (10 000) |
| `created_at`, `updated_at` | timestamp, obligatoires |

### `brews/{brewId}`

Lisible par le groupe, mesures comprises, sans coût. La recette et l'équipement sont copiés
à la création et ne changent plus (« Un brassin fige sa recette »).

| Champ | Type |
|---|---|
| `owner_uid` | string, obligatoire, immuable |
| `recipe_id` | string \| null : recette d'origine, immuable |
| `name` | string, obligatoire (120) |
| `status` | string, obligatoire : `planned`, `brewing`, `fermenting`, `conditioning`, `done`, `abandoned` |
| `planned_for`, `brewed_at` | timestamp \| null |
| `recipe_snapshot` | map, obligatoire, immuable : copie de la recette, mêmes champs de premier niveau |
| `equipment_snapshot` | map, obligatoire, immuable : copie de l'équipement, mêmes champs de premier niveau |
| `adjustments` | map \| null : ajustements du jour, jamais écrits dans la recette. Clés en liste blanche, chacune number \| null : `batch_volume_l`, `mash_water_l`, `sparge_water_l`, `pre_boil_volume_l`, `post_boil_volume_l`, `fermenter_volume_l`, `boil_off_l_per_h`, `mash_temp_c`, `mash_time_min`, `boil_time_min`, `mash_efficiency_pct`. Aucune autre clé, donc aucun prix ni coût (P5) |
| `bottles_count` | number \| null |
| `notes` | string \| null (10 000) |
| `imported_from` | string \| null (200) |
| `created_at`, `updated_at` | timestamp, obligatoires |

Le rendement réel se calcule à l'affichage à partir des événements et de la copie figée.

### `brews/{brewId}/events/{eventId}`

Un document par mesure, début ou fin d'étape. L'identifiant est créé par l'appareil.
Aucune transaction n'est nécessaire : l'écriture part du cache hors ligne et passe les
règles au retour du réseau.

| Champ | Type |
|---|---|
| `owner_uid` | string, obligatoire : propriétaire du brassin |
| `kind` | string, obligatoire : `step_started`, `step_ended`, `measurement`, `note` |
| `step_key` | string \| null (100) : étape de la chronologie |
| `measure_type` | string \| null : `temperature` (°C), `gravity` (SG), `volume` (L), `ph` |
| `value` | number \| null |
| `note` | string \| null (2 000) |
| `measured_at` | timestamp, obligatoire : heure de l'appareil |
| `created_at` | timestamp, obligatoire : `serverTimestamp()`, audit seul |

Après création, seuls `value`, `note` et `measured_at` se corrigent.

### `users/{uid}/…` — données privées

Lisibles et modifiables par leur seul propriétaire, membre. L'admin ne les lit pas (P5).
Les règles ne contrôlent pas la forme de ces documents.

| Chemin | Champs |
|---|---|
| `users/{uid}/prices/{ingredientKey}` | `name` string, `price_eur` number (prix d'un achat), `quantity` number, `unit` string (`g`, `l`, `unit`, `kwh`), `updated_at` timestamp |
| `users/{uid}/stock/{ingredientKey}` | `name` string, `quantity` number, `unit` string, `updated_at` timestamp (après la v1) |
| `users/{uid}/brew_costs/{brewId}` | `brew_id` string, `total_eur` number, `lines` list<map> (`key`, `name`, `quantity`, `unit`, `cost_eur`), `computed_at` timestamp |

Le coût réel d'un brassin est stocké parce qu'il reprend les prix du jour de l'achat ; le
coût d'une recette se recalcule à l'affichage avec les prix du lecteur.

### `error_reports/{reportId}`

Écrit par `ErrorReportService.reportError` (P13).

| Champ | Type |
|---|---|
| `uid` | string, obligatoire : `request.auth.uid` |
| `feature` | string, obligatoire, 1 à 100 caractères |
| `error` | string, obligatoire, 2 000 caractères au plus |
| `stack_trace` | string \| null (8 000) |
| `context` | string \| null (2 000) : texte libre, sans prix, stock, coût ni e-mail |
| `app_version` | string \| null (40) |
| `platform` | string \| null : `android` ou `web` |
| `created_at` | timestamp, obligatoire : `serverTimestamp()` |

## Règles d'accès

Un membre est un compte connecté par Google (`firebase.sign_in_provider == 'google.com'`),
à l'adresse vérifiée (`email_verified == true`), dont l'e-mail en minuscules a un document
`members/{email}` (P11). Le rôle n'existe que dans ce document.

| Chemin | Lecture | Création | Modification | Suppression |
|---|---|---|---|---|
| `members/{email}` | son propre document (même absent) pour tout compte Google vérifié ; tous pour l'admin | admin | personne | admin, sauf son propre document et celui d'un autre admin (`resource.data.role != 'admin'`) |
| `recipes/`, `equipment/` | membres | membre, à son `owner_uid` | propriétaire, `owner_uid` et `created_at` inchangés | propriétaire |
| `brews/` | membres | membre, à son `owner_uid` | propriétaire ; `recipe_id`, `recipe_snapshot`, `equipment_snapshot` inchangés | propriétaire |
| `brews/{id}/events/` | membres | propriétaire du brassin | auteur : `value`, `note`, `measured_at` | auteur |
| `users/{uid}/**` | propriétaire | propriétaire | propriétaire | propriétaire |
| `error_reports/` | admin | membre, `uid` = le sien, champs en liste blanche et bornés | personne | admin |
| tout autre chemin | refusé | refusé | refusé | refusé |

L'admin n'a aucun droit d'écriture sur le contenu des autres brasseurs.

Tests : `rules-tests/` (Node 22, `@firebase/rules-unit-testing`, `node --test`), lancés par
`npm test`, qui démarre l'émulateur Firestore (Java 21) sur le projet `demo-kassbeer`.
Chaque collection est rejouée pour les cinq profils de P4 (anonyme, connecté non membre,
brasseur propriétaire, autre brasseur, admin), plus les comptes invités à l'adresse non
vérifiée ou connectés par mot de passe, et un jeton à l'adresse en majuscules.

## Calculs de brassage

Les calculs vivent dans le paquet Dart pur `brewing/` (ADR-001, CLAUDE.md P3) : aucune
dépendance Flutter ni Firebase, `test` et `lints` en développement seulement. L'application
seule l'importe (`package:brewing/brewing.dart`). Aucune formule de brassage n'existe ailleurs.

**Unités.** Masses en grammes, volumes en litres, densités en SG décimal (1.0579), couleur en
EBC, durées d'ébullition en minutes ; le planning prend des `Duration` et des `DateTime` de
l'appareil. La conversion vers l'affichage se fait à l'écran.

**Erreurs.** Une entrée invalide (nombre négatif ou non fini, densité hors de 0.980 – 1.200,
FG > OG, liste vide, fin d'étape sans début) lève `BrewingInputException(field, value, message)`.
Le paquet ne fait aucun `catch` (`test/no_catch_test.dart` le vérifie) : l'appelant journalise
par `ErrorReportService.reportError` et affiche la panne.

| Calcul | Fonction | Formule |
|---|---|---|
| SG ↔ points | `sgToPoints`, `pointsToSg` | points = (SG − 1) × 1000 |
| Notation des fiches | `parseGravity` | « 1057,9 » et « 1090 » ÷ 1000 ; « 1.052 », « 1,07 » lus tels quels |
| Densité initiale prévue | `predictedOriginalGravity` | 1 + Σ (kg × points/kg/L × r) / V / 1000 ; r = rendement d'empâtage pour un malt, 1 pour un sucre |
| Potentiel d'un malt | `ExtractPotential` | rendement d'extrait % × 385,67 (saccharose, 46,214 ppg), ou points/kg/L |
| Rendement d'empâtage réel | `measuredMashEfficiency` | (points mesurés × V − points des sucres déjà dans le moût) / points des malts à 100 % |
| Degré | `alcoholByVolume` | (OG − FG) × 131,25 |
| Degré après bouteille | `alcoholByVolumeAfterBottling` | degré + g/L × potentiel du sucre / 10⁶ × 131,25 ; `null` sans donnée de resucrage |
| IBU | `tinsethIbu`, `tinsethIbuForHop` | Tinseth : 1,65 × 0,000125^(Gb − 1) × (1 − e^(−0,04 t)) / 4,15 × alpha (mg/L) ; pellets × 1,1, cônes × 1,0 ; après ébullition et dry hop : 0 |
| Couleur | `moreyColorEbc` | Morey : MCU = Σ (EBC / 1,97 × lb) / gal ; SRM = 1,4922 × MCU^0,6859 ; EBC = SRM × 1,97 |
| Coût | `computeCost` | Σ quantité × prix ; par litre = total / V ; bouteille de 33 cl = par litre × 0,33 |
| Planning | `recomputeSchedule` | début d'une étape = fin enregistrée de la précédente, sinon son début + sa durée ; une étape en cours qui dépasse finit à `now` ; une étape à venir ne commence pas avant `now` |
| Minuteur | `readTimer` | restant = début + durée − `now`, borné à zéro ; dépassement au-delà |

**Pas de valeur de repli.** Un prix manquant rend `CostUnavailable(linesWithoutPrice)`, jamais
un coût partiel. Sans sucre de resucrage, le degré après bouteille est absent : la hausse
forfaitaire de 0,5 % des fiches Excel n'est pas reprise. Les prix sont passés en argument par
l'appelant, qui les lit sous `users/{uid}/` ; le paquet n'en contient aucun.

**Jour de brassage.** `recomputeSchedule` et `readTimer` sont des fonctions pures qui prennent
`now` en argument : aucun `Timer` n'est la source d'une durée, et les heures recalculées se
dérivent à l'affichage sans s'écrire.

**Fixtures.** `brewing/test/fixtures/*.json` (densité, densité initiale et rendement, degré,
IBU, couleur, coût, planning) portent des cas tirés des 16 fiches Excel : entrées, valeur de
la fiche, valeur attendue, tolérance, et hypothèses quand la fiche ne donne pas une entrée.
Les erreurs connues des fiches (Citra « 22.4 » lu 22 400 g, degré calculé sur la densité
visée, densités d'en-tête différentes de la chronologie, champs EBC et IBU copiés, coût par
bouteille divisé par le nombre de bouteilles) sont rangées dans `divergences`, sans être
corrigées dans les attentes. Une formule changée ajoute d'abord son cas à la fixture.

## CI et déploiement

Deux workflows GitHub Actions. Toute modification de l'un d'eux, ou de
`scripts/check-version.mjs`, se signale à l'utilisateur avant la fusion (P10). `securite`
vérifie P14 sur chaque diff de `.github/workflows/`.

### `ci.yml` — contrôles

Déclencheurs : `pull_request`, `push` sur toutes les branches (pas sur les tags), lancement
manuel. Un nouveau push annule le run en cours de la même référence. Permission unique :
`contents: read`. Aucun secret.

| Job | Étapes |
|---|---|
| Version et outillage | `git fetch --tags`, puis `node scripts/check-version.mjs` : sur une PR avec `--base origin/<base de la PR>` (HEAD est le commit de fusion préparé par GitHub) ; sur un push de `main` avec `--base <commit d'avant le push>` ; sur un push d'une autre branche, contre `origin/main`. Non lancé sur un lancement manuel. Puis `node scripts/check-agents.mjs` et `node --test scripts/*.test.mjs` |
| Flutter et brewing | Flutter 3.44.6. Dans `brewing/` : `dart pub get`, `pubspec.lock` à jour, `dart analyze --fatal-infos`, `dart format` vérifié, `dart test`. Dans `app/` : `flutter pub get`, `pubspec.lock` à jour, `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test`, `flutter test`, `flutter build web --release` sans configuration Firebase |
| Règles — émulateur | Node 22, Java 21 (Temurin), `npm ci` et `npm test` dans `rules-tests/` (projet `demo-kassbeer`). Binaires de l'émulateur en cache |
| Android — compilation | quand le diff touche `app/pubspec.yaml`, `app/pubspec.lock` ou `app/android/`, et toujours sur un lancement manuel : `flutter build apk --release`, Java 17, signé par une clé jetable générée par `keytool` dans le job. Sinon le job réussit sans compiler |

Une branche de travail qui n'a pas encore incrémenté sa version est rouge au job Version :
le contrôle porte sur ce qui sera fusionné. Une branche avec une PR ouverte tourne deux fois
par push (`push` et `pull_request`). Les minutes des runners standard sont gratuites sur un
dépôt public (ADR-002).

Les actions sont épinglées par SHA de commit, version en commentaire, aux mêmes SHA que
Kass'Dalle.

### `deploy.yml` — déploiement

Déclencheurs : fin du workflow CI (`workflow_run`) en succès, sur un `push` de `main`, dans
ce dépôt ; lancement manuel, accepté sur `main` seulement. Un déploiement à la fois, jamais
annulé. Aucun déclencheur `pull_request` ni `pull_request_target` (P14).

| Job | Environnement, droits | Ce qu'il fait |
|---|---|---|
| `gate` | aucun, `contents: read` | vérifie que le commit est la tête de `main` ; sinon s'arrête en vert |
| `plan` | `production`, `id-token: write` | vérifie la configuration ; lit la version de `app/pubspec.yaml` ; obtient un jeton Google de 5 minutes ; lit la dernière version publiée sur App Distribution et décide s'il faut un nouvel APK |
| `build` | `production`, `contents: read` | build web et, si besoin, APK signé, avec `--dart-define-from-file` ; dépose les deux en artefacts conservés un jour |
| `deploy` | `production`, `id-token: write` | revérifie la tête de `main` ; installe `firebase-tools` depuis `rules-tests/package-lock.json` avant l'authentification ; `firebase deploy --only hosting,firestore:rules,firestore:indexes` ; publie l'APK sur App Distribution |

Le code compilé (dépendances pub, Gradle) tourne dans `build`, qui n'a pas de jeton OIDC.
Les jobs qui ont un accès à Google Cloud ne compilent rien.

**Configuration absente.** Les variables obligatoires sont `GCP_WORKLOAD_IDENTITY_PROVIDER`,
`GCP_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID`, `FIREBASE_ANDROID_APP_ID` et chaque clé de
`app/firebase.env.example.json`. Tant qu'aucune d'elles n'existe dans
l'environnement `production`, `plan` affiche « Déploiement non configuré » et le workflow
s'arrête en vert, sans rien déployer. Une configuration incomplète (au moins une variable
posée, une autre absente) fait échouer `plan` avec la liste des variables manquantes. Un
secret de signature absent fait échouer `build` avant tout déploiement, quand un APK est à
construire.

**Nouvel APK.** `plan` compare le numéro de build `N` de `app/pubspec.yaml`
(`X.Y.Z+N`) au `buildVersion` de la dernière version publiée sur App Distribution (API
`firebaseappdistribution.googleapis.com/v1/…/releases`). Un APK se construit quand aucune
version n'est publiée, quand `N` est plus grand, ou quand la dernière version publiée a
expiré. Une réponse de l'API autre que 200 arrête le déploiement. P7 garantit que `N` monte
à chaque version.

**Configuration Firebase du client.** `app/firebase.env.example.json` liste les clés que
l'application lit par `String.fromEnvironment` (`app/lib/firebase_options.dart`). `build`
écrit dans `$RUNNER_TEMP` un fichier JSON qui contient ces clés, et seulement elles, chacune
avec la variable GitHub du même nom, puis le passe à `flutter build web` et
`flutter build apk` par `--dart-define-from-file`. Le fichier est supprimé à la fin du job.
Ces valeurs sont la configuration publique du client, pas des secrets. Une clé ajoutée à
`firebase.env.example.json` devient une variable obligatoire de l'environnement
`production`.

**Clé de signature.** Les quatre secrets ne sont lus que dans `build`. Le keystore est
décodé dans `$RUNNER_TEMP`, `app/android/key.properties` (`storeFile`, `storePassword`,
`keyAlias`, `keyPassword`) est écrit dans le runner, puis les deux sont supprimés à la sortie
de l'étape, réussite ou échec.

### Réglages sur GitHub

Environnement `production` (Settings › Environments) : branches de déploiement limitées à
`main` (« Selected branches and tags », règle `main`). Sans relecteur requis : un relecteur
requis demanderait trois approbations par déploiement (`plan`, `build`, `deploy`). Sans
contournement par un administrateur (« Allow administrators to bypass configured protection
rules » décoché, `can_admins_bypass: false`) : un workflow lancé depuis une autre branche
que `main` ne lit pas les secrets de signature, même lancé par le propriétaire. Un `PUT` de
l'environnement par l'API doit contenir `deployment_branch_policy` : sans ce champ, GitHub
retire la règle de branche.

Variables de l'environnement `production` :

| Variable | Obligatoire | Valeur |
|---|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | oui | `projects/<numéro du projet>/locations/global/workloadIdentityPools/github/providers/kassbeer-deploy` |
| `GCP_SERVICE_ACCOUNT` | oui | `github-deploy@<identifiant du projet>.iam.gserviceaccount.com` |
| `FIREBASE_PROJECT_ID` | oui | identifiant du projet Firebase ; sert aussi à `firebase deploy --project` |
| `FIREBASE_MESSAGING_SENDER_ID` | oui | `messagingSenderId` (numéro du projet) |
| `FIREBASE_WEB_API_KEY` | oui | `apiKey` de l'application web (console Firebase › Paramètres du projet) |
| `FIREBASE_WEB_APP_ID` | oui | `appId` de l'application web (`1:<numéro>:web:<hex>`) |
| `FIREBASE_AUTH_DOMAIN` | oui | `authDomain` de l'application web (`<identifiant>.firebaseapp.com`) |
| `FIREBASE_ANDROID_API_KEY` | oui | `current_key` de `google-services.json` |
| `FIREBASE_ANDROID_APP_ID` | oui | `mobilesdk_app_id` de l'application Android (`1:<numéro>:android:<hex>`) ; sert aussi à App Distribution |
| `GOOGLE_SERVER_CLIENT_ID` | oui | identifiant du client OAuth de type « Web » créé par Firebase Auth (`…apps.googleusercontent.com`), demandé par `google_sign_in` sur Android |

Les huit dernières lignes suivent `app/firebase.env.example.json` à la date de ce document ;
le fichier fait foi.

Secrets de l'environnement `production` :

| Secret | Contenu |
|---|---|
| `KEYSTORE_BASE64` | le fichier `.jks` de release en base64, sur une ligne |
| `KEYSTORE_PASSWORD` | mot de passe du keystore |
| `KEY_ALIAS` | alias de la clé |
| `KEY_PASSWORD` | mot de passe de la clé : le même que `KEYSTORE_PASSWORD` (keystore PKCS12) |

Avec la CLI GitHub, depuis le poste :

```bash
REPO=ChinaFred/KassBeer
gh variable set FIREBASE_PROJECT_ID --repo "$REPO" --env production --body "<identifiant>"
# … une commande par variable du tableau
KS=~/kassbeer_release.jks                            # hors du dépôt
keytool -genkeypair -keystore "$KS" -storetype PKCS12 -alias kassbeer \
  -keyalg RSA -keysize 2048 -validity 10000          # une fois ; copie hors ligne (ADR-001)
base64 -w0 "$KS" | gh secret set KEYSTORE_BASE64 --repo "$REPO" --env production
gh secret set KEYSTORE_PASSWORD --repo "$REPO" --env production   # saisie masquée
gh secret set KEY_ALIAS --repo "$REPO" --env production --body kassbeer
gh secret set KEY_PASSWORD --repo "$REPO" --env production        # saisie masquée, même mot de passe
keytool -list -v -keystore "$KS" -alias kassbeer     # SHA-1 et SHA-256 (P8)
```

Le dépôt est public depuis le 2026-11-07 (ADR-002). Deux rulesets sont posés (Settings ›
Rules), sans liste de contournement. Sur `main` : PR requise, 0 approbation, fusion par
commit de fusion seule, branche à jour avec `main`, ni force push ni suppression, et les
quatre contrôles « Version et outillage », « Flutter et brewing — analyse, format, tests,
build web », « Règles — émulateur » et « Android — compilation ». Le job Android réussit
sans compiler quand le diff ne touche pas Android : il peut être exigé. Sur les
tags `v*` : ni suppression, ni mise à jour, ni force push. Seul le propriétaire a le droit d'écrire sur le
dépôt. Un `deploy.yml` modifié et fusionné sur `main` obtient l'accès du compte
`github-deploy`, qui peut publier des règles Firestore : P10 et P14 s'appliquent à chaque
diff de `.github/workflows/`.

Autres réglages : approbation des workflows pour tout contributeur externe (Settings ›
Actions › General) ; actions limitées à celles de GitHub, `subosito/flutter-action` et
`google-github-actions/auth`, épinglées par SHA ; secret scanning et push protection ;
alertes Dependabot ; signalement privé de failles ; suppression automatique des branches
fusionnées ; Projects désactivé ; fusion squash et rebase désactivées ; environnement
`production` sans contournement par les administrateurs.

### Workload Identity Federation (Google Cloud)

GitHub échange le jeton OIDC du job contre un accès temporaire au compte de service
`github-deploy`. Aucune clé JSON n'est créée ni stockée (P14). Commandes à lancer une fois,
par un compte propriétaire du projet, après la création du projet Firebase :

```bash
PROJECT_ID=<identifiant du projet Firebase>
REPO=ChinaFred/KassBeer
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
REPO_ID=$(gh api "repos/$REPO" --jq .id)        # identifiant numérique, stable
SA="github-deploy@$PROJECT_ID.iam.gserviceaccount.com"
gcloud config set project "$PROJECT_ID"

gcloud services enable iamcredentials.googleapis.com sts.googleapis.com \
  firebasehosting.googleapis.com firebaserules.googleapis.com firestore.googleapis.com \
  firebaseappdistribution.googleapis.com

gcloud iam service-accounts create github-deploy --display-name "Déploiement GitHub"
for role in roles/firebasehosting.admin roles/firebaserules.admin \
            roles/datastore.indexAdmin roles/firebaseappdistro.admin \
            roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$SA" --role "$role" --condition=None
done

gcloud iam workload-identity-pools create github --location=global \
  --display-name "GitHub Actions"
gcloud iam workload-identity-pools providers create-oidc kassbeer-deploy \
  --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref,attribute.environment=assertion.environment,attribute.workflow_ref=assertion.workflow_ref" \
  --attribute-condition="assertion.repository_id=='$REPO_ID' && assertion.ref=='refs/heads/main' && assertion.environment=='production' && assertion.workflow_ref=='$REPO/.github/workflows/deploy.yml@refs/heads/main'"

gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository_id/$REPO_ID"

echo "GCP_WORKLOAD_IDENTITY_PROVIDER=projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/kassbeer-deploy"
echo "GCP_SERVICE_ACCOUNT=$SA"
```

Le pool `github` ne garde qu'un fournisseur : la liaison `workloadIdentityUser` porte sur
tout le pool, et un second fournisseur à la condition plus large obtiendrait aussi
`github-deploy`. La condition du fournisseur n'admet qu'un jeton de ce dépôt (identifiant numérique : un
dépôt recréé sous le même nom ne passe pas, ADR-002), de `main`, de l'environnement
`production`, et du fichier `deploy.yml`. Les cinq rôles du compte de service couvrent Hosting, les règles,
les index et App Distribution ; il ne lit ni n'écrit les données Firestore. Si la CLI
Firebase refuse un déploiement pour une permission manquante, ajouter le rôle que nomme le
message d'erreur, pas un rôle large comme `roles/firebase.admin`.

### Firebase App Distribution

À faire une fois dans la console Firebase (fait le 2026-11-07, voir « État de la production ») :

- ajouter l'application Android, avec l'`applicationId` de
  `app/android/app/build.gradle.kts`, et y enregistrer les empreintes SHA-1 et SHA-256 de
  la clé de release (P8 : sans elles, la connexion Google échoue sur l'APK signé) ;
- App Distribution : choisir l'application Android en haut de la page et cliquer sur
  « Commencer ». Sans ce clic, l'API des versions répond 404 (« Requested entity was not
  found »), même au propriétaire du projet, et le job `plan` de `deploy.yml` échoue ;
- App Distribution › Testeurs et groupes : créer le groupe d'alias `brasseurs` et y ajouter
  l'e-mail de chaque brasseur.

Chaque nouvel APK part vers ce groupe, avec en notes de version la version, le commit et
l'entrée de cette version dans `CHANGELOG.md`. Le testeur reçoit un e-mail, puis installe
par l'application App Tester ou par le lien.

### Firebase Auth et clés d'API

Réglages faits à la main dans les consoles Firebase et Google Cloud, après la création du
projet. Rien dans le dépôt ne les garde : les vérifier à chaque création de projet.

- **Fournisseurs** (Firebase › Authentication › Sign-in method) : Google seul. Désactiver
  « Adresse e-mail/Mot de passe » et « Anonyme ». Les règles refusent déjà un autre
  fournisseur (P11) ; le désactiver empêche aussi la création de comptes inutiles.
- **Domaines autorisés** (Authentication › Settings) : `<projet>.web.app`,
  `<projet>.firebaseapp.com` et `localhost` seulement. Retirer tout autre domaine.
- **Clé d'API web** (Google Cloud › API et services › Identifiants) : restriction
  « Sites web » aux référents `https://<projet>.web.app/*` et
  `https://<projet>.firebaseapp.com/*`, plus `http://localhost:*/*` pour `flutter run -d chrome`
  sur le poste ; restriction d'API aux API Firebase utilisées
  (Identity Toolkit, Token Service, Cloud Firestore, Firebase Installations).
- **Clé d'API Android** : restriction « Applications Android » au paquet
  `fr.kassbeer.kass_beer` et à l'empreinte SHA-1 de la clé de release (la même que celle
  enregistrée pour App Distribution, P8), plus la SHA-1 de débogage du poste pour
  `flutter run` sur un téléphone. Cette empreinte s'enregistre aussi sur l'application
  Android de Firebase. La retirer des deux quand le développement sur téléphone ne s'en
  sert plus : le keystore de débogage a un mot de passe connu (`android`).
- **Client OAuth Web** : son identifiant est `GOOGLE_SERVER_CLIENT_ID` ; ne pas le
  supprimer, `google_sign_in` en dépend sur Android.

### État de la production

Réglages en place le 2026-11-07. Les identifiants ci-dessous sont la configuration publique
du client, pas des secrets.

| Élément | Valeur |
|---|---|
| Projet Firebase | `kassbeer`, numéro `647125623341`, plan Blaze (compte de facturation « Paiement de Firebase ») |
| Budget | « Kass'Beer 5 EUR », filtré sur ce projet, alertes à 50 %, 90 % et 100 % |
| Firestore | `(default)`, `europe-west1`, mode natif, protection contre la suppression ; sauvegarde quotidienne gardée 7 jours |
| Règles Firestore | publiées par `deploy.yml` le 2026-11-07 (run 42381643401) |
| Premier déploiement | 2026-11-07, run 42381643401 : site web, règles et index, APK 0.1.2+3 sur App Distribution |
| Application web | `1:647125623341:web:c4c47bf56841e8f2100ea4`, site Hosting `kassbeer` (`https://kassbeer.web.app`) |
| Application Android | `1:647125623341:android:6b006c09c09d1c04100ea4`, paquet `fr.kassbeer.kass_beer` |
| Empreintes Android | clé de release : SHA-1 `49:62:50:82:6C:FB:E0:9C:E7:5F:58:E8:EA:37:2B:8C:EC:DB:16:32` et SHA-256 `2E:8A:7C:16:A7:E3:9A:D2:D4:37:93:AE:B0:D8:9E:E8:2C:C0:A2:1A:96:30:84:31:C1:95:DE:AE:B8:58:D1:8B` (P8) ; clé de débogage du poste du brasseur : SHA-1 `A0:36:FC:AF:DA:88:32:44:6E:F8:5F:42:EE:81:E2:49:EB:91:02:59` |
| Firebase Auth | Google seul ; domaines autorisés `localhost`, `kassbeer.firebaseapp.com`, `kassbeer.web.app` |
| Clé d'API web | référents `https://kassbeer.web.app/*`, `https://kassbeer.firebaseapp.com/*`, `http://localhost:*/*` ; API Identity Toolkit, Token Service, Firestore, Firebase Installations |
| Clé d'API Android | paquet `fr.kassbeer.kass_beer` avec l'une des deux SHA-1 ci-dessus ; mêmes quatre API |
| Premier admin | `members/{e-mail Google de l'administrateur}`, rôle `admin`, `invited_by` = `console`, créé hors de l'application |
| App Distribution | ouvert pour l'application Android ; groupe `brasseurs`, un testeur (l'admin) |
| Workload Identity Federation | pool `github`, fournisseur `kassbeer-deploy`, compte de service `github-deploy`, cinq rôles |
| GitHub, environnement `production` | règle de branche `main` posée ; les dix variables et les quatre secrets de signature posés |
| Plan GitHub | Free, dépôt public depuis le 2026-11-07 (ADR-002). Minutes des runners standard gratuites. Le run 42366279942 a lu 9 variables de `production` sur 10, avant la pose des secrets ; le run 42381643401 a lu les 10 variables et les 4 secrets |
| GitHub, rulesets | `main` : PR requise, 0 approbation, fusion par commit de fusion, quatre contrôles requis, à jour avec `main`, ni force push ni suppression ; tags `v*` : ni suppression ni mise à jour ; aucun contournement |
| GitHub, sécurité | approbation des workflows pour tout contributeur externe, actions limitées et épinglées par SHA, secret scanning, push protection, alertes Dependabot, signalement privé de failles |

Les secrets de signature se posent par les quatre commandes `gh secret set` de
« Réglages sur GitHub », les deux mots de passe en saisie masquée. Un secret absent fait
échouer le job `build`, avant toute mise en ligne (« Secrets absents de l'environnement
production »).

### Poste de développement

| Outil | Version | Rôle |
|---|---|---|
| Flutter | 3.44.6 | `app/` et `brewing/` |
| JDK | Temurin 21, dans `JAVA_HOME` | émulateur Firestore de `rules-tests/` |
| JDK de Gradle | celui d'Android Studio (JBR 21), réglé par `flutter config --jdk-dir` | `flutter build apk` |
| SDK Android | plateforme 36, build-tools 36.1.0 | licences à accepter une fois par `flutter doctor --android-licenses` (commande interactive) |
| Node | 22, comme la CI et `engines` de `rules-tests/` | `rules-tests/`, `scripts/` |
| CLI Firebase | celle de `rules-tests/node_modules/.bin/` (15.35.0) | émulateur, commandes de projet |
| `gcloud`, `gh` | connectés au compte du brasseur | réglages Google Cloud et GitHub |

Fichiers locaux, jamais versionnés :

- `app/firebase.env.json` : copie de `app/firebase.env.example.json`, chaque clé avec la
  variable GitHub du même nom. Sans lui, l'application affiche « Configuration Firebase
  absente ».
- `app/android/key.properties` : `storeFile` (chemin absolu du keystore, hors du dépôt),
  `storePassword`, `keyAlias` (`kassbeer`), `keyPassword`.
- Le keystore de release et son mot de passe vivent hors du dépôt, sur le poste du
  brasseur, avec une copie hors ligne et le mot de passe dans un gestionnaire de mots de
  passe (ADR-001). Une clé perdue empêche toute mise à jour de l'APK installé.

## Intégrations et services tiers

## Coûts variables
