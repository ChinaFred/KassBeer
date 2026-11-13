# Guide du réseau d'agents

Ce document décrit le réseau d'agents livré avec ce dépôt : ce qu'il contient, comment il
démarre, comment il travaille, et comment le faire évoluer. Il se met à jour dans le même
commit que tout changement de `.claude/`, de `scripts/` ou de `CLAUDE.md`.

La CI et le déploiement arrivent avec le socle de l'application (section 7). Pas
d'intégration aux Issues GitHub. Jusque-là, les contrôles tournent sur le poste ou dans la
session, lancés par les agents.

## 1. Vue d'ensemble

```
utilisateur
    │
    ▼
session principale Claude Code ── lit CLAUDE.md, pose les questions, commite
    │
    ├─ démarrage / changement lourd ─▶ architecte (ADR, pile, évolutions du réseau)
    ├─ cadrage ──────────────────────▶ analyste-metier, ux-designer (proposition)
    ├─ implémentation ───────────────▶ developpeur
    ├─ relecture ────────────────────▶ relecteur-regles, ux-designer (revue), securite
    └─ version complète ─────────────▶ product-owner
```

Trois principes :

- **Une source de règles** : `CLAUDE.md`. Les agents le lisent ; aucun autre fichier ne répète
  les règles.
- **Des rôles séparés** : celui qui écrit le code n'est pas celui qui le relit. Les
  relecteurs (`relecteur-regles`, `securite`, `ux-designer`) n'ont aucun outil d'écriture.
- **La session principale décide et commite.** Elle seule parle à l'utilisateur ; un
  sous-agent reçoit un brief et rend un livrable.

## 2. Contenu

```
CLAUDE.md                       règles, chaîne de travail, tableaux à remplir au démarrage
.claude/
├── settings.json               déclaration des deux hooks
├── formatters.json             formateur par type de fichier (rempli au démarrage)
├── version.json                fichier qui porte la version (rempli au démarrage)
├── agents/                     sept agents
├── skills/                     quatre skills
└── hooks/
    ├── session-start.sh        vérifie agents et skills, lance setup-projet.sh s'il existe,
    │                           avertit si l'adresse git n'est pas noreply (ADR-002)
    ├── setup-projet.sh         session cloud : installe Flutter 3.44.6 et les dépendances
    │                           (app, brewing, rules-tests, functions)
    └── format-on-edit.mjs      formate le fichier écrit, selon formatters.json
scripts/
├── changelog-recent.mjs        écrit app/assets/changelog_recent.json (écran « Nouveautés »)
│                               depuis CHANGELOG.md ; relancé par ci.yml et deploy.yml
├── changelog-recent.test.mjs   node --test scripts/changelog-recent.test.mjs
├── check-agents.mjs            vérifie les en-têtes YAML et les noms cités dans CLAUDE.md
├── check-agents.test.mjs       node --test scripts/check-agents.test.mjs
├── check-version.mjs           avant une fusion : version de la branche > version de main
└── check-version.test.mjs      node --test scripts/check-version.test.mjs
documentation/                  modèles de documents, leçons apprises, ce guide
```

### Agents

| Agent | Outils | Rôle |
|---|---|---|
| `architecte` | lecture, recherche web, écriture limitée à `documentation/decisions/` | choix de pile, avis sur changement lourd, évolutions du réseau |
| `analyste-metier` | lecture + écriture (documentation fonctionnelle) | cadrage, critères d'acceptation |
| `ux-designer` | lecture seule | proposition d'écran avant le code, revue après |
| `developpeur` | lecture + écriture | implémentation, documentation technique |
| `relecteur-regles` | lecture seule | treize contrôles génériques + contrôles du projet |
| `securite` | lecture seule | droits, données, entrées, secrets, coûts, exposition |
| `product-owner` | lecture + écriture (documentation) | périmètre, go / no-go |

### Skills

| Skill | Rôle |
|---|---|
| `demarrage-projet` | questionnaire d'intention et de contraintes, appel de l'architecte, application |
| `changement-lourd` | avis de l'architecte avant un changement qui engage le projet |
| `evolution-reseau` | ajouter un contrôle, un agent, un skill ou un hook |
| `logique-dupliquee` | logique client ↔ serveur avec fixture partagée |

