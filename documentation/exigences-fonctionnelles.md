# Exigences fonctionnelles

État actuel du produit. L'historique vit dans `CHANGELOG.md`.

## Rôles et droits

Un compte n'ouvre l'application que si l'administrateur l'a invité : un document
`members/{e-mail}` existe pour l'adresse de son compte Google. Aucun e-mail n'est envoyé à
l'invitation.

| Rôle | Peut |
|---|---|
| `brewer` (Brasseur) | se connecter ; ouvrir Recettes, Brassins et Équipements ; lire toutes les recettes et tous les équipements du groupe ; créer des recettes et des équipements, modifier et supprimer les siens ; dupliquer toute recette à son nom ; créer un brassin depuis toute recette ; lire les brassins du groupe, leurs étapes, leurs mesures, leurs relevés et leur embouteillage ; suivre le jour de brassage, noter les relevés de fermentation, embouteiller, changer le statut et modifier ses seuls brassins ; saisir ses prix d'achat et ses frais (« Mes prix ») ; lire le coût de toute recette avec ses propres prix ; lire, figer et recalculer le coût de ses seuls brassins ; voir son nom, son e-mail et la version dans le menu du compte ; ouvrir « Nouveautés » depuis ce menu ; se déconnecter |
| `admin` (Administrateur) | tout ce que peut un brasseur, avec les mêmes droits sur ses propres recettes, équipements et brassins et aucun droit d'écriture sur ceux des autres ; ouvrir Admin ; inviter un compte (adresse, nom facultatif, rôle) ; retirer un brasseur. Il ne lit ni les prix, ni les frais, ni les coûts d'un autre membre. Il ne peut ni se retirer lui-même, ni retirer un autre administrateur : un administrateur se retire depuis la console Firebase |
| compte non invité | voir l'écran « Compte non invité », copier son adresse, vérifier à nouveau, se déconnecter. Rien d'autre |

Pas de changement de rôle : l'administrateur retire le compte puis le réinvite. Seul
l'administrateur saisit le nom d'un membre. Les prix, les frais et les coûts figés d'un
membre ne sont lus que par lui, administrateur compris ; ceux d'un membre retiré restent en
base et plus personne ne les lit. Retirer un compte ne supprime ni ses recettes ni
ses brassins, qui restent visibles du groupe. Les recettes et équipements d'un membre retiré
restent lisibles, ne sont plus modifiables par personne dans l'application, et peuvent être
dupliqués.

L'auteur d'une recette ou d'un équipement s'affiche « Vous » pour soi, sinon par le nom de
son compte Google enregistré avec le contenu, sinon « Autre brasseur ». Ce nom ne donne
aucun droit : seuls les droits du compte auteur comptent.

## Modules et parcours

L'application tourne sur Android (APK) et sur le web. Les écrans s'adaptent à la largeur :
moins de 600 px (téléphone), de 600 à 839 px, 840 px et plus.

### Démarrage et accès

1. **Chargement.** Logo, nom et indicateur, tant que la session et le document du membre
   ne sont pas lus.
2. **Connexion** (sans session). Titre « Kass'Beer », sous-titre « Recettes et brassins du
   groupe », bouton « Se connecter avec Google », note « Accès réservé aux comptes
   invités. ». Sur le web, une fenêtre Google s'ouvre ; sur Android, le choix de compte du
   téléphone.
   - Fenêtre Google fermée : retour à l'écran, sans message.
   - Réseau absent : « Connexion impossible. Vérifiez le réseau et réessayez. »
   - Autre échec : « La connexion a échoué. Réessayez. »
   - Pendant la connexion, le bouton affiche « Connexion en cours ».
3. **Contrôle d'accès.** L'adresse du compte, en minuscules, est cherchée dans `members/`.
   - Trouvée : Accueil, section Recettes.
   - Absente du serveur : Compte non invité.
   - Lecture impossible (réseau, refus, serveur muet 10 s quand l'appareil ne connaît pas
     encore le compte) : écran Erreur, « Impossible de vérifier votre accès. Vérifiez le
     réseau et réessayez. », boutons « Réessayer » et « Se déconnecter ». Une panne n'est
     jamais présentée comme « non invité ».
   - Un membre retiré pendant que l'application est ouverte passe sur Compte non invité dès
     que l'application reçoit le changement.
4. **Compte non invité.** Titre « Ce compte n'a pas accès à Kass'Beer », « Vous êtes
   connecté avec : », l'adresse en gros caractères (sélectionnable), « Transmettez cette
   adresse à l'administrateur. Une fois invité, appuyez sur Vérifier à nouveau. ». Boutons
   « Copier l'adresse » (annonce « Adresse copiée » ; en cas d'échec « Copie impossible.
   Sélectionnez l'adresse à la main. »), « Vérifier à nouveau » (« Vérification en cours »
   pendant la lecture, puis « Ce compte n'est toujours pas invité. » si l'adresse reste
   absente), « Se déconnecter ».
   - Compte Google sans adresse : ni adresse ni « Copier l'adresse » ; le message
     « Adresse du compte indisponible. Déconnectez-vous et reconnectez-vous. » et
     « Se déconnecter ».

Une page du web rechargée revient à la même page une fois l'accès vérifié, sauf une page
d'Admin pour un brasseur, qui renvoie sur Recettes.

### Accueil

Barre du haut : titre de la section, avatar Google à droite (« Mon compte »). Le menu du
compte montre le nom, l'e-mail, « Version X.Y.Z » (« Version indisponible » si elle n'a pas
pu être lue), un séparateur, « Mes prix », un séparateur, « Nouveautés », un séparateur et
« Se déconnecter ». Une déconnexion qui échoue affiche « Déconnexion impossible. Réessayez. ».

Destinations : Recettes, Brassins, Équipements, et Admin pour l'administrateur seul. Sous
600 px, barre de navigation en bas ; de 600 à 839 px, rail de navigation avec libellés ;
à partir de 840 px, rail étendu et contenu centré sur 840 px au plus. Le rail défile quand
ses destinations dépassent la hauteur (écran bas, grand texte).

Recettes, Équipements et Brassins sont décrits ci-dessous. Au lancement, si le compte a un seul
brassin en cours depuis moins de 24 h, l'écran du jour se rouvre avec le message « Brassage
repris. Les minuteurs comptent le temps écoulé. ».

Une page de second niveau (fiche d'une recette, d'un équipement, Admin › Membres) porte son
titre (« Recette », « Équipement », « Membres ») et un bouton retour vers sa liste. Les
éditeurs s'ouvrent en plein écran, hors de la barre de navigation, avec « Fermer » (✕), leur
titre, « Enregistrer », et le bandeau hors ligne quand l'appareil n'a pas de réseau.

**Hors ligne.** Quand l'appareil n'a plus de réseau, un bandeau « Hors ligne. Les
modifications partiront au retour du réseau. » s'affiche sous la barre du haut, en pleine
largeur, et il est annoncé aux lecteurs d'écran.

**Page introuvable.** Une adresse inconnue affiche « Cette page n'existe pas. » et le bouton
« Revenir à l'accueil ».

### Nouveautés

Ouvert depuis le menu du compte, pour tout membre (adresse `/nouveautes`). Plein écran, hors
de la barre de navigation : titre « Nouveautés » et flèche retour. La flèche revient à l'écran
d'où le membre est parti ; ouvert par son adresse, elle mène à l'accueil.

- En-tête : « Version installée : X.Y.Z. Seules les versions qui changent ce que vous voyez
  sont listées. », ou « Version installée indisponible. … » si la version n'a pas pu être lue.
