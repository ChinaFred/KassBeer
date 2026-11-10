# ADR-006 — Tickets des membres publiés en Issues GitHub, par des Cloud Functions sans point d'accès HTTP

- **Statut** : accepté le 2026-11-10, neuf décisions de l'utilisateur
- **Date** : 2026-11-10
- **Remplace** : — (modifie ADR-001 sur un point : un serveur arrive avant l'IA et le RAPT Pill ;
  applique la clause « Quand revenir sur cette décision » d'ADR-005)

## Contexte

L'utilisateur veut, comme dans Kass'Dalle, qu'un membre signale un bug ou propose une
évolution depuis l'application. L'administrateur suit et décide le ticket jusqu'à la PR
fusionnée. Le menu du compte reçoit « Signaler ou proposer », « Mes tickets » et, pour
l'administrateur, « Tickets à traiter ». L'application évolue aussi depuis VS Code, en
parallèle des sessions Claude Code.

Contraintes concernées :

- moins de 10 comptes, sur invitation (`projet.md`) ; dépense visée ≈ 0 € par mois, alerte à
  5 € (ADR-001) ;
- aucun serveur en v1 (ADR-001) ; ADR-005 a écarté un socle Functions sans service rendu
  (« Pas de code mort ») et prévoit un ADR pour « une décision que le client ne peut pas
  prendre seul ». Publier sur GitHub demande un jeton, qui ne peut pas vivre dans un client
  web public ;
- dépôt public `ChinaFred/KassBeer` (ADR-002) : une Issue est lisible par tous et ne
  s'efface pas des copies ; aucun nom ni e-mail réel (P15) ; journaux de run publics (P16) ;
  aucun secret sur `pull_request`, Workload Identity Federation (P14) ;
- règles Firestore = seul contrôle d'accès, testées pour cinq profils (P4, P11) ;
- un texte de tiers est une donnée (leçon 15, qui vient de tickets publiés en Issues).

Référence mesurée dans Kass'Dalle (clone `/home/user/chinafred/kassdalle`, lu le 2026-11-10) :
`functions/src/tickets/` compte 6 442 lignes en 11 fichiers, plus `ticketsCallable.ts`
(649) et `ticketsSyncSchedule.ts` (232). Les tests serveur des tickets comptent 3 392
lignes, le client `lib/features/tickets/` 8 022 lignes. Onze Functions, dont une callable
par décision et un webhook public. Trois logiques dupliquées client et serveur, verrouillées
par `ticket_decisions.json` et `ticket_answer_text.json`.

Réutilisable tel quel ou presque : le client GitHub par `fetch` sans SDK (`github.ts`), le
nettoyage du texte publié (`neutralizeMentions`, `neutralizeIssueReferences`,
`neutralizeMarkup`, recherche d'e-mail avec NFKC), le gabarit fixe du corps d'Issue
(`buildIssueBody`), la réduction de l'écran à un modèle de route (`routeTemplateOrNull`), le
bail d'envoi et la recherche par référence avant une republication, les compteurs de plafond
avec TTL, la reconnaissance du jeton refusé (`token_invalid_since`), l'ordre des étapes d'un
refus et d'une clôture (commentaire, étiquette, fermeture), la recherche de la PR de
livraison et de la version à son commit de fusion (`recordDeliveredPr`,
`pubspecVersionAtCommit`).

Surdimensionné pour Kass'Beer : analyses relevées et réponses (`admin/analysis`,
`answerTicketAnalysis`), lancements et livraison automatique (`admin/launches`,
`admin/delivery`), capture d'écran (Cloud Storage), notifications FCM, type « Question »,
webhook public, une callable par décision, et les trois fixtures dupliquées.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne pas le faire | rien à écrire ; ADR-001 inchangé | les membres signalent par message ; le suivi reste à la main | 0 € / 0 € |
| A. Lien pré-rempli vers une Issue (`/issues/new?title=…&body=…`) | aucun serveur, une demi-journée | chaque membre a besoin d'un compte GitHub, dont le login devient public ; aucun suivi dans l'application ; aucun plafond | 0 € / 0 € |
| B. Collection `tickets/` écrite par le membre, publiée et suivie par un script local que lance l'administrateur | aucun serveur ; écriture hors ligne | statut à jour seulement quand l'administrateur lance le script ; identifiants Admin SDK sur le poste ; aucune décision depuis l'application | 0 € / 0 € |
| C. Functions sans point d'accès HTTP (retenue) : le membre écrit `tickets/{id}`, l'administrateur écrit ses décisions dans Firestore ; des déclencheurs les appliquent sur GitHub ; une tâche horaire relit les Issues | aucun point d'accès public ajouté ; abus limité aux comptes invités ; les règles décident seules de qui écrit ; ticket créé hors ligne | premier serveur du projet : `functions/`, déploiement CI, rôles, un secret ; état relu sur GitHub en retard d'une heure au plus | ≈ 0 € / ≈ 0 € (compte de facturation distinct) |
| C'. Comme C, avec des callables et un webhook signé (HMAC) | statut immédiat | points d'accès publics : ADR-005 estimait ≈ 124 $ par mois sous attaque continue pour un point d'accès de ce type ; vérification d'appartenance recopiée en TypeScript | ≈ 0 € / ≈ 0 €, plus le risque d'abus |
| D. Parité Kass'Dalle | tout le parcours dans l'application | ≈ 18 700 lignes de référence ; trois fixtures dupliquées ; un webhook public | ≈ 0 € / ≈ 0 €, plus l'abonnement Claude |

Écartée aussi : une routine Claude Code à déclencheur GitHub « Issue labeled ». La
documentation ne propose des filtres que pour les PR. Sur un dépôt public, n'importe quel
compte qui ouvre une Issue démarrerait une session sur l'abonnement de l'administrateur.

## Décision

Option C. Le membre crée `tickets/{id}` dans Firestore, sous des règles testées. Un
déclencheur `onDocumentCreated` publie l'Issue avec un jeton GitHub tenu par Secret Manager.
L'administrateur décide par des boutons ; chaque décision est un document que l'administrateur
seul crée, et qu'un déclencheur applique sur l'Issue. Une tâche planifiée horaire relit
l'état des Issues, y compris les décisions prises directement sur GitHub. C'est l'option qui
rend le service sans ajouter de point d'accès public, et qui laisse les règles Firestore
seules décider de qui peut écrire.

### Décisions de l'utilisateur (2026-11-10)

1. Option C : déclencheurs Firestore et tâche horaire, aucun point d'accès HTTP.
2. Issues sur le dépôt public `ChinaFred/KassBeer`, avec un avertissement dans le formulaire.
3. Compte de facturation distinct de celui de Kass'Dalle : niveaux gratuits entiers.
4. Décisions de l'administrateur par boutons dans l'application : « Valider », « Refuser »
   avec un motif, « Clore » avec un commentaire. Écrites dans Firestore, appliquées par un
   déclencheur, sans callable.
5. Sessions Claude Code lancées depuis l'application : plus tard, par une décision à part, hors
   de cet ADR.
6. Priorité : ces lots commencent après la livraison des lots L2 à L4 d'ADR-005. Révisée le
   2026-11-10 : T1 démarre après la livraison de L1 (v0.1.15), en parallèle de L2 à L4 ; la
   branche intègre `main` à chaque livraison d'ADR-005.
7. Plafonds : 5 tickets par membre et 20 pour le groupe par jour, l'administrateur exempté.
8. Node 24 pour `functions/`.
9. Jeton à grain fin du compte propriétaire, dans Secret Manager, renouvelé à son expiration ;
   l'état « jeton refusé ou expiré » est visible par l'administrateur.

### Lots

Ils commencent après la livraison du lot L1 d'ADR-005, en parallèle de L2 à L4 (décision 6,
révisée le 2026-11-10). Les noms T1 et T2
évitent la confusion avec ces lots.