## 3. Démarrer un nouveau projet

1. Créer le dépôt du projet à partir d'agent-starter (voir le `README.md` d'agent-starter).
   Le bouton « Use this template » exige la case **Settings › Template repository**, cochée à
   la main sur GitHub.
2. Ouvrir Claude Code dans le dossier, et écrire : « démarre le projet ».
3. Répondre aux questions de la session : intention, utilisateurs, exposition (local, réseau
   protégé, Internet), données, plateformes, coûts.
4. Lire la comparaison de piles de l'`architecte`, trancher ses questions ouvertes, valider.
5. La session remplit `CLAUDE.md`, les formateurs, l'éventuel `setup-projet.sh`, applique les
   contrôles proposés, remplace le `README.md` d'agent-starter par celui du projet, et
   commite la version `0.1.0`.

## 4. Travailler

Toute demande de code suit la « Chaîne de travail » de `CLAUDE.md` : architecture si besoin,
cadrage, implémentation, relecture, version, commit, tag après la fusion et sa CI verte.
Une question reçoit
une réponse, sans modification de fichier.

### Travailler en parallèle

Deux sessions Claude ouvertes dans le même dossier partagent les fichiers, la branche et
l'index Git. Un commit de l'une embarque les fichiers à moitié écrits de l'autre.
`relecteur-regles` lit le diff des deux sessions. Les tests échouent sur un fichier que l'autre
session est en train d'écrire. La seconde de deux commandes Git simultanées échoue sur
`.git/index.lock`.

Une session cloud a déjà son conteneur et sa branche. En local (VS Code, terminal), chaque
session supplémentaire reçoit son propre worktree :

```bash
git worktree add ../<projet>-b -b <branche-b>   # nouveau dossier, nouvelle branche
code ../<projet>-b                              # ouvrir VS Code sur ce dossier, puis Claude
cd ../<projet>-b && claude                      # ou, en terminal
git worktree remove ../<projet>-b               # une fois la branche fusionnée
```

- Les fichiers ignorés par Git (`node_modules/`, `.env`, secrets locaux) ne sont pas copiés :
  réinstaller les dépendances et recopier les secrets dans chaque worktree.
- Deux sessions qui lancent l'application utilisent le même port : la seconde échoue au
  démarrage. Changer le port de l'une.
- Git refuse d'ouvrir la même branche dans deux worktrees.

Avant chaque commit, la session vérifie que `git status` ne liste que ses propres fichiers
(`CLAUDE.md`, « Git »).

