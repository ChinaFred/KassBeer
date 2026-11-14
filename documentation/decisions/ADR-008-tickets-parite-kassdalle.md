# ADR-008 — Tickets : copie de Kass'Dalle (analyses, lancements de sessions Claude Code, livraison, captures), par callables, webhook GitHub signé et Cloud Storage

- **Statut** : accepté le 2026-11-11, décision de l'utilisateur : option B, « copie exacte » de
  Kass'Dalle
- **Date** : 2026-11-11
- **Remplace** : ADR-006 sur trois points : option C (« aucun point d'accès HTTP »), décision 1
  et décision 5 ; P25 (« aucun `onRequest` ni `onCall` sans ADR » : cet ADR est celui qui les
  autorise, liste fermée ci-dessous). ADR-006 reste en vigueur pour le reste. Modifie ADR-001
  (premier poste de « Coûts variables », Cloud Storage ajouté). S'appuie sur ADR-007 sans le
  changer.

## Contexte

L'utilisateur a demandé de « s'inspirer voire copier le traitement des tickets de KassDalle
dans KassBeer ». À la liste des morceaux écartés (lancements de sessions Claude, analyses,
livraison automatique, captures), il a répondu : « Non non fais le comme prévu c'est une
amélioration ». Entre les options de cet ADR, il a choisi l'option B, « copie exacte » :
callables, webhook GitHub signé, Cloud Storage pour les captures. Il a demandé de travailler
sans lui : les valeurs par défaut viennent de Kass'Dalle, et chaque écart est nommé et justifié.

Ce qui existe (dépôt lu le 2026-11-11) : `functions/src/` compte 2 630 lignes en 13 fichiers,
dont `tickets/decisions.ts` (456) et `tickets/decisionModel.ts` (324) du lot T2, presque fini.
Quatre fonctions : `publishTicket`, `onDecisionCreated`, `onDecisionUpdated`, `syncTickets`
(`functions/src/index.ts`). Aucun `onRequest`, aucun `onCall`. Côté client : `firebase_core`
4.15.0, `firebase_auth` 6.7.0, `cloud_firestore` 6.8.0 (`app/pubspec.yaml`).

Référence Kass'Dalle (clone `/home/user/chinafred/kassdalle`, lu le 2026-11-11) :
`functions/src/tickets/routine.ts` (273 lignes), `launch.ts` (748), `delivery.ts` (351),
`webhook.ts` (597), `decisions.ts` (883), `stored.ts` (101), une part de `rules.ts` (2 097),
`callable/ticketsCallable.ts` (649) ; tests `ticketLaunches.test.ts` (530),
`ticketDelivery.test.ts` (700), `ticketDecisions.test.ts` (1 188) ; client
`lib/features/tickets/` (8 022 lignes) ; `storage.rules`, règle
`tickets/{uid}/{ticketId}/{fileName}` ; paquets `cloud_functions`, `firebase_storage`,
`firebase_app_check`, `image_picker`, `flutter_markdown_plus`, `markdown`.

Contraintes concernées :

- « Coûts variables » de `CLAUDE.md` : catalogue, plafond, jamais depuis le client, aucune
  action sur un défilement ou une frappe ; aucun poste en v1 (ADR-001) ;
- dépôt public (ADR-002) : analyses, précisions et comptes rendus sont publics ; ruleset de
  `main` à 0 approbation, sans contournement ; `deploy.yml` déploie seul après une CI verte ;
- un point d'accès public coûte jusqu'à ≈ 124 $ par mois sous attaque continue (ADR-005,
  option C ; base de calcul à recalculer avec les `maxInstances` de cet ADR) ; alerte
  budgétaire à 5 € (ADR-001) ;
- les prix ne quittent pas `users/{uid}/` (P5) ; une capture peut en montrer ;
- aucun sélecteur de fichier tiers sans ADR qui remplace ADR-007 (P28).

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne pas le faire | rien à écrire ; T2 suffit | contraire à la consigne | 0 € / 0 € |
| A. Analyses et « Répondre » seuls | ni secret de routine, ni poste de coût | parité partielle | 0 € / 0 € |
| B. Copie de Kass'Dalle : callables, webhook signé, Cloud Storage (retenue) | comportement connu ; erreurs rendues dans la boîte de dialogue ; relevé immédiat par le webhook ; capture de 5 Mo | jusqu'à 8 points d'accès publics ; vérification d'appartenance en TypeScript et dans `storage.rules` ; quatre paquets client ; un service Google de plus | ≈ 0 € / ≈ 0 €, plus l'abonnement Claude et le risque d'abus des points d'accès |
| C. Documents et déclencheurs Firestore, capture dans Firestore | aucun point d'accès ; aucun paquet | relevé en retard ; capture réduite à 900 Ko ; code adapté | ≈ 0 € / ≈ 0 € |

## Décision

Option B, choisie par l'utilisateur. Les actions de l'administrateur et le rattachement de la
capture passent par des callables. L'état de GitHub arrive par le webhook `githubTicketWebhook`,
signé HMAC, doublé de la tâche horaire. Les captures vivent dans Cloud Storage.

### Points d'accès autorisés (liste fermée)

| Fonction | Type | Garde | Lot | `maxInstances`, délai |
|---|---|---|---|---|
| `githubTicketWebhook` | `onRequest`, `invoker: "public"` | signature `X-Hub-Signature-256` | T3 | 5, 60 s |
| `answerTicketAnalysis` | `onCall` | `requireAdmin` | T3 | 2, 60 s |
| `launchTicketAnalysis` | `onCall` | `requireAdmin` | T4 | 1, 120 s |
| `launchTicketDevelopment` | `onCall` | `requireAdmin` | T4 | 1, 120 s |
| `launchTicketDelivery` | `onCall` | `requireAdmin` | T5 | 1, 180 s |
| `attachTicketScreenshot` | `onCall` | `requireMember`, auteur du ticket | T6 | 2, 60 s |
| `validateTicket`, `refuseTicket`, `closeTicket`, `retryTicketSend` | `onCall` | `requireAdmin` | T7 | 1, 60 s |

Tout autre `onRequest` ou `onCall` demande un nouvel ADR.

Ajout du 2026-11-14 : ADR-011 ajoute `queryLogs` (`onCall`, `requireAdmin`, lot J2,
`maxInstances` 1, `concurrency` 1, 60 s, aucun secret monté), lecture des journaux des fonctions
par l'admin.

**La création du ticket reste dans Firestore (T1).** `submitTicket` n'est pas copiée. Le
ticket se crée hors ligne compris, et Kass'Dalle perd ce cas (« Le ticket n'est pas parti.
Vérifiez la connexion »). Les règles de `tickets/` et leurs tests pour cinq profils sont livrés
(P23). Le plafond est déjà tenu par `publishTicket`. Une callable de plus serait un point
d'accès ouvert à tout compte connecté, membre ou non. Le service rendu au membre est le même.