| Lot | Contenu | Livré seul ? |
|---|---|---|
| T1 | `functions/` (Node 24, TypeScript, `logging.ts`, `github.ts`), déploiement par la CI ; règles et tests de `tickets/` ; « Signaler ou proposer », « Mes tickets », pastille de suivi ; déclencheur de publication ; tâche horaire ; état du jeton | une seule version : le socle sans le formulaire serait du code mort (ADR-005, option D écartée) |
| T2 | Admin › Tickets : liste, filtre « À traiter », auteur, « Ouvrir l'Issue », « Relancer l'envoi », compteur « Tickets à traiter » du menu, bandeau du jeton ; décisions « Valider », « Refuser », « Clore » (`tickets/{id}/decisions/`, déclencheur `onDecisionCreated`) | oui |

Estimation non mesurée : T1 ≈ 800 à 1 200 lignes serveur avec les tests, ≈ 1 500 à 2 000
lignes client. T2 ≈ 500 à 700 lignes serveur avec les tests (déclencheur des décisions,
reprise, relevé des réponses du propriétaire), ≈ 1 000 à 1 400 lignes client, et les tests
de règles des décisions.

Hors de cet ADR : sessions Claude Code lancées depuis l'application (décision 5 : un ADR ou
un avenant à part ; elles ouvriraient le premier poste de « Coûts variables »), capture
d'écran (Cloud Storage), notifications push, livraison automatique, type « Question ».

