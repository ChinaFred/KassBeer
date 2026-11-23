# ADR-020 — Routines des tickets : arrêt du développement distinct de l'analyse, règles du réseau modifiables avec accord lié à la tête de la PR, changement lourd depuis l'écran

- **Statut** : accepté (2026-11-22), décisions de l'utilisateur du 2026-11-22 sur les sept
  questions de l'avis (section « Décisions de l'utilisateur »)
- **Date** : 2026-11-22. Numéro ADR-018 à la rédaction, devenu ADR-020 le 2026-11-23 : `main` avait pris ADR-018 (divers) et ADR-019 (leçon 17) ; contrôles proposés P63 et P64 devenus P65 et P66.
- **Remplace** : —. Modifie ADR-008 sur cinq points : « Prompts » (points 3, 4 et 5 du
  prompt de développement, point 5 du prompt d'analyse, parties « Livraison » L2, L3, L8 et
  L10, et lieu des prompts), « Analyses et « Répondre » » (deux natures d'entrée de plus dans
  `admin/analysis`), « Livraison » (accord des règles du réseau, mode de
  `launchTicketDelivery`, champs de `admin/delivery`, motifs de refus), la liste des fichiers
  interdits à la session de développement (décision 15 du lot T5), et le gabarit des textes
  publiés (P24 : commentaire d'accord). ADR-008 reçoit « Modifié par : ADR-020 ». ADR-002 et
  ADR-006 restent inchangés.

## Contexte

Demande de l'utilisateur, le 2026-11-22 : « Il faut pouvoir faire du lourd depuis l'écran ;
si besoin de l'architecte on l'appelle ; si besoin de modifier CLAUDE.md, avoir un état
particulier qui attire l'attention dessus et demande une autre forme de validation avant de
déployer. »

Trois tickets validés dans Admin › Tickets sont arrêtés avant tout commit (commentaires lus le
2026-11-22 par `gh api`) :

- #110 (retirer la mention « non relu ») : la correction change P55 de `CLAUDE.md`, interdit
  au point 5 du prompt de développement. Arrêt le 2026-11-21 à 21 h 44 (UTC).
- #114 (Nouveautés plus courtes) : la proposition change `scripts/changelog-recent.mjs`, son
  test et la section « Version » de `CLAUDE.md`. Arrêt le 2026-11-21 à 22 h 25.
- #104 (file d'attente des livraisons) : change `CLAUDE.md` (P25, P36, P39, P43, P44, P46) et
  c'est un changement lourd ; le point 4 du prompt arrête la routine. Arrêt à 17 h 05, puis un
  second lancement arrêté à 21 h 43 sur « revalidation nécessaire ».

Le second arrêt de #104 vient d'un défaut du prompt. La routine de développement publie ses
arrêts sous « ## Analyse — compléments » (points 3, 4 et 6, `exigences-techniques.md`,
« Routines des tickets »). Le point 3 prend comme spécification le dernier commentaire du
compte 16348852 qui commence par « ## Analyse », compléments compris, et exige un `validé`
postérieur. Chaque arrêt devient la spécification et rend la validation antérieure. Sur
#104 : `validé` à 16 h 57, arrêt à 17 h 05, relance refusée.

Ce qui existe :

- `functions/src/tickets/analysisModel.ts` relève les commentaires de 16348852 qui commencent
  par `## Analyse` (`analysis`) ou `## Précisions` (`reply`, `unverified_reply`) ; un arrêt y
  entre comme `analysis` et s'affiche parmi les analyses (`section_analyses.dart`).
- `functions/src/tickets/delivery.ts` porte `SENSITIVE_DELIVERY_PATTERNS` (34 motifs, dont
  `scripts/**` et `**/CLAUDE.md`), comparé au bloc L3 du prompt par
  `functions/test/prompts.test.ts`. `deliveryState` calcule `ready` sur la CI seule ; les
  fichiers ne sont contrôlés qu'à l'appel de `launchTicketDelivery`
  (`delivery_sensitive_files`).
- `launchTicketDelivery` monte déjà `GITHUB_TICKETS_TOKEN` (`functions/src/index.ts`,
  ligne 251) : il peut publier un commentaire sans secret nouveau.
- `scripts/changelog-recent.mjs` tourne dans le job `build` de `deploy.yml` (ligne 380), après
  l'écriture du keystore de signature (variables `KEYSTORE_*` du même job).
  `scripts/check-version.mjs` et `scripts/check-agents.mjs` tournent dans `ci.yml` (lignes 78
  à 94) ; `check-agents.mjs` tourne aussi au démarrage de chaque session
  (`.claude/hooks/session-start.sh`). `scripts/garder-apk-en-ligne.sh` tourne dans le job
  `deploy` (ligne 616).