**Transition de T2.** T2 se livre tel quel : décisions par documents
`tickets/{id}/decisions/` et déclencheurs. Le lot T7, le dernier, fait la copie exacte. Il
passe Valider, Refuser, Clore et Relancer l'envoi en callables. Il réutilise le cœur de
`functions/src/tickets/decisions.ts` (bail, ordre des étapes, reconnaissance du commentaire et
des étiquettes) derrière une callable. Le même lot retire `onDecisionCreated`,
`onDecisionUpdated`, les règles de `decisions/` et leurs tests (« Pas de code mort »). Les
documents `decisions/` déjà écrits restent en base ; plus rien ne les lit. Entre T3 et T7,
« Répondre » est une callable et les trois autres décisions des documents : état transitoire
accepté. Sauter T7 est l'option moins lourde. Elle garde un modèle de décision différent de
Kass'Dalle.

2026-11-14 (lot T7), décisions de l'utilisateur : Valider, Refuser, Clore et « Relancer
l'envoi » passent en callables (`validateTicket`, `refuseTicket`, `closeTicket`,
`retryTicketSend`), avec `maxInstances: 1` et 60 s chacune : l'admin seul les appelle (le
tableau ci-dessus portait 2 instances, il est corrigé). `onDecisionCreated` et `onDecisionUpdated` sont
retirés, ainsi que la relance des envois (`retryFailedSends`) et la reprise des décisions
(`resumeStuckDecisions`) par la tâche horaire. `tickets/{id}/decisions/` reste l'historique,
écrit par les trois callables seules et lu par l'admin (`allow read: if isAdmin(); allow write:
if false`) : ce point remplace « plus rien ne les lit ». La ligne `Décision <id>` du commentaire
est gardée ; l'identifiant est tiré par le serveur. Une décision interrompue (`failed`,
`applying` au bail expiré, ou `pending` écrite par un client d'avant T7) se reprend par l'admin
seul, en rappelant la même callable : même
identifiant, commentaire déjà publié reconnu, texte stocké gardé dès qu'il est publié. Le motif
de Refuser et le commentaire de Clore passent de 2 000 à 4 000 caractères, comme « Répondre ».
Les décisions demandent le réseau : hors ligne, les boutons restent visibles et inactifs, le
texte saisi reste en brouillon, rien ne part au retour du réseau. Les deux déclencheurs sont
supprimés à la main par l'utilisateur avant la fusion (`deploy.yml` ne passe pas `--force`).
`ci.yml` et `deploy.yml` vérifient une liste fermée des déclencheurs : `publishTicket` seul
déclencheur Firestore, `syncTickets` seule tâche planifiée. Après T7 : onze points d'accès
publics (dix callables, dont `queryLogs` d'ADR-011, et le webhook), dix-sept instances au plus ;
sur la base de ≈ 64 $ par mois et par instance saturée (tarifs à vérifier), ≈ 1 090 $ par mois
en théorie sous une attaque continue de tous les points, l'alerte à 5 € part avant.

### Protection des callables

- `requireMember` et `requireAdmin` (`functions/src/auth.ts`) : jeton vérifié par le SDK,
  `email_verified == true`, `firebase.sign_in_provider == 'google.com'`, lecture de
  `members/{email en minuscules}` et de son rôle à chaque appel. C'est la vérification de P11,
  recopiée. Elle entre au tableau « Logique dupliquée », avec la fixture
  `test-fixtures/member_access.json` rejouée par `rules-tests/` (Firestore et Storage) et par
  `functions/test/`.
- `cors` limité à `https://kassbeer.web.app` et `https://kassbeer.firebaseapp.com`, comme
  Kass'Dalle. Cette liste ne protège pas d'un script : elle limite les navigateurs.
- Garde de taille brute avant toute lecture (`requireBoundedText` de Kass'Dalle) ; erreurs
  rendues avec `details.reason` et `details.field`, messages de Kass'Dalle.
- **App Check n'est pas copié.** L'APK est distribué par App Distribution, hors de Google
  Play : le verdict Play Integrity d'une application installée hors Play est à vérifier, et
  un refus bloquerait tous les brasseurs Android. Le web demanderait reCAPTCHA Enterprise et le
  paquet `firebase_app_check`. Kass'Dalle le pilote par une politique en base pour cette même
  raison. Ce qui borne l'abus : un appel non membre est refusé après la vérification du jeton ;
  `maxInstances` plafonne chaque fonction ; l'alerte à 5 € prévient.
- **Coût d'abus.** Huit points d'accès publics. ADR-005 estime ≈ 124 $ par mois pour un point
  d'accès saturé en continu. Avec `maxInstances` de 1 à 5, le plafond théorique est
  proportionnel au nombre d'instances. Recalcul au lot T3 (2026-11-12, `exigences-techniques.md`,
  tarifs à vérifier) : ≈ 64 $ par mois et par instance saturée, ≈ 442 $ par mois pour les deux
  points d'accès de T3 (7 instances) après le quota gratuit ; l'alerte à 5 € part en ≈ 9 h
  d'attaque continue sur les deux, ≈ 12 h sur le webhook seul.

### Webhook `githubTicketWebhook`