Les deux branches peuvent choisir le même numéro de version et ajoutent chacune une entrée en
tête du `CHANGELOG.md`. Deux branches qui passent leurs contrôles séparément peuvent produire
un résultat qui ne compile plus. Avant de fusionner, intégrer la branche principale dans la
branche : `git pull --no-rebase origin <branche-principale>`, ou `git merge
<branche-principale>` sans dépôt distant. Relancer ensuite les contrôles de « Commandes
utiles », `git fetch --tags` et `node scripts/check-version.mjs`, puis fusionner.
`CLAUDE.md` (« Version ») impose la fusion plutôt que le rebase. Le tag `vX.Y.Z` se pose
sur le commit de fusion, après sa CI verte s'il existe un dépôt distant (« Chaîne de
travail », étape 6). Le job `tag` de `deploy.yml` le pose après un déploiement réussi, au
nom de `github-actions[bot]` ; une session cloud ne peut pas pousser de tag (son proxy Git
n'autorise que sa branche). Une branche ne
reçoit pas de tag : si l'autre session fusionne la première, son numéro change.

Une entrée `— fonctionnel` du `CHANGELOG.md` est extraite par `scripts/changelog-recent.mjs`
vers `app/assets/changelog_recent.json`, que l'écran « Nouveautés » affiche. `CLAUDE.md` (« Version ») demande de l'écrire pour le
brasseur, sans chemin de fichier ni numéro d'incrément ; le détail va dans l'entrée
`— technique`.

`check-version.mjs` lit le fichier déclaré dans `.claude/version.json` dans le dernier commit
de la branche (`HEAD`) et sur la branche principale : la plus haute version entre `main` et
`origin/main`, ou la référence passée par `--base <ref>`. Une modification non commitée n'est
pas comparée. Il sort en 1 si le numéro de `HEAD` ne dépasse pas celui de la branche
principale, si le tag `v<numéro>` existe déjà dans le dépôt local, ou si la première entrée
de `CHANGELOG.md` dans `HEAD` porte un autre numéro. Il compare chiffre par chiffre : `0.1.10`
dépasse `0.1.9`. Il lit la clé `version` de premier niveau d'un `.json`, la `version` de la
section `[package]`, `[project]` ou `[tool.poetry]` d'un `.toml`, et la ligne `version:` sans
indentation d'un autre fichier (YAML). Tant que `fichier` est vide dans
`.claude/version.json`, il le dit et sort en 0. Une clé absente ou mal typée le fait échouer.

## 5. Faire évoluer le réseau

L'`architecte` termine chacun de ses avis par des « évolutions du réseau proposées » : un
contrôle de plus pour un relecteur, un skill pour une procédure propre à la pile, un hook.
La session principale les présente ; l'utilisateur choisit ; le skill `evolution-reseau`
les applique. La forme la plus légère est une ligne du tableau « Contrôles propres au
projet » de `CLAUDE.md`, que les relecteurs lisent à chaque relecture.

Un incident qui change une règle s'inscrit dans `lecons-apprises.md`.

Le 2026-11-11, ADR-010 (déroulé en journées) a étendu la règle absolue du hors ligne à chaque
journée du déroulé et la règle « Un brassin fige sa recette » à son déroulé, ajouté le lieu des
modèles (`process_templates/`) aux règles des prix, complété P2, P3 et P5, et ajouté P37 (lecture
du déroulé et découpage par journée, `relecteur-regles`) et P38 (règles des modèles et du champ
`process`, `securite`). P29 à P36 restent réservés à ADR-008. Avec la v0.1.34, P37 permet de
lire la recette figée d'un brassin (`recipe.brewSteps`, `recipe.brewStepsProblem`) comme entrée
d'une nouvelle résolution avant le départ : `assemblerDeroule` et l'aperçu « Chronologie de la
recette seule » par `Deroule.depuisRecette`. Toute autre lecture passe par `Brew.deroule`.

Le 2026-11-11, la ligne « Serveur » de `CLAUDE.md` (« Le projet ») cite ADR-008 : parité des
tickets avec Kass'Dalle, lots T3 à T7.

Le 2026-11-12, avec le lot T3 et l'accord de l'utilisateur, P6, P14, P23, P24, P25 et P26 sont
modifiés et P29 à P34 ajoutés : point d'accès `githubTicketWebhook` signé (P29), garde des
callables (P30), appartenance et rôle rejoués par `test-fixtures/member_access.json` (P31, ligne
de « Logique dupliquée »), relevé et affichage des analyses (P32, P33), « Répondre » (P34).
`ci.yml` et `deploy.yml` remplacent le refus de tout point d'accès HTTP ou callable par la liste
fermée d'ADR-008 (P10, accord de l'utilisateur). Les lots T4 à T7 ajouteront leurs contrôles.

