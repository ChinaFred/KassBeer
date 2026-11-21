# Changelog

Une entrée par version, la plus récente en tête, sous la date du jour. Titre
`### vX.Y.Z — fonctionnel` (ce que voit l'utilisateur) ou `— technique` (architecture,
données, outillage), ou les deux.

## 2026-11-21

### v0.1.86 — fonctionnel

La levure Lallemand « Prise de Mousse Wine » n'apparaît plus à côté de « Lalvin EC-1118 » dans la
Bibliothèque : c'est la même levure, sous une autre référence. Sa fiche est celle de « Lalvin
EC-1118 », qui garde « Prise de Mousse Wine » comme autre nom. Le changement arrive dans la
Bibliothèque quand l'administrateur relance l'ingestion.

### v0.1.86 — technique

`kCorrectionsCultures` (`exchange/lib/src/ingestion/fusions.dart`) gagne une ligne
`ReferenceCulture` (demande de l'utilisateur du 2026-11-21) : Lallemand `LALVIN-EC-1118` (fichier 004, « Prise de Mousse Wine ») →
`EC-1118`. L'entrée rejoint la souche EC-1118 du fichier 005, prioritaire, qui garde
l'identifiant `culture-lallemand-ec1118-lalvin-ec-1118` et ses valeurs. Préparation rejouée sur
les sources du 2026-11-08 : 960 documents `beer_cultures` au lieu de 961, 1 identifiant sort,
aucun n'entre, 1 document change. Doublons d'un même producteur inchangés (4, laissés listés).
`ecrire.mjs --supprimer-absents beer_cultures` retire l'ancien identifiant. Test : la ligne
rejouée dans « chaque ligne de kCorrectionsCultures » de `fusions_test.dart`. `DATA_SOURCES.md`
et `exigences-techniques.md` à jour.

### v0.1.85 — fonctionnel

Avant de lancer une analyse, un développement ou une livraison d'un ticket, l'administrateur
peut ouvrir la page d'usage de claude.ai : un lien « Usage Claude (5 h et semaine) : voir sur
claude.ai » figure dans la boîte de lancement et en tête de la liste des tickets. Il montre
la part restante de l'abonnement Claude pour la fenêtre de 5 heures et pour la semaine.
L'application n'affiche aucun chiffre : Anthropic ne publie pas ces valeurs. Demandé par le
ticket #96.

### v0.1.85 — technique

Option A de l'analyse du ticket #96 : `LienUsageClaude`
(`app/lib/features/tickets/presentation/lien_usage_claude.dart`) ouvre
`https://claude.ai/settings/usage` par `ouvrirLienProvider`, après `lienSessionOuvrable`
(`Uri.tryParse`, `https`, hôte `claude.ai`, sans identifiants ni port). Un échec passe par `reportError`
(`tickets.open_claude_usage`), sans adresse. Le lien est placé sous la ligne du quota dans
`BoiteLancement` et sous les messages de `BandeauTicketsAdmin` (`lienUsage`, faux pour la
fiche seule sur écran étroit, qui garderait sinon sa barre de décision sous le seuil de
480 px). Aucun serveur ni règle touché ; l'option B (lancements comptés sur 5 h et 7 jours)
n'est pas faite. Tests : `tickets_lancements_test.dart`. Demandé par le ticket #96.

### v0.1.84 — fonctionnel

Sur téléphone, la Bibliothèque montre ses six rubriques sans faire glisser la ligne : les
Levures, les Divers et les Recettes publiques ne sont plus cachées hors de l'écran. Chaque
rubrique a maintenant une icône à côté de son nom, à toutes les tailles d'écran ; la rubrique
ouverte montre une coche à la place de son icône. Sur téléphone, ou avec un texte agrandi, les
noms sont raccourcis (« Malts », « Recettes ») et les boutons « Échelle des couleurs » et
« Sources des données » passent en icônes sur une ligne au-dessus des rubriques.
Demandé par le ticket #97.

### v0.1.84 — technique

`SegmentBibliotheque` (`library_providers.dart`) reçoit `labelCourt` et `icone`. `_EnTete`
(`library_screen.dart`) place les puces dans un `Wrap` à toutes les largeurs. Sous 600 px, ou
à partir de `kGrandTexteMinScale` (130 %), les deux accès sont des icônes sur une ligne
au-dessus des puces, qui affichent leur nom court : à 600 px et 200 %, le rail laisse 423 px,
trop peu pour « Recettes publiques » et le bouton « Échelle des couleurs » en texte. La puce
ouverte n'a pas d'avatar : la coche de `ChoiceChip` remplace l'icône au lieu d'être peinte
dessus. Le `ShaderMask`, le défilement horizontal et la constante `_fondu` sortent. Le nom
complet reste le `semanticsLabel` de la puce et le titre de la fiche. Tests : à 320 px, texte
à 100 %, 130 % et 200 %, les six puces et les deux accès tiennent dans la largeur, sans
débordement, avec une cible de 48 px ; à 600 px, texte à 130 % et 200 %, les noms courts sont
entiers. Demandé par le ticket #97.

### v0.1.83 — fonctionnel

L'éditeur de recette reçoit un assistant. Le bouton « Assistant » ouvre une conversation avec
une intelligence artificielle, qui analyse la recette en cours ou propose des améliorations.
Les chiffres de la recette restent ceux du calcul de Kass'Beer. L'assistant est réservé à
l'administrateur pour commencer ; il pourra ensuite l'ouvrir à tous les membres. Chaque membre
dispose d'un nombre de tours par jour, et le menu du compte affiche ce que l'IA a coûté dans le
mois. Une conversation trop longue peut être résumée pour continuer. Dans Admin, deux écrans
nouveaux règlent l'IA (modèle, tarifs, plafonds, ouverture aux membres) et suivent ses coûts
par personne. L'assistant ne marche qu'une fois ses réglages enregistrés.

### v0.1.83 — technique

Lot A1 d'ADR-015 et ADR-016. Serveur : socle `functions/src/ai/` (client Claude par `fetch`,
postes, politique et grille dans `ai_config/`, réservation des tours en transaction dans
`ai_quotas/`, coût et comptes du mois dans `ai_usage/` avec `member_email` et `expires_at`),
callables `saveAiSettings` et `recipeAssistantTurn` (`functions/src/assistant/`), secret
`ANTHROPIC_API_KEY`, règles Firestore et leurs tests pour les cinq profils, TTL de
`ai_usage.expires_at`, fixture `test-fixtures/ai_cost_centers.json`. `ci.yml` et `deploy.yml`
ajoutent les deux callables à la liste fermée et réservent `ANTHROPIC_API_KEY` à
`recipeAssistantTurn`. Client : feature `ai/`, écrans `/admin/moteur-ia` et `/admin/couts-ia`,
panneau Assistant de l'éditeur (feuille sous 840 px, commutateur de 840 à 1 279 px, trois
colonnes au-delà), ligne « IA ce mois », `CorpsAnalyse` déplacé en `CorpsMarkdown`
(`core/presentation/corps_markdown.dart`), garde de départ des pages de la coquille
(`garde_depart.dart`). Aucune dépendance ajoutée ; seul le commentaire de `flutter_markdown_plus`
change dans `pubspec.yaml`. Taille de `main.dart.js` : 5 801 939 octets avant, 5 892 104 après
(+90 165, +1,6 %). ADR-015 note les choix de la livraison ; `CLAUDE.md` passe le lot A1 en livré.
Avant la mise en service : créer `ANTHROPIC_API_KEY` dans Secret Manager, donner à
`github-deploy` l'accès à ce secret, puis enregistrer la grille et la politique dans Admin ›
Moteur d'IA.

### v0.1.82 — fonctionnel

La Bibliothèque ne montre plus en double onze noms de levures que l'ancienne base donnait à
deux fiches d'un même fabricant. Une levure écrite sous deux références n'a plus qu'une fiche.
Les levures Lalvin, SafSpirit et Fermoale, qui portaient toutes le même nom, s'appellent
maintenant par leur référence : « Lalvin 71B », « SafSpirit HG-1 », « Fermoale AY3 ». Trois
levures Wyeast ne portent plus le nom d'une autre. Le changement arrive dans la Bibliothèque
quand l'administrateur relance l'ingestion.

### v0.1.82 — technique

