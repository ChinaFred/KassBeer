# Changelog

Une entrée par version, la plus récente en tête, sous la date du jour. Titre
`### vX.Y.Z — fonctionnel` (ce que voit l'utilisateur) ou `— technique` (architecture,
données, outillage), ou les deux.

## 2026-11-13

### v0.1.37 — fonctionnel

L'administrateur peut importer les 16 fiches Excel de brassage depuis Administration › Import.
Il choisit le fichier préparé, relit chaque fiche avec ses points à revoir (divergences,
corrections, heures reprises, coût), puis confirme. Chaque fiche devient une recette et un
brassin terminé, avec sa chronologie, ses mesures et ses relevés de fermentation. Le coût de
chaque brassin est figé avec les prix de sa fiche, visible par l'administrateur seul. Un second
import du même fichier n'écrit rien, et un import interrompu reprend où il s'était arrêté.

### v0.1.37 — technique

Incrément v0.6. `exchange/` : `package:exchange/fiches.dart` lit le format `kassbeer_fiches` v1
(document BeerJSON pour les recettes, bornes de FO4), et `bin/verifier_fiches.dart` le rejoue à
la préparation. Feature `import` : analyse sans écriture, identifiants fixés par le fichier,
marque de fin `imported_from` et empreinte pour la reprise, écritures par lots dans le budget
des règles, arrêt sur 30 s sans accusé du serveur. P9 amendé : Admin › Import lit les prix des
fiches de l'administrateur et ne les écrit que dans `users/{uid}/brew_costs/`. Aucune règle
Firestore ne change ; 25 tests de règles rejouent les écritures d'un import. `.gitignore` limite
`/import/` à la racine, pour versionner `app/lib/features/import/`. Aucun paquet ne change.
`main.dart.js` passe de 5 125 522 à 5 197 841 octets.

### v0.1.36 — fonctionnel

L'administrateur peut lancer depuis la fiche d'un ticket une session Claude Code qui analyse la
demande, puis, une fois le ticket validé, une session qui en écrit le code. Chaque lancement passe
par une boîte de confirmation qui affiche les lancements restants du jour. La fiche garde
l'historique des lancements avec le lien vers chaque session. « Valider » n'est plus proposé
qu'une fois le ticket analysé. Le développement ne se lance que pour un ticket validé depuis
l'application : un ticket validé sur GitHub propose de nouveau « Valider ».

### v0.1.36 — technique

Lot T4 d'ADR-008. Callables `launchTicketAnalysis` et `launchTicketDevelopment` (`requireAdmin`,
1 instance, 120 s) ; `routine.ts` appelle l'API Routines de Claude Code par `fetch` seul, corps
`analyse #N` ou `developpement #N`, sans redirection, 30 s, jamais rejoué ; secrets
`TICKETS_ROUTINE_ANALYSIS_ID`/`_TOKEN` et `TICKETS_ROUTINE_DEV_ID`/`_TOKEN`, chacun monté par sa
seule fonction. Premier poste de coût : `ticket_routine_launch`, plafond `LAUNCHES_PER_DAY` = 10 par
jour de Paris, compté avant l'appel dans `ticket_quotas/launch_{AAAAMMJJ}`, affiché par
`ticket_status/launches` ; historique `tickets/{id}/admin/launches`. `allowed_decisions` :
`launch_analysis` et `launch_development`, `validate` seulement depuis `analyzed`, revérifié au
serveur (version de report 4) ; `launch_development` exige un « Valider » fait dans l'application
(`validated_by_app_at`), une étiquette `validé` posée sur GitHub ne suffit pas (décision de
l'utilisateur du 2026-11-13). `syncTickets` passe de `every 60 minutes` à `0 * * * *` (Europe/Paris)
pour suivre le jour de Paris du compteur. Prompts des deux routines dans `exigences-techniques.md`,
à recoller sur claude.ai : arrêt si `GIT_COMMITTER_IDENT` n'est pas `noreply`, fichiers sensibles
étendus à `ingest/` et aux fichiers de construction Android, liste fermée des appels GitHub de
l'analyse (décisions de l'utilisateur du 2026-11-13). `ci.yml` et `deploy.yml` : liste fermée étendue aux deux callables, contrôle
des secrets par fonction ajouté à la CI. Contrôles P14, P23 et P25 modifiés, P35, P36 et P39 à P42 ajoutés. Aucun
paquet ajouté ; `main.dart.js` passe de 5 125 522 à 5 159 200 octets (+ 0,7 %).

### v0.1.35 — fonctionnel

Les journées après le brassage se suivent comme le brassage. Sur la fiche d'un brassin en
fermentation, « Préparer la journée « Houblonnage à cru » » s'affiche sous sa date prévue.
Préparez la journée sur le téléphone qui servira, avec du réseau : ensuite, étapes, minuteurs,
mesures et notes marchent sans réseau. « Commencer la journée » démarre la première étape ;
une journée commencée se reprend depuis la fiche.

Une densité ou une température saisie pendant une journée compte dans le relevé de
fermentation et dans la densité finale, jamais dans la densité initiale. Elle s'affiche sous
son étape, et le relevé nomme sa journée et son étape. « Terminer la journée » termine l'étape
en cours et marque sautées celles qui restent ; une journée dont toutes les étapes sont faites
se termine seule. Une journée que vous ne ferez pas se passe depuis la fiche : le menu de la
journée porte « Passer la journée », qui marque ses étapes sautées. Dans le déroulé de la
fiche, une journée terminée résume ce qui a été fait (« Terminée · 3 faites, 1 sautée »).

La journée d'embouteillage finit par « Embouteiller » : le formulaire habituel, puis le retour
sur la fiche. L'étape en cours se termine à l'envoi. Les prix et les frais lus à la préparation servent à figer le coût, même sans
réseau. Un brassin qui a une journée d'embouteillage garde « Embouteiller sans suivre la
journée » dans le menu ⋮ de sa fiche. La liste des brassins annonce toujours la prochaine
journée d'après sa date : une journée faite en avance reste annoncée jusqu'à cette date.

### v0.1.35 — technique

Lot D4 d'ADR-010. `PlanDuJour.calculer` prend la journée suivie : événements réduits sur toutes
les journées, horaire recalculé sur la seule journée, départ au premier début de la journée,
sinon à l'heure de l'appareil ; `journeeTerminee` et `PlanDuJour.commencee` en dérivent l'état.
Routes `/brassins/:id/jour/:journee/preparer` (dans la coquille) et `/brassins/:id/jour/:journee`
(plein écran) ; `PrepareBrewScreen` et `BrewDayScreen` sont paramétrés par la clé de la
journée, `journeeASuivre` nomme les refus. « Commencer la journée » écrit le seul début de la
première étape, « Terminer la journée » un `WriteBatch` de `step_ended` et de `step_skipped`,
sans statut. Les mesures et notes d'une journée 2 ou suivante portent `phase: 'fermentation'`
(`BrewEventInput.phase`). `capturerEmbouteillage` regroupe les lectures capturées à l'envoi de
l'embouteillage pour la fiche et pour la journée, qui le confie à la fiche pour ses annonces
(`embouteillagesAAnnoncerProvider`, vidée après l'affichage, refus déjà rapportés écoutés dès
la mise en mémoire) ; l'étape en cours reçoit son `step_ended` à l'envoi. « Passer la journée »
écrit les `step_skipped` des étapes non commencées en un lot. Sept éléments de ticket et deux
noms d'écran ajoutés. `exigences-techniques.md` porte les changements des lots D1 à D4 dans ses
deux copies des sections Architecture, Modèle de données et Règles d'accès. Les règles
d'accès, `brewing/` et les dépendances ne changent pas.

