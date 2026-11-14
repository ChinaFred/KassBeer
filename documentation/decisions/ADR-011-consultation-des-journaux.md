# ADR-011 — Consultation des journaux par l'administrateur : Admin › Rapports d'erreur et Admin › Journaux

- **Statut** : accepté le 2026-11-14
- **Date** : 2026-11-14
- **Remplace** : — . Ajoute une callable, `queryLogs`, à la liste fermée « Points d'accès
  autorisés » d'ADR-008 (P25) ; ADR-008 reste en vigueur pour le reste. Ajoute un rôle IAM au
  compte d'exécution `tickets-functions` (ADR-006, ADR-008). Ne change ni ADR-001 (règles
  Firestore, seul contrôle d'accès du client) ni ADR-002.

## Contexte

Demande de l'utilisateur, le 2026-11-14 : « Copier dans Kass'Beer le système de visualisation
des logs de kassdale. »

Ce qui existe dans Kass'Dalle (dépôt lu le 2026-11-14) :

- `kass_dalle/functions/src/callable/logsCallable.ts` (404 lignes) : callable `queryLogsFn`,
  admin seul, lit Cloud Logging par `@google-cloud/logging` chargé par `await import()`, sur le
  journal `kass-dalle-pipeline` que ses Functions écrivent elles-mêmes ; filtres `severity`
  (liste blanche, seuil), `correlationId`, `scanId`, `jobId`, `userId`, `freeText`, période de
  1 à 10 080 minutes, pages de 1 à 200 entrées, `nextPageToken` ; relit `ai_usage` pour joindre
  le coût de chaque appel d'IA ;
- client : `logs_screen.dart` (1 060 lignes), `logs_repository.dart` (178),
  `log_entry.dart` (56), `log_scan_group.dart` (330, regroupement scan → appel → ligne),
  `log_treatment_label.dart` (228) ; tests `log_scan_group_test.dart` (364),
  `log_treatment_label_test.dart` (150), `logsFilter.test.ts` (48) ;
- un écran « Rapports d'erreur » qui lit `error_reports/` dans Firestore ;
- documentation : `TechnicalRequirements.md`, §7.1 (« Trois journaux, trois publics ») et §7.5.

Ce qui existe dans Kass'Beer (dépôt lu le 2026-11-14, v0.1.39) :

- `functions/src/logging.ts` écrit par `firebase-functions/logger` sur la sortie standard des
  fonctions de 2e génération ; aucun client `@google-cloud/logging` (leçon 5). Champs :
  `feature`, `ticketId`, `errorDescription`, `stack`, et ceux de `extra`. Aucun
  `correlationId`, `scanId`, `jobId` ni `userId`. `redactSecrets` retire ce qui a la forme
  d'un jeton GitHub ;
- `functions/package.json` : deux dépendances d'exécution, `firebase-admin` 14.5.0 et
  `firebase-functions` 7.4.0 ;
- aucune IA dans l'application ; seul poste variable : `ticket_routine_launch` (ADR-008) ;
- `error_reports/` : écrit par `ErrorReportService` (P13), lisible et supprimable par l'admin
  (`firestore.rules`, bloc `error_reports`). Aucun écran ne le lit ;
- Admin (`app/lib/features/admin/presentation/admin_screen.dart`, 84 lignes) : Membres,
  Tickets, Import ;
- compte d'exécution `tickets-functions@kassbeer.iam.gserviceaccount.com` : rôles
  `datastore.user`, `eventarc.eventReceiver`, `run.invoker`, accès aux secrets
  (`exigences-techniques.md`, « Réglages faits une fois »). Aucun rôle de Cloud Logging ;
- la liste fermée des points d'accès est vérifiée par `jq` sur le manifeste des fonctions dans
  `.github/workflows/ci.yml` (ligne 267) et deux fois dans `deploy.yml` (lignes 447 et 571).

Ce qui n'a pas d'objet dans Kass'Beer : le regroupement par scan et par appel, les libellés de
traitement, la jointure des coûts d'IA (`ai_usage`, taux de change). Ils représentent
1 216 lignes sur 2 414 du système de Kass'Dalle.