`kCorrectionsCultures` (`exchange/lib/src/ingestion/fusions.dart`), appliquées par
`Referentiel.fusionner` aux seules entrées de Brewtarget (P56, décisions de l'utilisateur du
2026-11-21) : `ReferenceCulture` (5 lignes, une souche sous deux références), `GammeCulture` (3
lignes, nom `<gamme> <référence>` construit par Kass'Beer ; l'entrée AEB « Fermoale » sans
référence garde son nom), `AliasEcarteCulture` (3 lignes Wyeast). Ligne sans effet, entrée
corrigée deux fois ou alias absent : `StateError`. `EntreeBrute.corrigee`. `rapport.json` gagne
`doublons_meme_producteur`. Préparation rejouée sur les sources du 2026-11-08 : 961 documents
`beer_cultures` au lieu de 966, 12 identifiants sortent, 7 entrent, 8 documents changent ; noms
d'un même producteur en double : 4 au lieu de 15, laissés en attente (aucune fiche ne départage
les souches). `ecrire.mjs --supprimer-absents beer_cultures` (v0.1.80, PR #92) retire les 12
anciens, sous le plafond de 30. Tests : `fusions_test.dart`, groupe « corrections des cultures de Brewtarget »
(chaque sorte de ligne et ses refus sur des fixtures inventées, chaque ligne du projet sur ses
noms et références). `DATA_SOURCES.md` et `exigences-techniques.md` à jour.

### v0.1.81 — fonctionnel

La Bibliothèque ne montre plus en double 26 levures de la gamme Private Collection de Wyeast :
27 fiches en trop disparaissent. L'ancienne base les écrivait sous deux références : chaque
levure n'a plus qu'une fiche, celle du fabricant. Une recette importée qui nomme la référence avec « -PC » retrouve aussi sa levure. Le
changement arrive dans la Bibliothèque quand l'administrateur relance l'ingestion.

### v0.1.81 — technique

`cleProduit` (`exchange/lib/src/noms.dart`) retire `wy` et `pc` d'une référence Wyeast :
`2001`, `WY2001`, `2001-PC` et `WY2001-PC` donnent `2001` (décision de l'utilisateur du
2026-11-21, « Tolérer puis nettoyer », point 1). La clé sert à l'ingestion et à la résolution
d'un import (`resolution_import.dart`). Préparation rejouée sur les sources du 2026-11-08 :
966 documents `beer_cultures` au lieu de 993 ; 27 documents `-PC` rejoignent leur souche, 29
identifiants sortent, 2 entrent (identifiant tiré d'une autre entrée par `ordreIdentifiant`), 24
documents changent. Noms qui désignent deux documents d'un même producteur : 15 au lieu de 39
(P56, `DATA_SOURCES.md`). Après l'ingestion, `ecrire.mjs --supprimer-absents beer_cultures`
(v0.1.80, PR #92) retire les 29 anciens identifiants, sous le plafond de 30. Tests : `ingestion_test.dart` (quatre
graphies Wyeast, `pc` laissé aux autres producteurs), `fusions_test.dart` (fiche et entrées
`-PC` inventées en un seul document).

### v0.1.80 — technique

`ingest/ecrire.mjs --supprimer-absents` accepte aussi `beer_cultures` (ADR-014, amendement du
2026-11-15, décision de l'utilisateur). Des fiches de fabricants renommées laissaient
d'anciens documents `culture-…` en ligne : les douze variantes Omega en « + » s'écrivent
« Plus » (« Kolsch II+ » devient « Kolsch II Plus »), et des entrées Wyeast changent aussi. Les garde-fous sont ceux de
`beer_hops` : simulation, liste avant confirmation, 30 suppressions au plus, refus sous 90 %
des documents en ligne, saisie du nombre, motif `culture-…`, une collection par lancement.
`COLLECTIONS_SUPPRIMABLES` (`ingest/lib/options.mjs`) gagne `beer_cultures` ; tests unitaires
(acceptation, plafond, seuil, `beer_styles` et `beer_miscs` refusées) et test sous
l'émulateur (simulation puis suppression d'un ancien identifiant).
`CLAUDE.md` : P19 et « Commandes utiles » nomment `beer_cultures` parmi les collections
permises ; `guide-reseau.md` à jour.

### v0.1.79 — fonctionnel

La Bibliothèque reprend les fiches de 98 cultures d'Escarpment Labs : levures d'ale, de lager
et de bière de blé, kveiks, Brettanomyces, bactéries et assemblages pour bières acides. Type,
atténuation, plage de température et floculation viennent des fiches du fabricant. Ces valeurs
remplacent celles de l'ancienne base pour 50 cultures déjà connues, et 48 cultures
apparaissent. Sept fiches portent un autre nom que l'ancienne base pour la même souche
(« Classic Wit » pour « Classic Witbier », « Chaudron Sûr » pour « Lactobacillus Blend »…) :
elles rejoignent la culture déjà connue, qui prend le nom de la fiche et garde l'ancien nom
comme autre nom. L'écran « Sources des données » nomme Escarpment Labs. Les cultures arrivent
dans la Bibliothèque quand l'administrateur relance l'ingestion.

### v0.1.79 — technique

`exchange/donnees/fabricants/cultures.json` : 98 cultures Escarpment Labs relevées le
2026-11-15 sur `escarpmentlabs.com`, règles dans l'en-tête ; levures Lallemand revendues non
reprises. `kDatesReleveFabricants` reçoit `escarpment-labs`. Escarpment ne publie presque
aucune référence : une table de fusion des cultures (`kFusionsCultures`, `fusions.dart`,
décision de l'utilisateur du 2026-11-15) rattache sept fiches au document Brewtarget de la même
souche sous un autre nom. L'identifiant Brewtarget reste, la fiche donne valeurs et nom, le nom
Brewtarget passe en alias ; une ligne sans fiche ou sans entrée Brewtarget, une entrée désignée
deux fois, deux lignes de même identifiant ou une cible Brewtarget d'un autre identifiant (une
souche à référence) lèvent `StateError`. `Referentiel.fusionner` et
`preparer` reçoivent `fusionsCultures` ; `rapport.json` gagne `table_de_fusion_cultures`.
`kFusions` inchangée. Préparation rejouée sur les sources du 2026-11-08 : 50 fiches rejoignent
un document Brewtarget (43 par le nom, 7 par la table), 48 en créent un (993 documents
`beer_cultures` au lieu de 945), aucun document retiré ni autre document changé. Six noms
désignent désormais deux documents de producteurs différents (`cream-ale-blend`,
`lactobacillus-delbrueckii`, `northwest-ale`, `framgarden-kveik`, `granvin`, `midtbust`) ;
`berliner-weisse-blend` et `french-saison`, déjà partagés, gagnent un document. Tests :
`fusions_test.dart` (fixtures inventées, un cas par ligne de la table), `fabricants_donnees_test.dart` (537 entrées, chaque ligne de la table
désigne une fiche). `DATA_SOURCES.md`, ADR-005, exigences et écran « Sources des données » à
jour. `CLAUDE.md`, P56 (décision de l'utilisateur) : pour les cultures, un nom normalisé créé
par une fiche de fabricant ou par la table de fusion ne désigne pas deux documents d'un même
producteur, les 39 doublons hérités de Brewtarget sont comptés et listés en attendant leur
fusion ; un nom porté par une fiche dont les documents en double existaient avant elle compte
comme hérité (27 des 39, liste dans `DATA_SOURCES.md`) ; un nom partagé entre deux producteurs reste
permis et compté au rapport. `guide-reseau.md` à jour. Tests de cette règle :
`fabricants_donnees_test.dart` vérifie qu'aucune fiche ne partage son nom normalisé avec une
fiche du même producteur ; `fusions_test.dart` vérifie qu'un nom porté par deux producteurs
donne deux documents listés par `nomsPartages`, et que la table de fusion ne crée aucun nom
partagé. La préparation rejouée compte 39 noms qui désignent deux documents d'un même
producteur (« Wyeast Labs » compté comme Wyeast), tous antérieurs aux fiches Escarpment :
24 doublons de la Private Collection de Wyeast, 5 souches sous deux références, 7 noms donnés à
deux souches, 3 noms de gamme ; la préparation ne les refuse pas.

## 2026-11-19

### v0.1.78 — fonctionnel

« Nouveau brassin » choisit d'office votre processus quand vous n'en avez qu'un et que vous
n'avez jamais réglé de choix par défaut : le déroulé prévu reprend vos étapes (préparation, mouture, nettoyage)
autour de la chronologie de la recette, et la journée de houblonnage à cru. Avec « Chronologie
de la recette seule », le formulaire dit ce qu'un processus ajoute et propose « Choisir un
processus », ou « Créer un processus » si vous n'en avez aucun : ce bouton ouvre « Mes
processus », où le modèle d'exemple et le plan de brassage des fiches sont prêts à copier. Une
recette sans chronologie
affiche « sans processus, le brassin n'aura aucune étape ».

Sur la fiche d'un brassin prévu sans processus, la section « Déroulé » dit « Aucun processus
choisi » au lieu de « Aucune étape. », avec le bouton « Choisir un processus » pour son
propriétaire. Demandé par le ticket #61.

### v0.1.78 — technique

`lireChoixProcessus` présélectionne le seul processus valide du lecteur quand son document de
préférence est absent (`DocumentAbsent`) ; un défaut coupé ou supprimé garde la chronologie
seule. L'éditeur écrit `default_template_id` nul quand « Proposer par défaut » est décoché à
la création alors qu'aucun choix n'existe. Aucun modèle à copier n'est appliqué seul
(P37). « Créer un processus » n'apparaît plus qu'une fois dans « Nouveau brassin »
(`ChampProcessus.onCreer` facultatif) et ouvre `AppRoutes.processes` (« Mes processus » et
ses modèles à copier) au lieu de `AppRoutes.newProcess`, dans le formulaire comme dans la
feuille de la fiche ; dans cette feuille, sans processus, « Gérer mes processus » est retiré,
car « Créer un processus » ouvre le même écran ; la feuille de la fiche se titre « Choisir un
processus » sur un brassin prévu sans processus. `AideChronologieSeule`,
`BoutonProcessus` et `choisirProcessus` (`choix_processus.dart`) sous « Chronologie de la
recette seule » ; nouvelle fenêtre `/recettes/:id/fenetre/choix-processus` (et `/recettes/importer/:id/…`) dans
`kTicketElements`. `sansProcessusPrevu` (`section_deroule.dart`) remplace « Changer de
processus » par « Choisir un processus » sur un brassin prévu sans `process`, et
`_chronologie` n'y affiche plus « Aucune étape. ». Aucun calcul, aucune règle, aucun modèle de
données ne change ; l'écran du jour et les journées ne sont pas touchés (P2). Le préremplissage
de la voie « Chronologie de la recette seule » n'est pas fait (point 5 de l'analyse). Tests de
widgets ajoutés dans `deroule_d3_test.dart` et `process_screens_test.dart`. Demandé par le
ticket #61.

## 2026-11-15

### v0.1.77 — technique

ADR-015 (assistant de recette) et ADR-016 (socle IA) sont acceptés. L'utilisateur a tranché
quinze questions, une par une. La règle « Aucune IA dans l'application » d'ADR-001 est
retirée : l'IA passe par le serveur seul, avec Claude comme seul fournisseur. Le socle
`functions/src/ai/` appelle l'API par `fetch`. Admin › Moteur d'IA règle par poste le
modèle, l'effort, les plafonds (20 tours par membre et par jour, 60 pour le fondateur, borne
de 100) et l'ouverture aux membres. Admin › Coûts de l'IA suit les coûts par personne et par
poste, d'après une grille tarifaire dans Firestore. L'assistant arrive en deux lots :
analyse en texte (A1), puis propositions appliquées au brouillon (A2). `CLAUDE.md` reçoit
les contrôles P57 à P61, et P14, P25, P35 et P54 sont modifiés. Deux lignes s'ajoutent à
« Logique dupliquée », et le poste `recipe_assistant_turn` entre dans « Coûts variables ».
« Recettes en BeerJSON partiel » reçoit une exception à « aucune valeur inventée » : au lot A2,
une valeur technique proposée par l'assistant, faute de Bibliothèque, est acceptée et marquée
(`ai_proposed`). ADR-005 et ADR-008 reçoivent leur note de renvoi.
La relecture de sécurité ajoute des bornes à la requête de l'assistant (liste blanche,
120 000 caractères au total), garde le tour sur un délai ou un 5xx, et fixe `concurrency: 4`.
Aucun code n'est écrit à ce stade.

Dans la même version, `CLAUDE.md` (section « Ton ») ajoute « Poser ses questions une par
une ». Quand plusieurs décisions reviennent à l'utilisateur, la session pose une question par
message, avec son contexte, ses options et sa recommandation. L'utilisateur l'a demandé après
l'avis de l'architecte sur l'assistant de recette, qui listait treize questions d'un coup.
`documentation/guide-reseau.md` décrit le changement.

Après l'acceptation, trois amendements s'ajoutent. ADR-015 inscrit la décision de garder
`tickets-functions` comme compte d'exécution de l'assistant (commit 8657e43). ADR-015 et ADR-016
inscrivent les décisions du cadrage du lot A1 (commit 6b51e1f) : `member_email` dans `ai_usage`,
ligne « IA ce mois » selon le membre, refus d'une grille qui retire un modèle utilisé, et
« Résumer et continuer ». Ce dernier ajoute les clés `mode` et `summary` à la requête de
l'assistant, avec leurs bornes ; P57, P58, P59 et P60 sont complétés en conséquence.