Copie de `kass_dalle/functions/src/tickets/webhook.ts`. `POST` seul. Corps de plus de 25 Mo :
413. En-tête `X-GitHub-Event` absent : 400. Secret `GITHUB_WEBHOOK_SECRET` vide : 503, journalisé
au plus une fois par minute et par instance. HMAC SHA-256 du corps brut (`req.rawBody`), comparé
par `timingSafeEqual` ; signature absente ou fausse : 401, `logWarn` échantillonné une fois par
minute. Corps illisible : 400. `ping`, autre dépôt, autre événement, Issue sans ticket : 200,
ignoré. Panne Firestore : 500 ; la tâche horaire rattrape.

Événements : `issues`, `issue_comment` (commentaires du compte 16348852 seuls),
`pull_request` (auteur 16348852, ou `author_association` `OWNER`, `MEMBER`, `COLLABORATOR`),
`workflow_run` du workflow « CI ». Le secret est monté par cette seule fonction. La tâche
horaire `syncTickets` reste horaire (ADR-006).

### Statuts

Le statut `analyzed` s'ajoute, dérivé de l'étiquette `statut:analysé`. Les étiquettes
`statut:à-analyser` (posée à la publication), `statut:analysé` et `validé` suivent Kass'Dalle.
`in_progress` vient de l'étiquette `statut:en-cours` (règle de Kass'Beer) ou d'une PR ouverte
d'un auteur de confiance qui ferme l'Issue (Kass'Dalle). « Répondre » ramène à `received`
(`answer_reset_at`). `validate` n'est possible que depuis `analyzed` (« Valider sera possible une
fois le ticket analysé. »). `allowed_decisions` reste écrit par le serveur, qui recontrôle chaque
appel ; le client ne recopie pas les préconditions de Kass'Dalle (fixture
`ticket_decisions.json` non reprise). Un APK ancien affiche « Statut inconnu » (« Mettez
l'application à jour pour lire ce statut. »).

2026-11-12 : Jusqu'au lot T4, Valider reste offert depuis Reçu (décision de l'utilisateur) ; T4
le réserve aux tickets analysés.

2026-11-13, décision de l'utilisateur (lot T4) : « Lancer le développement » n'est possible
qu'après un « Valider » fait dans l'application. L'application d'une décision `validate` pose
`validated_by_app_at` sur le ticket (serveur seul) ; Refuser, Clore, « Répondre » et toute
relecture de l'Issue dont le statut d'avant ou d'après est hors `validated` et `in_progress`
l'effacent. `launch_development` n'entre dans
`allowed_decisions` qu'avec ce champ, et `launchTicketDevelopment` le recontrôle (refus
`not_launchable`). Une étiquette `validé` posée sur GitHub change toujours le statut affiché ;
le serveur offre alors « Valider » sur ce ticket `validated`, et l'application affiche
« Validé sur GitHub : validez depuis l'application pour lancer le développement. ». Le retrait
de `validé` sur une Issue ouverte ne fait pas reculer le statut et n'efface pas la validation de
l'application ; la session de développement, qui exige l'étiquette `validé`, refuse alors de
travailler. Version 4
de la règle (`ALLOWED_DECISIONS_VERSION`) : les tickets déjà validés avant ce changement
doivent être validés à nouveau dans l'application.

2026-11-14, décision de l'utilisateur (lot T5) : `in_progress` reste dérivé de la seule
étiquette `statut:en-cours`. Le second cas écrit plus haut (PR ouverte d'un auteur de confiance
qui ferme l'Issue, règle de Kass'Dalle) est abandonné : la session de développement pose déjà
l'étiquette, et le webhook `pull_request` ne change aucun statut.

2026-11-14, décisions de l'utilisateur (lot T5) : `launch_delivery` (« Livrer ») et
`relaunch_development` (« Relancer le développement ») n'entrent dans `allowed_decisions` que
pour un ticket `in_progress` validé dans l'application (`validated_by_app_at`), comme « Lancer le
développement ». Version 5 de la règle. Refuser et Clore restent dans la liste, mais sont masqués
par le client et rejetés par `decisionClaimVerdict` (depuis T7 : `refuseTicket` et
`closeTicket`, P44) tant que le verrou des livraisons porte ce ticket (« Une livraison est en
cours sur ce ticket. Attendez sa fin. »).

### Analyses et « Répondre »

Copie de Kass'Dalle. `tickets/{id}/admin/analysis` (dix entrées, 20 000 caractères chacune,
`kind` `analysis`, `reply`, `unverified_reply`, `answer_comment_ids`, `validated_at`), écrit par
le webhook, la tâche horaire et chaque décision, lu par l'administrateur seul.
`answerTicketAnalysis` : texte de 5 à 4 000 caractères, publié sous
`## Précisions de l'administrateur`, identifiant du commentaire noté dans `answer_comment_ids`.
Rendu en Markdown par `flutter_markdown_plus`, aucune image chargée, liens `http` et `https`
seuls.

### Lancements de sessions (Routines)

Copie de `launch.ts` et `routine.ts`. Deux routines sur claude.ai/code : « Kass'Beer — analyse
d'un ticket » et « Kass'Beer — développement d'un ticket » (qui reçoit aussi la livraison).
Corps exact `{"text": "<action> #N"}` contrôlé par
`^(analyse|developpement|livraison) #[1-9][0-9]{0,6}$`, délai 30 s, `redirect: "error"`.
Historique `tickets/{id}/admin/launches` (vingt entrées), règle « en cours » `retry_after` (1 h
analyse, 3 h développement et livraison), messages d'erreur de `routineFailureMessage`, résultat
`unknown` compté et bloquant. Un appel n'est jamais rejoué.

**Plafond et poste de coût.** Poste `ticket_routine_launch`, inscrit au catalogue de
`exigences-techniques.md`. 10 lancements par jour de Paris pour le groupe
(`LAUNCHES_PER_DAY`, `functions/src/config.ts`), compteur `ticket_quotas/launch_{AAAAMMJJ}`,
affichage `ticket_status/launches` (jour, mois, `routine_invalid_since`, `delivery_running`).
Le plafond de 50 du fondateur n'est pas copié : Kass'Beer n'a pas de compte fondateur, et le
changer tient en une ligne. L'API limite à 30 appels par heure et par routine et 100 par heure
pour le compte, partagés avec Kass'Dalle. Les sessions consomment l'abonnement Claude de
l'administrateur.