### v0.1.34 — fonctionnel

« Nouveau brassin » demande le processus du brassin : vos processus, ou « Chronologie de la
recette seule » comme avant. Votre processus par défaut est déjà choisi. En dessous, « Déroulé
prévu » montre chaque journée avec sa date et son nombre d'étapes, et prévient quand la recette
n'a pas de houblon à cru pour la journée de houblonnage, ou quand des houblons à cru n'ont pas
de journée. Hors ligne, si vos processus n'ont jamais été lus sur ce téléphone, le brassin se
crée avec la chronologie de la recette seule ; vous choisirez son processus plus tard.

La fiche d'un brassin a une section « Déroulé » à la place de « Chronologie » : le processus
choisi, la journée de brassage avec ses heures et ses mesures, puis les journées suivantes avec
leur date et leurs étapes. Tant que le brassage n'a pas commencé, « Changer de processus » en
choisit un autre, et le menu d'une journée change sa date ou rétablit celle du processus.
Ensuite, le déroulé ne change plus. « Recréer depuis la recette » garde le processus du brassin.

La liste des brassins annonce la prochaine journée d'un brassin en fermentation (« Prochaine
journée : Houblonnage à cru, mer. 25 nov. »). « Préparer le brassage » et l'écran du jour
suivent la journée de brassage du processus, préparation et nettoyage compris, et la barre de
l'écran du jour nomme la journée. Le suivi des journées après le brassage arrive avec la
prochaine version : d'ici là, la mesure de densité se saisit par « Ajouter un relevé » et
l'embouteillage par « Embouteiller ».

### v0.1.34 — technique

Lot D3 d'ADR-010. `assemblerDeroule` crée les clés et les libellés du déroulé depuis les
brouillons de `resolveProcess` (clés de la recette gardées, `erreurDeroule` avant l'écriture) ;
`nomEtapePreremplie`, ses avertissements et `formatQuantiteRecette` passent dans
`recipes/domain/libelles_etapes.dart`, sans changement de l'éditeur « Chronologie du jour ».
`BrewsRepository.setProcess` écrit `process` en entier après la création (option B'), au
changement de processus ou de date, et à la recréation ; nul retire le champ. Un `process`
illisible bloque « Commencer le brassage ». `brewing/` expose `processSessionOrder` (journée
de brassage en tête, puis par écart, à égalité dans l'ordre courant), utilisé par
`resolveProcess` et par le changement de date d'une journée ; cas `session_orders` ajoutés à
`process.json`. P37 permet de lire la recette figée d'un brassin comme entrée d'une nouvelle
résolution avant le départ (`assemblerDeroule`, aperçu par `Deroule.depuisRecette`) ; toute
autre lecture de ses étapes passe par `Brew.deroule`. Trois éléments de ticket : « Changer de
processus », « Actions d'une journée », « Écart d'une journée ». Les règles d'accès et les
dépendances ne changent pas.

### v0.1.33 — fonctionnel

Le menu du compte ouvre « Mes processus », sous « Mes prix ». Un processus décrit les journées
d'un brassin : le brassage, puis par exemple le houblonnage à cru et l'embouteillage, chacune
à quelques jours du brassage, avec ses étapes de préparation et de nettoyage autour de celles
de la recette. La liste montre vos processus, puis ceux des autres brasseurs. Pour commencer,
« Partir du modèle d'exemple » ouvre un processus de trois journées aux durées typiques, à
ajuster à votre matériel avant de l'enregistrer. Vous modifiez, dupliquez et supprimez les
vôtres, et vous choisissez celui que « Nouveau brassin » vous proposera : ce choix ne
concerne que vous. Le processus d'un autre brasseur se copie dans les vôtres. Un processus
compte 5 journées au plus et 60 étapes par journée ; les journées se rangent d'elles-mêmes
par date, et une journée sans étape n'est pas acceptée. Le choix du processus à la création
d'un brassin arrive avec une prochaine version.

### v0.1.33 — technique

Lot D2 d'ADR-010. Dépôts `ProcessesRepository` (`process_templates/` : document illisible
isolé et rapporté, `erreurModele` vérifié avant chaque écriture, copie et duplication à clés
neuves) et `PreferencesProcessusRepository` (`users/{uid}/preferences/processes`), sans
transaction. Le défaut n'est remis à nul qu'après l'acceptation de la suppression de son
processus. `LigneEditeur` accepte une ligne sans formulaire, avec une icône en tête ; l'éditeur
de recette ne change pas. L'éditeur de processus défile en un seul `CustomScrollView`, une
`SliverReorderableList` par journée. Le modèle d'exemple s'appelle « Brassage, houblonnage à
cru, embouteillage », dans l'application et dans `brewing/test/fixtures/process.json`. Aucune
dépendance ne change.

### v0.1.32 — technique

Premier lot (D1) d'ADR-010 : un brassin pourra suivre de 1 à 5 journées (brassage,
houblonnage à cru, embouteillage) tirées d'un modèle de processus partagé. Rien ne change
encore à l'écran. Le paquet `brewing/` résout un modèle avec la recette figée d'un brassin :
il garde ou retire chaque journée, place chaque houblon à cru au jour donné par la recette,
une journée par jour distinct, regroupe au-delà de 5 journées, trie par écart et calcule la
date de chaque journée. Ses 10 cas de résolution, dont le modèle d'exemple, et ses dates
autour des changements d'heure du 25 octobre 2026 et du 28 mars 2027 sont dans
`process.json`. Les règles acceptent les modèles (`process_templates/`, lus par le groupe,
écrits par leur auteur), le déroulé figé d'un brassin (`process`, absent de la création,
modifiable seulement avant le départ) et le choix par défaut privé de chaque brasseur.
L'application lit les étapes d'un brassin par son déroulé : un brassin sans déroulé garde sa
chronologie de recette, un déroulé illisible s'affiche en panne et se rapporte, sans repli.
Le calcul du jour se fait journée par journée. Le budget des règles a été mesuré : un
`pad()` vaut environ 4 expressions et non 10, la marge de la création d'un brassin est
d'environ 16 expressions, l'écriture du plus grand déroulé laisse environ 590 expressions,
et un lot de 60 étapes sautées passe. `CLAUDE.md` étend la règle hors ligne à chaque journée
et « Un brassin fige sa recette » au déroulé, complète P2, P3 et P5, et ajoute les contrôles
P37 (lecture du déroulé, découpage par journée) et P38 (règles des modèles et du déroulé).

## 2026-11-12

### v0.1.31 — fonctionnel

Le suivi d'un ticket a une nouvelle étape, « Analysé », entre « Reçu » et « Validé » : votre
demande a été lue et étudiée. L'administrateur lit maintenant dans la fiche d'un ticket les
analyses publiées sur sa page GitHub, et peut y répondre depuis l'application avec le bouton
« Répondre ». Sa réponse ramène le ticket à « Reçu » pour une nouvelle analyse.

### v0.1.31 — technique

