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
travail », étape 6). Une branche ne
reçoit pas de tag : si l'autre session fusionne la première, son numéro change.

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
`rules-tests/prettier.config.*`. Il se lit par `git diff` depuis `main` avant d'ouvrir une
session Claude Code sur la branche. Sinon, `session-start.sh` lancerait `check-agents.mjs`
et `setup-projet.sh`, et `format-on-edit.mjs` lancerait prettier dans `rules-tests/`. Ces
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

Les commandes de lancement de `CLAUDE.md` (« Commandes utiles ») passent
`--dart-define-from-file=firebase.env.json` : la configuration Firebase du client vit dans
ce fichier local, jamais versionné. État de la production et outils du poste :
`exigences-techniques.md`, « État de la production » et « Poste de développement ».

## 8. Exceptions inscrites dans `CLAUDE.md`

- 2026-11-07 : `debugPrint` seul est admis dans deux cas où aucun rapport ne peut partir :
  l'échec de démarrage de Firebase, et un rapport d'erreur impossible à écrire (écriture en
  échec, aucun compte, compte illisible, plafond atteint). Relecture du socle, décision de
  l'utilisateur.