### Statuts

| État de l'Issue | Statut |
|---|---|
| ticket écrit, Issue pas encore créée | `pending` |
| Issue créée (étiquettes `source:app`, `type:<type>`) | `received` |
| étiquette `validé` | `validated` |
| étiquette `statut:en-cours` | `in_progress` |
| fermée `completed` sans `statut:clos` | `delivered`, avec la PR fusionnée et la version lue dans `app/pubspec.yaml` à son commit de fusion |
| fermée, étiquette `statut:clos` | `closed` |
| fermée `not_planned` ou `duplicate` | `refused` |
| dix envois en échec | `send_failed` |
| plafond du jour atteint à la publication | `over_quota`, non publié |

Un statut ne recule pas, sauf à la réouverture de l'Issue. Sur un dépôt public, seuls le
propriétaire et ses collaborateurs posent une étiquette ou ferment une Issue créée par son
jeton.

### Décisions de l'administrateur

**Modèle.** Une décision est un document de la sous-collection
`tickets/{ticketId}/decisions/{decisionId}`. L'identifiant est créé par le client. Un
document par décision garde l'historique, et chaque décision a son propre état. Un champ du
ticket ne le permettrait pas.

| Champ | Écrit par | Contenu |
|---|---|---|
| `action` | admin, à la création | `validate`, `refuse` ou `close` |
| `text` | admin, à la création | motif (`refuse`) ou commentaire (`close`), 5 à 2 000 caractères ; absent pour `validate` |
| `requested_by_uid` | admin, à la création | `request.auth.uid` |
| `requested_at` | admin, à la création | `request.time` |
| `state` | admin à la création (`pending`), puis serveur | `pending` → `applying` → `applied` ; ou `rejected` (refus sans rien publier), `failed` (échec en cours de route) |
| `retry_requested_at` | admin, sur une décision `failed` | `request.time` |
| `steps_done`, `error_reason`, `applied_at`, `comment_id`, `lease_until` | serveur | avancement, message montré à l'admin, identifiant du commentaire publié |

Le ticket reçoit, du serveur seul, `reply_text` (motif ou commentaire, avec les adresses
e-mail remplacées par « [adresse retirée] »), `reply_at`, et `allowed_decisions` : la liste
des décisions que son statut permet (`received` : valider, refuser, clore ; `validated` et
`in_progress` : refuser, clore ; autres statuts : aucune). Le serveur réécrit ce champ à
chaque changement de statut. Le client affiche les boutons de cette liste et ne la calcule
pas.