- Une carte par version, la plus récente en tête : « Version X.Y.Z » (titre lu comme en-tête par les
  lecteurs d'écran), l'étiquette « Installée » sur la version de l'appareil, la date
  (« 8 novembre 2026 », « 1er » le premier du mois) et le texte de l'entrée « fonctionnel » du
  CHANGELOG, en paragraphes sélectionnables. Six versions au plus.
- Chargement : indicateur « Chargement des nouveautés ».
- Fichier illisible : « Impossible d'afficher les nouveautés. » et « Réessayer » ; la panne est
  journalisée.
- Aucune version : « Aucune nouveauté à afficher. » et « Revenir à
  l'accueil ».
- Le texte est livré avec l'application : l'écran marche sans réseau, sans bandeau hors ligne.
  Colonne de 840 px au plus.

### Admin

Réservé à l'administrateur. Deux entrées : « Membres » (« Inviter et retirer les comptes »)
et « Import » (« Disponible dans une prochaine version », inactive).

**Admin › Membres.** Liste des membres, administrateurs d'abord, puis par adresse. Chaque
ligne : nom (ou « Nom non renseigné »), adresse, étiquette « Administrateur » ou
« Brasseur » (« Rôle inconnu » pour une valeur stockée inattendue), étiquette « Vous » sur sa
propre ligne, et « En attente du réseau » tant
qu'une invitation faite hors ligne n'a pas atteint le serveur.

- **Inviter** : bouton flottant « Inviter » sur téléphone, bouton en tête de liste sur
  grand écran. Le formulaire « Inviter un membre » (feuille du bas sur téléphone, dialogue
  sinon) demande « Adresse e-mail Google » (mise en minuscules), « Nom (facultatif) » et,
  sous le titre « Rôle », « Brasseur » (par défaut) ou « Administrateur ». Sur le web, Entrée valide. Erreurs :
  « Adresse e-mail invalide. », « Cette adresse est déjà membre. ». Après « Inviter », le
  formulaire se ferme aussitôt, même hors ligne, et l'écran affiche « {e-mail} est invité.
  Aucun e-mail n'est envoyé : prévenez-le. ». Si le serveur refuse l'invitation, ce message
  est remplacé par « L'invitation de {e-mail} a échoué. »
- **Retirer** : icône « Retirer {e-mail} » sur la ligne de chaque brasseur. Sa propre ligne
  porte « Vous ne pouvez pas vous retirer vous-même », celle d'un autre administrateur « Un
  administrateur se retire depuis la console Firebase. », sans icône. Confirmation « Retirer {e-mail} ? » / « Ce compte
  n'aura plus accès à Kass'Beer. Ses recettes et brassins restent visibles du groupe. »,
  boutons « Annuler » et « Retirer ». Après « Retirer », la ligne disparaît et l'écran
  affiche « {e-mail} est retiré. ». Si le serveur refuse, ce message est remplacé par « Le
  retrait de {e-mail} a échoué. »
- Liste vide : « Aucun membre. Appuyez sur Inviter pour ajouter un compte. »
- Liste illisible : « Impossible de lire la liste des membres. » et « Réessayer ». Une panne
  après une première lecture garde la liste affichée, avec au-dessus « Mise à jour de la
  liste impossible. Elle peut ne plus être à jour. » et « Réessayer ».

### Équipements

**Liste.** Tous les équipements du groupe, les siens d'abord, puis par nom. Chaque ligne :
nom, puis « Cuves séparées » ou « Tout-en-un » · « Rendement 72 % » (ou « Rendement non
renseigné ») · auteur. Étiquette « En attente du réseau » tant qu'une écriture n'a pas
atteint le serveur. Bouton flottant « Nouvel équipement » sur téléphone, bouton en tête de
liste au-delà.

- Liste vide : « Aucun équipement. Appuyez sur Nouvel équipement pour décrire votre
  installation. »
- Lecture impossible : « Impossible de lire les équipements. » et « Réessayer ». Une panne
  après une première lecture garde la liste, avec « Mise à jour de la liste impossible. Elle
  peut ne plus être à jour. » et « Réessayer ».
- Un document illisible (type inconnu, champ obligatoire absent) s'affiche « Équipement
  illisible » ; l'erreur est rapportée.

**Fiche.** Une colonne : nom, type, et « Équipement de {auteur} » pour un autre brasseur.
Sections Rendement (rendement d'empâtage, évaporation, absorption du grain), Volumes (cuve
d'empâtage et cuve d'ébullition, ou « Volume de la cuve » pour un tout-en-un), Pertes
(volumes morts, pertes au trub, pertes au fermenteur), Notes. Un champ vide affiche « Non
renseigné ». Étiquette « En attente du réseau » tant qu'une écriture n'a pas atteint le
serveur. L'auteur voit « Modifier » et « Supprimer » ; un autre brasseur ne les voit pas.

- Équipement absent d'une réponse du serveur : « Cet équipement n'existe pas ou a été
  supprimé. » et « Revenir aux équipements ». Absent du cache, appareil hors ligne :
  « Équipement indisponible hors ligne. ». L'application n'annonce jamais une suppression sans
  réponse du serveur.

**Formulaire** (« Nouvel équipement » / « Modifier l'équipement », plein écran, une colonne).
« Nom de l'équipement » (obligatoire, 120 caractères ; sinon « Donnez un nom à
l'équipement. »), « Type » (« Cuves séparées » ou « Tout-en-un », obligatoire ; sinon
« Choisissez un type. »), « Rendement d'empâtage (%) » (aide « Sert au calcul de la densité
initiale des recettes. », de 0 à 100), « Évaporation (L/h) », « Absorption du grain (L/kg) »,
« Volume de la cuve d'empâtage (L) » et « Volume de la cuve d'ébullition (L) » (« Volume de
la cuve (L) » seul pour un tout-en-un, plus de 0 L), « Volume mort de la cuve d'empâtage (L) »,
« Volume mort de la cuve d'ébullition (L) », « Pertes au trub (L) », « Pertes au fermenteur
(L) » (0 ou plus), « Notes (facultatif) » (10 000 caractères). Une valeur hors bornes affiche
son message sur le champ et rien n'est enregistré. Un tout-en-un n'enregistre pas de cuve
d'ébullition.

**Supprimer.** Confirmation « Supprimer « {nom} » ? » / « L'équipement disparaît pour tout
le groupe. », plus, s'il sert à des recettes (de tous les brasseurs) : « Utilisé par N
recettes : {noms}. Leurs calculs afficheront Équipement supprimé. ». Si les recettes n'ont
pas pu être lues : « Les recettes qui l'utilisent n'ont pas pu être lues. Leurs calculs
afficheront Équipement supprimé. ». Les recettes gardent leur équipement d'origine ; aucune
recette n'est modifiée.

### Recettes

**Liste.** Toutes les recettes du groupe, la dernière modifiée en tête. Chaque ligne : nom,
puis style · volume · auteur ; étiquette « En attente du réseau ». « Rechercher une
recette » filtre sur le nom et le style ; « Toutes » / « Les miennes » filtre sur l'auteur.
La recherche et le filtre ne sont pas enregistrés. Aucun calcul dans la liste. Bouton
flottant « Nouvelle recette » sur téléphone, bouton en tête au-delà.

- Liste vide : « Aucune recette. Appuyez sur Nouvelle recette pour commencer. » ; « Les
  miennes » vide : « Vous n'avez pas encore de recette. Appuyez sur Nouvelle recette pour
  commencer. » ; recherche sans résultat : « Aucune recette ne correspond à « {texte} ». » et
  « Effacer la recherche ».
- Lecture impossible et panne après une première lecture : comme les équipements, avec
  « Impossible de lire les recettes. ». Un document illisible s'affiche dans la liste
  « Recette illisible », avec le sous-titre « Mettez l'application à jour, ou prévenez
  l'administrateur. » ; sa fiche et son éditeur affichent « Cette recette ne peut pas
  s'afficher. Elle a peut-être été enregistrée par une version plus récente de Kass'Beer :
  mettez l'application à jour. L'erreur est signalée à l'administrateur. ». L'erreur est
  rapportée (`error_reports/`) avec la longueur de la valeur fautive, jamais la valeur.
  Depuis la v0.1.15 (recettes en BeerJSON, ADR-005), une recette est illisible si sa version
  de format manque ou est inconnue (document de la v0.1.14 compris), si une unité ou une
  valeur énumérée sort du modèle, ou si une durée en minutes n'est pas entière. Une copie
  figée illisible rend le brassin illisible : « Brassin illisible » dans la liste, même
  sous-titre ; sur sa fiche, sa préparation et l'écran du jour, « Ce brassin ne peut pas
  s'afficher. Il a peut-être été enregistré par une version plus récente de Kass'Beer :
  mettez l'application à jour. L'erreur est signalée à l'administrateur. », avec le bouton
  « Revenir aux brassins », qui ramène à la liste. Relire le brassin rendrait le même
  document : la préparation garde « Réessayer » pour un brassin absent ou hors ligne
  seulement. Hors ligne, le rapport part au retour du réseau.