2026-11-13 (lot T4) : le motif du corps est réduit à `^(analyse|developpement) #[1-9][0-9]{0,6}$`
jusqu'à T5, qui y ajoutera `livraison` avec `launchTicketDelivery`. `routine_invalid_since` est
écrit en deux champs, un par routine : `analysis_invalid_since` et `development_invalid_since`
de `ticket_status/launches`. `delivery_running` arrive avec T5.

2026-11-14 (lot T5) : le motif devient `^(analyse|developpement|livraison|reprise) #[1-9][0-9]{0,6}$`.
`livraison #N` et `reprise #N` partent par la routine de développement : aucune troisième
routine, aucun secret nouveau ; `TICKETS_ROUTINE_DEV_*` est monté par `launchTicketDevelopment`
et `launchTicketDelivery`, et leur refus pose `development_invalid_since`. Décisions de
l'utilisateur :

- « Relancer le développement » (décision 9, conception revue par l'architecte) : sur un ticket
  En cours dont la CI de la PR est rouge (`failure`, `timed_out` ou `startup_failure` ;
  `cancelled` ne compte pas), action `reprise`, par la callable existante
  `launchTicketDevelopment` avec l'argument `mode: "resume"` (absent : `start`, jamais déduit
  du statut). Aucun point d'accès nouveau. Préconditions au serveur (P47), dont
  `admin/delivery.relaunch_ready` écrit par le serveur ;
- relance seulement après l'échéance de 3 h du développement ou de la reprise précédents
  (décision 10) ; aucune limite de reprises par ticket en plus du plafond du jour (décision 13) ;
- une reprise qui s'arrête ne publie rien sur GitHub ; sa raison est dans le résumé de la
  session (décision 11) ;
- « Livrer » est refusé (`reprise_running`) tant qu'une reprise du même ticket est en cours ;
  le premier développement ne bloque pas la livraison (décision 12) ;
- la livraison et la reprise sont des lancements du même poste `ticket_routine_launch` et du
  même plafond (10 par jour), comptés seulement après leurs contrôles et la prise du verrou
  (décision 6).

Règle « en cours » par action : une livraison est bloquée par une livraison ou une reprise en
cours ; une reprise par un développement, une reprise ou une livraison en cours ; l'analyse et
le premier développement restent bloqués par la même action seule. Bail de 210 s pour une
livraison, plus long que les 180 s de `launchTicketDelivery`.

### Livraison