Lot T3 d'ADR-008. Deux points d'accès, seuls de la liste fermée livrés à ce lot :
`githubTicketWebhook` (HTTP public, signature `X-Hub-Signature-256` vérifiée sur le corps brut,
événements `ping`, `issues`, `issue_comment`, secret `GITHUB_WEBHOOK_SECRET`, 5 instances, 60 s)
et la callable `answerTicketAnalysis` (`requireAdmin`, 2 instances, 60 s). `functions/src/auth.ts`
(`requireAdmin`, `requireMember`, `requireBoundedText`) et `test-fixtures/member_access.json`,
rejouée par `rules-tests/` et `functions/test/`. Statut `analyzed` (étiquette `statut:analysé`),
`answer` dans `allowed_decisions` (`validate` reste offert depuis `received` jusqu'à T4),
relevé des analyses du compte 16348852 dans `tickets/{id}/admin/analysis` (lecture admin seule)
par le webhook, la tâche horaire et les décisions. `ci.yml` et `deploy.yml` remplacent le refus
de tout point d'accès HTTP ou callable par la liste fermée d'ADR-008. Contrôles P6, P14, P23 à
P26 modifiés, P29 à P34 ajoutés.

Paquets ajoutés, version exacte : `cloud_functions` 6.5.0, `flutter_markdown_plus` 1.0.7,
`markdown` 7.3.1 ; nouveaux dans `pubspec.lock` : `cloud_functions_platform_interface` 6.0.7 et
`cloud_functions_web` 5.1.13. La famille FlutterFire ne change pas. `main.dart.js` passe de
4 920 447 à 5 125 522 octets (+ 4,2 %).

### v0.1.30 — technique

`documentation/exigences-techniques.md` ne contient plus qu'une copie (2 695 lignes au lieu de
3 959). Le commit `9e72415` avait remplacé la ligne `import_unresolved/` par un texte contenant
`` $` `` : dans un `String.replace` JavaScript, cette séquence insère tout ce qui précède le
passage remplacé, et le début du document s'est trouvé copié au milieu de cette ligne. Chaque
passage qui différait entre les deux copies garde sa version la plus récente, vérifiée contre le
code ; la ligne `import_unresolved/` est recousue, avec l'expression de `firestore.rules`.

## 2026-11-11

### v0.1.29 — fonctionnel

Le menu du compte propose « Préférences ». On y choisit le thème de l'application : clair,
sombre, ou comme l'appareil. Le changement est immédiat et reste enregistré sur l'appareil
utilisé ; chaque téléphone ou navigateur garde son propre choix. Par défaut, l'application suit
le réglage de l'appareil, comme avant. Demandé par le ticket #25.

### v0.1.29 — technique

ADR-009 accepté : préférence de thème gardée sur l'appareil, sans paquet ajouté. Canal Kotlin
`fr.kassbeer/prefs` (`SharedPreferences` `kassbeer_prefs`, clé `theme_mode`, valeurs `light`,
`dark`, `system`) et `window.localStorage` sur le web. La valeur est lue avant `runApp`, en
parallèle de `Firebase.initializeApp`, pour que le premier écran s'affiche dans le bon thème.
Le canal refuse un second appel pendant un appel en cours (P17) ; côté Dart, seul le dernier
choix part une fois le précédent écrit. Page `/preferences`, entrée du menu du compte. Une valeur
inconnue ne laisse que sa longueur dans le rapport d'erreur (P13). Aucune donnée Firestore,
aucune règle changée. Demandé par le ticket #25.

### v0.1.28 — fonctionnel

L'éditeur de recette s'appuie sur la Bibliothèque. En tapant le nom d'un malt, d'un houblon,
d'un ajout ou d'une levure, vous voyez les ingrédients qui correspondent, par nom ou autre nom.
Choisir l'un d'eux remplit les valeurs encore vides : couleur et rendement d'un malt, acides
alpha et forme d'un houblon, type, forme et atténuation d'une levure, type d'un ajout. Une
valeur déjà saisie ne change pas ; si elle diffère, « Reprendre les valeurs de la Bibliothèque »
la remplace. Le champ « Style » propose les styles BJCP par code ou par nom. Hors ligne, les suggestions viennent
de ce qui a déjà été lu ; sinon, la saisie reste libre.

L'export BeerXML est ouvert. Il retrouve le style de la recette dans la Bibliothèque, avec sa
catégorie et ses plages. Une recette sans style de la Bibliothèque demande de le choisir dans
les suggestions du champ Style. Le type du style BeerXML suit la levure de la recette : précisez-la si
l'export le demande. Un style sans plage chiffrée dans le guide BJCP ne s'exporte pas en
BeerXML : choisissez un autre style, ou exportez en BeerJSON. Quand votre équipement n'a pas
l'évaporation, les pertes ou le volume mort, « Compléter l'équipement » ouvre sa fiche.

Recettes › Importer complète les valeurs absentes du fichier quand le nom d'un ingrédient est
celui d'une entrée de la Bibliothèque, ou l'un de ses autres noms. Une valeur du fichier n'est
jamais remplacée. Les détails de chaque recette listent les valeurs reprises, par exemple
« Couleur de Pils reprise de la Bibliothèque. ». Hors ligne, l'import marche comme avant et le
dit. Les noms qu'aucune entrée ne reconnaît sont signalés à l'administrateur, sans votre nom ni
celui du fichier, pour qu'il complète la Bibliothèque.

### v0.1.28 — technique

`firestore.rules` ouvre `import_unresolved/` à l'écriture d'un membre (ADR-005, E6). Un membre
crée un nom non résolu à `count` 1, avec `source: import` et le nom normalisé dans `key`. Les
règles recalculent l'identifiant (SHA-256 de `import|nature|key`) et refusent tout autre
identifiant. Ensuite, seuls `name`, `count` (+ 1) et `updated_at` changent. Un document de
l'ingestion, d'un autre identifiant, ne se met jamais à jour par un membre. L'application en
signale 200 au plus par import, par lots de 10. Le contrôle P19 et la puce « Échange » de
`CLAUDE.md` le disent ; les règles de `recipes/` et `brews/` ne changent pas.

Dans `exchange/`, `noms.dart` regroupe la normalisation des noms partagée par l'ingestion et
l'application, et les deux empreintes de `import_unresolved/`. `resolution_import.dart`
résout les noms d'une recette importée contre les index de la Bibliothèque reçus en paramètre,
et reprend les valeurs absentes. L'export BeerXML tire son style d'une fiche de la Bibliothèque
(`styleBeerXmlDe`).

### v0.1.27 — fonctionnel

« Signaler ou proposer » a un nouveau champ, « Élément précis », sous « Écran concerné ». Il
permet de désigner un menu ou une fenêtre de l'écran : « Embouteillage » ou « Plus d'actions »
sur un brassin, « Houblon » dans l'éditeur de recette, « Menu du compte »… Par défaut, le ticket
porte sur l'écran entier. Le suivi affiche l'écran et l'élément, par exemple « Brassin ›
Embouteillage ». Les listes passent sur deux lignes quand le texte est agrandi. Demandé par le
ticket #26.

### v0.1.27 — technique

Table fermée `kTicketElements` dans `ticket_screens.dart` : la valeur `screen` devient
`<modèle de route>/menu/<clé>` ou `<modèle de route>/fenetre/<clé>`, acceptée sans changement
par `firestore.rules` et `routeTemplateOrNull` (cas ajoutés dans `rules-tests/` et
`functions/test/`). Chaque appel qui ouvre un menu ou une fenêtre dans `app/lib` porte un
commentaire `// ticket: <clé>` ou `// ticket: aucun (<raison>)`, vérifié par
`ticket_screens_test.dart`. Demandé par le ticket #26.

### v0.1.26 — fonctionnel

Une nouvelle entrée « Bibliothèque », à côté de Recettes, montre les styles de bière, les malts
et sucres, les houblons, les levures, les ajouts divers et les recettes publiques DIY Dog. Une
recherche filtre chaque liste par nom, autre nom ou code de style. La fiche d'un style donne ses
plages de densité, de degré, d'amertume et de couleur. La fiche d'un ingrédient donne ses valeurs,
sa source et sa licence.