**Règles.** Création par `isAdmin()` seul, champs en liste blanche, `state == 'pending'`,
`requested_by_uid == request.auth.uid`, `requested_at == request.time`, `text` présent et
borné pour `refuse` et `close`, absent pour `validate`. Lecture par l'administrateur seul.
Seule modification client : `retry_requested_at == request.time` par l'administrateur, sur
une décision `failed`. Aucune suppression. Le membre ne lit pas les décisions ; il lit
`reply_text` et le statut sur son ticket.

**Application et idempotence.** Un déclencheur peut s'exécuter deux fois. Le déclencheur
`onDecisionCreated` (et `onDecisionUpdated` pour `retry_requested_at`) suit cet ordre :

1. Transaction : la décision doit être `pending`, ou `failed` avec une reprise demandée, ou
   `applying` avec un bail expiré. Sinon le déclencheur s'arrête : c'est un rejeu. Le ticket
   ne doit avoir aucun autre bail de décision actif (`decision_lease_until`), et `action`
   doit figurer dans `allowed_decisions`. Sinon la décision passe `rejected`
   (« Une décision est déjà en cours sur ce ticket. », « Cette décision n'est plus possible
   pour ce statut. »). Puis bail de deux minutes sur le ticket et sur la décision, état
   `applying`.
2. Relecture de l'Issue. Si elle est déjà fermée, l'état lu est appliqué au ticket et la
   décision passe `rejected` (« Ce ticket a déjà été clos sur GitHub. »).
3. `refuse` et `close` : le commentaire `Réponse : <texte publié>` est publié, suivi d'une
   ligne « Décision <decisionId> ». Avant de publier, le serveur cherche cette ligne dans les
   commentaires du propriétaire (identifiant 16348852). Un commentaire déjà publié par un
   essai précédent n'est pas republié.
4. Étiquettes : `validé` pour `validate`, `statut:clos` pour `close`. Une étiquette déjà
   posée compte comme faite.
5. Fermeture : `not_planned` pour `refuse`, `completed` pour `close`. Une Issue déjà fermée
   de cette façon compte comme faite.
6. Transaction : statut, `reply_text`, `allowed_decisions` et `status_changed_at` du ticket,
   décision `applied`, baux retirés.

Un échec après l'étape 2 laisse la décision `failed`, avec `steps_done` et `error_reason`
(« Motif publié, mais l'Issue n'a pas été fermée. Réessayez. »). « Réessayer » écrit
`retry_requested_at` et reprend la même décision. La reconnaissance du commentaire et des
étiquettes empêche alors une double publication. La tâche horaire reprend une décision
`applying` dont le bail a expiré (fonction arrêtée en cours de route). Un jeton refusé ou
expiré laisse la décision `failed` (« Jeton GitHub refusé ou expiré. ») sans compter
d'échec.

**Ce que voit le membre.** « Mes tickets » montre le statut, et pour un ticket refusé ou clos
le texte de `reply_text` sous « Réponse de l'administrateur ». La pastille du compte s'allume
quand `status_changed_at` dépasse `seen_by_author_at`.

**Décisions prises sur GitHub.** Elles restent possibles, depuis VS Code ou le site. La tâche
horaire relit l'état et les étiquettes. Elle relit aussi le dernier commentaire du compte
16348852 qui commence par « Réponse : » et en fait `reply_text`, préfixe et ligne
« Décision … » retirés. Aucun autre commentaire n'est lu.

### Jeton GitHub