Copie de `delivery.ts` : état « PR prête » (`tickets/{id}/admin/delivery`), verrou global
`delivery_running` (3 h), comptes rendus `## Livraison — blocage` et `## Livraison — terminée`.
Fichiers sensibles refusés par `launchTicketDelivery` et par le prompt (casse ignorée, ancien
chemin d'un renommage compris) : `.github/**`, `.claude/**`, `scripts/**`, tout `CLAUDE.md`,
`CLAUDE.local.md`, `.mcp.json`, `firebase.json`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `rules-tests/package.json`, `rules-tests/package-lock.json`,
`rules-tests/prettier.config.*`, `functions/package.json`, `functions/package-lock.json`,
`functions/prettier.config.*`, `ingest/package.json`, `ingest/package-lock.json`,
`ingest/prettier.config.*`, `app/android/**/*.gradle`, `app/android/**/*.gradle.kts`,
`app/android/gradle.properties`, `app/android/settings.gradle*`, `app/android/gradle/**`. La
session ne pose jamais de tag : le job `tag` de `deploy.yml` le
fait (leçon 16). Jeton GitHub : Actions en lecture ajouté.

2026-11-13, décision de l'utilisateur (lot T4) : la liste ajoute les fichiers d'`ingest/` que
le hook `format-on-edit.mjs` et `npm ci` exécutent (P10), et les fichiers de construction
Android (`*.gradle`, `*.gradle.kts`, `gradle.properties`, `settings.gradle*`, `gradle/**`
sous `app/android/`), exécutés par la compilation de l'APK.

2026-11-14, décisions de l'utilisateur (lot T5) :

- `app/pubspec.lock`, `brewing/pubspec.lock` et `exchange/pubspec.lock` sont sensibles pour la
  livraison seule : un nouveau paquet exécute son code de construction dans le job `build` de
  `deploy.yml`, qui détient les secrets de signature. La session de développement peut ajouter
  un paquet ; « Livrer » refuse alors (`delivery_sensitive_files`) et l'administrateur fusionne
  à la main après relecture. La liste vit une seule fois dans
  `functions/src/tickets/delivery.ts` (`SENSITIVE_DELIVERY_PATTERNS`) ; le bloc L3 du prompt
  de développement en est la copie, comparée par `functions/test/prompts.test.ts` ;
- « Livrer » n'est offert que pour un ticket validé dans l'application, comme « Lancer le
  développement » (décision 1) ;
- quand une condition de L1 ou de L2 manque, la session de livraison publie un
  `## Livraison — blocage` qui la nomme, ce qui libère le verrou à la relecture suivante ; elle
  ne reste silencieuse que pour un texte de lancement refusé et pour L4 (décision 3) ;
- « PR prête » exige que le dernier run de `.github/workflows/ci.yml` (chemin et nom « CI ») de
  chaque événement sur la tête soit terminé en `success`, et que les deux événements `push` et
  `pull_request` soient présents : dans Kass'Beer, chaque tête a deux runs, et la CI de la
  fusion avec `main` compte. Un run dont `head_repository.full_name` n'est pas
  `ChinaFred/KassBeer` est ignoré ;
- le serveur écrit les échéances à jour : un blocage relevé libère le verrou, ramène le
  `retry_after` de l'entrée de livraison à l'heure du relevé et la marque
  `ended_by: "blocked"` ; un ticket qui quitte « En cours » libère le verrou qu'il tient. Le
  client ne lit que `retry_after` et `ended_by` (texte « s'est arrêtée » ou « n'a rien
  fusionné »), sans règle recopiée ni fixture partagée ;
- un ticket dont la PR est prête entre dans le filtre « À traiter » de la liste seulement ; le
  compteur du menu reste calculé sur le statut (décision 7) ;
- la section « Livraison (N) » se place juste après la description, avant « Analyses », ouverte
  (décision 8) ;
- un 403 sur `GET /actions/runs` est une panne à part (décision 14) : `launchTicketDelivery`
  refuse en `github_actions_forbidden` (« Le jeton GitHub ne peut pas lire la CI : sur
  GitHub, donnez-lui le droit « Actions : lecture ». »), sans décompte ; le serveur pose
  `ticket_status/launches.ci_read_denied_since`, effacé à la lecture suivante réussie des runs
  d'une PR éligible. La fiche d'un ticket En cours affiche cette ligne seulement si
  `admin/delivery` porte une seule PR éligible, et la liste ne montre ni « CI en cours » ni
  « PR prête » tant que le champ est posé. `token_invalid_since` n'est pas posé : le jeton
  sert par ailleurs (exception écrite dans P25) ;
- sont sensibles aussi (décision 15) : `app/android/gradlew` et `app/android/gradlew.bat`
  (lancés par `flutter build apk` dans le job qui détient la clé de signature), `**/hook/**`
  (build hooks Dart, exécutés à la compilation), `**/.claude/**` à toute profondeur (au lieu
  de `.claude/**` à la racine seule : consignes chargées par les sessions suivantes). Ces
  quatre motifs sont interdits à la session de développement, comme les fichiers de
  construction Android. `functions/src/auth.ts`, `functions/src/config.ts`,
  `functions/src/tickets/delivery.ts` et `test-fixtures/member_access.json` portent le
  contrôle des livraisons, le plafond et l'appartenance : ils sont sensibles pour la livraison
  seule, comme les `pubspec.lock` (la session peut les modifier ; « Livrer » refuse et
  l'administrateur fusionne à la main).

2026-11-14 : l'utilisateur a refusé de rendre tout `functions/src/` sensible pour la
livraison ; seuls `auth.ts`, `config.ts`, `delivery.ts` et `member_access.json` le sont.
Risque accepté : une PR qui modifie un autre fichier du serveur (`launch.ts`, `index.ts`…)
peut retirer un contrôle et rester livrable par « Livrer » ; la liste L3 du prompt et la
relecture de la PR par l'administrateur restent les protections.

### Prompts

Les deux prompts de Kass'Dalle sont repris dans `exigences-techniques.md` avec ces
substitutions : `ChinaFred/KassBeer`, `main`, `app/pubspec.yaml` (build + 1, P7),
`git fetch --tags && node scripts/check-version.mjs`, liste des fichiers sensibles ci-dessus,
contrôles de « Commandes utiles », `statut:en-cours` posée avant le premier commit (`CLAUDE.md`,
« Tickets »). Ajouts : arrêt avant le premier commit si `git var GIT_AUTHOR_IDENT` n'est pas une
adresse `noreply` (P15) ; aucun tag.

2026-11-13, décision de l'utilisateur (lot T4) : l'arrêt avant le premier commit vaut aussi
pour `git var GIT_COMMITTER_IDENT`. Le prompt d'analyse limite les appels GitHub à une liste
fermée : lire l'Issue et ses commentaires, publier un commentaire « ## Analyse », retirer
`statut:à-analyser` et poser `statut:analysé`. Tout autre appel est interdit : aucune autre
étiquette (ni `validé`), aucune fermeture, aucune autre Issue ou pull request, aucune fusion. Un test de `functions/test/` vérifie que la liste des
fichiers sensibles du prompt égale celle de `delivery.ts`.

2026-11-14 (lot T5) : le prompt de développement s'aiguille sur le premier mot du texte :
`developpement` (points 2 à 9), `livraison` (partie « Livraison », L0 à L11) et `reprise`
(partie « Reprise », R1 à R7 : même branche et même PR, aucune nouvelle PR, aucune étiquette,
aucun `--force`, aucune relance de workflow, arrêt expliqué dans le résumé seulement).
`prompts.test.ts` raisonne par routine et compare la liste L3 à `delivery.ts`.

### Capture d'écran

Remplacé en partie par la note du 2026-11-14 (point 4) : création seule, PNG seul. Le choix
d'image, d'abord écarté (point 2), revient par le complément du 2026-11-14 (point D).

Copie de Kass'Dalle. Case « Joindre une capture de l'écran précédent » décochée par défaut,
capture par un `RepaintBoundary` autour du routeur, ou choix d'une image. PNG ou JPEG, 5 Mo au
plus, textes de Kass'Dalle. Envoi : le ticket se crée dans Firestore (T1), puis l'image monte
dans Storage, puis `attachTicketScreenshot({ticketId, path})` vérifie l'auteur, l'existence,
le type annoncé, 5 Mo, la signature (`89 50 4E 47 0D 0A 1A 0A` ou `FF D8 FF`) et écrit
`screenshot_path`. Sans réseau ou en échec : « Ticket envoyé sans la capture. ». L'Issue porte
« Capture disponible dans Admin › Tickets. » ; la capture ne part jamais sur GitHub.

Deux écarts. Le choix d'image passe par le canal d'ADR-007 (`choisir(maxOctets: 5 Mo)`), et non
par `image_picker` : P28 refuse un sélecteur tiers sans ADR qui remplace ADR-007. Sur un écran
de coût ou de prix, la case n'est pas offerte, et l'avertissement ajoute « Elle peut montrer vos
prix. ». Exception à P5 : la capture est un partage choisi par le membre vers l'administrateur.

2026-11-14, décisions de l'utilisateur (lot T6, ticket #38) : six écarts à ce qui précède.

1. **Capture partout, prix compris.** La case est offerte à tout membre sur toute page qui porte
   le menu du compte, écrans de prix et de coût compris (Recette, Brassin, jour de brassage,
   journée suivante, Préparer la journée, Mes prix). Sur ces écrans, la section affiche « La
   capture peut montrer vos prix : l'administrateur la verra. ». C'est un écart à P5 et à
   l'écart « la case n'est pas offerte » ci-dessus : la capture est un partage choisi par le
   membre vers l'administrateur, case décochée par défaut. Elle ne part jamais sur GitHub ni
   dans un rapport d'erreur, et ni son contenu ni son nom de fichier n'entrent dans un journal.
2. **Pas de choix d'image.** Ni `image_picker`, ni le canal d'ADR-007 : seule la capture de
   l'écran quitté, prise par un `RepaintBoundary` autour du contenu de la page (corps du
   `Scaffold` de la coquille et des pages pleines, sans barre du haut ni barre de navigation),
   au moment de l'appui et avant la navigation. PNG seul côté client, échelle 2 au plus,
   2 000 px au plus de côté, 5 Mo au plus, en mémoire seulement. Aucune capture depuis « Mes
   tickets », l'adresse du formulaire ou « Reprendre ».
3. **Envoi en arrière-plan.** Le formulaire se ferme sans attendre ; le dépôt part une fois le
   ticket accepté par le serveur, au plus 30 s après l'envoi. Échec ou hors ligne : ticket sans
   capture, « Ticket enregistré sans la capture. » (ce texte remplace « Ticket envoyé sans la
   capture. »).
4. **`storage.rules` plus strict que Kass'Dalle.** Création seule (`resource == null`), par
   l'auteur membre, `tickets/{ticketId}` existant avec `author_uid == request.auth.uid`
   (`firestore.get`), `screenshot.png` seul en `image/png` (le client ne produit que ce nom),
   de 1 octet à 5 Mo ; lecture par l'auteur membre et l'administrateur ; remplacement, liste
   et suppression refusés : la capture contrôlée par `attachTicketScreenshot` (signature PNG
   seule) reste celle que l'administrateur lit. Ni l'application ni la callable ne
   journalisent le message ou la pile d'une erreur de Cloud Storage, qui portent le chemin :
   le code seul. Tests sur l'émulateur Storage pour les cinq profils de P4 et la fixture
   `member_access.json` (P31).
5. **Phrase fixe sur chaque Issue.** « Capture éventuelle disponible dans Admin › Tickets. »
   termine le corps de toute Issue, qu'une capture soit jointe ou non (gabarit de P24) : la
   phrase ne dit pas qu'un ticket a une capture.
6. **Pas de purge.** Une capture reste dans le bucket ; une capture déposée sans
   `screenshot_path` (callable en échec) n'est lue par personne. Remplacé par le point C du
   complément ci-dessous.

2026-11-14, complément du lot T6 (décisions de l'utilisateur, après la livraison de v0.1.41) :

A. **Délai d'une heure.** `storage.rules` refuse la création si `tickets/{ticketId}.created_at`
   a plus d'une heure (`created_at > request.time - duration.value(1, 'h')`). La capture part
   juste après la création du ticket ; aucun dépôt ne vise un ancien ticket. Le statut publié
   n'est pas contrôlé : la capture est acceptée dès la création (auteur, moins d'une heure,
   sans capture). Risque accepté par l'utilisateur : un compte volé peut joindre une image à
   un ticket qu'il vient de créer ; seul l'administrateur la lit.
B. **Dimensions.** `attachTicketScreenshot` lit les 24 premiers octets du fichier (lecture
   partielle) : signature PNG, bloc `IHDR`, largeur et hauteur. Un côté au-delà de 2 000 px est
   refusé (`dimensions_refused`). Le client ne produit pas plus grand (capture et image
   choisie réduites à 2 000 px).
C. **Rétention de 180 jours.** Une règle de cycle de vie du bucket efface les objets sous
   `tickets/` 180 jours après leur création ; la suppression réversible (soft delete) est
   désactivée. Les deux réglages sont faits par l'administrateur (2026-11-14,
   `exigences-techniques.md`, « Captures des tickets — réglages faits une fois »). Le serveur
   écrit `screenshot_expires_at` (rattachement + 180 jours) avec `screenshot_path`, champ
   serveur (P23). Échéance passée, ou fichier absent (`object-not-found`) : la fiche affiche
   « Capture effacée », sans lecture ni rapport d'erreur.