Les relectures de `relecteur-regles` et de `securite` complètent ces amendements. En mode
résumé, les bornes par champ et la forme de l'historique restent, `message` est refusé et
`history` compte au moins 2 messages. Le prompt nomme huit blocs de données, dont `RESUME`,
jamais suivis comme consignes. La grille et la politique se relisent l'une dans la
transaction de l'autre, et une grille qui retire un modèle ou un effort utilisé est refusée.
`ai_usage/` est gardé 13 mois, par `expires_at` et une règle TTL (décision de l'utilisateur).
La procédure d'effacement RGPD couvre `ai_usage/` et `ai_quotas/`. La dépense par jour est
bornée à environ 31 $, poste ouvert à tous, sous la limite de 20 $ de la Console. ADR-015
reçoit les décisions sur les écrans du lot A1 : icône « Assistant » dans la barre du haut,
commutateur « Calculs / Assistant » de 840 à 1 279 px, champ « Efforts acceptés ».

### v0.1.76 — fonctionnel

Les variantes « + » des levures Omega s'écrivent maintenant « Plus » : « Kolsch II Plus »,
« Bayern Lager Plus », « Point Loma Plus »… Elles ne se confondent plus avec la levure
d'origine. Une recette importée qui nomme « Kolsch II » retrouve à nouveau sa levure. Le
changement arrive dans la Bibliothèque quand l'administrateur relance l'ingestion.

### v0.1.76 — technique

`exchange/donnees/fabricants/cultures.json` : les douze noms Omega en « + » s'écrivent « Plus »
(décision de l'utilisateur du 2026-11-15). Préparation rejouée : 945 documents, cinq noms
normalisés (`kolsch-ii`, `german-lager-i`, `bayern-lager`, `point-loma`, `extra-special`) ne
désignent plus deux documents. Les identifiants de ces douze documents suivent le nom
(`culture-omega-yeast-oyl435-kolsch-ii` devient `…-kolsch-ii-plus`) ; `ingest/ecrire.mjs` ne
supprime rien dans `beer_cultures` : une ingestion faite depuis la v0.1.73 laisse les douze
anciens documents en ligne. `fabricants_donnees_test.dart` vérifie qu'aucun nom Omega ne
contient « + » et que leurs noms normalisés sont distincts. `DATA_SOURCES.md` à jour.

### v0.1.75 — fonctionnel

La Bibliothèque reprend les fiches de 77 cultures de Wyeast : levures d'ale, de lager et de
bière de blé, Brettanomyces, bactéries et assemblages pour bières acides. Type, atténuation,
plage de température et floculation viennent des fiches du fabricant. Ces valeurs remplacent
celles de l'ancienne base pour 74 cultures déjà connues, et 3 cultures apparaissent. Les
cultures de vin, de cidre, d'hydromel et de saké ne sont pas reprises. L'écran « Sources des
données » nomme Wyeast. Les cultures arrivent dans la Bibliothèque quand l'administrateur
relance l'ingestion.

### v0.1.75 — technique

`exchange/donnees/fabricants/cultures.json` : 77 cultures Wyeast relevées le 2026-11-15 sur
`wyeastlab.com` (Crawl-delay de 10 s), règles dans l'en-tête : `type` d'après « Species »,
référence sans le suffixe `-PC`, températures en °F, floculation `Low - High` absente ; série
4000 (vin, cidre, hydromel, saké, distillerie) non reprise. `kDatesReleveFabricants` reçoit
`wyeast`. Préparation rejouée sur les sources du 2026-11-08 : 74 fiches rejoignent un document
Brewtarget, 3 en créent un (945 documents `beer_cultures`), aucun autre document changé. Les
doublons Brewtarget de la Private Collection (`WY2001-PC` et `2001`) restent, et six noms
deviennent ambigus ; `DATA_SOURCES.md` décrit la correction possible par `cleProduit`.
`fabricants_donnees_test.dart` : 439 entrées, types et références Wyeast. `DATA_SOURCES.md`,
ADR-005, exigences et écran « Sources des données » à jour.

### v0.1.74 — fonctionnel

La Bibliothèque reprend les fiches de 162 cultures de White Labs et de sa gamme The Yeast Bay :
levures d'ale et de lager, levures de bière de blé, kveiks, Brettanomyces, bactéries et
assemblages pour bières acides. Type, atténuation, plage de température et floculation
viennent des fiches du fabricant. Ces valeurs remplacent celles de l'ancienne base pour les
123 cultures déjà connues. 39 cultures absentes jusqu'ici apparaissent. Les levures de vin, de
cidre et de distillerie ne sont pas reprises. L'écran « Sources des données » nomme White Labs
et The Yeast Bay. Les cultures arrivent dans la Bibliothèque quand l'administrateur relance
l'ingestion.

### v0.1.74 — technique

`exchange/donnees/fabricants/cultures.json` : 162 cultures WLP relevées le 2026-11-15 sur
`www.whitelabs.com` (115 White Labs, 47 The Yeast Bay d'après le titre de la fiche), règles
dans l'en-tête ; non reprises : WLP700 à WLP799, WLP616, distillerie, kombucha, bactéries
acétiques et malolactiques, WLP686, WLP692, produits revendus. `kDatesReleveFabricants` reçoit
`white-labs` et `the-yeast-bay`. Préparation rejouée sur les sources du 2026-11-08 : 123 fiches
rejoignent leur document Brewtarget, 39 en créent un (942 documents `beer_cultures`), aucun
autre document changé, aucun nom rendu ambigu ; WLP4042 et WLP4044 restent en double (White
Labs sur la fiche, The Yeast Bay chez Brewtarget). `fabricants_donnees_test.dart` : 362
entrées, types et champs absents de White Labs. `DATA_SOURCES.md`, ADR-005, exigences et
écran « Sources des données » à jour. `CLAUDE.md`, décisions de l'utilisateur : P15 accepte le
nom commercial d'une souche publié par son fabricant (WLP520, WLP4045, WLP4046), et
« Structure » décrit `exchange/donnees/fabricants/` sans liste de fabricants ;
`guide-reseau.md` à jour.

### v0.1.73 — fonctionnel

La Bibliothèque reprend les fiches de 104 cultures d'Omega Yeast : levures liquides, levures
sèches (Pinnacle, Dried Lutra), Brettanomyces, kveiks et deux bactéries qui acidifient la
bière. Type, atténuation, plage
de température et floculation viennent des fiches du fabricant. Ces valeurs remplacent celles
de l'ancienne base pour les 75 cultures déjà connues. 29 cultures absentes jusqu'ici
apparaissent, dont les variantes « + » et les levures sèches. L'écran « Sources des
données » nomme Omega Yeast et la date du relevé. Les cultures arrivent dans la Bibliothèque
quand l'administrateur relance l'ingestion.

### v0.1.73 — technique

`exchange/donnees/fabricants/cultures.json` : 104 cultures Omega Yeast relevées le 2026-11-15
sur `omegayeast.com`, règles dans l'en-tête : référence OYL du titre ou de la page, cinq
Pinnacle sans référence (identifiant tiré du nom), `type` d'après « Strain Type » puis kveik,
blé, `mixed-culture` (C2C), `lacto`, `pedio`, `other` (*Lachancea*), températures en °F.
`kDatesReleveFabricants` reçoit `omega-yeast`. Préparation rejouée sur les sources du
2026-11-08 : 75 fiches rejoignent leur document Brewtarget, 29 en créent un (903 documents
`beer_cultures`), aucun autre document changé. Les variantes « + » rendent ambigus cinq noms
de plus (`kolsch-ii`, `german-lager-i`, `bayern-lager`, `point-loma`, `extra-special`),
résolus par la souche. `fabricants_donnees_test.dart` : 200 entrées, types et champs absents
d'Omega. `DATA_SOURCES.md`, ADR-005, exigences et écran « Sources des données » à jour.

### v0.1.72 — fonctionnel

Vous pouvez choisir votre instrument de mesure de la densité : densimètre flottant étalonné à
20 °C ou à 15,6 °C, réfractomètre, densimètre électronique, ou autre instrument sans
correction. Le choix se fait par la ligne « Densimètre » de « Préparer le brassage » et de
« Préparer la journée », ou depuis le formulaire d'une densité. Avec un densimètre flottant,
vous saisissez aussi la température de l'échantillon : l'application propose la densité
corrigée (1050,0 lue à 68 °C donne 1070,7), approchée au-delà de 40 °C, impossible au-delà de
75 °C. Avec un réfractomètre, vous saisissez des °Brix et le facteur de votre appareil ; après
le début de la fermentation, la lecture est corrigée de l'alcool à partir de la densité
initiale. La case « Corriger » permet de garder la lecture telle quelle. La lecture d'origine
est toujours gardée, et la valeur retenue sert partout : relevé, courbes, « Prévu et mesuré »,
degré et rendement. Les mesures déjà enregistrées ne changent pas. Installez cette mise à jour
avant d'utiliser le réfractomètre : une ancienne version de l'application ne peut pas afficher
« Prévu et mesuré » d'un brassin mesuré au réfractomètre.

### v0.1.72 — technique

Module `brewing/lib/src/gravity_instruments.dart` : `InstrumentDensite` (liste fermée),
`masseVolumiqueEau` (Kell 1975), `corrigerDensimetre`, `plageCorrection` (0–40 °C, 40–75 °C
approchée, impossible au-delà), `brixCorrige` (°Brix divisé par le facteur, converti par la formule de
`platoToSg`, partagée sans bornes par `platoVersSgSansBornes`, non exportée), `densiteTerrill` (Terrill 2011, cubique) et
`densiteRetenue`, seule lecture d'une densité mesurée ; cas d'abord dans
`brewing/test/fixtures/hydrometer.json` et `refractometer.json`. Événements : champs
`gravity_instrument`, `brix`, `sample_temperature`, `refractometer_factor`, `correct` ; la
lecture brute est stockée, `value` reste la densité lue en SG et est nulle pour un
réfractomètre. `densiteDe` (`app/lib/features/brews/domain/densites.dart`) remplace la lecture
de `value` dans `MesuresRetenues`, `relevesDe`, la chronologie, les deux courbes et
« Prévu et mesuré ». Préférence `users/{uid}/preferences/measurement` (dépôt
`PreferenceMesureRepository`, écriture simple sans transaction). Saisie commune `BlocDensite`
(`saisie_densite.dart`) dans les quatre formulaires de densité. `firestore.rules` : `densityOk`,
correction de l'instrument permise, préférence en liste blanche ; tests
`rules-tests/test/gravity_instruments.test.mjs` ; budget mesuré après la fusion avec la v0.1.69 : environ 560 expressions de marge (14
`pad10()`) sur la correction d'un flottant à heure estimée en réfractomètre. Quatre cas
« autorisé » ajoutés à la suite « budget des règles » de `recipe_format.test.mjs`, sur le
brassin du 22 novembre : création d'une lecture au réfractomètre en fermentation, correction
d'un flottant en réfractomètre et la même correction sur une heure estimée avec l'heure changée,
ces trois cas avec une note de 2 000 caractères ; enfin embouteillage avec une densité finale
au réfractomètre dans le même lot.
`kReleveChampMinWidth` retiré (relevé en une colonne). Aucune dépendance ajoutée. Une lecture
de réfractomètre a `value` nulle : les versions 0.1.71 et antérieures lisent `event.value!` sur
une densité retenue et plantent sur « Prévu et mesuré » d'un tel brassin ; risque accepté par
l'utilisateur, couvert par la mise à jour proposée au lancement (ADR-012).

### v0.1.71 — fonctionnel

La Bibliothèque reprend les fiches de 55 levures liquides d'Imperial Yeast : type, atténuation,
plage de température et floculation, telles que le fabricant les publie. Ces valeurs remplacent
celles de l'ancienne base pour les 36 levures déjà connues. 19 levures absentes jusqu'ici
apparaissent, dont des lagers (Alpha, Kanpai, Lookr) et les Liquid Brick. L'écran « Sources
des données » nomme Imperial Yeast et la date du relevé. Les levures arrivent dans la
Bibliothèque quand l'administrateur relance l'ingestion.

### v0.1.71 — technique

`exchange/donnees/fabricants/cultures.json` : 55 cultures Imperial Yeast relevées le
2026-11-15 sur `www.imperialyeast.com` (aucun `robots.txt`), règles dans l'en-tête :
températures en °F de la fiche, converties par le lecteur ; floculation `low-medium` →
`medium low`, `medium-high` → `medium high`, `very-high` → `very high` ; `type` d'après la
catégorie (kveik pour A37, A43, A44, A46 ; `wheat` pour G01). A40, W01 et W04 (cidre, vin)
non reprises. `kDatesReleveFabricants` reçoit `imperial-yeast`. Préparation rejouée sur les
sources du 2026-11-08 : 36 fiches rejoignent leur document Brewtarget, 19 en créent un
(874 documents `beer_cultures`), aucun autre document changé. `fabricants_donnees_test.dart` :
96 entrées, conversion des °F et floculation d'Imperial. `DATA_SOURCES.md`, ADR-005,
`exigences-techniques.md`, `exigences-fonctionnelles.md` et l'écran « Sources des données »
à jour.

### v0.1.70 — fonctionnel

La Bibliothèque reprend les fiches des 16 levures de bière sèches de Mangrove Jack's : type,
atténuation, plage de température et floculation, telles que le fabricant les publie. Ces
valeurs remplacent celles de l'ancienne base pour les mêmes levures. La M24 Versa Lager, absente
jusqu'ici, apparaît. L'écran « Sources des données » nomme Mangrove Jack's et la date du relevé.
Les levures arrivent dans la Bibliothèque quand l'administrateur relance l'ingestion.

### v0.1.70 — technique

`exchange/donnees/fabricants/cultures.json` : 16 cultures Mangrove Jack's relevées le
2026-11-15 sur `mangrovejacks.com` (collection « Beer Yeasts »), avec leurs règles dans
l'en-tête : `type` sans espèce sur la fiche (haute → `ale`, basse → `lager`, bière de blé →
`wheat`, M12 → `kveik`), floculation reprise, M76 sans atténuation, °C gardés quand les °F de
M20 et M44 ne correspondent pas. Chaque fabricant a sa date de relevé :
`kDatesReleveFabricants` (`sources.dart`) remplace `kDateReleveFabricants`, `provenance[]`
prend la date du producteur de la fiche, une fiche d'un producteur sans date est refusée, et la
version de la source `fabricants` au rapport est le relevé le plus récent. Les 25 fiches
Fermentis gardent `2026-11-14`. Préparation rejouée sur les sources du 2026-11-08 : 15 fiches
rejoignent leur document Brewtarget, M24 crée `culture-mangrove-jack-s-m24-versa-lager`
(855 documents `beer_cultures`), aucun autre document changé. `fabricants_donnees_test.dart` :
41 entrées, dates par producteur, floculation ; `ingestion_test.dart` : version au rapport et
refus d'un producteur sans date. `DATA_SOURCES.md`, `exigences-techniques.md`,
`exigences-fonctionnelles.md` et l'écran « Sources des données » à jour.

### v0.1.69 — fonctionnel

Les heures des brassins importés des fiches Excel se lisent mieux. Une étape notée sans heure
sur la fiche s'affiche « vers 13:02 · heure estimée », et une étape absente de la fiche
s'affiche « Non notée » à son heure prévue, au lieu de « Non faite ». Une heure estimée ne
compte dans aucune durée réelle. Chaque étape d'un brassin, importé ou non, montre aussi
son écart de début : « Début : 25 min de retard » ou « Début : 5 min d'avance », sur la fiche
du brassin comme sur l'écran du jour. Une étape sans « Terminer » finit au début de l'étape
suivante. La durée totale dit quand une étape n'a pas d'heure notée. Les relevés importés sans
heure portent « heure non notée », la densité finale datée de 28 jours après le brassage
« date estimée ». Dans Admin › Import, une fiche modifiée depuis son import peut être
remplacée par la case « Remplacer ce brassin » ; un remplacement coupé se termine au prochain
import.

### v0.1.69 — technique

`brewing/` : `theoreticalStarts` (heure théorique d'une étape, ancrée sur le dernier début
noté ou l'heure de début prévue), `StepEvent.estimated` et `StepRecord.startEstimated`
(début estimé, sans réel ni écart) ; `actualDurations(plannedStart:)` rend la fin retenue
(`end` : fin enregistrée, sinon début noté de l'étape suivante), l'écart de début au plan
d'origine (`startDeltaMinutes`), l'heure théorique (`theoreticalStart`), la nature
`ActualStepKind.estimated` et les natures de journée `partial`, `startNotNoted`,
`endNotNoted` (`stepsWithoutTime` remplace `stepsWithoutEnd`, `ActualDayKind.missingEnd`
retiré). `fixtures/process.json` : 4 cas ajoutés, écarts de début, heures théoriques et fins
sur les cas existants ; les cas « commencée sans fin » changent (fin au début noté suivant).
`exchange/` : format `kassbeer_fiches` v2 (un fichier v1 est refusé) : `time_source`
`fiche`, `estimee` (heure calculée par le lecteur avec `brewing/`), `midi`, `estimee_j28` ;
`ligne_precedente` et `debut_brassage` retirés ; codes de refus `debutEnDouble`,
`heuresHorsOrdre`, `heureEnTrop` ; `verifier_fiches.dart` compte heures notées et estimées.
Firestore : `brews/{id}/events/{eventId}.time_estimated` et `date_estimated` (booléens
vrais seulement ; retirés seulement avec `measured_at` changé, `estimatedOk` et
`estimationRetireeOk`), tests des cinq profils dans `events.test.mjs` et
`import_fiches.test.mjs` (remplacement compris), budget noté (16 `pad10()` sur un lot de
10 événements). Application : `BrewEvent.timeEstimated`, `dateEstimated`, `natureHeure` ;
`Brew.importedFrom` et `importeDUneFiche` ; `ChronologieJour` reçoit les durées et l'écart de
début aussi sur l'écran du jour (calcul local, P2) ; une correction d'heure retire
l'estimation ; Admin › Import : `planDeRemplacement`, `LotSuppression`,
`SuppressionBrassin`, état `remplacementATerminer` (marque `Fiche Excel · {id} ·
remplacement`), `executerImport(aRemplacer:)`, compte rendu « remplacées » et « Supprimés »,
rubrique « Heures estimées ». Aucune dépendance ne change.

### v0.1.68 — technique

ADR-014 : `ecrire.mjs --supprimer-absents` refusait de supprimer les 24 doublons de
`beer_hops`, car la préparation compte 442 documents pour 466 en ligne (94,85 %, sous le seuil
de 95 %). Décision de l'utilisateur : `PART_MIN_PREPAREE` passe à 0,9
(`ingest/lib/ecriture.mjs`). Tests de `ingest/` adaptés (90 préparés pour 100 acceptés, 11
absents refusés ; émulateur à 61 pour 72 refusé). P19 de `CLAUDE.md`, `exigences-techniques.md`
et ADR-014 (note du 2026-11-15) mis à jour.

### v0.1.67 — fonctionnel

Sur l'écran du jour de brassage, le bouton « Étape suivante » termine l'étape en cours et
commence la suivante en un seul appui. Il fallait auparavant deux appuis : « Terminer
l'étape », puis « Commencer l'étape ». Avant une étape sans durée (un ajout, par exemple), le
bouton reste « Terminer l'étape » : l'ajout se confirme ensuite par « Fait ». Après l'appui,
un message « Étape « Ébullition » commencée. » s'affiche dix secondes avec « Annuler » : un
appui de trop se corrige en un geste. Avec TalkBack, le message reste ouvert jusqu'à son
action, comme celui qui annule un début ou une fin d'étape.

### v0.1.67 — technique

`brew_day_screen.dart` : `_enchainer` écrit `step_ended` de l'étape en cours et `step_started`
de `PlanDuJour.suivanteDe` dans un même lot, hors ligne comme les autres écritures d'étape
(P2), et prépare l'alerte du minuteur. `_BarreActions` l'affiche quand la suivante a une
durée ; sinon « Terminer l'étape » reste. Le libellé lu par TalkBack nomme les deux étapes.
Une `SnackBar` (10 s, `persist` vrai sous TalkBack par `MediaQuery.accessibleNavigationOf`,
comme celle de `_annuler`) propose « Annuler » : `_annulerEnchainement` relit le
plan et supprime `startEventId` de l'étape commencée et `endEventId` de la précédente par
`deleteEvents`, un `WriteBatch` sans transaction ; rien n'est supprimé si l'étape commencée
est déjà terminée ou sautée. Tests de `brew_day_screen_test.dart` adaptés, quatre cas ajoutés
(dernière étape, suivante de 0 min, « Annuler », « Annuler » après la fin).

### v0.1.66 — fonctionnel

Sur l'écran du jour de brassage, l'heure de fin s'écrit « Fin du brassage prévue vers 16:05 ».
Elle ne se confond plus avec la fin de l'étape en cours. Sur une autre journée, comme le
houblonnage à cru, elle s'écrit « Fin de la journée prévue vers… ».

### v0.1.66 — technique

`_Panneau` (`brew_day_screen.dart`) reçoit `libelleFin` : « Fin du brassage prévue » pour le
jour de brassage, « Fin de la journée prévue » pour une journée 2 ou suivante ; espace
insécable avant « · » pour couper la ligne après le point médian. Tests ajoutés
dans `brew_day_screen_test.dart` et `deroule_d4_test.dart`.

P15 accepte `noreply@anthropic.com`, l'adresse des sessions Claude Code, comme l'adresse
`noreply` de GitHub, pour les commits et les tags (décision de l'utilisateur du 2026-11-15).
Aucune des deux ne désigne une personne. `session-start.sh` n'avertit plus pour cette adresse.
Les prompts de développement (point 6, L6, Reprise) l'acceptent aussi : texte à recoller sur
claude.ai. `CLAUDE.md`, `guide-reseau.md` et `exigences-techniques.md` mis à jour.

Ces deux changements avaient été numérotés v0.1.62 et v0.1.63 sur leur branche, numéros pris
entre-temps par la branche principale, puis v0.1.64 et v0.1.65, pris aussi : ils sont renumérotés en v0.1.66.

### v0.1.65 — fonctionnel

Le formulaire « Inviter un membre » rappelle qu'une adresse invitée doit aussi être ajoutée aux
utilisateurs test du projet dans la console Google, faute de quoi Google refuse la connexion.
Un bouton copie l'adresse saisie et ouvre directement la bonne page de la console : il reste à
la coller. Google ne permet pas d'ajouter cette adresse automatiquement.

### v0.1.65 — technique

`invite_member_form.dart` devient un `ConsumerStatefulWidget` et ouvre
`console.cloud.google.com/auth/audience?project=<FIREBASE_PROJECT_ID>` par `ouvrirLienProvider`.
L'identifiant vient de `firebaseProjectIdProvider` (`members_providers.dart`, lu à la
compilation) et `consoleUtilisateursTest` le contrôle avant de construire l'adresse ; sans
identifiant valide, le bloc ne s'affiche pas. Échecs rapportés sous `members.open_console` et
`members.copy_email`, sans l'adresse. Aucune dépendance ajoutée.

### v0.1.64 — technique

ADR-014 : la première préparation réelle s'est arrêtée (`StateError`, « nom « ctz » porté par
hop-columbus, hop-ctz », 3 noms partagés). Le fichier 003 de Brewtarget porte `CTZ`,
`Tomahawk` et `Zeus` en documents à part. La ligne `Columbus` de `kFusions` les absorbe
(`EntreeDesignee` du 003) au lieu de les ajouter en alias ; leurs noms restent des alias de
`hop-columbus`. Cas ajoutés aux sources inventées de `fusions_test.dart`. Documents attendus en
moins : 24 (466 → 442), `DATA_SOURCES.md` à jour.
### v0.1.63 — technique

Fiches des fabricants versionnées (ADR-005, amendement du 2026-11-15, décision de
l'utilisateur) : le fichier BeerJSON 2.01 des 25 cultures Fermentis, relevé le 2026-11-14 et
écrit à la main, entre dans le dépôt sous `exchange/donnees/fabricants/cultures.json`.
`bin/preparer_referentiels.dart` le lit par défaut (option `--fabricants` pour un autre
chemin) : l'administrateur n'a plus à le copier dans `import/sources/`. Le fichier ne contient
que noms et valeurs techniques ; il n'est ni un asset ni servi par Hosting.
`exchange/test/fabricants_donnees_test.dart` le lit : 25 entrées, aucun rejet, les atténuations
de 98 à 102 % de HA-18, DA-16, DW-17 et LD-20 écartées. `DATA_SOURCES.md` (exception à « aucun
fichier de ces sources dans le dépôt », SHA-256 du fichier), ADR-005, `exigences-techniques.md`,
« Structure » de `CLAUDE.md` et `guide-reseau.md` mis à jour.

### v0.1.62 — fonctionnel

La Bibliothèque connaîtra toute la gamme de levures Fermentis pour le brassage, une fois le
référentiel relu et réécrit par l'administrateur : 23 levures et 2 bactéries, dont neuf
absentes jusqu'ici (SafLager E-30 et SH-45, SafAle BW-20 et W-68, SafBrew BR-8, DW-17, LD-20 et
LA-02, SafSour LB 1). Leurs atténuations et températures sont celles des fiches du fabricant.
« Sources des données » nomme cette nouvelle source.

### v0.1.62 — technique

ADR-005, amendement du 2026-11-14 : source `fabricants` de l'ingestion, fichier BeerJSON 2.01
écrit à la main (`import/sources/fabricants/cultures.json`, hors dépôt), lu par
`lireFabricants` d'`exchange/` et exigé par `bin/preparer_referentiels.dart`. Rang 0 : elle
passe avant 005, et les rangs des autres sources montent d'un. Une souche déjà connue de
Brewtarget garde l'identifiant de son document (`ingest/ecrire.mjs` n'efface rien). Licence
`Données publiées par le fabricant`, version et date du relevé `2026-11-14`, acceptées par
`ingest/lib/validation.mjs`. L'application affiche « Fiches des fabricants ». Les atténuations
de 98 à 102 % de HA-18, DA-16, DW-17 et LD-20 dépassent la borne de 100 % : écartées et
comptées au rapport. Admin › Sources nomme la source « Fiches des fabricants » dans
« Sources lues » (`libelleSourceExecution`) et dans son introduction. `DATA_SOURCES.md`,
`exigences-techniques.md` et `exigences-fonctionnelles.md` mis à jour.

### v0.1.61 — fonctionnel

La Bibliothèque des houblons est plus propre. Un même houblon n'apparaît plus plusieurs fois
sous des noms voisins : « Saaz (CZ) » et « Saaz (Czech Republic) », par exemple, ne font plus
qu'un. « Saaz » désigne le Saaz tchèque, et le Saaz cultivé aux États-Unis s'appelle « Saaz
(US) ». Les pays d'origine des houblons et des malts s'écrivent d'une seule façon. Une recette
qui cite « Hallertau », « Tettnanger », « CTZ » ou « Denali » retrouve le bon houblon. Ces
corrections arrivent dans l'application après la prochaine mise à jour de la Bibliothèque par
l'administrateur.

### v0.1.61 — technique

ADR-014 (option B). `exchange/lib/src/ingestion/origines.dart` : liste fermée des pays
(`kPays`) et table des graphies (`kGraphiesOrigine`), appliquées aux houblons et aux malts dans
`lecture_sources.dart` ; graphie inconnue ou double laissée absente et listée dans
`rapport.json` (`origines_inconnues`). `fusions.dart` : table de fusion écrite à la main
(`kFusions`, 16 lignes) branchée dans `Referentiel.fusionner`, identifiant inchangé
`hop-<cleNormalisee(nom)>`, noms écartés des alias ; la préparation s'arrête sur une ligne sans
entrée, une entrée désignée deux fois ou un nom porté par deux houblons ; trois alias DIY Dog
réorientés vers `hop-hallertauer-…`. `ingest/ecrire.mjs --supprimer-absents <beer_hops|beer_hop_aromas>` :
suppression contrôlée (30 au plus par lancement et par collection, refus sous 95 %, motif
d'identifiant, confirmation par la saisie du nombre, simulation, rapport `deletions`). 21
documents de `beer_hops` attendus en moins (466 → 445). Contrôles P19 complété et P56.

### v0.1.60 — fonctionnel

La teinte indicative s'affiche aussi devant la couleur d'un malt dans la Bibliothèque, et
devant la couleur calculée d'une recette. La page des teintes s'appelle désormais « Échelle
des couleurs », comme le lien qui l'ouvre. En thème sombre, les teintes foncées ont une
bordure plus visible. Demandé par le ticket #48.

### v0.1.60 — technique

Suites du ticket #48. `couleur_ebc.dart` : `CarreTeinte` (carré bordé d'une teinte),
`PastilleEbc` (teinte d'une valeur EBC par `teinteEbc` de `brewing/`, masquée et rapportée
une fois `library.color_swatch` si la valeur est refusée), `bordureTeinte` (`outline` au lieu
de `outlineVariant` sur la barre, les pastilles de l'échelle et les nouvelles pastilles).
`LigneFiche.avant` place un widget décoratif, exclu de la lecture d'écran, devant la valeur :
pastille de 20 px devant la couleur d'un malt. `_Indicateur.teinte` : pastille de 24 px dans
la tuile « Couleur » des calculs d'une recette. Titre de la page, nom de l'écran dans les
tickets et « Sources des données » : « Échelle des couleurs ». Aucune formule ni table dans
`app/lib/` (P3), aucune dépendance ajoutée.

### v0.1.59 — fonctionnel

Admin a une nouvelle entrée « Sources », réservée à l'administrateur. Elle montre la dernière
mise à jour de la Bibliothèque depuis les sources externes : sa date, sa cible, le nombre de
documents écrits, inchangés et refusés pour chaque collection, les sources lues avec leur
version et le nombre de noms non reconnus par nature. Un lien ouvre « Sources des données ».
Le bouton « Actualiser », ou un geste qui tire la page vers le bas, relit l'écran sans effacer
ce qui est affiché. Si cette lecture échoue, un message le dit au-dessus du compte rendu ou de
la liste, qui restent visibles.

En dessous, « Tous les noms non reconnus » liste les noms qu'aucune source n'a rattachés à un
ingrédient de la Bibliothèque, du plus fréquent au moins fréquent, par pages de 50, avec le
nombre de noms affichés, « Charger la suite » et la fin de la liste signalée. Chaque ligne
donne la nature, le nom, l'origine (recettes DIY Dog ou import d'un membre), le nombre de
fois et la date. Cette liste dit à l'administrateur quels noms ajouter à la table d'alias : un
nom rattaché reçoit les valeurs de l'ingrédient, et plus de recettes se calculent. L'écran ne
fait que lire : la mise à jour se lance toujours depuis le poste de l'administrateur.

### v0.1.59 — technique

Dernière partie de L4 d'ADR-005, préparée en v0.1.29 (PR #33) et reprise sur la branche
principale par une fusion. `features/admin/` : `SourcesRepository` (`ingest_runs/` par
`limit(1)`, `import_unresolved/` par pages de 50, `get()` seul), `domain/ingestion.dart`,
`admin_sources_screen.dart`, `libelles_sources.dart` ; route `/admin/sources`. L'entrée d'Admin
passe sur `LigneListe`, comme les autres, avec `AdminSourcesScreen.sousTitre`. L'écran suit
Admin › Rapports d'erreur : `CarteSection` et `TitreSection` (sous-sections), états en `Encadre`
dans chaque bloc au lieu d'`EtatVide`, d'`EtatErreur` et de `BandeauListePerimee` (panne de la
page suivante dans le pied, à la place de « Charger la suite »), lignes en
`LigneListe`, `IconButton` « Actualiser » de 48 px et `RefreshIndicator`, compte rendu sans la
borne `kDialogMaxWidth`. L'échec d'une relecture sous un compte rendu affiché se lit par
`hasError && hasValue` (Riverpod 3 garde la valeur). `LigneFiche` reçoit `selectionnable`
(chemin du rapport en `SelectableText`). `firestore.rules` inchangé : les deux collections sont
déjà lues par l'admin seul (P19).

### v0.1.58 — fonctionnel

Dans l'éditeur de recette, le champ « Style » montre les styles de la Bibliothèque dès qu'on
le touche, sans rien taper. Une icône de liste au bout du champ ouvre « Choisir un style » :
une recherche par code, nom ou catégorie, et tous les styles rangés par catégorie. Un appui
écrit le style dans le champ. La saisie libre reste permise. Sous le champ, une aide dit si le
style vient de la Bibliothèque ou si l'export BeerXML le refusera. Demandé par le ticket #49.

### v0.1.58 — technique

`ChampBibliotheque` reçoit `choixDesStyles` (champ « Style » seul ; malts, houblons, ajouts et
levures inchangés) et un quatrième argument `boutonListe` dans `fieldBuilder`. Nouveau
`choix_style.dart` (`choisirStyle`, `stylesGroupes`, `aideStyleSaisi`) ; `stylesParCode` et
`comparerCodesStyle` dans `referentiel.dart`. Index `beer_index/styles` lu par `get()` une fois,
partagé entre la liste et la feuille, aucun `snapshots()` (P22). Aucune dépendance ni règle
changée. L'aide « Style de la Bibliothèque » demande le nom exact, casse comprise, comme
l'export BeerXML. Demandé par le ticket #49.

La relecture ajoute : index des styles lu dès l'ouverture de l'éditeur, pour que l'aide « hors
Bibliothèque » paraisse sur une recette existante sans focus ; états de la feuille par
`EtatChargement`, `EtatVide` et `EtatErreur` (« Réessayer ») ; tailles de la feuille dans
`breakpoints.dart` ; avertissement retenu pendant la frappe tant que le texte a des
suggestions ; annonce « Style choisi » au lecteur d'écran ; curseur dans la recherche sur grand
écran.

### v0.1.57 — fonctionnel

La fiche d'un houblon de la Bibliothèque montre ses arômes : des descripteurs (agrumes, floral,
résineux…) et un court texte pour chaque moment d'ajout, du premier moût au houblonnage à cru.
Ces textes sont rédigés par une IA pour Kass'Beer. La fiche dit s'ils ont été relus par
l'administrateur, et signale une confiance faible. Les houblons de vos recettes sont relus en
premier. Un houblon trop peu documenté l'indique au lieu d'inventer. L'écran « Sources des
données » explique d'où viennent ces textes.

### v0.1.57 — technique

ADR-013 : descriptions aromatiques des houblons rédigées par l'API Claude (`claude-fable-5-2`,
effort `medium` par défaut) depuis le poste de l'admin. `ingest/generer-aromes.mjs` et
`ingest/lib/aromes/` (SDK `@anthropic-ai/sdk` 1.8.0 en version exacte, chargé au premier appel,
sorties structurées, API Batches, tarif lu dans `import/ingest/aromes/tarif.json`, budget,
confirmation, `--nouveaux` pour les houblons ajoutés depuis) ; `ingest/lister-houblons-recettes.mjs`
(lecture seule de `recipes/` et `brews/`) et `exchange/bin/lister_houblons_recettes.dart`
(`IndexBibliotheque.resoudre`, nouvelle `correspondances`) ; `ecrire.mjs --aromes` écrit
`beer_hop_aromas/` après validation et relecture, et compte les houblons sans description.
`firestore.rules` : `beer_hop_aromas/{id}` en `get` par `isMember()`, aucune liste ni écriture,
tests des cinq profils. Application : `AromesHoublon`, `lireAromesHoublon` (un `get`),
`SectionAromes` dans la fiche d'un houblon, paragraphe de « Sources des données ». Nouveau
poste de coût `hop_aroma_generation` ; contrôles P54 et P55. Paquets ajoutés à
`ingest/package-lock.json` : `@anthropic-ai/sdk` 1.8.0, `json-schema-to-ts` 3.1.1,
`@babel/runtime` 7.29.14, `ts-algebra` 2.0.0, `standardwebhooks` 1.1.1, `@stablelib/base64`
1.0.1, `fast-sha256` 1.3.0. Aucune dépendance de l'application ne change.

## 2026-11-14

### v0.1.56 — fonctionnel

Sur la fiche d'un style, une barre en dégradé montre sous la ligne « Couleur » la teinte de la
bière, du minimum au maximum de la plage. Une nouvelle page « Couleurs EBC » montre la teinte de
0 à 79 EBC, tous les 4 EBC. Elle s'ouvre depuis la Bibliothèque (« Échelle des couleurs ») et
depuis la fiche d'un style, et marche sans réseau. La teinte est indicative : la couleur réelle
dépend du verre, de la lumière et de l'écran. Au-delà de 79 EBC, la teinte ne fonce plus, et la
fiche le dit. « Sources des données » nomme la source des teintes et donne le texte de sa
licence. Demandé par le ticket #48.

### v0.1.56 — technique

`brewing/` : `teinteEbc` (EBC → `0xRRGGBB`), `degradeEbc` (arrêts d'un dégradé de plage) et
`teinteEbcLimite` (78,8 EBC), sur la table générée `teintes_srm.dart` : 400 triplets du paquet
npm srm2hex 1.0.2 (MIT, archive de SHA-1 d84847e600a65eaee38247e2bce6e6d33c214d14), repris par
script, indexés par floor(`ebcToSrm` × 10). Au-delà de 40 SRM, dernière teinte de la table.
Fixture écrite à la main `brewing/test/fixtures/teinte.json` (14 teintes dont une frontière à
11,82 EBC, 4 dégradés, 4 cas refusés, empreinte FNV-1a de `lookup.js` qui vérifie la table
générée ; génération décrite dans `DATA_SOURCES.md`). Application : `couleur_ebc.dart`
(`BarreCouleurEbc`, `BandeTeintes`, `TextesCouleurEbc.depasseLimite` et `auDela`),
`couleurs_ebc_screen.dart` (sans état d'erreur : ses entrées sont des constantes valides,
cases de la grille suivant l'échelle du texte), texte MIT `DataSourcesScreen.licenceMit`,
route `/bibliotheque/couleurs` hors de la coquille, lien « Échelle des couleurs » dans
l'en-tête de la Bibliothèque, ligne srm2hex dans « Sources des données » et dans
`DATA_SOURCES.md`. Aucune lecture Firestore, aucune dépendance ajoutée.
Pastille sur la fiche d'un malt et sur la recette : plus tard. Demandé par le ticket #48.

### v0.1.55 — fonctionnel

« Mes processus » propose toujours deux modèles à copier, même hors ligne : le modèle d'exemple
et le plan de brassage des fiches Excel, avec ses étapes et ses températures. Un appui ouvre un
nouveau processus prérempli ; rien n'est enregistré avant « Enregistrer ».

Une courbe des températures accompagne le jour de brassage. Elle montre la température visée
de chaque étape selon le plan de départ et selon les heures réelles, les températures et les
densités mesurées, et la densité initiale prévue. Sur le téléphone, une bascule « Étapes » |
« Courbe » l'affiche à la place de la chronologie ; sur grand écran, elle se place sous le
minuteur. Sur la fiche du brassin, elle paraît en tête de la journée de brassage dès la
première étape commencée. En paysage, sur un téléphone, la bascule garde le minuteur visible.

La courbe de fermentation commence à la densité initiale du jour de brassage : un seul relevé
suffit pour la voir. Elle montre aussi les densités initiale et finale prévues, et la plage de
température de la levure quand la Bibliothèque connaît cette levure. Si la levure est absente
de la Bibliothèque, ou sans plage, une ligne le dit.

### v0.1.55 — technique

`brewing/` : `brewDayTemperatureSeries` (`brew_day_curve.dart`) calcule les températures visées
du plan de départ et recalculées, le retard et les débuts théoriques à partir de l'horaire de
`recomputeSchedule` ; cas `brew_day_temperatures` et modèle `fiches` ajoutés d'abord à
`brewing/test/fixtures/process.json`. Application : `modele_fiches.dart`, `modeles_a_copier.dart`
(`ModeleACopier`, route `?modele=exemple|fiches`), section « Modèles à copier » de
`process_list_screen.dart` ; « Partir du modèle d'exemple », `partirExemple` et
`AppRoutes.newProcessFromExample` retirés (remplacés par `AppRoutes.newProcessFrom`).
`courbe_brassage.dart` (`CourbeBrassage`, `donneesCourbeBrassage`, `resumeCourbeBrassage`),
`ZoneChronologieCourbe` dans l'écran du jour (aussi en paysage bas), `TraceCourbeBrassage`,
`LignePrevue` et `PlageTrace` dans `trace_courbe.dart`, seul import de `fl_chart` (P18) :
graduations de densité rondes sur la grille, axe de droite sans libellés sous 200 px de tracé,
info-bulle à distance euclidienne qui réunit les séries touchées. Légende partagée
`legende_courbe.dart` (trait, disque, losange, aplat). `brewing/` : `gravityGapPoints` (cas
`gravity_gap` de `gravity.json`) pour l'écart des densités prévues ; l'écart initial se compte
sur la densité initiale retenue seule. `prevuDe` passe dans `brews/domain/prevu.dart`
(`CalculsRecette.calculOuNul`), ce qui retire l'import circulaire entre
`releve_fermentation.dart` et `prevu_et_mesure.dart`. Plage de la levure :
`plage_levure.dart` (`plageLevureProvider`), résolution par le nom (`IndexBibliotheque.resoudre`)
dans `beer_index/cultures`, puis `beer_cultures/{id}` par `get()` (P22) ; `lireFiche` reçoit
`cacheSeul` pour le hors ligne. Lecture faite par la fiche seule ; le test « P2 » de
`deroule_d4_test.dart` couvre les fichiers de la courbe du jour et refuse qu'ils lisent la
Bibliothèque. Fiche : la courbe du jour ne paraît qu'après le premier début d'étape. « Mes
processus » : « Modèles à copier » aussi sous une panne de lecture. Aucune écriture Firestore
nouvelle, aucune règle changée, aucune dépendance changée.

### v0.1.54 — fonctionnel

Après un import de recettes, un appui sur le nom d'une recette créée ouvre de nouveau sa fiche.
Le retour ramène au compte rendu de l'import. Après « Modifier » ou « Modifier la chronologie »,
« Enregistrer » revient à cette fiche ; « Supprimer » revient au compte rendu. On peut ainsi
compléter les recettes importées l'une après l'autre. Demandé par le ticket #60.

### v0.1.54 — technique

Recettes › Importer : la fiche d'une recette créée s'ouvre par `push` sur une route hors de la
coquille, `/recettes/importer/:id` (`AppRoutes.importedRecipe`, `ImportedRecipeScreen` :
`RecipeDetailScreen` dans une `PageSecondaire` « Recette »). L'import est ouvert par `push`
depuis la liste des recettes, donc au-dessus de la coquille ; un `push` de `/recettes/:id`
ajoutait une seconde page de coquille de même clé, le `Navigator` levait l'assertion
`!keyReservation.contains(key)` et la fiche ne s'affichait pas. Nouvelle route inscrite dans
`ticket_screens.dart` (nom d'écran, menu du compte, écrans à prix, et les quatre fenêtres de la
fiche : Exporter, Nouveau brassin, Prix d'un ingrédient, Reprendre un prix). Les sorties de la
fiche gardent le compte rendu dans la pile : `RecipeDetailScreen(depuisImport: true)` ouvre
`RecipeEditorScreen` et `BrewStepsEditorScreen` avec `extra: AppRoutes.retourParPop`, qui se
ferment par `pop` après « Enregistrer » ; Supprimer fait `pop`, Dupliquer ouvre la copie par
`push` sur `/recettes/importer/:id`, l'état absent affiche « Revenir au compte rendu ». Tests
ajoutés à `import_recipes_test.dart` sur le parcours réel (liste, import, fiche, retour ;
Modifier puis Enregistrer ; Supprimer) ; le test 11 est gardé. Demandé par le ticket #60.

### v0.1.53 — fonctionnel

Quand l'écran du jour se rouvre après une coupure, le message « Brassage repris » s'affiche sous
l'étape en cours, avec un bouton « Fermer ». Il ne cache plus le bas de la chronologie et reste
lisible en paysage avec un grand texte. Sur un petit téléphone, une barre de défilement indique
que le panneau de l'étape continue plus bas.

La fiche d'un brassin en fermentation indique la date du brassage avant le jour de fermentation
(« Brassé le 8 nov. 2026 (J+12) »). Le suivi d'un ticket prend la présentation des autres
fiches : titre, type et statut en tête, puis la date d'envoi, la version et l'écran en lignes.

### v0.1.53 — technique

Suite du lot 4 de la revue visuelle (remarques « plus tard » de la revue UX). `GroupeBrassins` et
`groupeBrassin` passent de `brews_screen.dart` à `domain/brew.dart` ; `compareBrews` trie
d'après ce groupe, et `_bucket`, qui le recopiait, sort. L'annonce de reprise devient un
`Encadre` du panneau (`liveRegion`), placé dans `_DefilementPanneau` (`Scrollbar` toujours
visible, dessinée seulement si le contenu dépasse, sans la seconde barre du web de bureau),
sous la carte de l'étape ; `scrollbarTheme` du thème en `onSurfaceVariant`, 6 px ; le test à 200 % n'écarte plus l'erreur
« Floating SnackBar presented off screen », et `masquerAnnonce` sort des tests. Le test du thème
contrôle le texte coloré sur `surfaceContainerLow` (fond des cartes), en clair et en sombre.
Mise à jour de l'APK : le fichier téléchargé s'ouvre par `File.open(mode: FileMode.write)` à la
place d'`openWrite`, qui sous Windows ne rendait jamais l'erreur d'un dossier absent ;
`app_update_transport_test` « dossier absent » passe sur le poste. Une erreur inattendue du
téléchargement (corps illisible, rappel qui lève) referme aussi le fichier avant de remonter,
avec son test (relecture `securite`). Bornes de taille et SHA-256 inchangés (P51).

### v0.1.52 — fonctionnel

Le compte fondateur a son propre plafond de lancements de sessions : 50 par jour, cinq fois
celui des autres administrateurs. Ses lancements ne consomment pas les 10 du groupe, et
inversement. Le compteur d'Admin › Tickets et la boîte de lancement affichent le plafond du
compte connecté. Le mois compte tous les lancements.

### v0.1.52 — technique

Compte fondateur reconnu par le champ `founder: true` de `members/{email}`, posé dans la
console Firebase (les règles refusent ce champ à tout client : liste blanche de `create`,
`update` fermé ; aucun e-mail dans le code, P15). `requireAdmin` rend `founder` sans lecture de
plus (`isFounder`, `functions/src/auth.ts`). `FOUNDER_LAUNCHES_PER_DAY` = 5 ×
`LAUNCHES_PER_DAY` (`config.ts`), compteur `ticket_quotas/launch_founder_{AAAAMMJJ}`,
`ticket_status/launches` gagne `founder_count_day` et `founder_per_day` (`launchModel.ts` :
`LaunchPool`, `launchLimitOf`). Client : `Member.founder`, `EtatLancements.vuePour`, appliqué
par `launchStatusProvider`. P36 et « Coûts variables » de `CLAUDE.md` modifiés (décision de
l'utilisateur du 2026-11-14). Réglage après le déploiement : ajouter `founder` (booléen,
`true`) au document `members/` du fondateur dans la console Firebase.

La relecture ajoute des tests : compteur du fondateur rendu sur un échec, deux lancements
simultanés du fondateur, champ `founder` refusé par les règles à l'admin ; cas fondateur ajoutés à
`test-fixtures/member_access.json`, rejoués par `functions/test/auth.test.ts` et
`app/test/members_repository_test.dart` (P31, ligne de « Logique dupliquée » mise à jour). P31
nomme aussi `app/lib/features/members/domain/member.dart` (cinq fichiers au lieu de quatre, accord
de l'utilisateur du 2026-11-14).

### v0.1.51 — fonctionnel

Les fiches d'une recette, d'un brassin, d'un équipement et d'un processus ont un en-tête avec le
nom et ses étiquettes, puis des sections dans des cartes. Sur la fiche d'un brassin, la prochaine
journée et son bouton sont en tête, dans une carte colorée. Les boutons suivent le même ordre
partout : l'action principale en plein, « Modifier » en teinte, « Supprimer » en rouge. La liste
des brassins est groupée : en cours, prévus, terminés et abandonnés. La recherche des recettes
prend toute la largeur. Les listes vides de tickets, de prix et de membres ont un titre.

Sur l'écran du jour, l'étape en cours est dans une carte, avec une barre qui montre le temps
écoulé. Quand le temps est dépassé, la carte passe à l'ambre, avec un bord et une alarme.
L'étape et l'heure de fin s'écrivent plus grand, pour se lire à deux mètres. Dans la
chronologie, une étape faite est en vert et l'étape en cours en brun. Dans « Préparer le
brassage », chaque vérification a l'icône et la couleur de son état, et le nom du brassin et sa
date sont sur deux lignes.

### v0.1.51 — technique

Lot 4 de la revue visuelle, en deux branches réunies (4a fiches et listes, 4b écran du jour).
Composants `EnTeteFiche`, `CarteSection` (débord de `kDebordCarteCompact` sous 600 px),
`RepereDisque`, `SurLigneChoisie` (contour de l'`Etiquette` sur une ligne choisie),
`PageSecondaire.marges` (borne dans la liste, défilement à la molette au-dessus des marges),
`ContenuRecette.enCartes`, `GroupeBrassins`, `kDetailLigneIllisible` ; fiche équipement à 840 px ;
27 `OutlineInputBorder()` explicites retirés (le thème les fournit). Écran du jour : `_CarteEtape`
(`primaryContainer`, puis `tertiaryContainer` et bord `tertiary` en dépassé, même marge),
`TimerReading.elapsedFraction` dans `brewing/` avec ses cas dans `planning.json` (P3),
`StylesJourDeBrassage` gagne `etiquette`, `information`, `bouton` et `saisie` (plus aucune taille en
dur dans `brew_day/`), colonne d'heure de la chronologie `kChronologieHeureWidth` multipliée par
l'échelle du texte et bornée à `kChronologieHeureMaxFraction`, état explicite des vérifications de
« Préparer ». Aucune lecture ni écriture de l'écran du jour changée (P2). Aucune dépendance
changée.

### v0.1.50 — fonctionnel

Pour l'administrateur, Valider, Refuser, Clore et « Relancer l'envoi » agissent tout de suite sur
GitHub, au lieu de partir plus tard. Pendant l'action, la fiche affiche « … en cours sur
GitHub. », puis un message court dit si c'est fait. En cas d'échec, le message dit pourquoi et
le texte saisi est gardé. La boîte de Refuser et de Clore peut se fermer pendant l'envoi, et
accepte maintenant 4 000 caractères. Ces actions demandent le réseau : hors ligne, les boutons
restent visibles mais inactifs, avec « Ces actions demandent le réseau. ». L'historique des
décisions d'un ticket reste affiché.

### v0.1.50 — technique

ADR-008, lot T7 (décisions de l'utilisateur du 2026-11-14 ; P23, P25, P26, P42, P44 modifiés,
P53 ajouté) : callables `validateTicket`, `refuseTicket`, `closeTicket` et `retryTicketSend`
(`functions/src/tickets/decisionCalls.ts`, `requireAdmin`, `maxInstances` 1, 60 s, secret
`GITHUB_TICKETS_TOKEN` seul). La décision se prend dans la transaction du bail
`decision_lease_until` (`decisionStart`) : `allowedDecisions` recalculé, verrou des
livraisons, reprise par l'admin de la décision la plus récente de même action (`failed`,
`applying` au bail expiré, ou `pending` d'avant T7) avec le même identifiant, commentaire déjà
publié reconnu sans republication (`textKept` dans la réponse), échec partiel en `aborted`.
Retirés : `onDecisionCreated`, `onDecisionUpdated`, `resumeStuckDecisions`,
`retryFailedSends`, la relance par `retry_requested_at`, trois index. `tickets/{id}/decisions/`
reste l'historique, en `allow read: if isAdmin(); allow write: if false`. `REPLY_MAX_CHARS` et
le motif passent à 4 000. Client : appels directs avec état « en cours » et « dernier échec »
dans `decisionsFicheProvider`, messages d'échec de 10 s, un seul appel à la fois par fiche,
boîte « Répondre » corrigée (`route.isActive`). Diffs des workflows (P10) : dans `ci.yml` et deux
fois dans `deploy.yml`, les quatre callables ajoutées à la liste fermée avec `maxInstances` 1 et
60 s, et une liste fermée des déclencheurs (`publishTicket` seul en déclencheur Firestore,
`syncTickets` seul en tâche planifiée). Réglages avant la fusion : aucune décision `pending` ou
`applying` en base, puis suppression manuelle des deux déclencheurs
(`firebase functions:delete`), sans quoi le déploiement des Functions échoue.

### v0.1.49 — fonctionnel

L'application prend les couleurs du logo : brun du bois, laiton, ambre de la chope et vert
pour ce qui est fait. Les titres s'écrivent dans une police à empattements, et les chiffres
restent alignés d'une ligne à l'autre. Le médaillon du logo s'affiche à la connexion, au
chargement, sur « Ce compte n'a pas accès » et en tête du menu sur grand écran. Le texte
s'affiche dans la même police sur tous les appareils. Sur le web, l'application ne télécharge
plus de police au démarrage, et les flèches s'affichent aussi sans réseau.

Les listes de recettes, brassins, équipements, processus, tickets et l'accueil Admin ont la même
ligne : une icône à gauche, le nom, les détails, puis les étiquettes. Les prix et les frais
suivent la même ligne, sans icône. Le statut d'un brassin s'affiche dans une étiquette colorée. Une liste vide affiche un titre. Les titres de
section se distinguent de leur contenu. Les messages d'erreur, d'avertissement et de succès
s'affichent dans des encadrés de couleur ; « Tout est prêt » passe en vert dans « Préparer le
brassage », et chaque vérification prend la couleur de son état.

### v0.1.49 — technique

Revue visuelle de l'agent `ux-designer`, lots 1 à 3. Lot 1 : `app_theme.dart` construit la
palette depuis quatre couleurs (couleurs principales en variante `fidelity`, conteneurs en
variante `tonalSpot` pour qu'un bouton posé dessus garde son contraste), surfaces tirées du
laiton, `ThemeExtension` `CouleursEtat` (succès), thèmes de barre, navigation, rail, cartes,
champs, listes, puces, segments, séparateurs, `ExpansionTile` et bouton flottant ;
`app/test/app_theme_test.dart` vérifie un contraste d'au moins 4,5:1 sur 23 couples en clair et
en sombre. Lot 2 : polices embarquées, sous SIL OFL 1.1, réduites par fonttools, chacune avec
sa licence en asset (`OFL-Bitter.txt`, `OFL-Roboto.txt`, `OFL-NotoSansMath.txt`) : Bitter
demi-grasse pour les titres, figée à la graisse 600 (38 736 octets) ; Roboto 400, 500, 700 et
italique 400 pour le texte (56 Ko chacune, latin, latin étendu A, ponctuation, symboles), posée
en `fontFamily` du thème : la famille « Roboto » du manifeste empêche le moteur web de la
télécharger depuis `fonts.gstatic.com` au démarrage, et Windows ou macOS ne prennent plus Segoe UI
ou SF ; `Symboles` (8 Ko, flèches et ⋮ tirés de Noto Sans Math) en `fontFamilyFallback` avec
Roboto, pour les flèches de la chronologie du jour, du coût figé et de l'import, absentes de
Roboto et de Bitter, que le web allait chercher dans une police Noto en ligne ; médaillon de 384 px en
WebP (38 564 octets) tiré de `assets/Kassbeer_transparent.png` ; `MedaillonKassBeer` (48 px
au moins) dans `logo_kass_beer.dart`, l'écran de panne au démarrage, `not_invited_screen.dart`
et l'en-tête du rail étendu. Lot 3 : composants `LigneListe`, `Encadre`, `PageSecondaire` et
`LigneTicket`, `TitreSection` à deux niveaux, `LigneFiche` en deux colonnes à partir de 600 px,
`EtatVide` avec titre, constante `kMargeBoutonFlottant` ; `encadre_avertissement.dart` est
supprimé ; tests dans `app/test/composants_test.dart`. Aucune dépendance changée ;
`main.dart.js` (`flutter build web --release`) : 5 633 682 octets sur `main` à la v0.1.47 (code de
`app/` inchangé à la v0.1.48),
5 649 424 après (+ 15 742, dont 14 980 pour la déclaration des polices du texte et de secours) ;
assets ajoutés : 325 546 octets (polices, licences et médaillon). APK de release compilé par
le job « Android — compilation » de la CI (clé de signature absente du poste) ; APK de débogage
compilé sur le poste. Corrections de la revue : « Tout est prêt » en `titleMedium` et annoncé,
séparateurs à leur hauteur par défaut, ton neutre d'`Encadre` retiré faute d'usage.

### v0.1.48 — fonctionnel

« Lancer l'analyse », les autres lancements de session, « Répondre » à une analyse, l'écran
Journaux et la vérification d'une capture jointe à un ticket marchent de nouveau. Ils échouaient avec « Réponse perdue » ou
« Journaux indisponibles pour l'instant ».

### v0.1.48 — technique

Chaque callable échouait en 500 sans détail (`app/no-app`, journaux du 2026-11-14) :
`firebase-functions` crée son application nommée `__FIREBASE_FUNCTIONS_SDK__` pour vérifier
le jeton avant le code de la fonction, et `firestore.ts` comme `storage.ts` ne créaient
l'application par défaut que si `getApps()` était vide. `src/adminApp.ts`
(`ensureDefaultApp`) la crée si aucune application `[DEFAULT]` n'existe ; test
`functions/test/adminApp.test.ts`. Les déclencheurs n'étaient pas touchés. Aucun paquet ne
change.

### v0.1.47 — fonctionnel

Sur Android, l'application vérifie à chaque lancement, une fois connecté, si une nouvelle
version existe. Si oui, une fenêtre « Nouvelle version » donne le numéro de la version, celui
de la version installée et la taille du téléchargement. « Plus tard » la ferme jusqu'au
lancement suivant. « Mettre à jour » télécharge la version dans l'application, contrôle le
fichier, puis ouvre l'écran d'installation d'Android. La première fois, Android demande
d'autoriser Kass'Beer à installer des applications : la fenêtre ouvre le bon réglage. Une
coupure du réseau affiche l'échec et « Réessayer ». La fenêtre ne s'ouvre jamais pendant le
jour de brassage ou une journée du déroulé : elle attend que vous en sortiez. Rien ne change
sur le web. L'invitation par e-mail reste en place. Demandé par le ticket #36.

### v0.1.47 — technique

ADR-012 (option A), ticket #36. Le job `build` de `deploy.yml` copie l'APK signé dans
`app/build/web/app-release.apk` et écrit `app/build/web/apk_release.json` (`version`,
`build_number`, `file`, `size_bytes`, `sha256`, `built_at`) ; `plan` lit aussi ce manifeste en
ligne, sans jeton, et fait construire l'APK s'il est absent, illisible ou en retard sur le build
de `app/pubspec.yaml`. Sans nouvel APK, `deploy` lance `scripts/garder-apk-en-ligne.sh` avant
l'authentification : la paire en ligne est recopiée si sa forme, `PK`, sa taille et son SHA-256
concordent ; un manifeste seul ou une paire incohérente arrête le déploiement. App Distribution
reste publié depuis le même APK. `firebase.json` : `app-release.apk` (type, téléchargement) et
`apk_release.json` en `no-cache`, règles de cache existantes inchangées (P1). Client :
`AppUpdateService` (`app/lib/core/services/app_update_service.dart`), lecture par `HttpClient`
de `dart:io` derrière un import conditionnel (stub sur le web), délai de 8 s, corps borné à
4 096 octets, formes contrôlées champ par champ, comparaison du seul `build_number` au build
installé ; échec réseau sans rapport, réponse 200 illisible en `app_update_check` ; fichier
faux (taille, SHA-256, paquet ou `versionCode`) effacé et rapporté en `app_update_download`,
coupure ou annulation sans rapport. Fenêtre `app_update_dialog.dart`, vérification depuis la
coquille (`verification_mise_a_jour.dart`), jamais sur `/brassins/:id/jour` ni
`/brassins/:id/jour/:journee`. Canal Kotlin `fr.kassbeer/updates` (`MisesAJour.kt`) :
`updatesDir`, `canRequestInstall`, `openInstallSettings`, `installApk(expectedBuild)` sans
chemin reçu du Dart, contrôle du paquet et du `versionCode` par `getPackageArchiveInfo`, second
`FileProvider` (`MisesAJourFileProvider`, autorité `.updates`, `cacheDir/updates/` seul),
permission `REQUEST_INSTALL_PACKAGES`, `cacheDir/updates/` vidé à chaque lancement neuf.
`app/pubspec.yaml` déclare `crypto: 3.0.8` en version exacte ; `pubspec.lock` : seul `crypto`
passe de `transitive` à `direct main`, aucune version ne change. `main.dart.js` : 5 610 310
octets avant, 5 612 436 octets après (+ 2 126). Taille de l'APK non mesurée (pas de SDK Android dans
la session) : à relever dans le résumé du job `build` du premier déploiement. Réglage hors
dépôt : rétention des versions de Hosting.

### v0.1.46 — fonctionnel

Dans « Rapports d'erreur », une relecture n'affiche plus qu'une seule attente, sur le bouton
appuyé. Après une panne, « Réessayer » montre l'attente dans le bandeau, et le bouton
« Actualiser » reste en place, désactivé. Tirer la liste vers le bas n'ajoute plus d'indicateur
en haut de l'écran.

### v0.1.46 — technique

`error_reports_screen.dart` remplace le drapeau `_actualisation` par l'origine de la lecture
(`_Origine` : en-tête, bandeau, état vide hors ligne, suite, geste), comme `logs_screen.dart` : l'indicateur de
l'en-tête ne s'affiche que pour « Actualiser », celui du bandeau que pour son « Réessayer »
(`retryEnabled: false` sinon), celui de « Charger la suite » que pour la suite, et
« tirer pour actualiser » garde le seul indicateur du `RefreshIndicator`. Quatre tests ajoutés à
`app/test/error_reports_test.dart`. Point relevé à la livraison d'ADR-011 :
deux indicateurs « Lecture en cours » pendant un « Réessayer » sous une liste. Aucune dépendance changée ;
`main.dart.js` (`flutter build web --release`) : 5 619 084 octets sur `main` à la v0.1.45,
5 609 932 après (− 9 152).

### v0.1.45 — fonctionnel

Dans « Signaler ou proposer », un bouton « Choisir une image » permet de joindre une image de
l'appareil à la place de la capture de l'écran. Seules les images PNG, JPEG et WebP sont
proposées. L'image est réduite à 2 000 pixels de côté au plus et réenregistrée sans ses
métadonnées (date, lieu de prise de vue). Une seule image part avec le ticket : choisir une image
décoche la capture de l'écran, et l'inverse. Pendant la préparation de l'image, « Envoyer » est
grisé. Une capture doit être envoyée dans l'heure qui suit le ticket. Les captures sont effacées
au bout de 180 jours ; la fiche du ticket affiche alors « Capture effacée. ».

### v0.1.45 — technique

ADR-008, complément du lot T6 (décisions de l'utilisateur du 2026-11-14, note datée de l'ADR,
points A à E ; P23 et P48 modifiés). `storage.rules` : `create` refusé si
`tickets/{ticketId}.created_at` n'est pas une date de moins d'une heure (`ticketOpenToCapture`),
tests de `rules-tests/` (55 et 61 min, champ absent ou texte, cinq profils sur un ticket de
90 min). `attachTicketScreenshot` lit 24 octets : signature, IHDR de 13 octets, largeur et
hauteur de 1 à 2 000 px (`dimensions_refused` sinon) ; écrit `screenshot_expires_at` (+ 180
jours) avec `screenshot_path`, champ serveur refusé au client (tests des cinq profils). Client :
« Capture effacée. » sans lecture ni rapport quand l'échéance est passée ou que Storage rend
`object-not-found` (`CaptureEffacee`). Canal `fr.kassbeer/files` (P17, P28) : `pickDocument`
reçoit `mimeTypes` en option (1 à 10 types, même motif vérifié en Dart et en Kotlin, test
d'égalité), envoyés par `EXTRA_MIME_TYPES` ; attribut `accept` sur le web ; sans filtre, appel
inchangé. Formulaire : `kTypesImages` (PNG, JPEG, WebP), lecture bornée à 5 Mo par le Dart,
`dimensionsImage` lit la taille dans l'en-tête (PNG IHDR, JPEG SOFn, WebP VP8, VP8L, VP8X) sans
décoder, refus au-delà de 50 millions de pixels par `depasseMaxPixels` (comparaison sans
produit), recontrôle du descripteur hors web, décodage `dart:ui` (côté long à 2 000 px) et
réencodage PNG ; `EditeurPleinEcran.actionActive` grise « Envoyer » pendant la préparation.
Réglages faits le 2026-11-14 : bucket en `us-east1` (documentation corrigée, constat du
stockage hors UE dans ADR-008), cycle de vie de 180 jours sous `tickets/`, suppression réversible
désactivée. Taille de `main.dart.js` (`flutter build web --release`) : 5 610 310 octets avant (v0.1.44),
5 619 084 après (+ 8 774). Kotlin modifié : APK compilé par le job CI « Android — compilation ».

### v0.1.44 — fonctionnel

L'administrateur trouve dans Administration un nouvel écran, « Journaux ». Il cherche dans les
messages écrits par le serveur (tickets, lancements, livraisons), du plus récent au plus ancien,
50 à la fois. On choisit la gravité, la période (1 h, 24 h ou 7 jours), une fonction, un ticket ou
un texte, puis on appuie sur « Rechercher » : rien ne part à l'ouverture ni pendant la frappe. Une
entrée se déplie sur son message et ses données, et « Copier l'entrée » les copie. Les journaux
peuvent contenir des adresses e-mail : l'écran rappelle de ne pas les recopier dans une Issue.

### v0.1.44 — technique

ADR-011, lot J2 : callable `queryLogs` (`functions/src/logs/queryLogs.ts`, exportée par
`index.ts`) : `onCall`, `requireAdmin` en premier, `maxInstances` 1, `concurrency` 1, 60 s,
256 Mio, `cors` de `CALLABLE_ORIGINS`, compte `tickets-functions`, aucun secret (P25). Elle lit
`entries:list` de Cloud Logging par `fetch` (`redirect: "error"`, 20 s, un appel), avec le jeton
du serveur de métadonnées mémorisé jusqu'à son échéance moins 60 s ; aucune dépendance ajoutée.
Filtre construit par le serveur, clause `cloud_run_revision` et `LOG_ID` `stdout` ou `stderr`
toujours en tête ; `severity`, `functionName` (liste fermée `QUERYABLE_FUNCTIONS` de `config.ts`,
égale aux exports de `index.ts` par test), `ticketId`, `freeText` (guillemets et barres obliques
inverses échappés), `periodMinutes` et `pageToken` contrôlés ; 50 entrées par page. Le jeton de
page vaut `<période>|<début ISO>|<jeton de l'API>` : la page suivante rejoue le même filtre, la
période est relue dans la liste fermée, et un début antérieur à maintenant − période − 5 min est
refusé. `payload` et `message` passent par `redactSecrets` avant d'être coupés à 8 000 caractères,
avec `payloadTruncated` et `messageTruncated` calculés sur le texte nettoyé, et la longueur
rendue au client (`maxChars`) ; e-mails visibles (P49). Tests : `functions/test/logs.test.ts`, dont les champs
`ticketId` et `message` écrits par `logging.ts` (P50). Diffs des workflows (P10, P14) :
dans `.github/workflows/ci.yml` et deux fois dans `.github/workflows/deploy.yml`, `queryLogs`
ajouté à la liste des callables du contrôle du manifeste, avec une ligne `jq` qui exige
`maxInstances` 1, `timeoutSeconds` 60 et `concurrency` 1 ; dans les deux `secrets_filter`, une
ligne `jq` refuse tout secret monté par `queryLogs` ; commentaires des contrôles mis à jour
(ADR-011). Réglage à faire avant la fusion : `roles/logging.viewer` sur le projet pour
`tickets-functions` (« Réglages faits une fois », étape 12). Client : Admin › Journaux
(`/admin/journaux`, tuile après « Rapports d'erreur »), `app/lib/features/admin/`
`domain/log_entry.dart`, `data/logs_repository.dart` (`FunctionsLogsRepository`, client des
Functions construit au premier appel, P6), `presentation/logs_screen.dart` ;
`formatJourCourtHeureSecondes` dans `core/presentation/formats.dart` ; `EtatErreur` et
`BandeauListePerimee` acceptent une panne sans « Réessayer » et un bouton désactivé sans
indicateur. L'écran ne recopie aucune borne du serveur : message d'un champ refusé lu dans la
`HttpsError`, longueur coupée lue dans `maxChars` et affichée sous « Message » et sous
« Données ». Un `invalid-argument` sans champ connu s'affiche « Recherche refusée par le
serveur. », sans « Réessayer » ; seul un refus de `pageToken` relit la première page. Une
nouvelle recherche replie toutes les entrées (numéro de recherche dans la clé). Tests : `app/test/logs_test.dart`,
`app/test/formats_test.dart`. Aucun paquet Dart ni npm ajouté ou monté. `main.dart.js`
(`flutter build web --release`) passe de 5 458 499 à 5 499 631 octets (+ 41 132) avant la
fusion de `main` ; mesuré sur `main` à la v0.1.41, avec J1 et J2 : 5 542 375 → 5 600 569 octets
(+ 58 194).

### v0.1.43 — fonctionnel

L'administrateur trouve dans Administration un nouvel écran, « Rapports d'erreur ». Il liste les
pannes rencontrées dans l'application par les membres, de la plus récente à la plus ancienne, 50
à la fois, avec « Charger la suite » pour les précédentes. Chaque ligne donne la date, la partie de
l'application concernée, la version et la plateforme (Android ou Web). Une ligne se déplie sur
l'erreur, son contexte, la pile d'appels et l'identifiant du compte, et « Copier le rapport » copie
le tout. L'écran est en lecture seule : aucun rapport ne se supprime depuis l'application.

### v0.1.43 — technique

ADR-011, lot J1 : Admin › Rapports d'erreur (`/admin/rapports-erreur`, `PageDeCoquille` sous
`/admin`, réservé à l'admin par le routeur). Fichiers ajoutés dans `app/lib/features/admin/` :
`domain/error_report.dart`, `data/error_reports_repository.dart` (`ErrorReportsRepository`,
`FirestoreErrorReportsRepository`, fourni par `errorReportsRepositoryProvider`),
`presentation/error_reports_screen.dart` ; tuile dans `admin_screen.dart`. Lecture de
`error_reports` par `orderBy('created_at', descending: true)`, `limit(50)`, `get()` et
`startAfterDocument`, sans `snapshots()` ni suppression (P50) ; une lecture ou une copie en échec
passe par `reportError`, sans texte de rapport dans `context` (P13). `firestore.rules` est
inchangé ; `rules-tests/test/error_reports.test.mjs` ajoute la requête paginée (page de 50 et
suite) pour les cinq profils de P4. Tests : `app/test/error_reports_test.dart`. Aucune dépendance
ajoutée ni montée. Évolutions du réseau ajoutées avec ADR-011 : `queryLogs` dans la liste fermée de
P25, contrôles P49 (`queryLogs`) et P50 (champs de `logging.ts`, Admin › Journaux, Admin › Rapports
d'erreur), lecture des journaux par l'API REST et `fetch` dans « Règles de code » de `CLAUDE.md`,
note de renvoi dans ADR-008. Seuil `kGrandTexteMinScale` (1,3) ajouté à
`core/presentation/breakpoints.dart`. `main.dart.js` (`flutter build web --release`) passe de
5 431 748 (`main` à la v0.1.40) à 5 458 499 octets (+ 26 751). Admin › Journaux et la callable `queryLogs` viendront
avec le lot J2.
### v0.1.42 — technique

Le déploiement de la v0.1.41 échouait à la publication de `storage.rules` : Firebase ne rend
pas de bucket par défaut pour le projet (404 sur `defaultBucket`). Le bucket existe, en
`us-east1` pour rester dans le niveau gratuit. Il est maintenant nommé partout : `storageBucket` des options Firebase de l'application (sans lui,
`FirebaseStorage.instance` n'avait aucun bucket et le dépôt d'une capture échouait),
`STORAGE_BUCKET` de `functions/src/config.ts` pour `attachTicketScreenshot`, et une copie
`firebase.deploy.json` écrite par `deploy.yml` avec le bucket nommé. `firebase.json` garde la
forme que l'émulateur des tests de règles exige. Aucun paquet ne change.

### v0.1.41 — fonctionnel

Au téléphone, la barre du bas n'affiche plus que les icônes ; un appui long sur une icône donne
son nom. Le menu du compte (votre avatar en haut à droite) est maintenant sur tous les écrans :
éditeurs, import, jour de brassage, Mes prix, Mes processus, Préférences, Nouveautés, Mes tickets.
L'entrée de l'écran où vous êtes n'y figure pas. Quitter un éditeur modifié ou un import en cours
par ce menu demande d'abord confirmation. Sur l'écran du jour de brassage, l'avatar montre votre
initiale, et la déconnexion prévient quand des saisies attendent encore le réseau.

« Signaler ou proposer » reprend l'écran que vous regardiez, et propose de joindre une capture de
cet écran (case décochée). Seuls vous et l'administrateur voyez la capture ; elle n'est jamais
publiée. Sur un écran qui montre vos prix, un avertissement le rappelle, avant la case. Une capture
jointe ne se remplace plus. Elle apparaît dans le suivi du ticket ; si elle ne se lit pas, un
bouton « Réessayer » la recharge, et sans réseau un message le dit. Sur l'écran du jour de
brassage, l'administrateur ouvre « Tickets à traiter » par-dessus l'écran, qui reste allumé ; au
téléphone, la pastille d'envoi passe en icône et nombre pour laisser la place au nom du brassin.

### v0.1.41 — technique

Demandé par les tickets #37, #38 et #39. #37 : `NavigationBar` en `alwaysHide` sous 600 px,
`navigationBarTheme` retiré du thème. #39 : `_AccountMenu` devient `MenuCompte`
(`core/presentation/menu_compte.dart`), posé sur la coquille et les 20 pages pleines, avec
`photo: false` sur l'écran du jour (aucune `NetworkImage`, P2), `avantDeQuitter` et
`avantDeDeconnecter`, entrée de l'écran courant masquée d'après `GoRouterState.of(context).fullPath` ;
`kTicketAccountMenuScreens` donne l'élément `menu/compte` aux pages pleines. #38 : lot T6
d'ADR-008 (note du 2026-11-14) : `ZoneCapture` (`RepaintBoundary`), image gardée en mémoire,
dépôt dans Cloud Storage sous `tickets/{uid}/{ticketId}/screenshot.png`, callable
`attachTicketScreenshot` (`requireMember`, `maxInstances: 2`, `timeoutSeconds: 60`) qui écrit
`screenshot_path`, lecture par `getData` ; `storage.rules` en création seule (`resource == null`), `screenshot.png`
en `image/png` seul, ticket existant de l'auteur (`firestore.get`), callable et client alignés sur
le PNG seul ; rapports d'erreur Storage neutres (`StateError('storage <code>')` côté client,
`errorCode` seul côté serveur), image illisible rapportée `tickets.capture_display` ;
phrase fixe « Capture éventuelle disponible dans Admin › Tickets. » sur chaque Issue. La cause du
`/admin/tickets` signalé n'a pas été reproduite : deux tests de non-régression couvrent une page
ouverte par `push`. Écran du jour : « Tickets à traiter » en `push` (`kEcransDuJour`), pastille
d'envoi compacte sous 400 dp, panneau du haut à 75 % du corps au plus (360 dp, texte à 200 %). Paquets ajoutés à `pubspec.lock` : `firebase_storage` 13.6.0,
`firebase_storage_platform_interface` 6.0.7, `firebase_storage_web` 3.11.13 ; aucune autre version
ne change. `main.dart.js` : 5 417 304 octets avant (#37 et #39 compris), 5 510 208 après. `ci.yml`
et `deploy.yml` : callable ajoutée à la liste fermée, émulateur Storage pour `rules-tests/`,
`storage` au déploiement. `CLAUDE.md` : P5, P6, P14, P23, P24, P25 et P31 modifiés, P48 ajouté.

### v0.1.40 — fonctionnel

L'administrateur peut livrer un ticket depuis sa fiche. Quand la pull request d'un ticket En cours
est prête, CI verte, « Livrer » lance une session Claude Code qui la met à jour, la fusionne et
suit le déploiement. La boîte de confirmation rappelle que la fusion met l'application en ligne
pour tout le groupe. Une seule livraison tourne à la fois. La section « Livraison » de la fiche
montre le compte rendu de la session : terminée, ou arrêtée avec la raison. Si la CI d'une pull
request est en échec, « Relancer le développement » lance une session qui corrige la même
branche. Dans la liste, des pastilles signalent « PR prête », « CI en cours », « Livraison en
cours » et « Correction en cours ».

### v0.1.40 — technique

Lot T5 d'ADR-008. Callable `launchTicketDelivery` (`requireAdmin`, 1 instance, 180 s), par la routine
de développement (secrets `TICKETS_ROUTINE_DEV_*` montés par deux fonctions, aucun secret nouveau) ;
reprise par `launchTicketDevelopment` avec `mode: "resume"` (action `reprise`). `delivery.ts` : PR
unique éligible, fichiers sensibles (liste d'ADR-008 plus `pubspec.lock`, `gradlew`, `**/hook/**`,
`**/.claude/**`, `auth.ts`, `config.ts`, `delivery.ts`, `member_access.json`), CI verte sur `push`
et `pull_request`, verrou global `ticket_status/launches.delivery_running` (3 h), état
`tickets/{id}/admin/delivery` (`ready`, `relaunch_ready`, comptes rendus `## Livraison — …`).
Webhook : `pull_request` et `workflow_run` de `ci.yml`. Refuser et Clore rejetés pendant une
livraison ; `launch_delivery` et `relaunch_development` seulement pour un ticket validé dans
l'application (version de report 5). 403 sur `/actions/runs` en panne à part
(`ci_read_denied_since`), sans `token_invalid_since`. Livraison et reprise comptées au plafond de
`ticket_routine_launch`. Prompt de développement : parties Livraison (L0 à L11) et Reprise (R1 à
R7), à recoller sur claude.ai. `ci.yml` et `deploy.yml` : `launchTicketDelivery` dans la liste
fermée. Contrôles P14, P24, P25, P29, P35, P36, P39 à P42 modifiés, P43 à P47 ajoutés. Aucun
paquet ajouté.

## 2026-11-13

### v0.1.39 — fonctionnel

Dans la liste des brassins, « Prochaine journée » annonce pour vos brassins la même journée que
leur fiche. Une journée faite avant sa date n'est plus annoncée : la suivante prend sa place. Une
journée commencée et pas terminée affiche « en cours ». Une journée dont la date est passée sans
qu'elle soit commencée affiche « en retard », suivi de sa date prévue. Une fois le brassin
embouteillé, seule une journée prévue après l'embouteillage reste annoncée ; sans elle, ou une
fois toutes les journées faites, la ligne reprend la date du brassin. La fiche ne propose plus une
journée placée avant une journée déjà faite. Une journée prévue après l'embouteillage reste
proposée sur la fiche. Les brassins des autres membres, et les vôtres tant que leurs saisies ne sont
pas lues, suivent les dates prévues, comme avant.

### v0.1.39 — technique

La fiche et la liste des brassins choisissent la prochaine journée par une seule fonction,
`prochaineJournee` (`brew_day/domain/plan_du_jour.dart`), qui remplace `_prochaineJournee` de la
fiche : première journée non terminée placée après la dernière journée terminée ; une fois
`bottled_at` posé, seules les journées placées après la journée d'embouteillage, et `null` sans
journée d'embouteillage dans le déroulé. Les deux ne l'appliquent qu'avec des événements lus (`evenementsLus` : une
lecture du cache sans document compte comme non lue). La liste écoute `brews/{id}/events` (cache
compris, aucune transaction) pour les seuls brassins du lecteur En fermentation ou En
conditionnement dont le `process` a au moins deux journées (`listeLitEvenements`), à l'affichage
de leur ligne. Sinon, `prochaineJourneeAnnoncee` garde `prochaineJourneePrevue`, fondée sur les
dates, qui ne cherche plus, après l'embouteillage, que parmi les journées placées après la
journée d'embouteillage. ADR-010 précise que sa limite « la liste ne
lit pas les événements » vaut jusqu'à la v0.1.38. Tests ajoutés dans
`app/test/deroule_d3_test.dart` et `app/test/deroule_d4_test.dart`. Les règles d'accès et les
dépendances ne changent pas.

### v0.1.38 — fonctionnel

L'administrateur peut importer les 16 fiches Excel de brassage depuis Administration › Import.
Il choisit le fichier préparé, relit chaque fiche avec ses points à revoir (divergences,
corrections, heures reprises, coût), puis confirme. Chaque fiche devient une recette et un
brassin terminé, avec sa chronologie, ses mesures et ses relevés de fermentation. Le coût de
chaque brassin est figé avec les prix de sa fiche, visible par l'administrateur seul. Un second
import du même fichier n'écrit rien, et un import interrompu reprend où il s'était arrêté.

### v0.1.38 — technique

Incrément v0.6. `exchange/` : `package:exchange/fiches.dart` lit le format `kassbeer_fiches` v1
(document BeerJSON pour les recettes, bornes de FO4), et `bin/verifier_fiches.dart` le rejoue à
la préparation. Feature `import` : analyse sans écriture, identifiants fixés par le fichier,
marque de fin `imported_from` et empreinte pour la reprise, écritures par lots dans le budget
des règles, arrêt sur 30 s sans accusé du serveur. P9 amendé : Admin › Import lit les prix des
fiches de l'administrateur et ne les écrit que dans `users/{uid}/brew_costs/` ; le lecteur
refuse un montant dans un texte lu par le groupe (code `montant`) et une fiche dont un document
ou un événement appartient à un autre compte. Aucune règle
Firestore ne change ; 25 tests de règles rejouent les écritures d'un import. `.gitignore` limite
`/import/` à la racine, pour versionner `app/lib/features/import/`. Aucun paquet ne change.
`main.dart.js` passe de 5 339 305 à 5 409 676 octets (+ 70 371, main mesuré à la v0.1.37).

### v0.1.37 — fonctionnel

Sur la fiche d'un brassin, le déroulé compare le prévu et le réel. Dès qu'une étape a un début
et une fin, sa ligne donne la durée prévue, la durée réelle et l'écart : « prévu 45 min · réel
57 min · +12 min ». Une étape sautée, en cours ou restée sans heure de fin le dit. Chaque journée
commencée affiche sa durée totale prévue et réelle, avec le temps passé entre les étapes. L'écran
du jour ne change pas.

Après le brassage, « Mettre à jour mon processus avec ce brassin » reprend dans votre processus
les durées réelles que vous cochez. Seules les étapes venues du processus se proposent, quand
leur durée réelle diffère de celle du processus. Pour un houblonnage à cru fait sur plusieurs
journées, vous choisissez la durée d'une des journées. Seules ces durées changent, et vos
brassins gardent leur déroulé. Pendant 10 secondes, « Annuler » rétablit les durées d'avant.

### v0.1.37 — technique

Suite d'ADR-010 : prévu et réel. `brewing/` gagne `actualDurations` (durée réelle d'une étape :
fin retenue moins début retenu de `StepRecord`, jamais `ScheduledStep.end`, arrondie à la minute
la plus proche ; journée du premier début à la dernière fin, temps entre les étapes, étapes en
cours ou sans fin), `durationUpdateIssue` et `roundedStepMinutes`. `fixtures/process.json`
reçoit d'abord 17 cas de durées (dont minuit, le 2026-10-25 et le 2027-03-28), 12 cas de
proposition et 4 arrondis ; P3 de `CLAUDE.md` couvre ces durées. Sur la fiche,
`ChronologieJour` reçoit les durées par un paramètre facultatif que l'écran du jour ne passe
pas ; textes dans `libelles_deroule.dart`. « Mettre à jour mon processus avec ce brassin » lit
`template_step_key` et `template_session_key` (`mise_a_jour_processus.dart`,
`maj_processus.dart`) et réécrit `sessions` par `ProcessesRepository.update` après
`erreurModele`, sans transaction ; seul `duration_min` des étapes choisies change. Un élément de
ticket ajouté (`/brassins/:id/fenetre/maj-processus`). Tests : `app/test/prevu_reel_test.dart`.
Les règles d'accès et les dépendances ne changent pas.

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

