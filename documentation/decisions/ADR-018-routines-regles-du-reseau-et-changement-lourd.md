# ADR-018 — Routines des tickets : arrêt du développement distinct de l'analyse, `CLAUDE.md` et `scripts/` modifiables avec fusion à la main, changement lourd depuis l'écran

- **Statut** : proposé
- **Date** : 2026-11-22
- **Remplace** : —. Modifie ADR-008 sur quatre points : « Prompts » (points 3, 4 et 5 du
  prompt de développement, point 5 du prompt d'analyse, partie « Livraison » L3 et L10),
  « Analyses et « Répondre » » (deux natures d'entrée de plus dans `admin/analysis`),
  « Livraison » (état « Règles du réseau modifiées » dans `admin/delivery`, motif de refus à
  part), et la liste des fichiers interdits à la session de développement (décision 15 du
  lot T5). ADR-008 reçoit « Modifié par : ADR-018 ». ADR-002 et ADR-006 restent inchangés.

## Contexte

Demande de l'utilisateur, le 2026-11-22 : « Il faut pouvoir faire du lourd depuis l'écran ;
si besoin de l'architecte on l'appelle ; si besoin de modifier CLAUDE.md, avoir un état
particulier qui attire l'attention dessus et demande une autre forme de validation avant de
déployer. »

Trois tickets validés dans Admin › Tickets sont arrêtés avant tout commit (commentaires de
l'Issue lus le 2026-11-22 par `gh api`) :

- #110 (retirer la mention « non relu ») : la correction change P55 de `CLAUDE.md`, interdit
  au point 5 du prompt de développement. Arrêt publié le 2026-11-21 à 21 h 44 (UTC).
- #114 (Nouveautés plus courtes) : la proposition change `scripts/changelog-recent.mjs`, son
  test et la section « Version » de `CLAUDE.md`. Arrêt le 2026-11-21 à 22 h 25.
- #104 (file d'attente des livraisons) : change `CLAUDE.md` (P25, P36, P39, P43, P44, P46) et
  c'est un changement lourd ; le point 4 du prompt arrête la routine. Arrêt à 17 h 05, puis un
  second lancement arrêté à 21 h 43 sur « revalidation nécessaire ».

Le second arrêt de #104 vient d'un défaut du prompt. La routine de développement publie ses
arrêts sous « ## Analyse — compléments » (points 3, 4 et 6 du prompt,
`exigences-techniques.md`, « Routines des tickets »). Le point 3 prend comme spécification le
dernier commentaire du compte 16348852 qui commence par « ## Analyse », compléments compris,
et exige un `validé` postérieur. Chaque arrêt devient donc la spécification et rend la
validation antérieure. Sur #104 : `validé` à 16 h 57, arrêt à 17 h 05, relance refusée.

Ce qui existe :

- `functions/src/tickets/analysisModel.ts` relève les commentaires de 16348852 qui commencent
  par `## Analyse` (`analysis`) ou `## Précisions` (`reply`, `unverified_reply`) ; un arrêt
  y entre comme `analysis` et s'affiche parmi les analyses (`section_analyses.dart`).
- `functions/src/tickets/delivery.ts` porte `SENSITIVE_DELIVERY_PATTERNS` (34 motifs, dont
  `scripts/**` et `**/CLAUDE.md`), comparé au bloc L3 du prompt par
  `functions/test/prompts.test.ts`. `deliveryState` calcule `ready` sur la CI seule ; la
  sensibilité des fichiers n'est contrôlée qu'à l'appel de `launchTicketDelivery`
  (`delivery_sensitive_files`).
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
| A. Volet 1 seul : arrêt sous un titre à part | 150 à 300 lignes ; plus aucune revalidation fantôme | #110, #114 et #104 restent hors de la routine | 0 € / 0 € |
| B. Volets 1 et 2 : `CLAUDE.md` et une partie de `scripts/` permis à la routine, PR « Règles du réseau modifiées » fusionnée à la main (retenue, lots R1 et R2) | débloque #110 et #114 ; la seule validation nouvelle est la lecture du diff sur GitHub et la fusion par l'admin | une PR de règles ne part pas par « Livrer » | 0 € / 0 € |
| B′. Comme B, avec un accord dans l'application puis livraison par la routine | tout se fait depuis l'écran | commentaire d'accord publié par le serveur, argument de plus sur `launchTicketDelivery`, liste L3 coupée en deux ; une PR qui change `scripts/` livrée par la routine exécute ce script à côté du keystore | 0 € / 0 € |
| C. B plus volet 3 : avis de l'architecte publié par la routine d'analyse, ADR écrit par la routine de développement (retenue, lot R3) | débloque #104 et les suivants depuis l'écran | une question par tour d'analyse : N questions coûtent N + 1 lancements ; un ADR long dépasse 20 000 caractères du relevé | 0 € / 0 €, lancements sur l'abonnement Claude |

## Décision

Option B puis C, en trois lots. L'arrêt d'une session de développement prend un titre qui
n'est jamais une spécification. `CLAUDE.md` à la racine et `scripts/` hors des trois scripts
de contrôle deviennent modifiables par la routine ; la PR qui les touche est marquée « Règles
du réseau modifiées » par le serveur et se fusionne à la main. Le changement lourd passe par
l'agent `architecte` dans la routine d'analyse ; « Valider » vaut acceptation de l'ADR publié.

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
- Un arrêt relevé, postérieur au lancement, ramène à l'heure du relevé le `retry_after` de
  l'entrée `developpement` en cours et la marque `ended_by: "stopped"`, comme un blocage de
  livraison (`blockedDeliveryEntries`). L'admin peut relancer sans attendre 3 h.
- Le serveur, le webhook et `syncTickets` ne tirent aucun statut de ce commentaire (P32).

### 2. Règles du réseau modifiables, fusion à la main (lot R2)

Trois catégories de fichiers, écrites une seule fois dans `delivery.ts` :

| Catégorie | Fichiers | Session de développement | « Livrer » |
|---|---|---|---|
| Interdit | liste actuelle du point 5, moins `CLAUDE.md` à la racine et `scripts/**`, plus `scripts/check-version.mjs`, `scripts/check-version.test.mjs`, `scripts/check-agents.mjs`, `scripts/check-agents.test.mjs`, `scripts/garder-apk-en-ligne.sh` ; `**/CLAUDE.md` hors racine, `**/CLAUDE.local.md`, `**/.mcp.json`, `**/.claude/**`, `.github/**` restent interdits | refuse | refuse |
| Règles du réseau (`NETWORK_RULES_PATTERNS`) | `CLAUDE.md` (racine seule), `scripts/**` hors des cinq fichiers ci-dessus, `documentation/prompts-routines.md` (voir plus bas) | permis | refuse, `delivery_network_rules` |
| Sensible pour la livraison seule | `pubspec.lock`, `auth.ts`, `config.ts`, `delivery.ts`, `member_access.json` (inchangé) | permis | refuse, `delivery_sensitive_files` |

Raisons de garder les cinq scripts interdits : `check-version.mjs` et `check-agents.mjs` sont
les contrôles que la CI applique à la PR elle-même ; une PR qui les change passe sa propre
CI. `check-agents.mjs` tourne aussi au démarrage d'une session sur le poste de l'admin.
`garder-apk-en-ligne.sh` tourne dans le job `deploy`.

État dérivé par le serveur seul. `readDelivery` lit la liste des fichiers de la PR éligible
(10 pages de 100 au plus, comme `launchTicketDelivery`) à chaque relecture d'un ticket
`in_progress`. `admin/delivery` reçoit :

- `network_rules_files` : chemins qui relèvent de `NETWORK_RULES_PATTERNS`, 20 au plus ;
- `network_rules_controls` : numéros `Pn` des lignes ajoutées ou retirées du tableau
  « Contrôles propres au projet », lus dans le `patch` de `CLAUDE.md` (lignes qui commencent
  par `+| P` ou `-| P`), 30 au plus ; liste vide si le patch manque ou dépasse la taille rendue
  par GitHub, avec `network_rules_controls_complete: false` ;
- `sensitive_files` : premier chemin sensible pour la livraison, ou `null` ;
- `files_complete` : faux si la liste dépasse 1 000 fichiers.

`ready` reste vrai sur une CI verte. Le client lit ces champs. Il ne recopie ni les motifs ni
la lecture du patch. Le ticket montre l'étiquette « Règles du réseau modifiées » dans la liste
et en tête de la section « Livraison », avec les fichiers, les contrôles, « Ouvrir la PR #M »
et le texte « Lisez le diff sur GitHub, puis fusionnez-la vous-même. ». « Livrer » est masqué
quand `network_rules_files` ou `sensitive_files` est posé ; `launchTicketDelivery` refuse
toujours de son côté.

Consignes de session : le prompt de développement et la partie « Reprise » disent que les
règles de session viennent du `CLAUDE.md` de `origin/main` (`git show origin/main:CLAUDE.md`).
Le `CLAUDE.md` de la branche est un contenu à livrer. Les interdits du prompt priment sur
tout `CLAUDE.md`. Une modification de `CLAUDE.md` passe par `relecteur-regles` et `securite`,
et le corps de la PR liste les sections et les contrôles changés.

Les deux prompts des routines quittent `exigences-techniques.md` pour
`documentation/prompts-routines.md`. Ce fichier entre dans `NETWORK_RULES_PATTERNS` : un diff
des prompts se voit à l'état de la PR, et la PR rappelle de recoller le texte sur claude.ai
(P40). `prompts.test.ts` lit ce fichier.

### 3. Changement lourd depuis l'écran (lot R3)

Routine d'analyse :

- Si le ticket entre dans la liste « Changement lourd » de `CLAUDE.md`, la session suit le
  skill `changement-lourd` et lance l'agent `architecte`. L'architecte écrit son projet d'ADR
  dans `documentation/decisions/` de la copie de travail de la session, au statut « proposé ».
  Rien n'est commité ni poussé.
- La session publie d'abord un commentaire « ## Avis d'architecture » : avis, options, coût,
  texte complet du projet d'ADR, évolutions du réseau proposées. 60 000 caractères au plus
  (GitHub accepte 65 536). Puis son « ## Analyse », qui renvoie à l'avis.
- Questions ouvertes : l'analyse pose la première seulement, avec son contexte, ses options,
  leur effet et leur coût, et la recommandation, sous une ligne fixe « Question à trancher :
  1 sur K ». L'admin répond par « Répondre » ; le ticket revient à `received` ; un nouveau
  « Lancer l'analyse » publie l'avis mis à jour et la question suivante. Sans question
  restante, l'analyse porte la ligne fixe « Questions ouvertes : aucune ».
- `analysisModel.ts` relève « ## Avis d'architecture » sous la nature `architecture`, la plus
  récente seule, coupée à 60 000 caractères au lieu de 20 000. Le serveur écrit dans
  `admin/analysis` le booléen `architecture_in_last_analysis` : un avis existe entre
  l'analyse précédente et la dernière.

Constat de la décision : aucun texte non fiable. L'acceptation est l'appui sur « Valider »
dans l'application, constaté par deux faits que seuls le serveur et l'admin produisent :
`validated_by_app_at` (écrit par `validateTicket`) et l'événement `labeled` `validé` d'acteur
16348852, postérieur à l'avis et à l'analyse. Quand `architecture_in_last_analysis` est vrai,
la boîte de « Valider » ajoute : « Valider accepte aussi le projet d'ADR publié et les choix
de l'analyse. Le développement écrira l'ADR au statut accepté. » Les réponses de l'admin sont
ses « ## Précisions de l'administrateur », citées dans l'analyse (règle actuelle du prompt
d'analyse, point 5).

Routine de développement :

- Le point 4 n'arrête plus sur un changement lourd si l'analyse validée suit un
  « ## Avis d'architecture » et porte « Questions ouvertes : aucune ». Sinon, arrêt sous
  « ## Développement — arrêt » (« changement lourd sans avis d'architecture validé »).
- La session écrit l'ADR depuis le texte de l'avis, au statut « accepté (date du `validé`),
  décision de l'utilisateur par Valider, ticket #N », applique les évolutions du réseau que
  l'avis propose et que l'analyse retient, puis suit la « Chaîne de travail » à l'étape 1.
  L'architecte n'écrit toujours que dans `documentation/decisions/` ; la session principale
  (ici la routine) change le statut, comme le skill `changement-lourd` le prévoit.
- Un ADR change presque toujours « Le projet » de `CLAUDE.md` : la PR prend l'état « Règles
  du réseau modifiées » et se fusionne à la main. Un numéro d'ADR déjà pris sur `main` au
  moment de la fusion se corrige par l'admin ; la livraison ne renumérote rien.
- Un changement lourd refusé (« Refuser ») n'écrit aucun fichier dans `decisions/` : l'avis
  publié sur l'Issue reste la trace. C'est un écart au skill `changement-lourd` (« l'ADR
  proposé passe au statut rejeté »).

### Lots

| Lot | Contenu | Après | Serveur et tests | Client et tests | Documents |
|---|---|---|---|---|---|
| R1 | titre d'arrêt, point 3 du prompt, nature `development_stop`, `ended_by: "stopped"` | — | 120 à 200 lignes (`analysisModel.ts`, `launchModel.ts` ou `sync.ts`, `analysis.test.ts`, `launch.test.ts`, `prompts.test.ts`) | 40 à 80 (`ticket_analysis.dart`, `section_analyses.dart`, test) | prompt recollé ; P32, P33, P40 |
| R2 | trois catégories, champs de `admin/delivery`, `delivery_network_rules`, prompts déplacés, consignes de session | R1 | 300 à 450 (`delivery.ts`, `launch.ts`, `delivery.test.ts`, `prompts.test.ts`) | 200 à 300 (`ticket_delivery.dart`, section « Livraison », liste, tests) | prompt recollé ; P10, P40, P43, P45, « Logique dupliquée », « Tickets » |
| R3 | architecte dans l'analyse, nature `architecture`, `architecture_in_last_analysis`, texte de « Valider », points 4 et 5 du prompt de développement | R2 | 120 à 200 (`analysisModel.ts`, `analyses.ts`, tests) | 60 à 120 (boîte de Valider, carte « Avis d'architecture », tests) | deux prompts recollés ; skill `changement-lourd` ; « Chaîne de travail », « Tickets » ; P64 |

Estimations non mesurées. Le lot R2 est lui-même une PR « Règles du réseau » : il se fait
dans une session locale, pas par la routine.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : relevé des commentaires, lecture des fichiers et du
   patch, état de livraison dans `functions/` (webhook, `syncTickets`, `launchTicketDelivery`).
   Affichage dans `app/lib/features/tickets/`. Avis, ADR et code dans les sessions Claude Code
   chez Anthropic. Fusion d'une PR de règles par l'admin sur GitHub.
2. **Ce qui existera en double** : `NETWORK_RULES_PATTERNS` et la liste des interdits du point
   5 vivent dans `delivery.ts` et dans le prompt, comparés par `prompts.test.ts` (ligne de
   plus au tableau « Logique dupliquée »). Le client ne recopie aucune liste.
3. **Ce qui pèse au démarrage** : rien. `fetch` seul, aucune dépendance.
4. **Compilation de chaque cible** : aucun paquet ajouté. Commandes inchangées.
5. **Qui voit quoi** : avis et ADR proposés sont publics sur l'Issue, comme les analyses
   (ADR-002) : ni nom, ni e-mail, ni prix. `network_rules_*` et la nature `architecture` sont
   lus par l'admin seul (`admin/{doc}`, règles actuelles). Aucun titre ni corps de PR écrit
   dans Firestore ; du patch de `CLAUDE.md`, seuls les numéros `Pn` sont gardés.
6. **Ce qui coûte à l'usage, plafond** : poste `ticket_routine_launch` inchangé. Un
   changement lourd à K questions coûte K + 1 lancements d'analyse et un de développement,
   dans le plafond de 10 par jour (50 pour le fondateur). Lectures GitHub en plus : la liste
   des fichiers d'une PR éligible par relecture, une dizaine d'appels par heure au plus.
7. **Exposition** : aucun point d'accès nouveau, aucun secret nouveau, aucun rôle nouveau.
   Surface nouvelle : un texte d'Issue non fiable peut pousser l'analyse à proposer
   d'affaiblir une règle. Protections : la validation humaine de l'analyse, l'état « Règles du
   réseau modifiées » avec les `Pn` touchés, la fusion à la main, et les interdits du prompt,
   qui ne vivent que sur claude.ai et ne changent que par un recollage à la main.
8. **Exploitation** : deux prompts recollés à R1, R2 et R3. Une PR de règles demande à l'admin
   de lire un diff sur GitHub et de fusionner. Rien à sauvegarder de plus.
9. **Coût de sortie** : faible. Revenir en arrière remet `CLAUDE.md` et `scripts/**` dans la
   liste interdite et retire deux natures d'entrée.

## Conséquences

Plus simple : #110 et #114 se développent depuis l'écran après R2 ; #104 après R3, en
commençant par « Répondre » (retour à `received`) puis « Lancer l'analyse ». Un arrêt ne
bloque plus la relance.

Plus difficile : l'admin fusionne à la main chaque PR qui touche les règles du réseau, et lit
le diff de `CLAUDE.md` avant. La routine change les règles que suivront les sessions
suivantes. Les prompts des routines restent la borne : leur texte ne change que par un
recollage.

Risque accepté : `scripts/changelog-recent.mjs` modifié par une routine s'exécute dans le job
`build` de `deploy.yml`, à côté du keystore, dès la fusion. La fusion à la main après lecture
du diff est la seule protection.

`CLAUDE.md` change : « Tickets », « Chaîne de travail » (étape 0 depuis une routine),
« Logique dupliquée », P10, P32, P33, P40, P43, P45, et deux contrôles nouveaux (P63, P64).
`exigences-techniques.md` : `admin/analysis`, `admin/delivery`, renvoi vers
`documentation/prompts-routines.md`. `guide-reseau.md` : routines et changement lourd.

## Sources

- Commentaires de #104, #110 et #114 : `gh api repos/ChinaFred/KassBeer/issues/<n>/comments`,
  lus le 2026-11-22.
- Taille maximale d'un commentaire GitHub, 65 536 caractères : à vérifier.
- Taille du `patch` rendu par `GET /pulls/{n}/files` (tronqué au-delà d'une limite) : à
  vérifier.
- Kass'Beer : `functions/src/tickets/analysisModel.ts`, `delivery.ts`, `decisionModel.ts`,
  `launchModel.ts`, `app/lib/features/tickets/domain/ticket_analysis.dart`,
  `.github/workflows/deploy.yml` (lignes 330 à 400, 616), `.github/workflows/ci.yml` (lignes
  78 à 94), `.claude/hooks/session-start.sh`, `exigences-techniques.md` lignes 5130 à 5500.