La fiche d'une recette publique montre ses ingrédients, ses paliers, les valeurs que Kass'Beer
peut calculer et, à part, les valeurs annoncées par la recette d'origine. Un houblon dont la
recette d'origine ne donne pas la durée garde le moment indiqué par la source, traduit.
« Dupliquer » copie la recette dans vos recettes et ouvre l'éditeur : choisissez votre
équipement, et la forme des houblons, que la recette d'origine ne donne pas, pour obtenir
densités, degré et amertume. Une recette dont un houblon n'a pas de forme dit « Forme du
houblon à compléter ». Recettes › Importer accepte aussi un houblon sans forme, sans rien
perdre : la forme reste à compléter dans la recette, et l'export BeerXML attend qu'elle le
soit.

« Sources des données », ouvert depuis la Bibliothèque ou le menu du compte, nomme chaque source,
sa licence et ce que Kass'Beer en a changé. La Bibliothèque demande le réseau, sauf pour ce qui a
déjà été lu. Elle reste vide tant que l'administrateur n'a pas chargé les données.

### v0.1.25 — technique

Les styles BJCP 2021, les malts et sucres, les houblons, les levures et les ajouts de
Brewtarget, et les 415 recettes publiques de DIY Dog sont en base depuis le 11 novembre. Ils ne
sont pas encore visibles dans l'application : l'écran de consultation arrive à la version
suivante. Un sucre, un miel ou un lactose de la liste des malts garde maintenant son type ;
11 lignes de recettes écrites le 11 novembre portent encore « grain », et la prochaine
exécution de l'outil met à jour ces seules recettes. Un outil du poste lit les fichiers d'origine, fusionne les doublons (2 670 entrées
lues, 1 895 retenues, plus 110 styles), convertit les unités et ne garde que les noms et les
valeurs techniques, sans description ni note. Il rattache chaque ingrédient d'une recette
publique au référentiel et recopie dans la ligne la couleur et le rendement d'un malt, l'acide
alpha d'un houblon, le type, la forme et l'atténuation d'une levure quand la recette ne les
donne pas. Après une table d'équivalences écrite à la main, 85 % des lignes de malts, 98 % des
houblons et 96 % des levures sont rattachées. Les noms restés sans équivalent sont gardés tels
quels dans la recette et listés pour l'administrateur. Les valeurs annoncées par BrewDog
(densités, degré, amertume, couleur) sont gardées à part et marquées comme telles. Les
référentiels et les recettes publiques sont lisibles par tout membre et ne s'écrivent que par
cet outil ; relancé sur les mêmes données, il ne réécrit aucun référentiel ni aucune recette,
et n'ajoute que le compte rendu de l'exécution. Paquets du nouveau lockfile de l'écrivain :
firebase-admin 14.5.0, ajv 8.20.0, firebase-tools 15.35.0, prettier 3.9.6.

### v0.1.24 — fonctionnel

L'administrateur traite les tickets depuis l'application. Le menu du compte gagne « Tickets à
traiter », avec le nombre de tickets qui attendent une décision, et la page Admin la tuile
« Tickets des membres ». La liste se filtre (à traiter, tous, bloqués) et montre l'auteur de
chaque ticket. La fiche d'un ticket permet de le valider, de le refuser avec un motif ou de le
clore avec un commentaire, de relancer un envoi en échec et d'ouvrir l'Issue sur GitHub ; elle
suit l'avancement de la décision. Une frise montre les étapes du ticket, ici comme dans Mes
tickets, et les statuts prennent de nouvelles couleurs. Sur grand écran, la liste et la fiche
s'affichent côte à côte.

### v0.1.24 — technique

Lot T2 d'ADR-006. Décisions de l'admin par documents `tickets/{id}/decisions/{decisionId}`,
appliquées sur l'Issue par les déclencheurs `onDecisionCreated` et `onDecisionUpdated` (bail en
transaction, reconnaissance de la ligne `Décision <id>`, commentaire « Réponse : » nettoyé,
étiquette, fermeture) ; `allowed_decisions` calculé par le serveur ; relance des envois par
`retry_requested_at` à la passe horaire ; règles et tests des décisions pour les cinq profils ;
trois index. Côté client : Admin › Tickets des membres, frise `FriseTicket`, tons `neutre`,
`primaire` et `tertiaire` d'`Etiquette`, liste et détail côte à côte. ADR-008 accepté : parité
avec Kass'Dalle (option B : webhook, callables, Cloud Storage, sessions Claude Code), lots T3 à
T7 ; ADR-001 et ADR-006 le citent. Aucun paquet ajouté.

### v0.1.23 — technique

« Réglages faits une fois » ajoute les derniers réglages relevés au déploiement des
Functions : la création de l'agent de service Pub/Sub, qui peut manquer sur un projet neuf, le
rôle `eventarc.serviceAgent` de l'agent Eventarc, sans lequel le déclencheur
Firestore de `publishTicket` est refusé, et la règle de nettoyage du dépôt `gcf-artifacts`
posée par `gcloud`, sans laquelle firebase-tools termine en erreur. Les Functions des tickets
sont en ligne depuis la v0.1.22.

## 2026-11-10

### v0.1.22 — technique

Les Functions déclarent leur compte d'exécution par son adresse complète
(`tickets-functions@kassbeer.iam.gserviceaccount.com`). Avec la forme courte
`tickets-functions@`, firebase-tools refusait de donner au compte l'accès au secret
`GITHUB_TICKETS_TOKEN` (erreur 400), et le premier déploiement des Functions échouait. Le
contrôle du manifeste dans `deploy.yml` n'accepte plus que l'adresse complète.

### v0.1.21 — fonctionnel

