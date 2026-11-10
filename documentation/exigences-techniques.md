# Exigences techniques

État actuel. Les choix et leurs raisons vivent dans `decisions/`.

## Architecture

Application Flutter (`app/`, Android et web) qui lit et écrit Cloud Firestore `(default)`
directement, avec le cache hors ligne persistant. `firestore.rules` est le seul contrôle
d'accès des clients. Le seul serveur est `functions/` (ADR-006) : deux Cloud Functions sans
point d'accès HTTP qui publient les tickets des membres en Issues GitHub et relisent ces
Issues (voir « Cloud Functions »).

| Fichier | Rôle |
|---|---|
| `firestore.rules` | règles d'accès, appliquant le modèle ci-dessous |
| `firestore.indexes.json` | index composites des requêtes de `tickets/`, TTL de `ticket_quotas/` |
| `firebase.json` | Firestore, Functions (`functions/`, Node 24), émulateurs (auth 9099, firestore 8080), Hosting |
| `functions/` | Cloud Functions des tickets, TypeScript (ADR-006) |
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
| `lib/core/router/` | `routes.dart` (chemins), `app_router.dart` (routeur, `redirectFor`) ; `/nouveautes` est déclaré hors de la coquille, ouvert par `context.push` depuis le menu du compte |
| `lib/core/router/page_de_coquille.dart` | `PageDeCoquille` : route de la coquille qui donne le titre de la barre du haut et le chemin du bouton retour ; `PageDeCoquilleDynamique` : retour calculé depuis le chemin (préparation d'un brassin) |
| `lib/core/data/lecture_document.dart` | `LecteurChamps` (lecture stricte d'un document, `DocumentIllisible` sans valeur par défaut), `champFacultatif` (absent à la création, `FieldValue.delete()` à la modification), `libelleAuteur`, `ListeLue` (documents lus et `fromCache`), `RechercheDocument` (trouvé, illisible, absent du serveur, absent du cache), `CreationEnCours` |
| `lib/core/data/nouveautes.dart` | `Nouveaute`, `lireNouveautes` (valide la forme de `assets/changelog_recent.json`, lève une `FormatException` sinon), `NouveautesRepository` (lecture de l'asset, panne journalisée sous `nouveautes` puis relancée) |
| `lib/core/presentation/` | `AppShell` (rail défilable ; titre et retour reçus de la route ; menu du compte), `NouveautesScreen`, `breakpoints.dart` (seuils 600 / 840 et largeurs `kFormMaxWidth` 400, `kDialogMaxWidth` 480, `kMessageMaxWidth` 480, `kAccountMenuMaxWidth` 280, `kContentMaxWidth` 840, `kEditorMaxWidth` 920, `kCalculationPanelWidth` 340, `kCalculationTileMinWidth` 120 à multiplier par l'échelle du texte, `kCompactMaxHeight` 480, `kBrewDayActionsMaxWidth` 480, `kBrewDayChronologyMaxWidth` 480, `kBrewDayMaxWidth` 1200, `kReleveChampMinWidth` 140 et `kComparaisonValeurMinWidth` 96, à multiplier par l'échelle du texte), `etats.dart` (`EtatChargement`, `EtatVide` avec action facultative, `EtatErreur` avec libellé de nouvelle lecture, `IndicateurBouton`), `BandeauHorsLigne`, `BandeauListePerimee`, `Etiquette`, `showFeuilleOuDialogue`, `formats.dart` (affichage à la française, `formatDateLongue`, `lireNombre`, `erreurNombre`), `ChampNombre` (mode entier, minimum), `PageDocument` (états d'une page de document), `EditeurPleinEcran` et `montrerChamp` (défilement vers le premier champ en erreur), `ecriture.dart` (`suivreEcriture`, `annoncerRefus`, `annoncerAvecAnnulation`, `annoncerAvecAction` (10 s, bouton facultatif), confirmations d'abandon, de suppression, `confirmerAction` et `confirmerActionOuAlternative` (« Annuler », une autre action, la confirmation ; boutons empilés quand la largeur manque)), `fiche.dart` (`LigneFiche`, `TitreSection`, `LigneDeuxNiveaux`, `TexteAbsent`, `SectionRepliable`), `LigneEditeur` (ligne d'une liste d'éditeur avec menu ⋮), `LogoKassBeer` ; `segments.dart` (`BoutonsSegmentes`, `segmentsTiennent` : choix par segments qui passent en colonne quand les libellés, mesurés avec l'échelle du texte, ne tiennent pas ; éditeur des recettes et formulaire de prix) |
| `lib/core/services/screen_wakelock.dart` | `ScreenWakelock` (verrou compté, une remontée d'erreur par session), `KeepScreenAwake` |
| `lib/core/theme/app_theme.dart` | thème Material 3, seul fichier où une couleur est écrite |
| `lib/features/auth/` | `AuthRepository` (Firebase Auth, Google, `currentTokenName`), état d'accès, `grantedAccessProvider`, écrans Chargement, Connexion, Compte non invité, Erreur |
| `lib/features/members/` | `MembersRepository` (`members/`), `Member`, Admin › Membres |
| `lib/features/equipment/` | `EquipmentRepository` (`equipment/`), `Equipment`, `EquipmentContent`, `EquipmentKind` ; liste, fiche, éditeur |
| `lib/features/recipes/` | `RecipesRepository` (`recipes/`, `updateBrewSteps`, `newStepKey`) ; `domain/recipe.dart` : `Recipe`, `RecipeContent` et ses lignes, conversion document BeerJSON ↔ `brewing/`, tri, duplication ; `domain/beerjson.dart` : unités canoniques, lecture des couples `{value, unit}`, valeurs énumérées du schéma et leurs libellés (`EnumerationBeerJson`), `verifierVersionFormat` ; `domain/chronologie.dart` : `BrewStepLine`, lecture et validation de `brew_steps`, durées dérivées ; liste, fiche, éditeur, éditeur de chronologie, `ContenuRecette` (sections partagées avec le brassin), formulaires des lignes (`ListeBeerJson` : liste déroulante d'une valeur BeerJSON, « Non précisé » en tête), vue des calculs |
| `lib/features/brews/` | `BrewsRepository` (`brews/`, `brews/{id}/events/`, jamais de transaction), `Brew`, `BrewEvent`, `BrewStatus`, `MeasureType`, `PhaseEvenement` ; `domain/mesures_retenues.dart` (mesures retenues, VR1, VR2, RR2), `domain/releves.dart` (regroupement du relevé) ; liste, fiche, « Nouveau brassin », `presentation/releve_fermentation.dart`, `prevu_et_mesure.dart`, `embouteillage.dart`, `courbe_fermentation.dart`, `trace_courbe.dart` (seul import de `fl_chart`, P18) |
| `lib/features/costs/` | `CostsRepository` (`users/{uid}/prices`, `fees`, `brew_costs`, jamais de transaction ni de `Source.server`, `brewCostRef`) ; `domain/price.dart` (`Price`, `purchaseUnitOf`, `isUnusualPrice`), `domain/fee.dart` (`Fee`), `domain/brew_cost.dart` (`BrewCost`, `BrewCostLine`, `FreezeKind`) ; `domain/cost_evaluation.dart` : clés dérivées des lignes de `RecipeContent` (`ingredientsDeRecette`), raisons d'un coût indisponible (`RaisonCout`), `evaluerCoutRecette`, `evaluerEstimationBrassin`, `evaluerFigeage`, déclencheur du figeage (`doitFigerAuPremierEmbouteillage`), boutons proposés (`figerLeCoutPropose`, `recalculerPropose`), écart avec l'embouteillage (`ecartsDepuisFigeage`) ; `data/figeage_embouteillage.dart` (`enregistrerEmbouteillage` : embouteillage puis coût, sans attente) ; `presentation/costs_providers.dart` (`pricesProvider`, `feesProvider`, `brewCostProvider`, `costReportsProvider`) ; `presentation/prices_screen.dart` (« Mes prix », route `/prix`), `price_form.dart` (`ouvrirFormulairePrix` : nouveau, manquant, modification ; « Reprendre un de mes prix »), `fee_form.dart`, `bloc_cout.dart` (`BlocCoutRecette`, lignes des raisons et du détail), `bloc_cout_brassin.dart` (`BlocCoutBrassin` : estimation, « Figer le coût », coût figé, écart, « Recalculer avec mes prix actuels »), `formats_cout.dart` (euros, kilogrammes et euros par kilogramme à l'affichage ; aucun calcul de coût) |
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

**Nouveautés.** `scripts/changelog-recent.mjs` lit `documentation/CHANGELOG.md` et écrit
`app/assets/changelog_recent.json` (asset déclaré dans `app/pubspec.yaml`) :
`{ "versions": [ { "version": "0.1.13", "date": "2026-11-10", "paragraphs": ["…"] } ] }`. Il
garde les six dernières versions qui ont une entrée « fonctionnel », de la plus récente à la
plus ancienne ; deux entrées « fonctionnel » d'une même version mettent leurs paragraphes bout
à bout. Le texte est simple : accents graves et `**` retirés, un paragraphe par bloc séparé
d'une ligne vide, une puce `- ` devient un paragraphe qui commence par « • ». Le script échoue
s'il ne trouve aucune version « fonctionnel », ou si une entrée « fonctionnel » n'a pas de date
`## AAAA-MM-JJ` au-dessus d'elle. La CI et `deploy.yml` le relancent avant chaque build web et
APK ; la copie versionnée sert aux builds locaux et aux tests (`flutter test` relit l'asset). Elle est versionnée par choix : c'est une entrée du build déclarée dans `app/pubspec.yaml`, pas un produit de build. La CI ne la compare pas au `CHANGELOG.md` : une version livrée depuis une autre session sans relancer le script ne fait pas échouer la CI, et le build publié reste à jour. Test : `scripts/changelog-recent.test.mjs`.
Aucune dépendance : l'écran affiche du texte, sans rendu Markdown.

**Déconnexion et cache.** La déconnexion ne vide pas le cache Firestore persistant. Les
documents lus restent dans le stockage du navigateur (IndexedDB) ou de l'appareil, prix,
frais et coûts figés compris : une personne qui ouvre ensuite la même session du navigateur
ou le même téléphone peut les lire avec les outils de développement, sans passer par les
règles. Un `clearPersistence()` à la déconnexion effacerait aussi les écritures encore en
attente, dont les mesures et les étapes du jour de brassage saisies hors ligne : elles
seraient perdues sans message. Le code de déconnexion n'appelle donc pas
`clearPersistence()`. Un appareil partagé se protège par sa propre session (profil du
navigateur, compte du téléphone).

**Signature Android.** `app/android/app/build.gradle.kts` lit `app/android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword` ; jamais versionné, P8). Sans ce
fichier, une compilation de release échoue avec un message ; aucune release n'est signée par
la clé de débogage. Le manifeste principal déclare `INTERNET`.

#### Providers

| Provider | Type | Rôle |
|---|---|---|
| `errorReportServiceProvider`, `authRepositoryProvider`, `membersRepositoryProvider`, `recipesRepositoryProvider`, `equipmentRepositoryProvider`, `brewsRepositoryProvider`, `costsRepositoryProvider`, `appVersionProvider` | `Provider` | services fournis par `main.dart` (`overrides`) ou par les tests ; sans valeur par défaut |
| `sessionUserProvider` | `StreamProvider<SessionUser?>` | `authStateChanges()` |
| `memberLookupProvider(emailKey)` | `StreamProvider.family<MemberLookup, String>` | `members/{email en minuscules}`, avec les métadonnées |
| `accessStateProvider` | `Provider<AccessState>` | `AccessLoading`, `AccessSignedOut`, `AccessNotInvited`, `AccessFailed`, `AccessGranted(user, member, offline)` |
| `accessRefreshingProvider` | `Provider<bool>` | nouvelle lecture en cours (boutons « Réessayer », « Vérifier à nouveau ») |
| `membersListProvider` | `StreamProvider.autoDispose<List<Member>>` | `members/` entier, admin seul |
| `grantedAccessProvider` | `Provider<AccessGranted?>` | membre connecté (uid, nom, `offline`), `null` pendant une transition |
| `recipesListProvider` | `StreamProvider.autoDispose<ListeLue<Recipe>>` | `recipes/` entier, avec `fromCache` |
| `equipmentListProvider` | `StreamProvider.autoDispose<ListeLue<Equipment>>` | `equipment/` entier, avec `fromCache` |
| `brewsListProvider` | `StreamProvider.autoDispose<ListeLue<Brew>>` | `brews/` entier, avec `fromCache` |
| `nouveautesSourceProvider` | `Provider<Future<String> Function()>` | lecture de `assets/changelog_recent.json` par `rootBundle` ; remplacée par les tests |
| `nouveautesRepositoryProvider` | `Provider<NouveautesRepository>` | lecture journalisée des nouveautés |
| `nouveautesProvider` | `FutureProvider.autoDispose<List<Nouveaute>>` | versions de l'écran « Nouveautés », sans nouvel essai automatique |
| `brewEventsProvider(brewId)` | `StreamProvider.autoDispose.family<ListeLue<BrewEvent>, String>` | saisies d'un brassin, `hasPendingWrites` par document |
| `pricesProvider(uid)`, `feesProvider(uid)` | `StreamProvider.autoDispose.family<ListeLue<…>, String>` | prix et frais du compte connecté, lus par « Mes prix », la fiche d'une recette et celle de ses brassins ; jamais ceux d'un autre |
| `brewCostProvider((uid:, brewId:))` | `StreamProvider.autoDispose.family<RechercheDocument<BrewCost>, …>` | coût figé d'un brassin, lu par la fiche pour son propriétaire seul |
| `costReportsProvider` | `Provider<Set<String>>` | mémoire de session : calculs de coût refusés déjà rapportés |
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

**Conversion document ↔ `brewing/`.** Écrite une fois, dans `features/recipes/domain/recipe.dart`,
avec les unités et les valeurs énumérées de BeerJSON dans `beerjson.dart` (v0.1.15) :
`fromFirestore` vérifie `format_version`, lit l'enveloppe, puis le sous-arbre `recipe` ; le
type d'un malt et la forme d'un houblon gardent leur valeur BeerJSON (`typesFermentable`,
`formesHoublon`), et leur nature et forme de calcul viennent de `FermentableKind.ofType` et
`HopForm.ofBeerJson` de `brewing/` (v0.1.17) ; le moment d'un houblon ou d'un ajout se lit dans
`timing` ; la quantité d'un houblon, d'un ajout ou d'une levure est une `Quantite`, en grammes
ou en litres ; `toFirestore` écrit l'enveloppe et
`recipe` d'un bloc, sans clé d'ingrédient (`ingredientKey` vérifie seulement le nom) ; `toInput`
construit le `RecipeInput` de `computeRecipe`. Les masses restent en grammes : la saisie en
kilogrammes des malts et sucres est multipliée par 1 000 dans le formulaire ; la durée à cru en
jours par 1 440 (`minutesParJour`), arrondie à la minute. Les autres ajouts (`OtherUse`), le
type de recette, de levure, d'ajout et de palier, la forme et la quantité de la levure et la
température du grain n'entrent dans aucun calcul.

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
| `/prix` | « Mes prix », page pleine avec retour, hors coquille, ouverte par `push` depuis le menu du compte | membre ; ses seuls prix et frais |
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
`FirebaseEnv`, `FirestoreBrewsRepository` sur `fake_cloud_firestore` (copie figée, `owner_name` à chaque écriture, identifiant de l'appareil, HS7), écrans Brassins et écran du jour (minuteur recalculé avec une horloge injectée, double appui, étape sautée, début en double, densité, alerte, verrou, reprise, pastille d'envoi), `AlerteMinuteurPlateforme` (`TestDefaultBinaryMessenger`, P17), domaine des coûts (`costs_domain_test.dart` : clés dérivées sans champ `key`, raisons de CB8, déclencheur du figeage, écarts), `FirestoreCostsRepository` sur `fake_cloud_firestore` (`costs_repository_test.dart` : écriture et suppression des prix et des frais, document illisible rapporté sans valeur, refus d'un premier figeage annoncé seulement si le coût n'est pas sur le serveur et rejeu journalisé `costs.freeze_replayed` (HL5), suppression du brassin et de son coût dans un même lot par `delete` et `deleteWithEvents` (CB19), `enregistrerEmbouteillage` : coût écrit après l'embouteillage sans attente, aucun coût pour une modification, un embouteillage déjà daté ou un coût déjà lu, embouteillage envoyé même quand le calcul échoue ou que les prix manquent, refus du coût seul et de l'embouteillage seul (CB7)), écrans des coûts (`costs_screens_test.dart` : « Mes prix », bloc de la recette, bloc du brassin absent pour un autre membre et pour l'admin, aucun montant avec un prix manquant ni dans une annonce, coût figé inchangé quand un prix change, figeage au premier embouteillage seulement, dialogues à trois boutons de « Figer » et de « Recalculer », nom importé coupé à 120 caractères, texte à 200 %, contraste, cibles tactiles et en-tête des manquants annoncé).

#### Tickets — client

Feature `lib/features/tickets/` (ADR-006, lot T1). Aucun code de ticket dans l'écran du jour
de brassage ni dans ce qu'il appelle (P2) ; aucun prix, stock ni coût (P5).

| Fichier | Contenu |
|---|---|
| `domain/ticket.dart` | `Ticket` (lecture tolérante : statut inconnu lu `TicketStatus.unknown`, type inconnu, champ obligatoire absent ou mal typé : `DocumentIllisible`), `TicketType`, `TicketStatus`, `TicketBrouillon`, bornes des règles (titre 5 à 100, description 10 à 2 000), `unread`, `compareTicketsRecentFirst`, `compareVersions` |
| `domain/ticket_screens.dart` | table fermée `kTicketScreenNames` (modèle de route → nom), `autre`, `inconnu` ; `ticketScreenValue` ne rend qu'une valeur de cet ensemble |
| `domain/etat_jeton_github.dart` | `EtatJetonGithub` (`token_invalid_since`, `token_expires_at`) |
| `data/tickets_repository.dart` | `TicketsRepository`, `FirestoreTicketsRepository` |
| `presentation/` | `TicketFormScreen`, `MyTicketsScreen`, `TicketDetailScreen`, `BandeauTicketsAdmin`, `ticket_statut.dart` (étiquette, icône et phrase de chaque statut), `ticket_lien_github.dart`, `tickets_providers.dart` |

**Routes.** Hors de la coquille, ouvertes par `push`, retour par `pop` sinon `/tickets` ou
l'accueil : `/tickets/nouveau` (déclarée avant `/tickets/:id`), `/tickets/:id`, `/tickets`.
`routes.dart` : `tickets`, `newTicket`, `ticket(id)`. Le menu du compte lit
`GoRouter.of(context).state.fullPath` (modèle `/recettes/:id`, jamais l'adresse) et le passe
dans `?ecran=` ; le formulaire le réduit par `ticketScreenValue`. « Reprendre ce ticket »
passe un `TicketBrouillon` par `extra`. `test/ticket_screens_test.dart` parcourt
`router.configuration.routes` et échoue si une route manque à la table.

**Écritures.** `create` écrit `tickets/{id}` avec l'identifiant créé par l'appareil à
l'ouverture du formulaire (`newTicketId`) et les seuls champs du contrat : `type`, `title`,
`description` (retirés de leurs espaces), `screen`, `app_version` (absent si illisible,
sans `+build`), `platform` (`android` ou `web`), `author_uid`, `author_email` (minuscules),
`created_at` = `serverTimestamp()`, `status` = `pending`. Un double appui est arrêté par une
garde synchrone du formulaire : un second `set` serait une mise à jour, refusée par les
règles. `markSeen` écrit `seen_by_author_at` = `serverTimestamp()` à l'ouverture d'un suivi à
lire. Ni callable, ni transaction, ni `Source.server` : tout marche hors ligne.

**Lectures.** `watchMine(uid)` : `where author_uid == uid`, tri à l'affichage, aucun index
composite. Pour l'admin : `watchNotSent` (`status in [pending, send_failed]`),
`watchIssueMissing` (`issue_missing_since != null`), `watchGithubStatus`
(`ticket_status/github`). Toutes avec `includeMetadataChanges` et le cache. Un
`serverTimestamp()` en attente se lit `null` : la date d'envoi affichée est alors l'heure de
l'appareil gardée par le dépôt pour un ticket créé dans la session, sinon aucune date. Un
ticket qui a une écriture en attente et n'est plus `pending` n'est pas compté à lire : cette
écriture ne peut être que `seen_by_author_at`.

**Pastille.** `Ticket.unread` : statut différent de `pending`, aucune écriture en attente,
`status_changed_at` présent et postérieur à `seen_by_author_at` (ou celui-ci absent).
Le passage `pending` → `received` n'écrit pas `status_changed_at` : il n'allume rien.
`unreadTicketsCountProvider` compte ces tickets ; « 99+ » au-delà de 99.

**Providers.** `ticketsRepositoryProvider` (`core/providers.dart`, fourni par `main.dart`),
`myTicketsProvider(uid)`, `unreadTicketsCountProvider`, `githubStatusProvider`,
`notSentTicketsProvider`, `issueMissingTicketsProvider`, `ouvrirLienProvider`
(`launchUrl(mode: externalApplication)`, remplacé dans les tests). Aucune nouvelle tentative
automatique : une panne s'affiche, « Réessayer » relance.

**`url_launcher` 6.3.3** (version exacte). `lienGithub` n'accepte qu'une adresse `https` sur
l'hôte `github.com`, sans identifiants ni port ; sinon le bouton « Voir la modification sur
GitHub » n'apparaît pas. Un refus du système ou une erreur est rapporté
(`tickets.open_github`, sans l'adresse) et annoncé. `AndroidManifest.xml` déclare dans
`<queries>` l'intent `VIEW` sur `https` (visibilité des paquets, Android 11+).

**Journal.** Rapports `tickets.create`, `tickets.read`, `tickets.mark_seen`,
`tickets.watch_*`, `tickets.read_github_status`, `tickets.open_github` : `context` ne porte
que `tickets/{id}` et le code d'erreur, jamais le titre, la description ni l'e-mail (P13).

**Bandeau Admin.** `messagesBandeauTickets` (fonction pure, testée) : jeton refusé
(`token_invalid_since`), échéance à 14 jours ou moins (`kTokenExpiryWarning`) ou inconnue,
tickets `send_failed` ou `pending` depuis plus d'une heure (`kTicketSendDelay`, heure de
`horlogeProvider`), Issues disparues. Liste vide quand tout va bien.

**Composants partagés.** `Etiquette` reçoit `icon` (exclue de la sémantique) et
`ton` (`TonEtiquette.erreur` : `errorContainer` / `onErrorContainer`). `EditeurPleinEcran`
reçoit `libelleAction` et `libelleEnCours` (« Enregistrer » et « Enregistrement » par défaut)
et `fermerParRetour` (faux par défaut : `go(closePath)` comme avant ; vrai : `pop` s'il y a un
écran précédent). `formats.dart` : `formatDateChiffres` (« 08/11/26 »). `AdminScreen` affiche
`BandeauTicketsAdmin` en tête.

**Tests.** `tickets_domain_test.dart` (lecture, statuts, suivi à lire, versions, lien,
bandeau), `ticket_screens_test.dart` (table et routes), `tickets_repository_test.dart`
(`fake_cloud_firestore` : champs écrits, illisible rapporté sans texte, `markSeen`, requêtes
admin, état du jeton), `tickets_screens_test.dart` (menu et pastille, formulaire, liste,
détail, bandeau Admin).

## Modèle de données

Unités du système international : masses en grammes (`_g`), volumes en litres (`_l`),
températures en °C (`_c`), densités en SG décimal, couleur en EBC, durées en minutes
(`_min`), pourcentages de 0 à 100 (`_pct`). Les dates `created_at` et `updated_at` sont
posées par `serverTimestamp()` ; les règles vérifient qu'elles valent l'heure de la requête.

Les règles refusent tout champ de premier niveau absent des listes ci-dessous. Tout nombre
de premier niveau est fini et strictement compris entre -1e9 et 1e9 (`optNumber`) ;
`mash_efficiency_pct` est en plus borné de 0 à 100. Les éléments
d'une liste (ingrédients, paliers) ne peuvent pas être inspectés par les règles : le dépôt
de données les écrit à partir de ses types, sans prix (P5).

Les recettes et leurs copies figées font exception à ces noms de champs : elles suivent
BeerJSON (ADR-005), en couples `{value, unit}` d'une seule unité par grandeur.

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

Lisible par tous les membres (partagée au groupe). Aucun prix. Depuis la v0.1.15, une
enveloppe propre à Kass'Beer et un sous-arbre `recipe` en BeerJSON partiel (ADR-005) : la
structure et les noms de `RecipeType` du schéma BeerJSON au commit figé `4370892d44`, copié
avec sa licence (MIT) dans `schemas/beerjson-4370892d44/`.

Enveloppe :

| Champ | Type |
|---|---|
| `format_version` | int, obligatoire : `1`. Toute autre valeur, ou son absence, rend le document illisible |
| `owner_uid` | string, obligatoire, uid de l'auteur, immuable |
| `owner_name` | string, facultatif, 1 à 80 caractères : nom de l'auteur affiché au groupe, égal au nom du jeton de celui qui écrit |
| `equipment_id` | string \| null (128) : profil d'équipement prévu |
| `imported_from` | string \| null (200) : nom de la fiche Excel d'origine |
| `brew_steps` | list<map> \| null (60) : chronologie du jour de brassage, dans l'ordre. Élément : `key` (20 caractères, `doc().id`, créée à l'ajout, stable au renommage et au déplacement, unique dans la recette), `name` (1 à 120), `duration_min` (0 à 600, décimale permise ; 0 pour une action sans minuteur), `temp_c` (0 à 100 \| null). Inchangée en v0.1.15 |
| `recipe` | map, obligatoire : ci-dessous |
| `created_at`, `updated_at` | timestamp, obligatoires |

`recipe` (BeerJSON, champs présents dans l'application) :

| Champ | Type |
|---|---|
| `name` | string, obligatoire, 1 à 120 caractères |
| `type` | string, facultatif : `all grain`, `partial mash`, `extract` à la saisie ; toute valeur de `RecipeType.type` du schéma à la lecture |
| `author` | string, facultatif, 1 à 120 caractères (v0.1.17) : auteur de la recette d'origine, conservé d'un import. L'éditeur l'affiche en lecture seule et le réécrit tel quel ; « Dupliquer » le copie ; la copie figée le porte. Distinct de `owner_name` |
| `efficiency` | refusé (v0.1.17, option A de L2a) : le rendement d'un fichier importé n'est pas stocké. L'export de L2b écrit `efficiency.brewhouse` depuis le rendement d'empâtage de l'équipement. Le contrôler, même par ses seules clés, faisait refuser la création d'un brassin (budget, voir « Règles d'accès ») |
| `style` | map, facultative : `name` (1 à 120) |
| `notes` | string, facultatif (10 000) |
| `batch_size` | `{value, "l"}`, facultatif : volume visé en fermenteur |
| `boil` | map, facultative : `boil_time` `{value entier, "min"}` |
| `mash` | map, facultative : `name` (« Empâtage », un libellé), `grain_temperature` `{value, "C"}` facultatif, `mash_steps` (20) absente sans palier, jamais une liste vide. Palier : `name`, `type` facultatif (`MashStepType.type`), `step_temperature` `{value, "C"}`, `step_time` `{value entier, "min"}` |
| `ingredients` | map, obligatoire, avec les quatre listes, même vides. `water_additions` refusé |
| `ingredients.fermentable_additions` | list (50) : `name`, `type` obligatoire (`grain`, `sugar` à la saisie ; toute valeur de `FermentableBase.type` à la lecture : `extract`, `dry extract`, `honey`, `fruit`, `juice`, `other`), `amount` `{value, "g"}`, `color` `{value, "EBC"}` facultatif, `yield.fine_grind` `{value, "%"}` facultatif |
| `ingredients.hop_additions` | list (50) : `name`, `form` obligatoire (`pellet`, `leaf` à la saisie ; toute valeur de `HopVarietyBase.form` à la lecture : `plug`, `leaf (wet)`, `powder`, `extract`), `alpha_acid` `{value, "%"}` facultatif, `amount` `{value, "g"}` ou `{value, "l"}` (v0.1.17), `timing` (ci-dessous) |
| `ingredients.miscellaneous_additions` | list (50) : `name`, `type` facultatif (`MiscellaneousBase.type`), `amount` `{value, "g"}` ou `{value, "l"}` (v0.1.17), `timing` facultatif |
| `ingredients.culture_additions` | list (10) : `name`, `type` et `form` facultatifs (`CultureBase`), `attenuation` `{value, "%"}` facultatif, `amount` `{value, "g"}` ou `{value, "l"}` (v0.1.17) facultatif. L'éditeur en écrit une au plus |

Un couple `{value, unit}` est absent ou complet, jamais une unité seule, jamais 0 à la
place d'un vide. Une seule unité par grandeur : `g`, `l`, `C`, `min`, `EBC`, `%`. La
quantité (`amount`) d'un houblon, d'un ajout ou d'une levure est une masse en `g` ou un volume
en `l` (décision du 2026-11-10), enregistrée dans son unité ; celle d'un malt reste en `g`.
L'éditeur saisit ces volumes en millilitres et les écrit en litres ; l'écran les affiche en
millilitres sous 1 L. Les durées
en minutes sont des entiers Firestore (`int` en Dart) : une durée décimale rend le document
illisible.

Moments (`timing`, BeerJSON au commit figé : `time` porte les minutes d'ébullition,
`duration` le temps d'infusion d'un ajout en fin d'ébullition) :

| Saisie | Écrit | Relu |
|---|---|---|
| Houblon, ébullition t min | `use: add_to_boil`, `time` t | Ébullition t |
| Houblon, whirlpool d min | `add_to_boil`, `time` 0, `duration` d | Whirlpool d |
| Houblon, à cru j jours | `add_to_fermentation`, `duration` = j × 1 440 arrondi à la minute ; `time`, jour d'ajout en minutes depuis le début de la fermentation, conservé d'un import (`HopLine.dayMin`, non lu par `brewing/`) | À cru |
| Houblon importé, empâtage ou conditionnement | `add_to_mash`, `add_to_package`, durée dans `duration` | Empâtage, Conditionnement (`HopUse.mash`, `HopUse.package`) |
| Ajout, Empâtage, Fermentation, Embouteillage | `add_to_mash`, `add_to_fermentation`, `add_to_package`, durée dans `duration` | idem |
| Ajout, Ébullition t | `add_to_boil`, `time` t | Ébullition t |
| Ajout, Après ébullition d | `add_to_boil`, `time` 0, `duration` d | Après ébullition d |
| Ajout, Après ébullition sans durée | `add_to_boil`, `time` 0 | Ébullition 0 min |
| Ajout sans utilisation | `timing` absent | sans utilisation |

Un `add_to_boil` à `time` non nul avec `duration`, ou un `time` à l'empâtage, au
conditionnement ou sur un autre ajout à la fermentation rendent le document illisible : la
valeur serait perdue au prochain enregistrement. Depuis la v0.1.17, un houblon `add_to_mash`
ou `add_to_package` et le `time` d'un houblon à cru se lisent. Un whirlpool sans durée
et une durée d'ajout sans utilisation ne s'écrivent pas (`ArgumentError`, l'éditeur les refuse).

Lecture (`recipe.dart`, `beerjson.dart`, `LecteurChamps`) : une valeur énumérée hors du schéma
(type de recette, de levure, d'ajout, de palier, forme de levure) ou une unité hors liste lève
`DocumentIllisible`, dont la raison donne la longueur du texte stocké, jamais le texte. Une
valeur du schéma absente des listes de l'éditeur (`cider`, `slant`…) est lue, affichée telle
quelle et réécrite à l'identique. Depuis la v0.1.17, le type d'un malt (`typesFermentable`)
et la forme d'un houblon (`formesHoublon`) suivent la même règle : toute valeur du schéma est
lue et gardée, une autre lève `DocumentIllisible`. Leur valeur de calcul vient de `brewing/` :
`FermentableKind.ofType` (`grain` → malt ; `sugar`, `extract`, `dry extract`, `honey`,
`fruit`, `juice` → sucre ; `other` → `null`, nature à préciser) et `HopForm.ofBeerJson`
(`leaf` et `plug` → cônes, `pellet` → pellets ; `leaf (wet)`, `powder`, `extract` → `null`,
forme sans facteur d'utilisation). La clé de prix d'un fermentescible qui n'est pas un malt
(`other` compris) a le préfixe `sucre` (`FermentableLine.nature`). Une quantité dans une autre
unité que `g` ou `l` (`ml`, `kg`, `each`…) lève `DocumentIllisible`. Le moment d'un houblon se
lit dans l'application : `HopUse` n'a pas de valeur stockée.

La clé d'ingrédient n'est plus stockée : `ingredientKey` de `brewing/` la dérive du nom et de
la nature (préfixe `malt`, `sucre`, `houblon`, `levure`, `ajout`, puis nom en minuscules, sans
accents, chaque suite de caractères hors lettre et chiffre remplacée par un tiret, 100
caractères au plus ; « Pils » → `malt-pils`). Deux lignes de même nom, à la casse près,
partagent la clé. Elle relie l'ingrédient au prix et au stock du lecteur. Un nom sans lettre
ni chiffre est refusé à l'enregistrement (`BrewingInputException`). Densités, degré, IBU, EBC
et coût ne sont pas stockés : `brewing/` les calcule à l'affichage.

`RecipeContent` et ses lignes restent le type de travail de l'application : `toInput` donne à
`computeRecipe` la même entrée qu'en v0.1.14 (test « même recette en plat et en BeerJSON »).
Modifier une recette réécrit `recipe` d'un bloc (`update`, le champ est remplacé, sans
`FieldValue.delete()` à l'intérieur) ; `equipment_id`, `imported_from` et `owner_name` vides
sont retirés par `FieldValue.delete()`.

Validation : `firestore.rules` contrôle l'enveloppe et le premier niveau de `recipe` (voir
« Règles d'accès ») ; ajv valide en test (`rules-tests/test/beerjson_schema.test.mjs`) les
documents écrits par `toFirestore` (`app/test/fixtures/recipe_documents/`, vérifiés à
l'identique par `recipe_conversion_test.dart`) contre le schéma partiel, dérivé à chaque
lancement du schéma officiel (`beerjson_partial.mjs`) : champs obligatoires de la liste fermée
d'ADR-005 retirés, unités réduites aux unités canoniques. ajv ne tourne pas dans l'application.

Les règles n'inspectent pas les éléments des listes : elles acceptent une valeur que le dépôt
de données refuse à la lecture. L'unité d'une quantité (`g` ou `l`) est donc contrôlée par le
schéma partiel en test et par la lecture Dart, pas par les règles (voir « Risques acceptés »).
La fixture `imported.json` (v0.1.17) porte les valeurs lues depuis L2a : auteur, malts extrait,
miel, fruit, jus et `other`, houblons à l'empâtage et au conditionnement, formes `plug`,
`powder`, `extract` et `leaf (wet)`, jour d'ajout à cru, quantités en litres, levure `wheat`.

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
| `recipe_snapshot` | map, obligatoire, immuable : copie de la recette, même forme que `recipes/` (enveloppe, `format_version` 1, `recipe` en BeerJSON partiel, `brew_steps` compris, 60 éléments au plus), plus `updated_at` de la recette au moment de la copie. Mêmes contrôles des règles que `recipes/`, à la création du brassin. `owner_name`, s'il est présent, est une chaîne de 1 à 80 caractères (celui de l'auteur de la recette, pas forcément celui qui brasse). Une version de format inconnue rend le brassin illisible |
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

Au premier enregistrement de l'embouteillage (`modification` faux, `bottled_at` nul avant
l'écriture, aucun coût figé déjà lu), `enregistrerEmbouteillage` fige aussi le coût réel :
le calcul se fait d'abord, sans lever (`evaluerFigeage`), puis `saveBottling` part, inchangé,
puis le `set` de `users/{uid}/brew_costs/{brewId}`, sans attente entre les deux. Le coût ne
part pas dans le lot de l'embouteillage : un refus sur `brew_costs` annulerait le statut,
l'embouteillage et le relevé de densité finale. La file de Firestore garde l'ordre des deux
écritures, hors ligne compris. Un refus du coût seul laisse l'embouteillage enregistré
(`costs.freeze_rejected`) ; un refus de l'embouteillage seul laisse le coût figé, et le bloc
Coût affiche l'écart. Un prix manquant ou une autre raison de ne pas figer n'empêche jamais
l'embouteillage : le coût reste « non figé » et se rattrape par « Figer le coût ».

La fiche du brassin lit `pricesProvider`, `feesProvider` et `brewCostProvider` pour son
propriétaire seul, et les garde ouverts même quand le bloc Coût est hors de l'écran : à l'envoi
du formulaire, elle capture ces valeurs avant d'attendre le nom du jeton, sans autre lecture.
Des prix ou des frais pas encore lus comptent comme indisponibles : le coût ne se fige pas.
« Voir le coût » fait défiler la fiche jusqu'au bloc, construit à la demande par la liste.

### `users/{uid}/…` — données privées

Lisibles et modifiables par leur seul propriétaire, membre. L'admin ne les lit pas (P5).
Les règles contrôlent la forme de `prices`, `fees` et `brew_costs` ; `stock` n'a pas encore de
contrôle de forme. Unités du système international : masses en grammes, montants en euros.

| Chemin | Champs |
|---|---|
| `users/{uid}/prices/{ingredientKey}` | `name` string (1 à 120), `price_eur` number (prix payé, 0 à 100 000), `quantity` number (quantité achetée, au-delà de 0 et jusqu'à 1e9), `unit` string (`g`, `unit` pour un sachet de levure, ou `l` depuis la v0.1.17 : prix au litre d'un houblon ou d'un ajout ; `purchaseUnitsOf` limite les litres à ces deux natures dans le formulaire, les règles ne lient pas l'unité au préfixe), `updated_at` timestamp (`serverTimestamp()`). Identifiant : clé d'ingrédient, 100 caractères au plus, préfixe `malt`, `sucre`, `houblon`, `levure` ou `ajout`, forme `^(malt|sucre|houblon|levure|ajout)(-[a-z0-9]+)*$` ; un identifiant hors de cette forme est lu comme illisible (`DocumentIllisible('id', 'clé hors format')`), rapporté sans l'identifiant, qui dérive du nom, puis se supprime après confirmation. Un kilogramme saisi est converti en grammes à l'écran, un millilitre en litres |
| `users/{uid}/fees/{feeId}` | `name` string (1 à 60), `amount_eur` number (0 à 10 000), `basis` string (`per_brew`, `per_bottle`), `updated_at` timestamp (`serverTimestamp()`). Identifiant créé par l'appareil ; 20 frais au plus, limite du formulaire |
| `users/{uid}/stock/{ingredientKey}` | `name` string, `quantity` number, `unit` string, `updated_at` timestamp (après la v1) |
| `users/{uid}/brew_costs/{brewId}` | `brew_id` string (égal à l'identifiant), `total_eur` number (somme exacte des lignes, positive ou nulle), `lines` list<map> (200 au plus : `key` clé d'ingrédient ou `frais-{feeId}`, `name`, `quantity`, `unit` parmi `g`, `unit`, `l` (v0.1.17, ligne en volume au prix au litre), `brew`, `bottle`, `cost_eur`), `computed_at` timestamp (heure de l'appareil au figeage), `freeze_kind` string (`initial`, `recalculation`), et, facultatifs, les valeurs d'embouteillage utilisées : `bottles_count` (entier de 1 à 9 999), `packaged_volume_l` (au-delà de 0 et jusqu'à 1 000), `priming_sugar_g` (0 à 100 000), `priming_sugar_name` (80) |

Le coût réel d'un brassin est stocké parce qu'il reprend les prix du jour du figeage ; le
coût d'une recette et l'estimation d'un brassin non figé se recalculent à l'affichage avec
les prix et les frais du lecteur, et rien n'est écrit. Un coût figé n'est jamais remplacé en
silence : modifier l'embouteillage ne réécrit pas `brew_costs`, le bloc compare les valeurs
d'embouteillage gardées à celles du brassin (`ecartsDepuisFigeage`), et seul « Recalculer
avec mes prix actuels » remplace le document entier (`freeze_kind: recalculation`). Supprimer
un brassin supprime `users/{uid}/brew_costs/{brewId}` dans le même `WriteBatch` que
`brews/{brewId}`, par `delete` comme par `deleteWithEvents`. Les prix et les frais sont lus
avec le cache hors ligne ; une clé absente d'une liste lue du cache rend « Prix indisponibles
sur cet appareil hors ligne », jamais « prix manquant », et rien ne se fige.

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

### `tickets/{ticketId}`

Ticket d'un membre (ADR-006). Identifiant créé par l'appareil à l'ouverture du formulaire
(`[A-Za-z0-9_-]`, 128 caractères au plus) : un double appui n'écrit qu'un ticket. Le membre le
crée hors ligne compris ; le déclencheur `publishTicket` le publie en Issue sur le dépôt
public `ChinaFred/KassBeer`. Aucun prix, stock ni coût (P5). `author_email` n'est jamais
publié.

Écrits par le client, à la création seule :

| Champ | Type |
|---|---|
| `type` | string, obligatoire : `bug`, `evolution` ou `feature` |
| `title` | string, obligatoire, 5 à 100 caractères, une ligne |
| `description` | string, obligatoire, 10 à 2 000 caractères |
| `screen` | string, obligatoire, 100 caractères au plus : modèle de route go_router (`/recettes/:id`), `autre` ou `inconnu` ; jamais un identifiant réel |
| `app_version` | string facultatif, 1 à 40 caractères |
| `platform` | string, obligatoire : `android` ou `web` |
| `author_uid` | string, obligatoire : `request.auth.uid` |
| `author_email` | string, obligatoire : e-mail du jeton en minuscules |
| `created_at` | timestamp, obligatoire : `serverTimestamp()` |
| `status` | string, obligatoire : `pending` à la création |

Écrit par l'auteur ensuite : `seen_by_author_at` (timestamp, `serverTimestamp()`), à
l'ouverture du suivi.

Écrits par le serveur seul (SDK Admin) :

| Champ | Contenu |
|---|---|
| `status` | `pending`, `received`, `validated`, `in_progress`, `delivered`, `refused`, `closed`, `send_failed`, `over_quota` |
| `status_changed_at` | timestamp : chaque changement de statut, sauf `pending` → `received`, et chaque nouvelle réponse |
| `github_issue_number`, `github_url` | numéro de l'Issue ; adresse construite depuis le numéro (`https://github.com/ChinaFred/KassBeer/issues/N`) |
| `github_checked_at` | timestamp de la dernière relecture de l'Issue (tri de la passe horaire) |
| `github_updated_at` | `updated_at` de l'Issue à la dernière relecture : les commentaires ne sont relus que s'il change |
| `send_attempts` | entier : essais d'envoi en échec ; au dixième, `send_failed` |
| `last_send_error` | string, 300 caractères au plus : code HTTP et message de GitHub, jamais le jeton |
| `send_lease_until` | timestamp : bail de deux minutes d'un envoi en cours |
| `send_quota_day` | `AAAAMMJJ`, jour de Paris où le plafond a été décidé ; le ticket n'est plus compté ensuite |
| `over_quota_reason` | `member` ou `group` |
| `reply_text`, `reply_at` | dernière réponse « Réponse : » du compte 16348852, préfixe et ligne « Décision … » retirés, adresses remplacées, 2 000 caractères au plus ; date du commentaire |
| `delivered_pr_number`, `delivered_pr_url`, `delivered_version` | PR fusionnée qui a fermé l'Issue, adresse `https://github.com/ChinaFred/KassBeer/pull/N`, version `X.Y.Z` de `app/pubspec.yaml` à son commit de fusion ; `null` sans PR (fermeture à la main) ou sans version lisible |
| `delivered_checked_at` | timestamp de la recherche de la PR de livraison |
| `issue_missing_since` | timestamp : Issue en 404 ou 410, dépôt joignable ; le statut ne change pas |
| `updated_at` | timestamp de la dernière écriture du serveur |

Un statut ne recule pas, sauf à la réouverture de l'Issue, qui reprend le statut de ses
étiquettes. Quitter `delivered` efface les quatre champs `delivered_*`. `allowed_decisions`,
`decision_lease_until` et la sous-collection `decisions/` arrivent avec le lot T2.

### `ticket_quotas/{id}`

Compteurs du plafond du jour de Paris, lus et écrits par le déclencheur seul :
`member_{uid}_{AAAAMMJJ}` (5 par membre) et `group_{AAAAMMJJ}` (20 pour le groupe). Champs
`count`, `day`, `expires_at` (date d'écriture + 7 jours, champ TTL de
`firestore.indexes.json`). Les tickets de l'administrateur ne sont ni refusés ni comptés.

### `ticket_status/github`

État du jeton GitHub, écrit par le serveur seul, lu par l'administrateur (bandeau de la page
Admin) :

| Champ | Contenu |
|---|---|
| `token_invalid_since` | timestamp du premier refus (401, 403 hors limite de débit, 404 sur le dépôt, secret vide), `null` après le premier appel réussi |
| `token_invalid_reason` | `secret_vide`, `jeton_refuse` ou `http_<code>` ; jamais le jeton |
| `token_expires_at` | date de l'en-tête `github-authentication-token-expiration` ; `null` quand la dernière réponse réussie ne le portait pas (« Date d'expiration du jeton GitHub inconnue. ») |
| `token_checked_at` | timestamp de la dernière réponse réussie qui a écrit ce document |
| `issues_cursor` | date ISO : curseur de la liste des Issues modifiées, propre à la passe horaire |

## Règles d'accès

Un membre est un compte connecté par Google (`firebase.sign_in_provider == 'google.com'`),
à l'adresse vérifiée (`email_verified == true`), dont l'e-mail en minuscules a un document
`members/{email}` (P11). Le rôle n'existe que dans ce document.

| Chemin | Lecture | Création | Modification | Suppression |
|---|---|---|---|---|
| `members/{email}` | son propre document (même absent) pour tout compte Google vérifié ; tous pour l'admin | admin | personne | admin, sauf son propre document et celui d'un autre admin (`resource.data.role != 'admin'`) |
| `recipes/`, `equipment/` | membres | membre, à son `owner_uid` ; `owner_name` absent ou égal au nom du jeton (`request.auth.token.name`, 1 à 80 caractères) | propriétaire, `owner_uid` et `created_at` inchangés, `owner_name` comme à la création | propriétaire |
| `brews/` | membres | membre, à son `owner_uid` ; `owner_name` comme dans `recipes/` ; champs de création seuls (`owner_uid`, `owner_name`, `recipe_id`, `name`, `status`, `planned_for`, `notes`, `imported_from`, copies, dates) ; `recipe_snapshot` contrôlé comme `recipes/` | propriétaire ; `recipe_id`, `recipe_snapshot`, `equipment_snapshot` inchangés ; liste blanche des clés ; seuls les champs changés sont contrôlés, par groupe (nom, statut, dates, ajustements, embouteillage, mesures retenues et `sugars_in_wort`, notes et `imported_from`) ; `owner_name` comme à la création | propriétaire |
| `brews/{id}/events/` | membres | propriétaire du brassin existant, à son `owner_uid`, forme selon `kind` | auteur : `value`, `note`, `measured_at`, forme gardée | auteur |
| `users/{uid}/**` | propriétaire | refusé, sauf les collections ci-dessous | refusé, sauf les collections ci-dessous | refusé, sauf les collections ci-dessous |
| `users/{uid}/prices/`, `fees/` | propriétaire | propriétaire, forme et bornes contrôlées | propriétaire, forme et bornes contrôlées | propriétaire |
| `users/{uid}/brew_costs/` | propriétaire | propriétaire, forme contrôlée, `freeze_kind == 'initial'` | propriétaire, forme contrôlée, `freeze_kind == 'recalculation'` | propriétaire |
| `users/{uid}/stock/` | propriétaire | propriétaire | propriétaire | propriétaire |
| `error_reports/` | admin | membre, `uid` = le sien, champs en liste blanche et bornés | personne | admin |
| `tickets/` | auteur (`author_uid` = le sien, requête « Mes tickets » comprise) ; tous pour l'admin | membre, champs de création seuls (voir `tickets/`), `status == 'pending'`, `created_at == request.time`, `author_email` = e-mail du jeton en minuscules | auteur : `seen_by_author_at == request.time` seul | personne |
| `ticket_quotas/**` | personne | personne | personne | personne |
| `ticket_status/**` | admin | personne | personne | personne |
| tout autre chemin | refusé | refusé | refusé | refusé |

L'admin n'a aucun droit d'écriture sur le contenu des autres brasseurs.

Le joker `users/{uid}/{document=**}` n'accorde que la lecture : les règles s'additionnent, et
une écriture permise par le joker rendrait sans effet les contrôles de forme. Sur
`brew_costs`, la création n'accepte que `freeze_kind: initial` et la modification que
`recalculation` : un second appareil qui fige le même brassin est refusé sans écraser le
premier, et un rejeu après un accusé perdu aussi. L'application relit alors le document par
une lecture ordinaire : s'il existe sans écriture en attente, le refus est journalisé
(`costs.freeze_replayed`) sans être annoncé. Les éléments de `lines` ne sont pas inspectés,
seul leur nombre est borné.

**Forme d'une recette (v0.1.15).** `recipeFields()` : `format_version`, `owner_uid`,
`owner_name`, `equipment_id`, `imported_from`, `brew_steps`, `recipe`, `created_at`,
`updated_at`. `format_version` vaut l'entier 1. `recipe` n'a que `name` (1 à 120), `type`
(une des neuf valeurs de `RecipeType.type` au commit figé), `author` (v0.1.17 : texte de 1 à
120 caractères ; `efficiency` reste refusé), `notes` (10 000), `style` (la
seule clé `name`, 1 à 120), `batch_size` (`unit` `l`), `boil` (la seule clé `boil_time`, `unit`
`min`, valeur entière), `mash` (les seules clés `name`, texte de 1 à 120 caractères,
`grain_temperature`, `unit` `C`, et `mash_steps`, 20) et `ingredients` (quatre listes bornées à
50, 50, 50 et 10 ; `water_additions` refusé). `style`, `boil`, `mash` et `ingredients` sont
des maps fermées : une autre clé, ou une liste ou un texte à leur place, est refusé. Une liste
de `recipe` (ingrédients, `mash_steps`) est absente ou une liste : `null` est refusé, comme
dans BeerJSON. Un couple présent est complet, aux seules clés `value` et `unit`, valeur finie
et bornée. `mash.name` est un libellé que l'application écrit (« Empâtage ») et ne relit pas.
`recipe_snapshot` passe les mêmes contrôles à la création du brassin, puis ne change plus. Un
document plat de la v0.1.14 est refusé.

**Risques acceptés.** Les règles ne contrôlent pas les éléments des listes (ingrédients,
paliers, étapes de la chronologie) : un élément peut porter un champ inconnu, un prix
compris. Les unités des quantités des listes (`amount` en `g` ou en `l` pour un houblon, un
ajout ou une levure, en `g` pour un malt) ne sont pas contrôlées par les règles non plus :
le schéma partiel les vérifie en test (`beerjson_schema.test.mjs`) et la lecture Dart rend
illisible une autre unité. Une recette écrite par un autre client avec `ml` ou `kg` est
acceptée par les règles et s'affiche « Recette illisible ». Seul son auteur peut l'écrire, dans sa recette ou dans sa copie figée, et le
document reste borné à 1 Mio par Firestore. La lecture typée de l'application ignore un
champ inconnu, et la copie figée d'un brassin passe par ces types (`recipeSnapshot`) : un
champ inconnu d'une recette ne se recopie pas dans un brassin créé par l'application. Les
valeurs de la copie de l'équipement (`equipment_snapshot`) ne sont pas contrôlées à la
création d'un brassin, ses clés seules le sont (liste blanche d'`equipment/`) : un contrôle
de plus dépasse le budget ci-dessous. Une valeur mal typée (`notes` en map, par exemple)
y rend le brassin illisible (« Brassin illisible ») ; seul le brasseur qui crée le brassin
peut l'écrire, et l'application écrit cette copie à partir de ses types.

Effet de ces risques, écrit par un client autre que l'application :

- Une copie figée ou un élément de liste mal typé rend le brassin ou la recette illisible
  chez tous les membres. Aucun ne peut brasser ce brassin ni dupliquer cette recette. Seul
  l'auteur peut corriger le document ; l'administrateur passe par la console Firebase.
  Chaque lecteur envoie un rapport par session (`error_reports/`).
- Les champs d'enveloppe de `recipe_snapshot` (`owner_uid`, `created_at`, `updated_at`) ne
  sont pas contrôlés en valeur : seule leur clé figure dans la liste blanche.
- Une valeur bien typée mais hors bornes dans `equipment_snapshot` (rendement à 150 %,
  volume négatif) passe la lecture : les calculs du brassin sont refusés (« Calcul
  impossible ») ou faux chez tous les lecteurs.
- `bottles_count` réécrit de 5 en 5.0 est accepté : Firestore juge les deux valeurs égales,
  le champ ne figure pas parmi les champs changés (`isBrewUpdate`), et `is int` n'est pas
  revérifié. Sans effet sur l'application, qui lit `toInt()`.

L'effet reste limité à l'affichage du document concerné : les autres documents, les droits et
les prix ne changent pas.

**Budget des règles.** Une requête évalue 1 000 expressions au plus. Le contrôle d'une
recette en coûte environ 500 : la création d'un brassin passe par `isBrewCreateShape`, limité
aux champs de création. La modification d'un brassin (`isBrewUpdate`) ne contrôle que les
champs changés, groupe par groupe (`!changed.hasAny([...]) || contrôle`, avec
`changed = request.resource.data.diff(resource.data).affectedKeys()`) : un champ inchangé a
été contrôlé à son écriture, et la copie figée ne change plus. Contrôler tous les champs à
chaque modification dépassait la limite sur un brassin rempli après le brassage avec
5 ajustements (mesure de `securite`, branche L1 et `main` de la v0.1.13). Une erreur n'arrête pas
un `&&` : la règle de modification commence par `resource != null`, qui vaut faux à la
création. Comparer une liste à `null` coûte cher : les listes de `recipe` passent par
`optArray` (`d.get(k, []) is list`), plus économe qu'`optList`.

Mesure de la v0.1.15 sur l'émulateur : des appels `pad()` (environ 10 expressions chacun) sont
ajoutés à la règle jusqu'au refus ; 98 tiennent dans une règle `if true`.

| Écriture | Marge |
|---|---|
| Création d'une recette, la plus grande permise | environ 470 expressions (47 `pad()`) |
| Création d'un brassin qui la copie, tous les champs de création, équipement complet | environ 70 (7 `pad()`) |
| Brassin du 22 novembre rempli (`brewed_at`, notes, embouteillage, 3 mesures retenues, `sugars_in_wort`, équipement complet) avec 11 ajustements : changement de statut | plus de 930 (93 `pad()`, la compilation refuse au-delà) |
| Même brassin : embouteillage et statut changés ensemble | plus de 930 |
| Même brassin : nom, date prévue et notes de 10 000 caractères | plus de 930 |
| Même brassin sans ajustements : écriture des 11 ajustements | environ 470 (47 `pad()`) |
| Même brassin : tous les groupes changés sauf les ajustements | environ 570 (57 `pad()`) |
| Même brassin : tous les groupes changés, ajustements compris, par un `set()` | limite dépassée, écriture refusée |

Mesure de la v0.1.17, même méthode (`pad()` = `return true`, 98 tiennent dans une règle
`if true` seule), avec `recipe.author` contrôlé :

| Écriture | v0.1.15 | v0.1.17, sans `author` | v0.1.17, `author` de 120 caractères |
|---|---|---|---|
| Création d'une recette, la plus grande permise | 71 `pad()` | 69 | 64 (environ 640 expressions) |
| Création d'un brassin qui la copie, tous les champs de création, équipement complet | 10 `pad()` | 8 | 4 (environ 40 expressions) |
| Brassin du 22 novembre rempli, changement de statut ; embouteillage et statut | 93 `pad()` (limite de compilation) | 93 | 93 |
| Modification de la plus grande recette | non mesuré | non mesuré | 61 |
| Création d'un prix au litre (`users/{uid}/prices`, `unit` `l`) | non mesuré | non mesuré | 93 (limite de compilation) |
| Coût figé de 200 lignes, dont des lignes en `l` (`users/{uid}/brew_costs`) | 94 `pad()` | — | 94 |

Sur ce jeu, la v0.1.15 donne 71 et 10 `pad()` là où le tableau précédent note 47 et 7 ; les
comparaisons de la v0.1.17 sont faites sur le même jeu. `recipe.efficiency`, contrôlé par
quatre `optMeasure` ou par ses seules clés, faisait refuser la création de ce brassin (limite
dépassée sans aucun `pad()`) : il n'est pas stocké. Une recette qui porte style, ébullition,
empâtage, notes et auteur coûte le même contrôle que la plus grande permise : la longueur
des listes n'entre pas dans le budget, leurs éléments n'étant pas inspectés. Toute règle
ajoutée sur `recipe` se mesure contre les 40 expressions restantes à la création d'un brassin.

L'application n'écrit jamais tous les groupes d'un coup : sa plus grosse modification est
l'embouteillage avec le statut. Des tests rejouent la plus grande recette permise, un brassin
qui la copie avec tous les champs de création, et le brassin du 22 novembre avec
11 ajustements (`recipe_format.test.mjs`, « budget des règles »).

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
`users.test.mjs` rejoue `prices`, `fees`, `stock` et `brew_costs` pour les cinq profils
(lecture, liste, écriture d'un document valide, suppression), les écritures de chacun sous son
propre uid, et refuse champ inconnu, type faux, `unit` hors de `g`, `unit` et `l` (dont `ml`,
`L`, `kwh`, `kg`) ; il accepte un prix au litre pour les cinq profils (v0.1.17) et un coût figé
dont une ligne est en `l` ; montant négatif ou hors bornes, identifiant de prix hors du format de clé, `brew_id`
différent du chemin, plus de 200 lignes, `freeze_kind: initial` en modification et
`recalculation` en création ; il vérifie aussi la suppression du brassin et de son coût dans un
même lot.

`tickets.test.mjs` rejoue `tickets/` pour les cinq profils (création à son nom, lecture du
ticket d'un autre, liste filtrée sur `author_uid` et triée sur `created_at`, liste sans
filtre, marque de lecture, suppression), P11 (adresse non vérifiée, mot de passe, adresse en
majuscules, membre retiré), chaque borne de la création (titre de 4, 5, 100, 101 caractères
et sur deux lignes, description de 9, 10, 2 000, 2 001, écran avec identifiant réel,
version de 41 caractères, plateforme `ios`), chaque champ serveur refusé à la création et en
modification, `seen_by_author_at` à l'heure de l'appareil, une décision créée par le
brasseur ou l'admin (refusée en T1), et `ticket_quotas/`, `ticket_status/` pour les cinq
profils.

`recipe_format.test.mjs` (v0.1.15) rejoue la forme BeerJSON dans `recipes/` et dans la copie
figée : document plat de la v0.1.14, sans `format_version`, `format_version` 2 ou en texte,
unité `kg`, `°F` ou heure, unité sans valeur, durée décimale, listes de 51 (11 levures, 21
paliers), `water_additions`, champ hors liste ; maps fermées, en création et en
modification : `style.price_eur`, `boil.cost_eur`, `mash.stock_g`, `style` en texte, `boil`
et `mash` en liste ou en texte, `mash.name` en map ou de 121 caractères, liste nulle ou en
map, `type` hors schéma (« bière ») ou en map, refusés ; `type` absent ou `cider` accepté ;
modification de `recipe_snapshot` refusée, `set()` complet d'un brassin existant avec une
autre copie de la recette ou de l'équipement refusé, avec la même copie accepté ; création de
recette au format plat refusée pour les cinq profils ; remplacement de `recipe` d'un bloc par
`update`. `beerjson_schema.test.mjs`, sans émulateur, valide par ajv 8.20.0
(`ajv/dist/2020`) les trois fixtures de `toFirestore` (recette complète, recette réduite au
nom, copie figée) contre le schéma partiel, et vérifie que le schéma officiel refuse les deux
premières.

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
par `ErrorReportService.reportError` et affiche la panne. Les erreurs du coût (`cost.dart`) ne
portent jamais la valeur reçue (`requirePositiveHidden`, `requireNonNegativeHidden`,
`value` nul) : un prix, un montant ou une quantité saisis par le brasseur n'entrent pas dans
`error_reports/`, que l'admin lit (P13). L'application remplace en plus toute erreur d'un
calcul de coût par `CalculCoutRefuse`, qui ne porte que le type de l'erreur d'origine.

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
| Plato ↔ SG (v0.1.17) | `platoToSg`, `sgToPlato` | SG = 1 + P / (258,6 − (P / 258,2) × 227,1) ; P = −616,868 + 1111,14 × SG − 630,272 × SG² + 135,997 × SG³ (ASBC). Pas l'inverse exact l'une de l'autre : 12 °P → 12,002 °P. Densité hors de 0,980 – 1,200 refusée |
| SRM, Lovibond ↔ EBC (v0.1.17) | `srmToEbc`, `ebcToSrm`, `lovibondToEbc`, `ebcToLovibond` | EBC = SRM × 1,97 ; le degré Lovibond d'un grain est lu comme un SRM, comme dans Morey ci-dessus (une couleur importée donne la même couleur de bière que dans le logiciel d'origine) |
| Rendement donné en densité (v0.1.17) | `potentialToYieldPercent` | % = (potentiel − 1) × 1000 / 46,214 × 100 (`yield.potential` de BeerJSON, densité d'une livre dans un gallon) ; potentiel de 1,000 à 1,046214 |
| Nature et forme d'une valeur BeerJSON (v0.1.17) | `FermentableKind.ofType`, `HopForm.ofBeerJson` | voir `recipes/` : extrait, miel, fruit, jus comptés comme un sucre ; `plug` comme des cônes ; `other`, `powder`, `extract`, `leaf (wet)` sans valeur de calcul |
| Calculs d'une recette | `computeRecipe` | OG, FG, degré, IBU, EBC, IBU par houblon : voir « Calculs d'une recette » |
| Clé d'ingrédient | `ingredientKey`, `isValidIngredientName` | préfixe de nature + nom normalisé (voir `recipes/`) ; `BrewingInputException` pour un nom sans lettre ni chiffre, que `isValidIngredientName` détecte sans exception (une seule définition de la règle) |
| Coût | `computeCost` | Σ quantité × prix, coût de chaque ligne (`lineCosts`) ; par litre = total / V ; bouteille de 33 cl = par litre × 0,33 ; sans volume, total seul. Un prix manquant rend `CostUnavailable` |
| Prix unitaire d'un achat | `unitPrice`, `unitPriceFor` | prix payé / quantité achetée (47,50 € pour 25 000 g = 0,0019 €/g) ; prix nul permis, quantité nulle refusée ; `unitPriceFor` rend `null` quand l'unité de l'achat (`g`, `unit`, `l`) n'est pas celle de la ligne, un prix au gramme ne chiffre pas une ligne en litres, ni l'inverse (`CostUnit.litre`, v0.1.17 : prix au litre, aucune densité supposée) |
| Regroupement | `groupCostItems` | lignes de même clé additionnées, nom et place de la première (Cascade 20 g + 30 g = 50 g) |
| Frais | `feeQuantity`, `bottles33clIn` | 1 par brassin ; par bouteille, nombre de bouteilles du brassin, ou volume / 0,33 sans arrondi pour une recette |
| Levure | `yeastSachetsPerLine` | une ligne de levure vaut un sachet (hypothèse H1) |
| Coût par bouteille réelle, par litre | `costPerBottle`, `costPerLitre` | total / bouteilles (40,84 / 50 = 0,8168) ; total / volume conditionné |
| Planning | `recomputeSchedule` | heure attendue d'une étape = fin de l'étape précédente dans l'ordre de la chronologie (fin enregistrée, sinon début réel + durée prévue). En cours (`running`) : l'étape commencée sans fin au début le plus récent ; elle finit au plus tôt à `now`. Une autre étape commencée sans fin est faite (`done`), à début + durée. Sautée (`skipped`, événement `step_skipped`, sans début) et non faite (`notDone`, sans événement alors qu'une étape plus loin a commencé) : durée nulle. À venir (`pending`) : ne commence ni avant `now`, ni avant la fin de l'étape en cours. Un début l'emporte sur un saut |
| Événements d'étape | `stepRecordsFromEvents` | un `StepRecord` par étape : début le plus ancien (à égalité, le plus petit identifiant), dernière fin à ou après ce début, sauts, et les identifiants d'événement retenus. Sans exception, les autres événements sont rendus en `StepEventIssue` : `duplicateStart`, `duplicateEnd`, `endWithoutStart`, `endBeforeStart`, `unknownStep`, triés par heure puis identifiant. Même résultat sur chaque appareil |
| Chronologie préremplie | `defaultBrewSteps` | une étape par palier ; puis l'ébullition coupée à chaque ajout de houblon d'ébullition, du plus long au plus court (un houblon de t min s'ajoute après durée d'ébullition − t min) ; puis le whirlpool, coupé de même, sur la plus longue durée de ses houblons ; houblons à cru, à l'empâtage et au conditionnement exclus ; ajout de 0 min. Voir ci-dessous |
| Minuteur | `readTimer` | restant = début + durée − `now`, borné à zéro ; dépassement au-delà |

**Pas de valeur de repli.** Un prix manquant rend `CostUnavailable(linesWithoutPrice)`, jamais
un coût partiel. Dans l'application, `evaluerCoutRecette`, `evaluerEstimationBrassin` et
`evaluerFigeage` rendent soit un montant, soit la liste des raisons (`RaisonCout`) : prix
manquant (une ligne en volume sans prix comprise), unité incompatible (ligne en volume face à
un prix au gramme, ou l'inverse), quantités de deux unités sous un même nom (`QuantitesDeDeuxUnites` :
l'application les écarte avant `groupCostItems`, qui lèverait), prix illisible, ligne sans nom
utilisable, volume non
renseigné, aucun ingrédient, calcul impossible, prix indisponibles hors ligne, frais
illisible, sucre de resucrage sans nature, nombre de bouteilles absent avec un frais par
bouteille. Aucun frais saisi n'est pas une raison : le montant s'affiche avec sa mention. Sans sucre de resucrage, le degré après bouteille est absent : la hausse
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
| Densité initiale (OG) | volume (`batchVolume`), au moins un fermentescible (`fermentables`), nature de chacun (`fermentableKind`, v0.1.17 : `FermentableInput.kind` nul pour `other`), rendement d'extrait de chacun (`extractYield`), rendement d'empâtage si un malt est présent (`mashEfficiency`) |
| Densité finale (FG) | OG (`originalGravity`), une levure (`yeast`), atténuation de la première (`yeastAttenuation`) |
| Degré | comme la FG |
| IBU | houblons mesurés en volume exclus (`HopInput.massGrams` nul : 0 IBU, listés dans `hopsWithoutMass`, v0.1.17) ; volume ; aucun houblon à l'empâtage ni au conditionnement (`hopUse`) ; sans houblon d'ébullition, 0 IBU ; sinon OG, forme de calcul (`hopForm` : `HopInput.form` nul), acides alpha (`hopAlpha`) et durée (`hopBoilTime`) de chaque houblon d'ébullition |
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
au-delà de 1.200) lève `BrewingInputException`. Aucune formule ne change en v0.1.17 : Tinseth,
Morey et la densité initiale sont inchangés ; les cas ajoutés à `brewing/test/fixtures/`
(`recipe.json`, `ibu.json`, `brew_comparison.json`, `cost.json`, `conversions.json`) fixent
les nouvelles règles de lecture. `compareBrewWithPlan` rend l'écart `fermentableKind` pour un
fermentescible sans nature. Aucun calcul de rendement de brassage ni de volume avant ébullition
n'existe : l'export de L2b écrit le rendement d'empâtage de l'équipement (ADR-005, amendements
de L2), et `BOIL_SIZE` (BeerXML) attend L2c.

**Chronologie préremplie.** `defaultBrewSteps(mashSteps:, boilMinutes:, hops:)` reçoit les
paliers (`MashStepInput` : température et durée facultatives), la durée d'ébullition et les
houblons (`HopInput`). Il rend des `BrewStepDraft` : nature (`BrewStepKind` : `mashStep`,
`boil`, `hopAddition`, `whirlpool`), place du palier ou du houblon d'origine
(`sourceIndex`), durée, température et défaut éventuel (`BrewStepProblem`). Aucune durée
n'est inventée : un palier sans durée rend une étape sans durée (`durationMinutes` nul), qui porte `missingDuration` ; sans
durée d'ébullition, aucune étape d'ébullition, et les ajouts se suivent du plus long au plus
court. Les houblons à l'empâtage et au conditionnement n'ont pas d'étape. Un houblon sans
durée est placé en tête de sa section (`missingHopTime`) ; un houblon
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
`cost.json` porte aussi les prix unitaires (`unit_prices`, dont l'unité incompatible), le
regroupement par clé (`grouping`), la quantité des frais (`fee_quantities`), le coût par
bouteille réelle (`per_bottle`) et par litre (`per_litre`), et le critère de fin de la v0.5
(`brew_cases`) : Ale blonde 140724 (eau 1,66 € et électricité 2,00 € par brassin, 0,2122 €
par bouteille, 50 bouteilles) rend 40,84 € à 0,0001 € près, 40,82 € de la fiche à 0,05 € près,
et 0,8168 € la bouteille (0,82 € sur la fiche) ; Bière blonde 11-2-24 rend 49,05 €, 49,04 € et
0,7432 € (0,74 €). La même recette comptée sur 20 L rend 43,09 €. Le test
`app/test/costs_domain_test.dart` retrouve ces deux coûts par le calcul de l'application.
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

## Cloud Functions

`functions/` (ADR-006) : Cloud Functions 2e génération, Node 24, TypeScript, région
`europe-west1` (celle de la base), compte d'exécution `tickets-functions@<projet>`. Aucun
`onRequest` ni `onCall` (P25) : les deux fonctions ne s'appellent pas depuis Internet.

| Fonction | Déclencheur | Réglages | Ce qu'elle fait |
|---|---|---|---|
| `publishTicket` | `onDocumentCreated('tickets/{ticketId}')` | `maxInstances` 2, 256 Mio, 60 s, sans rejeu (la passe horaire renvoie) | publie le ticket `pending` |
| `syncTickets` | `onSchedule('every 60 minutes')`, heure de Paris | `maxInstances` 1, 256 Mio, 300 s, sans rejeu | renvoie les `pending`, relit les Issues |

Les deux lisent le secret `GITHUB_TICKETS_TOKEN` (`defineSecret`). `src/firestore.ts` charge le
SDK Admin au premier appel ; le client GitHub (`src/tickets/github.ts`, `fetch`, aucun SDK)
se construit à l'appel avec le jeton (P26). `src/logging.ts` journalise par
`firebase-functions/logger` (`logError` dans chaque `catch`) et retire tout ce qui a la forme
d'un jeton GitHub. Les règles pures (`src/tickets/model.ts`, `src/tickets/text.ts`) sont
testées par `node --test` (`functions/test/`).

**Publication** (`src/tickets/publish.ts`). Transaction : le ticket doit être `pending`, sans
numéro d'Issue ni bail actif. Au premier essai, le rôle de l'auteur est lu dans
`members/{author_email}` ; hors administrateur, les compteurs du jour de Paris sont lus et
incrémentés dans la même transaction, ou le ticket passe `over_quota`. Bail de deux minutes.
Si un essai précédent a commencé, l'Issue est d'abord cherchée dans la liste des Issues
`source:app` modifiées depuis `created_at` du ticket moins dix minutes (500 au plus) : seule
compte une Issue du compte 16348852 dont une ligne du corps est la ligne « Référence » du
ticket. La liste ne dépend pas de l'index de recherche de GitHub, en retard de quelques
minutes. Sinon elle est créée, avec
les étiquettes `source:app` et `type:<type>`. Succès : `received`, sans
`status_changed_at`. Échec réseau ou 5xx : un essai compté, `pending` gardé, `send_failed` au
dixième. Limite de débit : non comptée. Jeton refusé ou secret vide : non compté,
`token_invalid_since` posé.

**Gabarit de l'Issue** (P24). Titre : celui du ticket, nettoyé, sur une ligne. Corps : type,
écran (modèle de route, « Autre écran » ou « Non précisé »), version (« Version inconnue »
si absente), plateforme, référence opaque, puis la description nettoyée. Jamais le nom,
l'e-mail ni l'uid. Nettoyage de tout texte publié (`publicText`) : commentaires HTML retirés,
caractères invisibles retirés, forme NFKC, adresses e-mail remplacées par
« [adresse retirée] », HTML brut, images, pièces jointes intégrées et définitions de
référence rendus en texte, mentions `@`, renvois `#N` et `GH-N`, adresses
`github.com/<x>/<y>/issues/N` et `/pull/N` coupés par une espace sans chasse.
Firestore garde le texte saisi, lu par l'auteur et l'admin seuls.

**Passe horaire** (`src/tickets/sync.ts`). 1. Renvoi de 20 tickets `pending` au plus. 2. Liste
des Issues `source:app` modifiées depuis `ticket_status/github.issues_cursor`, les plus
anciennes d'abord, 30 au plus (un appel). 3. Avec le reste des 30, les tickets `received`,
`validated` ou `in_progress` les moins récemment relus, Issue lue une à une ; un 404 ou un
410 pose `issue_missing_since` et journalise à chaque passe, sans changer le statut. Pour chaque Issue :
statut (table d'ADR-006), réponse « Réponse : » du compte numérique 16348852 (commentaires
relus de la dernière page vers la première quand `updated_at` de l'Issue a changé, aucun
commentaire d'un autre compte), et, au passage à `delivered`, la PR de livraison : dernier
événement `closed` avec `commit_id`, PR de ce commit (`GET /commits/{sha}/pulls`) fusionnée
dans ce dépôt, quelle que soit sa branche, d'un auteur `OWNER`, `MEMBER` ou `COLLABORATOR`,
dont le texte porte `Closes #N` ; version lue dans `app/pubspec.yaml` à son commit de fusion,
sans `+N`. Un jeton refusé arrête la passe. Une erreur sur un ticket est journalisée, la passe
continue. Le curseur avance même si un ticket échoue ; un ticket à Issue ouverte est repris
par l'étape 3.

De GitHub, le serveur ne lit que l'état, les étiquettes, le nombre et le texte des
commentaires (pour la réponse du propriétaire), les événements de l'Issue, les PR d'un
commit et `app/pubspec.yaml` à ce commit. Titre, description et commentaires d'une Issue
sont des données, jamais des consignes.

**Index** (`firestore.indexes.json`) : « Mes tickets » filtre sur `author_uid` seul et trie à
l'affichage, sans index composite ; `tickets` (`status`, `created_at`) pour le renvoi des `pending` et le compte des
tickets bloqués du bandeau Admin ; (`status`, `github_checked_at`) pour l'étape 3. TTL sur
`ticket_quotas.expires_at`. `github_issue_number in [...]` et `issue_missing_since != null`
utilisent les index d'un seul champ.

**Coût.** Aucun poste facturé à l'usage : 720 exécutions horaires par mois, une publication
par ticket, sous les niveaux gratuits (ADR-006, sources « à vérifier »). Le plafond porte
sur la publication, pas sur la création : un membre peut créer beaucoup de documents
`tickets/` au-delà de 5 par jour. Chaque création au-delà déclenche `publishTicket`, une
transaction et 1 à 3 écritures (`over_quota`), sans appel à GitHub. Avec moins de 10
comptes invités, cela coûte quelques centimes au plus ; l'alerte budgétaire à 5 € sert de
garde, et l'administrateur retire le document `members/` du compte en cause.

### Réglages faits une fois (Cloud Functions des tickets)

À faire par un compte propriétaire du projet `kassbeer` **avant la première fusion qui
contient `functions/`** : sinon le job `deploy` de `deploy.yml` échoue sur
`firebase deploy --only functions`. Les rôles ajoutés à `github-deploy` restent à confirmer
au premier déploiement (ADR-005 : « sans déploiement d'essai ») ; un refus nomme le rôle
manquant, à ajouter seul.

```bash
PROJECT_ID=kassbeer
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
DEPLOY_SA="github-deploy@$PROJECT_ID.iam.gserviceaccount.com"
RUN_SA="tickets-functions@$PROJECT_ID.iam.gserviceaccount.com"
BUILD_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"   # compte de build par défaut
gcloud config set project "$PROJECT_ID"

# 1. API (github-deploy n'a que serviceUsageConsumer : il ne les active pas lui-même).
gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com run.googleapis.com eventarc.googleapis.com \
  pubsub.googleapis.com storage.googleapis.com secretmanager.googleapis.com \
  cloudscheduler.googleapis.com
# Compute Engine crée le compte compute par défaut, compte de build des Functions et cible
# des étapes 4, 5 et 7. Sur kassbeer, il n'existait pas avant cette activation.
gcloud services enable compute.googleapis.com

# 2. Compte d'exécution des fonctions : lit et écrit Firestore, reçoit les événements
#    Firestore et l'appel de Cloud Scheduler, lit le secret.
gcloud iam service-accounts create tickets-functions --display-name "Functions des tickets"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$RUN_SA" --role roles/datastore.user --condition=None
for role in roles/eventarc.eventReceiver roles/run.invoker; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$RUN_SA" --role "$role" --condition=None
done

# 3. Secret GITHUB_TICKETS_TOKEN (saisie masquée, sans retour à la ligne final).
gcloud secrets create GITHUB_TICKETS_TOKEN --replication-policy=automatic
read -rs TOKEN && printf '%s' "$TOKEN" | gcloud secrets versions add GITHUB_TICKETS_TOKEN --data-file=- && unset TOKEN
gcloud secrets add-iam-policy-binding GITHUB_TICKETS_TOKEN \
  --member "serviceAccount:$RUN_SA" --role roles/secretmanager.secretAccessor

# 4. Rôles de github-deploy pour les Functions.
for role in roles/cloudfunctions.admin roles/cloudscheduler.admin roles/run.admin \
            roles/artifactregistry.reader; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$DEPLOY_SA" --role "$role" --condition=None
done
for sa in "$RUN_SA" "$BUILD_SA"; do
  gcloud iam service-accounts add-iam-policy-binding "$sa" \
    --member "serviceAccount:$DEPLOY_SA" --role roles/iam.serviceAccountUser
done
gcloud secrets add-iam-policy-binding GITHUB_TICKETS_TOKEN \
  --member "serviceAccount:$DEPLOY_SA" --role roles/secretmanager.viewer

# 5. Liaisons des agents de service que firebase-tools pose au premier déploiement d'un
#    déclencheur Firestore et d'une tâche planifiée ; github-deploy ne modifie pas la
#    stratégie IAM du projet, elles se posent ici.
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role roles/iam.serviceAccountTokenCreator --condition=None
for role in roles/run.invoker roles/eventarc.eventReceiver; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$BUILD_SA" --role "$role" --condition=None
done

# 6. Artifact Registry : images des fonctions gardées un jour (ADR-006, 0,5 Go gratuits).
#    Le dépôt gcf-artifacts se crée au premier déploiement : lancer cette commande depuis le
#    poste juste après, ou créer le dépôt avant.
npx firebase functions:artifacts:setpolicy --location europe-west1 --days 1 --project "$PROJECT_ID"

# 7. Compte compute par défaut (compte de build des Functions), créé à l'étape 1 avec
#    roles/editor posé d'office : lister ses rôles.
gcloud projects get-iam-policy "$PROJECT_ID" --flatten=bindings \
  --filter="bindings.members:serviceAccount:$BUILD_SA" --format='value(bindings.role)'
#    S'il porte roles/editor (rôle posé d'office sur les anciens projets), le remplacer par
#    roles/cloudbuild.builds.builder, ou passer à un compte de build dédié. github-deploy
#    agit en son nom (serviceAccountUser) : roles/editor lui donnerait la main sur tout le
#    projet.
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BUILD_SA" --role roles/cloudbuild.builds.builder --condition=None
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BUILD_SA" --role roles/editor   # seulement s'il figure dans la liste

# 8. Compte App Engine par défaut : firebase-tools exige, avant tout déploiement de
#    Functions, que le compte qui déploie puisse agir en son nom (iam.serviceAccounts.actAs),
#    même si les fonctions tournent sous tickets-functions. Il porte roles/editor d'office ;
#    Kass'Beer ne l'utilise pas : retirer ce rôle, puis donner l'actAs à github-deploy.
APPSPOT_SA="$PROJECT_ID@appspot.gserviceaccount.com"
gcloud projects get-iam-policy "$PROJECT_ID" --flatten=bindings \
  --filter="bindings.members:serviceAccount:$APPSPOT_SA" --format='value(bindings.role)'
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$APPSPOT_SA" --role roles/editor --condition=None   # seulement s'il figure dans la liste
gcloud iam service-accounts add-iam-policy-binding "$APPSPOT_SA" \
  --member "serviceAccount:$DEPLOY_SA" --role roles/iam.serviceAccountUser
```

État relevé le 2026-11-10 sur `kassbeer` : le compte compute ne porte que
`cloudbuild.builds.builder`, `eventarc.eventReceiver` et `run.invoker` ; le compte App Engine
ne porte aucun rôle sur le projet. Le premier déploiement des Functions (run 17) a échoué faute
de l'actAs de l'étape 8.

`roles/run.admin` sert à `firebase-tools` pour donner au compte d'exécution le droit
d'appeler le service Cloud Run de la tâche planifiée (`run.services.setIamPolicy`).
`secretmanager.viewer` lit les métadonnées du secret, pas sa valeur. `github-deploy` obtient
pourtant un accès indirect aux données : par `serviceAccountUser` sur `tickets-functions`, il
déploie du code qui tourne avec `datastore.user` et lit le secret. Cet accès est inhérent au
déploiement des Functions ; `firebaserules.admin` l'ouvrait déjà, puisque des règles publiées
décident de qui lit quoi. Le garde-fou est le même : `deploy.yml` ne part que de `main`, après
une PR et une CI verte, et chaque diff de `.github/workflows/` ou de `functions/` passe en
relecture (P10, P14, P25).

**Jeton à grain fin** (GitHub › Settings › Developer settings › Fine-grained tokens), compte
propriétaire : dépôt `ChinaFred/KassBeer` seul ; permissions « Issues : Read and write »,
« Pull requests : Read-only », « Contents : Read-only », « Metadata : Read-only » (posée
d'office) ; rien d'autre. Durée : la plus longue que permet GitHub ; noter ici la date
d'expiration à chaque renouvellement. Renouveler : `gcloud secrets versions add
GITHUB_TICKETS_TOKEN --data-file=-`, puis relancer `deploy.yml` à la main (les fonctions
lisent la version épinglée au déploiement).

| Élément | Valeur |
|---|---|
| Expiration du jeton `GITHUB_TICKETS_TOKEN` | à noter à la création |

**Étiquettes GitHub** à créer une fois sur `ChinaFred/KassBeer` :

```bash
REPO=ChinaFred/KassBeer
gh label create "source:app" --repo "$REPO" --color 0E8A16 --description "Ticket envoyé depuis l'application"
gh label create "type:bug" --repo "$REPO" --color D73A4A --description "Ticket : bug"
gh label create "type:evolution" --repo "$REPO" --color A2EEEF --description "Ticket : évolution"
gh label create "type:feature" --repo "$REPO" --color 7057FF --description "Ticket : nouvelle fonctionnalité"
gh label create "validé" --repo "$REPO" --color 0075CA --description "Ticket validé par l'administrateur"
gh label create "statut:en-cours" --repo "$REPO" --color FBCA04 --description "Une session travaille sur ce ticket"
gh label create "statut:clos" --repo "$REPO" --color 6A737D --description "Ticket clos par l'administrateur"
```

**Ruleset de `main`** : ajouter le contrôle « Functions — lint, build, tests » aux contrôles
requis.

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
| Version et outillage | `git fetch --tags`, puis `node scripts/check-version.mjs` : sur une PR avec `--base origin/<base de la PR>` (HEAD est le commit de fusion préparé par GitHub) ; sur un push de `main` avec `--base <commit d'avant le push>` ; sur un push d'une autre branche, contre `origin/main`. Non lancé sur un lancement manuel. Puis `node scripts/check-agents.mjs` et `node --test scripts/*.test.mjs` (dont `changelog-recent.test.mjs`) |
| Flutter et brewing | Flutter 3.44.6. Dans `brewing/` : `dart pub get`, `pubspec.lock` à jour, `dart analyze --fatal-infos`, `dart format` vérifié, `dart test`. Dans `app/` : `flutter pub get`, `pubspec.lock` à jour, `node scripts/changelog-recent.mjs` (asset des nouveautés régénéré), `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test`, `flutter test`, `flutter build web --release` sans configuration Firebase |
| Règles — émulateur | Node 22, Java 21 (Temurin), `npm ci` et `npm test` dans `rules-tests/` (projet `demo-kassbeer`). Binaires de l'émulateur en cache |
| Functions — lint, build, tests | Node 24, dans `functions/` : `npm ci`, `npm run lint` (ESLint et Prettier), `npm run build`, `npm test`, puis manifeste des fonctions (`firebase-functions` avec `FUNCTIONS_MANIFEST_OUTPUT_PATH`) : échec si une fonction a un déclencheur HTTP, callable, bloquant ou de file, ou n'a pas de `maxInstances` (P25) |
| Android — compilation | quand le diff touche `app/pubspec.yaml`, `app/pubspec.lock` ou `app/android/`, et toujours sur un lancement manuel : `node scripts/changelog-recent.mjs`, puis `flutter build apk --release`, Java 17, signé par une clé jetable générée par `keytool` dans le job. Sinon le job réussit sans compiler |

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
| `gate` | aucun, `contents: read` | vérifie que le commit est la tête de `main` ; sinon s'arrête en vert. Décide du déploiement des Functions : `git diff HEAD^1 HEAD -- functions/` non vide, ou lancement manuel |
| `plan` | `production`, `id-token: write` | vérifie la configuration ; lit la version de `app/pubspec.yaml` ; obtient un jeton Google de 5 minutes ; lit la dernière version publiée sur App Distribution et décide s'il faut un nouvel APK |
| `build` | `production`, `contents: read` | `node scripts/changelog-recent.mjs`, puis build web et, si besoin, APK signé, avec `--dart-define-from-file` ; dépose les deux en artefacts conservés un jour |
| `build-functions` | aucun, `contents: read` | quand `gate` le décide : `npm ci`, `npm run build`, manifeste `functions/functions.yaml` (mêmes contrôles P25 que la CI) ; dépose `functions/lib` et `functions.yaml` en artefact conservé un jour |
| `deploy` | `production`, `id-token: write` | revérifie la tête de `main` ; installe `firebase-tools` depuis `rules-tests/package-lock.json` avant l'authentification ; relit par `jq`, avant l'authentification, le manifeste `functions.yaml` de l'artefact (aucun déclencheur HTTP, callable, bloquant ou de file, `maxInstances` partout, compte `tickets-functions`, aucun secret autre que `GITHUB_TICKETS_TOKEN`) ; `firebase deploy --only hosting,firestore:rules,firestore:indexes` ; si `gate` l'a décidé, `firebase deploy --only functions` depuis l'artefact ; publie l'APK sur App Distribution |
| `tag` | aucun, `contents: write` | après un `deploy` réussi seulement : lit la version de `plan` (sans `+N`) et pose par l'API le tag annoté `vX.Y.Z` sur le commit déployé, au nom de `github-actions[bot]` (adresse `noreply`, P15). Un tag déjà présent n'est ni recréé ni déplacé (avertissement s'il pointe ailleurs). Aucune extraction du code, aucun secret, aucun accès à Google Cloud |

Le code compilé (dépendances pub, Gradle, npm de `functions/`) tourne dans `build` et
`build-functions`, qui n'ont pas de jeton OIDC. Les jobs qui ont un accès à Google Cloud ne
compilent rien. Pour les Functions, `deploy` ne lance ni `npm ci` ni `tsc` dans `functions/` :
le predeploy de `firebase.json` vérifie seulement que `lib/index.js` et `functions.yaml` sont
là, et `firebase-tools` lit `functions.yaml` au lieu de charger le code (P14). Cloud Build
installe les dépendances de production depuis `functions/package-lock.json`, côté Google ;
`gcp-build` vide empêche qu'il recompile. Un déploiement des Functions en échec se rejoue par
un lancement manuel de `deploy.yml`, qui les redéploie toujours.

Le tag arrive après la CI verte du commit, ce qui évite l'échec de `check-version.mjs` décrit
par la leçon 16 : sur `workflow_run`, le workflow démarre à la fin de cette CI ; sur un
lancement manuel, `tag` lit le run CI `push` du commit et ne pose rien tant qu'il n'est pas
`completed` et `success`. Seule une réponse 404 compte comme « tag absent » ; toute autre
erreur de l'API fait échouer le job sans rien créer. Une version dont le déploiement échoue
ne reçoit pas de tag : relancer `deploy.yml` à la main après la correction le pose.

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
cinq contrôles « Version et outillage », « Flutter et brewing — analyse, format, tests,
build web », « Règles — émulateur », « Functions — lint, build, tests » et « Android —
compilation ». Le job Android réussit
sans compiler quand le diff ne touche pas Android : il peut être exigé. Sur les
tags `v*` : ni suppression, ni mise à jour, ni force push. Seul le propriétaire a le droit d'écrire sur le
dépôt, à une exception : le job `tag` de `deploy.yml` crée les références `refs/tags/v*` au
nom de `github-actions[bot]`, ce que le ruleset des tags permet (il n'interdit que la
suppression, la mise à jour et le force push). Un `deploy.yml` modifié et fusionné sur `main` obtient l'accès du compte
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
les index et App Distribution ; il ne lit ni n'écrit les données Firestore. Les Functions
ajoutent les rôles de « Réglages faits une fois (Cloud Functions des tickets) ». Si la CLI
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
| Workload Identity Federation | pool `github`, fournisseur `kassbeer-deploy`, compte de service `github-deploy`, rôles listés dans « Réglages faits une fois » (cinq au départ, plus ceux des Functions) |
| GitHub, environnement `production` | règle de branche `main` posée ; les dix variables et les quatre secrets de signature posés |
| Plan GitHub | Free, dépôt public depuis le 2026-11-07 (ADR-002). Minutes des runners standard gratuites. Le run 42366279942 a lu 9 variables de `production` sur 10, avant la pose des secrets ; le run 42381643401 a lu les 10 variables et les 4 secrets |
| GitHub, rulesets | `main` : PR requise, 0 approbation, fusion par commit de fusion, quatre contrôles requis, à jour avec `main`, ni force push ni suppression ; tags `v*` : ni suppression ni mise à jour ; aucun contournement |
| GitHub, sécurité | approbation des workflows pour tout contributeur externe, actions limitées, secret scanning, push protection, alertes Dependabot, signalement privé de failles |

Les secrets de signature se posent par les quatre commandes `gh secret set` de
« Réglages sur GitHub », les deux mots de passe en saisie masquée. Un secret absent fait
échouer le job `build`, avant toute mise en ligne (« Secrets absents de l'environnement
production »).

### Passage au modèle BeerJSON (v0.1.15) : commande d'effacement

Outil à usage unique, `effacement-l1/` (Node 22, `firebase-admin` 14.5.0, son propre
`package.json`), pour le déroulé d'ADR-005 (« Calendrier et passage en production »). Il sort
du dépôt à la livraison suivante.

| Commande | Effet |
|---|---|
| `node effacer.mjs rapport --projet <id>` | compte rendu sans écriture : nombre de recettes ; chaque brassin avec son statut, sa date, son nombre d'événements et son coût figé (`users/{owner_uid}/brew_costs/{id}`) ; nombre de coûts figés ; événements orphelins (brassin absent qui garde des `events/`), nommés ; documents hors modèle (autre sous-collection), nommés |
| `node effacer.mjs effacer --projet <id> [--sauvegarde <dossier>]` | même compte rendu ; refus si un brassin est en `brewing` (code 2) ou si un document est hors modèle (code 5), avant la copie ; copie JSON de `recipes/` et `brews/` (événements et orphelins compris) dans `import/backup/`, ignoré par Git, sans aucun coût figé ; saisie du nom du projet ; compte rendu refait : refus si un brassin est passé en `brewing` (code 2), si un document ou un coût figé a été ajouté, retiré ou modifié depuis la copie (`updateTime`) ou si les nombres diffèrent (code 5), rien n'étant effacé ; `recursiveDelete` de `recipes/` et `brews/`, puis suppression de chaque coût figé à sa date de modification ; nombres effacés ; chaque coût figé dont la suppression échoue, écrit avec son chemin et le message d'erreur, en code 0 comme en code 4 ; contrôle qu'aucun document ne reste sous `recipes/` et `brews/` ni aucun coût figé effacé, et que `equipment/`, `users/` (hors des coûts figés effacés), `members/` et `error_reports/` ont le même nombre de documents |

Lancer la commande depuis PowerShell ou Windows Terminal : sous Git Bash (mintty),
`process.stdin.isTTY` peut manquer, et l'outil refuse alors l'effacement en production.
Recettes, brassins et événements se comptent et se copient par un seul parcours
(`listDocuments`, sous-collections comprises), qui lit aussi un brassin absent gardant des
`events/`. Le coût figé d'un brassin est celui de son propriétaire
(`users/{owner_uid}/brew_costs/{id}`) ; un coût posé sous un autre compte, ou celui d'un
brassin déjà supprimé, reste en place.

Les coûts figés sont comptés et effacés sans être lus ni copiés, y compris ceux de
l'administrateur (décision du 2026-11-10) : ils portent les prix de chaque brasseur. L'outil
les lit sans champ (`getAll` avec un `fieldMask` vide), pour leur existence et leur
`updateTime`. Le décompte de `users/` se fait de la même façon : aucun prix ne passe par
l'outil. Un coût figé effacé ne se retrouve que dans la sauvegarde quotidienne de Firestore.

La relecture et `recursiveDelete` sont séparés de quelques secondes. Une écriture faite dans
cet intervalle est effacée sans figurer dans la copie. D'où l'arrêt de l'usage demandé à
l'étape 1 du déroulé d'ADR-005, et la sauvegarde quotidienne gardée 7 jours.

Contrôles faits avant toute connexion : `GOOGLE_APPLICATION_CREDENTIALS` posé est refusé
(identifiants par `gcloud auth application-default login` seulement, aucune clé JSON) ; seuls
le projet `kassbeer` et un projet `demo-` avec `FIRESTORE_EMULATOR_HOST` sont permis (avec
l'émulateur, l'outil ne parle qu'à lui ; un projet `demo-` sans émulateur est refusé) ; en
production, `effacer` exige un terminal (entrée standard redirigée refusée) ; une sauvegarde
dans le dépôt hors de `import/` est refusée ; un dossier de sauvegarde dans un autre arbre
Git, autre dépôt ou autre worktree, est refusé même si Git l'y ignore, car une configuration
Git de l'environnement (fichier d'exclusion global, `GIT_CONFIG_*`) peut faire paraître ignoré
un dossier suivi ; dans `import/` de ce dépôt, `git check-ignore` doit dire le fichier de la
copie ignoré. Risque accepté : le chemin est jugé tel qu'il est écrit. Une jonction posée
à la main dans `import/` vers un dossier suivi, ou l'outil copié dans un autre dépôt qui
n'ignore pas `import/`, ferait accepter un dossier suivi ; l'outil sert une fois, lancé par
l'administrateur sur son poste. Un dossier hors de tout arbre Git est accepté, et seulement quand
`git rev-parse` répond « not a git repository » : toute autre erreur (`safe.directory`, chemin
trop long pour Git, dossier illisible) est refusée. Git est lancé en messages anglais
(`LC_ALL=C`) et sans `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE`,
`GIT_CEILING_DIRECTORIES` ni `GIT_DISCOVERY_ACROSS_FILESYSTEM`, qui changeraient le dépôt
découvert. Les événements comptés sont ceux de chaque
brassin (`brews/{id}/events`), jamais un `collectionGroup("events")`, qui compterait aussi un
`events/` sous `users/`. Codes de sortie : 0 fait, 1 usage ou lancement refusé, 2 brassin en
cours, 3 nom du projet refusé, 4 effacement incomplet ou collection protégée modifiée,
5 document hors modèle, ou `recipes/`, `brews/` et coûts figés différents de la copie (rien
n'est effacé). Tests contre l'émulateur seul
(`effacer.test.mjs`), depuis `rules-tests/` :
`npx firebase --config ../firebase.json emulators:exec --only firestore --project demo-kassbeer "node --test ../effacement-l1/effacer.test.mjs"`,
après `(cd effacement-l1 && npm ci)`.

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

| Service | Appelé par | Usage | Accès |
|---|---|---|---|
| API REST GitHub (`api.github.com`) | `functions/` seul | créer une Issue, chercher une Issue par référence, lire Issues, commentaires, événements, PR d'un commit, `app/pubspec.yaml` à un commit | jeton à grain fin `GITHUB_TICKETS_TOKEN` (Secret Manager), en-tête `x-github-api-version: 2022-11-28` |

## Coûts variables