D. **« Choisir une image ».** Dans le formulaire, sous la case : une seule image, exclusive de
   la capture de l'écran (choisir décoche la case, cocher retire l'image), aperçu, « Retirer
   l'image ». Le sélecteur passe par le canal d'ADR-007 : `EchangeFichiers.choisir` reçoit
   un argument facultatif de types (`EXTRA_MIME_TYPES` et type `image/*` sur Android,
   attribut `accept` sur le web), borne de 5 Mo passée par le Dart (P17, P28) ; aucun
   `image_picker` ni `file_picker`. Toute image choisie est décodée par `dart:ui` (côté long
   réduit à 2 000 px), puis réencodée en PNG, ce qui retire les métadonnées EXIF : le serveur
   et `storage.rules` restent en PNG seul. Textes : « Cette image n'a pas pu être ouverte.
   Choisissez-en une autre. », « Cette image dépasse 5 Mo. Choisissez une image plus
   légère. ». L'avertissement des prix reste celui du point 1.
E. **Bucket en `us-east1`.** L'administrateur a créé `kassbeer.firebasestorage.app` en
   `us-east1` (vérifié par `gcloud`), et non en `europe-west1` comme prévu ci-dessous : choix
   de l'utilisateur pour le niveau gratuit de Cloud Storage, réservé à `us-east1`, `us-west1`
   et `us-central1`. Firestore et les Functions restent en `europe-west1`. Le transfert entre
   régions est négligeable : une capture de 5 Mo au plus par ticket, 24 octets lus par la
   callable, une lecture par fiche ouverte.
   Constat : les captures sont stockées en `us-east1`, hors de l'Union européenne, par choix
   de l'utilisateur pour le niveau gratuit. Ce transfert est couvert par les clauses
   contractuelles types de Google (conditions de traitement des données de Google Cloud). Les
   captures sont effacées après 180 jours (point C). Une capture peut montrer un nom ou un
   e-mail : c'est pourquoi seuls l'auteur et l'administrateur la lisent (`storage.rules`).

`github-deploy` peut demander, pour publier `storage.rules`, un rôle de lecture du bucket par
défaut (`roles/firebasestorage.viewer`, à vérifier au premier déploiement) : c'est le seul rôle
que T6 peut ajouter à la liste de P14. `tickets-functions` reçoit `roles/storage.objectViewer`
sur le seul bucket par défaut.