Recettes › Importer lit aussi les fichiers BeerXML, le format qu'exportent BeerSmith,
Brewfather, Brewer's Friend et Brewtarget. Le fichier s'importe comme un fichier BeerJSON :
aperçu sans écriture, recettes déjà importées ou en double décochées, compte rendu. Un fichier
BeerSmith qui contient des apostrophes ou des accents se lit sans caractère faux. « Détails »
dit ce qui change à l'import : un houblon « First Wort » compte à l'ébullition pendant toute
l'ébullition de la recette, un houblon « Aroma » avec une durée compte à l'ébullition pendant
cette durée (si c'était un whirlpool, choisissez Whirlpool dans la recette), un whirlpool sans
durée compte à l'arrêt du feu, et le style ne garde que son nom. Le profil d'eau, les étapes de fermentation
et l'équipement du fichier ne sont pas importés. Une levure liquide mesurée en litres garde sa
quantité en litres. Un fichier BeerSmith (.bsmx) n'est pas lu : exportez la recette en
BeerXML depuis BeerSmith. L'export BeerXML reste visible et bloqué : il demande un style de la
liste BJCP, dont le choix arrive dans une prochaine version.

### v0.1.21 — technique

Livraison L2c d'ADR-005. `CLAUDE.md` (« Le projet », « Structure ») et `guide-reseau.md` disent que
`exchange/` lit et écrit le BeerXML.

`exchange/` gagne `xml` 7.0.1, version prévue par ADR-005,
et sa dépendance `petitparser` 7.0.2 : ce sont les deux paquets ajoutés à
`exchange/pubspec.lock`. `app/pubspec.lock` ne change pas : `xml` 7.0.1 et `petitparser` 7.0.2
y étaient déjà, tirés par `dbus` ; ils entrent désormais dans `main.dart.js`, qui passe de
4 668 716 à 4 735 582 octets (+66 866, +1,4 %). APK de release compilé sur le PC.

Lecture du BeerXML 1.0 : encodage déclaré (UTF-8 par défaut ; ISO-8859-1, windows-1252 et
US-ASCII décodés en windows-1252, comme le standard Encoding du WHATWG ; autre encodage
refusé), fins de ligne normalisées, analyse à événements sans récursion, 16 niveaux
d'éléments au plus, aucun `DOCTYPE` ni entité autre que les cinq prédéfinies et les
références numériques (tests d'une « billion laughs » et d'une entité externe, P9). Revue de
sécurité : l'analyse ne garde que les éléments que la lecture utilise (`kConteneursBeerXml`),
300 000 au plus (`kMaxElementsXml` ; 500 recettes de 50 houblons en gardent 203 501) ; un
fichier BeerJSON de plus de 1 000 000 de valeurs (`kMaxValeursJson`, comptées dans le
parcours de la profondeur) est refusé avant `jsonDecode` ; une liste n'est convertie que
jusqu'au plafond + 1, et le refus cite le nombre du fichier ; le texte d'un élément coupé en
morceaux (commentaires, CDATA) se joint une seule fois, au lieu d'une recopie par morceau ;
le décodage windows-1252 passe par un `Uint16List`. Chaque
recette est récrite en BeerJSON puis lue par la lecture du BeerJSON (`lireRecetteConvertie`) :
mêmes bornes, mêmes unités, même compte rendu, même empreinte (`imported_from` « BeerXML ·
sha256:… ») et même détection de doublon. Correspondances de `DATA_SOURCES.md` : `First
Wort`, `Aroma`, `Whirlpool`, `Secondary`, `Adjunct`, `Wheat`, couleur en Lovibond ou SRM et
`POTENTIAL` convertis par `brewing/`, quantités d'ajout et de levure en litres sauf
`AMOUNT_IS_WEIGHT`. Nouvelles modifications `FirstWortEnEbullition`, `ArretDuFeuSansDuree`,
`AromaEnEbullition` et parties non importées `equipement` et `nomEmpatage` ; `RaisonFichier.beerXml` (« sa lecture
arrive dans une prochaine version ») est retiré, avec son libellé. `formatPresume` donne le
format présumé dans le rapport d'un fichier illisible.

Écriture du BeerXML (`exporterBeerXml`) : complète et testée, bloquée sans style BJCP
(`StyleBeerXml`, qui viendra de `beer_styles`) ; l'application ne l'appelle pas encore
(décision 2). `BOIL_SIZE` vient de `preBoilVolumeLitres`, nouvelle formule de `brewing/`
(volume en fermenteur, pertes au trub, volume mort de la cuve d'ébullition, évaporation),
cas ajoutés d'abord à `brewing/test/fixtures/boil_volume.json`. Pertes et manques propres au
BeerXML ajoutés à `ChampExport` et `PerteExport` (`ValeurEcriteAutrement` porte la liste et
le champ de la ligne), avec leurs libellés aux mots de l'éditeur. Quatre fixtures
BeerXML écrites à la main (à la manière de BeerSmith en windows-1252, Brewfather, Brewer's
Friend, Brewtarget ; noms fictifs) : leurs lectures passent le schéma partiel par ajv, et le
critère A1 (lecture, export, relecture ; écart entre la source et l'export égal aux pertes du
compte rendu) est vérifié en test. Textes de l'import et de la liste vide rétablis selon la
proposition d'écran validée. Aucune règle Firestore ne change.

### v0.1.20 — fonctionnel

Recettes › Importer : « Importer », dans la liste des recettes, lit un fichier BeerJSON exporté
d'un autre logiciel de brassage (500 recettes et 10 Mo au plus) et crée ses recettes à votre
nom. Avant toute écriture, un aperçu donne pour chaque recette son état : « Prête »,
« Incomplète », « Déjà importée le … » (même contenu déjà importé par vous, décochée),
« En double dans le fichier » ou « Refusée », avec la raison. « Détails » liste ce qui reste à
compléter et ce qui a changé à l'import (unités converties, valeurs écartées, parties non
importées). Vous choisissez l'équipement des recettes, cochez celles à importer, puis lisez le
compte rendu : créées, ignorées, en erreur. L'import marche sans réseau : les recettes partent
au retour du réseau. Les prix et le stock du fichier ne sont jamais importés. Le BeerXML n'est
pas encore lu : un fichier BeerXML est annoncé comme tel.

« Exporter », sur la fiche de toute recette du groupe, produit un fichier BeerJSON sans aucun
prix : sur Android, « Enregistrer » ou « Partager le fichier » ; sur le web, « Télécharger ». Le
fichier porte l'auteur de la recette, le rendement de son équipement et les densités, le
degré, l'amertume et la couleur calculés. Ce qui manque au format est listé (« Type de recette
non renseigné. ») ; l'auteur peut compléter la recette, un autre membre la duplique. Une
recette à l'extrait, sans palier ni température du grain, s'exporte sans empâtage ; une
recette sans durée d'ébullition, sans ébullition ; la feuille le dit, comme pour le style et la
chronologie du jour, qui ne sont pas exportés. La recette d'un autre membre qui n'indique pas
d'auteur ne s'exporte pas à son nom : la feuille propose « Dupliquer », et la copie s'exporte à
votre nom. Avant l'envoi, la feuille nomme l'auteur écrit dans le fichier. Si l'envoi échoue,
la feuille le dit et l'envoi peut se refaire. L'export BeerXML
est visible et bloqué : il demande un style de la liste BJCP, qui arrive dans une prochaine
version.

### v0.1.20 — technique

Livraison L2b d'ADR-005, avec le canal de fichiers d'ADR-007.

Nouveau paquet Dart pur `exchange/` (dépend de `brewing/` et de `crypto` ^3.0.8) : bornes de
P9 (10 Mo, 500 recettes, plafonds des listes, textes coupés), détection du format par le
contenu (BeerJSON 1 à 3, JSON non BeerJSON, BeerXML annoncé, BeerSmith), lecture BeerJSON
champ par champ vers le modèle partiel (unités converties, Lovibond, SRM et densité
potentielle par `brewing/`), compte rendu par recette (`Refus`, `Modification`, empreinte
SHA-256, doublon dans le fichier), export BeerJSON 2.01 (`author`, `efficiency.brewhouse` pris
au rendement d'empâtage de l'équipement, valeurs de `computeRecipe`, style omis, `mash` et
`boil` omis et listés quand ils sont vides), liste de ce qui bloque l'export ; `author` pris à
`owner_name` pour le seul propriétaire. Contrôles de direction U+061C, U+200E, U+200F,
U+202A à U+202E et U+2066 à U+2069 retirés des textes importés. Après conversion, un nombre
non fini ou au-delà des plafonds de `bornes.dart` (1 000 kg ou 1 000 L par ligne, 10 000 L de
volume, 2 000 EBC, 365 jours hors ébullition, valeurs nouvelles) refuse la recette ou est
écarté ; une recette imbriquée sur plus de 32 niveaux est illisible, et un fichier JSON plus
profond que 36 niveaux est refusé avant son décodage, par un parcours linéaire des octets.
L'en-tête d'un fichier XML se lit par `indexOf`, sans expression régulière à retour arrière ;
une version ou une unité inconnues ne s'affichent que courtes et nettoyées. Fixtures écrites à la
main ; `rules-tests/test/exchange_schema.test.mjs` valide les recettes lues contre le schéma
partiel et les fichiers exportés, recette à l'extrait comprise, contre le schéma officiel au
commit figé. `brewing/` gagne `normalizeName` (nom du fichier exporté) et
`maxPotentialGravity` (borne de `potentialToYieldPercent`, lue par `exchange/`), sans formule
nouvelle.

