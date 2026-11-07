# Exigences fonctionnelles

État actuel du produit. L'historique vit dans `CHANGELOG.md`.

## Rôles et droits

Un compte n'ouvre l'application que si l'administrateur l'a invité : un document
`members/{e-mail}` existe pour l'adresse de son compte Google. Aucun e-mail n'est envoyé à
l'invitation.

| Rôle | Peut |
|---|---|
| `brewer` (Brasseur) | se connecter ; ouvrir Recettes, Brassins et Équipements ; lire toutes les recettes et tous les équipements du groupe ; créer des recettes et des équipements, modifier et supprimer les siens ; dupliquer toute recette à son nom ; voir son nom, son e-mail et la version dans le menu du compte ; se déconnecter |
| `admin` (Administrateur) | tout ce que peut un brasseur, avec les mêmes droits sur ses propres recettes et équipements et aucun droit d'écriture sur ceux des autres ; ouvrir Admin ; inviter un compte (adresse, nom facultatif, rôle) ; retirer un brasseur. Il ne peut ni se retirer lui-même, ni retirer un autre administrateur : un administrateur se retire depuis la console Firebase |
| compte non invité | voir l'écran « Compte non invité », copier son adresse, vérifier à nouveau, se déconnecter. Rien d'autre |

Pas de changement de rôle : l'administrateur retire le compte puis le réinvite. Seul
l'administrateur saisit le nom d'un membre. Retirer un compte ne supprime ni ses recettes ni
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
pu être lue) et « Se déconnecter ». Une déconnexion qui échoue affiche « Déconnexion
impossible. Réessayez. ».

Destinations : Recettes, Brassins, Équipements, et Admin pour l'administrateur seul. Sous
600 px, barre de navigation en bas ; de 600 à 839 px, rail de navigation avec libellés ;
à partir de 840 px, rail étendu et contenu centré sur 840 px au plus. Le rail défile quand
ses destinations dépassent la hauteur (écran bas, grand texte).

Brassins ne contient encore qu'un message : « Les brassins arriveront dans une prochaine
version. ». Recettes et Équipements sont décrits ci-dessous.

Une page de second niveau (fiche d'une recette, d'un équipement, Admin › Membres) porte son
titre (« Recette », « Équipement », « Membres ») et un bouton retour vers sa liste. Les
éditeurs s'ouvrent en plein écran, hors de la barre de navigation, avec « Fermer » (✕), leur
titre, « Enregistrer », et le bandeau hors ligne quand l'appareil n'a pas de réseau.

**Hors ligne.** Quand l'appareil n'a plus de réseau, un bandeau « Hors ligne. Les
modifications partiront au retour du réseau. » s'affiche sous la barre du haut, en pleine
largeur, et il est annoncé aux lecteurs d'écran.

**Page introuvable.** Une adresse inconnue affiche « Cette page n'existe pas. » et le bouton
« Revenir à l'accueil ».

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
  « Impossible de lire les recettes. ». Un document illisible s'affiche « Recette
  illisible ».

**Fiche.** Nom, style, « Recette de {auteur} » pour un autre brasseur. Boutons « Modifier »
et « Supprimer » pour l'auteur, « Dupliquer » pour tous. Puis le bloc Calculs (voir
« Calculs affichés »), et les sections Général (volume en fermenteur, durée d'ébullition,
équipement), Malts et sucres, Houblons (avec l'IBU apporté par chacun), Autres ajouts,
Levure, Paliers d'empâtage, Notes. Chaque ligne d'ingrédient tient sur deux niveaux : nom,
puis ses valeurs.

- Recette absente d'une réponse du serveur : « Cette recette n'existe pas ou a été
  supprimée. » et « Revenir aux recettes ». Absente du cache hors ligne : « Recette
  indisponible hors ligne. ».

**Dupliquer.** Crée « Copie de {nom} » (coupé à 120 caractères) au nom de celui qui
duplique, avec les mêmes ingrédients, paliers et équipement, sans fiche d'origine. La source
ne change pas. Possible sur toute recette, y compris celle d'un membre retiré. Message
« Recette dupliquée. » (hors ligne : « Recette dupliquée sur l'appareil. Elle partira au
retour du réseau. »), puis la fiche de la copie. Pendant la lecture du nom du compte, le
bouton affiche « Duplication » et ne répond pas : un double appui ne crée qu'une copie.

**Supprimer** (auteur). « Supprimer « {nom} » ? » / « La recette disparaît pour tout le
groupe. », boutons « Annuler » et « Supprimer ». Puis « Recette supprimée. ».

**Éditeur** (« Nouvelle recette » / « Modifier la recette », plein écran). Sections toujours
ouvertes, avec des puces de saut en haut (« Malts et sucres (7) », « Houblons (3) »…).

- Général : « Nom » (seul champ obligatoire, 120 caractères ; sinon « Donnez un nom à la
  recette. », l'écran remonte au champ et y place le curseur), « Style (facultatif) », « Volume en fermenteur
  (L) » (plus de 0), « Durée d'ébullition (min) » (0 à 600), « Équipement » (« Aucun
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
  Whirlpool, À cru), durée (« Durée d'ébullition (min) », obligatoire à l'ébullition ;
  « Durée (min) » au whirlpool ; « Durée à cru (jours) »), « Forme » (Pellets, Cônes, sans
  choix par défaut ; sinon « Choisissez une forme. »).
- Autre ajout : « Nom », « Quantité (g) », « Utilisation » (facultative : Empâtage,
  Ébullition, Après ébullition, Fermentation, Embouteillage), « Durée (min) ». Aucun calcul.
- Levure : « Nom », « Atténuation (%) », « Forme » (Sèche, Liquide, facultative).
- Palier : « Nom », « Température (°C) » (0 à 100), « Durée (min) » (0 à 600).
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
« Entre 0 et 100. », « Nombre trop grand. » (à partir de 1 000 000 000, la borne des règles).
L'unité figure dans le libellé du champ (« Quantité (kg) »). À l'enregistrement, un champ en
erreur bloque l'enregistrement même hors de l'écran : l'éditeur défile jusqu'au premier champ
en erreur ; un nom manquant reçoit le curseur. Passer un houblon à « À cru », ou l'en sortir,
vide sa durée : des minutes ne deviennent pas des jours. Un nom d'ingrédient sans lettre ni chiffre est refusé :
« Le nom doit contenir une lettre ou un chiffre. ». Aucun champ de prix ni de stock.

**Affichage.** Virgule décimale, espace insécable avant l'unité : densité « 1057,9 », degré
« 6,6 % vol », « 32 IBU », « 18 EBC » (entiers), malts et sucres en kilogrammes (« 4,5 kg »),
houblons et ajouts en grammes (« 22,4 g »), « 20 L », « 67 °C », « 60 min », houblon à cru
« 3 jours » (« 1,5 jour » au singulier sous 2). Les tuiles des calculs s'élargissent avec la
taille du texte : à 200 %, elles passent sur une colonne plutôt que de couper « 1057,9 ».

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