**Cloud Storage.** Bucket `kassbeer.firebasestorage.app`, prévu en `europe-west1` (région
de la base), créé en `us-east1` (complément du 2026-11-14, point E). Note du 2026-11-14
(v0.1.42) : Firebase ne le déclare pas comme bucket par défaut ; l'application, les Functions
et `deploy.yml` le nomment (`exigences-techniques.md`, « Captures des tickets — réglages faits
une fois »). `storage.rules` (note du 2026-11-14, point 4, et complément, point A) : `match
/tickets/{uid}/{ticketId}/{fileName}` ; lecture par le membre propriétaire ou
l'administrateur ; création seule (`resource == null`) par le propriétaire membre, ticket
existant dont il est l'auteur, créé il y a une heure au plus, `fileName` égal à
`screenshot.png`, type `image/png`, de 1 octet à 5 Mo ; mise à jour, liste, suppression et
tout autre chemin refusés. L'appartenance se lit par
`firestore.get(members/{email en minuscules})`. L'agent de service de Storage doit pouvoir
lire Firestore (accordé par la console au premier déploiement de règles croisées, à
vérifier). Lecture sur le web par `getData()` : une règle CORS du bucket pour
`kassbeer.web.app` et `kassbeer.firebaseapp.com` est à vérifier au lot T6. Tests sur
l'émulateur Storage dans `rules-tests/`. `firebase.json` reçoit `storage` ; `deploy.yml`
déploie les règles Storage (P10, P14).

### Paquets client

`cloud_functions` (T3) et `firebase_storage` (T6), montés avec la famille FlutterFire dans la
même commande (P6) ; `flutter_markdown_plus` et `markdown` (T3), version exacte. Les instances
`FirebaseFunctions` et `FirebaseStorage` se construisent au premier usage et sont mémorisées.
Taille du `main.dart.js` mesurée avant et après chaque lot, par `flutter build web --release`.

### Lots

Ils commencent après la fusion de T2. Estimations non mesurées, tirées des tailles de Kass'Dalle.

| Lot | Contenu | Après | Serveur avec tests | Client | Règles et tests |
|---|---|---|---|---|---|
| T2 | livré tel quel (décisions par documents) | — | fait | fait | fait |
| T3 | `githubTicketWebhook`, `auth.ts` et `member_access.json`, statut `analyzed`, étiquettes, relevé des analyses, `answerTicketAnalysis` ; `cloud_functions`, `flutter_markdown_plus`, `markdown` ; section « Analyses (N) », « Répondre » | T2 | 1 400 à 1 800 | 1 200 à 1 500 | 100 à 200 |
| T4 | `launchTicketAnalysis`, `launchTicketDevelopment`, `routine.ts`, plafond, `ticket_status/launches`, bandeaux des routines, section « Lancements (N) », prompts | T3 | 1 400 à 1 700 | 1 000 à 1 300 | 100 à 150 |
| T5 | `launchTicketDelivery`, `admin/delivery`, événements `pull_request` et `workflow_run`, verrou global, « Livrer », section « Livraison (N) » | T4 | 1 100 à 1 400 | 500 à 800 | 50 à 100 |
| T6 | bucket, `storage.rules`, `attachTicketScreenshot`, `firebase_storage`, capture et affichage | T3 | 250 à 350 | 800 à 1 000 | 200 à 300 |
| T7 | `validateTicket`, `refuseTicket`, `closeTicket`, `retryTicketSend` en callables ; retrait des déclencheurs et des règles de `decisions/` | T3 | 400 à 600 | 300 à 500 | − 150 à − 250 |

### Réglages faits une fois

| Lot | Réglage |
|---|---|
| T3 | secret `GITHUB_WEBHOOK_SECRET` (`openssl rand -hex 32`) créé avant le déploiement ; webhook du dépôt : adresse de `githubTicketWebhook` affichée par le déploiement, `application/json`, ce secret, SSL vérifié, événements Issues et Issue comments (T5 : Pull requests, Workflow runs), `ping` en 200 ; rôles de `github-deploy` sur ce secret ; invocation publique des callables et du webhook (Cloud Run) |
| T4 | deux routines sur claude.ai/code, dépôt `ChinaFred/KassBeer` seul, aucun connecteur, déclencheur API, prompts collés ; secrets `TICKETS_ROUTINE_ANALYSIS_ID`, `TICKETS_ROUTINE_ANALYSIS_TOKEN`, `TICKETS_ROUTINE_DEV_ID`, `TICKETS_ROUTINE_DEV_TOKEN`, même vides, avant le déploiement |
| T5 | avant la fusion : jeton `GITHUB_TICKETS_TOKEN` étendu à Actions en lecture, prompt de la routine de développement recollé sur claude.ai (compatible avec le serveur de T4), événements « Pull requests » et « Workflow runs » cochés sur le webhook du dépôt ; aucun secret nouveau |
| T6 | bucket en `us-east1`, nommé dans le code (point E du complément du 2026-11-14 et note du 2026-11-14 ci-dessus), cycle de vie de 180 jours sous `tickets/` et suppression réversible désactivée (point C) ; accès de l'agent Storage à Firestore ; CORS du bucket si `getData()` l'exige ; rôle de `github-deploy` pour publier les règles Storage (à vérifier) |
| T7 | avant la fusion : aucune décision `pending` ni `applying` (requête de groupe sur `decisions` dans la console), puis `firebase functions:delete onDecisionCreated onDecisionUpdated --region europe-west1 --project kassbeer --force` depuis le poste de l'utilisateur ; après le déploiement : invocation publique de `validateTicket`, `refuseTicket`, `closeTicket` et `retryTicketSend` à vérifier (une erreur `unauthenticated` pour l'admin signale un réglage manquant) ; facultatif : suppression des index `tickets (status, retry_requested_at)` et `decisions (state, lease_until)`, `decisions (state, requested_at)` dans la console |