Application : `app/lib/core/fichiers/` (`EchangeFichiers`, canal `fr.kassbeer/files` sur
Android, `package:web` sur le web) ; `EchangeFichiers.kt` (`pickDocument` borné à
`maxBytes + 1` octets et contrôlé avant lecture, `shareFile` qui prépare son fichier hors du fil
principal, `saveDocument`, codes `TOO_LARGE`, `ALREADY_ACTIVE`, `NO_PICKER`, `INVALID_NAME` ;
choix, enregistrement et partage marqués jusqu'à leur résultat final, un second appel rend
`ALREADY_ACTIVE`), branché dans `MainActivity.kt` ;
`ExportsFileProvider` non exporté, limité à `cacheDir/exports/`, vidé à chaque lancement ;
aucune permission de stockage. Écrans Recettes › Importer (`/recettes/importer`) et feuille
« Exporter » ; `libelleManqueExport` étend `libelleManque` ; aperçu en `ListView.builder` avec
statuts mémorisés par équipement (53 ms pour un appui sur une case avec 500 recettes, en
test) ; statut « Prête » calculé avec le nom du jeton, celui qu'écrit l'import ; panne inattendue
de l'analyse rapportée sous `exchange.read`. `imported_from` porte
`BeerJSON · sha256:…` ; `Recipe` lit `created_at`. Aucune règle d'accès ne change : le budget
des règles est inchangé.

Dépendances. `app/pubspec.lock` : seule l'entrée `exchange` (chemin) s'ajoute ; `crypto`
reste en 3.0.8, dépendance indirecte. Android : `androidx.core:core:1.17.0` déclaré dans
`app/android/app/build.gradle.kts`, version déjà résolue par le graphe des greffons (aucun
changement de version). CI : le job « Flutter et brewing » contrôle aussi `exchange/`
(dépendances, `pubspec.lock`, analyse, format, tests).

### v0.1.19 — technique

