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
| `brewing/` | calculs de brassage, Dart pur (voir « Calculs de brassage ») |
| `exchange/` | import et export de recettes BeerJSON et BeerXML, Dart pur, dépend de `brewing/` et de `xml` (ADR-005, voir « Échange de recettes ») |
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
| `lib/core/presentation/` | `AppShell` (rail défilable ; titre et retour reçus de la route ; menu du compte), `NouveautesScreen`, `breakpoints.dart` (seuils 600 / 840 et largeurs `kFormMaxWidth` 400, `kDialogMaxWidth` 480, `kMessageMaxWidth` 480, `kAccountMenuMaxWidth` 280, `kRailLabelMaxWidth` 160 (libellé d'une destination du rail non étendu, réduit par `FittedBox` au-delà), `kContentMaxWidth` 840, `kEditorMaxWidth` 920, `kCalculationPanelWidth` 340, `kCalculationTileMinWidth` 120 à multiplier par l'échelle du texte, `kCompactMaxHeight` 480, `kBrewDayActionsMaxWidth` 480, `kBrewDayChronologyMaxWidth` 480, `kBrewDayMaxWidth` 1200, `kReleveChampMinWidth` 140 et `kComparaisonValeurMinWidth` 96, à multiplier par l'échelle du texte), `etats.dart` (`EtatChargement`, `EtatVide` avec action facultative, `EtatErreur` avec libellé de nouvelle lecture, `IndicateurBouton`), `BandeauHorsLigne`, `BandeauListePerimee`, `Etiquette`, `showFeuilleOuDialogue`, `formats.dart` (affichage à la française, `formatDateLongue`, `lireNombre`, `erreurNombre`), `ChampNombre` (mode entier, minimum), `PageDocument` (états d'une page de document), `EditeurPleinEcran` et `montrerChamp` (défilement vers le premier champ en erreur), `ecriture.dart` (`suivreEcriture`, `annoncerRefus`, `annoncerAvecAnnulation`, `annoncerAvecAction` (10 s, bouton facultatif), confirmations d'abandon, de suppression, `confirmerAction` et `confirmerActionOuAlternative` (« Annuler », une autre action, la confirmation ; boutons empilés quand la largeur manque)), `fiche.dart` (`LigneFiche`, `TitreSection`, `LigneDeuxNiveaux`, `TexteAbsent`, `SectionRepliable`), `LigneEditeur` (ligne d'une liste d'éditeur avec menu ⋮), `LogoKassBeer` ; `segments.dart` (`BoutonsSegmentes`, `segmentsTiennent` : choix par segments qui passent en colonne quand les libellés, mesurés avec l'échelle du texte, ne tiennent pas ; éditeur des recettes et formulaire de prix) |
| `lib/core/fichiers/` | `EchangeFichiers` (ADR-007) : `choisir(maxOctets)` rend `ChoixAnnule`, `FichierChoisi` (nom, octets), `FichierTropGros` (taille ou `null`) ou `ChoixImpossible` ; `modes` (Android : `enregistrer`, `partager` ; web : `telecharger`) et `envoyer` rendent `EnvoiFait`, `EnvoiAnnule` ou `EnvoiImpossible`. `EchangeFichiersPlateforme` : canal `fr.kassbeer/files` sur Android, `fichiers_web.dart` (`package:web`) sur le web, `fichiers_web_stub.dart` hors du web (import conditionnel) ; fourni par `echangeFichiersProvider` |
| `lib/core/services/screen_wakelock.dart` | `ScreenWakelock` (verrou compté, une remontée d'erreur par session), `KeepScreenAwake` |
| `lib/core/theme/app_theme.dart` | thème Material 3, seul fichier où une couleur est écrite |
| `lib/features/auth/` | `AuthRepository` (Firebase Auth, Google, `currentTokenName`), état d'accès, `grantedAccessProvider`, écrans Chargement, Connexion, Compte non invité, Erreur |
| `lib/features/members/` | `MembersRepository` (`members/`), `Member`, Admin › Membres |
| `lib/features/equipment/` | `EquipmentRepository` (`equipment/`), `Equipment`, `EquipmentContent`, `EquipmentKind` ; liste, fiche, éditeur |
| `lib/features/recipes/` | `RecipesRepository` (`recipes/`, `updateBrewSteps`, `newStepKey`) ; `domain/recipe.dart` : `Recipe`, `RecipeContent` et ses lignes, conversion document BeerJSON ↔ `brewing/`, tri, duplication ; `domain/beerjson.dart` : unités canoniques, lecture des couples `{value, unit}`, valeurs énumérées du schéma et leurs libellés (`EnumerationBeerJson`), `verifierVersionFormat` ; `domain/chronologie.dart` : `BrewStepLine`, lecture et validation de `brew_steps`, durées dérivées ; liste, fiche, éditeur, éditeur de chronologie, `ContenuRecette` (sections partagées avec le brassin et la recette publique ; `momentsOrigine` ajoute « moment d'origine : … » à un houblon), formulaires des lignes (`ListeBeerJson` : liste déroulante d'une valeur BeerJSON, « Non précisé » en tête), vue des calculs (`libelleManque`, et `libelleManqueExport` pour l'export et l'aperçu de l'import) ; `domain/import_recettes.dart` : `preparerImport` (recette lue par `exchange/`, relue par `RecipeContent.fromFirestore`, « Déjà importée » par l'empreinte), `avecEquipement` ; `presentation/import_recipes_screen.dart` (Recettes › Importer, `statutImport` : l'auteur retenu est le nom du jeton (`currentTokenName`, lu une fois avant le premier aperçu), celui qu'écrit l'import ; statuts mémorisés par équipement et lignes construites à l'écran par `ListView.builder` : un appui sur une case avec 500 recettes prend 53 ms en test), `export_recipe_sheet.dart` (feuille « Exporter » : « Auteur dans le fichier : {nom}. » lu dans `ExportPret.auteur`, boutons radio inactifs pendant un envoi), `libelles_echange.dart` (refus, modifications, fichiers refusés, pertes) |
| `lib/features/brews/` | `BrewsRepository` (`brews/`, `brews/{id}/events/`, jamais de transaction ; un déroulé illisible est rapporté sous `brews.process`, une chronologie figée illisible sous `brews.brew_steps`), `Brew`, `BrewEvent`, `BrewStatus`, `MeasureType`, `PhaseEvenement` ; `domain/deroule.dart` (ADR-009) : `Deroule`, `JourneeDeroulee`, `EtapeDeroulee`, `lireDeroule` (lecture de `process`, illisible avec sa raison, sans repli), `erreurDeroule` (contrôle avant écriture, clés d'étapes uniques sur toutes les journées) ; `Brew.deroule`, seul accès aux étapes d'un brassin (P37) : `process` s'il existe, sinon une journée de brassage tirée de `recipe_snapshot.brew_steps` ; `domain/assemblage_deroule.dart` (`assemblerDeroule`, `ecartDuProcessus`, v0.1.30) ; `setProcess` du dépôt ; `presentation/choix_processus.dart` (« Processus » et « Déroulé prévu »), `section_deroule.dart` (section « Déroulé » de la fiche), `changer_processus.dart`, `libelles_deroule.dart` ; `domain/mesures_retenues.dart` (mesures retenues, VR1, VR2, RR2), `domain/releves.dart` (regroupement du relevé) ; liste, fiche, « Nouveau brassin », `presentation/releve_fermentation.dart`, `prevu_et_mesure.dart`, `embouteillage.dart`, `courbe_fermentation.dart`, `trace_courbe.dart` (seul import de `fl_chart`, P18) |
| `lib/features/costs/` | `CostsRepository` (`users/{uid}/prices`, `fees`, `brew_costs`, jamais de transaction ni de `Source.server`, `brewCostRef`) ; `domain/price.dart` (`Price`, `purchaseUnitOf`, `isUnusualPrice`), `domain/fee.dart` (`Fee`), `domain/brew_cost.dart` (`BrewCost`, `BrewCostLine`, `FreezeKind`) ; `domain/cost_evaluation.dart` : clés dérivées des lignes de `RecipeContent` (`ingredientsDeRecette`), raisons d'un coût indisponible (`RaisonCout`), `evaluerCoutRecette`, `evaluerEstimationBrassin`, `evaluerFigeage`, déclencheur du figeage (`doitFigerAuPremierEmbouteillage`), boutons proposés (`figerLeCoutPropose`, `recalculerPropose`), écart avec l'embouteillage (`ecartsDepuisFigeage`) ; `data/figeage_embouteillage.dart` (`enregistrerEmbouteillage` : embouteillage puis coût, sans attente) ; `presentation/costs_providers.dart` (`pricesProvider`, `feesProvider`, `brewCostProvider`, `costReportsProvider`) ; `presentation/prices_screen.dart` (« Mes prix », route `/prix`), `price_form.dart` (`ouvrirFormulairePrix` : nouveau, manquant, modification ; « Reprendre un de mes prix »), `fee_form.dart`, `bloc_cout.dart` (`BlocCoutRecette`, lignes des raisons et du détail), `bloc_cout_brassin.dart` (`BlocCoutBrassin` : estimation, « Figer le coût », coût figé, écart, « Recalculer avec mes prix actuels »), `formats_cout.dart` (euros, kilogrammes et euros par kilogramme à l'affichage ; aucun calcul de coût) |
| `lib/features/processes/` | modèles de processus (ADR-009, lot D2). `domain/modele_processus.dart` : `ModeleProcessus` (avec `hasPendingWrites`), `ContenuModele`, `JourneeModele`, `ElementModele`, `NatureElement` (lecture de `process_templates/`, champ inconnu ignoré, `DocumentIllisible` sinon ; écriture en liste blanche ; `erreurModele` : bornes, clés uniques, puis contraintes d'ADR-009 par `processTemplateIssue` de `brewing/` ; `copieModele` : clés neuves de journées et d'éléments, nom coupé à 120 caractères) ; `domain/modele_exemple.dart` : `modeleExemple` (trois journées acceptées le 2026-11-11, nom « Brassage, houblonnage à cru, embouteillage », note « Durées typiques, à ajuster à votre matériel. », clés neuves à chaque copie), écrit seulement à « Enregistrer » après « Partir du modèle d'exemple » ; `domain/preference_processus.dart` : `PreferenceProcessus`, `idModeleParDefaut`. `data/processes_repository.dart` : `ProcessesRepository` (`watchAll` avec `includeMetadataChanges`, document illisible isolé en `DocumentInvalide` et rapporté sous `processes.read` ; `create`, `update`, `copy`, `duplicate` (« {nom} (copie) »), `delete`, `newKey` = `doc().id` ; `erreurModele` vérifié avant chaque écriture, refus `ModeleInvalide` rapporté sans rien écrire ; aucune transaction). `data/preferences_processus_repository.dart` : `PreferencesProcessusRepository` (`watch(uid)`, `saveDefault` par `set` de `default_template_id` et `updated_at`). `presentation/` : `processes_providers.dart`, `process_list_screen.dart` (« Mes processus »), `process_detail_screen.dart` (fiche, `textesProcessus` ; le défaut n'est remis à nul qu'après l'acceptation de la suppression de son processus), `process_editor_screen.dart` (éditeur plein écran en un `CustomScrollView`, une `SliverReorderableList` par journée dans un `SliverMainAxisGroup` ; `FormulaireEtape` des recettes, `LigneEditeur` ; « Proposer par défaut » coché seulement quand l'absence de défaut est lue avec certitude), `formulaire_journee.dart`, `libelles_processus.dart` (résumés ; durées par `dureeChronologie` et `decalagesChronologie`, P3) |
| `lib/features/brew_day/` | `PlanDuJour` (chronologie dérivée par `brewing/`, journée de brassage du déroulé : événements réduits sur les étapes de toutes les journées, horaire recalculé sur celles de la journée), `AlerteMinuteur` (canal `fr.kassbeer/alert`, Web Audio), écran du jour, « Préparer le brassage », formulaire de mesure, `IndicateurEnvoi`, `RepriseBrassage` |
| `lib/features/library/` | Bibliothèque (ADR-005, L4) : `LibraryRepository` (`beer_index/`, `beer_*/`, `public_recipes/`, `get()` seul) ; `domain/referentiel.dart` : `NatureReferentiel` (document d'index et collection), `IndexReferentiel` et ses entrées (`EntreeStyle`, `EntreeFermentable`, `EntreeHoublon`, `EntreeLevure`, `EntreeDivers`), `FicheReferentiel` et ses fiches, `Plage`, `Provenance`, `normaliserRecherche` ; `domain/recette_publique.dart` : `RecettePublique` (`recipe` lu par `RecipeContent.fromFirestore`, `announced` en `ValeursAnnoncees`, `source_hop_timing` en `momentsOrigine`, `provenance`, `style_id`), `copie` pour « Dupliquer » ; `presentation/` : `LibraryScreen` (segments, recherche, listes), `ReferenceEntryScreen`, `PublicRecipeScreen`, `DataSourcesScreen`, `library_providers.dart` (`SegmentBibliotheque`), `libelles_bibliotheque.dart` (plages, sources, provenance ; affichage seul) |
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
| `errorReportServiceProvider`, `authRepositoryProvider`, `membersRepositoryProvider`, `recipesRepositoryProvider`, `equipmentRepositoryProvider`, `brewsRepositoryProvider`, `costsRepositoryProvider`, `processesRepositoryProvider`, `preferencesProcessusRepositoryProvider`, `appVersionProvider` | `Provider` | services fournis par `main.dart` (`overrides`) ou par les tests ; sans valeur par défaut |
| `sessionUserProvider` | `StreamProvider<SessionUser?>` | `authStateChanges()` |
| `memberLookupProvider(emailKey)` | `StreamProvider.family<MemberLookup, String>` | `members/{email en minuscules}`, avec les métadonnées |
| `accessStateProvider` | `Provider<AccessState>` | `AccessLoading`, `AccessSignedOut`, `AccessNotInvited`, `AccessFailed`, `AccessGranted(user, member, offline)` |
| `accessRefreshingProvider` | `Provider<bool>` | nouvelle lecture en cours (boutons « Réessayer », « Vérifier à nouveau ») |
| `membersListProvider` | `StreamProvider.autoDispose<List<Member>>` | `members/` entier, admin seul |
| `grantedAccessProvider` | `Provider<AccessGranted?>` | membre connecté (uid, nom, `offline`), `null` pendant une transition |
| `recipesListProvider` | `StreamProvider.autoDispose<ListeLue<Recipe>>` | `recipes/` entier, avec `fromCache` |
| `equipmentListProvider` | `StreamProvider.autoDispose<ListeLue<Equipment>>` | `equipment/` entier, avec `fromCache` |
| `brewsListProvider` | `StreamProvider.autoDispose<ListeLue<Brew>>` | `brews/` entier, avec `fromCache` |
| `libraryRepositoryProvider` | `Provider<LibraryRepository>` | fourni par `main.dart` ou par les tests ; sans valeur par défaut |
| `indexReferentielProvider(nature)` | `FutureProvider.autoDispose.family` | `beer_index/{nature}` par `lireIndex` ; une panne s'affiche, « Réessayer » invalide |
| `ficheReferentielProvider((nature:, id:))` | `FutureProvider.autoDispose.family` | `beer_*/{id}` par `lireFiche` |
| `recettePubliqueProvider(id)` | `FutureProvider.autoDispose.family` | `public_recipes/{id}` par `lireRecettePublique` |
| `nouveautesSourceProvider` | `Provider<Future<String> Function()>` | lecture de `assets/changelog_recent.json` par `rootBundle` ; remplacée par les tests |
| `nouveautesRepositoryProvider` | `Provider<NouveautesRepository>` | lecture journalisée des nouveautés |
| `nouveautesProvider` | `FutureProvider.autoDispose<List<Nouveaute>>` | versions de l'écran « Nouveautés », sans nouvel essai automatique |
| `brewEventsProvider(brewId)` | `StreamProvider.autoDispose.family<ListeLue<BrewEvent>, String>` | saisies d'un brassin, `hasPendingWrites` par document |
| `pricesProvider(uid)`, `feesProvider(uid)` | `StreamProvider.autoDispose.family<ListeLue<…>, String>` | prix et frais du compte connecté, lus par « Mes prix », la fiche d'une recette et celle de ses brassins ; jamais ceux d'un autre |
| `brewCostProvider((uid:, brewId:))` | `StreamProvider.autoDispose.family<RechercheDocument<BrewCost>, …>` | coût figé d'un brassin, lu par la fiche pour son propriétaire seul |
| `processTemplatesProvider` | `StreamProvider.autoDispose<ListeLue<ModeleProcessus>>` | `process_templates/` entier, avec `fromCache` ; lu à l'ouverture de « Mes processus », pas au lancement |
| `processPreferenceProvider(uid)` | `StreamProvider.autoDispose.family<RechercheDocument<PreferenceProcessus>, String>` | choix par défaut du compte connecté, lu par la liste, la fiche et l'éditeur ; jamais celui d'un autre |
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

**Choix et partage d'un fichier (ADR-007).** `EchangeFichiers` (`lib/core/fichiers/`). Sur
Android, `MethodChannel('fr.kassbeer/files')`, méthodes `pickDocument` (`maxBytes`),
`shareFile` et `saveDocument` (`name`, `mimeType`, `bytes`), définies dans
`EchangeFichiers.kt` et branchées par `MainActivity.configureFlutterEngine` (P17) :

- `pickDocument` : `ACTION_OPEN_DOCUMENT`, `CATEGORY_OPENABLE`, type `*/*` (le format se lit au
  contenu). `OpenableColumns.SIZE` au-delà de `maxBytes` rend `TOO_LARGE` (taille en `details`)
  sans ouvrir le flux ; sinon lecture bornée à `maxBytes + 1` octets, `TOO_LARGE` sans taille
  au-delà. Rend `{name, bytes}`, ou `null` sur une annulation. La borne vient du Dart
  (`kMaxOctetsParFichier`, 10 Mo) : aucune constante de taille en Kotlin.
- `shareFile` : marque le partage en cours, puis, hors du fil principal, crée le dossier,
  contrôle le chemin canonique, vide `cacheDir/exports/`, y écrit le fichier ; enfin `ACTION_SEND` avec
  `EXTRA_STREAM`, `ClipData` et `FLAG_GRANT_READ_URI_PERMISSION` dans `Intent.createChooser`.
  URI de `ExportsFileProvider` (sous-classe de `FileProvider`, autorité
  `${applicationId}.exports`, `exported="false"`, `grantUriPermissions="true"`), limité par
  `res/xml/exports_paths.xml` à `<cache-path name="exports" path="exports/"/>`.
- `saveDocument` : `ACTION_CREATE_DOCUMENT` avec `EXTRA_TITLE` ; rend `true` une fois le
  fichier écrit, `false` sur une annulation.
- Nom refusé (`INVALID_NAME`) : vide, plus de 120 caractères, `/`, `\`, `..`, ou chemin
  canonique hors de `cacheDir/exports/`. Un choix, un enregistrement ou un partage pendant un
  autre rend `ALREADY_ACTIVE` : chacun reste marqué jusqu'au résultat final de sa lecture ou
  de son écriture (`finirChoix`, `finirEnregistrement`, `terminerPartage`, sur le fil
  principal). Sur Android, « Choisir un fichier » ne répond pas pendant un choix ; sur le web,
  il reste actif et un nouveau choix clôt le précédent ; sans application de choix, `NO_PICKER` ; lecture et écriture en
  échec, `READ_FAILED`, `WRITE_FAILED`, `SHARE_FAILED`. Codes de requête `0x4B42` (choix) et
  `0x4B43` (enregistrement), déclarés une fois. Lecture et écriture sur un fil à part, résultat
  rendu sur le fil principal. Aucun message d'erreur ne porte de nom ni de contenu de fichier.
- `cacheDir/exports/` est vidé à chaque lancement neuf (`onCreate` sans état sauvegardé) : le
  fichier exporté porte le nom de l'auteur. Aucune permission de stockage.

Côté Dart, garde `kIsWeb` avant le canal ; chaque `catch` appelle `reportError`
(`exchange.pick`, `exchange.share`, `exchange.save`) avec un `context` limité au code et à la
taille. Sur le web, `fichiers_web.dart` : `<input type="file">` créé et cliqué dans le geste de
l'utilisateur, `File.size` au-delà de la borne refusé avant `arrayBuffer()`, événement
`cancel` (un nouveau choix clôt le précédent comme annulé sur un navigateur qui ne l'émet
pas) ; téléchargement par `Blob`, `URL.createObjectURL`, lien `download`, clic,
`revokeObjectURL` une seconde après. Rien ne part vers un serveur. Tests :
`echange_fichiers_test.dart` (`TestDefaultBinaryMessenger`) ; le Kotlin et le web se vérifient
par la compilation et un essai à la main.

**Verrou d'écran (`wakelock_plus`).** Pris à l'ouverture de « Préparer le brassage » et de
l'écran du jour, relâché en quittant, repris au retour d'arrière-plan. Compté par
`ScreenWakelock` ; un échec est rapporté une fois par session (`brew_day.wakelock`). Sur le
web, `no_sleep.js` se charge au premier appel : d'où la prise à l'ouverture, avant la coupure
du réseau.

**Dépendances.** `wakelock_plus` 1.8.2, `flutter_localizations` (SDK), `web` ^1.1.1 (direct,
déjà tiré), `package_info_plus` ^10.2.2. `flutter_localizations` tire `intl` 0.20.2. `fl_chart`
1.3.0 (version exacte, ADR-004) dessine la courbe du relevé et n'ajoute aucun paquet transitif.
`exchange` (chemin `../exchange`, v0.1.20) tire `crypto` 3.0.8, déjà résolu en dépendance
indirecte : `pubspec.lock` ne gagne que l'entrée `exchange`. Côté Android,
`androidx.core:core:1.17.0` est déclaré pour `FileProvider`, à la version que le graphe des
greffons résout déjà (`./gradlew :app:dependencies --configuration releaseRuntimeClasspath`) ;
à remonter avec eux.

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
| `/recettes/importer` | « Importer des recettes », page pleine avec retour, hors coquille, ouverte par `push` depuis la liste, déclarée avant la coquille | membre ; écrit sous son seul `owner_uid` |
| `/equipements`, `/equipements/:id` | liste et fiche des équipements, dans la coquille | membre |
| `/equipements/nouveau`, `/equipements/:id/modifier` | éditeur d'équipement, plein écran, hors coquille | membre ; même règle que les recettes |
| `/brassins`, `/brassins/:id` | liste et fiche des brassins, dans la coquille | membre |
| `/brassins/:id/preparer` | « Préparer le brassage », dans la coquille, retour vers la fiche | membre ; propriétaire pour commencer |
| `/brassins/:id/jour` | écran du jour, plein écran, hors coquille | propriétaire ; un autre membre lit « Seul le brasseur de ce brassin suit son brassage. » |
| `/recettes/:id/chronologie` | éditeur de chronologie, plein écran | auteur ; sinon « Seul l'auteur modifie cette chronologie. » |
| `/bibliotheque` | redirige vers `/bibliotheque/styles` (route sans écran, hors de la coquille) : une seule page par segment, que le retour d'une fiche retrouve avec sa recherche | membre |
| `/bibliotheque/{segment}` | Bibliothèque, dans la coquille ; segments `styles`, `malts`, `houblons`, `levures`, `divers`, `recettes` ; chaque segment est une route de premier niveau de la coquille | membre |
| `/bibliotheque/{segment}/:id` | fiche d'un style, d'un ingrédient ou d'une recette publique, dans la coquille, retour vers le segment ; route fille du segment, qui garde la liste et ses pages lues au retour | membre |
| `/sources-des-donnees` | « Sources des données », page pleine avec retour, hors coquille, ouverte par `push` depuis la Bibliothèque, une fiche ou le menu du compte | membre |
| `/prix` | « Mes prix », page pleine avec retour, hors coquille, ouverte par `push` depuis le menu du compte | membre ; ses seuls prix et frais |
| `/processus` | « Mes processus », page pleine avec retour, hors coquille, ouverte par `push` depuis le menu du compte | membre ; ses processus puis ceux du groupe |
| `/processus/nouveau` | « Nouveau processus », éditeur plein écran, hors coquille, déclaré avant `/processus/:id` ; `?modele=exemple` le préremplit du modèle d'exemple | membre ; écrit sous son seul `owner_uid` |
| `/processus/:id` | fiche d'un processus, page pleine, hors coquille, retour vers la liste | membre ; « Copier dans mes processus » pour un autre que l'auteur |
| `/processus/:id/modifier` | « Modifier le processus », plein écran, hors coquille | auteur ; sinon « Seul l'auteur modifie ce processus. » |
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
`FirebaseEnv`, `EchangeFichiersPlateforme` (`echange_fichiers_test.dart`, `TestDefaultBinaryMessenger`, P17 : annulation, fichier rendu, `TOO_LARGE` avec et sans taille, `ALREADY_ACTIVE` au choix et au partage, `NO_PICKER`, `READ_FAILED`, `INVALID_NAME`, `WRITE_FAILED`, aucun nom de fichier rapporté), Recettes › Importer (`import_recipes_test.dart` : relecture identique des recettes lues par `exchange/` (I9), « Déjà importée » par l'empreinte et jamais par le nom seul, fichier trop gros, illisible, non BeerJSON, statuts, détails, « Tout cocher », filtre, écriture sous le compte de l'importateur avec l'équipement présélectionné, hors ligne, refus du serveur, message groupé après la sortie et après « Importer un autre fichier », panne inattendue de l'analyse, boutons de l'accueil, filtres comptés, raisons des ignorées, fiche ouverte par-dessus le compte rendu, annonces, mesure de l'appui sur une case avec 500 recettes), feuille « Exporter » (`export_recipe_test.dart` : pertes, nom du fichier, auteur, rendement de l'équipement, aucun identifiant ni nom d'équipement, web, échec affiché dans la feuille avec réessai, un seul bouton plein, BeerXML bloqué, recette à l'extrait exportée sans `mash` ni `boil`, recette d'un autre membre sans auteur bloquée avec « Dupliquer », export bloqué pour l'auteur et pour un autre membre), `FirestoreBrewsRepository` sur `fake_cloud_firestore` (copie figée, `owner_name` à chaque écriture, identifiant de l'appareil, HS7), écrans Brassins et écran du jour (minuteur recalculé avec une horloge injectée, double appui, étape sautée, début en double, densité, alerte, verrou, reprise, pastille d'envoi), `AlerteMinuteurPlateforme` (`TestDefaultBinaryMessenger`, P17), domaine des coûts (`costs_domain_test.dart` : clés dérivées sans champ `key`, raisons de CB8, déclencheur du figeage, écarts), `FirestoreCostsRepository` sur `fake_cloud_firestore` (`costs_repository_test.dart` : écriture et suppression des prix et des frais, document illisible rapporté sans valeur, refus d'un premier figeage annoncé seulement si le coût n'est pas sur le serveur et rejeu journalisé `costs.freeze_replayed` (HL5), suppression du brassin et de son coût dans un même lot par `delete` et `deleteWithEvents` (CB19), `enregistrerEmbouteillage` : coût écrit après l'embouteillage sans attente, aucun coût pour une modification, un embouteillage déjà daté ou un coût déjà lu, embouteillage envoyé même quand le calcul échoue ou que les prix manquent, refus du coût seul et de l'embouteillage seul (CB7)), Bibliothèque (`library_domain_test.dart` : index, entrée mal typée écartée et comptée, champ inconnu ignoré, plages, unités canoniques seules, provenance, recette publique, rang de houblon hors de la liste, `copie` sans les champs propres aux recettes publiques ni `equipment_id` ni `brew_steps`, houblons sans forme, `normaliserNomRecherche`, libellés traduits, provenance courte ; `library_repository_test.dart` sur `fake_cloud_firestore` : index gardé pour la session, absent non gardé, un seul rapport pour les entrées illisibles, fiches, pages de 50 par `startAfterDocument`, préfixe, recette illisible rapportée, clés écrites par « Dupliquer » comparées à une liste recopiée de `recipeFields()` et des clés de `isBeerJsonRecipe` (à tenir à jour avec `firestore.rules`), `search_name` et les champs propres aux recettes publiques absents, recherche sur `search_name` avec saisie normalisée ; `library_screens_test.dart` : navigation, segments, recherche locale, fiches, états, hors ligne, pages suivantes, recherche à la validation, « Dupliquer » puis éditeur, houblons sans forme, « Voir le style » par `push`, recherche gardée au retour d'une fiche, compte annoncé, puces sur une ligne au téléphone, barre du bas à 360 px en texte × 2, « Sources des données » et son lien ; `recipe_screens_test.dart` : houblon sans forme, « Forme du houblon à compléter », forme demandée puis enregistrée dans l'éditeur), déroulé d'un brassin (`deroule_d3_test.dart` : clés uniques et clés de la recette gardées, libellés, journée retirée, préremplissage, houblonnage répété, chronologie illisible refusée, date changée et rétablie, prochaine journée, « Nouveau brassin » avec présélection, chronologie seule, modèle d'un autre membre jamais proposé, hors ligne, panne, refus du seul déroulé et de la création, fiche avant et après le départ, « Changer de processus », « Recréer depuis la recette », liste, « Préparer le brassage » et écran du jour avec un processus ; `brews_repository_test.dart` : `setProcess` écrit, relu, retiré, refusé par `erreurDeroule`), processus (`processes_repository_test.dart` sur `fake_cloud_firestore` : champs écrits, modèle refusé par `erreurModele` sans écriture, document illisible isolé et rapporté, modification qui garde `owner_uid` et `created_at`, copie au nom du lecteur avec clés neuves, duplication, suppression, choix par défaut absent, écrit, remis à nul et illisible ; `process_screens_test.dart` : menu du compte, chargement et panne, liste vide avec le modèle d'exemple écrit à « Enregistrer » seulement et proposé par défaut, miens puis groupe par nom, « Par défaut », document illisible, hors ligne sans cache, fiche, autre membre en lecture seule avec copie, choix par défaut, suppression du défaut, duplication, journée vide refusée, nom manquant, journée 1 fixe, tri par écart annoncé, 5 journées et 60 étapes au plus, bloc déjà placé, modification, double appui du lecteur d'écran sur une ligne, « Nouveau processus » en panne et hors ligne, choix par défaut en lecture, en panne et non lu, suppression refusée qui garde le défaut, duplication bloquée pendant l'attente, journée retirée, résumés ; `ligne_editeur_test.dart` : ligne avec et sans formulaire, icône en tête, ⋮ masqué sans action), écrans des coûts (`costs_screens_test.dart` : « Mes prix », bloc de la recette, bloc du brassin absent pour un autre membre et pour l'admin, aucun montant avec un prix manquant ni dans une annonce, coût figé inchangé quand un prix change, figeage au premier embouteillage seulement, dialogues à trois boutons de « Figer » et de « Recalculer », nom importé coupé à 120 caractères, texte à 200 %, contraste, cibles tactiles et en-tête des manquants annoncé).

#### Bibliothèque — client

Feature `lib/features/library/` (ADR-005, L4, étape 2). Lecture seule de `beer_index/`,
`beer_fermentables/`, `beer_hops/`, `beer_cultures/`, `beer_miscs/`, `beer_styles/` et
`public_recipes/`, que le script d'ingestion écrit. Aucune écriture dans ces collections ;
la seule écriture de la feature est « Dupliquer », qui passe par `RecipesRepository.create`.

**Lectures (P22).** `FirestoreLibraryRepository` ne fait que des `get()` ordinaires (cache
puis serveur), jamais de `snapshots()` ni de `Source.server` sur ces collections.

| Lecture | Requête | Mémoire |
|---|---|---|
| `lireIndex(nature)` | `get()` de `beer_index/{nature}` (`fermentables`, `hops`, `cultures`, `miscs`, `styles`) | gardé pour la session (instance du dépôt), une entrée par nature, si la lecture vient du serveur et que le document existe ; une lecture du cache, un document absent ou illisible, une panne ne sont pas gardés |
| `lireFiche(nature, id)` | `get()` de `beer_*/{id}` | aucune |
| `pageRecettesPubliques(prefixe:, apres:)` | `public_recipes`, `orderBy('search_name')`, `limit(50)` (`kTaillePageRecettes`), `startAfterDocument` pour la page suivante ; préfixe normalisé par `normaliserNomRecherche` (`normalizeName` de `brewing/`, tirets remplacés par des espaces, 100 caractères au plus, comme `nomDeRecherche` de l'ingestion), s'il reste non vide : `where('search_name', >= préfixe)` et `< préfixe + U+F8FF` (`kFinDePrefixe`) ; même champ que le tri, index d'un seul champ | l'écran garde les pages lues tant qu'il est ouvert |
| `lireRecettePublique(id)` | `get()` de `public_recipes/{id}` | aucune |

Coût par session, au plus : 5 lectures d'index, une page de 50 par ouverture du segment des
recettes publiques et par recherche validée, une lecture par fiche ouverte. La recherche des
référentiels filtre l'index en mémoire ; celle des recettes publiques part à la validation,
jamais à la frappe.

**Lecture typée.** `LecteurChamps` et `LectureBeerJson` : un champ inconnu est ignoré, un
champ attendu mal typé ou dans une autre unité que l'unité canonique (`%`, `EBC`, `C`, `sg`,
`IBUs`) rend l'entrée illisible. Index : `entries` absent ou qui n'est pas une liste rend le
document illisible ; une entrée mal typée est écartée et comptée, et le dépôt de données
journalise une seule fois pour l'index (`library.index_entries`, première erreur, compte dans
`context`). Une plage d'index est une paire de nombres finis `[min, max]` ; une plage de fiche
`{minimum, maximum}` a au moins une borne. `category_id`, `style_id` et `product_id` se lisent
en texte ou en entier. `provenance[]` exige `source`, `version`, `licence` et `retrieved`
(texte) ; `source_id` n'est pas lu. Une recette publique se lit par
`RecipeContent.fromFirestore` (même lecture que `recipes/`), puis `announced` (couples en `sg`,
`%`, `IBUs`, `EBC`), `source_hop_timing` (`hop_index` entier dans la liste des houblons, sinon
illisible), `provenance`, `search_name` et `style_id` (lien « Voir le style », ouvert par
`push` vers `/bibliotheque/styles/{style_id}` ; absent des recettes DIY Dog).
`ingredient_refs` n'est pas lu à cette étape. Index des styles : `og`, `fg` et `ebc` ne sont
pas lus (la liste ne les affiche pas ; la fiche lit ses plages dans `beer_styles`).

Écarts relevés sur les fichiers préparés par l'ingestion (`import/ingest/prepare/`, 2026-11-11,
lus par un test local supprimé ensuite) : aucun houblon des 415 recettes ne porte `form`
(2 116 lignes), d'où la lecture facultative de `form` (voir `recipes/`) ; `recipe.type` et
`boil` sont absents ; 58 recettes n'ont pas de `mash` ; `style_id` est absent ; libellés de
`source_hop_timing` relevés : `start`, `middle` (toutes casses), `Whirlpool`, `WHP`, `FV`,
`HD1`, `HD2`, `FWH`, `First Wort Hops` ; `purpose` d'un houblon `aroma/bittering`. Les
5 index (2 005 entrées), 2 005 fiches et 415 recettes passent la lecture sans erreur, et chaque
`search_name` est égal à `normaliserNomRecherche(recipe.name)`.

**Journal.** `library.index`, `library.entry`, `library.public_recipe` (panne d'un `get()`, ou
document illisible, `context` : chemin), `library.public_recipes` (panne d'une page),
`library.public_recipe_read` (recette illisible dans une page), `library.index_entries`,
`library.open_licence` (lien de la licence refusé par le système). Aucun prix, aucun e-mail.

**Dupliquer.** `RecettePublique.copie` est le `RecipeContent` lu, sans `equipment_id` ni
`brew_steps` ; `RecipesRepository.create` l'écrit sous l'uid du lecteur avec `owner_name` du
jeton. `RecipeContent.toFirestore` n'écrit que `format_version`, `imported_from` (`DIY Dog ·
diydog-{id}`) et `recipe`, aux clés de `isBeerJsonRecipe` : ni `style_id`, ni
`ingredient_refs`, ni `source_hop_timing`, ni `announced`, ni `provenance`, ni `search_name`
(règles actuelles de `recipes/`, ADR-005, décision D3 de L3). Un houblon sans forme est écrit
sans `form`. Le nom n'est pas préfixé de « Copie de ». L'écran ouvre ensuite l'éditeur par
`push`.

**Calculs.** La fiche d'une recette publique appelle `evaluerRecette` sans équipement
(`SansEquipement`) : aucune formule hors de `brewing/` (P3). `BlocCalculs(messageManques:)`
remplace la liste « À compléter » par un seul message (lecture seule). Les valeurs annoncées
s'affichent avant les calculs et ne leur sont jamais passées. Le moment d'origine d'un houblon
est traduit à l'affichage (`libelleMomentOrigine`), avec la valeur de la source entre
parenthèses. La provenance d'une fiche est une ligne courte sans doublon
(`lignesProvenance` : source, numéro de version, licence, date du relevé).

**Téléphone.** Sous 600 px (`WindowSize.compact`), les puces des segments sont dans un
`SingleChildScrollView` horizontal, et « Sources des données » est une `IconButton` avec
infobulle à leur droite ; au-delà, `Wrap` et `TextButton`. La fiche d'une recette publique est
dans un `Material` transparent : son `ExpansionTile` garde son encre quand une fiche s'ouvre
par-dessus dans la coquille.

**Lien externe.** « Sources des données » n'ouvre qu'une adresse, la constante
`kLicenceCcBySa` (`https://creativecommons.org/licenses/by-sa/4.0/`), par
`ouvrirLienProvider` (`url_launcher`, déjà en dépendance).

**Hors ligne.** Aucun code de la Bibliothèque dans l'écran du jour ni dans ce qu'il appelle
(P2). Sans réseau, ce qui est en cache se lit ; un document absent du cache est rendu
`DocumentAbsentDuCache` et affiché « indisponible hors ligne », jamais « absent ».

#### Tickets — client

Feature `lib/features/tickets/` (ADR-006, lot T1). Aucun code de ticket dans l'écran du jour
de brassage ni dans ce qu'il appelle (P2) ; aucun prix, stock ni coût (P5).

| Fichier | Contenu |
|---|---|
| `domain/ticket.dart` | `Ticket` (lecture tolérante : statut inconnu lu `TicketStatus.unknown`, type inconnu, champ obligatoire absent ou mal typé : `DocumentIllisible`), `TicketType`, `TicketStatus`, `TicketBrouillon`, bornes des règles (titre 5 à 100, description 10 à 2 000), `unread`, `compareTicketsRecentFirst`, `compareVersions` |
| `domain/ticket_screens.dart` | tables fermées `kTicketScreenNames` (modèle de route → nom) et `kTicketElements` (élément d'un écran → nom : `<modèle de route>/menu/<clé>` ou `<modèle de route>/fenetre/<clé>`, minuscules et tirets ; éléments propres à un écran, plus « Menu du compte » et « Barre de navigation » sur chaque écran de `kTicketShellScreens`), `autre`, `inconnu` ; `ticketScreenValue` ne rend qu'une valeur de cet ensemble ; `ticketElementOptions` (« L'écran entier » puis les éléments, vide pour un écran d'Admin vu par un brasseur) ; `ticketScreenLabel` rend « Brassin › Embouteillage » |
| `domain/etat_jeton_github.dart` | `EtatJetonGithub` (`token_invalid_since`, `token_expires_at`) |
| `data/tickets_repository.dart` | `TicketsRepository`, `FirestoreTicketsRepository` |
| `presentation/` | `TicketFormScreen`, `MyTicketsScreen`, `TicketDetailScreen`, `BandeauTicketsAdmin`, `ticket_statut.dart` (étiquette, icône et phrase de chaque statut), `ticket_lien_github.dart`, `tickets_providers.dart` |

**Routes.** Hors de la coquille, ouvertes par `push`, retour par `pop` sinon `/tickets` ou
l'accueil : `/tickets/nouveau` (déclarée avant `/tickets/:id`), `/tickets/:id`, `/tickets`.
`routes.dart` : `tickets`, `newTicket`, `ticket(id)`. Le menu du compte lit
`GoRouter.of(context).state.fullPath` (modèle `/recettes/:id`, jamais l'adresse) et le passe
dans `?ecran=` ; le formulaire le réduit par `ticketScreenValue`. « Reprendre ce ticket »
passe un `TicketBrouillon` par `extra`. `test/ticket_screens_test.dart` parcourt
`router.configuration.routes` et échoue si une route manque à la table, ou si
`kTicketShellScreens` n'est pas la liste des routes de la `ShellRoute`. Cette liste compte
23 routes, dont les 12 de la Bibliothèque (`/bibliotheque/<segment>` et
`/bibliotheque/<segment>/:id` pour `styles`, `malts`, `houblons`, `levures`, `divers` et
`recettes`) ; ces 12 écrans n'ont que les deux éléments de la coquille.
`/sources-des-donnees`, hors de la coquille, n'a aucun élément. L'élément précis
s'écrit dans le même champ `screen` (aucun champ ajouté, règles et `routeTemplateOrNull`
inchangés : la forme passe déjà leur contrôle). Il n'est jamais lu de `?ecran=` :
`initState` ne garde que l'écran ; seul « Reprendre » rend l'élément du ticket refusé.

**Commentaire `// ticket:`.** Chaque appel de `showFeuilleOuDialogue`, `showDialog`,
`showModalBottomSheet`, `showGeneralDialog`, `showMenu`, `PopupMenuButton`, `MenuAnchor`,
`SearchAnchor`, `confirmerAction`, `confirmerActionOuAlternative`, `confirmerAbandon`,
`confirmerSuppression`, `showDatePicker`, `showDateRangePicker` ou `showTimePicker` dans
`app/lib/` (hors définitions de `feuille_ou_dialogue.dart` et `ecriture.dart`) porte, sur la
ligne précédente, `// ticket: <clé>[, <clé>…]` (clés de `kTicketElements`) ou
`// ticket: aucun (<raison>)` (confirmation générique, sélecteur du système). Un appel partagé
par plusieurs écrans cite une clé par écran, séparées par des virgules : le formulaire de prix
de `price_form.dart`, ouvert depuis `/prix`, `/recettes/:id` et `/brassins/:id`, cite
`/prix/fenetre/prix, /recettes/:id/fenetre/prix, /brassins/:id/fenetre/prix`, et sa liste
« Reprendre un prix » les trois clés `…/fenetre/reprendre`. Les commentaires
`<coquille>/menu/compte` et `<coquille>/menu/navigation` citent la clé de chaque écran de la
coquille ; ces commentaires sont dans `app_shell.dart`. `ticket_screens_test.dart` échoue sur un appel sans
commentaire, une clé citée absente de la table, une clé de la table citée nulle part, une clé
qui ne commence pas par un modèle de `kTicketScreenNames` suivi de `/menu/` ou `/fenetre/`,
une route qui contient un segment `menu` ou `fenetre`, une valeur qui ne passe pas la regex
des règles ou dépasse 100 caractères.

**Écritures.** `create` écrit `tickets/{id}` avec l'identifiant créé par l'appareil à
l'ouverture du formulaire (`newTicketId`) et les seuls champs du contrat : `type`, `title`,
`description` (retirés de leurs espaces), `screen`, `app_version` (absent si illisible,
sans `+build`), `platform` (`android` ou `web`), `author_uid`, `author_email` (minuscules),
`created_at` = `serverTimestamp()`, `status` = `pending`. Un double appui est arrêté par une
garde synchrone du formulaire : un second `set` serait une mise à jour, refusée par les
règles. `markSeen` écrit `seen_by_author_at` = `serverTimestamp()` à l'ouverture d'un suivi à
lire. Ni callable, ni transaction, ni `Source.server` : tout marche hors ligne.

**Lectures.** `watchMine(uid)` : `where author_uid == uid`, tri à l'affichage, aucun index
composite. Pour l'admin : `watchAll` et `watchGithubStatus` (`ticket_status/github`), voir
« Tickets — client (T2) ». Toutes avec `includeMetadataChanges` et le cache. Un
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
`ouvrirLienProvider`
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
(`token_invalid_since`), échéance à 14 jours ou moins (`kTokenExpiryWarning`) ; sans échéance connue, rien,
tickets `send_failed` ou `pending` depuis plus d'une heure (`kTicketSendDelay`, heure de
`horlogeProvider`), Issues disparues, comptés sur la liste de `watchAll`. Liste vide quand tout
va bien. Affiché dans Admin › Tickets depuis T2.

**Composants partagés.** `Etiquette` reçoit `icon` (exclue de la sémantique) et
`ton` (`TonEtiquette.erreur` : `errorContainer` / `onErrorContainer`). `EditeurPleinEcran`
reçoit `libelleAction` et `libelleEnCours` (« Enregistrer » et « Enregistrement » par défaut)
et `fermerParRetour` (faux par défaut : `go(closePath)` comme avant ; vrai : `pop` s'il y a un
écran précédent). `formats.dart` : `formatDateChiffres` (« 08/11/26 »).

**Tests.** `tickets_domain_test.dart` (lecture, statuts, suivi à lire, versions, lien,
bandeau), `ticket_screens_test.dart` (tables, routes, éléments, commentaires `// ticket:`, remise à « L'écran entier »), `tickets_repository_test.dart`
(`fake_cloud_firestore` : champs écrits, illisible rapporté sans texte, `markSeen`, requêtes
admin, état du jeton), `tickets_screens_test.dart` (menu et pastille, formulaire, liste,
détail, bandeau Admin).

#### Tickets — client (T2)

Admin › Tickets des membres et décisions de l'administrateur (ADR-006, lot T2). Le client
n'appelle aucune callable : il écrit des documents que les déclencheurs appliquent.

| Fichier | Contenu |
|---|---|
| `domain/ticket.dart` | champs serveur lus en plus : `author_email`, `github_issue_number`, `github_url`, `delivered_pr_number`, `send_attempts`, `last_send_error`, `issue_missing_since`, `allowed_decisions` (`null` si absent ; valeur inconnue ignorée), `decision_lease_until`, `retry_requested_at` ; `toProcess` (`received` ou `send_failed`), `isLate`, `isBlocked`, `decisionInProgress` ; `TicketDecisionAction`, `TicketDecisionState`, `TicketDecision` (lecture tolérante : action inconnue lue `null`, état inconnu `unknown` ; seul un champ mal typé rend la décision illisible), `compareDecisionsRecentFirst`, `kDecisionTextMinLength` / `kDecisionTextMaxLength` (5 et 2 000), `kDecisionPendingDelay` (2 min) |
| `presentation/admin_tickets_screen.dart` | `AdminTicketsScreen` (liste, filtres, disposition côte à côte), `filtreTicketsProvider`, `auteurTicket`, `pastillesAdmin` |
| `presentation/admin_ticket_screen.dart` | `AdminTicketScreen` (fiche), `ligneDecision`, `ligneHistorique`, `FormulaireDecision` |
| `presentation/frise_ticket.dart` | `etapesFrise` (étapes et étape actuelle par statut), `FriseTicket` |
| `presentation/encadre_reponse.dart` | `EncadreReponse(titre:, texte:)`, partagé avec le suivi du membre ; `titreReponse` dans `ticket_statut.dart` |
| `presentation/ticket_statut.dart` | `statutAfficheDe` (ton et icône de chaque statut), `EtiquetteStatut(clignoteAuChangement:)` |

**Routes.** Dans la coquille, sous `/admin` : `/admin/tickets` (« Tickets des membres »,
retour `/admin`) et `/admin/tickets/:id` (« Ticket d'un membre », retour `/admin/tickets`), toutes
deux `AdminTicketsScreen(selectedId:)` et `PageDeCoquille(pleineLargeur: true)` : `AppShell`
ne borne pas ces pages à `kContentMaxWidth`. `routes.dart` : `adminTickets`,
`adminTicket(id)`. `kTicketScreenNames` reçoit « Admin › Tickets des membres » et « Admin ›
Ticket d'un membre », cachés aux brasseurs par `isAdminTicketScreen`. `/tickets/:id` construit
`MyTicketsScreen(selectedId:)`.

**Disposition côte à côte.** Admin › Tickets : fenêtre d'au moins
`kTicketsAdminCoteACoteMinWidth` (840 + 256 px du rail étendu, soit 1 096 px ; le routeur choisit
la clé de page avant la mise en page) → liste de `kListeTicketsAdminWidth` (360) à gauche, fiche à
droite, bandeau au-dessus des deux. `/admin/tickets` et `/admin/tickets/:id` sont deux routes
sœurs qui partagent la clé de page `cleDePageTicketsAdmin` : choisir une ligne par `go` ne change
que le panneau de droite, sans transition, et la liste garde son défilement. En dessous : liste
seule, fiche seule ouverte par `push`. Mes tickets : même seuil de largeur, liste de
`kListeMesTicketsWidth` (380), `TicketDetailPane` à droite ; une ligne choisie passe par
`context.replace`, qui garde la clé de page et la pile ouverte par `push`. Le filtre vit dans `filtreTicketsProvider` (`Notifier` en `autoDispose`, jamais
stocké) : il reste le même entre la liste et une fiche.
Les brouillons des boîtes « Refuser » et « Clore » et la décision écrite vivent dans
`decisionsFicheProvider` (`Notifier` en `autoDispose`, indexé par l'identifiant du ticket) : un
changement de disposition pendant qu'une boîte est ouverte ne perd ni le texte ni l'écriture.

**Lectures.** `watchAll()` : toute la collection `tickets/`, sans filtre, pour l'admin (les
règles autorisent la lecture de tout ticket à `isAdmin()`). Elle sert à la liste, au compteur
« Tickets à traiter » du menu (`ticketsToProcessCountProvider`, 0 pour un brasseur, qui ne
s'abonne pas), au bandeau et à la pastille de la tuile d'Admin
(`messagesBandeauTicketsProvider`). `watchDecisions(ticketId)` : `tickets/{id}/decisions/`, tri à l'affichage. Le
nom de l'auteur vient de `members/{author_email}.display_name` par `membersListProvider`
(lecture admin de `members/`, déjà faite par Admin › Membres) ; sans nom, l'adresse. Ce nom
ne quitte pas l'écran de l'admin.

**Écritures.** `createDecision` : `tickets/{id}/decisions/{decisionId}` avec l'identifiant de
l'appareil (`newDecisionId`), `action`, `text` (retiré de ses espaces, absent pour `validate`),
`state: pending`, `requested_by_uid`, `requested_at` = `serverTimestamp()`. `retrySend` :
`retry_requested_at` = `serverTimestamp()` sur un ticket `send_failed`. `retryDecision` : même
champ sur une décision `failed`. Chaque écriture se fait dans le cache dès l'appel ; la
`Future` se termine à l'accord du serveur. Les trois écritures rendent `Future<bool>`. Un refus est
rapporté par le dépôt (`tickets.create_decision`, `tickets.retry_send`, `tickets.retry_decision`)
avec le chemin, l'action et le code d'erreur, jamais le texte (P13), qui rend `false` ; l'écran
n'attrape rien et annonce « Décision non enregistrée. Réessayez. »
ou « Relance non enregistrée. Réessayez. ».

**Barre de décision.** Les boutons viennent de `allowed_decisions` seul (P26) : le client
n'en dérive aucun du statut. Aucun bouton pendant une décision `pending` ou `applying`, ou
tant que `decision_lease_until` est dans le futur, ou tant que les décisions ne sont pas lues.
La décision écrite par l'écran s'affiche en attendant que la lecture la rende. Ligne d'état de
la dernière décision (`ligneDecision`, fonction pure) : écriture en attente hors ligne
(création, ou reprise d'une décision `failed` restée `failed` dans le cache avec
`hasPendingWrites`), en cours, en attente depuis plus de `kDecisionPendingDelay`, bail expiré (`lease_until` de la
décision, sinon `decision_lease_until` du ticket), écartée, en échec. Hauteur d'au moins
`kBarreDecisionFixeMinHeight` (480) : barre fixée en bas ; en dessous, en fin de fiche. Les phrases hors ligne se
dérivent du cache (`hasPendingWrites` de la décision ou du ticket et `offline`), jamais d'un
état du widget : elles restent après un changement de disposition.

**Étiquettes.** `TonEtiquette` reçoit `neutre` (`surfaceContainerHighest` / `onSurface`),
`primaire` (`primaryContainer`) et `tertiaire` (`tertiaryContainer`). `EtiquetteStatut` avec
`clignoteAuChangement` (fiche d'Admin seule) : trois pulsations d'opacité en 1 200 ms par un
`AnimationController` créé pour cette seule étiquette, rien si
`MediaQuery.disableAnimationsOf`, annonce `SemanticsService.sendAnnouncement` dans tous les cas.

**Journal.** Rapports ajoutés : `tickets.watch_all`, `tickets.watch_decisions`,
`tickets.read_decision`, `tickets.create_decision`, `tickets.retry_send`,
`tickets.retry_decision`, `tickets.open_github` (contexte « Issue d'un ticket » ou « PR d'un
ticket livré », sans l'adresse).

**Tests.** `tickets_admin_test.dart` : domaine (À traiter, bloqué, frise par statut, tons,
titres de l'encadré, infobulle, ligne d'état pour chaque état, historique), menu et compteur,
tuile d'Admin, liste (filtres, états, auteur, pastilles, téléphone et large), fiche (boutons
selon `allowed_decisions`, boîtes et validations, écriture refusée, hors ligne, rejet, échec et
« Réessayer », relance d'envoi, Issue disparue, barre fixe ou en fin de fiche, clignotement et
animations réduites, texte à 200 %), Mes tickets (frise et sémantique, téléphone et large).
`tickets_repository_test.dart` : `watchAll`, champs des décisions, lecture tolérante, relances.

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
| `imported_from` | string \| null (200) : origine d'une recette importée, `{format} · sha256:{64 chiffres hexadécimaux}` (`BeerJSON · sha256:…`, v0.1.20), empreinte du contenu de la recette dans le fichier ; aucun nom de fichier. Recettes › Importer marque « Déjà importée » une recette du fichier dont l'empreinte termine l'`imported_from` d'une recette de l'importateur. L'éditeur la garde ; « Dupliquer » ne la copie pas |
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
| `ingredients.hop_additions` | list (50) : `name`, `form` facultatif (absent pour une recette publique et sa copie, ADR-005 D8 ; `pellet`, `leaf` à la saisie ; toute valeur de `HopVarietyBase.form` à la lecture : `plug`, `leaf (wet)`, `powder`, `extract`), `alpha_acid` `{value, "%"}` facultatif, `amount` `{value, "g"}` ou `{value, "l"}` (v0.1.17), `timing` (ci-dessous) |
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
forme sans facteur d'utilisation). Depuis la v0.1.26, la forme d'un houblon peut manquer
(`HopLine.form` nul, aucune clé `form` écrite) : les recettes DIY Dog ne la donnent pas, et
aucune forme n'est inventée. `calcForm` rend alors `null`, comme pour une forme sans facteur :
un houblon d'ébullition rend l'IBU indisponible (`MissingInputKind.hopForm`, `brewing/`
inchangé). `libelleManque(..., content:)` lit la ligne et affiche « Forme du houblon à
compléter : {noms}. » pour une forme absente, « Forme non prise en charge par le calcul :
{noms}. » pour une forme sans facteur ; la fiche, l'éditeur et la feuille « Exporter » passent
`content`. L'éditeur demande une forme quand la ligne est modifiée (« Choisissez une forme. »).
L'import BeerJSON et BeerXML garde une ligne sans forme, sans `form` et sans perte listée ;
une forme hors du schéma reste refusée. L'export BeerJSON l'écrit sans `form` (le schéma ne
l'exige pas) ; l'export BeerXML est bloqué (`ChampExport.formeHoublon`, « Forme du houblon à
compléter : {noms}. »). La clé de prix d'un fermentescible qui n'est pas un malt
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
| `process` | map \| null (ADR-009) : déroulé figé, voir ci-dessous. Absent de la création ; écrit, réécrit en entier ou retiré par une modification, seulement si `brewed_at` est nul avant et après l'écriture |
| `created_at`, `updated_at` | timestamp, obligatoires |

**Déroulé figé `process` (ADR-009, v0.1.28).** Résolution d'un modèle de processus avec la
recette figée, écrite juste après la création du brassin (v0.1.30) : contrôler `process` à la
création ferait dépasser le budget de `isBrewCreateShape`.

| Champ | Type |
|---|---|
| `format_version` | int, `1` |
| `template_id` | string \| null (128) : modèle d'origine, peut avoir été supprimé depuis |
| `template_name` | string \| null (120) : nom du modèle au moment de la résolution |
| `sessions` | liste de 1 à 5 journées résolues, triées par écart, la journée de brassage en tête |

Journée résolue (non inspectée par les règles, lue par `lireDeroule`) : `key` (1 à 100, unique
dans le déroulé), `name` (1 à 120), `offset_days` (entier de 0 à 365), `offset_source`
(`template`, `recipe`, `brewer`), `role` (`brew` pour la première et elle seule, `packaging`
pour une seule au plus, `other`), `template_session_key` (100) facultatif, `steps` (120 au
plus). Étape résolue : `key` (1 à 100, unique sur toutes les journées du brassin), `name`
(1 à 120), `duration_min` (0 à 600), `temp_c` (0 à 100) facultative, `origin` (`template`,
`recipe_steps`, `dry_hops`, `packaging_additions`), `template_step_key` (100) facultatif. Les
étapes de la recette gardent leur clé de `recipe_snapshot.brew_steps` ; les autres reçoivent
une clé neuve (`doc().id`) à chaque résolution. `template_step_key` et `template_session_key`
servent au prévu/réel d'une livraison suivante. Aucun prix, stock ni coût (P5).

Lecture tolérante : un brassin sans `process` (ou à `process` nul) se lit comme une journée de
brassage unique tirée de `recipe_snapshot.brew_steps` ; aucune migration. Un `process`
illisible (format inconnu, clé en double, borne dépassée, rôle mal placé) rend le déroulé
illisible : la fiche, « Préparer le brassage » et l'écran du jour affichent « Déroulé
illisible. Mettez l'application à jour, ou prévenez l'administrateur. », « Commencer le
brassage » est bloqué, le dépôt le rapporte (`brews.process`), sans repli sur la chronologie
de la recette. Une chronologie figée illisible d'un brassin sans `process` garde son texte
« Chronologie de ce brassin illisible : {raison}. ». Un champ inconnu est ignoré. Les six
lecteurs des étapes d'un brassin (`plan_du_jour.dart`, `brew_day_screen.dart`,
`prepare_brew_screen.dart`, `prevu_et_mesure.dart`, `brew_detail_screen.dart`,
`brews_repository.dart`) passent par `Brew.deroule` depuis la v0.1.28.

**Écriture de `process` (v0.1.30).** `BrewsRepository.setProcess(brewId:, deroule:,
ownerName:)` écrit `process` en entier par un `update`, avec `owner_name` et `updated_at` ;
`deroule` nul retire le champ (« Chronologie de la recette seule »). `erreurDeroule` est
vérifié avant l'écriture : un refus lève `DerouleInvalide`, rapporté sous
`brews.process_write`, sans rien écrire. Aucune transaction. Trois appelants, tous avant le
départ (`Brew.derouleModifiable` : `brewed_at` nul et statut prévu) :

- « Nouveau brassin » : `create` inchangé, puis `setProcess` sur le même identifiant, sans
  attendre le serveur (option B'). Les deux écritures partent dans le cache, hors ligne
  compris ; un brassin refusé à la création rend aussi son déroulé refusé, et seul le refus de
  la création s'annonce (`suivreDeroule`) ;
- la fiche : « Changer de processus », « Changer la date », « Rétablir la date du processus » ;
- « Recréer depuis la recette » : le modèle d'origine, s'il est lu, s'assemble de nouveau avec
  la nouvelle copie de la recette, puis `setProcess` sur le nouveau brassin ; sans modèle lu ou
  assemblable, le brassin recréé n'a pas de `process` et l'annonce le dit.

**Assemblage (v0.1.30).** `assemblerDeroule(templateId:, modele:, recipe:, nouvelleCle:)`
(`brews/domain/assemblage_deroule.dart`) appelle `resolveProcess` puis crée les clés et les
libellés : étape du modèle (nom, durée, température, `template_step_key`), étape de
`brew_steps` (clé gardée), étape préremplie (`nomEtapePreremplie`, clé neuve), houblon à cru et
ajout à l'embouteillage (« Ajouter {nom} {quantité} », 0 min, clé neuve), journée (clé neuve,
`template_session_key`, « {nom} 1 », « {nom} 2 » pour un houblonnage répété). Il lève
`AssemblageImpossible` pour une chronologie de recette illisible (aucun repli sur le
préremplissage) ou un déroulé refusé par `erreurDeroule`, et laisse passer
`BrewingInputException`. L'écran appelle `evaluerAssemblage`, qui rapporte un refus une fois par
modèle et par raison (`brews.process_assembly`, `derouleReportsProvider`). L'aperçu de « Déroulé
prévu » s'assemble avec des clés locales (`clesApercu`), l'écriture avec `newKey` du dépôt des
processus (`doc().id`). À la création, la recette assemblée est `recipe.content`, celle que
`recipeSnapshot` copie dans le même appel ; sur la fiche, `brew.recipe`, la copie figée.
Annonces : préremplissage, avertissements de `defaultBrewSteps` (textes de
`avertissementPreremplissage`, partagés avec l'éditeur « Chronologie du jour »), journée retirée
faute de houblon à cru ou d'ajout à l'embouteillage, houblons à cru sans journée, jour regroupé.
`Deroule.avecEcart` change l'écart d'une journée après le brassage (source `brewer`) et range
les journées par `processSessionOrder` de `brewing/`, le même ordre que `resolveProcess`.
`AssemblageImpossible` porte sa cause affichée ; `evaluerAssemblage` rend `AssemblageRefuse`
avec cette cause, ou celle d'une `BrewingInputException` (modèle invalide, jour d'ajout hors
limites). « Changer de processus » ne remplace jamais le déroulé actuel faute d'avoir lu la
liste : le déroulé actuel absent de la liste devient l'entrée « {nom} (actuel) », et
« Appliquer » n'écrit qu'un choix du brasseur différent du déroulé actuel. La confirmation de
« Recréer depuis la recette » assemble le modèle avant de s'afficher. `ecartDuProcessus` retrouve l'écart d'origine d'une journée
dans le modèle assemblé de nouveau, par `template_session_key`, puis par le nom pour un
houblonnage répété ; sans modèle lu, « Rétablir la date du processus » n'est pas proposé.
`fermentationDayNumber` donne l'écart d'une date choisie, `JourneeDeroulee.date` (par
`processSessionDate`) la date d'une journée (P3). `prochaineJourneePrevue` dérive la ligne de
la liste des dates seules, sans lire les événements.

Le rendement réel, le degré mesuré et les écarts se calculent à l'affichage à partir des
événements et de la copie figée, jamais stockés ; aucune migration : un champ absent vaut nul.
Aucun prix ni coût (P5). `MesuresRetenues` lit les identifiants ci-dessus puis applique la règle
automatique (dernière densité du jour, dernière densité de fermentation, dernier volume) ;
hors statut En fermentation, un relevé postérieur au jour de `bottled_at` ne compte pas dans la
densité finale.

### `process_templates/{templateId}`

Modèle de processus (ADR-009, v0.1.28). Lisible par le groupe, écrit par son auteur depuis
« Mes processus » (v0.1.29, lot D2).

| Champ | Type |
|---|---|
| `format_version` | int, obligatoire, `1` |
| `owner_uid` | string, obligatoire, immuable |
| `owner_name` | string, facultatif, contrôlé comme dans `recipes/` (`ownerNameOk`) |
| `name` | string, obligatoire, 1 à 120 caractères |
| `notes` | string \| null (10 000) |
| `sessions` | liste, obligatoire, de 1 à 5 journées |
| `created_at`, `updated_at` | timestamp, `serverTimestamp()` |

Journée (non inspectée par les règles) : `key` (1 à 100, unique dans le modèle), `name`
(1 à 120), `offset_days` (entier de 0 à 365, écart depuis le début du brassage),
`requires_recipe_block` (bool, facultatif : la journée n'entre dans un brassin que si son bloc
tiré de la recette n'est pas vide), `steps` (60 au plus). Élément de `steps` : `key` (1 à 100,
unique dans le modèle), `kind` (`step`, `recipe_steps`, `dry_hops`, `packaging_additions`) ;
`name` (1 à 120), `duration_min` (0 à 600) et `temp_c` (0 à 100, facultative) pour `step`
seulement. `erreurModele` vérifie avant l'écriture les contraintes d'ADR-009 : première journée
à J+0 avec le seul bloc `recipe_steps` du modèle ; un bloc `dry_hops` et un bloc
`packaging_additions` au plus, jamais le jour du brassage ni dans la même journée ;
`requires_recipe_block` sur une journée qui porte l'un d'eux ; écarts qui ne décroissent pas.
Les deux blocs ne vont jamais dans la même journée (ADR-009) : une journée de houblonnage se
répète une fois par jour d'ajout.

Le modèle d'exemple (`modeleExemple`) est une constante de l'application, jamais écrite sans
l'action « Partir du modèle d'exemple » puis « Enregistrer » du brasseur ; il est aussi le cas `exemple`
de `brewing/test/fixtures/process.json`, relu par `app/test/processes_domain_test.dart`.

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
| `users/{uid}/preferences/processes` | `default_template_id` string \| null (128) : modèle présélectionné dans « Nouveau brassin » ; `updated_at` timestamp (`serverTimestamp()`). Document unique, état propre au lecteur, jamais écrit sur le modèle lu par le groupe (ADR-009, v0.1.28 ; lu et écrit par « Mes processus » depuis la v0.1.29. Supprimer le processus par défaut remet `default_template_id` à nul) |
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
| `screen` | string, obligatoire, 100 caractères au plus : modèle de route go_router (`/recettes/:id`), élément de cet écran (`/brassins/:id/fenetre/embouteillage`, `/recettes/menu/compte`), `autre` ou `inconnu` ; jamais un identifiant réel |
| `app_version` | string facultatif, 1 à 40 caractères |
| `platform` | string, obligatoire : `android` ou `web` |
| `author_uid` | string, obligatoire : `request.auth.uid` |
| `author_email` | string, obligatoire : e-mail du jeton en minuscules |
| `created_at` | timestamp, obligatoire : `serverTimestamp()` |
| `status` | string, obligatoire : `pending` à la création |

Écrit par l'auteur ensuite : `seen_by_author_at` (timestamp, `serverTimestamp()`), à
l'ouverture du suivi.

Écrit par l'admin ensuite (T2) : `retry_requested_at` (timestamp, `serverTimestamp()`), seul
champ modifié, sur un ticket `send_failed` seulement (« Relancer l'envoi »). La passe horaire
le retire quand elle reprend le ticket.

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
| `allowed_decisions` | liste parmi `validate`, `refuse`, `close` : `received` → les trois ; `validated` et `in_progress` → `refuse`, `close` ; autres statuts → liste vide. Réécrite à chaque changement de statut (publication, passe horaire, décision) ; posée une fois par la passe horaire sur les tickets écrits avant T2. Absente sur un ticket `pending` jamais publié. Le client affiche les boutons de cette liste et ne la calcule pas (P26) |
| `decision_lease_until` | timestamp : bail de deux minutes d'une décision en cours, posé en transaction, retiré à la fin |
| `send_retried_at` | timestamp de la dernière relance demandée par l'admin : avec `send_attempts` remis à 0, il fait chercher l'Issue par sa référence avant un nouvel envoi |
| `updated_at` | timestamp de la dernière écriture du serveur |

Un statut ne recule pas, sauf à la réouverture de l'Issue, qui reprend le statut de ses
étiquettes. Quitter `delivered` efface les quatre champs `delivered_*`.

### `tickets/{ticketId}/decisions/{decisionId}`

Décision de l'admin sur un ticket (ADR-006, T2). Identifiant créé par l'appareil
(`[A-Za-z0-9_-]`, 128 caractères au plus) ; il part sur le dépôt public dans la ligne
`Décision <id>` du commentaire. Un document par décision garde l'historique. Les
déclencheurs `onDecisionCreated` et `onDecisionUpdated` l'appliquent sur l'Issue.

Écrits par l'admin, à la création seule :

| Champ | Type |
|---|---|
| `action` | string, obligatoire : `validate`, `refuse` ou `close` |
| `text` | string, 5 à 2 000 caractères : motif (`refuse`) ou commentaire (`close`), obligatoire pour ces deux actions, absent pour `validate` |
| `state` | string, obligatoire : `pending` à la création |
| `requested_by_uid` | string, obligatoire : `request.auth.uid` |
| `requested_at` | timestamp, obligatoire : `serverTimestamp()` |

Écrit par l'admin ensuite : `retry_requested_at` (timestamp, `serverTimestamp()`), seul
champ modifié, sur une décision `failed` seulement (« Réessayer »). Le serveur le retire
quand il reprend la décision.

Écrits par le serveur seul (SDK Admin) :

| Champ | Contenu |
|---|---|
| `state` | `pending` → `applying` → `applied` ; ou `rejected` (rien publié par cet essai), `failed` (échec en cours de route) |
| `error_reason` | texte court en français, montré à l'admin, jamais le jeton ni le message brut de GitHub : « Cette décision n'est plus possible pour ce statut. », « Une décision est déjà en cours sur ce ticket. », « Ce ticket a déjà été clos sur GitHub. », « Ce ticket n'existe plus. », « Ce ticket n'a pas encore d'Issue GitHub. », « Décision illisible. », « Jeton GitHub refusé ou expiré. », « Motif publié, mais l'Issue n'a pas été fermée. Réessayez. », « Commentaire publié, mais l'Issue n'a pas été close. Réessayez. », « GitHub limite les appels pour l'instant. Réessayez plus tard. », « L'Issue de ce ticket est introuvable sur GitHub. », « GitHub n'a pas répondu, rien n'a été publié. Réessayez. », « Décision faite sur GitHub, mais le ticket n'a pas été mis à jour. Réessayez. » ; retiré quand la décision est reprise ou appliquée |
| `steps_done` | liste parmi `comment`, `label`, `close` : étapes faites sur GitHub |
| `comment_id` | identifiant du commentaire publié (`refuse`, `close`) ; relu en premier à la reprise |
| `lease_until` | timestamp : bail de deux minutes, le même que `decision_lease_until` du ticket |
| `applied_at` | timestamp de l'application |
| `updated_at` | timestamp de la dernière écriture du serveur |

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
| `token_expires_at` | date de l'en-tête `github-authentication-token-expiration` ; `null` quand la dernière réponse réussie ne le portait pas (le bandeau ne dit alors rien de l'expiration) |
| `token_checked_at` | timestamp de la dernière réponse réussie qui a écrit ce document |
| `issues_cursor` | date ISO : curseur de la liste des Issues modifiées, propre à la passe horaire |
| `allowed_decisions_backfilled_at` | timestamp : `allowed_decisions` posé sur les tickets écrits avant T2, propre à la passe horaire |

### Référentiels et recettes publiques (ADR-005, L3)

Écrits par l'ingestion seule (`exchange/bin/preparer_referentiels.dart`, puis
`ingest/ecrire.mjs`, Admin SDK), jamais par un client. Noms et valeurs techniques seuls :
aucun `notes`, description, URL ni texte libre d'une source (P20), sauf `method.twist` de DIY
Dog dans `recipe.notes`. Unités canoniques en couples `{value, unit}` (`g`, `l`, `C`, `min`,
`EBC`, `sg`, `%`, `IBUs` pour l'amertume d'un style ou annoncée) ; plages en
`{minimum: {value, unit}, maximum: {value, unit}}` comme BeerJSON. Chaque document porte :

| Champ | Contenu |
|---|---|
| `provenance` | liste de `{source, source_id, version, licence, retrieved}` ; `source` : `brewtarget-001` à `brewtarget-005` ou `diydog` ; `source_id` : `id` ou `local_id` de la source, sinon le nom, ou le code de style, ou le numéro de recette ; `version` : `v5.2.3 ea10908` ou `e6c12ab` ; `licence` : `GPL-3.0`, `CC BY-SA 4.0` (part beer-analytics.com du 005, selon `folder_path`), `BJCP (noms et plages)`, `DIY Dog (usage privé)` ; `retrieved` : `2026-11-08` |
| `content_sha256` | SHA-256 du JSON canonique du document (clés triées, entier sans décimale), hors `content_sha256` et `updated_at`, calculé par la préparation ; l'écrivain ne réécrit pas un document de même empreinte |
| `updated_at` | `serverTimestamp()`, posé par l'écrivain |

Identifiant d'une entrée : `<nature>-<clé>`, nature `fermentable`, `hop`, `culture` ou `misc` ;
clé = nom normalisé comme une clé d'ingrédient de `brewing/` (`normalizeName` : minuscules,
accents retirés, tout caractère hors a-z et 0-9 en tiret, tirets réduits), 100 caractères au
plus. Deux entrées de même clé fusionnent : la source prioritaire (005, puis 003 et 004, puis
001) donne toutes les valeurs, chaque entrée ajoute sa ligne de `provenance` et son nom aux
`aliases`. Une culture qui porte un producteur et une référence se regroupe d'abord avec celles
de même producteur et de même référence (`Wyeast Labs` = `Wyeast`, `Omega Yeast Labs` =
`Omega Yeast` ; `WY1056` = `1056` chez Wyeast, `001` = `WLP001` chez White Labs ; tirets
ignorés) ; sa clé est producteur, référence et nom de l'entrée prioritaire, sans producteur
ni référence répétés en tête du nom ni `yeast` final (`culture-wyeast-1056-american-ale`). Un
rendement, un acide alpha ou une atténuation à 0 dans une source est lu comme inconnu : écarté
et compté.

| Collection | Champs |
|---|---|
| `beer_fermentables/{id}` | `name`, `aliases` (liste, peut être vide), `label_fr`?, `type` (`grain`, `sugar`, `extract`, `dry extract`, `honey`, `fruit`, `juice`, `other` ; `Adjunct` du 001 donne `grain`), `yield`? (`{fine_grind: {value, unit: '%'}}`), `color`? (EBC ; Lovibond et SRM convertis par `brewing/`), `producer`?, `origin`? |
| `beer_hops/{id}` | `name`, `aliases`, `label_fr`?, `form`?, `alpha_acid`? (`%`), `beta_acid`? (`%`), `origin`?, `purpose`? (`type` BeerJSON du houblon : `aroma`, `bittering`, `aroma/bittering`… ; `Both` du 001 donne `aroma/bittering`) |
| `beer_cultures/{id}` | `name`, `aliases`, `type`?, `form`?, `producer`?, `product_id`?, `attenuation`? (plage `%` ; une valeur du 001 donne une plage d'une valeur), `temperature_range`? (plage `C`, °F convertis), `flocculation`? (`very low` à `very high`) |
| `beer_miscs/{id}` | `name`, `aliases`, `label_fr`?, `type`? (`spice`, `herb`, `flavor`, `fining`, `water agent`, `wood`, `other`) |
| `beer_styles/bjcp2021-{code}` | `name`, `category`, `category_id`, `style_id`, `type`, `style_guide`, `original_gravity`, `final_gravity` (plages `sg`), `international_bitterness_units` (plage `IBUs`), `color` (plage EBC, SRM converti par `brewing/`), `alcohol_by_volume` (plage `%`) ; 17 des 110 styles n'ont aucune plage |
| `beer_index/{nature}` | 5 documents : `fermentables`, `hops`, `cultures`, `miscs`, `styles`. `{count, entries, content_sha256, updated_at}`, entrées triées par nom (sans casse), nombres nus : fermentable `{id, name, aliases?, label_fr?, type?, yield?, color?}` ; houblon `{id, name, aliases?, form?, alpha?}` ; culture `{id, name, aliases?, producer?, product_id?, type?, form?, attenuation?}` (milieu de la plage) ; ajout `{id, name, aliases?, label_fr?, type?}` ; style `{id, name, code, category, og?, fg?, ibu?, ebc?, abv?}` (plages en `[min, max]`). Taille contrôlée par l'écrivain, moins de 900 Ko (calcul de la documentation Firestore) |
| `public_recipes/diydog-{id}` | enveloppe de `recipes/` : `format_version: 1`, `owner_uid: 'system'`, `owner_name: 'DIY Dog'`, `imported_from: 'DIY Dog · diydog-{id}'`, `search_name` (`recipe.name` normalisé comme une clé d'ingrédient, des espaces à la place des tirets : « Punk IPA 2007 - 2010 » donne « punk ipa 2007 2010 » ; l'application trie et cherche par préfixe sur ce champ, la saisie normalisée de la même façon ; compris dans `content_sha256`), `recipe` (BeerJSON partiel, clés de `isBeerJsonRecipe` seules : copiable tel quel vers `recipes/`) ; propres aux recettes publiques : `style_id`? (absent : DIY Dog ne nomme pas de style), `ingredient_refs` (`{clé ingredientKey de brewing/ : id}` des lignes résolues), `source_hop_timing` (`{hop_index, label}` des houblons dont le libellé d'origine ne dit pas la durée : `start`, `middle`, `Whirlpool`, `WHP`, `FWH`, `HD1`, `FV`…), `announced` (`original_gravity`, `final_gravity` en `sg`, `alcohol_by_volume` en `%`, `ibu_estimate` en `IBUs`, `color_estimate` en EBC ; valeurs de la source, jamais un résultat de calcul) |
| `ingest_runs/{AAAAMMJJTHHMMSSZ}` | `started_at`, `finished_at`, `target` (`emulator` ou `production`), `counts` (`{collection: {written, unchanged, refused}}`), `sources` (`{source, version}`), `unresolved` (noms non résolus par nature), `report_sha256` (SHA-256 du rapport JSON local) |
| `import_unresolved/{empreinte}` | empreinte : SHA-256 de `nature|nom normalisé`, 64 chiffres hexadécimaux ; `nature`, `name` (nom tel que DIY Dog l'écrit), `source: 'diydog'`, `count` (lignes de recettes), `updated_at` ; aucun `content_sha256` : l'écrivain compare les quatre champs |

Dans `recipe` d'une recette publique : `author` vaut `BrewDog` ; `notes` porte `method.twist`
seul ; `boil` est absent (DIY Dog ne donne pas la durée d'ébullition, `DATA_SOURCES.md`,
décision 1) ; le volume avant ébullition et la température de fermentation sont écartés
(`recipe` n'a pas de clé pour eux) ; chaque palier est une infusion nommée « Palier N », et un
palier sans durée est écarté (`step_time` obligatoire dans le schéma partiel et dans la
lecture de l'application). Une ligne garde le nom de la source. Une valeur technique manquante
est recopiée de l'entrée résolue (ADR-005, D4 : malt `type`, `yield` et `color`, houblon
`alpha_acid`, levure `type`, `form`, `attenuation` au milieu de la plage) ; une valeur de la
source (l'acide alpha de `10% Alpha`) n'est jamais remplacée. Une ligne de malt non résolue
garde le type `grain` : la source la range dans `malt` sans autre précision. Aucun houblon ne porte de
`form` : la source ne la donne pas, et aucune valeur n'est inventée.

## Règles d'accès

Un membre est un compte connecté par Google (`firebase.sign_in_provider == 'google.com'`),
à l'adresse vérifiée (`email_verified == true`), dont l'e-mail en minuscules a un document
`members/{email}` (P11). Le rôle n'existe que dans ce document.

| Chemin | Lecture | Création | Modification | Suppression |
|---|---|---|---|---|
| `members/{email}` | son propre document (même absent) pour tout compte Google vérifié ; tous pour l'admin | admin | personne | admin, sauf son propre document et celui d'un autre admin (`resource.data.role != 'admin'`) |
| `recipes/`, `equipment/` | membres | membre, à son `owner_uid` ; `owner_name` absent ou égal au nom du jeton (`request.auth.token.name`, 1 à 80 caractères) | propriétaire, `owner_uid` et `created_at` inchangés, `owner_name` comme à la création | propriétaire |
| `brews/` | membres | membre, à son `owner_uid` ; `owner_name` comme dans `recipes/` ; champs de création seuls (`owner_uid`, `owner_name`, `recipe_id`, `name`, `status`, `planned_for`, `notes`, `imported_from`, copies, dates) ; `recipe_snapshot` contrôlé comme `recipes/` | propriétaire ; `recipe_id`, `recipe_snapshot`, `equipment_snapshot` inchangés ; liste blanche des clés ; seuls les champs changés sont contrôlés, par groupe (nom, statut, dates, ajustements, embouteillage, mesures retenues et `sugars_in_wort`, notes et `imported_from`, `process`) ; `process` changé seulement si `brewed_at` est nul avant et après l'écriture, nul ou map aux clés `format_version` (== 1), `template_id` (128), `template_name` (120), `sessions` (liste de 1 à 5) ; `owner_name` comme à la création | propriétaire |
| `process_templates/` | membres | membre, à son `owner_uid` (`createdByMe`), `owner_name` comme dans `recipes/` ; clés en liste blanche, `format_version == 1`, `name` 1 à 120, `notes` 10 000, `sessions` liste de 1 à 5 | propriétaire (`updatedByOwner`), même forme | propriétaire |
| `brews/{id}/events/` | membres | propriétaire du brassin existant, à son `owner_uid`, forme selon `kind` | auteur : `value`, `note`, `measured_at`, forme gardée | auteur |
| `users/{uid}/**` | propriétaire | refusé, sauf les collections ci-dessous | refusé, sauf les collections ci-dessous | refusé, sauf les collections ci-dessous |
| `users/{uid}/prices/`, `fees/` | propriétaire | propriétaire, forme et bornes contrôlées | propriétaire, forme et bornes contrôlées | propriétaire |
| `users/{uid}/brew_costs/` | propriétaire | propriétaire, forme contrôlée, `freeze_kind == 'initial'` | propriétaire, forme contrôlée, `freeze_kind == 'recalculation'` | propriétaire |
| `users/{uid}/stock/` | propriétaire | propriétaire | propriétaire | propriétaire |
| `users/{uid}/preferences/processes` | propriétaire (joker) | propriétaire, clés `default_template_id` (128 ou nul) et `updated_at == request.time` | idem | propriétaire |
| `error_reports/` | admin | membre, `uid` = le sien, champs en liste blanche et bornés | personne | admin |
| `tickets/` | auteur (`author_uid` = le sien, requête « Mes tickets » comprise) ; tous pour l'admin | membre, champs de création seuls (voir `tickets/`), `status == 'pending'`, `created_at == request.time`, `author_email` = e-mail du jeton en minuscules | auteur : `seen_by_author_at == request.time` seul ; admin : `retry_requested_at == request.time` seul, ticket `send_failed` | personne |
| `tickets/{id}/decisions/` | admin | admin, ticket existant, champs de création seuls (voir `decisions/`), `state == 'pending'`, `requested_by_uid == request.auth.uid`, `requested_at == request.time`, `text` 5 à 2 000 pour `refuse` et `close`, absent pour `validate` | admin : `retry_requested_at == request.time` seul, décision `failed` | personne |
| `ticket_quotas/**` | personne | personne | personne | personne |
| `ticket_status/**` | admin | personne | personne | personne |
| `beer_fermentables/`, `beer_hops/`, `beer_cultures/`, `beer_miscs/`, `beer_styles/`, `beer_index/` | membres, `get` seul (aucune requête) | personne | personne | personne |
| `public_recipes/` | membres : `get`, et requête de 50 documents au plus (`request.query.limit <= 50`) ; sans limite ou au-delà, refusée | personne | personne | personne |
| `ingest_runs/`, `import_unresolved/` | admin | personne | personne | personne |
| tout autre chemin | refusé | refusé | refusé | refusé |

L'admin n'a aucun droit d'écriture sur le contenu des autres brasseurs.

`public_recipes/` : la règle borne chaque requête à 50 documents, pas leur nombre total. Un
membre peut donc lire les 415 recettes par des requêtes à `offset` (ou `startAfter`). Le coût
reste borné par la taille de la collection, et le groupe compte moins de 10 comptes. Ce risque
est accepté (revue de sécurité de L3, 2026-11-11).

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
ajoutée sur `recipe` se mesure contre la marge de la création d'un brassin, corrigée en v0.1.28
ci-dessous (environ 16 expressions).

Mesure de la v0.1.28 (ADR-009, déroulé en journées), même émulateur. Étalonnage : 98 `pad()`
isolés atteignent la limite de compilation avant le budget ; regroupés par dix
(`pad10()` = dix `pad()`), 243 tiennent dans une règle `if true` seule, et 69 `pad()` isolés
coûtent autant que 6 `pad10()` et 8 ou 9 `pad()`. Un `pad()` vaut donc environ
4 expressions, et non 10 comme l'écrivaient les mesures de la v0.1.15 et de la v0.1.17 : la
marge de la création d'un brassin (4 `pad()`, inchangée) est d'environ 16 expressions. Toute
règle ajoutée sur `recipe` se mesure contre ces 16 expressions. Marges mesurées avec
`pad10()`, plus grande recette copiée et plus grand déroulé (5 journées de 120 étapes, noms
de 120 caractères, `template_id` de 128 caractères) :

| Écriture | Avant le contrôle de `process` | v0.1.28 |
|---|---|---|
| Écriture de `process` sur un brassin prévu qui copie la plus grande recette, notes et `imported_from` à leur longueur maximale, équipement complet | — | 145 `pad()` (environ 590 expressions) |
| Brassin du 22 novembre (plus grande recette, plus grand déroulé, 11 ajustements) : changement de statut | 177 `pad()` (sans `process`) | 174 |
| Même brassin : embouteillage et statut | — | 138 |
| Brassin du 22 novembre sans ajustements : écriture des 11 ajustements | 70 | 68 |
| Création d'un brassin qui copie la plus grande recette | 4 | 4 |
| Création du plus grand modèle de processus (5 journées de 60 éléments, nom de 120, notes de 10 000) | — | 185 |

Le contrôle de `process` coûte environ 3 `pad()` (12 expressions) à chaque modification d'un
brassin : `brewFields()` s'allonge d'une clé et `changed.hasAny(['process'])` s'évalue. Un
lot de 60 `step_skipped`, plus le début d'étape suivant, passe sur l'émulateur
(`processes.test.mjs`) : « Terminer la journée » et « Les sauter et commencer » n'ont pas à
découper leur lot.

La v0.1.20 (import et export, L2b) ne change aucune règle : `imported_from` reste une chaîne
de 200 caractères au plus, déjà portée à sa longueur maximale par le test « budget des
règles ». La marge mesurée en v0.1.17 vaut donc encore.

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
`fermenting`, le premier début en un `WriteBatch`, et un brassin créé puis son premier événement.
`processes.test.mjs` (v0.1.28, ADR-009, P38) rejoue pour les cinq profils la lecture, la
création, la modification et la suppression de `process_templates/`, l'écriture de `process`
sur un brassin prévu, sa lecture, `process` à la création (refusé) et sur un brassin commencé
(refusé), et `users/{uid}/preferences/processes` ; il vérifie les formes refusées (6 journées,
aucune, `format_version` 2, clé hors liste, `template_id` de 129 caractères), `process` écrit
avec `brewed_at` dans la même écriture (refusé), un départ qui ne touche pas `process`
(accepté), et un lot de 60 `step_skipped` (accepté). `numbers.test.mjs` vérifie que
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
modification, `seen_by_author_at` à l'heure de l'appareil, et `ticket_quotas/`, `ticket_status/` pour les
cinq profils. Pour T2, il rejoue `decisions/` pour les cinq profils (création, lecture, liste
triée sur `requested_at`, reprise d'une décision `failed`, suppression), le brasseur qui crée
une décision sur son propre ticket (refusé pour les trois actions), chaque borne de la
création (texte de 4, 5, 2 000, 2 001 caractères, texte pour `validate`, texte absent pour
`refuse` et `close`, état autre que `pending`, `requested_by_uid` d'un autre compte,
`requested_at` de l'appareil, chaque champ serveur), un ticket absent, une reprise sur une
décision `applied` ou avec un autre champ ; et la relance d'un ticket `send_failed` pour les
cinq profils, refusée sur un ticket `received`, à l'heure de l'appareil ou avec un autre
champ, ainsi que `allowed_decisions` et `decision_lease_until` écrits par l'admin.

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
| Défaut d'un modèle de processus | `processTemplateIssue` | premier défaut parmi les contraintes d'ADR-009 (`ProcessTemplateIssueKind`), et la journée qui le porte ; `null` si le modèle se résout |
| Résolution d'un modèle de processus | `resolveProcess` | journées gardées ou retirées, blocs remplacés par la recette figée, journées de houblonnage par jour distinct, regroupement au-delà de 5, tri par écart, avertissements. Voir ci-dessous |
| Jour d'un houblon à cru | `dryHopDay` | `round(dayMin / 1 440)` ; `dayMin` négatif ou jour au-delà de 365 : `BrewingInputException` |
| Ordre des journées | `processSessionOrder` | journée de brassage en tête, puis par écart croissant, à égalité dans l'ordre courant ; sert à `resolveProcess` et au changement de date d'une journée ; lève pour une liste vide, une première journée hors de J+0 ou un écart hors de 0 à 365 |
| Date d'une journée | `processSessionDate` | jour calendaire local du départ (`brewed_at`, sinon `planned_for`) plus l'écart, à minuit ; inverse de `fermentationDayNumber`, un changement d'heure ne décale pas la date |

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
fermentescible sans nature. Aucun calcul de rendement de brassage n'existe : les exports
écrivent le rendement d'empâtage de l'équipement (ADR-005, amendements de L2).

**Volume avant ébullition** (v0.1.21, `boil_volume.dart`). `preBoilVolumeLitres` donne le
`BOIL_SIZE` d'un export BeerXML : volume en fermenteur + pertes au trub + volume mort de la
cuve d'ébullition + évaporation (L/h) × durée d'ébullition / 60. Le retrait du moût au
refroidissement n'est pas compté : aucun profil d'équipement ne le porte. Aucune valeur par
défaut : l'export est bloqué si l'une manque. Volume en fermenteur nul, autre valeur
négative ou non finie : `BrewingInputException`. Cas dans `boil_volume.json`.

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

**Déroulé en journées (ADR-009, v0.1.28).** `resolveProcess(template:, recipe:)` reçoit les
journées du modèle (`ProcessTemplateSession` : écart, `requiresRecipeBlock`, nature de chaque
élément) et la recette figée (`ProcessRecipe` : nombre d'étapes de `brew_steps`, paliers,
ébullition et houblons pour le préremplissage, jour d'ajout à cru de chaque houblon, ajouts au
conditionnement). Il lève si `processTemplateIssue` rend un défaut. Le bloc `recipeSteps`
reçoit les étapes de `brew_steps`, ou à défaut le préremplissage `defaultBrewSteps` sans ses
étapes sans durée ; `dryHops` un houblon à cru par étape, dans l'ordre de la recette ;
`packagingAdditions` les houblons puis les ajouts au conditionnement. Un bloc vide disparaît,
et sa journée aussi si elle porte `requiresRecipeBlock`. Un houblon à cru qui a un jour
d'ajout tombe à `dryHopDay(dayMin)`, sinon à l'écart du modèle ; une journée de houblonnage
par jour distinct (rang 1, 2…), écart de source `recipe` sauf si l'un de ses houblons n'a pas
de jour. Au-delà de 5 journées, les jours les plus tardifs se regroupent dans le premier jour
regroupé. Tri par écart, à égalité dans l'ordre du modèle. Le résultat (`ProcessResolution`)
rend des brouillons sans clé ni libellé (`ProcessSessionDraft`, `ProcessStepDraft` : origine
et indice dans la liste d'origine), le préremplissage complet et les avertissements
(`ProcessWarning` : étape préremplie sans durée, houblon sans durée ou plus long que
l'ébullition, houblons à cru sans journée, jour regroupé). L'application crée les clés et les
libellés (`assemblerDeroule`, v0.1.30). `fixtures/process.json` compte 10 cas de résolution, dont le modèle
d'exemple, 11 modèles invalides, 2 recettes invalides, 6 jours d'ajout, 9 dates, dont les
changements d'heure du 2026-10-25 et du 2027-03-28, et 5 ordres de journées (`session_orders`,
4 refusés).

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

`normalizeName` (v0.1.20) rend le nom normalisé d'une clé d'ingrédient sans préfixe, sans
lever : il sert au nom du fichier d'un export. Ce n'est pas une formule de brassage.

## Échange de recettes (`exchange/`)

Paquet Dart pur (ADR-005, livraisons L2b, v0.1.20, et L2c, v0.1.21) : aucune dépendance
Flutter ni Firebase ; dépend de `brewing/`, de `crypto` 3.0.8 (empreinte SHA-256) et de `xml`
7.0.1 (analyseur à événements, lecture du BeerXML ; tire `petitparser` 7.0.2). Aucun `catch`
dans `lib/` (`test/no_catch_test.dart`). Il rend un résultat et ne lève pas pour une donnée
invalide, sauf `FormatException` pour un JSON ou un XML mal formé ou un UTF-8 invalide
(`XmlParserException` et `XmlTagException` du paquet `xml` en sont), que l'application
rapporte (`exchange.read`, `context` : format présumé `formatPresume` — `xml`, `json` ou
`inconnu` —, taille, position ; ni nom ni contenu du fichier, l'exception elle-même n'est pas transmise, son texte
citant le fichier) avant d'afficher « Fichier illisible ». Toute autre panne de l'analyse est
attrapée aussi (`exchange.read`, `context` : taille et type de l'erreur) et affiche
« Fichier illisible ». L'analyse passe par `analyseurFichierProvider` (`recipes_providers.dart`),
que les tests remplacent. Un export qui ne peut pas se construire est rapporté sous
`exchange.export` (`context` : identifiant de la recette).

**Bornes (P9 réécrit par ADR-005).** `kMaxOctetsParFichier` 10 Mo (contrôlée aussi par
`EchangeFichiers` avant la lecture) ; `kMaxRecettesParFichier` 500 : au-delà, les 500
premières, `FichierLu.tronque` vrai ; plafonds des règles : 50 malts, 50 houblons, 50 ajouts,
10 levures, 20 paliers, une liste plus longue refuse la recette, sans troncature ; nom, auteur,
style et nom d'une ligne coupés à 120 caractères, notes à 10 000, la coupe listée ;
`kMaxProfondeur` 32 niveaux d'imbrication dans une recette. Avant `jsonDecode`, un parcours
linéaire des octets compte `[` et `{` hors des chaînes : au-delà de `kMaxProfondeurFichier`
(32 + 4 : racine, `beerjson`, `recipes`, recette), le fichier est refusé (illisible) sans être
décodé (1 000 000 de niveaux testés sur la VM et dans Chrome). Une recette qui dépasse
`kMaxProfondeur` dans `lireEmpreinte` est illisible, sans lecture. Le même parcours compte
les valeurs (chaque `{`, `[` et `,` hors des chaînes) : au-delà de `kMaxValeursJson`
(1 000 000), le fichier est refusé avant `jsonDecode` (10 Mo de `{}` testés). 500 recettes
de 50 houblons écrites sans espace en comptent 354 003 (mesure du 2026-11-10).

Un fichier XML de plus de `kMaxProfondeurXml` (16) niveaux d'éléments est refusé pendant
l'analyse, qui se fait sans récursion. `lireXml` ne garde que ce que la lecture utilise : sous
`RECIPES`, les 500 premiers `RECIPE` seuls (les suivants sont comptés, un autre enfant n'est
pas gardé) ; ailleurs, les enfants des éléments de `kConteneursBeerXml` (`RECIPE`, `STYLE`,
listes, lignes, `MASH`, `MASH_STEPS`, `MASH_STEP`), sauf `VERSION`, `INVENTORY`, `DISPLAY_*`
et `DISP_*`. Les enfants d'un autre élément (`WATERS`, `EQUIPMENT`, élément inconnu) ne sont
pas gardés : il garde son texte et note qu'il a des enfants, ce qui suffit à le lister. Au-delà
de `kMaxElementsXml` (300 000) éléments gardés, le fichier est refusé (illisible) et l'analyse
s'arrête (10 Mo de `<X/>` dans une recette testés). 500 recettes de 50 houblons, champs
d'affichage compris, en gardent 203 501 (mesure du 2026-11-10). Une liste n'est convertie
que jusqu'au plafond + 1 ligne ; le refus cite le nombre du fichier (« Plus de 50 houblons
(200000). »). Les entités sont vérifiées aussi dans un texte qui n'est pas gardé. Le texte
d'un élément coupé en morceaux (commentaires, sections CDATA) se joint une seule fois, à sa
première lecture : 1 300 000 commentaires dans des notes se lisent en moins de 5 s (test).
Le décodage windows-1252 passe par un tampon de 16 bits par caractère (`Uint16List`). Un fichier
BeerXML de 10 Mo (2 178 recettes) s'analyse en 343 ms sur la VM (mesure du 2026-11-10, hors
test).

**Risques acceptés (`exchange/`).** Une balise ouverte et non fermée (`<A b="1" c="2" …`)
suivie de millions de pseudo-attributs est analysée par le paquet `xml` jusqu'à l'erreur, qui
lève `FormatException` : l'analyseur garde ces attributs en mémoire avant de lire la fin de la
balise. `exchange/` ne peut pas l'interrompre (aucun rappel par attribut). Le coût est borné
par les 10 Mo du fichier, refusé avant toute lecture au-delà : 10 Mo de pseudo-attributs
lèvent `FormatException` en 342 ms sur la VM (mesure du 2026-11-10, hors test).

Plafonds hauts d'une valeur convertie (v0.1.20, valeurs nouvelles : l'éditeur n'en a pas) :
1 000 kg (`kMaxGrammesParLigne`) et 1 000 L (`kMaxLitresParLigne`) par ligne, 10 000 L de
volume (`kMaxVolumeBrassin`), 2 000 EBC (`kMaxEbc` ; les malts torréfiés les plus foncés
approchent 1 500 EBC), 365 jours pour un ajout hors ébullition (`kMaxDuree`). L'ébullition, les
paliers, les températures et les pourcentages gardent les bornes de l'éditeur. Un nombre non
fini après conversion (`1e308 week`) est hors limites. Au-delà, une valeur obligatoire refuse
la recette, une valeur facultative est écartée et listée. Ce sont des garde-fous contre un
fichier faux, pas des seuils métier.

**Détection, par le contenu (`analyserFichier`).** BOM UTF-8 et blancs de tête ignorés.
`{` ou `[` : JSON en UTF-8 ; objet avec `beerjson.version` de 1.x, 2.x ou 3 (nombre, ou texte
lisible comme un nombre) : BeerJSON ; autre JSON : `jsonNonBeerJson` ; autre version :
`versionInconnue` (valeur affichée seulement si c'est un nombre ou une chaîne courte, 20
caractères au plus après nettoyage ; jamais une liste ou un objet convertis en texte). `<` : les
4 096 premiers octets lus en ISO-8859-1 ; `<F_R_`, `<_PERMID_>` ou `<Selections` : BeerSmith
(`bsmx`) ; premier élément `RECIPES` ou `RECIPE` après les déclarations `<?…?>`, les
commentaires et un `DOCTYPE`, trouvé par un parcours linéaire (`indexOf`, aucune expression
régulière à retour arrière : 4 096 octets de `<?a?>` se lisent en moins de 100 ms) : BeerXML,
lu (ci-dessous) ; premier élément d'une bibliothèque BeerXML (`HOPS`, `FERMENTABLES`,
`YEASTS`, `MISCS`, `WATERS`, `STYLES`, `EQUIPMENTS`, `MASHS` ou leur élément seul) :
`aucuneRecette` ; sinon `illisible`. Aucune recette (`recipes` absent ou vide, `RECIPES` sans
`RECIPE`) : `aucuneRecette`.

**BeerXML : décodage et analyse (`decodage_xml.dart`, P9).** Encodage lu dans la déclaration
`<?xml … encoding="…"?>` (1 024 premiers octets) : sans déclaration ou `UTF-8`, UTF-8 strict
(un octet invalide lève `FormatException`, sans repli) ; `ISO-8859-1`, `windows-1252` et
`US-ASCII` (et leurs alias) décodés en windows-1252, comme le fait le standard Encoding du
WHATWG pour ces noms : un fichier BeerSmith qui annonce ISO-8859-1 et contient une
apostrophe typographique (0x92) se lit juste, et les cinq octets sans caractère gardent leur
valeur, retirée ensuite comme contrôle C1 ; tout autre encodage déclaré (UTF-16, ISO-8859-15…)
ou une déclaration illisible : `illisible`. Fins de ligne normalisées (XML 1.0, § 2.11).
Analyse par `parseEvents` du paquet `xml` (`validateNesting`, `validateDocument`), sans
décodage d'entité par le paquet (`XmlNullEntityMapping`) : `exchange/` décode les cinq entités
prédéfinies et les références numériques des caractères permis par XML 1.0. Tout `DOCTYPE`,
toute autre entité (`&xxe;`, `&nbsp;`), un `&` seul ou une référence interdite (`&#0;`)
refusent le fichier (`illisible`) : aucune entité interne ni externe n'est étendue (tests :
« billion laughs » refusée en moins de 100 ms, entité externe `SYSTEM`). Noms d'éléments lus
en majuscules.

**BeerXML : lecture d'une recette (`lireRecetteBeerXml`).** La recette est d'abord récrite en
BeerJSON (`lecture_beerxml.dart`), puis lue par la lecture du BeerJSON
(`lireRecetteConvertie`) : bornes, unités, nettoyage et compte rendu sont les mêmes. BeerXML
est métrique : kilogrammes → grammes (arrondis au microgramme), litres, °C, minutes ; couleur
d'un fermentescible en Lovibond (en SRM pour un extrait liquide, `TYPE` `Extract`), convertie
par `brewing/` ; `YIELD`, sinon `POTENTIAL` (densité) converti par `brewing/`. Valeurs
énumérées lues sans casse. Correspondances (`DATA_SOURCES.md`) : `Adjunct` → `grain` ;
`First Wort` → `add_to_boil` à la durée de `BOIL_TIME`, listé (`FirstWortEnEbullition`) ;
`Aroma` avec une durée → ébullition de cette durée, listé (`AromaEnEbullition`), à 0 minute →
arrêt du feu ; `Aroma` sans `TIME` et `Whirlpool` sans durée → `add_to_boil` à 0 minute sans
`duration`, listé (`ArretDuFeuSansDuree`) ; `Whirlpool` avec durée → 0 minute et `duration` ;
`Dry Hop` → `add_to_fermentation`, `Mash` → `add_to_mash`, avec `duration` ; `Secondary`
(houblon ou ajout) → `add_to_fermentation`, listé ; ajout `Primary`, `Bottling` →
`add_to_fermentation`, `add_to_package`. `AMOUNT` d'un ajout et d'une levure en litres, en
kilogrammes si `AMOUNT_IS_WEIGHT` vaut `TRUE` (décision 6) ; une autre valeur que `TRUE` ou
`FALSE` refuse la recette. Le style garde son nom seul. Non importés et listés : `EQUIPMENT`
(`PartieNonImportee.equipement`), `WATERS`, `EFFICIENCY`, `BOIL_SIZE`, valeurs annoncées,
fermentation, conditionnement, dégustation, `ASST_BREWER` et `DATE`, nom de l'empâtage s'il
n'est pas `Empâtage` (`PartieNonImportee.nomEmpatage`), détails des paliers
(`INFUSE_AMOUNT`, rampes…) et des ingrédients.
`VERSION`, `INVENTORY`, `DISPLAY_*` et `DISP_*` ne sont pas lus ; tout autre élément est compté
(`ChampsInconnus`). Un élément vide n'est pas listé. Empreinte : `lireEmpreinte` sur la forme
canonique de l'élément `RECIPE` gardé (`[nom, texte]` d'une feuille, `[nom, [enfants]]`
sinon) : l'ordre des enfants compte, l'indentation, les fins de ligne, les champs d'affichage
et le contenu des parties non importées (eau, équipement) non. `imported_from` :
« BeerXML · sha256:… ».

**Lecture d'une recette (`lireRecetteBeerJson`).** Champ par champ, vers le sous-arbre
`recipe` dans la forme qu'écrit `RecipeContent.toFirestore` (I9), unités canoniques :

- Masses `mg`, `kg`, `lb`, `oz` → `g` ; volumes `ml`, mesures américaines et impériales
  (`tsp` à `bbl`, `ifloz` à `ibbl`) → `l` ; `F` → `C` ; `sec`, `hr`, `day`, `week` → `min`,
  arrondies à la minute (arrondi listé) ; `Lovi` et `SRM` → `EBC` par `brewing/` ;
  `yield.potential` en `sg` → % par `potentialToYieldPercent` de `brewing/`, borné par sa
  constante `maxPotentialGravity` (saccharose pur), lue par `exchange/`. Chaque unité
  convertie est listée (`UnitesConverties`). Plato et brix d'un potentiel : écartés.
- Valeur obligatoire pour l'application (nom de la recette, nom, type et quantité d'un malt,
  nom, quantité et moment d'un houblon, nom et quantité d'un ajout, nom, température
  et durée d'un palier) absente, illisible, hors bornes ou d'unité inconnue : recette refusée
  (`Refus`). La forme d'un houblon est facultative (ADR-005, D8) : absente, la ligne est
  gardée sans `form` et sans perte ; hors du schéma ou illisible, la recette est refusée. Valeur facultative hors bornes, hors du schéma ou d'unité sans dimension
  (`each`, `pkg`) : écartée, le champ reste absent, listée (`ValeurRejetee`). Une unité hors
  du schéma refuse toujours la recette ; le compte rendu la cite nettoyée (contrôles de
  direction retirés) et coupée à 120 caractères. Rendement et acides alpha à 0 : lus comme absents,
  listés. `coarse_grind` seul : écarté, listé.
- Nom d'un ingrédient sans lettre ni chiffre (`isValidIngredientName`, K3) : recette refusée.
- Moments : à l'ébullition, `time` (sinon `duration`) ; `time` 0 avec une `duration` positive :
  après l'arrêt du feu ; houblon à cru : `time` et `duration` ; autres moments, et ajout à cru :
  `duration` seule. Une heure ou un repère non gardé (`continuous`, `specific_gravity`, `pH`,
  `step`) est listé (`MomentSimplifie`, avec le moment retenu).
- `mash.name` devient `Empâtage` (`kNomEmpatage`, partagé avec l'application) ; `mash` absent
  sans température du grain ni palier. Le style garde son nom seul (listé). Le rendement, les
  valeurs annoncées, la fermentation, l'eau, le conditionnement, la dégustation, les détails
  de l'ébullition, des paliers et des ingrédients ne sont pas importés (`PartiesNonImportees`).
  `inventory`, prix et tout autre champ inconnu sont ignorés et comptés (`ChampsInconnus`).
- Textes : contrôles de direction U+061C, U+200E, U+200F, U+202A à U+202E et U+2066 à U+2069
  retirés (P9), contrôles C0 et
  C1 retirés (remplacés par une espace dans un nom ; sauts de ligne et tabulations gardés
  dans les notes). Un texte n'est jamais interprété.

**Empreinte et doublons.** `lireEmpreinte` : `sha256:` et 64 chiffres hexadécimaux sur le
JSON canonique de l'objet lu (clés triées, nombre entier écrit sans décimale : même valeur
sur la VM et sur le web ; à partir de 10^15, notation scientifique), et si la recette dépasse
`kMaxProfondeur`. Deux recettes de même empreinte dans un fichier : la seconde
`enDouble`. `importedFrom(format, empreinte)` donne `imported_from` ; `estImporteeDe` compare.

**Export (`exporterBeerJson`).** Document `{"beerjson": {"version": 2.01, "recipes": [ … ]}}`
(version candidate d'ADR-005, à confirmer par un essai d'import dans Brewtarget), en JSON
indenté de deux espaces, identique d'un export à l'autre. La recette stockée, plus `author`
(`recipe.author`, sinon `owner_name` passé par l'application quand le propriétaire exporte,
`null` pour un autre membre : décision du 2026-11-10, la recette se duplique),
`efficiency.brewhouse` (rendement d'empâtage de l'équipement, amendements de L2) et les
valeurs calculées par `computeRecipe` (densités à 4 décimales, degré à 2, IBU de Tinseth et
EBC à 1) ; style omis et listé (`StyleNonExporte`), chronologie listée
(`ChronologieNonExportee`). Sans palier ni température du grain, `mash` est omis
(`EmpatageNonExporte`) ; sans durée d'ébullition, `boil` est omis (`EbullitionNonExportee`) :
les deux sont facultatifs dans `RecipeType` (décision du 2026-11-10). Bloqué
(`ExportBloque`) tant qu'il manque le type, l'auteur, le volume, le rendement, un palier (si
la température du grain est saisie), la température du grain (si un palier l'est), le type
d'un palier, le rendement d'extrait ou la couleur d'un malt, les acides alpha d'un houblon,
le type, la forme ou la quantité d'une levure, le type d'un ajout :
`ManqueDeCalcul` (un `MissingInput` de `brewing/`, libellé par `libelleManque`) ou
`ManqueDeFormat`. `ExportPret.auteur` donne l'auteur écrit. `nomFichierExport` : `normalizeName` coupé à 100 caractères, `recette`
sinon.

**Export BeerXML (`exporterBeerXml`, v0.1.21).** BeerXML 1.0 en UTF-8 déclaré, indenté de
deux espaces, identique d'un export à l'autre (nombres par `toStringAsFixed`, zéros finaux
retirés). L'application garde l'export BeerXML visible et bloqué tant que `beer_styles` manque
(ADR-005, décision 2) : elle n'appelle pas cette fonction. Elle reçoit la recette stockée, le
nom du propriétaire (comme le BeerJSON), le rendement d'empâtage, l'évaporation, les pertes
au trub et le volume mort de l'équipement, un `StyleBeerXml` (style BJCP complet, venu du
référentiel) et le calcul de `computeRecipe`. Bloqué, en plus des manques du BeerJSON, sans
style (`ChampExport.style`), sans durée d'ébullition, sans évaporation, pertes au trub ou
volume mort (`BOIL_SIZE` = `preBoilVolumeLitres` de `brewing/`), pour un type de recette hors
`All Grain`, `Partial Mash`, `Extract`, un ajout sans moment, un houblon ou un ajout sans
durée (`USE` et `TIME` sont obligatoires) et un houblon mesuré en volume. Écrit :
`EFFICIENCY` (rendement d'empâtage), `STYLE` complet (couleurs en SRM par `brewing/`), masses
en kilogrammes, couleur en Lovibond (SRM pour un extrait liquide) par `brewing/`, `WATERS`
vide, valeurs calculées dans les champs d'affichage `EST_OG`, `EST_FG`, `EST_COLOR`, `IBU`
(`IBU_METHOD` `Tinseth`), `EST_ABV`. Pertes listées : valeur écrite autrement
(`ValeurEcriteAutrement`, avec la liste et le champ de la ligne, libellée avec les mots de
l'éditeur : « Cascade : le moment Whirlpool est écrit Aroma en BeerXML. » ; whirlpool écrit `Aroma` avec sa durée, miel, fruit et jus écrits
`Sugar`, `other` écrit `Adjunct`, forme poudre ou extrait écrite `Pellet`, levure hors des
cinq types écrite `Ale`, `dregs` écrit `Culture`, palier hors des trois types écrit
`Temperature`, `wood` écrit `Other`, houblon au conditionnement écrit `Dry Hop`), volume d'eau
d'un palier d'infusion (`INFUSE_AMOUNT`, que Kass'Beer ne stocke pas), jour d'ajout à cru,
durée après l'arrêt du feu d'un ajout, empâtage absent (`MASH` omis, comme en BeerJSON),
chronologie. Les textes sont échappés ; les caractères interdits par XML 1.0 sont retirés.

**Validation.** Fixtures écrites à la main, noms fictifs : `exchange/test/fixtures/lecture/`
(fichier et lecture attendue `*.attendu.json` ; pas `import/`, que `.gitignore` réserve aux
fichiers d'import qui portent des prix) et `export/` (fichiers attendus, dont une recette à
l'extrait sans `mash` ni `boil`, et les exports BeerXML `*.xml`), vérifiées à
l'identique par les tests du paquet (`MAJ_FIXTURES=1 dart test` les récrit, à relire avant le
commit). `rules-tests/test/exchange_schema.test.mjs` valide chaque recette lue contre le schéma
partiel et chaque fichier exporté contre le schéma officiel au commit figé (`beer.json`, ajv
`dist/2020`). Le test de l'aller-retour (A2) réimporte l'export et retrouve la recette, auteur
ajouté, style retiré. `schema_test.dart` compare les valeurs énumérées du paquet au schéma.

Quatre fixtures BeerXML écrites à la main, à la manière de BeerSmith (déclarée ISO-8859-1,
octets windows-1252, champs `DISPLAY_*`), Brewfather, Brewer's Friend (BOM, sans déclaration)
et Brewtarget (recette en double, recette sans nom), noms fictifs ; aucun fichier tiré de
Brewtarget, de DIY Dog ni de `diydog-beerxml` (ADR-005). Critère A1
(`export_beerxml_test.dart`) : lecture, export BeerXML avec le style du fichier (comme le
donnera `beer_styles`), relecture ; la recette relue est égale à la recette lue (0,01 g,
0,1 EBC, durées exactes), et l'écart entre le fichier source et l'export, rangé par
catégorie, est la liste des pertes du compte rendu de l'import (le style, repris du
référentiel, et les équivalences sans perte, `Adjunct` = `Grain` et `Aroma` 0 min = `Boil`
0 min, mis à part). L'application relit chaque recette BeerXML lue et la récrit à
l'identique (I9, `import_recipes_test.dart`). Les suites sans fichier (`analyse_test`,
`lecture_test`, `lecture_beerxml_test`) tournent aussi dans Chrome (`dart test -p chrome`) ;
`test/support/decrire.dart` n'importe pas `dart:io`.

## Ingestion des référentiels et des recettes publiques (ADR-005, L3)

Deux étapes, lancées à la main par l'administrateur sur son poste (ADR-005, D5). Les sources
vivent dans `import/sources/` (`brewtarget-v5.2.3/`, `punkapi-e6c12ab/data/`), la préparation
dans `import/ingest/prepare/`, les rapports d'écriture dans `import/ingest/rapports/` :
`import/` est ignoré par Git (P20).

```bash
# 1. Préparation, sans réseau : lit import/sources/, écrit import/ingest/prepare/
(cd exchange && dart run bin/preparer_referentiels.dart)
# 2. Écriture dans l'émulateur (par défaut), deux fois de suite : la seconde ne réécrit aucun
#    référentiel ni aucune recette ; seul son document ingest_runs est créé
(cd ingest && npx firebase --config ../firebase.json emulators:exec --only firestore --project demo-kassbeer "node ecrire.mjs && node ecrire.mjs")
# 3. Écriture en production : identifiants ADC, saisie du nom du projet au terminal
gcloud auth application-default login   # compte de l'admin ; kassbeer-ingest reporté (ADR-005, D7)
(cd ingest && node ecrire.mjs --production --projet kassbeer --simulation)   # compte sans écrire
(cd ingest && node ecrire.mjs --production --projet kassbeer)
```

**Préparation** (`package:exchange/ingestion.dart`, bibliothèque distincte de
`exchange.dart`, jamais importée par l'application ; `bin/preparer_referentiels.dart`). Aucun
`catch`, aucun réseau. Bornes : chaque fichier source fait 10 Mo au plus
(`kMaxOctetsParFichier`, contrôlé avant la lecture), 1 000 fichiers DIY Dog au plus
(`kMaxFichiersDiyDog`), JSON de 32 niveaux au plus (`kMaxProfondeur`, `lireJsonBorne`) ; au-delà,
la préparation s'arrête sans rien écrire. Aucune empreinte des sources n'est vérifiée. Lecteurs : 001 en BeerXML (`decoderXml` et `lireXml` de
`decodage_xml.dart`, sous une racine ajoutée car le fichier en a plusieurs ; listes
`FERMENTABLES`, `HOPS`, `MISCS`, `YEASTS` du premier niveau seules, ni recettes, ni
équipements, ni styles d'anciennes éditions) ; 002 à 004 en BeerJSON 2.01 et 005 en DotBeer,
JSON dont les lignes commençant par `//` sont retirées (`lireJsonCommente`) ; DIY Dog. Les
couleurs passent par `versEbc` (Lovibond et SRM de `brewing/`, P3), les °F par `versCelsius`.
Une valeur d'unité inconnue, illisible, hors bornes ou nulle (rendement, alpha, atténuation)
est écartée et comptée. Résolution d'un nom de DIY Dog : clé normalisée égale à celle d'un nom
du référentiel, puis pour une levure le producteur et la référence lus dans le nom (`Wyeast
1056`, `WLP099`), puis la table d'alias écrite à la main (`lib/src/ingestion/alias.dart`). Un
alias vers une entrée absente arrête la préparation (`StateError`). La table liste aussi les
noms de la liste `hops` qui ne sont pas des houblons (épices, fruits, copeaux) : leur ligne va
dans `miscellaneous_additions`. Sortie : `<collection>.json` (listes `{id, data}`, triées par
identifiant, `content_sha256` calculé) et `rapport.json` : entrées par source, entrées
rejetées, listes ignorées, valeurs écartées, fusions, documents par collection, recettes lues
et refusées, résolution par nature avant et après alias, valeurs recopiées, noms non résolus
avec leur nombre de lignes, lignes rejetées, libellés perdus, températures de fermentation non
reprises, taille JSON des index.

**Écriture** (`ingest/`, Node 24, ESM ; `firebase-admin` 14.5.0, comme `functions/` ; `ajv`
8.20.0 et `prettier` 3.9.6, comme `rules-tests/` ; `firebase-tools` 15.35.0 pour les tests).
`ecrire.mjs` refuse `GOOGLE_APPLICATION_CREDENTIALS` et `CLOUDSDK_CONFIG`, quelle que soit
la casse de la variable (aucune clé JSON de compte de service, aucun autre dossier gcloud) ;
en production, il lit le type du fichier ADC de gcloud (`%APPDATA%\gcloud` sous Windows,
`~/.config/gcloud` ailleurs) et n'accepte que `authorized_user`, ou
`impersonated_service_account` dont `source_credentials.type` vaut `authorized_user` :
`service_account`, à la racine ou en source d'un emprunt, est refusé, avant la confirmation ;
sans `--production`, il exige `FIRESTORE_EMULATOR_HOST` et un projet `demo-*` (sans
l'émulateur, l'Admin SDK viserait la production) ; avec `--production`, il exige
`--projet kassbeer`, l'absence de `FIRESTORE_EMULATOR_HOST`, un terminal et la saisie du nom
du projet. Il lit les huit fichiers de la liste blanche (`beer_fermentables`, `beer_hops`,
`beer_cultures`, `beer_miscs`, `beer_styles`, `beer_index`, `public_recipes`,
`import_unresolved`) et contrôle chaque document : identifiant de sa collection, clés
permises, unités canoniques, plages, provenance (sources et licences connues), empreinte, pas
de `updated_at` préparé ; `recipe` d'une recette publique limité aux clés de
`isBeerJsonRecipe` et aux plafonds de listes, puis validé par ajv contre le schéma partiel
que dérive `rules-tests/test/beerjson_partial.mjs` (`rules-tests/` installé d'abord, aucune
seconde dérivation) ; valeurs de `ingredient_refs` de la forme d'un identifiant de
référentiel, 200 caractères au plus ; chaque entrée de `beer_index` limitée aux clés de sa
nature, valeurs typées et nombres finis ; `beer_index` sous 900 Ko. Un document refusé n'est pas écrit, les
autres le sont (code de sortie 3). Il compare chaque document à la base par `getAll` (300 par
appel) : même `content_sha256`, ou mêmes champs pour `import_unresolved`, donc inchangé et non
réécrit. Les autres s'écrivent en entier (`set` sans fusion, `updated_at` du serveur), par
lots de 400. `--simulation` lit et compte sans écrire. En fin d'exécution : rapport JSON
`import/ingest/rapports/<id>.json` (comptes, documents refusés et leurs erreurs, sources, non
résolus), puis `ingest_runs/<id>` par `create`, hors simulation. L'Admin SDK se charge au
premier usage, après les contrôles. Aucun document absent de la préparation n'est supprimé.

Tests : `(cd exchange && dart test)` (`test/ingestion_test.dart`, fixtures écrites à la main
dans `test/fixtures/ingestion/`, entrées inventées dans la forme des sources) ;
`(cd ingest && npm test)` (`node --test` sous `firebase emulators:exec`, projet
`demo-kassbeer` : options, contrôle, lots sur une base simulée, et deux écritures de la
fixture `test/fixtures/prepare/` contre l'émulateur, la seconde sans aucun référentiel ni
aucune recette réécrit, seul son document `ingest_runs` créé) ;
`npm run test:unitaires` sans émulateur. La CI ne lance pas encore `ingest/` (ADR-005, D2).

## Cloud Functions

`functions/` (ADR-006) : Cloud Functions 2e génération, Node 24, TypeScript, région
`europe-west1` (celle de la base), compte d'exécution `tickets-functions@kassbeer.iam.gserviceaccount.com`. Aucun
`onRequest` ni `onCall` (P25) : aucune des quatre fonctions ne s'appelle depuis Internet.

| Fonction | Déclencheur | Réglages | Ce qu'elle fait |
|---|---|---|---|
| `publishTicket` | `onDocumentCreated('tickets/{ticketId}')` | `maxInstances` 2, 256 Mio, 60 s, sans rejeu (la passe horaire renvoie) | publie le ticket `pending` |
| `onDecisionCreated` | `onDocumentCreated('tickets/{ticketId}/decisions/{decisionId}')` | `maxInstances` 2, 256 Mio, 60 s, sans rejeu | applique la décision de l'admin (T2) |
| `onDecisionUpdated` | `onDocumentUpdated('tickets/{ticketId}/decisions/{decisionId}')` | idem | reprend une décision `failed` quand `retry_requested_at` est posé ou change ; ne fait rien sur les écritures du serveur |
| `syncTickets` | `onSchedule('every 60 minutes')`, heure de Paris | `maxInstances` 1, 256 Mio, 300 s, sans rejeu | relance les envois demandés, renvoie les `pending`, reprend les décisions au bail expiré, relit les Issues |

Les quatre lisent le secret `GITHUB_TICKETS_TOKEN` (`defineSecret`). `src/firestore.ts` charge le
SDK Admin au premier appel ; le client GitHub (`src/tickets/github.ts`, `fetch`, aucun SDK)
se construit à l'appel avec le jeton (P26). `src/logging.ts` journalise par
`firebase-functions/logger` (`logError` dans chaque `catch`) et retire tout ce qui a la forme
d'un jeton GitHub. Les règles pures (`src/tickets/model.ts`, `src/tickets/text.ts`,
`src/tickets/decisionModel.ts`) sont testées par `node --test` (`functions/test/`).
`src/tickets/issueState.ts` applique l'état d'une Issue à son ticket, pour la passe horaire et
pour une décision qui trouve son Issue déjà fermée.

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
dixième. Chaque changement de statut (`received`, `send_failed`, `over_quota`) écrit aussi
`allowed_decisions`. Après une relance de l'admin, `send_retried_at` fait chercher l'Issue
avant un nouvel envoi, comme un essai précédent. Limite de débit : non comptée. Jeton refusé ou secret vide : non compté,
`token_invalid_since` posé.

**Gabarit de l'Issue** (P24). Titre : celui du ticket, nettoyé, sur une ligne. Corps : type,
écran (modèle de route, « Autre écran » ou « Non précisé »), version (« Version inconnue »
si absente), plateforme, référence opaque, puis la description nettoyée. Jamais le nom,
l'e-mail ni l'uid. Nettoyage de tout texte publié (`publicText`) : commentaires HTML retirés,
caractères invisibles et contrôles bidirectionnels (U+200E, U+200F, U+202A à U+202E,
U+2066 à U+2069) retirés, forme NFKC, adresses e-mail remplacées par
« [adresse retirée] », HTML brut, images, pièces jointes intégrées et définitions de
référence rendus en texte, mentions `@`, renvois `#N` et `GH-N`, adresses
`github.com/<x>/<y>/issues/N` et `/pull/N` coupés par une espace sans chasse.
Firestore garde le texte saisi, lu par l'auteur et l'admin seuls.

**Décisions de l'admin** (`src/tickets/decisions.ts`, T2). Ordre suivi par
`onDecisionCreated`, `onDecisionUpdated` et la passe horaire :

1. Transaction sur la décision et son ticket. La décision doit être `pending`, `failed` avec
   `retry_requested_at`, ou `applying` au bail expiré ; sinon rien (rejeu : une décision
   `applied` ou `rejected` ne fait rien). Elle passe `rejected` si le ticket n'existe plus,
   n'a pas d'Issue, porte un `decision_lease_until` actif, ou si `action` n'est pas dans
   `allowed_decisions` (une reprise sur un ticket déjà au statut visé passe : la passe
   horaire a pu appliquer ce qu'un essai précédent a fait). Sinon bail de deux minutes sur
   le ticket (`decision_lease_until`) et sur la décision (`lease_until`), état `applying`,
   `retry_requested_at` retiré.
2. Relecture de l'Issue. Pour `refuse` et `close`, recherche d'un commentaire du compte
   16348852 qui porte la ligne `Décision <id>`. Si la décision porte déjà `comment_id`, ce
   seul commentaire est relu (`GET /issues/comments/{id}`) : présent avec la ligne, il compte
   comme publié ; supprimé (404 ou 410), il est republié sans relire les pages. Sinon, ou
   s'il a perdu sa ligne, les pages sont relues (cinq de 100 au plus). Une Issue fermée
   par un autre geste : l'état lu est appliqué au ticket (`issueState.ts`), la décision passe
   `rejected` (« Ce ticket a déjà été clos sur GitHub. »). Une Issue fermée par un essai
   précédent de cette décision (`not_planned` avec le commentaire, ou `statut:clos` avec le
   commentaire) compte comme faite.
3. `refuse` et `close` : commentaire `Réponse : <texte nettoyé par publicText>`, une ligne
   vide, puis `Décision <id>`, sauf s'il est déjà publié.
4. Étiquette `validé` (`validate`) ou `statut:clos` (`close`), sauf si elle est posée.
5. Fermeture `not_planned` (`refuse`) ou `completed` (`close`).
6. Transaction, si le bail est encore celui de cet essai : ticket au statut visé
   (`validated`, `refused`, `closed`), `allowed_decisions`, `reply_text` et `reply_at`
   (texte que la passe horaire relira dans le commentaire, préfixe et ligne `Décision`
   retirés), `status_changed_at` quand le statut ou la réponse change, bail retiré ;
   décision `applied`, `applied_at`, `steps_done`, `comment_id`.

Un échec laisse la décision `failed` avec `steps_done` et `error_reason`, et retire les deux
baux. Un jeton refusé ou un secret vide pose `token_invalid_since`. Le délai d'exécution
(60 s) est plus court que le bail (2 min) : un bail expiré veut dire une fonction arrêtée.

**Passe horaire** (`src/tickets/sync.ts`). 1. Une fois, `allowed_decisions` posé sur chaque
ticket qui ne l'a pas ou dont la liste ne suit pas le statut (marque
`allowed_decisions_backfilled_at` dans `ticket_status/github`). 2. Tickets `send_failed` avec
`retry_requested_at` (20 au plus) : en transaction, `pending`, `send_attempts` à 0,
`send_retried_at` posé, `retry_requested_at` retiré, `status_changed_at` inchangé ; puis
nouvel essai de publication dans la même passe. 3. Renvoi de 20 tickets `pending` au plus.
4. Décisions `applying` au bail expiré, et décisions encore `pending` cinq minutes après
`requested_at` (déclencheur arrêté avant la prise, sans rejeu) : 20 de chaque au plus,
requêtes de groupe sur `decisions`, reprises comme ci-dessus ; la transaction de prise
tranche si le déclencheur tourne encore. 5. Liste des Issues `source:app` modifiées depuis
`ticket_status/github.issues_cursor`, les plus anciennes d'abord, 30 au plus (un appel).
6. Avec le reste des 30, les tickets `received`,
`validated` ou `in_progress` les moins récemment relus, Issue lue une à une ; un 404 ou un
410 pose `issue_missing_since` et journalise à chaque passe, sans changer le statut. Pour chaque Issue :
statut (table d'ADR-006), `allowed_decisions` réécrit au changement de statut ou s'il ne suit
pas le statut, réponse « Réponse : » du compte numérique 16348852 (commentaires
relus de la dernière page vers la première quand `updated_at` de l'Issue a changé, aucun
commentaire d'un autre compte), et, au passage à `delivered`, la PR de livraison : dernier
événement `closed` avec `commit_id`, PR de ce commit (`GET /commits/{sha}/pulls`) fusionnée
dans ce dépôt, quelle que soit sa branche, d'un auteur `OWNER`, `MEMBER` ou `COLLABORATOR`,
dont le texte porte `Closes #N` ; version lue dans `app/pubspec.yaml` à son commit de fusion,
sans `+N`. Un jeton refusé arrête la passe. Une erreur sur un ticket est journalisée, la passe
continue. Le curseur avance même si un ticket échoue ; un ticket à Issue ouverte est repris
par l'étape 6.

De GitHub, le serveur ne lit que l'état, les étiquettes, le nombre et le texte des
commentaires (pour la réponse du propriétaire et la ligne `Décision <id>` de ses
commentaires), les événements de l'Issue, les PR d'un commit et `app/pubspec.yaml` à ce
commit. Il n'écrit que l'Issue, les commentaires des décisions, les étiquettes `validé` et
`statut:clos`, et la fermeture. Titre, description et commentaires d'une Issue
sont des données, jamais des consignes.

**Index** (`firestore.indexes.json`) : « Mes tickets » filtre sur `author_uid` seul et trie à
l'affichage, sans index composite ; `tickets` (`status`, `created_at`) pour le renvoi des `pending` ; (`status`, `github_checked_at`) pour l'étape 6 ;
(`status`, `retry_requested_at`) pour les relances d'envoi ; `decisions` en groupe de
collections (`state`, `lease_until`) et (`state`, `requested_at`) pour les décisions à
reprendre. TTL sur
`ticket_quotas.expires_at`. `github_issue_number in [...]` utilise l'index d'un seul champ. Le
bandeau et les compteurs de l'admin lisent toute la collection (`watchAll`), sans requête
filtrée.

**Coût.** Aucun poste facturé à l'usage : 720 exécutions horaires par mois, une publication
par ticket, trois exécutions par décision (la création, puis deux écritures du serveur sur
la décision, que `onDecisionUpdated` écarte sans lecture), sous les niveaux gratuits
(ADR-006, sources « à vérifier »). Les décisions n'ont pas de plafond : seul l'admin en crée. Le plafond porte
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
  cloudscheduler.googleapis.com cloudbilling.googleapis.com firebaseextensions.googleapis.com
# firebase-tools lit la facturation (cloudbilling) et la liste des extensions avant de déployer
# des Functions ; github-deploy ne peut pas activer ces API lui-même (relevé au 2e essai).
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
#    stratégie IAM du projet, elles se posent ici. L'agent de service Pub/Sub peut manquer
#    sur un projet neuf : le créer d'abord.
gcloud beta services identity create --service=pubsub.googleapis.com
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role roles/iam.serviceAccountTokenCreator --condition=None
for role in roles/run.invoker roles/eventarc.eventReceiver; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$BUILD_SA" --role "$role" --condition=None
done
#    Agent Eventarc : sans ce rôle, le déclencheur Firestore de publishTicket est refusé
#    (« Permission denied while using the Eventarc Service Agent », run 25).
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:service-$PROJECT_NUMBER@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role roles/eventarc.serviceAgent --condition=None

# 6. Artifact Registry : images des fonctions gardées un jour (ADR-006, 0,5 Go gratuits).
#    Le dépôt gcf-artifacts se crée au premier déploiement, qui échoue ensuite tant que la
#    règle manque (« could not set up cleanup policy ») : la poser juste après, puis relancer
#    deploy.yml à la main. Nom de règle repris de firebase-tools, qui la reconnaît.
echo '[{"name":"firebase-functions-cleanup","action":{"type":"Delete"},"condition":{"tagState":"any","olderThan":"86400s"}}]' > policy.json
gcloud artifacts repositories set-cleanup-policies gcf-artifacts --location=europe-west1 \
  --policy=policy.json --no-dry-run && rm policy.json

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
de l'actAs de l'étape 8. Les essais suivants ont relevé, dans l'ordre : les API Cloud Billing et
Firebase Extensions (étape 1), l'adresse complète du compte d'exécution (v0.1.22), le rôle de
l'agent Eventarc (étape 5) et la règle de nettoyage (étape 6). Les Functions sont en ligne
depuis le run 26 (2026-11-11, v0.1.22).

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
| Flutter et brewing | Flutter 3.44.6. Dans `brewing/`, puis dans `exchange/` (v0.1.20) : `dart pub get`, `pubspec.lock` à jour, `dart analyze --fatal-infos`, `dart format` vérifié, `dart test`. Dans `app/` : `flutter pub get`, `pubspec.lock` à jour, `node scripts/changelog-recent.mjs` (asset des nouveautés régénéré), `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test`, `flutter test`, `flutter build web --release` sans configuration Firebase |
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
| `deploy` | `production`, `id-token: write` | revérifie la tête de `main` ; installe `firebase-tools` depuis `rules-tests/package-lock.json` avant l'authentification ; relit par `jq`, avant l'authentification, le manifeste `functions.yaml` de l'artefact (aucun déclencheur HTTP, callable, bloquant ou de file, `maxInstances` partout, compte `tickets-functions@kassbeer.iam.gserviceaccount.com` écrit en entier (la forme courte fait échouer l'accès au secret), aucun secret autre que `GITHUB_TICKETS_TOKEN`) ; `firebase deploy --only hosting,firestore:rules,firestore:indexes` ; si `gate` l'a décidé, `firebase deploy --only functions` depuis l'artefact ; publie l'APK sur App Distribution |
| `tag` | aucun, `contents: write` | après un `deploy` réussi seulement (condition `!cancelled() && needs.deploy.result == 'success'`, pour que l'absence de `build-functions` ne l'ignore pas) : lit la version de `plan` (sans `+N`) et pose par l'API le tag annoté `vX.Y.Z` sur le commit déployé, au nom de `github-actions[bot]` (adresse `noreply`, P15). Un tag déjà présent n'est ni recréé ni déplacé (avertissement s'il pointe ailleurs). Aucune extraction du code, aucun secret, aucun accès à Google Cloud |

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
| Flutter | 3.44.6 | `app/`, `brewing/` et `exchange/` |
| JDK | Temurin 21, dans `JAVA_HOME` | émulateur Firestore de `rules-tests/` |
| JDK de Gradle | celui d'Android Studio (JBR 21), réglé par `flutter config --jdk-dir` | `flutter build apk` |
| SDK Android | plateforme 36, build-tools 36.1.0 | licences à accepter une fois par `flutter doctor --android-licenses` (commande interactive) |
| Node | 22, comme la CI et `engines` de `rules-tests/` ; 24 pour `ingest/` et `functions/` (le poste a 24.15.0, qui fait tourner `rules-tests/` aussi) | `rules-tests/`, `scripts/`, `ingest/` |
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