Contraintes concernées : dépôt public (ADR-002) ; données personnelles limitées au nom et à
l'e-mail (RGPD) ; dépense visée ≈ 0 € par mois, alerte à 5 € ; « Aucune dépendance lourde
chargée au démarrage » ; liste fermée des callables (P25) ; « Pas de valeur de repli figée ».

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne pas le faire | rien à écrire ni à déployer ; l'Explorateur de journaux de la console Google Cloud lit déjà tout, pour le propriétaire du projet | `error_reports/` n'est lu par personne ; la console est peu lisible sur téléphone et montre aussi les journaux de requêtes (adresses IP) et d'audit ; contraire à la demande | 0 € / 0 € |
| A. Admin › Rapports d'erreur seul, sur `error_reports/` | aucune callable, aucun rôle IAM, aucune dépendance ; règles et tests déjà en place ; couvre les pannes des appareils, aujourd'hui lues par personne | les journaux des Functions restent dans la console | 0 € / lectures Firestore, ≈ 0 € |
| B. A, puis Admin › Journaux par la callable `queryLogs`, appel REST `entries:list` par `fetch` (recommandée) | parité avec Kass'Dalle sur ce qui a un objet ici ; aucune dépendance ajoutée ; réponse JSON sans les `Long` protobuf que `logsCallable.ts` convertit en trois endroits ; filtre construit par le serveur seul | un point d'accès de plus ; un rôle IAM ; les listes des workflows à modifier (P10, P14) | 0 € / ≈ 0 € (à vérifier) |
| C. Comme B, avec `@google-cloud/logging` chargé par `await import()` | copie ligne à ligne de `logsCallable.ts` | ajoute `@google-cloud/logging`, qui tire gRPC, `google-gax` et protobuf dans `functions/package-lock.json` et le bundle des neuf fonctions ; conversions de `Long` et de dates à recopier ; contraire au commentaire de `logging.ts` | 0 € / ≈ 0 € |

## Décision

Option B, en deux lots. **J1** : Admin › Rapports d'erreur, sur `error_reports/`, sans
serveur. **J2** : Admin › Journaux, par la callable `queryLogs`, qui appelle l'API REST
`entries:list` de Cloud Logging par `fetch`, avec un jeton du serveur de métadonnées. Le serveur impose
au filtre une clause qui limite la lecture à la sortie des fonctions.

Raison principale : la part utile du système de Kass'Dalle (filtres, pagination, lecture admin
seule) se copie sans ajouter de dépendance ni toucher au démarrage, et la part propre à
Kass'Dalle (scan, coûts d'IA) n'a ici rien à afficher.

### Choix de l'utilisateur (2026-11-14)

- Périmètre : J1, puis J2.
- Les adresses e-mail des journaux ne sont pas masquées : l'admin les lit telles quelles, pour
  diagnostiquer le problème d'un compte précis. Elles restent dans l'application, lue par
  l'admin seul, et ne se recopient jamais dans une Issue (ADR-002, P24).
- Admin › Rapports d'erreur est en lecture seule : aucune suppression depuis l'écran.
- Rôle IAM : `roles/logging.viewer` sur le projet. Aucune vue de journaux à créer. Le filtre
  du serveur ajoute toujours la clause qui limite la lecture à la sortie des fonctions.

### J1 — Admin › Rapports d'erreur

- Lecture de `error_reports/` par l'admin : `orderBy('created_at', descending: true)`,
  `limit(50)`, `startAfterDocument` pour la suite, `get()`, aucun écouteur. Règles
  inchangées ; un test de `rules-tests/` ajoute le cas « requête paginée » pour les cinq
  profils de P4 s'il n'existe pas.
- Une ligne : date, `feature`, `platform`, `app_version`, première ligne de `error`. Détail :
  `error`, `context`, `stack_trace` en texte brut, sélectionnable. `uid` affiché tel quel ;
  aucune lecture de `users/` ni de `members/` pour le traduire.
- Aucune suppression depuis l'écran (lecture seule, choix du 2026-11-14). `error_reports/`
  n'a pas de rétention.
- Tuile « Rapports d'erreur » dans `admin_screen.dart`.