Le job `tag` de `deploy.yml` était ignoré quand `build-functions` ne tournait pas (cas de tout
déploiement qui ne touche pas `functions/`) : la condition implicite `success()` de GitHub est
fausse dès qu'un job en amont est ignoré. Sa condition devient `!cancelled() &&
needs.deploy.result == 'success'`, comme celle de `deploy`. Les versions 0.1.16 et 0.1.18 n'ont
pas reçu de tag et le reçoivent à la main.

### v0.1.18 — technique

`deploy.yml` gagne un job `tag` : après un déploiement réussi, il pose le tag annoté `vX.Y.Z`
sur le commit déployé, par l'API GitHub, au nom de `github-actions[bot]`. Une session cloud ne
pouvait pas pousser de tag, et le tag manuel venait parfois avant la fin de la CI (leçon 16).
Le job a seul `contents: write`, sans secret ni accès à Google Cloud ; un tag existant n'est
ni recréé ni déplacé ; sur un lancement manuel, il attend la CI verte du commit. L'étape 6 de
la chaîne de travail devient une vérification. La documentation du ruleset de `main` compte
désormais cinq contrôles requis, avec « Functions — lint, build, tests ». « Réglages faits une
fois » ajoute ce que le premier déploiement des Functions a révélé : création du compte compute
par l'API Compute Engine, `roles/editor` retiré des comptes compute et App Engine, et droit
d'agir au nom du compte App Engine pour `github-deploy`, et activation des API Cloud Billing
et Firebase Extensions, que firebase-tools lit avant de déployer des Functions.

### v0.1.17 — fonctionnel

La quantité d'un ajout et celle d'une levure se saisissent en grammes ou en millilitres : le
choix de l'unité se trouve avant la quantité. Une quantité en volume s'affiche en millilitres
sous 1 L, en litres au-delà.

Dans Mes prix, un houblon ou un ajout peut avoir un prix au litre, saisi en litres ou en
millilitres (« 6,50 € les 100 ml · 65,00 €/L »). Une ligne en millilitres se chiffre alors
avec ce prix, dans le coût d'une recette comme dans le coût figé d'un brassin. Sans prix,
« Saisir le prix au litre » l'ouvre directement en litres. Une ligne en millilitres face à un
prix au gramme, ou l'inverse, le dit (« votre prix est au gramme ») : aucune densité n'est
supposée ; le message dit toujours quelle unité de prix la ligne attend (au gramme, au
litre ou au sachet). En remplaçant un prix au gramme par un prix au litre, ou l'inverse, le
formulaire prévient que les lignes de l'autre unité ne seront plus comptées. Deux lignes de
même nom, l'une en grammes et l'autre en volume, sont signalées : l'auteur les remet dans la
même unité, un autre membre duplique la recette.

Kass'Beer lit et garde maintenant les valeurs des recettes venues d'autres logiciels de
brassage, avant l'arrivée de l'import : extrait liquide ou sec, miel, fruit et jus, comptés
comme des sucres dans la densité initiale ; houblon à l'empâtage ou au conditionnement ; cônes
pressés, comptés comme des cônes ; houblon en poudre, en extrait ou en cônes frais ; jour
d'ajout d'un houblon à cru ; auteur indiqué par le fichier importé, affiché sur la fiche.
L'éditeur garde ces valeurs à l'enregistrement. Quand le calcul ne sait pas les traiter,
« À compléter » le dit : « Nature à préciser », « Moment non pris en charge par le calcul »,
« Forme non prise en charge par le calcul » ; l'éditeur avertit aussi sous la nature et sous
la forme. Un houblon mesuré en volume n'est pas compté dans l'amertume, et la fiche le nomme ;
l'en-tête des houblons ne compte que les houblons pesés dans sa masse. Dans Prévu et mesuré,
la question sur les sucres nomme les ingrédients ajoutés hors de l'empâtage. Les choix par
boutons passent l'un sous l'autre quand le texte est grand. Les chiffres des recettes
existantes ne changent pas.

### v0.1.17 — technique

Livraison L2a d'ADR-005. ADR-007 est accepté (choix et partage d'un fichier par un canal Kotlin et
`package:web`, sans greffon) ; son code, P28, l'extension de P17 et les lignes de `CLAUDE.md`
arrivent avec L2b. ADR-005 reçoit les amendements de L2 : trois PR, rendement exporté pris à
l'équipement (décision 8 remplacée), 500 recettes et 10 Mo par fichier (décision 11 modifiée),
export BeerXML bloqué jusqu'à L3, quantités en litres, `recipe.efficiency` jamais stocké, prix au
litre.

Livraison L2a d'ADR-005 (lecture et calculs), option A retenue : `recipe.author` est stocké
(1 à 120 caractères), `recipe.efficiency` ne l'est pas. `brewing/` : `MissingInputKind` gagne
`fermentableKind`, `hopUse` et `hopForm` ; `FermentableInput.kind`, `HopInput.form` et
`HopInput.massGrams` deviennent nullables (nature `other`, forme sans facteur de Tinseth,
houblon en volume exclu de l'IBU et listé dans `RecipeCalculation.hopsWithoutMass`) ;
`HopUse.mash` et `HopUse.package` s'ajoutent ; `FermentableKind.ofType` et
`HopForm.ofBeerJson` remplacent les deux `fromStored` (extrait, miel, fruit, jus → sucre ;
`plug` → cônes ; `other`, `powder`, `extract`, `leaf (wet)` → sans valeur de calcul) ;
`CostUnit.litre` ; `MeasurementGapKind.fermentableKind` dans `compareBrewWithPlan` ;
conversions Plato ↔ SG, SRM et Lovibond ↔ EBC, `yield.potential` → % (`conversions.dart`).
Aucune formule ne change ; cas ajoutés d'abord à `recipe.json`, `ibu.json`,
`brew_comparison.json`, `cost.json` et `conversions.json`. Pas de rendement de brassage ni de
volume avant ébullition (décision 3, `BOIL_SIZE` en L2c). Application : `Quantite` (g ou l)
pour houblons, ajouts et levures ; type de malt et forme de houblon gardés en valeur BeerJSON
(`typesFermentable`, `formesHoublon`) ; jour d'ajout à cru (`HopLine.dayMin`) ; éditeur avec
unité g ou ml ; deux lignes de même clé en g et en l écartées de `groupCostItems` avec la
raison `QuantitesDeDeuxUnites`. Règles : `author` ajouté à `isBeerJsonRecipe`, `efficiency`
refusé ; les unités des `amount` des listes restent contrôlées par le schéma partiel et la
lecture Dart. Budget mesuré sur l'émulateur avec `author` : création d'une recette 64 `pad()`,
création d'un brassin qui la copie 4 `pad()` (environ 40 expressions), brassin du 22 novembre
93 `pad()` ; `efficiency` faisait dépasser la limite à la création d'un brassin. Fixture ajv
`imported.json`. Aucun fichier de l'écran du jour ne change ; il lit les nouvelles valeurs par
`RecipeContent.fromFirestore` et `ContenuRecette`. Aucune dépendance ne change.

Prix au litre (décision du 2026-11-10) : `CostUnit.purchaseUnits` gagne `litre` (cas
`acide-lactique-au-litre`, `litres-pour-des-litres` et `litres-pour-des-grammes` ajoutés à
`cost.json` d'abord ; la formule du coût ne change pas) ; `users/{uid}/prices.unit` accepte
`l` dans les règles (tests des cinq profils dans `users.test.mjs`, `ml`, `L`, `kg` et `kwh`
refusés) ; `brew_costs.lines` porte `l` et se relit ; `purchaseUnitsOf` (litres pour houblon
et ajout), seuil de prix inhabituel de 1 000 €/L, formulaire de prix en kg, g, L ou ml.
Relectures : `_Choix` passe en colonne quand les libellés mesurés par `TextPainter` ne
tiennent pas ; avertissements en `tertiary` ; `IngredientNature.ofFermentable` accepte une
nature nulle et sert `FermentableLine.nature` ; les branches `on BrewingInputException`
inatteignables de `recipes_repository.dart` et `brews_repository.dart` sont retirées ; tests
de modification de `recipe.author` et de `recipe_snapshot.recipe.author`. Budget remesuré :
modification d'une recette 61 `pad()`, prix au litre 93, coût figé de 200 lignes 94 ; création
d'un brassin inchangée (4). `segmentsTiennent` et `BoutonsSegmentes` passent dans
`core/presentation/segments.dart`, partagés par les choix de l'éditeur et l'unité d'un prix ;
`TextesCout.prixIncompatible` nomme l'unité attendue de la ligne et remplace
`TextesCout.uniteIncompatible` ; `volumeParle`, `achatParle` et `prixUnitaireParle` donnent
la lecture d'écran des quantités et des prix.

### v0.1.16 — fonctionnel

Le menu du compte gagne « Signaler ou proposer » et « Mes tickets ». Un membre signale un bug,
propose une évolution ou une nouvelle fonctionnalité depuis l'écran où il se trouve, même sans
réseau : le ticket part au retour de la connexion. Le titre et la description sont publiés sur
un site public, sans le nom ni l'adresse de l'auteur. « Mes tickets » montre où en est chaque
demande : reçue, validée, en cours, livrée, refusée ou close, avec la réponse de
l'administrateur. Une pastille sur l'avatar signale un changement à lire. Une demande livrée dit
dans quelle version, et si une mise à jour de l'application est nécessaire. Cinq tickets par
membre et par jour, vingt pour le groupe. L'administrateur voit sur la page Admin si l'envoi des
tickets est bloqué.

### v0.1.16 — technique

Lot T1 d'ADR-006 et son avenant. Premières Cloud Functions (`functions/`, Node 24, TypeScript,
`europe-west1`, sans point d'accès HTTP) : `publishTicket` (déclencheur Firestore : plafonds,
bail en transaction, Issue publiée avec `source:app` et `type:*`, texte nettoyé) et
`syncTickets` (tâche horaire : renvoi, statuts lus sur GitHub, « Réponse : » du mainteneur, PR
fusionnée et version livrée, Issue disparue, état du jeton dans `ticket_status/github`).
Règles et tests de `tickets/`, `ticket_quotas/` et `ticket_status/`. Job CI « Functions » ;
`deploy.yml` construit les Functions dans un job sans `id-token` et contrôle le manifeste avant
de les déployer. Paquets ajoutés à l'application : `url_launcher` 6.3.3, `url_launcher_android`
6.3.33, `url_launcher_ios` 6.4.2, `url_launcher_linux` 3.2.3, `url_launcher_macos` 3.2.6,
`url_launcher_platform_interface` 2.3.2, `url_launcher_web` 2.4.3, `url_launcher_windows` 3.1.6 ;
aucun paquet existant ne change. `functions/` : `firebase-admin` 14.5.0, `firebase-functions`
7.4.0, et pour les outils `typescript` 6.0.3, `eslint` 10.14.0, `@eslint/js` 10.0.1,
`typescript-eslint` 8.72.2, `@types/node` 24.19.2, `prettier` 3.9.6. `main.dart.js` passe de
4 501 692 à environ 4 547 389 octets. Réseau d'agents : contrôles P23 à P27, P10 et P14 étendus,
section « Tickets » de `CLAUDE.md`, formateur et `npm ci` de `functions/`.

### v0.1.15 — fonctionnel

Les recettes changent de format. L'éditeur gagne le type de recette, la température du
grain, la quantité et le type de la levure, le type d'un ajout et le type d'un palier. Ces
champs sont facultatifs, sans valeur choisie d'avance. Les durées en minutes sont des nombres
entiers. Un whirlpool demande sa durée d'infusion, de 1 à 600 min ; pour un ajout à l'arrêt du
feu, choisissez Ébullition et 0 min. Le formulaire d'un houblon garde une durée par moment :
revenir à un moment remet ce que vous aviez saisi. Sous la quantité d'une levure, une aide
rappelle que le coût compte un sachet par levure. La fiche, le brassin et l'écran du jour
montrent ces nouveaux champs. Les listes tiennent sur deux lignes en grande taille de texte, et
une aide longue n'est plus coupée. Les chiffres calculés ne changent pas.

Les recettes et les brassins enregistrés avant cette version sont effacés au passage, avec le
coût figé de ces brassins. Une recette ou un brassin qui ne peut pas s'afficher le dit, invite à
mettre l'application à jour et ramène à la liste.

### v0.1.15 — technique

Livraison L1 d'ADR-005 : les recettes et la copie figée des brassins passent en BeerJSON
partiel dans Firestore. Modèle : enveloppe (`format_version` 1, propriétaire, équipement, chronologie, dates) et
sous-arbre `recipe` suivant `RecipeType` du schéma BeerJSON au commit `4370892d44`, en couples
`{value, unit}` d'une seule unité par grandeur. La clé d'ingrédient n'est plus stockée.
`recipe_snapshot` prend la même forme. `HopUse.storedValue` et `HopUse.fromStored` sortent de
`brewing/`, aucune formule ne change ; les exceptions de `HopForm.fromStored` et
`FermentableKind.fromStored` nomment les chemins stockés (`hop_additions[].form`,
`fermentable_additions[].type`). Règles : `recipeFields()` et le sous-arbre `recipe` contrôlés,
dans la recette et dans sa copie figée ; `style`, `boil`, `mash` et `ingredients` sont des maps
fermées, `type` est une valeur du schéma, `mash.name` un texte borné, et une liste de `recipe`
nulle est refusée. Les éléments des listes et les valeurs de la copie de l'équipement restent
non contrôlés, risques acceptés et écrits dans `exigences-techniques.md`. La création d'un
brassin n'accepte plus que ses champs de création, et sa modification ne contrôle que les champs
changés (`isBrewUpdate`, qui remplace `isBrewShape`) : un brassin rempli après le brassage avec
5 ajustements dépassait 1 000 expressions évaluées à chaque modification, même sur `origin/main`.
Mesures sur l'émulateur : marge d'environ 70 expressions à la création d'un brassin (plus grande
recette permise), 470 à celle d'une recette ; sur le brassin du 22 novembre rempli avec
11 ajustements, plus de 900 au changement de statut ou d'embouteillage, 470 à l'écriture des
11 ajustements. Une écriture qui change d'un coup tous les groupes de champs, ajustements
compris, dépasse la limite et est refusée ; l'application n'en fait pas. Les schémas BeerJSON (MIT) sont copiés dans `schemas/`, et ajv valide les documents
écrits par l'application contre le schéma partiel. `effacement-l1/effacer.mjs` refuse une clé
JSON, un projet autre que `kassbeer` ou `demo-` avec l'émulateur, une confirmation hors terminal
en production (à lancer depuis PowerShell ou Windows Terminal), une sauvegarde dans le dépôt
hors de `import/` (`<dépôt>/..copie` compris) et une sauvegarde dans un autre arbre Git,
autre dépôt ou worktree, même ignorée par Git ; dans `import/`, le fichier de la copie doit
être ignoré (`git check-ignore`). Git y est lancé sans `GIT_DIR` ni les variables voisines,
et seul « not a git repository » vaut « hors de Git ». Il
efface aussi le coût figé de chaque brassin (`users/{owner_uid}/brew_costs/{id}`), sans le
copier ni lire son contenu (décision du 2026-11-10) : les coûts figés et le décompte de
`users/` se lisent sans champ (`fieldMask` vide), et aucun document sous `users/` n'entre
dans la copie. Il ne touche à rien d'autre sous `users/`. Un coût figé dont la suppression
échoue est écrit avec son chemin et le message d'erreur, en code 0 comme en code 4. Après la
confirmation, il refait le compte rendu : un brassin passé en `brewing` sort en code 2, un
document ou un coût figé ajouté, retiré ou modifié (`updateTime`) en code 5, rien n'étant
effacé. Un événement
dont le brassin est absent est compté, nommé, copié et effacé ; un document hors modèle (autre
sous-collection) fait refuser l'effacement avant la copie. Les risques acceptés des règles
disent l'effet d'une copie mal typée chez tous les lecteurs, et acceptent `bottles_count`
réécrit de 5 en 5.0, que l'application lit par `toInt()`. Un test des règles vérifie que le
propriétaire ne retire pas `recipe_id` d'un brassin. `PageDocument` accepte un bouton propre
à l'état illisible. La ligne « Brassin illisible » de la liste a son propre `Material` : au
retour d'une fiche, la transition de page levait une assertion de `ListTile` en mode debug. `CLAUDE.md` gagne la règle « Recettes
en BeerJSON partiel », le contrôle P21, les nouveaux dossiers de « Structure » et une exception
ponctuelle à « Une écriture de masse » pour l'effacement ; `guide-reseau.md` les décrit.

Paquets — `rules-tests/package-lock.json` : `ajv` 8.20.0 devient une dépendance directe de
développement, version déjà présente par `firebase-tools`, aucune autre version ne change.
`effacement-l1/package-lock.json`, nouveau : `firebase-admin` 14.5.0 et 171 paquets transitifs,
dont `@google-cloud/firestore` 9.4.0, pour l'outil local seulement. `app/pubspec.lock` ne change
pas.

### v0.1.14 — fonctionnel

Le menu du compte gagne une entrée « Nouveautés ». Elle ouvre un écran qui présente les
dernières versions qui changent ce que vous voyez, la plus récente en tête, avec leur date.
La version installée sur l'appareil y porte l'étiquette « Installée ». Le texte se
sélectionne pour être copié. L'écran marche sans réseau : les nouveautés sont livrées avec
l'application.

### v0.1.14 — technique

`scripts/changelog-recent.mjs` extrait du `CHANGELOG.md` les six dernières versions qui ont une
entrée « fonctionnel », en texte simple découpé en paragraphes, et écrit
`app/assets/changelog_recent.json`. La CI et `deploy.yml` régénèrent ce fichier avant chaque build
web et APK ; la copie versionnée sert aux builds locaux. Le script a son test, rejoué par le job
« Version et outillage ». L'application valide la forme du fichier et affiche la panne, journalisée,
s'il est mal formé. Route `/nouveautes` hors de la coquille. Aucune dépendance ajoutée :
`app/pubspec.lock` ne change pas.

ADR-006 accepté : les tickets des membres seront publiés en Issues GitHub par des Cloud Functions
sans point d'accès HTTP (Node 24), en deux lots T1 et T2 après les lots L2 à L4 d'ADR-005. Aucune
implémentation dans cette version. ADR-001 et la section « Le projet » de `CLAUDE.md` le citent.

`CLAUDE.md` (« Version ») ajoute une règle d'écriture : une entrée « fonctionnel » s'adresse au
brasseur, sans chemin de fichier ni numéro d'incrément, puisqu'elle s'affiche dans « Nouveautés ».

### v0.1.13 — fonctionnel

Les prix et le coût arrivent (incrément v0.5). Chaque brasseur saisit ses prix d'achat et ses
frais (eau, électricité, embouteillage) dans « Mes prix », ouvert depuis le menu du compte. La
fiche d'une recette affiche son coût avec les prix du lecteur : total, par litre et bouteille de
33 cl. Un prix manquant n'affiche aucun montant : la liste des manquants permet de saisir chaque
prix sans quitter la recette. Sur la fiche d'un brassin, son propriétaire voit l'estimation,
puis le coût figé automatiquement au premier embouteillage si tous les prix sont connus, par
bouteille réelle. Sinon, « Figer le coût » rattrape le figeage. « Recalculer avec mes prix
actuels » remplace un coût figé après confirmation. Les prix et les coûts ne sont visibles que
de leur propriétaire.

### v0.1.13 — technique

`brewing/` : prix unitaire d'un achat, regroupement des lignes de même clé, levure en sachets,
frais par brassin et par bouteille, coût par bouteille réelle et par litre, `natureOfKey`, avec
leurs cas dans `cost.json` ; les coûts des fiches Ale blonde 140724 et Bière blonde 11-2-24 sont
retrouvés. Aucune erreur de `cost.dart` ne porte plus de valeur, et l'application remplace une
erreur de calcul de coût par `CalculCoutRefuse` (P13). Règles : `users/{uid}/prices`, `fees` et
`brew_costs` contrôlés en forme et en bornes, `freeze_kind` (`initial` en création seule,
`recalculation` en mise à jour seule), plus d'écriture libre sous `users/{uid}/`, hors
`stock/`. Nouvelle feature `costs` ; le coût figé part dans une écriture séparée de
l'embouteillage, sans transaction ; la suppression d'un brassin efface son coût figé dans le
même lot. Aucun paquet ne change. `main.dart.js` passe de 4 336 026 à 4 439 270 octets.

## 2026-11-08

### v0.1.12 — technique

Cadrage du socle données, sans code. ADR-005 décide le passage des recettes en BeerJSON partiel
dans Firestore, l'import et l'export BeerJSON et BeerXML en Dart, sans Cloud Function, cinq
référentiels d'ingrédients et de styles, et 415 recettes publiques DIY Dog. `DATA_SOURCES.md`
consigne les versions figées, les licences et la correspondance de chaque source, relevées sur les
fichiers. Les règles de `CLAUDE.md` et le code changent aux livraisons suivantes.

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

