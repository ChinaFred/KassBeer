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
| `lib/app.dart` | `KassBeerApp` (thème, routeur), `MissingConfigurationApp`, `StartupFailureApp` ; les trois portent `locale: fr` et les délégués `Global*` (`flutter_localizations`) |
| `lib/firebase_options.dart` | `FirebaseEnv` : configuration lue par `String.fromEnvironment` |
| `lib/core/providers.dart` | providers des services, fournis par `main.dart` ou par les tests |
| `lib/core/services/error_report_service.dart` | `ErrorReportService`, `ErrorReportFields` |
| `lib/core/router/` | `routes.dart` (chemins), `app_router.dart` (routeur, `redirectFor`) |
| `lib/core/router/page_de_coquille.dart` | `PageDeCoquille` : route de la coquille qui donne le titre de la barre du haut et le chemin du bouton retour ; `PageDeCoquilleDynamique` : retour calculé depuis le chemin (préparation d'un brassin) |
| `lib/core/data/lecture_document.dart` | `LecteurChamps` (lecture stricte d'un document, `DocumentIllisible` sans valeur par défaut), `champFacultatif` (absent à la création, `FieldValue.delete()` à la modification), `libelleAuteur`, `ListeLue` (documents lus et `fromCache`), `RechercheDocument` (trouvé, illisible, absent du serveur, absent du cache), `CreationEnCours` |
| `lib/core/presentation/` | `AppShell` (rail défilable ; titre et retour reçus de la route), `breakpoints.dart` (seuils 600 / 840 et largeurs `kFormMaxWidth` 400, `kDialogMaxWidth` 480, `kMessageMaxWidth` 480, `kAccountMenuMaxWidth` 280, `kContentMaxWidth` 840, `kEditorMaxWidth` 920, `kCalculationPanelWidth` 340, `kCalculationTileMinWidth` 120 à multiplier par l'échelle du texte, `kCompactMaxHeight` 480, `kBrewDayActionsMaxWidth` 480, `kBrewDayChronologyMaxWidth` 480, `kBrewDayMaxWidth` 1200, `kReleveChampMinWidth` 140 et `kComparaisonValeurMinWidth` 96, à multiplier par l'échelle du texte), `etats.dart` (`EtatChargement`, `EtatVide` avec action facultative, `EtatErreur` avec libellé de nouvelle lecture, `IndicateurBouton`), `BandeauHorsLigne`, `BandeauListePerimee`, `Etiquette`, `showFeuilleOuDialogue`, `formats.dart` (affichage à la française, `lireNombre`, `erreurNombre`), `ChampNombre` (mode entier, minimum), `PageDocument` (états d'une page de document), `EditeurPleinEcran` et `montrerChamp` (défilement vers le premier champ en erreur), `ecriture.dart` (`suivreEcriture`, `annoncerRefus`, `annoncerAvecAnnulation`, confirmations d'abandon, de suppression et `confirmerAction`), `fiche.dart` (`LigneFiche`, `TitreSection`, `LigneDeuxNiveaux`, `TexteAbsent`, `SectionRepliable`), `LigneEditeur` (ligne d'une liste d'éditeur avec menu ⋮), `LogoKassBeer` |
| `lib/core/services/screen_wakelock.dart` | `ScreenWakelock` (verrou compté, une remontée d'erreur par session), `KeepScreenAwake` |
| `lib/core/theme/app_theme.dart` | thème Material 3, seul fichier où une couleur est écrite |
| `lib/features/auth/` | `AuthRepository` (Firebase Auth, Google, `currentTokenName`), état d'accès, `grantedAccessProvider`, écrans Chargement, Connexion, Compte non invité, Erreur |
| `lib/features/members/` | `MembersRepository` (`members/`), `Member`, Admin › Membres |
| `lib/features/equipment/` | `EquipmentRepository` (`equipment/`), `Equipment`, `EquipmentContent`, `EquipmentKind` ; liste, fiche, éditeur |
| `lib/features/recipes/` | `RecipesRepository` (`recipes/`, `updateBrewSteps`, `newStepKey`) ; `domain/recipe.dart` : `Recipe`, `RecipeContent` et ses lignes, conversion document ↔ `brewing/`, tri, duplication ; `domain/chronologie.dart` : `BrewStepLine`, lecture et validation de `brew_steps`, durées dérivées ; liste, fiche, éditeur, éditeur de chronologie, `ContenuRecette` (sections partagées avec le brassin), formulaires des lignes, vue des calculs |
| `lib/features/brews/` | `BrewsRepository` (`brews/`, `brews/{id}/events/`, jamais de transaction), `Brew`, `BrewEvent`, `BrewStatus`, `MeasureType`, `PhaseEvenement` ; `domain/mesures_retenues.dart` (mesures retenues, VR1, VR2, RR2), `domain/releves.dart` (regroupement du relevé) ; liste, fiche, « Nouveau brassin », `presentation/releve_fermentation.dart`, `prevu_et_mesure.dart`, `embouteillage.dart`, `courbe_fermentation.dart`, `trace_courbe.dart` (seul import de `fl_chart`, P18) |
| `lib/features/brew_day/` | `PlanDuJour` (chronologie dérivée par `brewing/`), `AlerteMinuteur` (canal `fr.kassbeer/alert`, Web Audio), écran du jour, « Préparer le brassage », formulaire de mesure, `IndicateurEnvoi`, `RepriseBrassage` |
| `lib/features/admin/` | écran Admin |

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
| `errorReportServiceProvider`, `authRepositoryProvider`, `membersRepositoryProvider`, `recipesRepositoryProvider`, `equipmentRepositoryProvider`, `brewsRepositoryProvider`, `appVersionProvider` | `Provider` | services fournis par `main.dart` (`overrides`) ou par les tests ; sans valeur par défaut |
| `sessionUserProvider` | `StreamProvider<SessionUser?>` | `authStateChanges()` |
| `memberLookupProvider(emailKey)` | `StreamProvider.family<MemberLookup, String>` | `members/{email en minuscules}`, avec les métadonnées |
| `accessStateProvider` | `Provider<AccessState>` | `AccessLoading`, `AccessSignedOut`, `AccessNotInvited`, `AccessFailed`, `AccessGranted(user, member, offline)` |
| `accessRefreshingProvider` | `Provider<bool>` | nouvelle lecture en cours (boutons « Réessayer », « Vérifier à nouveau ») |
| `membersListProvider` | `StreamProvider.autoDispose<List<Member>>` | `members/` entier, admin seul |
| `grantedAccessProvider` | `Provider<AccessGranted?>` | membre connecté (uid, nom, `offline`), `null` pendant une transition |
| `recipesListProvider` | `StreamProvider.autoDispose<ListeLue<Recipe>>` | `recipes/` entier, avec `fromCache` |
| `equipmentListProvider` | `StreamProvider.autoDispose<ListeLue<Equipment>>` | `equipment/` entier, avec `fromCache` |
| `brewsListProvider` | `StreamProvider.autoDispose<ListeLue<Brew>>` | `brews/` entier, avec `fromCache` |
| `brewEventsProvider(brewId)` | `StreamProvider.autoDispose.family<ListeLue<BrewEvent>, String>` | saisies d'un brassin, `hasPendingWrites` par document |
| `horlogeProvider` | `Provider<DateTime Function()>` | heure de l'appareil, injectée en test ; source de toute durée du minuteur |
| `screenWakelockProvider`, `alerteMinuteurProvider` | `Provider` | verrou d'écran, alerte de fin de minuteur |
| `preparedBrewsProvider`, `planReportsProvider`, `repriseTraiteeProvider` | `Provider` | mémoire de session, jamais écrite : brassins préparés, anomalies déjà rapportées, reprise au lancement traitée |
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

**Recettes et équipements.** `FirestoreRecipesRepository` et `FirestoreEquipmentRepository`
écoutent la collection entière avec `includeMetadataChanges: true` et rendent une
`ListeLue` : chaque document lu, ou illisible, et `fromCache`. Un document illisible
(champ obligatoire absent, type inattendu, valeur stockée inconnue comme `extract`) est
rapporté (`recipes.read`, `equipment.read`) et s'affiche « Recette illisible » : aucune
valeur par défaut ne le complète. Les fiches et les éditeurs cherchent leur document dans
cette liste : absent d'une lecture du serveur, il « n'existe pas ou a été supprimé » ; absent
du cache seul, la page attend le serveur en ligne et affiche « indisponible hors ligne » hors
ligne (`AccessGranted.offline`). Les fiches lisent aussi la liste des équipements (calculs)
et la fiche d'un équipement celle des recettes (annonce E9).

Écritures, toutes faites dans le cache dès l'appel. Créer, modifier et dupliquer attendent
d'abord le nom du jeton, 3 s au plus (« Nom de l'auteur ») ; puis l'écran se ferme sans
attendre le serveur. Supprimer n'attend rien :

| Action | Écriture |
|---|---|
| Créer | `doc()` (identifiant créé par l'appareil, connu avant la réponse du serveur), `set` des champs saisis, `owner_uid`, `owner_name` s'il existe, `created_at` et `updated_at` = `serverTimestamp()` |
| Modifier | `update` des champs saisis, `owner_name` réécrit ou retiré, `updated_at` = `serverTimestamp()` ; ni `owner_uid` ni `created_at` ne sont écrits. Un champ vidé est retiré (`FieldValue.delete()`) |
| Dupliquer | création d'une copie de `RecipeContent.duplicate()` au nom du lecteur ; la source n'est pas écrite |
| Supprimer | `delete` ; une recette qui cite un équipement supprimé n'est pas écrite |

`written` (création) ou la Future rendue se termine à la réponse du serveur ; un refus est
rapporté par le dépôt, puis annoncé par `suivreEcriture` (« L'enregistrement de « {nom} » a
échoué. »). Aucun écran n'écrit un état propre au lecteur : la recherche et le filtre « Les
miennes » restent dans l'écran, les calculs se recalculent à chaque affichage.

**Nom de l'auteur.** Avant d'enregistrer, l'écran lit `AuthRepository.currentTokenName()` :
`(await user.getIdTokenResult()).claims['name']`, la valeur que les règles comparent à
`owner_name` (`displayName` peut en différer jusqu'au rafraîchissement du jeton). Nom absent
ou vide, ou plus long que 80 caractères (`kOwnerNameMaxLength`, sans quoi les règles
refuseraient toute écriture de ce compte) : champ absent à la création, retiré à la
modification. « Dupliquer » ignore un second appui pendant cette attente. Lecture du jeton
impossible
ou plus longue que 3 s (`kTokenNameWait`, jeton expiré hors ligne) : l'erreur est rapportée
(`auth.token_name`) et l'enregistrement part sans nom au lieu d'attendre le réseau.

**Brassins et jour de brassage.** `FirestoreBrewsRepository` écrit dans le cache dès
l'appel ; les `Future` rendues se terminent à la réponse du serveur. Aucune transaction, aucun
`Source.server` sur le code de l'écran du jour (P2) ; `Source.server` n'apparaît que dans
`deleteWithEvents`, appelée depuis la fiche.

| Action | Écriture |
|---|---|
| Nouveau brassin | `doc()`, `set` seul (un brassin s'écrit avant tout événement : la règle d'un événement le lit par `get()`), `status: planned`, `recipe_snapshot`, `equipment_snapshot`, `owner_name` s'il existe |
| Modifier | `update` de `name`, `planned_for`, `notes`, `owner_name`, `updated_at` |
| Commencer le brassage | `WriteBatch` : `status: brewing`, `brewed_at` (heure de l'appareil), `owner_name`, et le premier `step_started` si la première étape a une durée |
| Début, fin, saut d'étape | `set` d'un événement (`writeSteps`) ; `WriteBatch` pour « Terminer et commencer » et une étape de 0 min (`step_started` + `step_ended`). « Les sauter et commencer » : chaque `step_skipped` en écriture simple, l'une après l'autre, puis le début : un lot de plus de 20 événements ferait plus de 20 `get()` dans les règles |
| Terminer le brassage | `update` : `status: fermenting`, `owner_name` |
| Mesure, note | `set` (`addEvent`), identifiant créé par l'appareil, `measured_at` = heure de l'appareil |
| Corriger | `update` de `value`, `note`, `measured_at` |
| Annuler (SnackBar, début, fin, mesure) | `delete` ; « Annuler » réécrit le même identifiant et la même heure (`restoreEvent`) |
| Supprimer un brassin | sans saisie : `delete`, hors ligne compris ; avec saisies : réseau exigé (`Source.server`), les événements un par un par écritures simples, puis le brassin, sans lot (un lot de plus de 20 `get()` de règles peut être refusé) |

`owner_name` : toute écriture sur `brews/{id}` réécrit le champ avec le nom actuel du jeton
ou le retire (`FieldValue.delete()`) : `ownerNameOk` s'applique à l'état final et refuserait
un ancien nom, avec le lot qui porte le premier début d'étape. L'écran de préparation, l'écran
du jour et la fiche du brassin (pour son propriétaire, au premier affichage) lisent le nom une
fois, à l'ouverture (3 s au plus), et le réutilisent : le statut part sans attente réseau, et
aucune action ne relit le jeton.

Refus du serveur (HS7) : `creationSuivie` compare avec le document serveur par une lecture
ordinaire (jamais `Source.server`). Si l'événement n'y est pas, le refus est rapporté
(`brews.event_rejected`, nature, type et code, sans valeur), et la `Future` échoue : l'écran
l'affiche. Si l'événement y est (un accusé perdu fait rejouer un `set`, refusé parce que
`created_at` change), le refus est journalisé sous `brews.event_replayed` (aucun `catch`
silencieux) et n'est pas annoncé à l'utilisateur. Limite : un refus reçu après la fermeture
de l'application n'est pas annoncé.

`recomputeSchedule`, `stepRecordsFromEvents` et `readTimer` donnent toutes les heures
(`PlanDuJour`) ; une heure prévue n'est jamais écrite. Heure de l'appareil lue par
`horlogeProvider` ; le `Timer` périodique ne sert qu'à redessiner (P2).

**Alerte de fin de minuteur (ADR-003).** `AlerteMinuteur` : `MethodChannel('fr.kassbeer/alert')`,
méthodes `beep` et `vibrate`, définies dans `MainActivity.kt` (P17). `beep` joue le son de
notification du système, canal `USAGE_ALARM` (il sonne en mode silencieux) ; `vibrate` vibre
environ une seconde (permission `VIBRATE`). Sur le web, garde `kIsWeb` et oscillateur Web Audio
de 300 ms (`package:web`), `AudioContext` créé sur un appui. Aucun fichier ni URL chargé. Bip et
vibration échouent séparément : chacun est rapporté une fois par session (`brew_day.alert_beep`,
`brew_day.alert_vibrate`). L'alerte ne part qu'une fois par
étape, au passage de la durée, écran ouvert, dans les 5 s suivant la fin (un écran rouvert plus
tard ne sonne pas).

**Verrou d'écran (`wakelock_plus`).** Pris à l'ouverture de « Préparer le brassage » et de
l'écran du jour, relâché en quittant, repris au retour d'arrière-plan. Compté par
`ScreenWakelock` ; un échec est rapporté une fois par session (`brew_day.wakelock`). Sur le
web, `no_sleep.js` se charge au premier appel : d'où la prise à l'ouverture, avant la coupure
du réseau.

**Dépendances.** `wakelock_plus` 1.8.2, `flutter_localizations` (SDK), `web` ^1.1.1 (direct,
déjà tiré), `package_info_plus` ^10.2.2. `flutter_localizations` tire `intl` 0.20.2. `fl_chart`
1.3.0 (version exacte, ADR-004) dessine la courbe du relevé et n'ajoute aucun paquet transitif.

**Conversion document ↔ `brewing/`.** Écrite une fois, dans `features/recipes/domain/recipe.dart` :
`fromFirestore` lit chaque ligne par `FermentableKind`, `HopUse` et `HopForm.fromStored` ;
`toFirestore` écrit `storedValue` et la clé `ingredientKey` de chaque ingrédient ; `toInput`
construit le `RecipeInput` de `computeRecipe`. Les masses restent en grammes : la saisie en
kilogrammes des malts et sucres est multipliée par 1 000 dans le formulaire, la durée à cru en
jours par 1 440 (`minutesParJour`). Les autres ajouts (`OtherUse`) et la forme de la levure
(`YeastForm` : `dry`, `liquid`) n'entrent dans aucun calcul et sont lus dans l'application.

**Calculs à l'écran.** `evaluerRecette` appelle `computeRecipe` avec le rendement de
l'équipement de la recette (`EquipementRecette` : aucun, supprimé, indisponible hors ligne,
illisible, en lecture, connu). `libelleManque` choisit le libellé de chaque `MissingInput`.
Une `BrewingInputException` affiche « Calcul impossible : {champ} hors des limites. » ;
elle est rapportée (`recipes.calculation`, nom du champ seul) une fois par recette et par
champ et par session (`calculationReportsProvider`), et non à chaque frappe ni à chaque
lecture. La validation du nom d'un ingrédient (K3) appelle `isValidIngredientName` de
`brewing/`, la même règle que `ingredientKey` : une faute de saisie n'est ni une exception
ni un rapport.

**Saisie.** `lireNombre` refuse plus d'un séparateur décimal et toute valeur non finie (plus de
309 chiffres) ; `erreurNombre` refuse aussi un nombre à partir de 1e9 (`kNombreMaximum`), la
borne des règles, qui l'excluent. Les éditeurs sont des colonnes défilantes (`SingleChildScrollView`), pas des
`ListView` : chaque champ reste construit, donc validé, même hors de l'écran.
`validateGranularly` donne le premier champ en erreur, vers lequel l'éditeur défile ; un nom
manquant reçoit le focus. `LecteurChamps` refuse de même un nombre stocké non fini.

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
| `/recettes`, `/recettes/:id` | liste et fiche des recettes, dans la coquille | membre |
| `/recettes/nouvelle`, `/recettes/:id/modifier` | éditeur de recette, plein écran, hors coquille | membre ; la modification d'une recette d'un autre affiche « Seul l'auteur modifie cette recette. » |
| `/equipements`, `/equipements/:id` | liste et fiche des équipements, dans la coquille | membre |
| `/equipements/nouveau`, `/equipements/:id/modifier` | éditeur d'équipement, plein écran, hors coquille | membre ; même règle que les recettes |
| `/brassins`, `/brassins/:id` | liste et fiche des brassins, dans la coquille | membre |
| `/brassins/:id/preparer` | « Préparer le brassage », dans la coquille, retour vers la fiche | membre ; propriétaire pour commencer |
| `/brassins/:id/jour` | écran du jour, plein écran, hors coquille | propriétaire ; un autre membre lit « Seul le brasseur de ce brassin suit son brassage. » |
| `/recettes/:id/chronologie` | éditeur de chronologie, plein écran | auteur ; sinon « Seul l'auteur modifie cette chronologie. » |
| `/admin` | Admin | admin |
| `/admin/membres` | Admin › Membres | admin |

`redirectFor(access, uri)` (fonction pure, testée) envoie chaque état sur son écran. Un
chemin demandé pendant un écran d'accès est gardé dans `?depuis=` et retrouvé une fois le
membre lu ; seuls les chemins internes (`/…`, pas `//…`) sont suivis, et une page d'Admin ne
s'ouvre pas pour un brasseur. Les éditeurs plein écran sont déclarés avant la coquille :
`/recettes/nouvelle` n'est pas lu comme l'identifiant d'une recette. Chaque page de la coquille
est une `PageDeCoquille` (titre, retour). Un chemin inconnu affiche « Cette page n'existe pas. » et
« Revenir à l'accueil ». Le routeur ne protège aucune donnée : `firestore.rules` le fait.

**Tests.** `app/test/` : écrans et contrôle d'accès avec des doubles des dépôts
(`test/support/fakes.dart`, sans Firebase), `redirectFor`, `ErrorReportFields`,
`FirestoreMembersRepository`, `FirestoreRecipesRepository` et `FirestoreEquipmentRepository`
sur `fake_cloud_firestore` (création, modification sans toucher `owner_uid` ni `created_at`,
`owner_name`, duplication, suppression, refus rapporté, document illisible), conversion
document ↔ `brewing/`, lecture et affichage des nombres, écrans Recettes et Équipements
(états, lecture seule, « À compléter », éditeur), attente du serveur sous `fake_async`,
`FirebaseEnv`, `FirestoreBrewsRepository` sur `fake_cloud_firestore` (copie figée, `owner_name` à chaque écriture, identifiant de l'appareil, HS7), écrans Brassins et écran du jour (minuteur recalculé avec une horloge injectée, double appui, étape sautée, début en double, densité, alerte, verrou, reprise, pastille d'envoi), `AlerteMinuteurPlateforme` (`TestDefaultBinaryMessenger`, P17).

## Modèle de données

Unités du système international : masses en grammes (`_g`), volumes en litres (`_l`),
températures en °C (`_c`), densités en SG décimal, couleur en EBC, durées en minutes
(`_min`), pourcentages de 0 à 100 (`_pct`). Les dates `created_at` et `updated_at` sont
posées par `serverTimestamp()` ; les règles vérifient qu'elles valent l'heure de la requête.

Les règles refusent tout champ de premier niveau absent des listes ci-dessous. Tout nombre
de premier niveau est fini et strictement compris entre -1e9 et 1e9 (`optNumber`) ;
`mash_efficiency_pct` est en plus borné de 0 à 100. Les éléments
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
| `owner_name` | string, facultatif, 1 à 80 caractères : nom de l'auteur affiché au groupe, égal au nom du jeton de celui qui écrit |
| `name` | string, obligatoire, 1 à 120 caractères |
| `style` | string \| null (120) |
| `notes` | string \| null (10 000) |
| `batch_volume_l` | number \| null : volume visé en fermenteur |
| `boil_time_min` | number \| null |
| `equipment_id` | string \| null : profil d'équipement prévu |
| `fermentables` | list<map> \| null (50) : `key`, `name`, `kind` (`grain`, `sugar`), `weight_g`, `ebc`, `yield_pct` |
| `hops` | list<map> \| null (50) : `key`, `name`, `weight_g`, `alpha_pct`, `use` (`boil`, `whirlpool`, `dry_hop`), `time_min` (à cru : jours saisis × 1 440), `form` (`pellet`, `leaf`) |
| `others` | list<map> \| null (50) : épices et ajouts, `key`, `name`, `weight_g`, `use` (`mash`, `boil`, `after_boil`, `fermentation`, `bottling`), `time_min` |
| `yeasts` | list<map> \| null (10) : `key`, `name`, `attenuation_pct`, `form` (`dry`, `liquid`) ; l'éditeur en écrit une au plus |
| `mash_steps` | list<map> \| null (20) : `name`, `temp_c`, `duration_min` |
| `brew_steps` | list<map> \| null (60) : chronologie du jour de brassage, dans l'ordre. Élément : `key` (20 caractères, `doc().id`, créée à l'ajout, stable au renommage et au déplacement, unique dans la recette), `name` (1 à 120), `duration_min` (0 à 600 ; 0 pour une action sans minuteur), `temp_c` (0 à 100 \| null) |
| `imported_from` | string \| null (200) : nom de la fiche Excel d'origine |
| `created_at`, `updated_at` | timestamp, obligatoires |

`key` est la clé d'ingrédient, calculée par `ingredientKey` de `brewing/` à chaque
enregistrement et jamais saisie : préfixe de nature (`malt`, `sucre`, `houblon`, `levure`,
`ajout`) et nom en minuscules, sans accents, chaque suite de caractères hors lettre et chiffre
remplacée par un tiret, sans tiret en bord, 100 caractères au plus (« Pils » → `malt-pils`,
« Sucre candi ambré » → `sucre-candi-ambre`). Le préfixe n'est pas répété quand le nom
commence par lui. Deux lignes de même nom, à la casse près, partagent la clé. Elle relie
l'ingrédient au prix et au stock du lecteur. Densités, degré, IBU, EBC et coût ne sont pas
stockés : `brewing/` les calcule à l'affichage.

Les valeurs `extract` (fermentescible) et `first_wort` (houblon) sont retirées du modèle en
v0.1.7 (arbitrage A5) ; aucune recette n'en contenait. La correspondance avec les enums de
`brewing/` est écrite une seule fois, dans ces enums : `FermentableKind.fromStored`
(`grain` → `malt`, `sugar` → `sugar`), `HopUse.fromStored` (`boil` → `boil`, `whirlpool` →
`afterBoil`, `dry_hop` → `dryHop`), `HopForm.fromStored` (`pellet` → `pellet`, `leaf` →
`whole`), et `storedValue` en sens inverse. Une valeur inconnue lève `BrewingInputException`,
dont `value` est la longueur du texte stocké : écrit par un autre membre, ce texte n'entre
jamais dans `error_reports/`. `OtherUse`, `YeastForm` et `EquipmentKind` de l'application
suivent la même règle (`DocumentIllisible` sans la valeur).
Les règles n'inspectent pas les listes : elles acceptent une valeur retirée, que le dépôt de
données refuse à la lecture par ces fonctions.

`brew_steps` : les règles bornent la liste à 60 éléments, sans lire ses éléments. Le dépôt de
données valide chaque élément (clé présente et unique, nom, durée et température dans leurs
bornes). `brews/{id}/events/{eventId}.step_key` porte la `key` de l'étape. Le préremplissage
vient de `defaultBrewSteps` (voir « Calculs de brassage ») ; changer un palier ensuite ne
change pas la chronologie.

`owner_name` est écrit par l'auteur à chaque enregistrement, depuis le nom que porte son
jeton d'identité (`claims['name']`, voir « Nom de l'auteur ») ; un compte sans nom n'écrit pas
le champ. Une copie (« Dupliquer ») porte le nom de
celui qui copie. Les règles refusent une écriture dont `owner_name` diffère du nom du jeton.
Une modification qui garderait l'ancien nom après un changement de nom Google est donc
refusée : le dépôt réécrit le nom à chaque modification, ou retire le champ quand le nom est
vide.

`owner_name` n'est qu'un libellé d'affichage déclaré par l'auteur. Aucun droit, aucun filtre
(« Les miennes »), aucune suppression, aucun tri (« les miens d'abord ») ne s'appuie dessus :
tout cela utilise `owner_uid`.

### `equipment/{equipmentId}`

Lisible par le groupe (ADR-001, arbitrage 5).

| Champ | Type |
|---|---|
| `owner_uid` | string, obligatoire, immuable |
| `owner_name` | string, facultatif, 1 à 80 caractères : comme dans `recipes/` |
| `name` | string, obligatoire (120) |
| `kind` | string, obligatoire : `multi_vessel` (cuves séparées) ou `all_in_one` (Grainfather) |
| `mash_efficiency_pct` | number \| null : rendement d'empâtage, de 0 à 100 (règles) |
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
| `owner_name` | string, facultatif, 1 à 80 caractères : nom du brasseur affiché au groupe, égal au nom du jeton de celui qui écrit (comme dans `recipes/`) |
| `recipe_id` | string \| null : recette d'origine, immuable |
| `name` | string, obligatoire (120) |
| `status` | string, obligatoire : `planned`, `brewing`, `fermenting`, `conditioning`, `done`, `abandoned`. Le jour de brassage passe de `planned` à `brewing` (premier début d'étape) puis à `fermenting` (« Terminer le brassage »), par des écritures simples ou un `WriteBatch`, jamais une transaction ; les règles ne contrôlent pas l'ordre des statuts |
| `planned_for`, `brewed_at` | timestamp \| null : `brewed_at` = `measured_at` du premier début d'étape. Aucun champ « préparé » ni heure prévue recalculée |
| `recipe_snapshot` | map, obligatoire, immuable : copie de la recette, mêmes champs de premier niveau, `brew_steps` compris (60 éléments au plus) ; `owner_name`, s'il est présent, est une chaîne de 1 à 80 caractères (celui de l'auteur de la recette, pas forcément celui qui brasse) |
| `equipment_snapshot` | map, obligatoire, immuable : copie de l'équipement, mêmes champs de premier niveau ; `owner_name` borné comme dans `recipe_snapshot` |
| `adjustments` | map \| null : ajustements du jour, jamais écrits dans la recette. Clés en liste blanche, chacune number \| null : `batch_volume_l`, `mash_water_l`, `sparge_water_l`, `pre_boil_volume_l`, `post_boil_volume_l`, `fermenter_volume_l`, `boil_off_l_per_h`, `mash_temp_c`, `mash_time_min`, `boil_time_min`, `mash_efficiency_pct`. Chaque valeur est finie et strictement comprise entre -1e9 et 1e9 ; `mash_efficiency_pct` est borné de 0 à 100. Aucune autre clé, donc aucun prix ni coût (P5) |
| `bottles_count` | int \| null : entier de 1 à 9 999 (règles) |
| `bottled_at` | timestamp \| null : date d'embouteillage choisie, heure de l'appareil. Gardé après un retour en arrière ; la reprise d'un abandon s'en déduit (`statutDeReprise`) |
| `packaged_volume_l`, `priming_sugar_g` | number \| null : volume conditionné (au-delà de 0 et jusqu'à 1 000 L), masse totale de sucre de resucrage (0 à 100 000 g), sans calcul ; bornes vérifiées par les règles |
| `priming_sugar_name` | string \| null (80) |
| `og_event_id`, `fg_event_id`, `fermenter_volume_event_id` | string \| null (128) : événement choisi comme densité initiale, densité finale, volume en fermenteur ; nul (champ retiré) = dernière mesure. Identifiants, jamais de valeur. Faits communs au groupe, écrits par le propriétaire |
| `sugars_in_wort` | bool \| null : réponse à « Les sucres étaient-ils dans le moût à cette mesure ? » |
| `notes` | string \| null (10 000) |
| `imported_from` | string \| null (200) |
| `created_at`, `updated_at` | timestamp, obligatoires |

Le rendement réel, le degré mesuré et les écarts se calculent à l'affichage à partir des
événements et de la copie figée, jamais stockés ; aucune migration : un champ absent vaut nul.
Aucun prix ni coût (P5). `MesuresRetenues` lit les identifiants ci-dessus puis applique la règle
automatique (dernière densité du jour, dernière densité de fermentation, dernier volume) ;
hors statut En fermentation, un relevé postérieur au jour de `bottled_at` ne compte pas dans la
densité finale.

### `brews/{brewId}/events/{eventId}`

Un document par mesure, début ou fin d'étape. L'identifiant est créé par l'appareil.
Aucune transaction n'est nécessaire : l'écriture part du cache hors ligne et passe les
règles au retour du réseau.

| Champ | Type |
|---|---|
| `owner_uid` | string, obligatoire : propriétaire du brassin |
| `kind` | string, obligatoire : `step_started`, `step_ended`, `step_skipped` (étape marquée sautée), `measurement`, `note` |
| `step_key` | string \| null, 1 à 100 caractères, jamais vide : `key` d'une étape de `brew_steps` ; nul quand la mesure ou la note ne porte sur aucune étape |
| `measure_type` | string \| null : `temperature` (°C), `gravity` (SG), `volume` (L), `ph` |
| `value` | number \| null |
| `note` | string \| null (2 000) |
| `measured_at` | timestamp, obligatoire : heure de l'appareil |
| `created_at` | timestamp, obligatoire : `serverTimestamp()`, audit seul |
| `phase` | string \| null : absent ou nul pour le jour de brassage, `fermentation` pour un relevé ; permis sur `measurement` et `note`, refusé sur un événement d'étape ; immuable |

Forme selon `kind` (règles) :

| `kind` | `step_key` | `measure_type`, `value` | `note` |
|---|---|---|---|
| `step_started`, `step_ended`, `step_skipped` | obligatoire, non vide | absents ou nuls | facultative |
| `measurement` | facultatif : nul pour une mesure sans étape, sinon non vide | type de la liste, valeur numérique dans les bornes de son type (ci-dessous) | facultative |
| `note` | facultatif : nul pour une note sans étape, sinon non vide | absents ou nuls | obligatoire, 1 à 2 000 caractères |

Les bornes de saisie (température 0 à 110 °C, densité 0,980 à 1,200, volume au-delà de 0 et
jusqu'à 1 000 L, pH 0 à 14) sont vérifiées par l'application et par les règles, à la création et
à la correction d'un événement. Les deux jeux de bornes sont identiques, bornes comprises : une
saisie acceptée à l'écran n'est pas refusée au retour du réseau.

Après création, seuls `value`, `note` et `measured_at` se corrigent, et la forme reste
valide : une mesure ne perd pas sa valeur, un début d'étape n'en reçoit pas. « Ne plus
sauter » supprime l'événement `step_skipped`. Deux appareils hors ligne peuvent écrire deux
débuts de la même étape : `stepRecordsFromEvents` garde le plus ancien et rend l'autre comme
« Début en double ».

Le premier début d'étape et le passage à `brewing` partent dans un même `WriteBatch`. La
règle de création d'un événement lit le brassin par `get()`, qui voit l'état d'avant le lot,
où `owner_uid` est déjà celui du brasseur. La création d'un brassin et d'un de ses événements
dans un même lot est refusée pour la même raison : le brassin part d'abord, par une écriture
simple, et la file hors ligne garde l'ordre.

Un relevé est écrit par `addReleve` : un événement par valeur, ou une note seule, dans un
`WriteBatch` (deux `get()` de règles pour un couple densité et température). La note va sur le
premier événement. `correctReleve` met à jour, crée ou supprime chaque valeur dans un lot.
« Embouteiller » écrit les champs, le statut et, si la densité finale est remplie, un relevé à
`bottled_at` dans le même lot ; ce relevé n'est pas recréé par une modification de
l'embouteillage. Hors ligne, aucune de ces écritures n'exige le réseau.

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
| `recipes/`, `equipment/` | membres | membre, à son `owner_uid` ; `owner_name` absent ou égal au nom du jeton (`request.auth.token.name`, 1 à 80 caractères) | propriétaire, `owner_uid` et `created_at` inchangés, `owner_name` comme à la création | propriétaire |
| `brews/` | membres | membre, à son `owner_uid` ; `owner_name` comme dans `recipes/` | propriétaire ; `recipe_id`, `recipe_snapshot`, `equipment_snapshot` inchangés ; `owner_name` comme à la création | propriétaire |
| `brews/{id}/events/` | membres | propriétaire du brassin existant, à son `owner_uid`, forme selon `kind` | auteur : `value`, `note`, `measured_at`, forme gardée | auteur |
| `users/{uid}/**` | propriétaire | propriétaire | propriétaire | propriétaire |
| `error_reports/` | admin | membre, `uid` = le sien, champs en liste blanche et bornés | personne | admin |
| tout autre chemin | refusé | refusé | refusé | refusé |

L'admin n'a aucun droit d'écriture sur le contenu des autres brasseurs.

**Effacement d'un membre retiré (RGPD).** L'application ne permet ni à l'admin ni au membre
retiré de modifier ou de supprimer ses contenus. Une demande d'effacement se traite depuis la
console Firebase ou par l'Admin SDK, avec l'uid du membre : les documents `recipes/` et
`equipment/` dont `owner_uid` vaut cet uid (suppression, ou retrait de `owner_name`), les
brassins `brews/` à son `owner_uid` et leurs `events/`, ses données `users/{uid}/`, et, dans les
brassins des autres membres, les copies `recipe_snapshot` et `equipment_snapshot` qui portent
son `owner_uid` ou son `owner_name`. Le document `members/{email}` est déjà supprimé par le
retrait.

Tests : `rules-tests/` (Node 22, `@firebase/rules-unit-testing`, `node --test`), lancés par
`npm test`, qui démarre l'émulateur Firestore (Java 21) sur le projet `demo-kassbeer`.
Chaque collection est rejouée pour les cinq profils de P4 (anonyme, connecté non membre,
brasseur propriétaire, autre brasseur, admin), plus les comptes invités à l'adresse non
vérifiée ou connectés par mot de passe, et un jeton à l'adresse en majuscules.
`owner_name.test.mjs` ajoute des jetons au nom absent, vide, de 80 et 81 caractères, et non
textuel, pour `recipes/`, `equipment/` et `brews/`, et borne `owner_name` dans les copies des
brassins. `events.test.mjs` rejoue chaque `kind` pour les cinq profils, les formes refusées
de chacun, et l'événement sous un brassin inexistant. `after_brew.test.mjs` rejoue pour les cinq
profils chaque champ d'après brassage, le passage à `abandoned` et aux autres statuts, l'embouteillage
en un `WriteBatch`, `phase` (valeur inconnue, sur un début d'étape, modification refusées), les
bornes de l'embouteillage et celles de `value` selon `measure_type`, en création et en correction.
`brew_day.test.mjs` vérifie `brew_steps`
(60 étapes acceptées, 61 refusées, dans la recette et dans sa copie), les statuts `brewing` puis
`fermenting`, le premier début en un `WriteBatch`, et un brassin créé puis son premier événement. `numbers.test.mjs` vérifie que
les règles refusent Infinity, -Infinity, NaN, ±1e9 et acceptent ±999 999 999, 0 et 1,5, et
borne `mash_efficiency_pct` de 0 à 100 ; `content.test.mjs` fait de même dans `adjustments`.

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
| Notation des fiches | `parseGravity`, `readGravity` | « 1057,9 » et « 1090 » ÷ 1000 ; « 1.052 », « 1,07 » lus tels quels. `readGravity` ne lève pas : il rend `GravityRead(sg)`, `GravityUnreadable()` ou `GravityOutOfRange(sg)`, pour la saisie (une faute de frappe ne va pas dans `error_reports/`). `parseGravity` lève `BrewingInputException`. Seule définition de la règle : `readGravity` |
| Densité initiale prévue | `predictedOriginalGravity` | 1 + Σ (kg × points/kg/L × r) / V / 1000 ; r = rendement d'empâtage pour un malt, 1 pour un sucre |
| Densité finale prévue | `predictedFinalGravity` | 1 + (OG − 1) × (1 − atténuation / 100) ; OG de 1.000 à 1.200 |
| Potentiel d'un malt | `ExtractPotential` | rendement d'extrait % × 385,67 (saccharose, 46,214 ppg), ou points/kg/L |
| Rendement d'empâtage réel | `readMashEfficiency` | (points mesurés × V − points des sucres déjà dans le moût) / points des malts à 100 % |
| Degré | `alcoholByVolume` | (OG − FG) × 131,25 |
| Degré après bouteille | `alcoholByVolumeAfterBottling` | degré + g/L × potentiel du sucre / 10⁶ × 131,25 ; `null` sans donnée de resucrage |
| IBU | `tinsethIbu`, `tinsethIbuForHop` | Tinseth : 1,65 × 0,000125^(Gb − 1) × (1 − e^(−0,04 t)) / 4,15 × alpha (mg/L) ; pellets × 1,1, cônes × 1,0 ; après ébullition et dry hop : 0 |
| Couleur | `moreyColorEbc`, `moreyColorEbcOfGrist` | Morey : MCU = Σ (EBC / 1,97 × lb) / gal ; SRM = 1,4922 × MCU^0,6859 ; EBC = SRM × 1,97 ; la seconde ne prend que masses et couleurs |
| Calculs d'une recette | `computeRecipe` | OG, FG, degré, IBU, EBC, IBU par houblon : voir « Calculs d'une recette » |
| Clé d'ingrédient | `ingredientKey`, `isValidIngredientName` | préfixe de nature + nom normalisé (voir `recipes/`) ; `BrewingInputException` pour un nom sans lettre ni chiffre, que `isValidIngredientName` détecte sans exception (une seule définition de la règle) |
| Coût | `computeCost` | Σ quantité × prix ; par litre = total / V ; bouteille de 33 cl = par litre × 0,33 |
| Planning | `recomputeSchedule` | heure attendue d'une étape = fin de l'étape précédente dans l'ordre de la chronologie (fin enregistrée, sinon début réel + durée prévue). En cours (`running`) : l'étape commencée sans fin au début le plus récent ; elle finit au plus tôt à `now`. Une autre étape commencée sans fin est faite (`done`), à début + durée. Sautée (`skipped`, événement `step_skipped`, sans début) et non faite (`notDone`, sans événement alors qu'une étape plus loin a commencé) : durée nulle. À venir (`pending`) : ne commence ni avant `now`, ni avant la fin de l'étape en cours. Un début l'emporte sur un saut |
| Événements d'étape | `stepRecordsFromEvents` | un `StepRecord` par étape : début le plus ancien (à égalité, le plus petit identifiant), dernière fin à ou après ce début, sauts, et les identifiants d'événement retenus. Sans exception, les autres événements sont rendus en `StepEventIssue` : `duplicateStart`, `duplicateEnd`, `endWithoutStart`, `endBeforeStart`, `unknownStep`, triés par heure puis identifiant. Même résultat sur chaque appareil |
| Chronologie préremplie | `defaultBrewSteps` | une étape par palier ; puis l'ébullition coupée à chaque ajout de houblon d'ébullition, du plus long au plus court (un houblon de t min s'ajoute après durée d'ébullition − t min) ; puis le whirlpool, coupé de même, sur la plus longue durée de ses houblons ; houblons à cru exclus ; ajout de 0 min. Voir ci-dessous |
| Minuteur | `readTimer` | restant = début + durée − `now`, borné à zéro ; dépassement au-delà |

**Pas de valeur de repli.** Un prix manquant rend `CostUnavailable(linesWithoutPrice)`, jamais
un coût partiel. Sans sucre de resucrage, le degré après bouteille est absent : la hausse
forfaitaire de 0,5 % des fiches Excel n'est pas reprise. Les prix sont passés en argument par
l'appelant, qui les lit sous `users/{uid}/` ; le paquet n'en contient aucun.

**Calculs d'une recette.** `computeRecipe(recipe:, mashEfficiencyPercent:)` reçoit la recette
saisie (`RecipeInput` : `FermentableInput`, `HopInput`, `YeastInput`, volume, durée
d'ébullition), dont les données facultatives peuvent manquer, et le rendement d'empâtage de
l'équipement, nul s'il est inconnu. Il rend un `RecipeCalculation` : pour chaque indicateur,
`CalculationComputed(value)` ou `CalculationUnavailable(missing)`. Chaque `MissingInput`
porte une nature (`MissingInputKind`) et les lignes concernées (`IngredientRef` : place et
nom). Le paquet ne contient aucun texte affiché : l'écran choisit le libellé de chaque nature.

| Indicateur | Données demandées |
|---|---|
| Densité initiale (OG) | volume (`batchVolume`), au moins un fermentescible (`fermentables`), rendement d'extrait de chacun (`extractYield`), rendement d'empâtage si un malt est présent (`mashEfficiency`) |
| Densité finale (FG) | OG (`originalGravity`), une levure (`yeast`), atténuation de la première (`yeastAttenuation`) |
| Degré | comme la FG |
| IBU | volume ; sans houblon d'ébullition, 0 IBU ; sinon OG, acides alpha (`hopAlpha`) et durée (`hopBoilTime`) de chaque houblon d'ébullition |
| EBC | volume, au moins un fermentescible, couleur de chacun (`color`) ; pas d'équipement |

`originalGravity` signale qu'un indicateur dépend d'une OG indisponible. Règle de l'IBU, qui
l'emporte sur C8 (« OG en panne ⇒ IBU en panne ») : sans houblon d'ébullition, l'IBU vaut 0 même
quand l'OG est indisponible ; avec un houblon d'ébullition, l'IBU dépend de l'OG.
`missingInputs` rassemble les données à compléter, sans doublon et sans cette dépendance.
`mashEfficiency` ne dit pas pourquoi le rendement manque. L'écran le sait et choisit le
libellé : aucun équipement choisi, équipement supprimé, indisponible hors ligne, ou rendement
non renseigné. La densité d'ébullition de l'IBU est l'OG prévue (`boilGravity`).
`hopBitterness` donne l'IBU de chaque houblon pour « Détail des calculs ».
`hopsLongerThanBoil` liste les houblons d'ébullition plus longs que l'ébullition de la recette
(avertissement U6). Une valeur hors limites (volume nul, pourcentage au-delà de 100, OG prévue
au-delà de 1.200) lève `BrewingInputException`.

**Chronologie préremplie.** `defaultBrewSteps(mashSteps:, boilMinutes:, hops:)` reçoit les
paliers (`MashStepInput` : température et durée facultatives), la durée d'ébullition et les
houblons (`HopInput`). Il rend des `BrewStepDraft` : nature (`BrewStepKind` : `mashStep`,
`boil`, `hopAddition`, `whirlpool`), place du palier ou du houblon d'origine
(`sourceIndex`), durée, température et défaut éventuel (`BrewStepProblem`). Aucune durée
n'est inventée : un palier sans durée rend une étape sans durée (`durationMinutes` nul), qui porte `missingDuration` ; sans
durée d'ébullition, aucune étape d'ébullition, et les ajouts se suivent du plus long au plus
court. Un houblon sans durée est placé en tête de sa section (`missingHopTime`) ; un houblon
d'ébullition plus long que l'ébullition aussi (`hopLongerThanBoil`). Le paquet ne compose
aucun libellé ni aucune clé : l'application nomme l'étape (nom du palier, « Ébullition »,
« Ajouter Cascade 20 g », « Whirlpool ») et lui donne une clé `doc().id` à l'ajout.

**Jour de brassage.** `recomputeSchedule` et `readTimer` sont des fonctions pures qui prennent
`now` en argument : aucun `Timer` n'est la source d'une durée, et les heures recalculées se
dérivent à l'affichage sans s'écrire. L'application lit les événements `step_*` du brassin
(`StepEvent`, `StepEventKind.fromStored`), les réduit par `stepRecordsFromEvents`, puis passe
les enregistrements à `recomputeSchedule`. Une anomalie de la réduction (fin avant le début,
étape inconnue) est rapportée et affichée ; elle ne lève pas. `recomputeSchedule` lève
encore pour une clé en double ou des enregistrements non réduits (étape inconnue ou enregistrée
deux fois). Le constructeur `PlannedStep` lève pour une durée négative.

**Comparaison prévu / mesuré.** `compareBrewWithPlan` (`brew_comparison.dart`) rend pour chaque
ligne la valeur prévue, le résultat mesuré (`MeasuredComputed`, `MeasuredUnavailable` et la liste
des `MeasurementGap`, `MeasuredImpossible`) et l'écart. Elle ne lève que sur une valeur enregistrée
hors limites ; une densité finale supérieure à l'initiale ou des sucres qui expliquent toute la
densité (`readMashEfficiency`, qui ne lève pas) sont des résultats. `fermentationSeries`
(`fermentation.dart`) rend les points d'un relevé triés (`dayNumber` = écart en jours calendaires,
`dayOffset` = ce nombre plus la fraction de la journée locale, un jour de changement d'heure
comptant pour un jour), lus par la liste et par la courbe.

**Fixtures.** `brewing/test/fixtures/*.json` (densité, densité initiale et rendement, densité
finale, degré, IBU, couleur, coût, planning, chronologie préremplie, calculs d'une recette,
comparaison prévu / mesuré, relevé de fermentation) portent des cas tirés des 16 fiches Excel : entrées, valeur de
la fiche, valeur attendue, tolérance, et hypothèses quand la fiche ne donne pas une entrée.
Les erreurs connues des fiches (Citra « 22.4 » lu 22 400 g, degré calculé sur la densité
visée, densités d'en-tête différentes de la chronologie, champs EBC et IBU copiés, coût par
bouteille divisé par le nombre de bouteilles) sont rangées dans `divergences`, sans être
corrigées dans les attentes. Une formule changée ajoute d'abord son cas à la fixture.
`final_gravity.json` prend pour atténuation l'atténuation apparente des densités mesurées de
trois fiches (Ale blonde 140724 : 55,8 %, Twin bottle 4 : 84,1 %, Blonde triple : 98,5 %) et
vérifie que leur FG est retrouvée. `recipe.json` compte 18 cas : un seul est tiré d'une fiche
(`twin-bottle-4-hypothese`), les 17 autres sont synthétiques (données manquantes, cas
limites). Ses valeurs attendues sont calculées hors du paquet.
`planning.json` rejoue la tranche d'empâtage de l'Ale blonde 140724 (colonne « Heure exécution
prévue » retrouvée), puis des cas synthétiques : retard, fin enregistrée, étape sautée, sautée
puis commencée, non faite, retour en arrière, reprise le lendemain (dépassement de 14 h 05),
étapes de 0 min. Sa section `event_cases` réduit des événements : les sept débuts de l'Ale
blonde, deux appareils hors ligne (`double-debut`), des anomalies, deux débuts à la même
minute. `brew_steps.json` compte 8 cas synthétiques de `defaultBrewSteps`, dont l'exemple de
l'ébullition coupée à un ajout de houblon (« Ébullition » 45 min, « Ajouter Cascade 20 g », « Ébullition » 15 min).
`density.json` range chaque lecture refusée en `unreadable` ou `out_of_range`.
`brew_comparison.json` compte un cas par ligne et par donnée manquante, dont l'Ale blonde 140724
(1.052, 20 L) ; ses rendements attendus sont calculés hors du paquet. `fermentation.json` couvre
l'ordre, une densité absente, les deux changements d'heure et deux relevés le même jour.

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

Les actions sont épinglées par SHA de commit, version en commentaire. Depuis la v0.1.6,
toutes tournent sous Node 24 :

| Action | Version |
|---|---|
| `actions/checkout` | v7.0.1 |
| `actions/setup-node` | v7.1.0 |
| `actions/setup-java` | v6.1.0 |
| `actions/cache` | v6.1.0 |
| `actions/upload-artifact` | v7.0.2 |
| `actions/download-artifact` | v8.0.2 |
| `google-github-actions/auth` | v3.0.0 |
| `subosito/flutter-action` | v2.23.0, action composite ; elle appelle `actions/cache@v5` par son étiquette |

`upload-artifact` et `download-artifact` montent ensemble. Les artefacts restent zippés
(`archive` vaut `true` par défaut) : le web s'extrait dans `app/build/web/` et l'APK dans
`$RUNNER_TEMP/apk/`.

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
`google-github-actions/auth` ; secret scanning et push protection ;
alertes Dependabot ; signalement privé de failles ; suppression automatique des branches
fusionnées ; Projects désactivé ; fusion squash et rebase désactivées ; environnement
`production` sans contournement par les administrateurs. « Require actions to be pinned to a
full-length commit SHA » reste décoché : `subosito/flutter-action` appelle `actions/cache@v5`
par son étiquette, et ce réglage refuse aussi les appels internes d'une action. Il a bloqué
la CI de la PR #4 le 2026-11-07.

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
| GitHub, sécurité | approbation des workflows pour tout contributeur externe, actions limitées, secret scanning, push protection, alertes Dependabot, signalement privé de failles |

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

### Alertes de dépendances tolérées

Quatre alertes Dependabot portent sur `rules-tests/package-lock.json`, en dépendances de
développement. Aucune ne touche l'application livrée. Décision de l'utilisateur du
2026-11-07 : les tolérer, et remonter `firebase-tools` ou `firebase` dès qu'une version
les corrige. Les alertes sont fermées sur GitHub avec le motif « Vulnerable code is not
actually used ».

| Paquet | Tiré par | Faille | Pourquoi elle ne nous touche pas |
|---|---|---|---|
| `@grpc/grpc-js` 1.9.16 (deux alertes) | `@firebase/firestore`, qui fige `~1.9.0`, même dans `firebase` 13.2.0 | `getAuthContext` côté serveur ; messages d'erreur d'un serveur transmis au client | le SDK n'est qu'un client gRPC, vers l'émulateur local |
| `minimatch` 9.0.9 | `glob` 10, dans `firebase-tools` 15.35.0 | déni de service par un motif glob forgé | les motifs viennent de `firebase.json`, écrit par nous |
| `uuid` 9.0.1 | `gaxios` 6, dans `firebase-tools` | pas de contrôle de borne quand un tampon est fourni aux versions 3, 5 et 6 | `gaxios` appelle `v4` sans tampon |

Forcer les versions corrigées par des `overrides` npm a été écarté : le déploiement exécute
`firebase-tools`, et aucun test local ne vérifie une CLI aux dépendances forcées.

## Intégrations et services tiers

## Coûts variables