- Le ruleset de `main` demande 0 approbation (ADR-002) ; une fusion déploie seule.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun code ; les trois tickets se font dans une session locale | #110, #114 et #104 restent bloqués depuis l'écran ; chaque arrêt rend la relance impossible sans « Répondre » puis nouvelle analyse | 0 € / 0 € |
| A. Arrêt sous un titre à part, seul | peu de code ; plus aucune revalidation fantôme | les trois tickets restent hors de la routine | 0 € / 0 € |
| B. A, plus règles du réseau permises à la routine, PR fusionnée à la main | aucune livraison automatique d'une PR de règles | la validation se fait hors de l'application | 0 € / 0 € |
| B′. A, plus règles du réseau permises, second accord dans l'application lié à la tête de la PR, puis livraison par la routine (retenue) | tout se fait depuis l'écran ; l'accord nomme les fichiers et les contrôles changés | un commentaire d'accord publié par le serveur, un mode de plus sur `launchTicketDelivery`, liste L3 coupée en deux ; `changelog-recent.mjs` livré par la routine s'exécute à côté du keystore | 0 € / 0 € |
| C. B′, plus avis de l'architecte publié par la routine d'analyse et ADR écrit par la routine de développement (retenue) | débloque #104 et les suivants | une question par tour : K questions coûtent K + 1 lancements d'analyse | 0 € / 0 €, lancements sur l'abonnement Claude |

## Décisions de l'utilisateur (2026-11-22)

1. **Validation d'une PR de règles** : second accord dans l'application, puis livraison par la
   routine (option B′). L'accord est lié au `head_sha` ; un nouveau commit l'annule. La boîte
   liste les fichiers de règles du réseau et les contrôles `Pn` changés. Le serveur publie un
   commentaire d'accord sur gabarit fixe. La liste L3 se coupe en deux.
2. **`scripts/`** : seuls `scripts/changelog-recent.mjs` et `scripts/changelog-recent.test.mjs`
   sont permis à la routine. Tout le reste de `scripts/` reste interdit.
3. **Questions d'un changement lourd** : une par tour d'analyse.
4. **Avis d'architecture** : complet dans l'application ; relevé à 60 000 caractères pour
   « ## Avis d'architecture » seul.
5. **Arrêt du développement** : relance immédiate (`ended_by: "stopped"`).
6. **Prompts** : déplacés dans `documentation/prompts-routines.md`, classé règles du réseau.
7. **Changement lourd refusé** : l'avis reste sur l'Issue seulement ; aucun fichier dans
   `decisions/`.

Ajout du 2026-11-23, décision de l'utilisateur (option 1, sur une anomalie moyenne relevée par
`securite` à la relecture de R2) : le serveur passe la tête de la PR qu'il a relue et contrôlée
dans le texte d'une livraison, dans les deux modes : `livraison #N <tête>` (40 chiffres
hexadécimaux en minuscules). Le motif revérifié avant l'appel (`routine.ts`) n'accepte la tête
que pour la livraison ; analyse, développement et reprise ne changent pas. La routine exige en
L2 que `head.sha` relu soit égal à cette tête, sinon blocage ; en L3b, la ligne `Tête` de
l'accord doit nommer cette même tête, qui est la tête accordée ; L8 s'appuie sur elle. En mode
`deliver`, la tête est celle que le serveur a relue et contrôlée (CI, fichiers).

## Décision

Options B′ et C, en trois lots. L'arrêt d'une session de développement prend un titre qui
n'est jamais une spécification. `CLAUDE.md` à la racine, les deux fichiers de
`changelog-recent` et `documentation/prompts-routines.md` deviennent modifiables par la
routine ; la PR qui les touche porte l'état « Règles du réseau modifiées » et ne se livre
qu'après un accord de l'admin lié à sa tête. Le changement lourd passe par l'agent
`architecte` dans la routine d'analyse ; « Valider » vaut acceptation de l'ADR publié.

### 1. Arrêt du développement (lot R1)

- La routine de développement publie tout arrêt (points 3, 4 et 6 du prompt) dans un
  commentaire qui commence par « ## Développement — arrêt ». Elle ne commence plus jamais un
  commentaire par « ## Analyse ». La reprise reste muette (décision 11 du lot T5).
- Point 3 : la spécification est le dernier commentaire de 16348852 qui commence par
  « ## Analyse » et ne commence pas par « ## Analyse — compléments ». Dans Kass'Beer, seule la
  routine de développement a écrit des compléments : les arrêts déjà publiés sur #104, #110 et
  #114 cessent d'être des spécifications, et leur `validé` redevient valable.
- `analysisModel.ts` relève « ## Développement — arrêt » sous la nature `development_stop`.
  `hasAnalysis` et la reconnaissance d'une réponse ne comptent que `analysis` et les
  réponses. Le client affiche la carte « Arrêt du développement » et retire la ligne de titre
  (`corpsAffiche`). Un APK ancien lit une nature inconnue comme `null` et n'affiche pas
  l'entrée (`TicketAnalysisKind.fromStored`).
- Décision 5 : un arrêt relevé, postérieur au lancement, ramène à l'heure du relevé le
  `retry_after` de l'entrée `developpement` en cours et la marque `ended_by: "stopped"`, comme
  un blocage de livraison (`blockedDeliveryEntries`). Le client lit `ended_by` et affiche
  « s'est arrêté » ; l'admin peut relancer tout de suite.
- Le serveur, le webhook et `syncTickets` ne tirent aucun statut de ce commentaire (P32).

### 2. Règles du réseau, accord lié à la tête de la PR (lot R2)

#### Trois catégories de fichiers

Écrites une seule fois dans `functions/src/tickets/delivery.ts`. Le point 5 du prompt de
développement et les deux blocs L3 du prompt en sont les copies, comparées par
`prompts.test.ts`.