Jeton à grain fin du compte propriétaire, limité à `ChinaFred/KassBeer` : Issues en lecture et
écriture, Pull requests et Contents en lecture. Il vit dans le secret `GITHUB_TICKETS_TOKEN`
et se renouvelle à son expiration. Le document `ticket_status/github`, écrit par le serveur et
lu par l'administrateur seul, porte `token_invalid_since` (réponse 401, 403 hors limite de
débit, 404 sur le dépôt, secret vide) et `token_expires_at`, lu dans l'en-tête
`github-authentication-token-expiration` des réponses de GitHub (à vérifier au premier
appel). Admin › Tickets affiche « Jeton GitHub refusé ou expiré depuis le jj/mm/aa : remplacez
`GITHUB_TICKETS_TOKEN` dans Secret Manager. », et « Le jeton GitHub expire le jj/mm/aa. »
quatorze jours avant l'échéance. Un jeton refusé n'use pas les essais d'envoi. Les tickets
et les décisions repartent quand le jeton est remplacé. Le premier appel réussi efface
`token_invalid_since`.

### Coexistence avec le développement depuis VS Code

- Le ticket passe « livré » quand l'Issue se ferme `completed` sans `statut:clos`, quelle
  que soit la branche de la PR. Une PR qui traite un ticket porte `Closes #N`.
- La session qui prend un ticket pose `statut:en-cours` avant son premier commit. Elle
  s'arrête si l'étiquette est déjà posée.
- Une session ne publie jamais un commentaire qui commence par « Réponse : » sans l'accord de
  l'utilisateur : ce texte arrive dans « Mes tickets ».
- Les numéros de version suivent la règle actuelle : fusion sans rebase,
  `check-version.mjs` avant la fusion. Le ticket lit sa version au commit de fusion. Il ne
  la calcule pas.
- L'entrée du `CHANGELOG.md` porte « Demandé par le ticket #N ». Elle ne nomme jamais le
  membre (P15).