Six secrets en tout : la limite de six versions actives gratuites est atteinte (à vérifier).
Une rotation détruit la version précédente (`gcloud secrets versions destroy`). Un secret
remplacé ne vaut qu'après un redéploiement des fonctions qui le montent.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : boutons, boîtes, sections et capture dans `app/`.
   Création du ticket dans `firestore.rules`. Callables, webhook, lancements, relevés, PR prête
   et vérification de la capture dans `functions/` (Node 24, `europe-west1`). Capture dans
   Cloud Storage, sous `storage.rules`. Les sessions tournent chez Anthropic, avec l'identité
   GitHub du propriétaire. Rien dans l'écran du jour de brassage (P2).
2. **Ce qui existera en double** : la vérification d'appartenance existe dans
   `firestore.rules`, `storage.rules` et `functions/src/auth.ts`, verrouillée par
   `member_access.json`. La liste des fichiers sensibles existe dans `delivery.ts` et dans le
   prompt, verrouillée par un test. Les préconditions des décisions restent au serveur seul.
3. **Ce qui pèse au démarrage** : quatre paquets client ; instances construites au premier
   usage. Côté serveur, `fetch` seul pour GitHub et Anthropic (leçon 5). Le webhook partage le
   bundle des Functions : aucun import lourd au niveau module (P26).
4. **Compilation de chaque cible** : `cloud_functions` et `firebase_storage` touchent Android
   et le web. Job « Android — compilation » et `flutter build web --release` à chaque lot
   (P6). `(cd rules-tests && npm test)` lance aussi l'émulateur Storage à partir de T6.
5. **Qui voit quoi** : le membre voit son ticket, `reply_text` et sa capture. L'administrateur
   voit en plus analyses, lancements (lien de session), comptes rendus, « PR prête ». Sur
   l'Issue publique s'ajoutent analyses, précisions et comptes rendus. Les sessions n'ont aucun
   accès à Firestore ni à Storage. Le corps envoyé à Anthropic se limite à « <action> #N ».
6. **Ce qui coûte à l'usage, plafond** : poste `ticket_routine_launch`, 10 par jour, sur
   l'abonnement Claude. Storage : 100 captures de 5 Mo font 0,5 Go, hors niveau « Always
   Free » en `europe-west1` (à vérifier). Functions : quelques centaines d'appels par mois.
   Dépense estimée : moins de 0,05 € par mois hors attaque.
7. **Exposition** : huit points d'accès publics, dont un sans compte (le webhook, protégé par
   sa signature). Callables : membre ou admin relu à chaque appel. `maxInstances` sur chacun.
   Sortie nouvelle : `api.anthropic.com`.
8. **Exploitation, sauvegarde, mise à jour** : réglages du tableau ci-dessus. Les captures ne
   sont pas dans la sauvegarde de Firestore ; une capture perdue ne casse pas le ticket.
   Webhook perdu : la tâche horaire rattrape.
9. **Coût de sortie** : moyen. Retirer les callables et le webhook revient à l'option C. Les
   Issues et les PR restent sur GitHub. Le bucket se vide et se supprime. L'API des routines
   est expérimentale : un changement de forme coûte une reprise de `routine.ts`.

## Conséquences

Plus simple : l'administrateur traite un ticket de bout en bout depuis l'application, avec un
résultat immédiat dans la boîte de dialogue. Le membre joint une capture.

Plus difficile : le projet expose huit points d'accès publics et un service de plus. La
vérification d'appartenance existe en trois langages de règles et de code. Une session lancée
publie sur un dépôt public avec l'identité du propriétaire. La session de livraison fusionne
sur `main`, qui se déploie seul : le ruleset à 0 approbation ne l'empêche pas. Les garde-fous
sont la validation humaine de l'analyse, la liste des fichiers sensibles, le verrou d'une
livraison à la fois.

`CLAUDE.md` change : « Le projet » (callables, webhook, Storage, routines), « Structure »
(`storage.rules`, `test-fixtures/`), « Commandes utiles » (émulateur Storage), « Coûts
variables » (premier poste), « Logique dupliquée » (`member_access.json`), « Tickets », P5
(exception de la capture), P23 à P27 modifiés, P29 à P34 ajoutés au lot T3 (2026-11-12), les suivants par lot. ADR-006 reçoit « Modifié
par : ADR-008 (option C, décisions 1 et 5, P25) » ; ADR-001 aussi.

## Sources

Consultées le 2026-11-11.

- API de déclenchement d'une routine : expérimentale, aucune clé d'idempotence, 30 appels par
  heure et par routine, 100 par heure et par compte, usage décompté de l'abonnement :
  https://platform.claude.com/docs/en/api/claude-code/routines-fire
- Routines, en aperçu de recherche ; branches `claude/` ; rulesets appliqués à l'accès GitHub
  connecté ; crédits d'usage : https://code.claude.com/docs/en/routines
- Cloud Storage for Firebase : plan Blaze requis, « Always Free » limité à `us-central1`,
  `us-east1`, `us-west1` (à vérifier) :
  https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024
- Secret Manager, six versions actives gratuites (à vérifier) :
  https://cloud.google.com/secret-manager/pricing
- Cloud Run, niveau gratuit (à vérifier) : https://cloud.google.com/run/pricing
- Kass'Dalle : `documentation/TechnicalRequirements.md` §3.12 bis, « Tickets », « Routines des
  tickets » ; `documentation/FunctionalRequirements.md` §5.13 ;
  `kass_dalle/functions/src/tickets/routine.ts`, `webhook.ts` (`invoker: "public"`,
  `maxInstances: 5`) ; `kass_dalle/functions/src/callable/_auth.ts` (App Check par politique en
  base) ; `kass_dalle/storage.rules` ; `kass_dalle/pubspec.yaml` ; `documentation/CHANGELOG.md`
  (liste CORS des callables) ; comptes de lignes par `wc -l`.
- Kass'Beer : `functions/src/index.ts`, `functions/src/config.ts`, `app/pubspec.yaml`,
  `documentation/exigences-techniques.md` (rulesets) ; ADR-005, option C (≈ 124 $ par mois).
- Verdict Play Integrity d'un APK installé hors Google Play : à vérifier.
- Estimations non mesurées : volume de code des lots T3 à T7.