| Catégorie | Fichiers | Session de développement | Livraison par la routine |
|---|---|---|---|
| Interdit (`FORBIDDEN_DEVELOPMENT_PATTERNS`) | liste actuelle du point 5, moins `CLAUDE.md` à la racine et les deux fichiers de `changelog-recent` ; `scripts/**` hors de ces deux fichiers, `**/CLAUDE.md` hors racine, `**/CLAUDE.local.md`, `**/.mcp.json`, `**/.claude/**`, `.github/**` restent interdits | refuse | refuse (`delivery_sensitive_files`) |
| Règles du réseau (`NETWORK_RULES_PATTERNS`) | `CLAUDE.md` (racine seule), `scripts/changelog-recent.mjs`, `scripts/changelog-recent.test.mjs`, `documentation/prompts-routines.md` | permis | après accord seulement (mode `network_rules`) |
| Sensible pour la livraison seule | les trois `pubspec.lock`, `functions/src/auth.ts`, `functions/src/config.ts`, `functions/src/tickets/delivery.ts`, `test-fixtures/member_access.json` (inchangé) | permis | refuse (`delivery_sensitive_files`), fusion à la main |

`SENSITIVE_DELIVERY_PATTERNS` reste l'union des catégories 1 et 3. Le reste de `scripts/`
reste interdit (décision 2) : `check-version.mjs` et `check-agents.mjs` sont les contrôles
que la CI applique à la PR elle-même, `check-agents.mjs` tourne au démarrage d'une session sur
le poste de l'admin, `garder-apk-en-ligne.sh` tourne dans le job `deploy`.

#### État dérivé par le serveur

`readDelivery` lit la liste des fichiers de la PR éligible (10 pages de 100 au plus, comme
`launchTicketDelivery`) à chaque relecture d'un ticket `in_progress` : webhook
(`pull_request`, `workflow_run`), `syncTickets`, `launchTicketDelivery`. `admin/delivery`
reçoit :