Le 2026-11-13, avec le lot T4 et l'accord de l'utilisateur, P14, P23 (champ serveur
`validated_by_app_at`) et P25 sont modifiés et P35, P36,
P39 à P42 ajoutés (P37 et P38 étaient pris par ADR-010) : appel de l'API Routines (P35), plafond du
poste `ticket_routine_launch` (P36), confirmation d'un lancement (P39), prompts des routines
signalés avant la fusion, avec l'arrêt sur `GIT_COMMITTER_IDENT`, les fichiers sensibles
d'`ingest/` et d'Android et la liste fermée des appels de l'analyse (P40), historique des
lancements (P41), Valider réservé aux tickets analysés et « Lancer le développement » réservé à un
ticket validé dans l'application (P42). La section « Coûts variables » de
`CLAUDE.md` décrit ce premier poste. `ci.yml` et `deploy.yml` ajoutent les deux callables de T4 à la
liste fermée et leurs secrets au contrôle des secrets (P10, accord de l'utilisateur).

Le 2026-11-10, ADR-006 (tickets) a ajouté les contrôles P23 à P27 (règles de `tickets/`, texte
publié sur GitHub, exposition des Functions, publication sans doublon, PR d'un ticket), étendu
P10 (fichiers de `functions/` exécutés par un hook) et P14 (déploiement des Functions sans
exécuter les dépendances de `functions/` dans le job qui détient le jeton Google ; seule
l'installation verrouillée de firebase-tools, sans script, y est permise), et ajouté la section
« Tickets » de `CLAUDE.md`. `formatters.json` formate le TypeScript de `functions/` par
prettier, et `setup-projet.sh` y lance `npm ci`.

Le réseau est copié dans chaque projet, puis il y évolue. Pour reprendre une amélioration
faite dans agent-starter :

```bash
git remote add starter https://github.com/ChinaFred/agent-starter.git
git fetch starter
git diff HEAD starter/main -- .claude scripts   # voir les écarts, puis reprendre à la main
```

## 6. Pièges connus

- **En-tête YAML** : une `description` qui contient « : » se met entre guillemets doubles,
  sinon l'agent disparaît sans message. `check-agents.mjs` le détecte au démarrage.
- **Nouvel agent** : Claude Code ne le charge qu'à la session suivante.
- **Sous-agent** : il ne peut pas poser de question à l'utilisateur. Le questionnaire du
  démarrage est conduit par la session principale.
- **Mémoire automatique** : elle reste sur le poste. Une règle qui doit valoir pour toutes les
  sessions va dans `CLAUDE.md`.
- **Hook** : un hook qui sort en code 2 bloque l'outil. Les deux hooks fournis sortent
  toujours en 0. Le hook de démarrage a un délai de 600 s, pour laisser `setup-projet.sh`
  installer la chaîne d'outils.
- **Agents obligatoires** : `architecte`, `relecteur-regles` et `securite` ne se retirent pas ;
  `check-agents.mjs` signale leur absence.
- **Windows** : les hooks sont en Node ou en bash ; sous Windows, `bash` est celui de Git for
  Windows, pas celui de WSL.

## 7. CI et déploiement de Kass'Beer

ADR-001 retient une CI GitHub Actions, ajoutée avec le socle de l'application. Une session
cloud n'a pas de SDK Android, et seule la CI compile l'APK.

`.github/workflows/ci.yml` tourne sur chaque pull request et chaque push de branche. Quatre
jobs, repris de Kass'Dalle sans les Functions ni le job « déjà testé en PR » : Version et
outillage (`check-version.mjs`, `check-agents.mjs`, tests de `scripts/`), Flutter et
`brewing/` (analyse, format, tests, build web), Règles (émulateur Firestore, Java 21),
Android (compilation de l'APK, clé jetable, quand `app/pubspec.yaml`, `app/pubspec.lock` ou
`app/android/` change). Aucun secret. Une branche qui n'a pas encore incrémenté sa version
est rouge au job Version. Une PR dont la CI n'est pas verte ne se fusionne pas.

`.github/workflows/deploy.yml` part après une CI verte sur un push de `main`, ou à la main
sur `main`. Il déploie Hosting, les règles et les index Firestore, et publie un nouvel APK
sur Firebase App Distribution (groupe `brasseurs`) quand le numéro de build de
`app/pubspec.yaml` dépasse celui de la dernière version publiée. Tant que le projet
Firebase n'est pas configuré dans l'environnement GitHub `production`, il s'arrête en vert
avec l'annonce « Déploiement non configuré ». Détail des jobs, variables, secrets et
commandes Google Cloud : `exigences-techniques.md`, « CI et déploiement ».

Le dépôt est public (ADR-002) : les minutes des runners standard sont gratuites. Le ruleset
de `main` exige les quatre contrôles avant la fusion. Une PR de fork ne lance la CI qu'après
approbation du propriétaire. Une branche avec une PR ouverte tourne deux fois par push
(`push` et `pull_request`). Toute modification de
`.github/workflows/` ou de `scripts/check-version.mjs` se signale à l'utilisateur avant la
fusion (P10). Sur une branche externe (PR d'un fork, ou commit d'un autre auteur que le
propriétaire), un diff d'un fichier qu'un hook exécute se signale aussi : `.claude/**`,
`CLAUDE.md`, `scripts/**`, `rules-tests/package.json`, `rules-tests/package-lock.json`,
`rules-tests/prettier.config.*`, `functions/package.json`, `functions/package-lock.json`,
`functions/prettier.config.*`. Il se lit par `git diff` depuis `main` avant d'ouvrir une
session Claude Code sur la branche. Sinon, `session-start.sh` lancerait `check-agents.mjs`
et `setup-projet.sh`, et `format-on-edit.mjs` lancerait prettier dans `rules-tests/` ou `functions/`. Ces
scripts tournent sur le poste. Le `npm ci` de `setup-projet.sh` ne tourne que dans une
session cloud, sauf si la branche a modifié ce script. `securite` vérifie aussi les workflows (P14) : aucun secret
lisible sur `pull_request`, aucun `pull_request_target`, accès Google Cloud par Workload
Identity Federation, sans clé JSON de compte de service.

Tout ce que le dépôt publie est lisible par tous : fichiers, commits, PR, tags, journaux de
run. `securite` vérifie qu'aucun prénom, nom ou e-mail réel n'y entre (P15) et que chaque
variable que `toJSON(vars)` affiche dans le journal est une valeur publique (P16). Une
valeur sensible va dans les secrets, jamais dans les variables du dépôt ni de
l'environnement.

Depuis l'incrément v0.3 (ADR-003), `relecteur-regles` vérifie deux points de plus. P2 couvre
l'alerte de fin de minuteur : son et vibration ne chargent rien par le réseau, et le verrou
d'écran est pris à l'ouverture de l'écran du jour. P17 couvre tout canal de plateforme :
même nom côté Dart et Kotlin, garde web, erreur rapportée, test Dart du canal, APK compilé.
Un nom de canal mal recopié ne se voit dans aucun test Dart, seulement sur le téléphone.

Depuis l'incrément v0.4 (ADR-004), `relecteur-regles` vérifie P18 : `fl_chart` figé en version
exacte, importé par un seul fichier, couleurs lues dans le thème, résumé pour les lecteurs
d'écran. Ce fichier unique permet de retirer le paquet sans toucher au reste. P1 s'étend à
`deferred as` : un fichier chargé à part exige sa règle `no-cache` et un nouvel ADR.

Depuis la v0.1.15 (ADR-005, livraison L1), `relecteur-regles` vérifie P21 : les recettes et la
copie figée restent en BeerJSON partiel au commit figé, en unités canoniques, sans champ propre
à Kass'Beer dans `recipe`. Les fixtures de `app/test/fixtures/recipe_documents/` passent le
schéma partiel par ajv dans le job « Règles — émulateur ». Le contrôle des règles approche la
limite de Firestore de 1 000 expressions par requête : toute règle ajoutée sur `recipes/` ou
`brews/` est mesurée par le test « budget des règles ». `CLAUDE.md` gagne la règle « Recettes
en BeerJSON partiel ». P19, P20, P22 et les autres évolutions d'ADR-005 arrivent avec L2 à
L4, quand leur code existe.

Depuis la v0.1.20 (L2b d'ADR-005, ADR-007), `securite` vérifie P28 sur le canal de fichiers
`fr.kassbeer/files` : lecture bornée avant tout chargement, nom de fichier exporté sans remontée
de chemin, `FileProvider` limité à `cacheDir/exports/`, aucune permission de stockage, aucun
greffon de fichier sans nouvel ADR. P17 s'étend aux appels qui lisent un fichier ou attendent une
autre activité (hors du thread principal, un seul code de requête, second appel refusé). P9
devient la règle commune des imports (10 Mo, 500 recettes, décodage, lecture typée, aucun prix lu,
caractères de contrôle bidirectionnels retirés) et P3 couvre les conversions Plato, Lovibond et
SRM et les valeurs calculées d'un export. Le paquet `exchange/` entre dans « Structure »,
« Commandes utiles », `.claude/formatters.json` (`dart format`) et `setup-projet.sh`
(`dart pub get`) ; la CI le contrôle dans le job « Flutter et brewing ».

Depuis la v0.1.37 (import des 16 fiches, v0.6), P9 admet une exception : Admin › Import lit les
prix et frais des fiches de l'administrateur, par `package:exchange/fiches.dart`, et ne les écrit
que dans le coût figé de chaque brassin importé (`users/{uid de l'admin}/brew_costs/`). `securite`
vérifie qu'aucun de ces prix n'entre dans `prices`, `fees`, `recipes/`, `brews/`, une note, un
rapport d'erreur ou une annonce.

Depuis la v0.1.29 (ADR-009), `relecteur-regles` applique aussi P17 au canal `fr.kassbeer/prefs`
de la préférence de thème : noms identiques en Dart et en Kotlin, garde `kIsWeb`, travail hors du
thread principal, second appel refusé (`BUSY`) ; le Dart n'envoie qu'un appel à la fois et ne
garde que le dernier choix. Aucun contrôle n'est ajouté.

Depuis la v0.1.21 (L2c), « Le projet » et « Structure » disent que `exchange/` lit et écrit aussi le
BeerXML. Depuis la v0.1.28 (ADR-005, E4), l'export BeerXML de l'écran retrouve son style dans la
Bibliothèque, et P19 couvre la création d'un `import_unresolved` par un membre (E6).

Depuis la v0.1.25 (L3 d'ADR-005, étape 1), l'ingestion des référentiels et des recettes
publiques passe par deux outils du poste : la préparation en Dart
(`exchange/bin/preparer_referentiels.dart`) et l'écrivain Node 24 `ingest/` (Admin SDK).
`CLAUDE.md` reçoit les évolutions d'ADR-005 qui portent sur ce code : l'exception à « Une
écriture de masse sur les données a un seul écran » pour l'ingestion d'une source externe,
`ingest/` dans « Structure », des lignes de « Commandes utiles » pour la préparation et
l'écriture, P10 étendu à `ingest/package.json`, `ingest/package-lock.json` et
`ingest/prettier.config.*`, et trois contrôles : P19 (`securite` : référentiels, recettes
publiques et `ingest_runs` jamais écrits par un client ; depuis la v0.1.28, `import_unresolved`
créé et mis à jour par un membre après un import, liste blanche, `key` normalisée dont le
SHA-256 donne l'identifiant, compte + 1, aucune suppression ; tests des cinq profils), P20 (`relecteur-regles` : aucun fichier ni texte libre d'une source dans le dépôt ou
en base, licence CC BY-SA 4.0 portée dans `provenance[]`) et P22 (`relecteur-regles` : aucun
écouteur ni lecture entière sur `beer_*` ou `public_recipes`). `.claude/formatters.json` lance
prettier sur `ingest/`. `setup-projet.sh` et la CI ne lancent pas encore `ingest/` (ADR-005,
D2) : ses tests tournent en local. P19 ne couvre pas encore `style_stats` (reporté, D1).

Les commandes de lancement de `CLAUDE.md` (« Commandes utiles ») passent
`--dart-define-from-file=firebase.env.json` : la configuration Firebase du client vit dans
ce fichier local, jamais versionné. État de la production et outils du poste :
`exigences-techniques.md`, « État de la production » et « Poste de développement ».

## 8. Exceptions inscrites dans `CLAUDE.md`

- 2026-11-07 : `debugPrint` seul est admis dans deux cas où aucun rapport ne peut partir :
  l'échec de démarrage de Firebase, et un rapport d'erreur impossible à écrire (écriture en
  échec, aucun compte, compte illisible, plafond atteint). Relecture du socle, décision de
  l'utilisateur.
- 2026-11-10 : exception ponctuelle à « Une écriture de masse sur les données a un seul
  écran ». Au passage de L1, `effacement-l1/` efface depuis le poste `recipes/`, `brews/`,
  leurs `events/` et les coûts figés de ces brassins, après un compte rendu sans écriture, une copie dans `import/backup/` et une
  confirmation. L'outil et l'exception sortent à la livraison suivante. ADR-005, décision de
  l'utilisateur.
- 2026-11-11 : exception durable à « Une écriture de masse sur les données a un seul écran ».
  L'ingestion d'une source externe (référentiels, recettes publiques) passe par un script local
  lancé par l'administrateur (`ingest/`) : émulateur par défaut, production sur option
  explicite et confirmation, liste blanche de collections, identifiants déterministes, rapport
  JSON chiffré. Admin › Sources affichera les compteurs et les non résolus (L4). ADR-005,
  évolution acceptée le 2026-11-08.