**Fiche.** Nom, style, « Recette de {auteur} » pour un autre brasseur. Boutons « Modifier »
et « Supprimer » pour l'auteur, « Dupliquer » pour tous. Puis le bloc Calculs (voir
« Calculs affichés »), le bloc « Coût avec vos prix » (voir « Coût »), et les sections Général (type de recette, « Non renseigné » s'il
manque ; volume en fermenteur, durée d'ébullition, équipement), Malts et sucres, Houblons
(avec l'IBU apporté par chacun), Autres ajouts, Levure, Paliers d'empâtage, Chronologie du
jour, Notes. Chaque ligne d'ingrédient tient sur deux niveaux : nom, puis ses valeurs. Un
ajout porte son type en tête (« Correction de l'eau · 5 g · Empâtage · 60 min ») ; la levure
« Haute fermentation (ale) · 11 g · atténuation 75 % · Sèche » ; un palier « Infusion ·
65 °C · 60 min » (libellé court du type de palier ; le libellé long, « Infusion (eau chaude
ajoutée) », ne figure que dans le menu de l'éditeur). Quand elle est renseignée, la
température du grain précède les paliers sur une ligne libellé-valeur, comme les valeurs de
Général : « Température du grain », « 18 °C ». La copie figée d'un brassin et l'écran du
jour montrent les mêmes détails. « Nouveau brassin » (tous les membres) ouvre le
formulaire de création. Une chronologie illisible s'affiche « Chronologie illisible », sans
masquer le reste de la recette, et l'erreur est rapportée.

- Recette absente d'une réponse du serveur : « Cette recette n'existe pas ou a été
  supprimée. » et « Revenir aux recettes ». Absente du cache hors ligne : « Recette
  indisponible hors ligne. ».

**Dupliquer.** Crée « Copie de {nom} » (coupé à 120 caractères) au nom de celui qui
duplique, avec les mêmes ingrédients, paliers et équipement, sans fiche d'origine. La source
ne change pas. Possible sur toute recette, y compris celle d'un membre retiré. Message
« Recette dupliquée. » (hors ligne : « Recette dupliquée sur l'appareil. Elle partira au
retour du réseau. »), puis la fiche de la copie. Pendant la lecture du nom du compte, le
bouton affiche « Duplication » et ne répond pas : un double appui ne crée qu'une copie.

**Chronologie du jour.** La section montre les étapes et la durée totale. Pour l'auteur,
« Modifier la chronologie » ouvre l'éditeur plein écran « Chronologie du jour », qui n'écrit que
la chronologie (« Total : 5 h 40 · 11 étapes »). Sans étape : « Aucune étape. Préremplissez
depuis les paliers et l'ébullition, ou ajoutez une étape. », boutons « Préremplir depuis la
recette » et « Ajouter une étape ». Le préremplissage crée une étape par palier, puis
l'ébullition coupée à chaque ajout de houblon (« Ébullition », « Ajouter Cascade 20 g »,
0 min), puis le whirlpool. Avec des étapes, « Repartir des paliers et de l'ébullition » demande
« Remplacer les {n} étapes ? ». Modifier un palier ensuite ne change pas la chronologie. Chaque
étape : « Nom de l'étape » (120 caractères), « Durée (min) » (0 à 600 ; 0 pour une action sans
minuteur), « Température visée (°C) (facultatif) » (0 à 100). Menu ⋮ : « Monter », « Descendre »,
« Dupliquer », « Retirer » (SnackBar « Annuler ») ; poignée pour réordonner. Au plus 60 étapes
(« 60 étapes au plus. »). La clé d'une étape ne change ni au renommage ni au déplacement ;
dupliquer une recette garde les clés. L'adresse de l'éditeur pour un autre membre affiche « Seul
l'auteur modifie cette chronologie. ».

**Supprimer** (auteur). « Supprimer « {nom} » ? » / « La recette disparaît pour tout le
groupe. », boutons « Annuler » et « Supprimer ». Puis « Recette supprimée. ».

**Éditeur** (« Nouvelle recette » / « Modifier la recette », plein écran). Sections toujours
ouvertes, avec des puces de saut en haut (« Malts et sucres (7) », « Houblons (3) »…).

- Général : « Nom » (seul champ obligatoire, 120 caractères ; sinon « Donnez un nom à la
  recette. », l'écran remonte au champ et y place le curseur), « Style (facultatif) »,
  « Type de recette » (liste déroulante : « Non précisé », Tout grain, Empâtage partiel,
  Extrait), « Volume en fermenteur (L) » (plus de 0), « Durée d'ébullition (min) » (entier
  de 0 à 600), « Équipement » (« Aucun
  équipement », les siens, puis ceux du groupe avec leur auteur ; un équipement disparu
  s'affiche « Équipement supprimé »). Une nouvelle recette présélectionne l'équipement du
  brasseur s'il n'en a qu'un. Une recette incomplète s'enregistre.
- Chaque section a son bouton : « Ajouter un malt ou un sucre », « Ajouter un houblon »,
  « Ajouter un ajout », « Ajouter une levure » (une seule levure), « Ajouter un palier ». Le
  formulaire s'ouvre en feuille du bas sur téléphone, en dialogue au-delà, avec « Annuler »,
  « Ajouter et continuer » (ajoute la ligne, vide le formulaire, remet le curseur sur « Nom »
  et annonce « « {nom} » ajouté. ») et « Ajouter » (« Enregistrer » pour une ligne
  existante).
- Malt ou sucre : « Nom », « Nature » (Malt, Sucre), « Quantité (kg) » (obligatoire),
  « Couleur (EBC) » (aide « Sert au calcul de la couleur. »), « Rendement d'extrait (%) »
  (aide « Sert au calcul de la densité initiale. »).
- Houblon : « Nom », « Quantité (g) », « Acides alpha (%) », « Utilisation » (Ébullition,
  Whirlpool, À cru), durée, « Forme » (Pellets, Cônes, sans choix par défaut ; sinon
  « Choisissez une forme. »). La durée dépend du moment : « Durée d'ébullition (min) »,
  obligatoire, entier de 0 à 600 ; « Durée d'infusion (min) » au whirlpool, obligatoire,
  entier de 1 à 600 (« Champ obligatoire. » si vide ; à 0, « Au moins 1 min. Pour un ajout à
  l'arrêt du feu, choisissez Ébullition et 0 min. »), avec l'aide « Temps entre l'arrêt du
  feu et le refroidissement. Pour un ajout à l'arrêt du feu sans infusion, choisissez
  Ébullition et 0 min. », jamais coupée ; « Durée à cru (jours) », facultative, décimale
  permise, enregistrée en minutes entières (jours × 1 440, arrondi à la minute). Le
  formulaire garde une durée par moment : le texte saisi est mémorisé pour chaque moment,
  revenir à un moment remet son texte, un moment jamais saisi a un champ vide.
- Autre ajout : « Nom », « Quantité (g) », « Type d'ajout » (liste déroulante : « Non
  précisé », Correction de l'eau, Clarifiant, Épice, Herbe, Arôme, Bois, Autre),
  « Utilisation » (facultative : Empâtage, Ébullition, Après ébullition, Fermentation,
  Embouteillage), « Durée (min) » (entier). Une durée sans utilisation est refusée :
  « Choisissez une utilisation. » ; ce message s'efface dès qu'une utilisation est choisie
  ou que la durée est vidée. Un ajout « Après ébullition » sans durée s'enregistre comme un
  ajout à 0 min d'ébullition et se relit « Ébullition · 0 min » ; tant que la durée est vide,
  l'aide « Sans durée, l'ajout est enregistré à l'arrêt du feu (Ébullition, 0 min). »
  s'affiche sous « Durée (min) ». Aucun calcul.
- Levure : « Nom », « Quantité (g) » (facultative, plus de 0, aide « Le coût compte un
  sachet par levure, quelle que soit la quantité. » ; la quantité n'entre dans aucun calcul
  de coût), « Atténuation (%) »,
  « Type de levure » (liste déroulante : « Non précisé », Haute fermentation (ale), Basse
  fermentation (lager), Kveik, Brettanomyces, Lactobacilles, Pédiocoques, Culture mixte,
  Champagne, Vin, Fermentation spontanée, Bactéries malolactiques, Autres bactéries,
  Autre), « Forme » (Sèche, Liquide, facultative).
- Paliers d'empâtage : « Température du grain (°C) » en tête de section, facultative,
  décimale, de -20 à 60 (« Entre -20 et 60. »), aide « Température des malts au moment de
  l'empâtage, souvent celle de la pièce. » ; elle s'enregistre sans palier. Palier : « Nom »,
  « Température (°C) » (0 à 100), « Durée (min) » (entier de 0 à 600 ; la touche « Suivant »
  du clavier passe au type), « Type de palier » (liste déroulante : « Non précisé »,
  Infusion (eau chaude ajoutée), Chauffe de la cuve d'empâtage, Décoction, Rinçage, Vidange
  de la cuve d'empâtage, Acidification à l'empâtage, Acidification du moût ; le champ
  affiche le libellé court, « Infusion »).
- Listes déroulantes : une entrée tient sur deux lignes à grande taille de texte.
- Aucune valeur n'est choisie d'avance dans les nouveaux champs. Une valeur absente de ces
  listes mais connue du modèle (venue d'un futur import) s'affiche sous son libellé français
  et l'enregistrement la conserve. Types de recette : Cidre, Kombucha, Soda, Hydromel, Vin,
  Autre ; type de levure : Levure de blanche ; formes de levure : Gélose, Culture, Lie (la
  forme importée reste visible et choisie dans le formulaire, à côté de Sèche et Liquide).
  Ces valeurs ne sont pas proposées à la saisie.
- Un appui sur une ligne ouvre son formulaire. Le menu ⋮ propose « Dupliquer » et
  « Retirer » (sans confirmation ; la SnackBar « « {nom} » retiré. » propose « Annuler »),
  et pour un palier « Monter » et « Descendre ». Les malts et sucres se rangent par masse
  décroissante ; les houblons par moment (ébullition de la plus longue à la plus courte,
  whirlpool, à cru) ; l'ordre est enregistré tel quel.
- Plafonds : 50 malts et sucres, 50 houblons, 50 ajouts, 20 paliers. Au plafond, le bouton
  d'ajout est inactif avec « 50 houblons au plus. » (etc.).
- Avertissements non bloquants : « Quantité inhabituelle : 22 400 g. Vérifiez la saisie. »
  au-delà de 1 000 g pour un houblon ou un ajout, de 30 kg pour un malt ou un sucre ;
  « Volume inhabituel : 250 L. Vérifiez la saisie. » au-delà de 200 L ; « Plus long que
  l'ébullition de la recette. » pour un houblon d'ébullition plus long que la durée
  d'ébullition.
- Les calculs se mettent à jour à chaque changement : barre en bas sous 840 px (« DI 1057,9
  · DF 1012,0 · 5,9 % · 32 IBU · 18 EBC », « — » pour un calcul indisponible ; un appui ouvre
  le bloc complet ; masquée quand le clavier est ouvert), panneau à droite au-delà.
- « Enregistrer » ferme l'éditeur et ouvre la fiche avec « Recette enregistrée. » (hors
  ligne : « Recette enregistrée sur l'appareil. Elle partira au retour du réseau. »). Un
  refus du serveur affiche « L'enregistrement de « {nom} » a échoué. ».
- Quitter avec des changements (✕, retour Android) : « Abandonner les modifications ? » /
  « Les changements de cette recette ne seront pas enregistrés. », boutons « Continuer la
  saisie » et « Abandonner ». Même chose pour l'équipement.
- L'adresse de modification d'une recette d'un autre affiche « Seul l'auteur modifie cette
  recette. » et « Voir la recette » (« Seul l'auteur modifie cet équipement. » et « Voir
  l'équipement » pour un équipement).

**Saisie des nombres.** Virgule ou point décimal ; les espaces sont ignorés. « 22.4 » et
« 22,4 » valent 22,4 ; « 1.500 » kg vaut 1,5 kg. Un nombre qui contient plus d'un séparateur
(« 1.234,5 ») est refusé, comme un nombre trop long pour être lu (plus de 309 chiffres).
Messages : « Champ obligatoire. », « Nombre illisible. », « Nombre positif attendu. »,
« Entre 0 et 100. », « Nombre trop grand. » (à partir de 1 000 000 000, la borne des règles),
« Nombre entier attendu. » (toute durée en minutes d'une recette, hors chronologie du jour).
L'unité figure dans le libellé du champ (« Quantité (kg) »). À l'enregistrement, un champ en
erreur bloque l'enregistrement même hors de l'écran : l'éditeur défile jusqu'au premier champ
en erreur ; un nom manquant reçoit le curseur. Chaque moment d'un houblon garde sa propre
durée : des minutes d'ébullition ne deviennent ni des minutes d'infusion ni des jours. Une
aide ou un message d'erreur sous un champ n'est pas coupé. Un nom d'ingrédient sans lettre ni chiffre est refusé :
« Le nom doit contenir une lettre ou un chiffre. ». Aucun champ de prix ni de stock.

**Affichage.** Virgule décimale, espace insécable avant l'unité : densité « 1057,9 », degré
« 6,6 % vol », « 32 IBU », « 18 EBC » (entiers), malts et sucres en kilogrammes (« 4,5 kg »),
houblons et ajouts en grammes (« 22,4 g »), « 20 L », « 67 °C », « 60 min », houblon à cru
« 3 jours » (« 1,5 jour » au singulier sous 2). Les tuiles des calculs s'élargissent avec la
taille du texte : à 200 %, elles passent sur une colonne plutôt que de couper « 1057,9 ».

### Brassins

**Nouveau brassin** (fiche d'une recette, tous les membres). « Nom du brassin » (prérempli, 120
caractères), « Équipement » (les siens puis ceux du groupe avec leur auteur ; présélection :
celui de la recette, sinon son seul équipement ; obligatoire : « Choisissez un équipement. » ;
hors ligne sans équipement lu : « Équipement indisponible hors ligne. Reconnectez le téléphone
pour créer le brassin. »), « Date prévue (facultatif) » (aujourd'hui par défaut, effaçable). Le
brassin reçoit une copie de la recette et de l'équipement : la recette peut changer ensuite, le
brassin garde sa version. Recette sans chronologie : le brassin se crée, sans étape à suivre.
Messages : « Brassin créé. », « Brassin créé sur l'appareil. Il partira au retour du réseau. »,
« La création de « {nom} » a échoué. ».

**Liste** (tous les brassins du groupe). En cours, puis En fermentation et En conditionnement,
puis prévus par date croissante, puis Terminés et Abandonnés, chaque groupe du plus récent au plus
ancien. « Tous » / « Les miens », non enregistré. Chaque ligne :
nom, « {statut} · {équipement} · {auteur} », date (« Prévu le sam. 15 nov. 2026 », « Commencé
aujourd'hui à 11:15 », « Brassé le 11 févr. 2024 », « Embouteillé le 3 déc. 2026 » en
conditionnement), étiquette « En attente du réseau ». Vide :
« Aucun brassin. Ouvrez une recette et appuyez sur Nouveau brassin. ». Statuts : Prévu, En
cours, En fermentation, En conditionnement, Terminé, Abandonné.

**Fiche.** Nom, ligne de statut (« En fermentation · J+12 », « En conditionnement · Embouteillé
le 3 déc. 2026 », « Terminé · Embouteillé le 3 déc. 2026 »), lien vers la recette, « Brassin de
{auteur} » pour un autre membre. Prévu et En cours : bloc Calculs sur la copie figée, Chronologie
(heures, état, mesures), sections de la recette figée, Général (date prévue, brassé le,
équipement). Après le brassage, dans l'ordre : en fermentation, Relevé, Prévu et mesuré, Notes ;
en conditionnement, Prévu et mesuré, Embouteillage, Relevé, Notes ; terminé, Prévu et mesuré,
Embouteillage, Notes, Relevé ; abandonné, Relevé, Prévu et mesuré, Embouteillage (si `bottled_at`
existe), Notes. Puis Général, le pli « Chronologie » (fermé), le pli « Recette et calculs prévus »
(fermé sur téléphone, ouvert à partir de 840 pixels). Un brassin en cours affiche aussi le relevé
s'il en existe un. Pour le propriétaire seul, le bloc « Coût » (voir « Coût ») suit
l'Embouteillage quand il existe (Terminé : avant les Notes), sinon Prévu et mesuré ; prévu et en
cours, il suit Général. Un autre membre, administrateur compris, ne voit ni ce bloc ni son titre. Propriétaire : « Préparer le brassage » (prévu), « Reprendre le brassage » (en
cours), « Marquer comme terminé » (en conditionnement), « Reprendre ce brassin » (abandonné). À
partir de En cours, le menu ⋮ (« Plus d'actions ») porte « Modifier » (nom, date prévue, notes ;
quitter avec une modification : « Les modifications de ce brassin ne seront pas enregistrées. »),
« Revenir à {statut} », « Abandonner ce brassin » et « Supprimer » selon le statut ; un brassin
prévu garde ses boutons « Modifier » et « Supprimer ». Un appui sur une mesure ouvre sa correction.
Autre membre : aucun bouton, mêmes chiffres. La recette a changé depuis
la création : « La recette a changé depuis la création de ce brassin. Il garde la version du
{date}. » ; pour un brassin prévu sans saisie, « Recréer depuis la recette ».
« Préparé sur cet appareil » s'affiche quand la préparation a abouti pendant la session ; sans
cette information, rien ne s'affiche.

**Supprimer** (propriétaire). « Supprimer « {nom} » ? » / « Le brassin, ses étapes et ses mesures
disparaissent pour tout le groupe. ». Le coût figé du brassin est supprimé avec lui. Sans saisie : immédiat, même hors ligne. Avec saisies :
réseau exigé (hors ligne, le message s'affiche avant la confirmation : « Suppression impossible
hors ligne : ce brassin a des saisies. »).

**Statuts** (propriétaire). « Terminer le brassage » passe En cours à En fermentation. En
fermentation : « Ajouter un relevé » (FAB sur téléphone, bouton au-delà) et « Embouteiller ». En
conditionnement : « Marquer comme terminé », sans confirmation (« Brassin terminé. » avec
« Annuler » 10 s), et « Ajouter un relevé » sous la liste. Terminé : aucune action principale ;
sans note, le propriétaire lit « Aucune note. Ajoutez votre avis sur cette bière. » et « Modifier
les notes ». « Abandonner ce brassin » (En cours, En fermentation, En conditionnement) demande
« Abandonner « {nom} » ? » / « Le brassin reste visible du groupe, avec ses mesures. Vous pourrez
le reprendre. ». « Reprendre ce brassin » rend En conditionnement si le brassin a été embouteillé,
sinon En fermentation, sans confirmation. « Revenir à {statut} » demande « Revenir à « {statut} » ? »
/ « Les mesures et l'embouteillage sont gardés. », avec « L'écran du jour s'ouvrira de nouveau par
Reprendre le brassage. » vers En cours. Annonces : « Brassin revenu à {statut}. », « Brassin
abandonné. », « Brassin repris : {statut}. ». Hors ligne : « Statut changé sur l'appareil. Il partira
au retour du réseau. ». L'ordre des statuts n'est pas contrôlé : un retour en arrière et une file
hors ligne passent.

### Relevé de fermentation

Section « Relevé de fermentation » de la fiche, visible à partir de En fermentation, et dans tout
statut si un relevé existe. Relevés du plus récent au plus ancien ; sur téléphone, les 5 plus
récents puis « Voir les N relevés plus anciens ». Ligne : densité, température, écart au relevé
de densité précédent (« −3,0 pts »), puis « sam. 15 nov. 18:30 · J+5 », la note, et « En attente
du réseau ». J+N est l'écart en jours calendaires depuis le brassage. À partir de deux densités,
une courbe s'affiche au-dessus de la liste (densité en trait plein, température en pointillés,
légende écrite, info-bulle au toucher) ; sans date de brassage, seule la liste s'affiche. Une valeur
enregistrée que le calcul refuse affiche « Courbe indisponible : une valeur enregistrée est
refusée. » et la liste reste lisible.

« Ajouter un relevé » (propriétaire, En fermentation ou En conditionnement) : « Densité »
(0,980 à 1,200), « Température (°C) » (0 à 110), « Date et heure » (maintenant par défaut,
« Changer la date »), « Ajouter une note » (2 000 caractères). Densité, température et note sont
facultatives, sauf les trois vides : « Saisissez une densité, une température ou une note. ». Une
heure à venir : « L'heure ne peut pas être dans le futur. » ; un jour antérieur au brassage : « Le
relevé ne peut pas précéder le brassage. ». Après la date d'embouteillage : « Après
l'embouteillage : ce relevé ne compte pas dans la densité finale. », sans blocage. Quitter avec
une saisie : « La saisie de ce relevé ne sera pas enregistrée. ».

Un appui sur une ligne (propriétaire) ouvre le formulaire prérempli (« Corriger le relevé ») :
vider une valeur supprime sa mesure, en ajouter une la crée à la même heure. « Supprimer le relevé »
propose « Annuler » 10 s, qui rétablit les mêmes saisies. Messages : « Relevé enregistré. »
(« Annuler » 10 s), « Relevé corrigé. », « Relevé supprimé. », « Relevé supprimé. La densité
finale revient à la dernière mesure. » si le relevé était retenu ; refus du serveur : « Refusée
par le serveur : Densité 1020,0 du 15 nov. 18:30. Elle n'est pas enregistrée. ». Un relevé ne
s'affiche pas dans la Chronologie, et une mesure du jour ne s'affiche pas dans le relevé.

États : « Chargement des relevés », « Impossible de lire les relevés. », « Aucun relevé. Appuyez
sur Ajouter un relevé. » (propriétaire qui peut en ajouter), « Aucun relevé. », « Relevés
indisponibles sur cet appareil hors ligne. ».

### Embouteillage

« Embouteiller » (propriétaire, En fermentation) ouvre le formulaire : « Date d'embouteillage »
(aujourd'hui par défaut, ni future ni antérieure au jour du brassage), « Densité finale
(facultatif) », « Nombre de bouteilles (facultatif) » (entier de 1 à 9 999), « Volume conditionné
(L) (facultatif) » (0 exclu à 1 000), « Sucre de resucrage (g) (facultatif) » (0 à 100 000),
« Nature du sucre (facultatif) » (80 caractères). Densité finale remplie : un relevé de
fermentation est créé à l'heure d'embouteillage, dans le même envoi que le statut. Seule la date
est obligatoire : une mise en fût n'a pas de bouteilles. Information : « Le brassin passera En
conditionnement. », et, si le champ densité finale est vide et qu'aucune densité de fermentation
n'existe, « Aucune densité mesurée en fermentation : le degré restera indisponible. ».
Avertissements au-delà de 200 bouteilles, 200 L ou 1 000 g. Sortie avec saisie : « La saisie de
cet embouteillage ne sera pas enregistrée. ». Un retour en arrière garde les
données, et « Embouteiller » rouvre le formulaire prérempli.

Au premier embouteillage (aucune date d'embouteillage avant, aucun coût figé lu), le coût réel
se fige avec les prix et les frais déjà lus par la fiche, si tout est connu (voir « Coût »).
L'embouteillage part toujours, même quand le coût ne se fige pas ; le formulaire ne change pas.
Annonces, 10 s, sans aucun montant : « Embouteillage enregistré. Brassin en conditionnement.
Coût figé. », ou « … Coût non figé. » avec « Voir le coût », qui fait défiler la fiche jusqu'au
bloc Coût et y place le focus ; hors ligne, « Embouteillage enregistré sur l'appareil. Il partira
au retour du réseau. Coût figé. » ou « … Coût non figé. » ; refus du seul coût : « Coût non
figé : l'enregistrement a été refusé. » avec « Voir le coût » ; refus de l'embouteillage :
« L'enregistrement de « {nom} » a échoué. ». Une modification de l'embouteillage, ou un nouvel
embouteillage après un retour en arrière, ne fige rien : « Embouteillage modifié. », « Embouteillage
enregistré. Brassin en conditionnement. ».

La section « Embouteillage » de la fiche affiche ces cinq lignes (« Non renseigné » si vide).
« Modifier l'embouteillage » (propriétaire, En conditionnement ou Terminé) rouvre le formulaire
sans densité finale : elle se corrige dans le relevé. Aucun degré après bouteille.

### Prévu et mesuré

Le bloc « Prévu et mesuré » compare cinq lignes, Prévu / Mesuré / Écart : Densité initiale, Densité
finale, Degré, Volume en fermenteur, Rendement. Écart = mesuré moins prévu, en points pour les
densités et le rendement, en % vol pour le degré, en litres pour le volume, sans couleur. Tout est
recalculé à l'affichage ; aucune valeur n'est enregistrée, et aucune valeur prévue ne remplace une
mesure absente (« — » dans sa colonne et dans l'écart).

Densité initiale et volume retenus : la dernière mesure du jour de brassage, ou celle que le
propriétaire choisit. Densité finale retenue : la dernière densité de fermentation (hors celle
retenue comme densité initiale) ou celle choisie ; hors statut En fermentation, seuls comptent les
relevés d'un jour au plus égal à celui de l'embouteillage. Chaque valeur affiche son origine
(« Refroidissement · 8 nov. 15:20 · Dernière mesure », « Relevé J+12 · 20 nov. 18:30 · Choisie »)
et « Changer » (propriétaire), qui liste les mesures possibles et, si une mesure est retenue, « Dernière mesure (automatique) ».
En fermentation sans choix : « Densité finale (dernière mesure) », et le degré suivi de
« provisoire ». Choisir une mesure écrit l'identifiant, jamais la valeur.

Indisponible, chaque raison nommée : « Aucune densité mesurée le jour du brassage. » (« Saisir la
densité initiale »), « Aucune densité mesurée en fermentation. », « Dépend de la densité
initiale. », « Dépend de la densité finale. », « Dépend des deux densités. ». Rendement :
« Aucune densité initiale mesurée. », « Aucun volume mesuré le jour du brassage. » (« Saisir le
volume en fermenteur »), « Rendement d'extrait non renseigné : {noms}. », « Indiquez si les sucres
étaient dans le moût à cette mesure. » ; aucun malt : « Sans malt, le rendement ne s'applique
pas. ». Si la copie contient un sucre, le propriétaire répond à « Les sucres étaient-ils dans le
moût à cette mesure ? ». Calcul impossible : « Calcul impossible : la densité finale dépasse la
densité initiale. Vérifiez les mesures retenues. », « Calcul impossible : les sucres expliquent à
eux seuls la densité mesurée. ». Rendement au-delà de 100 % : la valeur s'affiche, avec
« Rendement au-delà de 100 % : vérifiez le volume et la densité. ». Sucres ajoutés après la mesure
de densité initiale : « Les sucres ajoutés après cette densité initiale ne comptent pas dans ce
degré. ».

### Préparer le brassage

Écran « Préparer le brassage » (propriétaire d'un brassin prévu ou en cours : un autre membre lit
« Seul le brasseur de ce brassin suit son brassage. », un brassin fini « Le brassage de ce brassin
est terminé. », sans bouton pour le relancer). À faire sur le téléphone qui
servira, avec du réseau, avant de le couper. Il attend une réponse du serveur, 15 s au plus, sans
rien écrire, et liste : brassin et recette figée, équipement, chronologie (« 11 étapes · 5 h 40 ·
fin vers 16:05 »), compte, écran gardé allumé, minuteurs (« Aucune alarme ne sonne écran
verrouillé : gardez l'écran visible. »). Réponse reçue : « Tout est prêt. Vous pouvez couper le
réseau. ». Sans réponse ni réseau : « Préparation impossible sans réseau. Le brassin est lisible
sur cet appareil, mais peut ne pas être à jour. ». « Commencer le brassage » passe le brassin « En
cours » avec l'heure de l'appareil, démarre la première étape si elle a une durée, et ouvre
l'écran du jour. Sur le web : « Gardez cet onglet ouvert. Une page rechargée sans réseau ne
s'ouvre plus. ».

### Jour de brassage

Écran plein écran, réservé au propriétaire. L'écran reste allumé tant qu'il est ouvert. La
barre affiche le nom du brassin et l'heure de l'appareil, mise à jour avec le minuteur. Quand le brassage
est affiché, ou pendant la lecture des saisies, le retour Android ramène à la fiche du brassin. Un
autre membre lit « Seul le brasseur de ce brassin suit son brassage. » et suit le brassin depuis
sa fiche, en lecture seule.

**Panneau.** Étape en cours : numéro, nom, minuteur lisible à deux mètres (« 32:15 », « 1:05:12 »),
« restantes sur 45 min », température visée et dernière mesure, « Ensuite : {nom} · vers 12:30 »,
« Fin prévue vers 16:05 · retard 12 min ». Durée dépassée : « +04:12 », fond distinct, « Dépassé de
4 min · prévu 45 min » (« Dépassé · prévu 45 min » la première minute). Pas d'étape en cours : « Prochaine étape : {nom} », « Maintenant » ou
« Prévue vers 12:30 », bouton « Commencer l'étape » (« Fait » pour une étape de 0 min, début et
fin au même instant). Fin : « Toutes les étapes sont faites. », « Terminer le brassage » (statut
« En fermentation »). Sans chronologie : « Aucune étape. Saisissez vos mesures. ».

**Fin d'un minuteur.** Vibration d'environ une seconde et son de notification, une seule fois
par étape, écran ouvert seulement : aucune alarme ne sonne écran verrouillé.

**Étapes.** Un appui sur une ligne ouvre : « Commencer cette étape », « Marquer comme sautée » /
« Ne plus sauter », « Corriger l'heure de début », « Corriger l'heure de fin » (l'heure choisie se place au jour le plus proche de la valeur corrigée, sans jamais être dans le futur : un début à 23:50 corrigé à 00:05 passe au lendemain, une fin notée à 08:00 corrigée à 18:00 revient à la veille ; une heure à venir se place à la veille si la veille reste après le début du brassage, sinon elle est refusée ; « La fin doit suivre le début. »), « Annuler le début » / « Annuler la fin » (SnackBar
« Annuler » 10 s), « Saisir une mesure pour cette étape ». Une étape jamais commencée s'affiche
« Non faite » dès qu'une étape plus loin a commencé ; marquée sautée, elle s'affiche « Sautée » ; dans les deux cas, elle reste démarrable.
Étapes faites : heure réelle de début et de fin. À venir : heure attendue, recalculée à partir
des heures réelles (un retard décale la suite). Commencer une étape alors qu'une autre tourne
demande « « {nom} » est en cours. », « Terminer et commencer » ; après des étapes non commencées,
« Les sauter et commencer ». Un double appui n'écrit qu'un événement. Deux débuts pour une étape
(deux appareils hors ligne) : le plus ancien compte, l'autre s'affiche « Début en double »,
supprimable. Fin avant le début : « La chronologie ne peut pas être calculée : l'étape « {nom} »
finit avant de commencer. Corrigez son heure. ».

**Mesures.** Bouton « Mesure » : étape (ou « Sans étape »), type (Température 0 à 110 °C, Densité,
Volume au-delà de 0 et jusqu'à 1 000 L, pH 0 à 14, Note), heure (« maintenant » par défaut,
une heure à venir se place à la veille si la veille reste après le début du brassage, comme 23:55 saisi à 00:05 ; sinon elle est refusée), note facultative. Densité : « 1057,9 » ou « 1.058 » (« Densité illisible.
Écrivez 1057,9 ou 1.058. », « Densité hors de 980 à 1200. »). Le formulaire ne se ferme pas par un appui hors de la feuille
ni par un glissement : seuls « Annuler » et l'enregistrement le ferment. « Enregistrer la mesure » ferme la
feuille ; « Mesure enregistrée. » avec « Annuler » 10 s. Un appui sur une mesure ouvre sa
correction (valeur, note, heure) et « Supprimer la mesure ». Pour changer de type, supprimer et
ressaisir. Menu ⋮ : « Ajouter une note », « Voir la recette », « Terminer le brassage ». Terminer :
« Les étapes non commencées resteront non faites. Vous pourrez encore corriger les mesures. ».

**Reprise.** L'application rouvre l'écran du jour au lancement (voir Accueil). Le minuteur se
recalcule depuis l'heure enregistrée, quel que soit le temps écoulé.

### Hors ligne du jour de brassage

- L'écran marche sans réseau sur l'APK, une fois « Préparer le brassage » fait. Toutes les étapes
  et les mesures s'écrivent sur l'appareil sans attente ni erreur.
- Une pastille dans la barre remplace le bandeau : « Envoyé », « Envoi · 3 », « Hors ligne · 3 »,
  « 1 refusée ». Son appui ouvre le détail : les saisies en attente, « Gardées sur ce téléphone,
  même si l'application se ferme. », et les refus. Une saisie refusée pendant que l'écran est ouvert
  s'affiche « Refusée par le serveur : Densité 1057,9 à 12:10. Elle n'est pas enregistrée. » avec
  « Saisir à nouveau » ; elle est rapportée.
- Une saisie déjà enregistrée (accusé perdu et renvoi) n'est jamais annoncée refusée.
- Limite : un refus du serveur reçu après la fermeture de l'application passe sans message : il
  n'existe pas de journal local des saisies non confirmées en v0.3.
- Au retour du réseau, chaque saisie arrive une fois, à l'heure de sa saisie, sans intervention.
- Sur le web, seul un onglet déjà ouvert marche sans réseau (« Ne fermez pas cet onglet avant le
  retour du réseau. »).
- Reporté : le message à la déconnexion avec des saisies en attente (HS8).
- Sur la fiche d'un brassin déjà ouvert en ligne sur l'appareil, relevés, corrections, suppressions,
  embouteillage, statuts et mesures retenues s'écrivent aussi sans réseau. Annonce : « … sur
  l'appareil. Il partira au retour du réseau. ». Une ligne attend avec « En attente du réseau ».
  Une suppression d'un brassin avec saisies exige toujours le réseau.
- Prix, frais, figeage au premier embouteillage, « Figer le coût » et « Recalculer » s'écrivent
  aussi sans réseau, dans le cache de l'appareil. Des prix ou des frais absents du cache
  affichent « Prix indisponibles sur cet appareil hors ligne. » et ne figent rien. Deux
  appareils qui figent le même brassin : le premier coût arrivé reste.

### Mes prix

« Mes prix » s'ouvre depuis le menu du compte (tout membre) : page pleine, hors de la barre de
navigation, avec retour. Chacun n'y voit que ses frais et ses prix. De haut en bas : « Mes
frais » (« 3 frais »), une ligne par frais triée par nom (« Électricité · 2,00 € par brassin »),
« Ajouter un frais » ; puis « Ingrédients », un pli par nature non vide (« Malts », « Sucres »,
« Houblons », « Levures », « Ajouts », résumé « 12 prix »), fermé sur téléphone, ouvert à partir
de 840 pixels. Ligne : « Pils », puis « 47,50 € les 25 kg · 1,90 €/kg » ; levure : « 3,99 € les
5 sachets · 0,80 €/sachet ». Quantité en kilogrammes à partir de 1 000 g. Montant saisi affiché
tel quel jusqu'à 4 décimales, montant calculé au centime. « Ajouter un prix » (bouton flottant
sur téléphone, bouton sous le titre « Ingrédients » au-delà). Une écriture en attente porte « En attente du réseau ».
Un appui sur une ligne ouvre sa modification.

États : « Chargement de vos prix » ; « Impossible de lire vos prix. » et « Réessayer » ; « Aucun
prix enregistré. Ajoutez-en un, ou complétez-les depuis une recette. » ; « Aucun frais. Ajoutez
l'eau, l'électricité, les capsules… pour qu'ils comptent dans le coût. » ; hors ligne sans
cache, « Prix indisponibles sur cet appareil hors ligne. », sans « Réessayer » ni bouton d'ajout.
Un prix ou un frais illisible s'affiche « Prix illisible » (« Ce prix ne peut pas être lu.
Supprimez-le, puis saisissez-le de nouveau. ») ou « Frais illisible » (même phrase pour un
frais), avec « Supprimer », qui demande « Supprimer le prix illisible ? » / « Il ne peut pas être
relu : la suppression ne pourra pas être annulée. ». Un prix dont l'identifiant sort du
format des règles (plus de 100 caractères, préfixe de nature absent, majuscule ou autre
caractère) s'affiche aussi « Prix illisible ».

**Formulaire de prix.** « Nouveau prix », « Modifier le prix », ou « Prix de « Pils » » depuis
un manquant. « Nature » (Malt, Sucre, Houblon, Levure, Ajout), « Nom » (120 caractères), « Prix
payé (€) » (0 à 100 000), « Quantité achetée (kg) » ou « (g) » selon « Unité » (kg par défaut
pour un malt ou un sucre, g pour un houblon ou un ajout), « Quantité achetée (sachets) » pour une
levure (nombre entier). Tous sont obligatoires. Le prix 0 est un prix connu. Ligne de résultat :
« Soit 1,90 €/kg » (« €/sachet » pour une levure). « Prix inhabituel : vérifiez la quantité. »
au-delà de 50 €/kg pour un malt ou un sucre, 500 €/kg pour un houblon ou un ajout, 50 € le
sachet, sans blocage. Nom sans lettre ni chiffre : « Le nom doit contenir une lettre ou un
chiffre. ». Nom dont le prix existe : « Un prix existe déjà pour « Pils ». Il sera remplacé. ».
« Corriger le prix » d'une unité incompatible laisse la quantité vide, avec « L'unité
enregistrée ne correspond pas : saisissez la quantité en kg. » (ou g, ou sachets). Un nom
venu d'une recette est coupé à 120 caractères. En modification, nature et nom sont
verrouillés : « Le nom suit celui des recettes. Pour le
changer, supprimez ce prix et ajoutez-en un autre. ». Depuis un manquant, nature et nom sont
fixés (« Malt · Pils ») ; « Reprendre un de mes prix » (s'il existe un prix de la même nature)
ouvre « Reprendre un prix de malt », dont un appui copie prix, quantité et unité dans le
formulaire, sans lien avec l'original. « Supprimer » (modification) retire le prix sans
confirmation : « Prix de « Pils » supprimé. » avec « Annuler » 10 s, qui le réécrit. Les coûts
figés ne changent pas. Quitter avec une saisie : « Le prix saisi ne sera pas enregistré. ».
Annonces : « Prix enregistré. », « Prix enregistré sur l'appareil. Il partira au retour du
réseau. », « L'enregistrement du prix de « Pils » a échoué. ».

### Mes frais

Un frais (eau, électricité, embouteillage) compte dans chaque coût : « Nom » (60 caractères),
« Montant (€) » (0 à 10 000), « Base » (« Par brassin », « Par bouteille », sans choix par
défaut : « Choisissez une base. »). Aucun frais ni montant n'est préinstallé. 20 frais au plus :
au-delà, « Ajouter un frais » laisse la place à « 20 frais au plus. Supprimez-en un pour en
ajouter un autre. ». « Nouveau frais », « Modifier le frais », mêmes boutons et même protection
que le formulaire de prix. Annonces : « Frais enregistré. », « Frais enregistré sur l'appareil.
Il partira au retour du réseau. », « Frais « Capsules » supprimé. » avec « Annuler » 10 s.

### Coût

Prix et frais sont ceux du lecteur. Un seul prix manquant affiche la liste des manquants et
aucun montant : ni total, ni par bouteille, ni sous-total. Montants au centime (« 40,84 € ») ;
le total arrondit la somme exacte et peut différer d'un centime de la somme des lignes.

**Recette** (bloc « Coût avec vos prix », entre Calculs et Général, tout lecteur). Recalculé à
chaque affichage, jamais enregistré, avec les prix de celui qui lit, auteur ou non. « Total »,
« Par litre », « Bouteille de 33 cl », puis l'hypothèse « Pour 20 L · environ 61 bouteilles de
33 cl » (volume en fermenteur ; une recette n'a pas de nombre de bouteilles). « Détail du coût »
(replié, « 14 lignes ») : « Pils · 5 kg · 9,50 € », « S-04 · 1 sachet · 3,99 € », « Électricité
· par brassin · 2,00 € », « Capsules · par bouteille · 3,03 € ». Deux lignes du même ingrédient
sont regroupées ; une levure compte pour un sachet. Sans frais : « Aucun frais compté (eau,
électricité, embouteillage). » et « Ajouter mes frais », qui ouvre « Mes prix ».

Manquants : « Coût indisponible : 3 prix manquants. » (annoncé aux lecteurs d'écran), puis une
ligne par raison : « Pils · 5 kg » et « Saisir le prix » ; « Pils : unité du prix
incompatible. » ou « Pils : prix illisible. » et « Corriger le prix » ; « Volume en fermenteur
non renseigné. » (et « Compléter la recette » pour l'auteur) ; « Une ligne de cette recette n'a
pas de nom utilisable. » ; « Un de vos frais est illisible : il ne peut pas être compté. » et
« Ouvrir Mes prix ». « Saisir le prix » ouvre le formulaire de prix sans quitter la recette, pour
tout lecteur ; à l'enregistrement, la ligne sort de la liste et le focus revient sur l'en-tête ;
au dernier prix, le montant apparaît. Autres états : « Chargement de vos prix », « Impossible de
lire vos prix. » et « Réessayer », « Prix indisponibles sur cet appareil hors ligne. » (jamais
« manquant »), « Aucun ingrédient. » (jamais « 0,00 € »), « Calcul du coût impossible. » dans un
cadre d'erreur.

**Brassin** (bloc « Coût », propriétaire seul). Tant que rien n'est figé : « Coût estimé avec
vos prix actuels », calculé sur la copie figée de la recette et le sucre de resucrage, « Total »,
« Par bouteille (50 bouteilles) » ou « Bouteille de 33 cl », « Par litre », l'hypothèse « Pour
20 L · 50 bouteilles » ou « Pour 20 L · environ 61 bouteilles de 33 cl, nombre de bouteilles non
renseigné », le détail. Ouvrir la fiche n'écrit rien.

En conditionnement, Terminé et Abandonné, sans coût figé : « Coût non figé », l'estimation ou ses
raisons, recalculées à l'affichage (manquants et « Saisir le prix » ; « Nature du sucre de
resucrage non renseignée. » et « Modifier l'embouteillage » ; « Nombre de bouteilles non
renseigné : les frais par bouteille ne peuvent pas être comptés. » et « Renseigner les
bouteilles », ces deux actions en En conditionnement et Terminé ; « Prix indisponibles sur cet
appareil hors ligne. » ; « Calcul du coût impossible. »). « Figer le coût » est désactivé tant
qu'une raison bloque, suivi de « Complétez les éléments ci-dessus pour figer le coût. ». Seul
le nombre de bouteilles manque avec un frais par bouteille : « Figer sans les frais par
bouteille ? » / « Aucun nombre de bouteilles n'est renseigné : les frais par bouteille ne
seront pas comptés. », boutons « Annuler », « Renseigner les bouteilles » (En conditionnement ou
Terminé) et « Figer ». Annonces : « Coût figé. », « Coût figé sur l'appareil. Il partira au
retour du réseau. », « Coût non figé : l'enregistrement a été refusé. ». Rien ne se fige à
l'ouverture d'une fiche ni à la saisie d'un prix.

Coût figé : « Coût figé le 12 nov. 2026 » (« En attente du réseau » tant qu'il attend), « Total »,
« Par bouteille (50 bouteilles) », « Par litre (17 L) » (volume conditionné seul), le détail
figé (« Capsules · 50 bouteilles · 2,50 € »). Sans nombre de bouteilles : « Aucun frais par
bouteille compté. ». Le montant ne change plus quand un prix change ou disparaît. Un
embouteillage modifié depuis le figeage (bouteilles, volume, sucre de resucrage ou sa nature ;
la date seule ne compte pas) affiche, sous le montant, « L'embouteillage a changé depuis le
figeage : Bouteilles 50 → 52. ». « Recalculer avec mes prix actuels » (bouton encadré dans cet
avertissement, bouton texte sinon ; désactivé et suivi des raisons quand une raison l'empêche)
demande « Remplacer le coût figé ? » / « 40,84 € du 12 nov. 2026 deviendra 42,10 €. Les prix
actuels remplacent ceux du figeage. », bouton « Remplacer ». Quand seul le nombre de bouteilles
manque avec un frais par bouteille, le recalcul se fait sans ces frais : le dialogue ajoute
« Aucun nombre de bouteilles n'est renseigné : les frais par bouteille ne seront pas
comptés. » et le bouton « Renseigner les bouteilles » (En conditionnement ou Terminé). Le coût est remplacé en entier,
sans historique. Annonces : « Coût recalculé. », « Coût recalculé sur l'appareil. Il partira au
retour du réseau. », « Coût non recalculé : l'enregistrement a été refusé. ». Un coût figé
illisible affiche « Coût figé illisible. » et « Recalculer avec mes prix actuels ». États :
« Chargement du coût », « Impossible de lire le coût. » et « Réessayer ». Aucune annonce ne
contient de montant.

### Calculs affichés

La fiche et l'éditeur affichent cinq tuiles : « Densité initiale », « Densité finale »,
« Degré », « Amertume », « Couleur ». Rien n'est enregistré : tout est recalculé à chaque
affichage, avec l'équipement tel qu'il est au moment de l'affichage. Deux brasseurs voient les
mêmes valeurs.

- Densité initiale : volume en fermenteur, au moins un malt ou sucre, le rendement d'extrait
  de chacun, et le rendement d'empâtage de l'équipement si la recette contient un malt.
- Densité finale : densité initiale et atténuation de la levure. Degré : à partir des deux
  densités, avant refermentation en bouteille.
- Amertume (Tinseth) : volume ; un houblon d'ébullition demande ses acides alpha, sa durée,
  et la densité initiale (densité d'ébullition retenue). Sans houblon d'ébullition,
  l'amertume vaut 0 IBU, même sans densité initiale. Whirlpool et à cru comptent 0 IBU.
- Couleur (Morey) : volume, et couleur de chaque malt et sucre. Elle ne dépend pas de
  l'équipement.

Le degré, le rendement et les écarts mesurés sur un brassin suivent les mêmes règles : ils se
recalculent à l'affichage, et leurs messages d'indisponibilité sont décrits dans « Prévu et
mesuré ».

Un calcul dont une donnée manque affiche « Indisponible » avec une icône (« Dépend de la
densité initiale. » quand seule celle-ci manque). Aucune valeur par défaut ne remplace une
donnée absente. La liste « À compléter » nomme chaque donnée manquante :

- « Aucun équipement choisi. », « L'équipement de cette recette n'existe plus. »,
  « Équipement indisponible hors ligne. », « Rendement d'empâtage non renseigné dans
  « {équipement} ». »
- « Volume en fermenteur non renseigné. », « Aucun malt ni sucre. »
- « Rendement d'extrait non renseigné : {noms}. », « Couleur non renseignée : {noms}. »
- « Acides alpha non renseignés : {noms}. », « Durée non renseignée : {noms}. »
- « Aucune levure. », « Atténuation non renseignée : {nom}. »

Pour l'auteur, « Compléter la recette » ouvre l'éditeur. Sous les tuiles, une ligne
d'hypothèses : « Pour 20 L · Grainfather (72 %) · US-05 78 % ». « Détail des calculs »
(repliable) donne la densité d'ébullition retenue, l'amertume de chaque houblon et les
méthodes. Une valeur que le calcul refuse (densité initiale au-delà de 1200, par exemple)
affiche « Calcul impossible : {champ} hors des limites. » ; l'erreur est rapportée.

### Hors ligne (recettes et équipements)

- Sur l'APK sans réseau, supprimer ferme l'écran sans attendre le serveur. Créer,
  modifier et dupliquer attendent d'abord le nom du compte porté par le jeton, 3 s au plus
  (le bouton affiche « Enregistrement » ou « Duplication »), puis ferment l'écran sans
  attendre le serveur ; au-delà de 3 s, l'enregistrement part sans nom d'auteur ; le changement est visible aussitôt, et la ligne porte « En attente du réseau »
  jusqu'à la réponse du serveur. La mention disparaît au retour du réseau.
- Si le serveur refuse, l'écran affiche « L'enregistrement de « {nom} » a échoué. » (ou « La
  suppression de « {nom} » a échoué. ») et l'erreur est rapportée. Les formulaires vérifient
  les mêmes bornes que les règles pour que ce cas reste rare.
- Les calculs marchent hors ligne. Un équipement absent du cache s'affiche « Équipement
  indisponible hors ligne », jamais « supprimé ».
- Sur le web, seul un onglet déjà ouvert continue de marcher sans réseau.
- Deux appareils qui modifient la même recette : le dernier enregistrement l'emporte.

### Configuration absente

Une version compilée sans configuration Firebase affiche « Configuration Firebase absente »
et la liste des clés manquantes, au lieu de démarrer.