| Champ | Contenu |
|---|---|
| `network_rules_files` | chemins de la PR qui relèvent de `NETWORK_RULES_PATTERNS`, 4 au plus (la liste est fermée) |
| `network_rules_controls` | numéros `Pn` des lignes ajoutées ou retirées du tableau « Contrôles propres au projet », lus dans le `patch` de `CLAUDE.md` (lignes qui commencent par `+| P` ou `-| P`, motif `^[+-]\| P([0-9]{1,3}) \|`), sans doublon, triés, 60 au plus |
| `network_rules_controls_complete` | faux si `CLAUDE.md` change et que GitHub ne rend pas son `patch` (fichier trop gros) |
| `sensitive_files` | premier chemin des catégories 1 ou 3, ou `null` |
| `files_complete` | faux si la liste dépasse 1 000 fichiers |
| `network_rules_ack` | dernier accord : `head_sha`, `at`, `ack_id`, `comment_id` (ou `null` tant que la publication n'a pas réussi), `files`, `controls` |
| `network_rules_ack_valid` | vrai si `network_rules_ack.head_sha` égale `head_sha` et que `comment_id` est posé |

Un nouveau commit change `head_sha` et rend `network_rules_ack_valid` faux : l'accord est
annulé, sans écriture de plus. `ready` reste vrai sur une CI verte. Le client lit ces champs.
Il ne recopie ni les motifs, ni la lecture du patch, ni la comparaison des sha.

#### Mode `network_rules` de `launchTicketDelivery`

Aucune callable nouvelle (P25). `launchTicketDelivery` reçoit `mode` : `deliver` (absent vaut
`deliver`) ou `network_rules`, et `headSha` pour le second, 40 chiffres hexadécimaux en
minuscules. Même `requireAdmin`, mêmes `maxInstances: 1` et 180 s, même bail de 210 s, même
secret. Toute autre clé ou valeur est refusée en `invalid-argument` (`details.field`).

Ordre des contrôles en mode `network_rules`, chaque refus en `failed-precondition` avec
« Rien n'a été lancé ni décompté. » et `details.code` :

1. `requireAdmin`, puis `ticketId`, `mode`, `headSha` (`invalid-argument` ; `headSha` présent
   en mode `deliver` refusé).
2. Précondition et bail, aucune reprise en cours, PR éligible unique : comme P43
   (`delivery_no_pr`, `delivery_multiple_prs`, `reprise_running`…).
3. Tête relue sur GitHub égale à `headSha`, sinon `delivery_head_changed` (« La PR a changé
   depuis l'affichage. Relisez-la, puis approuvez à nouveau. »).
4. Liste des fichiers lue en entier, sinon `delivery_files_unreadable`. Un chemin des
   catégories 1 ou 3 : `delivery_sensitive_files`. Aucun chemin de la catégorie 2 :
   `delivery_no_network_rules` (« Cette PR ne change pas les règles du réseau : utilisez
   « Livrer ». »). `CLAUDE.md` changé sans `patch` : `delivery_network_rules_unreadable`
   (« Les contrôles changés ne peuvent pas être lus : fusionnez-la vous-même après
   relecture. »).
5. CI verte sur cette tête (`delivery_ci_not_green`), puis verrou des livraisons (P44,
   `delivery_running_elsewhere`).
6. Accord : dans la transaction du bail, le serveur tire `ack_id` et écrit
   `network_rules_ack` sans `comment_id`. Il publie le commentaire d'accord, après
   reconnaissance d'un commentaire de 16348852 qui porte déjà la ligne `Accord <ack_id>`
   (P26). Puis il écrit `comment_id`. Échec de publication : `delivery_ack_publish_failed`,
   verrou rendu, rien compté ; l'accord sans `comment_id` reste invalide.
7. Plafond (P36), entrée `livraison` `unknown`, appel unique de la routine avec
   `livraison #N <tête>`, la tête relue et contrôlée par le serveur (ajout du 2026-11-23) ;
   la routine lit l'accord sur l'Issue.

En mode `deliver`, une PR qui touche la catégorie 2 est refusée en `delivery_network_rules`
(« Cette PR change les règles du réseau : utilisez « Approuver les règles et livrer ». »),
sans décompte.

Gabarit du commentaire d'accord, fixe, sans aucun texte venu de la PR ni de l'Issue :

```text
## Accord — règles du réseau

PR #<M>
Tête <head_sha>
Fichiers : <chemins de network_rules_files, séparés par « , »>
Contrôles : <Pn séparés par « , », ou « aucun »>

Accord <ack_id>
```

Les chemins viennent de la liste fermée de la catégorie 2 ; `ack_id` est tiré par le serveur
(motif `^[A-Za-z0-9]{20}$`). Le commentaire n'est relevé ni comme analyse ni comme compte
rendu de livraison.

#### Écran

- Liste et section « Livraison » : étiquette « Règles du réseau modifiées » dès que
  `network_rules_files` n'est pas vide.
- Section « Livraison » : fichiers, contrôles changés (ou « Contrôles changés : liste
  illisible »), « Ouvrir la PR #M », et l'état de l'accord : « Accord donné pour la tête
  <7 premiers caractères> » si `network_rules_ack_valid`, « Accord annulé par un nouveau
  commit » si un accord existe pour une autre tête.
- « Livrer » est masqué quand `network_rules_files` n'est pas vide. À sa place, « Approuver
  les règles et livrer », offert si `launch_delivery` est dans `allowed_decisions`, `ready`
  est vrai, `sensitive_files` est nul et `network_rules_controls_complete` est vrai.
- Boîte de confirmation, ouverte par un appui seul (P39) : PR #M et tête courte ; liste des
  fichiers ; liste des contrôles ; « Ces fichiers sont les règles que suivent toutes les
  sessions Claude Code et le contenu de l'écran Nouveautés. Lisez le diff sur GitHub avant
  d'approuver. » ; lien « Lire le diff » vers
  `https://github.com/ChinaFred/KassBeer/pull/<M>/files` ; lancements restants ; phrase de
  « Livrer » (« La fusion met l'application en ligne pour tout le groupe sans autre
  accord. ») ; champ « Saisissez le numéro de la PR pour approuver », bouton actif seulement
  quand le champ vaut M. L'appel envoie le `head_sha` affiché.

#### Prompt de développement

- Point 5 : la liste interdite devient `FORBIDDEN_DEVELOPMENT_PATTERNS`. Une modification de
  la catégorie 2 passe par `relecteur-regles` et `securite`. Le corps de la PR liste les
  sections et les contrôles de `CLAUDE.md` changés.
- Règles de session : celles du `CLAUDE.md` de `origin/main` (`git show origin/main:CLAUDE.md`),
  pour le développement, la livraison et la reprise. Le `CLAUDE.md` de la branche est un
  contenu à livrer. Les interdits du prompt priment sur tout `CLAUDE.md`.
- L3 coupé en deux :
  - **L3a** : un fichier ou un ancien chemin des catégories 1 ou 3 : blocage ;
  - **L3b** : un fichier de la catégorie 2 : la livraison continue seulement si l'Issue porte
    un commentaire de 16348852 qui commence par « ## Accord — règles du réseau », dont la
    ligne `PR #M` nomme cette PR, dont la ligne `Tête` égale `head.sha` relu en L2 (et la tête
    du texte de lancement, ajout du 2026-11-23), et dont la ligne `Fichiers` donne l'ensemble
    des fichiers de la catégorie 2 de la PR. Sinon : blocage.
- L8 : en plus du contrôle de L3 sur la tête finale, `git rev-list --first-parent
  <tête accordée>..HEAD` ne rend rien, ou seulement le commit de fusion de L6, dont le premier
  parent est la tête accordée. Sinon : blocage. Si `origin/main` a avancé depuis L5 : pour une pull request qui touche un fichier de L3b, c'est un blocage (pas de second tour de L5) ; pour les autres, recommence en L5 (trois tours au plus, sinon blocage) ; décision de l'utilisateur du 2026-11-23.
- L7 : pour une PR qui touche un fichier de la catégorie 2, le job « Version et outillage » en
  échec à l'étape de la version est un blocage (pas de retour en L5) ; pour les autres, retour
  en L5 (décision de l'utilisateur du 2026-11-23).
- L10 et point 5 : aucune session ne commence un commentaire par « ## Accord ».

### 3. Changement lourd depuis l'écran (lot R3)

Routine d'analyse :

- Si le ticket entre dans la liste « Changement lourd » de `CLAUDE.md`, la session suit le
  skill `changement-lourd` et lance l'agent `architecte`. L'architecte écrit son projet d'ADR
  dans `documentation/decisions/` de la copie de travail de la session, au statut « proposé ».
  Rien n'est commité ni poussé.
- La session publie d'abord un commentaire « ## Avis d'architecture » : avis, options, coût,
  texte complet du projet d'ADR, évolutions du réseau proposées, 60 000 caractères au plus
  (GitHub accepte 65 536, à vérifier). Puis son « ## Analyse », qui renvoie à l'avis.
- Décision 3 : l'analyse pose une seule question, avec son contexte, ses options, leur effet
  et leur coût, et la recommandation, sous la ligne fixe « Question à trancher : <i> sur
  <K> ». L'admin répond par « Répondre » ; le ticket revient à `received` ; un nouveau
  « Lancer l'analyse » publie l'avis mis à jour et la question suivante. Sans question
  restante, l'analyse porte la ligne fixe « Questions ouvertes : aucune ».
- Décision 4 : `analysisModel.ts` relève « ## Avis d'architecture » sous la nature
  `architecture`, la plus récente seule, coupée à 60 000 caractères ; les autres natures
  restent à 20 000. L'application affiche l'avis complet dans une carte « Avis
  d'architecture ». Le serveur écrit dans `admin/analysis` le booléen
  `architecture_in_last_analysis` : un avis existe entre l'analyse précédente et la dernière.

Constat de la décision, sans texte non fiable : l'appui sur « Valider », constaté par
`validated_by_app_at` (écrit par `validateTicket`) et l'événement `labeled` `validé` d'acteur
16348852, postérieur à l'avis et à l'analyse. Quand `architecture_in_last_analysis` est vrai,
la boîte de « Valider » ajoute : « Valider accepte aussi le projet d'ADR publié et les choix
de l'analyse. Le développement écrira l'ADR au statut accepté. » Les réponses de l'admin sont
ses « ## Précisions de l'administrateur », citées dans l'analyse (prompt d'analyse, point 5).

Routine de développement :

- Le point 4 n'arrête plus sur un changement lourd si l'analyse validée suit un
  « ## Avis d'architecture » et porte « Questions ouvertes : aucune ». Sinon, arrêt sous
  « ## Développement — arrêt » (« changement lourd sans avis d'architecture validé »).
- La session écrit l'ADR depuis le texte de l'avis, au statut « accepté (date du `validé`),
  décision de l'utilisateur par Valider, ticket #N », applique les évolutions du réseau que
  l'avis propose et que l'analyse retient, puis suit la « Chaîne de travail » à l'étape 1.
  L'architecte n'écrit toujours que dans `documentation/decisions/` ; la routine, session
  principale, change le statut, comme le skill `changement-lourd` le prévoit.
- Une évolution qui touche la catégorie 1 (`.claude/**`, `.github/**`, autre script) reste
  interdite : la session l'écrit dans le corps de la PR, et l'admin l'applique dans une
  session à lui.
- Un ADR change presque toujours « Le projet » de `CLAUDE.md` : la PR prend l'état « Règles du
  réseau modifiées » et passe par l'accord. Un numéro d'ADR déjà pris sur `main` au moment de
  la livraison est un blocage (L5 ne résout que deux conflits) ; l'admin renumérote.
- Décision 7 : un changement lourd refusé (« Refuser ») n'écrit aucun fichier dans
  `decisions/`. L'avis publié sur l'Issue reste la trace. C'est un écart au skill
  `changement-lourd` (« l'ADR proposé passe au statut rejeté »), écrit dans ce skill.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : relevé des commentaires, lecture des fichiers et du
   patch, accord et état de livraison dans `functions/` (webhook, `syncTickets`,
   `launchTicketDelivery`). Affichage dans `app/lib/features/tickets/`. Avis, ADR, code et
   fusion dans les sessions Claude Code chez Anthropic.
2. **Ce qui existera en double** : les trois catégories vivent dans `delivery.ts` et dans le
   prompt, comparées par `prompts.test.ts` (ligne du tableau « Logique dupliquée » étendue).
   Le gabarit de l'accord est écrit par le serveur et lu par le prompt, comparé par un test qui
   lit le bloc L3b. Le client ne recopie aucune liste ni règle.
3. **Ce qui pèse au démarrage** : rien. `fetch` seul, aucune dépendance.
4. **Compilation de chaque cible** : aucun paquet ajouté. Commandes inchangées.
5. **Qui voit quoi** : avis, ADR proposés et accords sont publics sur l'Issue (ADR-002) : ni
   nom, ni e-mail, ni prix. Les champs nouveaux de `admin/delivery` et `admin/analysis` sont
   lus par l'admin seul (règles actuelles de `admin/{doc}`). Aucun titre ni corps de PR écrit
   dans Firestore ; du patch de `CLAUDE.md`, seuls les numéros `Pn` sont gardés.
6. **Ce qui coûte à l'usage, plafond** : poste `ticket_routine_launch` inchangé. Un
   changement lourd à K questions coûte K + 1 lancements d'analyse et un de développement,
   dans le plafond de 10 par jour (50 pour le fondateur). Une livraison avec accord compte un
   lancement, comme « Livrer ». Lectures GitHub en plus : la liste des fichiers d'une PR
   éligible par relecture, une dizaine d'appels par heure au plus.
7. **Exposition** : aucun point d'accès, secret ni rôle nouveau. Surfaces nouvelles : un
   texte d'Issue non fiable peut pousser l'analyse à proposer d'affaiblir une règle, et une
   PR de règles part en ligne sans fusion humaine. Protections : validation de l'analyse,
   accord lié à la tête avec les `Pn` affichés et la saisie du numéro, annulation par tout
   nouveau commit, contrôle L8 des commits ajoutés, interdits du prompt qui ne changent que
   par un recollage à la main sur claude.ai.
8. **Exploitation** : prompts recollés à R1, R2 et R3. Rien à sauvegarder de plus.
9. **Coût de sortie** : faible. Revenir en arrière remet la catégorie 2 dans les interdits,
   retire le mode `network_rules` et deux natures d'entrée.

## Conséquences

Plus simple : #110 et #114 se développent et se livrent depuis l'écran après R2 ; #104 après
R3, en commençant par « Répondre » (retour à `received`) puis « Lancer l'analyse ». Un arrêt
ne bloque plus la relance.

Plus difficile : la routine change les règles que suivront les sessions suivantes, et
l'admin doit lire un diff sur GitHub avant chaque accord. Les prompts des routines restent la
borne : leur texte ne change que par un recollage.

Risque accepté par l'utilisateur (décision 1) : `scripts/changelog-recent.mjs` modifié par une
routine et livré après accord s'exécute dans le job `build` de `deploy.yml`, à côté du
keystore. La lecture du diff avant l'accord est la protection.

`CLAUDE.md` change : « Tickets », « Chaîne de travail » (étape 0 depuis une routine),
« Logique dupliquée », P10, P24, P25, P32, P33, P39, P40, P43, P44, P45, et deux contrôles
nouveaux (P65, P66). `exigences-techniques.md` : `admin/analysis`, `admin/delivery`, mode de
`launchTicketDelivery`, renvoi vers `documentation/prompts-routines.md`. `guide-reseau.md` :
routines et changement lourd.

## Évolutions du réseau

Acceptées avec l'ADR (2026-11-22). La session principale les applique par le skill
`evolution-reseau`, au lot indiqué.

```
[contrôle] P32 (securite), R1 et R3 — ajout — arrêt pris pour une analyse ; avis tronqué — après « (`analysis`) » : « ou `## Développement — arrêt` (`development_stop`), ou `## Avis d'architecture` (`architecture`, la plus récente seule, 60 000 caractères ; les autres natures à 20 000) » ; en fin : « `hasAnalysis` et la reconnaissance d'une réponse ne comptent que `analysis` et les réponses ; un arrêt relevé après le lancement ramène le `retry_after` de l'entrée `developpement` à l'heure du relevé (`ended_by: "stopped"`) ; `architecture_in_last_analysis` écrit par le serveur seul ; « ## Accord — règles du réseau » n'est relevé ni comme analyse ni comme compte rendu »
```
```
[contrôle] P33 (securite), R1 et R3 — ajout — titre affiché ; nature inconnue en erreur — « titres `## Développement — arrêt` et `## Avis d'architecture` retirés à l'affichage ; avis affiché en entier ; nature inconnue ignorée sans erreur »
```
```
[contrôle] P24 (securite), R2 — ajout — texte non fiable dans un commentaire publié — « commentaire d'accord sur gabarit fixe (`## Accord — règles du réseau`, `PR #M`, `Tête <sha de 40 caractères>`, `Fichiers :` pris dans `NETWORK_RULES_PATTERNS` seuls, `Contrôles :` en numéros `Pn` seuls ou « aucun », ligne `Accord <ack_id>`) ; aucun texte de la PR ni de l'Issue »
```
```
[contrôle] P25 (securite), R2 — précision — point d'accès ajouté pour l'accord — « `launchTicketDelivery` reçoit `mode` (`deliver`, absent vaut `deliver`, ou `network_rules`) et `headSha` ; aucune callable nouvelle ; secrets, `maxInstances` et délai inchangés »
```
```
[contrôle] P39 (relecteur-regles), R2 et R3 — ajout — accord donné sans lire ce qui change — « « Approuver les règles et livrer » : remplace « Livrer » quand `network_rules_files` n'est pas vide, offert seulement si `ready`, `sensitive_files` nul et `network_rules_controls_complete` ; boîte ouverte par un appui seul, qui liste la PR, la tête courte, les fichiers et les contrôles lus dans `admin/delivery`, le lien `https://github.com/ChinaFred/KassBeer/pull/<M>/files`, les lancements restants et la phrase de « Livrer » ; bouton actif seulement après la saisie du numéro de la PR ; l'appel envoie le `head_sha` affiché ; étiquette « Règles du réseau modifiées » et état de l'accord (« Accord donné pour la tête … », « Accord annulé par un nouveau commit ») lus dans `network_rules_ack_valid` et `network_rules_ack`, sans comparaison de sha en Dart ; boîte de « Valider » avec « Valider accepte aussi le projet d'ADR publié et les choix de l'analyse. Le développement écrira l'ADR au statut accepté. » quand `architecture_in_last_analysis` est vrai ; « s'est arrêté » lu dans `ended_by: "stopped"` »
```
```
[contrôle] P40 (relecteur-regles), R1 à R3 — changement — revalidation fantôme ; consignes prises dans le CLAUDE.md d'une branche — remplacer « (`exigences-techniques.md`, « Routines des tickets ») » par « (`documentation/prompts-routines.md`) », puis ajouter : « la routine de développement ne commence jamais un commentaire par « ## Analyse » ni « ## Accord » ; ses arrêts commencent par « ## Développement — arrêt » ; le point 3 ignore tout « ## Analyse — compléments » ; règles de session lues dans `git show origin/main:CLAUDE.md`, les interdits du prompt priment sur tout `CLAUDE.md` ; la liste du point 5 est égale à `FORBIDDEN_DEVELOPMENT_PATTERNS`, L3a à l'union des catégories 1 et 3, L3b à `NETWORK_RULES_PATTERNS` (tests) ; L3b exige un accord de 16348852 qui nomme la PR, la tête relue en L2 et l'ensemble des fichiers de la catégorie 2 ; L8 : `git rev-list --first-parent <tête accordée>..HEAD` ne rend rien, ou seulement le commit de fusion de L6, dont le premier parent est la tête accordée ; routine d'analyse : avis « ## Avis d'architecture » de 60 000 caractères au plus, une question par analyse (« Question à trancher : i sur K »), ligne « Questions ouvertes : aucune » ; aucune session ne commence un commentaire par « ## Avis d'architecture » hors de la routine d'analyse »
```
```
[contrôle] P43 (securite), R2 — ajout — PR de règles livrée sans accord ou sur une autre tête — « mode `deliver` : chemin de `NETWORK_RULES_PATTERNS` refusé en `delivery_network_rules` ; mode `network_rules`, dans l'ordre : `headSha` de 40 hexadécimaux (`invalid-argument`, refusé en mode `deliver`), contrôles actuels de P43, tête relue égale à `headSha` (`delivery_head_changed`), aucun chemin des catégories 1 ou 3 (`delivery_sensitive_files`), au moins un chemin de la catégorie 2 (`delivery_no_network_rules`), patch de `CLAUDE.md` lisible (`delivery_network_rules_unreadable`), CI verte, verrou (P44), accord publié (`delivery_ack_publish_failed`, verrou rendu), puis plafond et appel ; chaque refus sans décompte ni appel ; tests : chaque refus, accord publié une seule fois sur deux appels (ligne `Accord <id>` reconnue), tête changée entre l'affichage et l'appel refusée, PR qui touche `CLAUDE.md` et `functions/src/auth.ts` refusée en `delivery_sensitive_files`, `docs/CLAUDE.md` refusé, `scripts/check-version.mjs` refusé, `scripts/changelog-recent.mjs` accepté après accord »
```
```
[contrôle] P44 (securite), R2 — ajout — verrou tenu par un accord jamais publié — « en mode `network_rules`, verrou pris avant la publication de l'accord et rendu si elle échoue ; un accord sans `comment_id` ne vaut rien ; test : publication en échec, verrou rendu, rien compté »
```
```
[contrôle] P45 (securite), R2 — ajout — état recopié en Dart ; texte de PR en base — « champs `network_rules_files` (4 au plus), `network_rules_controls` (numéros `Pn` seuls, 60 au plus, motif `^[+-]\| P([0-9]{1,3}) \|` sur le patch de `CLAUDE.md`), `network_rules_controls_complete`, `sensitive_files`, `files_complete`, `network_rules_ack` (`head_sha`, `at`, `ack_id`, `comment_id`, `files`, `controls`), `network_rules_ack_valid` (vrai seulement si la tête égale celle de l'accord et que `comment_id` est posé) ; aucune autre ligne du patch gardée ; un nouveau commit annule l'accord sans écriture de plus ; tests : accord valide, accord annulé par une nouvelle tête, patch absent »
```
```
[contrôle] P10 (relecteur-regles), R2 — ajout — règles du réseau changées sans le signaler — « une PR de ticket qui touche `NETWORK_RULES_PATTERNS` est signalée à l'utilisateur dans toute session qui la relit ; `documentation/prompts-routines.md` rejoint la liste des fichiers dont le diff est signalé »
```
```
[contrôle] P65 (relecteur-regles), R2, nouveau — catégories incohérentes entre serveur et prompt — « `functions/src/tickets/delivery.ts` porte seul `FORBIDDEN_DEVELOPMENT_PATTERNS`, `NETWORK_RULES_PATTERNS` (`CLAUDE.md` à la racine, `scripts/changelog-recent.mjs`, `scripts/changelog-recent.test.mjs`, `documentation/prompts-routines.md`) et `SENSITIVE_DELIVERY_PATTERNS` (union des catégories 1 et 3) ; le point 5, L3a et L3b du prompt de développement en sont les copies, égalités rejouées par `functions/test/prompts.test.ts`, avec le gabarit d'accord ; tout autre fichier de `scripts/` reste interdit à la routine ; une extension de `NETWORK_RULES_PATTERNS` demande un ADR ; le corps d'une PR de règles liste les sections et les contrôles de `CLAUDE.md` changés » | ADR-020
```
```
[contrôle] P66 (securite), R3, nouveau — décision d'architecture tirée d'un texte non fiable — « changement lourd depuis l'écran : avis publié par la routine d'analyse seule sous « ## Avis d'architecture » ; une question par analyse ; la routine de développement n'écrit un ADR « accepté » que si l'analyse validée suit l'avis, porte « Questions ouvertes : aucune », et si le `validé` d'acteur 16348852 est postérieur aux deux ; une évolution du réseau qui touche un fichier interdit est écrite dans le corps de la PR, jamais appliquée ; un refus n'écrit rien dans `decisions/` » | ADR-020
```
```
[règle] CLAUDE.md « Logique dupliquée », R2 — ligne remplacée — divergence entre listes du prompt et du serveur — | point 5, L3a, L3b et gabarit d'accord de `documentation/prompts-routines.md` | fichiers interdits à la routine, règles du réseau, sensibles pour la livraison, accord | prompt de la routine de développement | `functions/src/tickets/delivery.ts` (`FORBIDDEN_DEVELOPMENT_PATTERNS`, `NETWORK_RULES_PATTERNS`, `SENSITIVE_DELIVERY_PATTERNS`, gabarit d'accord), égalités rejouées par `functions/test/prompts.test.ts` |
```
```
[règle] CLAUDE.md « Tickets », R2 — ajout — PR de règles livrée sans lecture — « Une PR de ticket qui modifie `CLAUDE.md`, `scripts/changelog-recent.mjs`, son test ou `documentation/prompts-routines.md` porte l'état « Règles du réseau modifiées ». Elle ne part que par « Approuver les règles et livrer », après lecture du diff sur GitHub ; l'accord vaut pour la tête affichée, et un nouveau commit l'annule. »
```
```
[skill] changement-lourd, R3 — section « Depuis une routine » — décision prise sans l'utilisateur — « Dans la routine d'analyse, l'architecte écrit dans `decisions/` de la copie de travail ; rien n'est commité. La session publie « ## Avis d'architecture », puis une seule question dans « ## Analyse ». L'accord est l'appui sur « Valider ». La routine de développement écrit l'ADR au statut accepté. Un refus laisse l'avis sur l'Issue comme seule trace, sans fichier « rejeté » (ADR-020, décision 7). »
```

## Lots

Ordre : R1, puis R2, puis R3. Les trois lots touchent des fichiers que la routine ne peut pas
modifier ou livrer au moment où ils partent : ils se font dans une session de l'admin.

| Lot | Fichiers touchés | Par qui | Raison |
|---|---|---|---|
| R1 — arrêt du développement | `functions/src/tickets/analysisModel.ts`, `functions/src/tickets/launchModel.ts` et `sync.ts` (`ended_by: "stopped"`), `functions/test/analysis.test.ts`, `launch.test.ts`, `prompts.test.ts` ; `app/lib/features/tickets/domain/ticket_analysis.dart`, `ticket_launch.dart`, `presentation/section_analyses.dart`, leurs tests ; prompt de développement dans `exigences-techniques.md` (recollé sur claude.ai) ; `CLAUDE.md` (P32, P33, P40) ; `CHANGELOG.md`, `app/pubspec.yaml` | session de l'admin | `CLAUDE.md` est encore interdit à la routine |
| R2 — règles du réseau et accord | `functions/src/tickets/delivery.ts` (trois catégories, champs, gabarit), `launch.ts` (mode `network_rules`), `functions/src/index.ts` (commentaire seul), `functions/test/delivery.test.ts`, `launch.test.ts`, `prompts.test.ts` ; `app/lib/features/tickets/domain/ticket_delivery.dart`, section « Livraison », liste, boîte « Approuver les règles et livrer », tests ; `documentation/prompts-routines.md` créé, prompts retirés de `exigences-techniques.md` ; `CLAUDE.md` (P10, P24, P25, P39, P40, P43, P44, P45, P65, « Logique dupliquée », « Tickets ») ; `guide-reseau.md` | session de l'admin | `delivery.ts` est sensible pour la livraison, et le lot crée la catégorie 2 elle-même |
| R3 — changement lourd depuis l'écran | `functions/src/tickets/analysisModel.ts` et `analyses.ts` (nature `architecture`, 60 000 caractères, `architecture_in_last_analysis`), `functions/test/analysis.test.ts`, `prompts.test.ts` ; `app/lib/features/tickets/` (carte « Avis d'architecture », boîte de « Valider »), tests ; `documentation/prompts-routines.md` (deux prompts recollés) ; `.claude/skills/changement-lourd/SKILL.md` ; `CLAUDE.md` (P32, P33, P39, P40, P66, « Chaîne de travail ») ; `guide-reseau.md` | session de l'admin | `.claude/**` reste interdit à la routine |

Estimations non mesurées : R1, 160 à 280 lignes ; R2, 800 à 1 200 lignes ; R3, 180 à 320
lignes, surtout du texte de prompt. Après R2, les tickets dont la PR ne touche que la
catégorie 2 se livrent depuis l'écran ; #110 et #114 se relancent par « Lancer le
développement », sans revalidation.

## Sources

- Commentaires de #104, #110 et #114 : `gh api repos/ChinaFred/KassBeer/issues/<n>/comments`,
  lus le 2026-11-22.
- Taille maximale d'un commentaire GitHub, 65 536 caractères : à vérifier.
- Taille du `patch` rendu par `GET /pulls/{n}/files` (absent au-delà d'une limite) : à
  vérifier.
- Kass'Beer : `functions/src/tickets/analysisModel.ts`, `delivery.ts`, `decisionModel.ts`,
  `launchModel.ts`, `functions/src/index.ts` (secrets de `launchTicketDelivery`, ligne 251),
  `app/lib/features/tickets/domain/ticket_analysis.dart`, `.github/workflows/deploy.yml`
  (lignes 330 à 400, 616), `.github/workflows/ci.yml` (lignes 78 à 94),
  `.claude/hooks/session-start.sh`, `exigences-techniques.md` lignes 5130 à 5500.