### J2 — Admin › Journaux, callable `queryLogs`

**Réglages** : `onCall`, `requireAdmin` (P30) en première instruction, `maxInstances: 1`,
`concurrency: 1`, `timeoutSeconds: 60`, 256 Mio, `cors` de `CALLABLE_ORIGINS`, compte
`RUNTIME_SERVICE_ACCOUNT`, aucun secret monté.

**Lecture** : `POST https://logging.googleapis.com/v2/entries:list`, `redirect: "error"`,
`AbortSignal.timeout(20_000)`, un seul appel par appel de la callable. Jeton :
`GET http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token`
avec `Metadata-Flavor: Google`, obtenu à l'appel, mémorisé jusqu'à son échéance moins 60 s,
jamais journalisé ni rendu. Sous l'émulateur, sans serveur de métadonnées : « Journaux non
disponibles dans l'émulateur », sans appel.

**Ressource lue** : `resourceNames: ["projects/kassbeer"]`, l'identifiant du projet lu dans
l'environnement d'exécution (`GCLOUD_PROJECT`), jamais dans un argument. Le filtre commence
toujours par la clause `resource.type="cloud_run_revision" AND
(LOG_ID("run.googleapis.com/stdout") OR LOG_ID("run.googleapis.com/stderr"))`, que le client ne
peut ni retirer ni changer. Ni les journaux de requêtes (`run.googleapis.com/requests`, qui
portent l'adresse IP et l'agent de l'appelant), ni les journaux d'audit ne sont rendus. Les
noms de `LOG_ID` et du type de ressource se vérifient sur le premier journal lu (à vérifier).

**Filtre** : construit par le serveur seul, à partir de valeurs contrôlées. Aucune chaîne du
client n'entre dans le filtre sans passer par l'une de ces lectures :

| Argument | Lecture | Clause |
|---|---|---|
| `severity` | `DEBUG`, `INFO`, `WARNING`, `ERROR`, absent ; autre valeur : `invalid-argument` | `severity>=X`, `severity=DEBUG` pour `DEBUG` (comme `severityClause` de Kass'Dalle) |
| `functionName` | liste fermée des fonctions déployées, tirée de `index.ts` par une constante de `config.ts` ; autre valeur : `invalid-argument` | `resource.labels.service_name="<nom en minuscules>"` (à vérifier) |
| `ticketId` | `^[A-Za-z0-9_-]{1,128}$` | `jsonPayload.ticketId="…"` |
| `freeText` | taille brute bornée (`requireBoundedText`), 1 à 100 caractères, aucun caractère de contrôle | `jsonPayload.message:"…"`, guillemets et barres obliques inverses échappés |
| `periodMinutes` | `60`, `1440` ou `10080` ; défaut `60` | `timestamp>="<ISO>"` |
| `pageToken` | chaîne de 1 à 2 000 caractères, opaque | passé à l'API avec le même filtre |

`pageSize` est fixé à 50 par le serveur. Les clauses sont jointes par `AND`.

**Réponse** : par entrée, `timestamp` (chaîne RFC 3339 rendue par l'API), `severity`,
`functionName`, `message`, `insertId`, et `payload` : le `jsonPayload` sans `message`,
sérialisé. Chaque texte passe par `redactSecrets`, puis est coupé à 8 000 caractères. Les adresses
e-mail restent visibles (choix du 2026-11-14). La réponse porte aussi `nextPageToken` et la
liste `functions` des noms filtrables : le client construit son menu depuis cette liste et ne
la recopie pas. Le filtre n'est pas rendu.

**Erreurs** : 429 de l'API → `resource-exhausted`, « Quota de lecture des journaux atteint,
réessayez dans une minute. » ; 401 ou 403 → `failed-precondition`, « Lecture des journaux non
autorisée : rôle IAM manquant. » ; autre échec ou délai → `unavailable`. `logError` dans chaque
`catch`, sans jeton, sans le filtre complet, sans `freeText`. `details` ne porte que `reason`
et `field`.

**Client** : `app/lib/features/admin/` (`data/logs_repository.dart`, `domain/log_entry.dart`,
`presentation/logs_screen.dart`). Liste à plat, du plus récent au plus ancien ; une ligne se
déplie sur le `payload` en texte brut. Recherche lancée par le bouton « Rechercher », jamais
par une frappe ; « Charger la suite » par `nextPageToken`, et « Fin des journaux pour cette
période » quand il manque ; « DEBUG » masqué par défaut. `FirebaseFunctions.instanceFor(region:
'europe-west1')` réutilisé (P6). Tuile « Journaux » dans `admin_screen.dart`.

**IAM et réglage fait une fois** (`exigences-techniques.md`) : donner à `tickets-functions`
`roles/logging.viewer` sur le projet (choix du 2026-11-14). Ce rôle ouvre aussi les journaux de
requêtes au compte qui exécute les fonctions ; la clause imposée par le serveur est la seule
limite de ce que `queryLogs` rend. `roles/logging.viewer` ne donne pas accès aux journaux
d'accès aux données (`roles/logging.privateLogViewer`).

**Livraison de J2 (v0.1.42, 2026-11-14).** Précisions apportées à la livraison, sans changer la
décision :

- `nextPageToken` rendu au client vaut `<période>|<début de la période en ISO>|<jeton de
  l'API>` : la page suivante rejoue le même filtre, que l'API exige identique, au lieu de
  recalculer « maintenant − période ». La période est relue dans la liste fermée ; le début
  n'est ni futur ni antérieur à maintenant − période − 5 minutes. Une page demandée plus tard
  est refusée, et le client relit la première page. Le tout reste borné à 2 000 caractères.
- La réponse porte `maxChars` (8 000) et, par entrée, `messageTruncated` et
  `payloadTruncated`, calculés après `redactSecrets` : le texte est nettoyé avant d'être coupé.
  Le client affiche « Texte coupé à N caractères. » depuis cette valeur, et le message d'un refus de champ depuis la `HttpsError`.
  Aucune borne du serveur n'est recopiée en Dart.
- Les contrôles du manifeste de `ci.yml` et `deploy.yml` vérifient `queryLogs` : `maxInstances`
  1, 60 s, `concurrency` 1, aucun secret.
- `message` vient de `jsonPayload.message`, ou de `textPayload` pour une ligne non structurée
  de `stderr`, et est coupé à 8 000 caractères comme `payload`. Pour un `ERROR`,
  `firebase-functions/logger` écrit la pile de l'appel dans `message` : le filtre `freeText`
  porte aussi sur elle.
- `details.reason` des refus du serveur hors `invalid-argument` est un code (`quota`, `iam`,
  `emulator`, `logging_unavailable`) : le client distingue un `unavailable` du serveur d'une
  coupure du réseau (`unavailable` sans `reason`).
- `roles/logging.viewer` est le seul réglage à faire ; `github-deploy` ne reçoit aucun rôle.
- Noms à vérifier sur le premier journal lu en production : `LOG_ID` `run.googleapis.com/stdout`
  et `stderr`, type `cloud_run_revision`, `service_name` égal au nom de la fonction en
  minuscules.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : J1 sur l'appareil, lecture Firestore sous les règles
   existantes. J2 : filtre, appel de l'API et nettoyage de la réponse dans `functions/` ;
   affichage seul sur l'appareil. Le client ne parle jamais à l'API Cloud Logging.
2. **Ce qui existera en double** : rien. La liste des fonctions filtrables et des sévérités
   vit dans `functions/src/config.ts` ; la liste des fonctions est rendue au client. Les
   quatre sévérités du menu sont un vocabulaire de l'API Cloud Logging, refusé par le serveur
   hors liste : pas de fixture.
3. **Ce qui pèse au démarrage** : rien. Aucune dépendance ajoutée, aucun client au niveau
   module ; `fetch` et le jeton à l'appel (P26). Côté application, deux écrans de plus dans
   `main.dart.js` ; taille avant et après notée (P6).
4. **Compilation de chaque cible** : aucun paquet Dart ajouté (`cloud_functions` 6.5.0 déjà
   dans `app/pubspec.yaml`). `flutter build web --release` et `flutter build apk --release`
   par la CI, comme d'habitude.
5. **Qui voit quoi** : l'admin seul, par les règles (`error_reports/`) et par `requireAdmin`
   (`queryLogs`). Les journaux des Functions contiennent des identifiants de tickets, des
   numéros d'Issue, des descriptions d'erreurs et des piles d'appel ; un message d'erreur
   Firestore peut contenir un chemin `members/{email}`. Les e-mails restent visibles de l'admin
   (choix du 2026-11-14). Rien ne part vers un tiers : la lecture reste chez Google, dans le
   projet `kassbeer`. Le texte d'un journal ne se recopie pas dans une Issue (ADR-002, P24).
6. **Ce qui coûte à l'usage, plafond** : lecture par l'API Cloud Logging non facturée, selon
   la page de prix de Google Cloud Observability (à vérifier). Quota de `entries.list` :
   60 requêtes par minute et par projet, non augmentable, partagé avec l'Explorateur de
   journaux de la console. Plafond : `maxInstances: 1`, `concurrency: 1`, 50 entrées par page,
   une requête par appui sur un bouton. Aucun poste de coût au catalogue : rien n'est facturé
   à l'appel. Invocations dans la gratuité de Cloud Functions (à vérifier).
7. **Exposition** : `queryLogs` est une callable ouverte sur Internet comme les trois autres,
   gardée par `requireAdmin`. Un compte non admin reçoit `permission-denied` avant toute
   lecture d'argument ; le coût d'un appel refusé est une lecture de `members/`.
8. **Exploitation** : un réglage fait une fois (le rôle), à décrire dans
   « Réglages faits une fois ». Rétention des journaux : 30 jours dans `_Default`, sans coût
   de stockage au-delà de l'ingestion (à vérifier). Rien à sauvegarder. Mise à jour : déploiement
   des Functions par `deploy.yml`, écran par Hosting et l'APK.
9. **Coût de sortie** : faible. La callable n'appelle qu'une API REST documentée ; quitter
   Cloud Logging retire `queryLogs` et un écran. J1 suit Firestore.

## Conséquences

- La liste fermée d'ADR-008 et P25 gagnent `queryLogs` (`onCall`, `requireAdmin`, J2,
  `maxInstances` 1, 60 s). Les listes de `ci.yml` (ligne 267) et de `deploy.yml` (lignes 447
  et 571) changent : diff signalé à l'utilisateur (P10, P14).
- Le compte `tickets-functions` peut lire les journaux du projet (`roles/logging.viewer`) :
  une faille dans l'une des fonctions lit aussi les journaux de requêtes et d'audit
  d'administration. `queryLogs` n'en rend que la sortie des fonctions.
- `functions/src/logging.ts` est inchangé. Ses champs deviennent un format lu par un écran :
  un champ renommé (`ticketId`) casse le filtre sans erreur. Un test de `functions/test/`
  vérifie que le filtre lit les noms de champs que `logging.ts` écrit.
- Documents : `exigences-techniques.md` (table des Cloud Functions, « Réglages faits une
  fois », section « Journaux » sur le modèle du §7.1 de Kass'Dalle : deux journaux, deux
  publics), `exigences-fonctionnelles.md` (Admin › Rapports d'erreur, Admin › Journaux),
  `CLAUDE.md` (« Le projet », P25), ADR-008 (note de renvoi vers cet ADR), `CHANGELOG.md`.

## Sources

- Code de Kass'Dalle et de Kass'Beer lu le 2026-11-14 (fichiers cités dans « Contexte »).
- Quota de `entries.list`, 60 requêtes par minute et par projet, non augmentable : page
  « Quotas and limits » de Cloud Logging, https://cloud.google.com/logging/quotas, résultat
  de recherche consulté le 2026-11-14 (la page n'a pas pu être ouverte depuis la session).
- Lecture et requêtes non facturées, rétention de 30 jours sans coût dans `_Default` : page
  « Google Cloud Observability pricing », https://cloud.google.com/stackdriver/pricing,
  résultat de recherche consulté le 2026-11-14, à vérifier sur la page.
- Nom des journaux `run.googleapis.com/stdout` et `stderr` des fonctions de 2e génération :
  à vérifier dans la documentation de Cloud Logging et sur le premier journal lu.