- « Livré » veut dire fusionné. Un ticket livré en vX.Y.Z affiche « Disponible après mise à
  jour » tant que la version installée est inférieure (comparaison faite à l'affichage).

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : formulaire, « Mes tickets » et Admin › Tickets dans
   l'application. Contrôle d'écriture dans `firestore.rules`. Publication, décisions,
   plafond, nettoyage du texte et relecture des Issues dans `functions/` (Cloud Functions 2e
   génération, Node 24, `europe-west1`, région de la base). Le paquet `brewing/` n'est pas
   touché. Aucun code de ticket dans l'écran du jour de brassage (P2).
2. **Ce qui existera en double** : rien. Les règles décident de l'appartenance et du rôle
   d'administrateur ; les déclencheurs ne les revérifient pas. Le texte publié est nettoyé
   côté serveur seul : les adresses e-mail sont remplacées au lieu d'être refusées. Le
   statut et `allowed_decisions` sont dérivés par le serveur seul et lus tels quels. Le
   tableau « Logique dupliquée » reste vide.
3. **Ce qui pèse au démarrage** : côté serveur, aucun SDK lourd ; client GitHub par `fetch`,
   `firebase-admin` et `firebase-functions` seuls (leçon 5). Côté client, pas de
   `cloud_functions` : les écritures passent par `cloud_firestore`. Seul `url_launcher` s'ajoute
   (avenant du 2026-11-10), pour ouvrir la PR livrée ; il est léger et n'entre pas au démarrage.
4. **Compilation de chaque cible** : `(cd functions && npm ci && npm run build && npm test)`
   s'ajoute à « Commandes utiles » et à `ci.yml`. Côté client, `url_launcher` 6.3.3
   s'ajoute (avenant du 2026-11-10) : l'APK se compile par le job « Android — compilation »
   de la CI (P6), le web par `flutter build web`.
5. **Qui voit quoi** : un membre lit ses tickets et la réponse qui lui est faite,
   l'administrateur tous les tickets et toutes les décisions. L'Issue publique contient le
   titre, la description nettoyée, le type, le modèle de route, la version, la plateforme et
   l'identifiant opaque du ticket, puis les réponses publiées par l'administrateur. Elle ne
   contient jamais le nom, l'e-mail, l'uid, un contenu de recette ni un prix. L'auteur d'une
   Issue est le compte du jeton. Le formulaire, et les boîtes « Refuser » et « Clore », disent
   que le texte sera public. Un nom écrit dans un texte ne se détecte pas : cet avertissement
   est le seul garde-fou.
6. **Ce qui coûte à l'usage, plafond** : aucun poste facturé à l'usage. Plafond de
   publication : 5 tickets par membre et 20 pour le groupe par jour (heure de Paris),
   l'administrateur exempté, compteurs `ticket_quotas/` avec TTL de 7 jours, lus et
   incrémentés par le déclencheur de publication. Les décisions n'ont pas de plafond : seul
   l'administrateur les crée. Tâche horaire : 720 exécutions par mois, 30 Issues relues au
   plus par passe.
7. **Exposition** : aucun point d'accès HTTP ajouté. Un déclencheur Firestore et une tâche
   planifiée ne s'appellent pas depuis Internet. Les abus possibles viennent d'un membre
   invité, dont l'administrateur retire le document `members/`. `maxInstances` borne chaque
   fonction.
8. **Exploitation, sauvegarde, mise à jour** : maintenu par l'administrateur avec Claude Code.
   `deploy.yml` déploie `functions/` seulement quand ce dossier change. La découverte des
   fonctions se fait dans un job sans `id-token` (P14), selon les conditions relevées par
   ADR-005 dans `firebase-tools` 15.35.0. Réglages faits une fois : API, rôles de
   `github-deploy`, politique de nettoyage d'Artifact Registry à 1 jour, secret
   `GITHUB_TICKETS_TOKEN`, étiquettes `source:app`, `type:*`, `validé`, `statut:en-cours`,
   `statut:clos`. La date d'expiration du jeton se note dans `exigences-techniques.md` ; le
   bandeau d'Admin › Tickets l'annonce. Tickets et décisions vivent dans la sauvegarde
   quotidienne de Firestore. Les Issues restent sur GitHub.
9. **Coût de sortie** : faible. Les tickets sont des Issues GitHub ordinaires. Retirer
   `functions/` laisse les Issues et la collection `tickets/` lisibles. Le dépôt ne se
   recrée jamais (ADR-002, condition Workload Identity Federation).

## Avenant du 2026-11-10 — cadrage de T1

Après le cadrage de T1 (`analyste-metier`, `ux-designer`), l'utilisateur a tranché :

1. **Réponse dès T1.** La tâche horaire relève le dernier commentaire « Réponse : » du compte
   16348852 et l'écrit dans `reply_text` ; « Mes tickets » l'affiche sous « Réponse de
   l'administrateur ». Ce relevé passe de T2 à T1.
2. **Bandeau Admin en T1.** La page Admin lit `ticket_status/github` et compte les tickets
   bloqués : jeton refusé ou expiré, expiration à 14 jours ou moins, tickets `send_failed` ou
   `pending` depuis plus d'une heure, tickets dont l'Issue a disparu. En T2, il passe dans
   Admin › Tickets.
3. **Écran d'origine modifiable.** Liste préremplie par le modèle de route de l'écran d'origine,
   avec « Autre écran » et « Je ne sais pas » ; une table fermée donne le nom de chaque route, et
   un test vérifie que chaque route y figure.
4. **Lien vers la PR livrée** par `url_launcher`, ouvert seulement en `https` sur `github.com`.
   P6 s'applique.
5. **« Reprendre ce ticket »** sur un ticket `over_quota` : formulaire prérempli, nouveau
   ticket.
6. **Pastille** : elle ne s'allume pas au passage `pending` → `received`.
7. **Issue disparue** (404 ou 410 sur l'Issue, dépôt joignable) : le ticket garde son statut,
   l'erreur est journalisée et le bandeau Admin la compte.
8. **Description** : 10 à 2 000 caractères, contrôlés par le formulaire et par les règles.
9. **Plafond** : les tickets de l'administrateur ne sont jamais refusés et ne comptent pas dans
   les 20 du groupe.

Relevé à l'implémentation de T1 (déduit du code de firebase-tools 15.35.0, à confirmer au premier
déploiement) : `github-deploy` reçoit aussi `run.admin` (invocation de la tâche planifiée),
`cloudscheduler.admin`, `artifactregistry.reader` (lecture de la politique de nettoyage) et
`secretmanager.viewer` sur le seul secret `GITHUB_TICKETS_TOKEN`. Les Functions tournent sous un
compte dédié `tickets-functions`. La liste complète vit dans `exigences-techniques.md`,
« Réglages faits une fois ». `allowed_decisions` et `retry_requested_at` arrivent avec T2.

## Conséquences

Plus simple : un membre signale depuis l'application, hors ligne compris, et lit la réponse.
L'administrateur décide depuis l'application, ou traite le ticket comme une Issue depuis
VS Code ou une session Claude Code. Le socle Functions existe pour l'IA et le RAPT Pill, avec
un service rendu dès sa livraison.

Plus difficile : le projet a un serveur à déployer, un secret à renouveler et un journal
serveur à lire. Chaque texte publié est public et définitif. Un déclencheur peut s'exécuter
deux fois : publication et décisions passent par un bail en transaction et par la
reconnaissance de ce qui est déjà fait sur GitHub. Une décision met quelques secondes à
s'appliquer : l'écran suit `state` de la décision.

`CLAUDE.md` change : « Le projet » (serveur), « Structure » (`functions/`), « Commandes
utiles », une section « Tickets », P10 et P14 étendus, P23 à P27 ajoutés. « Coûts variables »
ne change pas. ADR-001 reçoit « Modifié par : ADR-006 ».

## Sources

Consultées le 2026-11-10.

- Kass'Dalle, `documentation/TechnicalRequirements.md` §3.12 bis et « Tickets »,
  `documentation/FunctionalRequirements.md` §5.13, `CLAUDE.md` (routines), comptes de lignes
  par `wc -l` sur `kass_dalle/functions/src/tickets/`, `kass_dalle/functions/src/tests/` et
  `kass_dalle/lib/features/tickets/`.
- Dépôt `ChinaFred/KassBeer` : Issues activées, propriétaire d'identifiant numérique
  16348852, aucune étiquette `source:app` ni `statut:*` (`gh api`, 2026-11-10).
- API de déclenchement d'une routine (option future) : aucune clé d'idempotence, 30
  déclenchements par heure et par routine, usage décompté de l'abonnement :
  https://platform.claude.com/docs/en/api/claude-code/routines-fire
- Routines, déclencheurs GitHub (filtres pour les PR seulement) :
  https://code.claude.com/docs/en/routines
- Node.js 24 dans Cloud Run functions, obsolète le 2028-04-30 :
  https://docs.cloud.google.com/run/docs/runtimes/function-runtimes
- Eventarc : événements de sources Google à 0 $ : https://cloud.google.com/eventarc/pricing
  (montant pour une base Firestore Standard : à vérifier).
- Secret Manager, six versions gratuites par compte de facturation :
  https://cloud.google.com/secret-manager/pricing (à vérifier).
- Cloud Scheduler, trois tâches gratuites par compte de facturation :
  https://cloud.google.com/scheduler/pricing (à vérifier).
- Cloud Run, niveau gratuit (180 000 vCPU-s, 360 000 Gio-s, 2 millions de requêtes par mois) :
  https://cloud.google.com/run/pricing (à vérifier).
- Artifact Registry, 0,5 Go gratuit : https://cloud.google.com/artifact-registry/pricing
  (à vérifier).
- En-tête `github-authentication-token-expiration` des jetons à grain fin : à vérifier au
  premier appel.
- Estimation de ≈ 124 $ par mois sous attaque continue d'un point d'accès public : ADR-005,
  option C.
- Estimations non mesurées : volume de code des lots T1 et T2.
