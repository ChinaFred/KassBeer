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
| `validateTicket`, `refuseTicket`, `closeTicket`, `retryTicketSend` | `onCall` | `requireAdmin` | T7 | 2, 60 s |

Tout autre `onRequest` ou `onCall` demande un nouvel ADR.

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

### Livraison

Copie de `delivery.ts` : état « PR prête » (`tickets/{id}/admin/delivery`), verrou global
`delivery_running` (3 h), comptes rendus `## Livraison — blocage` et `## Livraison — terminée`.
Fichiers sensibles refusés par `launchTicketDelivery` et par le prompt (casse ignorée, ancien
chemin d'un renommage compris) : `.github/**`, `.claude/**`, `scripts/**`, tout `CLAUDE.md`,
`CLAUDE.local.md`, `.mcp.json`, `firebase.json`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `rules-tests/package.json`, `rules-tests/package-lock.json`,
`rules-tests/prettier.config.*`, `functions/package.json`, `functions/package-lock.json`,
`functions/prettier.config.*`. La session ne pose jamais de tag : le job `tag` de `deploy.yml` le
fait (leçon 16). Jeton GitHub : Actions en lecture ajouté.

### Prompts

Les deux prompts de Kass'Dalle sont repris dans `exigences-techniques.md` avec ces
substitutions : `ChinaFred/KassBeer`, `main`, `app/pubspec.yaml` (build + 1, P7),
`git fetch --tags && node scripts/check-version.mjs`, liste des fichiers sensibles ci-dessus,
contrôles de « Commandes utiles », `statut:en-cours` posée avant le premier commit (`CLAUDE.md`,
« Tickets »). Ajouts : arrêt avant le premier commit si `git var GIT_AUTHOR_IDENT` n'est pas une
adresse `noreply` (P15) ; aucun tag. Un test de `functions/test/` vérifie que la liste des
fichiers sensibles du prompt égale celle de `delivery.ts`.

### Capture d'écran

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

**Cloud Storage.** Bucket par défaut `kassbeer.firebasestorage.app`, créé en `europe-west1`
(région de la base ; choix définitif à la création). `storage.rules` :
`match /tickets/{uid}/{ticketId}/{fileName}` ; lecture par le membre propriétaire ou
l'administrateur ; création et mise à jour par le propriétaire membre, `fileName` égal à
`screenshot.png` ou `screenshot.jpg`, `request.resource.size <= 5 * 1024 * 1024`, type
`image/png` ou `image/jpeg` ; tout le reste refusé. L'appartenance se lit par
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
| T5 | jeton `GITHUB_TICKETS_TOKEN` étendu à Actions en lecture |
| T6 | bucket par défaut en `europe-west1` ; accès de l'agent Storage à Firestore ; CORS du bucket si `getData()` l'exige ; rôle de `github-deploy` pour publier les règles Storage (à vérifier) |

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
