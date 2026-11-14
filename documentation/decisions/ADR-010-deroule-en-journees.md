# ADR-010 — Déroulé d'un brassin en journées : modèles de processus partagés, journées suivies hors ligne

- **Statut** : accepté (réponses de l'utilisateur du 2026-11-11, validation du 2026-11-13)
- **Date** : 2026-11-11
- **Remplace** : — . Étend ADR-001 sur deux règles de `CLAUDE.md` : « Le jour de brassage
  marche sans réseau » couvre chaque journée du déroulé, et « Un brassin fige sa recette »
  couvre son déroulé à partir du départ. ADR-003 (alerte de minuteur) s'applique sans
  changement à chaque journée.

## Contexte

Le brasseur veut suivre un brassin sur plusieurs journées : le brassage, puis par exemple le
houblonnage à cru et l'embouteillage. Chaque journée a ses étapes de préparation et de
nettoyage, qui ne dépendent pas de la recette. Aujourd'hui, ces étapes n'existent nulle part :
la chronologie d'un brassin est la seule `brew_steps` de la recette, copiée dans
`recipe_snapshot` (`app/lib/features/brew_day/domain/plan_du_jour.dart`, ligne 105).

Réponses de l'utilisateur du 2026-11-11 :

1. de 1 à 5 journées par modèle, nommées et ordonnées par le brasseur, chacune avec son écart
   en jours ;
2. un seul bloc tiré de la recette en journée de brassage : sa « Chronologie du jour »
   (`brew_steps`), ou le préremplissage `defaultBrewSteps` si elle est vide. Les autres
   journées ont aussi un bloc tiré de la recette : houblons à cru (une étape « Ajouter
   {houblon} {masse} g », 0 min, par houblon) et ajouts à l'embouteillage ;
3. le jour d'ajout à cru de la recette (BeerJSON `timing.time`, `HopLine.dayMin`) prime sur
   l'écart du modèle ; sinon l'écart du modèle ; la date se déplace sur le brassin avant son
   départ ; point de départ : `brewed_at`, sinon `planned_for` ;
4. partage par copie depuis la liste du groupe (« Copier dans mes processus ») ; aucun modèle
   d'un autre membre n'est présélectionné ;
5. les mesures des journées 2 et suivantes comptent dans le relevé de fermentation (densité
   finale), jamais comme densité initiale, et restent visibles sous leur étape ;
6. modèles et journées suivies livrés ensemble, visés avant le brassin du 22 novembre 2026 ;
   prévu/réel et mise à jour du modèle à la livraison suivante ;
7. modèle de départ accepté tel quel (durées typiques, voir « Modèle d'exemple »).

Choix gardés par défaut, non contredits : aucun nouveau statut ; ligne dérivée « En
fermentation · Houblonnage à cru prévu le … » ; déroulé modifiable seulement avant le départ ;
anciens brassins en une journée.

Ce qui existe (worktree `processus-journees`, `origin/main` v0.1.25, lu le 2026-11-11) :

- `firestore.rules` : la création d'un brassin (`isBrewCreateShape`) passe avec une marge
  d'environ 40 expressions sur 1 000 (mesure de la v0.1.17, commentaire au-dessus de
  `match /brews/{brewId}`). Un changement de statut laisse 93 `pad()` (≈ 930 expressions), les
  11 ajustements environ 470. Les éléments de `brew_steps` ne sont pas inspectés par les règles.
- `brews/{id}/events/` : `step_key` de 1 à 100 caractères, `phase` nulle ou `fermentation`
  (mesure et note seulement). Aucune règle ne lie `step_key` à une étape connue.
- `brewing/lib/src/schedule.dart` : `recomputeSchedule` lève si `records` nomme une étape
  inconnue ; `stepRecordsFromEvents` rend une étape inconnue comme anomalie.
- `brewing/lib/src/brew_steps.dart` : `defaultBrewSteps` exclut les houblons à cru et au
  conditionnement ; il ne crée pas de clé.
- `brewing/lib/src/fermentation.dart` : `fermentationDayNumber` compte les J+N en jours
  calendaires locaux depuis `brewed_at`.
- `app/lib/features/brews/domain/mesures_retenues.dart` : la densité initiale automatique ne
  prend que les densités sans `phase: 'fermentation'`.
- `app/lib/features/brew_day/presentation/brew_day_screen.dart`, lignes 97 à 112 : l'écran du
  jour ne s'ouvre qu'au statut `brewing`.
- `app/lib/features/brews/domain/brew.dart`, `brassinAReprendre` : reprise au lancement pour
  un brassin `brewing` commencé depuis moins de 24 h.
- `app/lib/features/costs/data/figeage_embouteillage.dart` : `enregistrerEmbouteillage` fige
  le coût au premier embouteillage, sans transaction ni lecture du serveur.
- Six fichiers lisent `recipe.brewSteps` ou `recipe.brewStepsProblem` d'un brassin :
  `plan_du_jour.dart` (ligne 105), `brew_day_screen.dart` (410, 819),
  `prepare_brew_screen.dart` (147, 173, 183), `prevu_et_mesure.dart` (214),
  `brew_detail_screen.dart` (771, 888), `brews_repository.dart` (289).

Contraintes concernées : hors ligne du jour de brassage (CLAUDE.md, règle absolue), calculs
dans `brewing/` (P3), prix privés (P5), règles = seul contrôle d'accès (P4), « Pas de valeur de
repli figée », « Données partagées et état propre à un utilisateur ».

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Ne rien changer | aucun travail | les étapes de préparation et de nettoyage se recopient dans chaque recette ; aucune journée après le brassage | 0 € / 0 € |
| A. Étapes du processus ajoutées à la chronologie de chaque recette | aucun nouveau modèle de données | une seule journée ; mêmes étapes copiées dans chaque recette ; une recette partagée porte le matériel d'un brasseur | 0 € / 0 € |
| B. Modèles partagés, déroulé résolu écrit à la création du brassin | une seule écriture | `isBrewCreateShape` a environ 40 expressions de marge ; contrôler `process` en plus coûte de 15 à 25 expressions (estimation) et ne laisse rien pour la suite | 0 € / 0 € |
| B'. Modèles partagés, déroulé résolu écrit par une modification juste après la création, tant que `brewed_at` est nul (retenue) | budget de création intact ; contrôle de `process` dans `isBrewUpdate`, qui a plus de 900 expressions de marge sur un changement de statut ; le déroulé se change avant le départ par la même écriture | deux écritures à la création ; un brassin créé par un APK antérieur n'a pas de déroulé | 0 € / 0 € |
| C. Brassin qui garde le seul `template_id` ; déroulé résolu à l'affichage | aucune copie | un modèle changé ou supprimé change un brassin en cours ; hors ligne, le modèle doit être en cache ; contraire à « Un brassin fige sa recette » | 0 € / 0 € |
| D. Sous-collection `brews/{id}/sessions/{k}` | un document par journée | jusqu'à 5 documents de plus à créer, valider et lire avant chaque journée ; une écriture de masse à la création ; un `get()` de plus par règle | 0 € / 0 € |

## Décision

Option B'. Un modèle de processus vit dans `process_templates/{id}`, lisible par le groupe et
écrit par son auteur. À la création d'un brassin, l'application résout le modèle avec la recette
figée et écrit le déroulé dans `brews/{id}.process`, par une modification qui n'est permise que
tant que `brewed_at` est nul. Raison principale : le contrôle de `process` à la création ferait
dépasser le budget de 1 000 expressions, et le déroulé doit être figé pour marcher hors ligne.

### Modèle de processus `process_templates/{templateId}`

| Champ | Type |
|---|---|
| `format_version` | int, obligatoire, `1` |
| `owner_uid` | string, obligatoire, immuable |
| `owner_name` | string, facultatif, contrôlé comme dans `recipes/` (`ownerNameOk`) |
| `name` | string, obligatoire, 1 à 120 caractères |
| `notes` | string \| null, 10 000 caractères au plus |
| `sessions` | liste, obligatoire, de 1 à 5 journées |
| `created_at`, `updated_at` | timestamp, `serverTimestamp()` |

Journée (élément de `sessions`, non inspecté par les règles, lu et validé par l'application) :

| Champ | Type |
|---|---|
| `key` | string, 1 à 100 caractères, unique dans le modèle |
| `name` | string, 1 à 120 caractères |
| `offset_days` | int, 0 à 365 : écart en jours depuis le début du brassage |
| `requires_recipe_block` | bool, facultatif : la journée n'est reprise dans un brassin que si son bloc tiré de la recette n'est pas vide |
| `steps` | liste, 60 éléments au plus |

Élément de `steps` :

| Champ | Type |
|---|---|
| `key` | string, 1 à 100 caractères, unique dans le modèle |
| `kind` | `step`, `recipe_steps`, `dry_hops` ou `packaging_additions` |
| `name`, `duration_min`, `temp_c` | pour `step` seulement, bornes de `brew_steps` (`chronologie.dart` : nom 120, durée 0 à 600 min, température 0 à 100 °C) ; absents sur un bloc |

Contraintes que l'application vérifie avant d'écrire (les règles ne lisent pas les éléments) :

- la première journée est la journée de brassage : `offset_days` = 0 et un bloc
  `recipe_steps`, un seul dans tout le modèle ;
- `dry_hops` et `packaging_additions` : un de chaque au plus, jamais dans la première journée,
  jamais dans la même journée (une journée de houblonnage se répète une fois par jour d'ajout) ;
- `requires_recipe_block` n'est permis que sur une journée qui porte `dry_hops` ou
  `packaging_additions` ;
- `offset_days` ne décroît pas d'une journée à la suivante ;
- aucun champ hors de ces listes : aucun prix, aucun stock, aucun coût (P5).

### Blocs tirés de la recette

La résolution lit la copie figée `recipe_snapshot` du brassin, jamais la recette vivante.

| Bloc | Contenu dans le brassin | Bloc vide |
|---|---|---|
| `recipe_steps` | `brew_steps` de la copie, clés gardées ; si la liste est vide, le préremplissage `defaultBrewSteps` (paliers, ébullition, whirlpool), avec ses avertissements (étape sans durée non ajoutée, houblon placé en tête), clés créées par l'application | la journée de brassage garde ses étapes du modèle |
| `dry_hops` | une étape « Ajouter {houblon} {quantité} », 0 min, par houblon `add_to_fermentation`, dans l'ordre de la recette | le bloc disparaît ; la journée disparaît si `requires_recipe_block` est vrai |
| `packaging_additions` | une étape « Ajouter {nom} {quantité} », 0 min, par houblon `add_to_package` puis par ajout `add_to_package` (`OtherUse.bottling`) | idem |

Le rinçage et la montée à ébullition restent dans la chronologie de la recette. Les ajouts
`add_to_fermentation` autres que les houblons (fruit, épice) n'entrent dans aucun bloc dans cette
livraison ; l'utilisateur dira s'ils rejoignent le bloc `dry_hops`. Une recette qui a des houblons à cru, résolue avec un modèle sans
bloc `dry_hops`, ne crée aucune journée ; l'écran de choix l'annonce (« La recette a 2 houblons à
cru. Ce processus n'a pas de journée pour eux. »).

### Écarts et dates

Point de départ : la date locale de `brewed_at`, sinon de `planned_for`. Sans l'un ni l'autre,
l'écran affiche « J+4 » sans date. La date d'une journée est le jour calendaire local de départ
plus `offset_days` : la même règle que `fermentationDayNumber`, dont elle est l'inverse.

Houblons à cru :

1. un houblon dont la recette donne le jour d'ajout (`dayMin`, en minutes depuis le début de la
   fermentation) tombe à J+`round(dayMin / 1 440)` ; un houblon sans jour tombe à l'écart du
   modèle ;
2. une journée de houblonnage par jour distinct, chacune copie les étapes de la journée du
   modèle (désinfection, mesure, nettoyage) avec de nouvelles clés, et nommée « {nom} 1 »,
   « {nom} 2 » quand il y en a plusieurs ;
3. borne de 5 journées : si le nombre de journées dépasse 5, les jours de houblonnage les plus
   tardifs se regroupent dans la journée du premier jour regroupé, et l'écran de choix l'annonce
   (« Houblons à cru du J+8 regroupés au J+6 : 5 journées au plus. »). Le brasseur déplace la
   date s'il le veut.

Toutes les journées sont ensuite triées par écart, à égalité dans l'ordre du modèle. La
journée de brassage reste la première.

Avant le départ, le brasseur change le processus ou la date d'une journée sur la fiche du
brassin. Chaque changement réécrit `process` en entier. Après le départ, le déroulé ne change
plus (règles) ; une journée peut toutefois commencer un autre jour que sa date prévue.

### Déroulé figé du brassin `brews/{brewId}.process`

| Champ | Type |
|---|---|
| `format_version` | int, `1` |
| `template_id` | string \| null (128) : modèle d'origine, peut avoir été supprimé depuis |
| `template_name` | string \| null (120) : nom du modèle au moment de la résolution |
| `sessions` | liste de 1 à 5 journées résolues |

Journée résolue (non inspectée par les règles) : `key`, `name`, `offset_days`, `offset_source`
(`template`, `recipe` ou `brewer`), `role` (`brew` pour la première, `packaging` pour celle qui
portait `packaging_additions`, `other` sinon), `template_session_key`, `steps` (120 éléments au
plus : 59 étapes du modèle et 60 de la recette). Étape résolue : `key`, `name`, `duration_min`,
`temp_c` facultative, `origin` (`template`, `recipe_steps`, `dry_hops`, `packaging_additions`),
`template_step_key` pour une étape tirée du modèle.

Règles de ce champ :

- chaque clé d'étape est unique dans tout le brassin, toutes journées comprises ; les étapes du
  modèle et des blocs `dry_hops` et `packaging_additions` reçoivent une clé neuve
  (`doc().id`) à chaque résolution ; les étapes de la recette gardent leur clé de
  `recipe_snapshot.brew_steps` ;
- `template_step_key` et `template_session_key` ne servent à rien dans cette livraison. Ils
  sont écrits dès maintenant pour que le prévu/réel de la livraison suivante relie les heures
  du brassin du 22 novembre aux étapes du modèle. Sans eux, ce brassin ne pourrait pas mettre à
  jour son modèle ;
- la copie des étapes de la recette dans la première journée double `recipe_snapshot.brew_steps`
  dans le même document. Les deux copies sont figées au départ ; une seule est lue (le déroulé
  quand il existe). Taille du document : environ 20 Ko de plus au pire, loin de la limite de
  1 Mio.

### Lecture tolérante

Un brassin sans `process` (anciens brassins, brassin créé par un APK antérieur, résolution pas
encore écrite) se lit comme une journée de brassage unique, tirée de
`recipe_snapshot.brew_steps`. Aucune migration. Un `process` illisible (format inconnu, clé en
double, borne dépassée) rend le déroulé illisible : la fiche et l'écran du jour l'affichent et
le rapportent (`reportError`), sans se replier sur la chronologie de la recette. Un repli
silencieux ferait suivre au brasseur un déroulé qui n'est pas le sien.

Toutes les lectures du déroulé passent par un seul accès (proposé : `Brew.deroule`). Les six
fichiers listés au contexte lisent ensuite les étapes par lui ; aucun ne lit plus
`recipe.brewSteps` d'un brassin. Sans ce changement, `prevu_et_mesure.dart` affiche « Sans
étape » pour une mesure prise sur une étape du modèle.

### Choix par défaut `users/{uid}/preferences/processes`

Document privé : `default_template_id` (string \| null, 128), `updated_at`. Écrit par son
propriétaire seul. Le formulaire « Nouveau brassin » propose les seuls modèles du lecteur et
présélectionne celui-ci. Sans préférence, ou si elle désigne un modèle supprimé ou d'un autre
membre, la présélection est « Chronologie de la recette seule » : le brassin a une journée,
comme aujourd'hui. Le choix est un état propre au lecteur : il ne va pas sur le modèle, lu par
le groupe.

### Partage

« Mes processus » liste les modèles du lecteur, puis ceux du groupe avec le nom de leur auteur.
« Copier dans mes processus » crée un nouveau document au nom du lecteur, avec de nouvelles
clés de journées et d'étapes. Un modèle ne se modifie que par son auteur. Supprimer un modèle ne
change aucun brassin : chacun garde sa copie résolue.

### Écran du jour par journée

Un seul écran, paramétré par la journée (route proposée : `/brews/:id/day/:sessionKey`, la
route actuelle ouvrant la journée de brassage). Chaque journée a son « Préparer la journée »,
qui attend le serveur 15 s au plus comme aujourd'hui, sans écrire.

| Journée | S'ouvre au statut | Début | Fin |
|---|---|---|---|
| Brassage (`brew`) | `brewing` (« Préparer le brassage » au statut `planned`) | inchangé : `planned` → `brewing` et premier début d'étape dans un `WriteBatch` | « Terminer le brassage » → `fermenting` |
| Autre (`other`) | `fermenting` ou `conditioning` | premier début d'étape, écriture simple, aucun statut | « Terminer la journée » : `step_ended` pour l'étape en cours et `step_skipped` pour chaque étape à venir, dans un `WriteBatch` ; aucun nouveau type d'événement |
| Embouteillage (`packaging`) | `fermenting` | idem | « Embouteiller » : le formulaire d'embouteillage, puis `enregistrerEmbouteillage` → `conditioning`. Prix, frais et coût figé du propriétaire lus à « Préparer la journée » et gardés ouverts, capturés à l'envoi |

Une journée est terminée quand aucune de ses étapes n'est en cours ni à venir, ou pour
l'embouteillage quand `bottled_at` est posé. Le statut ne change qu'à la fin du brassage et à
l'embouteillage. La fiche garde son bouton « Embouteiller » pour un brassin sans journée
d'embouteillage.

Le calcul se fait journée par journée. `stepRecordsFromEvents` reçoit une fois les étapes de
toutes les journées : une étape inconnue reste une anomalie du brassin. `recomputeSchedule`
reçoit ensuite les étapes d'une seule journée et leurs seuls enregistrements. Sans ce
découpage, le premier début d'étape du houblonnage marque « Non faites » les étapes non
commencées du brassage, et `recomputeSchedule` lève pour une étape inconnue. Départ prévu d'une
journée : son premier début enregistré, sinon `brewed_at` pour le brassage et l'heure de
l'appareil pour les autres.

La reprise au lancement (`brassinAReprendre`) reste limitée au brassage : elle lit la liste des
brassins, sans leurs événements. Les autres journées s'ouvrent depuis la liste et la fiche.
Jusqu'à la v0.1.38, la liste dérive sa ligne des dates seules (« En fermentation · Houblonnage à
cru prévu le 26/11 ») et ne lit pas les événements : une journée faite avant sa date reste
annoncée jusqu'à cette date (limite acceptée). Depuis la v0.1.39, elle lit les événements des
brassins du lecteur En fermentation ou En conditionnement dont le `process` a au moins deux
journées, et annonce la même journée que la fiche ; les dates seules restent la règle pour les
brassins des autres membres et tant que ces événements ne sont pas lus (décision de
l'utilisateur du 2026-11-13).

### Mesures des journées 2 et suivantes

Elles s'écrivent avec `phase: 'fermentation'` et le `step_key` de leur étape. Les règles le
permettent déjà (`phaseOk`). Effets :

- `MesuresRetenues` ne les prend jamais comme densité initiale automatique ;
- elles entrent dans le relevé de fermentation, la courbe et la densité finale ;
- l'écran de la journée les affiche sous leur étape : `plan_du_jour.dart` doit cesser d'écarter
  toute mesure de fermentation (ligne 122) et garder celles dont l'étape appartient à la
  journée ;
- une mesure « Sans étape » saisie pendant une journée 2 ou suivante est un relevé de
  fermentation ordinaire.

### Calculs dans `brewing/`

Ajouts au paquet, sans Flutter ni Firebase, comme `defaultBrewSteps` :

- résolution du modèle : journées gardées ou retirées, jours de houblonnage, regroupement au-delà
  de 5, tri par écart, avertissements. Elle rend des brouillons sans clé ni libellé (indice de
  l'étape du modèle, de l'étape de la recette ou du houblon) ; l'application crée les clés et
  les libellés, comme pour le préremplissage ;
- jour d'un houblon à cru : `round(dayMin / 1 440)` ;
- date d'une journée depuis le départ et l'écart, inverse de `fermentationDayNumber`.

Fixture `brewing/test/fixtures/process.json`, cas au minimum : modèle d'exemple et recette sans
houblon à cru (journée 2 retirée) ; deux houblons sans jour (un J+4) ; jours 3 et 6 (deux
journées) ; quatre jours distincts avec trois autres journées (regroupement) ; houblons avec et
sans jour ; chronologie de recette vide (préremplissage, étape sans durée retirée) ; ajouts à
l'embouteillage vides (journée gardée, bloc retiré) ; dates autour des changements d'heure du
2026-10-25 et du 2027-03-28.

### Modèle d'exemple

Trois façons de livrer le modèle accepté par l'utilisateur :

| Façon | Pour | Contre |
|---|---|---|
| L'administrateur le saisit dans l'éditeur après la mise en ligne | aucun code ; les amis le copient depuis le groupe | 3 journées et 21 étapes à saisir avant le 22 novembre ; un nouveau membre sans le savoir part de rien |
| Écriture unique par Admin › Import | données, pas code | un schéma d'import et un écran de plus pour un seul document |
| Constante « Modèle d'exemple » dans l'application, proposée quand le lecteur n'a aucun modèle, copiée sur demande sous son nom puis modifiable (retenue) | une action ; marche pour chaque nouveau membre ; sert de cas à la fixture | 21 durées dans le code |

La constante ne contredit pas « Pas de valeur de repli figée ». Cette règle interdit de
remplacer une donnée absente par une constante présentée comme exacte. Ici, rien ne remplace
une donnée absente : un brassin sans processus a une journée, celle de la recette. Le modèle
d'exemple ne s'applique jamais seul. Il ne s'écrit que sur l'action « Partir du modèle
d'exemple », devient alors une donnée du brasseur, et porte la note « Durées typiques, à
ajuster à votre matériel. ». Ses durées ne sont pas des formules de brassage (P3).

Contenu (accepté le 2026-11-11), en minutes :

- **Brassage** (J+0) : Mise en place du matériel 30 ; Désinfection du fermenteur 20 ; Chauffe
  de l'eau d'empâtage 40 ; Mouture du grain 20 ; [Chronologie de la recette] ; Refroidissement
  30 ; Mise en cuve et mesure de densité 15 ; Oxygénation et ensemencement 10 ; Nettoyage du
  matériel 60 ; Rangement 30.
- **Houblonnage à cru** (J+4, `requires_recipe_block`) : Désinfection du matériel 10 ; Mesure
  de densité 5 ; [Houblons à cru] ; Nettoyage 10.
- **Embouteillage** (J+14) : Lavage des bouteilles 60 ; Désinfection des bouteilles et du
  matériel 30 ; Préparation du sucre de resucrage 15 ; Transfert en cuve d'embouteillage 15 ;
  [Ajouts à l'embouteillage] ; Mise en bouteilles et capsulage 60 ; Nettoyage et rangement 30.

### Règles d'accès

| Chemin | Lecture | Création | Modification | Suppression |
|---|---|---|---|---|
| `process_templates/{id}` | membres | membre, `createdByMe`, `ownerNameOk`, forme ci-dessus : clés en liste blanche, `format_version == 1`, `name` 1 à 120, `notes` 10 000, `sessions` liste de 1 à 5 | propriétaire, `updatedByOwner`, même forme | propriétaire |
| `brews/{id}`, champ `process` | inchangée | absent à la création (`brewCreateFields` inchangé) | propriétaire ; `process` changé seulement si `resource.data.brewed_at` est nul et le reste ; nul, ou map de clés `format_version` (== 1), `template_id` (128), `template_name` (120), `sessions` (liste de 1 à 5) | inchangée |
| `users/{uid}/preferences/processes` | propriétaire (joker existant) | propriétaire, clés `default_template_id` (128 au plus, ou nul) et `updated_at == request.time` | idem | propriétaire |

Les événements ne changent pas : aucun nouveau `kind`, aucun nouveau champ.

### Budget des règles

Non mesuré pour cet ADR : l'émulateur n'a pas été lancé. Estimation :

- création d'un brassin : inchangée, `process` n'y entre pas (marge d'environ 40 expressions) ;
- modification qui écrit `process` : 15 à 25 expressions de plus, sur un document sans
  ajustements ni embouteillage (brassin prévu) ;
- toute autre modification : 3 à 5 expressions de plus (`brewFields` et le test
  `changed.hasAny(['process'])`), contre plus de 900 de marge sur un changement de statut et
  environ 470 sur les 11 ajustements ;
- création d'un modèle : 40 à 60 expressions.

« Terminer la journée » et « Les sauter et commencer » écrivent jusqu'à 60 événements dans un
lot. Chaque création d'événement appelle `get()` sur le brassin et `exists()` sur `members/`.
La limite est de 20 appels par lot ; la documentation dit que « certains appels peuvent être
mis en cache », sans dire lesquels. Ce cas existe déjà pour « Les sauter et commencer » et n'a
pas de test.

Condition de la première livraison (lot D1) : mesurer par la méthode des `pad()` de la v0.1.17
(1) l'écriture de `process` sur un brassin prévu qui copie la plus grande recette, (2) un
changement de statut et l'embouteillage sur un brassin rempli qui porte le plus grand `process`,
(3) la création du plus grand modèle ; écrire les chiffres dans le commentaire de
`firestore.rules` et dans `rules-tests/test/recipe_format.test.mjs`. Ajouter un test d'un lot de
60 `step_skipped`. S'il échoue, l'application découpe le lot en lots de 10 écritures au plus,
partis à la suite sans attente, comme le coût après l'embouteillage.

### Lots de cette livraison

Le brassin du 22 novembre a besoin de la journée de brassage le 22 novembre. Sa journée de
houblonnage tombe le 26 novembre (J+4 du modèle d'exemple) et son embouteillage vers le
6 décembre (J+14). Les lots suivent cet ordre.

| Lot | Contenu | Échéance proposée |
|---|---|---|
| D1 — technique | `brewing/` (résolution, jour à cru, dates, fixture `process.json`) ; règles et tests (`process_templates/`, `process`, `preferences/`, cinq profils, brassin commencé refusé) ; mesures du budget ; lecteur `Brew.deroule` avec lecture tolérante ; les six lecteurs passent par lui, sans changement visible | 15 novembre |
| D2 — fonctionnel | « Mes processus » : liste, éditeur, copie, modèle d'exemple, choix par défaut | 18 novembre |
| D3 — fonctionnel | « Nouveau brassin » : choix du processus, écriture de `process` ; fiche : section Déroulé, dates, changement avant le départ ; journée de brassage tirée du déroulé (préparation, écran, mesures) ; ligne de la liste | 20 novembre, puis brassage à blanc |
| D4 — fonctionnel | journées 2 et suivantes : « Préparer la journée », écran paramétré, « Terminer la journée », « Embouteiller » en fin de journée, mesures en `phase: 'fermentation'` | visé avant le 22 novembre, au plus tard le 25 novembre |

Si D4 manque le 25 novembre, le houblonnage du brassin du 22 se fait sans écran de journée : la
mesure de densité se saisit par le relevé de fermentation, et l'embouteillage par la fiche. Le
déroulé écrit par D3 reste valable pour D4 sans migration.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : sur l'appareil. Résolution du modèle, jours et dates
   dans `brewing/` ; clés, libellés, écrans et écritures dans `app/lib/features/processes/` et
   les features `brews/` et `brew_day/`. Contrôle d'accès dans `firestore.rules`. Aucune
   fonction serveur, aucune tâche planifiée.
2. **Ce qui existera en double** : aucune logique entre client et serveur. Dans un même
   document, les étapes de la recette existent dans `recipe_snapshot.brew_steps` et dans
   `process.sessions[0].steps`, toutes deux figées au départ ; une seule est lue. Le modèle
   d'exemple existe dans le code et dans chaque copie faite par un brasseur ; les copies sont
   ensuite indépendantes.
3. **Ce qui pèse au démarrage** : rien. Aucun paquet ajouté. Les modèles se lisent à
   l'ouverture de « Mes processus » et du formulaire « Nouveau brassin », pas au lancement. Un
   brassin pèse jusqu'à environ 20 Ko de plus dans la liste des brassins.
4. **Compilation de chaque cible** : aucune dépendance nouvelle. Les commandes de « Commandes
   utiles » ne changent pas.
5. **Qui voit quoi** : un modèle est lu par le groupe, comme une recette ; ses noms d'étapes sont
   du texte libre visible par tous les membres. Le déroulé d'un brassin est lu par le groupe,
   comme le brassin. La préférence est privée (`users/{uid}/`). Aucun prix, stock ni coût dans
   `process_templates/` ni dans `process` (P5). Rien ne part vers un service tiers.
6. **Ce qui coûte à l'usage** : quelques lectures de modèles par ouverture d'écran, une
   écriture de plus par brassin créé, de 1 à 60 écritures d'événements par journée suivie. Pour
   moins de 10 comptes, la dépense reste ≈ 0 € par mois ; aucun poste de coût variable.
7. **Exposition** : inchangée. Ouvert sur Internet, comptes sur invitation ; nouvelles
   collections derrière `isMember()`.
8. **Exploitation** : aucune migration ; sauvegarde avec le reste de Firestore. Un APK antérieur
   à D3 lit un brassin résolu comme une journée unique : il ignore `process`, et les débuts
   d'étape du modèle s'y affichent comme anomalies. Installer l'APK de D3 sur chaque téléphone
   qui suit un brassin avant le 22 novembre. Le web se met à jour au rechargement (P1).
9. **Coût de sortie** : nul vis-à-vis du fournisseur. Le déroulé est un JSON documenté. Le
   retirer revient à ignorer `process` : la lecture tolérante rend la journée de la recette.

## Conséquences

Plus simple : les étapes de préparation et de nettoyage se saisissent une fois par brasseur ;
le houblonnage et l'embouteillage se suivent hors ligne avec minuteurs et mesures.

Plus difficile : chaque lecteur des étapes d'un brassin passe par le déroulé ; le calcul se
découpe par journée ; l'écran du jour s'ouvre à trois statuts ; deux écritures à la création
d'un brassin.

Règles et contrôles à ajouter à `CLAUDE.md` (proposés dans le livrable de l'architecte,
appliqués par la session principale après le « oui » de l'utilisateur) : règle « Le jour de
brassage marche sans réseau » étendue à chaque journée ; « Un brassin fige sa recette » étendue
au déroulé ; P2, P3 et P5 complétés ; deux contrôles nouveaux (P37 lecture du déroulé et découpage
par journée, `relecteur-regles` ; P38 règles des modèles et du déroulé, `securite`).

Reporté à la livraison suivante : prévu/réel par étape et mise à jour du modèle depuis un
brassin (lu par `template_step_key`).

## Sources

- Limites de Cloud Firestore : document de 1 Mio au plus, 1 000 expressions évaluées par
  requête de règles, 10 appels `get()`/`exists()` par requête d'un document et 20 par lot
  d'écritures. https://firebase.google.com/docs/firestore/quotas, consulté le 2026-11-11.
- « Some document access calls may be cached, and cached calls do not count towards the
  limits. » https://firebase.google.com/docs/firestore/security/rules-conditions, consulté le
  2026-11-11.
- Marges de budget du dépôt : mesures de la v0.1.15 et de la v0.1.17, commentaire de
  `firestore.rules` au-dessus de `match /brews/{brewId}` et
  `rules-tests/test/recipe_format.test.mjs`, lus le 2026-11-11.
