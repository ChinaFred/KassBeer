# Exigences fonctionnelles

État actuel du produit. L'historique vit dans `CHANGELOG.md`.

## Rôles et droits

Un compte n'ouvre l'application que si l'administrateur l'a invité : un document
`members/{e-mail}` existe pour l'adresse de son compte Google. Aucun e-mail n'est envoyé à
l'invitation.

| Rôle | Peut |
|---|---|
| `brewer` (Brasseur) | se connecter ; ouvrir Recettes, Bibliothèque, Brassins et Équipements ; consulter les styles, les ingrédients et les recettes publiques de la Bibliothèque, et dupliquer une recette publique à son nom ; ouvrir « Sources des données » ; lire toutes les recettes et tous les équipements du groupe ; créer des recettes et des équipements, modifier et supprimer les siens ; dupliquer toute recette à son nom ; importer à son seul nom les recettes d'un fichier BeerXML ou BeerJSON (500 recettes et 10 Mo par fichier) ; exporter en BeerJSON ou en BeerXML toute recette lisible (BeerXML : style de la Bibliothèque) ; créer un brassin depuis toute recette ; lire les brassins du groupe, leurs étapes, leurs mesures, leurs relevés et leur embouteillage ; suivre le jour de brassage, noter les relevés de fermentation, embouteiller, changer le statut et modifier ses seuls brassins ; saisir ses prix d'achat et ses frais (« Mes prix ») ; lire les modèles de processus du groupe (« Mes processus »), en créer, modifier, dupliquer et supprimer les siens, copier à son nom celui d'un autre membre, choisir le sien proposé par défaut dans « Nouveau brassin » (choix lu par lui seul) ; lire le coût de toute recette avec ses propres prix ; lire, figer et recalculer le coût de ses seuls brassins ; voir son nom, son e-mail et la version dans le menu du compte ; ouvrir « Nouveautés » depuis ce menu ; choisir le thème de l'application sur son appareil (« Préférences ») ; signaler un bug ou proposer une évolution (« Signaler ou proposer »), lire ses seuls tickets, leur statut et la réponse de l'administrateur (« Mes tickets ») ; se déconnecter |
| `admin` (Administrateur) | tout ce que peut un brasseur, avec les mêmes droits sur ses propres recettes, équipements, processus et brassins et aucun droit d'écriture sur ceux des autres ; ouvrir Admin ; inviter un compte (adresse, nom facultatif, rôle) ; retirer un brasseur ; lire tous les tickets des membres, leur auteur et leurs décisions dans Admin › Tickets des membres, avec l'état du jeton GitHub et les tickets bloqués ; valider, refuser ou clore un ticket parmi les décisions que le serveur permet ; lire les analyses d'un ticket relevées sur son Issue et y répondre (« Répondre », quand le serveur le permet) ; relancer l'envoi d'un ticket bloqué et reprendre une décision en échec ; ouvrir « Tickets à traiter » depuis le menu du compte ; importer les fiches Excel préparées (Admin › Import), sous son propre compte, coûts figés compris ; lire les rapports d'erreur des membres (Admin › Rapports d'erreur), sans les supprimer ; lire les journaux des fonctions du serveur (Admin › Journaux), adresses e-mail comprises. Il ne lit ni les prix, ni les frais, ni les coûts d'un autre membre. Il ne peut ni se retirer lui-même, ni retirer un autre administrateur : un administrateur se retire depuis la console Firebase |
| compte non invité | voir l'écran « Compte non invité », copier son adresse, vérifier à nouveau, se déconnecter. Rien d'autre |

Pas de changement de rôle : l'administrateur retire le compte puis le réinvite. Seul
l'administrateur saisit le nom d'un membre. Les prix, les frais et les coûts figés d'un
membre ne sont lus que par lui, administrateur compris ; ceux d'un membre retiré restent en
base et plus personne ne les lit. Retirer un compte ne supprime ni ses recettes ni
ses brassins, qui restent visibles du groupe. Les recettes, équipements et processus d'un
membre retiré restent lisibles, ne sont plus modifiables par personne dans l'application, et
peuvent être dupliqués ou copiés.

L'auteur d'une recette, d'un équipement ou d'un processus s'affiche « Vous » pour soi, sinon par le nom de
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
pu être lue), un séparateur, « Mes prix », « Mes processus », « Préférences », un séparateur, « Signaler ou proposer », « Mes
tickets », « Tickets à traiter » (administrateur seul), « Nouveautés », « Sources des données », un séparateur et « Se
déconnecter ». Une déconnexion qui échoue
affiche « Déconnexion impossible. Réessayez. ».

Une pastille chiffrée sur l'avatar et sur « Mes tickets » compte les tickets dont le suivi est
à lire (« 99+ » au-delà de 99) ; elle est lue « Mon compte, 2 suivis de ticket à lire » et
« Mes tickets, 2 à lire ». Sans suivi à lire, rien ne change. Voir « Tickets ».

Pour l'administrateur, « Tickets à traiter » ouvre Admin › Tickets des membres. Sa pastille
compte les tickets reçus ou analysés sans décision et ceux dont l'envoi est impossible, rien à 0 ; elle est
lue « Tickets à traiter, 3 ». La pastille de l'avatar additionne les suivis à lire et les
tickets à traiter, et l'avatar est lu « Mon compte, 1 suivi de ticket à lire, 3 tickets à
traiter ».

Destinations : Recettes, Bibliothèque, Brassins, Équipements, et Admin pour l'administrateur seul. Sous
600 px, barre de navigation en bas ; de 600 à 839 px, rail de navigation avec libellés ;
à partir de 840 px, rail étendu et contenu centré sur 840 px au plus (sauf Admin › Tickets des
membres, en liste et fiche côte à côte). Le rail défile quand
ses destinations dépassent la hauteur (écran bas, grand texte). Dans le rail avec libellés, un
libellé plus large que 160 px est réduit pour tenir sur une ligne.

Recettes, Équipements et Brassins sont décrits ci-dessous. Au lancement, si le compte a un seul
brassin en cours depuis moins de 24 h, l'écran du jour se rouvre avec le message « Brassage
repris. Les minuteurs comptent le temps écoulé. ».

Une page de second niveau (fiche d'une recette, d'un équipement, d'une entrée de la
Bibliothèque, Admin › Membres) porte son titre (« Recette », « Équipement », « Houblon »,
« Recette publique », « Membres ») et un bouton retour vers sa liste. Les
éditeurs s'ouvrent en plein écran, hors de la barre de navigation, avec « Fermer » (✕), leur
titre, « Enregistrer », et le bandeau hors ligne quand l'appareil n'a pas de réseau.

**Hors ligne.** Quand l'appareil n'a plus de réseau, un bandeau « Hors ligne. Les
modifications partiront au retour du réseau. » s'affiche sous la barre du haut, en pleine
largeur, et il est annoncé aux lecteurs d'écran.

**Page introuvable.** Une adresse inconnue affiche « Cette page n'existe pas. » et le bouton
« Revenir à l'accueil ».

### Préférences

Ouverte depuis le menu du compte, pour tout membre (adresse `/preferences`). Page pleine, hors
de la barre de navigation : titre « Préférences » et flèche retour. La flèche revient à l'écran
d'où le membre est parti ; ouverte par son adresse, elle mène à l'accueil. Colonne de 840 px au
plus.

- Section « Apparence » (lue comme en-tête), une carte de trois choix :
  - « Comme l'appareil », « Suit le mode clair ou sombre du téléphone ou du navigateur. » ;
  - « Clair » ;
  - « Sombre ».
- Sous la carte : « Ce choix vaut pour cet appareil seulement. ».
- Par défaut, et quand rien n'a été enregistré : « Comme l'appareil ».
- Un choix change le thème de toute l'application aussitôt et s'enregistre sur l'appareil,
  sans bouton. Il vaut pour tous les comptes de cet appareil ou de ce navigateur, et se perd à
  la désinstallation ou au nettoyage du navigateur. Rien n'est écrit dans Firestore.
- Enregistrement en échec : le thème choisi reste jusqu'à la fermeture de l'application, et
  le message « Thème non enregistré : l'ancien thème reviendra au prochain démarrage. » s'affiche ; la panne
  est journalisée. Si un autre choix a suivi entre-temps, seul l'échec de ce dernier choix
  s'annonce ; l'échec du précédent est seulement journalisé.
- Au démarrage, le thème enregistré s'applique dès le premier écran, écran de connexion
  compris. Lecture impossible ou valeur inconnue : « Comme l'appareil », sans message ; la
  panne est journalisée.
- L'écran de lancement d'Android et le fond de la page web avant le chargement suivent le
  thème du téléphone ou du navigateur. « Configuration Firebase absente » et « Kass'Beer n'a
  pas pu démarrer » aussi.
- Marche sans réseau.

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

### Tickets

Un membre signale un bug ou propose une évolution depuis l'application, sans compte GitHub
(ADR-006). Le ticket devient une Issue publique du dépôt ; l'administrateur la traite, et le
membre suit son statut dans « Mes tickets ». Aucun accès depuis l'écran du jour de brassage.
Trois pages pleines, hors de la barre de navigation, ouvertes depuis le menu du compte. Leur
flèche retour revient à l'écran précédent ; ouvertes par leur adresse, elle mène à « Mes
tickets » ou à l'accueil.

**Signaler ou proposer** (`/tickets/nouveau`). Cadre d'éditeur plein écran : « Fermer » (✕),
titre, bouton « Envoyer » (« Envoi » pendant l'action), colonne de 840 px au plus.

- Encadré toujours visible : « Publié sur un site public : n'écrivez ni nom ni adresse. » /
  « Le titre et la description seront lisibles par tous sur GitHub. Votre nom et votre adresse
  e-mail ne sont jamais publiés. »
- « Type » : « Bug » (« Quelque chose ne marche pas »), « Évolution » (« Améliorer ce qui
  existe »), « Nouvelle fonctionnalité » (« Pouvoir faire quelque chose de nouveau »). Aucun
  type présélectionné.
- « Titre », une ligne, 5 à 100 caractères, avec compteur.
- Plan de description propre au type, en texte fixe au-dessus de la description (bug : « Ce
  que vous faisiez : … / Ce qui s'est passé : … / Ce que vous attendiez : … »).
- « Description », 10 à 2 000 caractères, avec compteur.
- « Écran concerné » : liste préremplie par l'écran d'où le membre a ouvert le menu (« Recette »,
  « Équipements »…), modifiable, terminée par « Autre écran » et « Je ne sais pas ». Ouvert
  depuis « Mes tickets » ou par son adresse : « Je ne sais pas ». Les écrans d'Admin n'y
  figurent que pour l'administrateur. Seul le nom de l'écran part, jamais l'identifiant de la
  recette ou du brassin.
- « Élément précis », sous « Écran concerné », quand l'écran choisi a des menus ou des
  fenêtres : « L'écran entier » par défaut, puis ses éléments (« Menu du compte », « Barre de
  navigation » sur les écrans à barre de navigation, listes et fiches de la Bibliothèque
  comprises ; « Embouteillage », « Relevé de
  fermentation », « Coût du brassin »… sur la fiche d'un brassin ; « Malt ou sucre »,
  « Houblon »… dans l'éditeur de recette ; « Journée », « Étape », « Actions d'une journée »,
  « Insérer un bloc de la recette » dans l'éditeur de processus ; « Plus d'actions » sur la
  fiche d'un processus). Le formulaire de prix porte le même nom, « Prix d'un
  ingrédient », sur « Mes prix », la fiche d'une recette et celle d'un brassin, et sa liste
  « Reprendre un prix » aussi ; « Coût du brassin » désigne les deux confirmations « Figer le
  coût » et « Recalculer avec mes prix actuels ». Aide : « Menu ou fenêtre concerné. »
Jamais prérempli ; changer d'écran le remet à « L'écran entier » ; absent pour
  « Autre écran » et « Je ne sais pas ». Les éléments d'Admin ne figurent que pour
  l'administrateur. Le suivi affiche « Brassin › Embouteillage ». Les confirmations (« Supprimer
  ? », « Abandonner les modifications ? ») et les sélecteurs de date et d'heure n'y figurent pas.
  « Sources des données », sans menu ni fenêtre, n'a pas de champ « Élément précis ».
- Ligne grise : « Envoyé avec : version 0.2.0, Android » (ou « web », « version
  indisponible »).
- Erreurs à l'appui sur « Envoyer », le premier champ en erreur reçoit le focus : « Choisissez
  le type de ticket. », « Le titre doit faire au moins 5 caractères. », « Décrivez le bug ou
  l'idée en 10 caractères au moins. ».
- Envoi : le ticket s'écrit sur l'appareil, le formulaire se ferme sans attendre le serveur,
  et l'écran d'origine affiche « Ticket enregistré. Suivez-le dans Mes tickets. » (hors ligne :
  « Ticket enregistré. Il partira au retour du réseau. ») avec « Voir ». Un double appui
  n'écrit qu'un ticket. Un refus du serveur affiche « Votre ticket a été refusé. Il n'est pas
  enregistré. » avec « Reprendre », qui rouvre le formulaire avec le texte envoyé.
- Quitter avec une saisie demande « Abandonner les modifications ? » / « Le texte saisi sera
  perdu. ». Un ticket envoyé ne se modifie ni ne s'annule.

**Mes tickets** (`/tickets`). Tickets du membre, le plus récent en tête (un ticket encore sur
l'appareil d'abord). Dans une fenêtre de 840 px ou plus, la liste fait 380 px à gauche et le
suivi du ticket choisi s'affiche à droite (adresse `/tickets/:id`) ; sans choix : « Choisissez
un ticket pour voir son suivi. ». Choisir un ticket ne fait ni transition ni retour en haut de la
liste, et la flèche retour ramène toujours à l'écran d'où « Mes tickets » a été ouvert. La ligne
choisie prend le fond secondaire du thème. Le suivi garde une marge basse pour le bouton
flottant. En dessous de 840 px, le suivi s'ouvre seul par-dessus la liste. Chaque ligne : icône du type, titre, date « jj/mm/aa », étiquette du
statut (icône et texte), et à droite un point lu « Nouveau suivi à lire » quand le statut ou la
réponse a changé depuis la dernière ouverture du ticket. Bouton flottant « Signaler ou
proposer », absent de l'état vide, qui porte déjà ce bouton. Chargement « Chargement de vos tickets » ; aucun ticket : « Aucun ticket pour
l'instant. Un bug, une idée ? Envoyez-les à l'administrateur. » et « Signaler ou proposer » ;
panne : « Impossible de lire vos tickets. » et « Réessayer » ; panne après une première
lecture : la liste reste, sous « Mise à jour de la liste impossible. Elle peut ne plus être à
jour. ». Hors ligne : bandeau hors ligne et liste du cache. Un ticket illisible s'affiche
« Ticket illisible » / « Mettez l'application à jour, ou prévenez l'administrateur. ».

**Suivi d'un ticket** (`/tickets/:id`). Type, titre, étiquette du statut, « Envoyé le jj/mm/aa à
hh:mm », phrase du statut, encadré du texte de l'administrateur quand il a répondu (titré
« Motif du refus » pour un ticket refusé, « Commentaire de clôture » pour un ticket clos,
« Réponse de l'administrateur » sinon), frise des étapes (voir ci-dessous), description, « Écran : Recette », « Envoyé avec : … ». Le texte est sélectionnable. Ouvrir un
ticket dont le suivi est à lire éteint la pastille, hors ligne compris. États : « Chargement du
ticket », « Impossible de lire vos tickets. », « Ce ticket n'existe plus. », « Ce ticket n'est
pas disponible hors ligne. », « Ce ticket est illisible. », avec « Retour à mes tickets ».

| Statut | Étiquette | Phrase |
|---|---|---|
| sur l'appareil seul | En attente du réseau | « Votre ticket est enregistré sur cet appareil. Il partira au retour du réseau. » |
| en attente de transmission | Envoi en cours | « Votre ticket est enregistré. Il sera transmis à l'administrateur dans quelques minutes. », puis au-delà d'une heure « La transmission prend du retard. » |
| reçu | Reçu | « L'administrateur a reçu votre ticket. » |
| analysé | Analysé | « Votre ticket a été lu et étudié. » |
| validé | Validé | « Votre demande sera traitée. » |
| en cours | En cours | « Le travail a commencé. » |
| livré | Livré | « C'est fait. Livré dans la version X.Y.Z. » (sans version : « C'est fait. ») ; étiquette « Disponible après mise à jour » si la version installée est plus ancienne, sinon « Disponible dans votre version » ; bouton « Voir la modification sur GitHub » quand la modification est connue |
| refusé | Refusé | « Cette demande ne sera pas traitée. » |
| clos | Clos | « Ce ticket est clos. » |
| envoi impossible | Envoi impossible (ton d'erreur) | « Votre ticket n'a pas pu être transmis. Il reste enregistré dans l'application. L'administrateur est prévenu. » |
| limite du jour | Limite du jour atteinte (ton d'erreur) | « Ce ticket n'a pas été transmis : la limite de tickets du jour était atteinte. Reprenez-le demain avec le bouton ci-dessous. » et bouton « Reprendre ce ticket », qui ouvre le formulaire prérempli pour un nouveau ticket |
| inconnu de cette version | Statut inconnu | « Mettez l'application à jour pour lire ce statut. » |

Étiquettes : icône et texte, sur un fond du thème. Gris neutre pour « Envoi en cours », « En
attente du réseau », « Refusé », « Statut inconnu » ; couleur primaire pour « Reçu », « Analysé »,
« Validé », « Livré » ; tertiaire pour « En cours » ; secondaire pour « Clos » ; ton d'erreur pour « Envoi
impossible » et « Limite du jour atteinte ». Elles ne clignotent pas côté membre.

**Frise.** Sous la phrase du statut, les boutons et l'encadré, avant « Description », une frise
verticale montre les étapes du ticket : coche pour une étape passée, icône du statut en gras
pour l'étape actuelle, cercle vide pour une étape à venir. Chaque étape est lue d'un bloc
(« Reçu : étape passée », « Validé : étape actuelle », « Livré : à venir ») ; le texte passe à
la ligne à 200 %.

| Statut | Étapes |
|---|---|
| en attente, reçu, analysé, validé, en cours, livré | Envoi en cours → Reçu → Analysé → Validé → En cours → Livré |
| sur l'appareil seul | En attente du réseau → Reçu → Analysé → Validé → En cours → Livré |
| refusé | Envoi en cours → Reçu → Refusé |
| clos | Envoi en cours → Reçu → Clos |
| envoi impossible | Envoi en cours → Envoi impossible (icône en ton d'erreur) |
| limite du jour | Envoi en cours → Limite du jour atteinte (icône en ton d'erreur) |
| inconnu de cette version | pas de frise |

« Voir la modification sur GitHub » n'ouvre qu'une adresse `https` sur `github.com`, hors de
l'application. Un échec affiche « Impossible d'ouvrir GitHub. ».

La pastille ne s'allume pas quand le ticket passe de « Envoi en cours » à « Reçu ». Elle
s'allume pour tout autre changement de statut et pour une nouvelle réponse, y compris le
retour d'« Analysé » à « Reçu » après une réponse de l'administrateur (la frise recule alors
d'une étape).

### Admin

Réservé à l'administrateur. Cinq entrées : « Membres » (« Inviter et retirer les comptes »),
« Tickets des membres » (« Bugs et idées des membres, et leur suivi sur GitHub », avec une
pastille en ton d'erreur qui compte les alertes en ton d'erreur du bandeau des tickets et la
panne de lecture des tickets, lue « Tickets des membres, 2 alertes, Bugs et idées des membres,
et leur suivi sur GitHub » ; une échéance de jeton proche ne l'allume pas, un jeton de routine
refusé l'allume), « Import » (« Fiches Excel préparées en JSON »), « Rapports d'erreur »
(« Pannes rencontrées dans l'application par les membres ») et « Journaux » (« Messages des
fonctions du serveur »).

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

### Admin › Import

Réservé à l'administrateur (v0.6). Adresse `/admin/import`, page pleine hors de la coquille,
titre « Importer les fiches Excel », flèche de retour, bandeau hors ligne. Un brasseur qui
ouvre l'adresse est renvoyé à l'accueil. C'est le seul écran d'écriture de masse sur les
données du groupe.

Le fichier est préparé hors de l'application par une session Claude Code à partir des 16
fiches `.xlsx`, puis vérifié par `exchange/bin/verifier_fiches.dart` (format dans
`exigences-techniques.md`, « Admin › Import »). Chaque correction est validée par
l'utilisateur pendant la préparation ; l'application n'en fait aucune.

1. **Choix.** « Choisissez le fichier JSON préparé à partir des fiches Excel. 10 Mo au plus.
   Rien n'est écrit avant votre confirmation. » et « Choisir le fichier » (sélecteur
   d'ADR-007). Hors ligne, « Import impossible hors ligne. Reconnectez-vous pour analyser le
   fichier. » remplace le bouton. Refus : « Ce fichier dépasse 10 Mo. » ; « Ce fichier n'est
   pas un fichier de fiches Kass'Beer. Choisissez le fichier JSON préparé. » (JSON mal formé
   compris) ; « Ce fichier est d'un format que cette version ne lit pas. Faites-le préparer de
   nouveau. » ; « Ce fichier contient plus de 50 fiches. Faites-le préparer de nouveau. » ;
   « Deux fiches de ce fichier portent l'identifiant « {id} ». Faites-le préparer de
   nouveau. ». Fichier sans fiche : « Ce fichier ne contient aucune fiche. ».
2. **Analyse, sans écriture.** « Lecture du fichier », puis « Comparaison avec les données
   déjà enregistrées » : index de la Bibliothèque et documents aux identifiants du fichier,
   lus sur le serveur. Panne : « Impossible de vérifier ce qui est déjà importé. Vérifiez la
   connexion. » et « Réessayer », sans redemander le fichier.
3. **Relecture.** « Choisir un autre fichier », puis « 16 fiches · 15 recettes · 16 brassins
   · 490 heures et mesures · 8 coûts figés » et les comptes par état sans les zéros (« 14
   nouvelles · 1 à compléter · 1 refusée »). Une ligne par fiche : case, « Ale blonde · 14
   juil. 2024 », identifiant de la fiche, étiquette d'état, points à revoir (« 3 divergences
   · 2 heures reprises »), détail dépliable. États : « Nouvelle » et « À compléter » (« Import
   commencé et non terminé : seul ce qui manque sera écrit. »), cochées ; « Déjà importée » ;
   « Déjà importée, contenu différent » (« Le fichier a changé depuis l'import. Pour remplacer
   cette fiche, supprimez son brassin et sa recette, puis importez de nouveau. ») ;
   « Refusée : {raison} », avec le champ en cause (par exemple « montant dans un texte lu
   par le groupe (brew.notes). » : un prix ne va que dans le coût figé). Seules les deux
   premières se cochent. Le lecteur d'écran lit la ligne d'un bloc, explication de l'état
   comprise : « Ale blonde, 14 juillet 2024, à compléter, 3 points à revoir, Import commencé
   et non terminé : seul ce qui manque sera écrit. ». Le détail liste, sans rubrique vide :
   nom en double (« Une de vos recettes s'appelle déjà « Ale blonde ». »), « À compléter dans
   la recette », « Divergences », « Corrections validées », « Valeurs déduites » (dont unités
   converties, durées arrondies, moments et style simplifiés, textes coupés à la lecture de la
   recette), « Reprises de la Bibliothèque », « Heures reprises » (dont « Relevé sans date :
   daté de 28 jours après le brassage. »), « Non importé » (dont parties de la recette non
   importées et valeurs rejetées), « Coût » (« Coût figé : 49,04 € », « Coût non figé : prix
   manquant pour Houblon Saaz. Vous pourrez le figer depuis le brassin. », « Écart avec la
   fiche : … dans la fiche, … recalculé. »). Hors ligne, « Choisir un autre fichier »
   disparaît.
4. **Barre du bas.** « Importer N fiches » ; sans case cochée, « Cochez au moins une
   fiche. » ; quand rien n'est cochable, « Toutes les fiches de ce fichier sont déjà
   importées. Rien à écrire. » à la place du bouton ; hors ligne, « Import impossible hors
   ligne. Reconnectez-vous pour importer les fiches cochées. ». Le second import d'un même
   fichier n'écrit donc rien.
5. **Confirmation.** « Importer 16 fiches ? » / « 16 brassins et 15 recettes seront écrits
   sous votre compte. Ils seront visibles du groupe. Les coûts restent privés. » (une fiche :
   « 1 brassin sera écrit sous votre compte. Il sera visible du groupe. … »), boutons
   « Annuler » et « Importer ». Une recette déjà enregistrée n'entre pas dans le compte.
6. **Écriture.** « Fiche 4 sur 16 · Ale blonde », barre de progression et « 212 écritures sur
   610 », ce dernier texte absent tant que le total n'est pas connu ; annonce au lecteur
   d'écran une fois par fiche. Quitter demande « Arrêter l'import ? » / « La fiche en cours
   sera reprise au prochain import du même fichier. », boutons « Continuer l'import » et
   « Arrêter ». Une écriture sans accusé du serveur en 30 s, ou la perte de la connexion,
   arrête l'import.
7. **Compte rendu.** « Import terminé · 16 créées · 0 ignorées · 0 en erreur », annoncé au
   lecteur d'écran sans montant ; après une perte de connexion ou un accusé absent, le titre
   et l'annonce disent « Import arrêté · 4 créées · 11 ignorées · 1 en erreur », suivis de
   « Connexion perdue. Import arrêté à la fiche 5 sur 16. Reconnectez-vous puis choisissez de
   nouveau le fichier : les fiches commencées seront reprises. ». Sections « Fiches à revoir » (rubriques du détail),
   « Ignorées » (« Non cochée », « Déjà importée », « Refusée : … », « Non traitée : import
   arrêté ») et « En erreur » (« Ale blonde (2024-07-14-ale-blonde) — événements, lot 3 :
   écriture refusée. Relancez l'import du même fichier pour reprendre. »). Une fiche en
   erreur est passée, les suivantes continuent. Boutons « Voir les brassins » et « Revenir
   à l'administration ». Le compte rendu se relit en choisissant de nouveau le fichier.

Ce que l'import crée, sous le compte de l'administrateur : une recette par recette
distincte du fichier (deux fiches de mêmes matières et même chronologie en partagent une),
sans équipement ; un brassin « Terminé » par fiche, sans date d'embouteillage, avec ses
notes de fiche, une copie d'équipement sans valeurs (« Installation à cuves (fiches
Excel) » ou « Brew in bag (fiches Excel) ») et donc une densité prévue « à compléter » ;
ses heures réelles (débuts d'étape), mesures, relevés de fermentation, nombre de bouteilles,
volume conditionné et nature du sucre de resucrage ; le coût figé de la fiche quand tous
ses prix sont connus (voir « Coût »). Rien n'est écrit dans « Mes prix » ni dans « Mes
frais ». Une recette ou un brassin déjà présent à l'identifiant prévu n'est pas réécrit.


### Admin › Rapports d'erreur

Réservé à l'administrateur (ADR-011, J1). Adresse `/admin/rapports-erreur`, titre « Rapports
d'erreur », retour vers Admin. L'écran lit les pannes que l'application a rapportées sur les
appareils des membres, de la plus récente à la plus ancienne. Lecture seule : aucun rapport
ne se supprime depuis l'écran.

- **En tête** : « N rapports affichés » (« 1 rapport affiché ») et le bouton « Actualiser »,
  qui relit la première page. Tirer la liste vers le bas fait la même chose.
- **Une ligne repliée** : icône de bug en ton d'erreur ; titre = première ligne de l'erreur,
  deux lignes au plus (« Erreur sans message » si elle est vide) ; résumé « date · fonction ·
  v{version} », ce qui manque omis ; étiquette « Android » ou « Web », « Plateforme inconnue »
  en ton neutre si elle manque. L'étiquette est à droite du titre sur une ligne d'au moins
  600 px, sous le résumé sinon (téléphone, texte agrandi).
- **Une ligne dépliée** : sections « Erreur », « Contexte », « Pile d'appels » (en chasse
  fixe) et « Compte » (identifiant du compte, tel quel), chacune absente si elle est vide,
  texte sélectionnable. « Copier le rapport » copie le résumé, la plateforme et les sections,
  puis affiche « Rapport copié. » (« Impossible de copier le rapport. » en cas d'échec).
- **Pages de 50** : « Charger la suite » lit les 50 suivants, « Lecture en cours » pendant la
  lecture. Pendant « Actualiser », l'icône laisse place à un indicateur annoncé « Lecture en
  cours », et « Charger la suite » reste désactivé. Une page de moins de 50 affiche « Fin des rapports. ».
- Chargement : « Chargement des rapports ». Liste vide : « Aucun rapport d'erreur. Une panne
  rencontrée par un membre apparaîtra ici, avec son contexte. »
- Première lecture impossible : « Impossible de lire les rapports d'erreur. » et
  « Réessayer ». Une panne sur la suite ou sur « Actualiser » garde la liste affichée, avec
  au-dessus « Lecture impossible. Les rapports déjà affichés restent visibles. »
  et « Réessayer », qui rejoue la lecture en échec. Sans aucun rapport affiché, une panne
  d'« Actualiser » s'affiche seule : « Impossible de lire les rapports d'erreur. » et
  « Réessayer ». Pendant une nouvelle lecture, la panne affichée reste, avec « Lecture en
  cours », jusqu'à la réponse.
- Hors ligne, avec au moins un rapport lu : la liste lue dans l'appareil s'affiche sous
  « Hors ligne. Rapports lus sur cet appareil : la liste peut être incomplète. » et
  « Réessayer ». Sans aucun rapport dans l'appareil, sans ce bandeau : « Aucun rapport lu sur
  cet appareil. Réessayez avec le réseau. » et « Réessayer ».

### Admin › Journaux

Réservé à l'administrateur (ADR-011, J2). Adresse `/admin/journaux`, titre « Journaux », retour
vers Admin. L'écran cherche dans les messages écrits par les fonctions du serveur (tickets,
lancements, livraisons), du plus récent au plus ancien, 50 à la fois. Lecture seule.

- **Ouverture** : aucune recherche ne part. L'écran affiche les filtres et « Choisissez les
  filtres, puis appuyez sur Rechercher. ».
- **Filtres** : « Gravité » (« Info et plus » par défaut, « Avertissements et plus »,
  « Erreurs », « Débogage seul »), boutons segmentés qui passent en colonne quand ils ne
  tiennent pas ; « Période » (« 1 h » par défaut, « 24 h », « 7 jours ») ; « Fonction »
  (« Toutes les fonctions », puis la liste rendue par le serveur ; avant la première réponse,
  aide « La liste des fonctions arrive avec la première recherche. ») ; « Ticket » (aide
  « Identifiant du ticket ») ; « Texte à chercher » (aide « Mot ou expression contenu dans le
  message »). La touche Entrée d'un champ ne lance rien.
- **Rechercher** : bouton « Rechercher ». Pendant un appel, seul le bouton appuyé
  (« Rechercher », « Réessayer » ou « Charger la suite ») affiche « Recherche en cours » ; les
  autres sont désactivés, sans indicateur. Après une recherche, « N entrées affichées » (« 1 entrée affichée ») est
  annoncé.
- **Filtre changé après une recherche** : la liste reste, avec « Filtres modifiés : appuyez sur
  Rechercher pour mettre la liste à jour. », et « Charger la suite » disparaît.
- **Téléphone** : filtres et liste dans le même défilement. Après une recherche réussie, les
  filtres se replient en une ligne (« Info et plus · 1 h · Toutes les fonctions », suivie du
  ticket et du texte s'ils sont remplis) avec « Modifier les filtres ». **Grand écran** (fenêtre
  d'au moins 840 px) : filtres toujours dépliés, « Gravité » et « Période » sur une ligne,
  « Fonction », « Ticket » et « Texte à chercher » côte à côte, « Rechercher » à droite.
- **Note fixe** sous les filtres : « Les journaux peuvent contenir des adresses e-mail. Ne les
  recopiez pas dans une Issue. » Les adresses ne sont pas masquées (choix de l'utilisateur du
  2026-11-14).
- **Une entrée repliée** : icône et couleur de la gravité (erreur, avertissement, information,
  débogage), lue « Erreur », « Avertissement », « Information » ou « Débogage » ; `CRITICAL`,
  `ALERT` et `EMERGENCY` s'affichent en erreur, `NOTICE` en information, toute autre gravité
  avec une icône de cercle, lue « Gravité inconnue » ; titre = la première ligne du message,
  deux lignes au plus ; sous-titre « date et heure avec les secondes · fonction »
  (« 14 nov. 10:30:05 · synctickets »).
- **Une entrée dépliée** : « Message » (le message entier, en chasse fixe s'il tient sur
  plusieurs lignes, comme une pile d'appels) et « Données » (le reste de l'entrée, en chasse
  fixe), texte sélectionnable ; « Texte coupé à N caractères. » sous « Message » ou sous
  « Données » quand le serveur a coupé ce texte, N étant la longueur gardée que le serveur
  indique (8 000 aujourd'hui). Une entrée
  dépliée le reste quand elle sort de l'écran et y revient ; une nouvelle recherche replie
  tout ; « Copier l'entrée », puis « Entrée copiée. » (« Impossible de copier l'entrée. »
  en cas d'échec).
- **Suite** : « Charger la suite » lit les 50 suivantes ; sans suite, « Fin des journaux pour
  cette période. ».
- Chargement : « Recherche des journaux ». Aucune entrée : « Aucune entrée pour ces filtres.
  Élargissez la période ou videz un champ, puis relancez la recherche. »
- **Pannes**, seules sans liste, en bandeau au-dessus d'une liste déjà affichée : « Quota de
  lecture des journaux atteint, réessayez dans une minute. » ; « Journaux indisponibles pour
  l'instant. » ; « Hors ligne. La recherche des journaux demande le réseau. », chacune avec
  « Réessayer », qui rejoue le dernier appel ; « Page suivante refusée par le serveur. Relancez
  la recherche. » (page demandée trop tard pour sa période, ou illisible), dont « Réessayer »
  relit la première page avec les filtres de la liste (« Recherche en cours » sur le bouton du
  bandeau pendant la relance) ; « Lecture des journaux non autorisée : rôle IAM manquant. »,
  « Journaux non disponibles dans l'émulateur. », « Réservé à l'administrateur. » et
  « Recherche refusée par le serveur. » (autre filtre refusé), sans « Réessayer ». Pendant une nouvelle tentative, la panne reste
  affichée jusqu'à la réponse.
- **Champ refusé** par le serveur (ticket ou texte) : le message rendu par le serveur
  s'affiche sous le champ, qui prend le focus, et une panne affichée auparavant disparaît.
  L'application ne recopie ni la forme d'un identifiant ni la longueur permise du texte.

### Admin › Tickets des membres

Réservé à l'administrateur (ADR-006, T2). Adresse `/admin/tickets`, titre « Tickets des
membres », retour vers Admin ; ouverte par la tuile d'Admin ou par « Tickets à traiter » du
menu du compte.

**Bandeau des tickets.** En tête de la liste et de la fiche, lu par l'administrateur seul,
texte sélectionnable et annoncé, borné au tiers de la hauteur et défilant au-delà. Rien quand
tout va bien. Une ligne par alerte :

- « Jeton GitHub refusé ou expiré depuis le jj/mm/aa : remplacez GITHUB_TICKETS_TOKEN dans
  Secret Manager. » (ton d'erreur) ;
- « Le jeton GitHub expire le jj/mm/aa. » à 14 jours ou moins de l'échéance, « Le jeton
  GitHub a expiré le jj/mm/aa. » (ton d'erreur) une fois l'échéance passée ; sans échéance
  (jeton sans expiration), rien sur l'expiration ;
- « N tickets ne sont pas arrivés sur GitHub. » : envoi impossible, ou en attente de
  transmission depuis plus d'une heure ;
- « N tickets dont l'Issue a disparu. » ;
- « Jeton de la routine d'analyse refusé depuis le jj/mm/aa. Remplacez-le dans Secret
  Manager. » et « Jeton de la routine de développement refusé depuis le jj/mm/aa. Remplacez-le
  dans Secret Manager. » (ton d'erreur), lus dans l'état des lancements (ADR-008, T4) ;
- « État du jeton GitHub illisible. » pour un document illisible, journalisé ; « Impossible de
  lire l'état du jeton GitHub. » quand la lecture échoue ; de même « État des lancements
  illisible. » et « Impossible de lire l'état des lancements. ». Le plafond des lancements
  atteint n'y figure pas : c'est un état normal. Une panne de lecture des tickets
  n'y est pas répétée : la liste ou la fiche affiche déjà « Impossible de lire les tickets. ».

**Disposition.** Dans une fenêtre de 1 096 px ou plus (840 px de contenu à côté du rail
étendu), la liste fait 360 px à gauche et la fiche du ticket choisi s'affiche à droite, sous un bandeau
commun ; sans choix : « Choisissez un ticket pour voir son suivi. ». Appuyer sur un ticket
change l'adresse (`/admin/tickets/:id`) sans transition : seule la fiche change, la liste garde
son défilement, la barre du haut garde « Tickets des membres » et son retour mène à Admin.
La ligne choisie prend le fond secondaire du thème, texte et icône accordés, comme dans Mes
tickets. En dessous, la liste occupe l'écran et la fiche s'ouvre seule par-dessus (titre
« Ticket d'un membre », retour vers la liste).

**Compteur des lancements.** Au-dessus des filtres, en texte secondaire : « Lancements de
sessions : 2 sur 10 le 13/11 · 3 en novembre 2026 ». Le jour, le mois et le plafond sont ceux écrits
par le serveur : l'application ne recalcule pas le jour de Paris et n'a aucun plafond en dur.
Sans compteur : « Lancements de sessions : aucun compté. » ; lecture : « … : lecture en
cours. » ; hors ligne, absent du cache : « … : compteur non disponible hors ligne. » ;
illisible : « … : compteur illisible. » ; panne : « Lancements de sessions : compteur
indisponible. » en ton d'erreur, avec un bouton icône « Réessayer ».

**Liste.** Filtres « À traiter (N) » (tickets reçus ou analysés sans décision, envois
impossibles, et tickets En cours dont la pull request est prête à livrer, sauf pendant une
livraison ou une correction de ce ticket et tant que GitHub refuse au jeton la lecture de la CI ; un ticket validé n'y est pas ; le compteur « Tickets à traiter » du menu ne compte que les statuts),
« Tous » et « Bloqués (N) » (envoi impossible, en attente depuis plus d'une heure, Issue
disparue) ; sans nombre tant que la liste n'est pas lue. Le choix n'est pas enregistré :
l'écran s'ouvre sur « À traiter », et passe une fois sur « Tous » s'il n'y a rien à traiter,
une fois lu l'état de la pull request de chaque ticket En cours ;
il reste le même entre la liste et une fiche. Au téléphone, les filtres défilent à
l'horizontale. Liste du plus récent au plus ancien ; chaque ligne : icône du type (lue),
titre sur deux lignes au plus, « #12 · Nom · jj/mm/aa » (sans Issue, pas de numéro ; le nom
déclaré dans Admin › Membres, sinon l'adresse, jamais publié sur l'Issue), étiquette du statut
et, selon le cas, « Décision en cours », « Issue disparue », « En retard », « Analyse en
cours » ou « Développement en cours » (sablier, lu « Analyse en cours depuis 14:05 »),
« Relance possible ». Ces deux dernières pastilles ne lisent l'historique des lancements que
pour un ticket dont le serveur permet un lancement (reçu ou validé). Un ticket En cours porte
au plus une pastille de livraison, dans cet ordre : « Livraison en cours » (sablier, lu
« Livraison en cours depuis 14:05 »), « Correction en cours » (sablier, lu « Correction de la
pull request en cours », pendant une relance du développement), « CI en cours » (horloge, lu
« CI de la pull request en cours »), « PR prête » (icône de livraison, ton tertiaire, lu
« Pull request prête à livrer ») ; l'état de la pull request n'est lu que pour les tickets En cours, et sans lui
aucune pastille ne s'affiche. Tant que GitHub refuse au jeton la lecture de la CI, ni « CI en
cours » ni « PR prête » ne s'affiche. Pas de point de non-lu. Un ticket illisible n'apparaît que sous « Tous » : « Ticket illisible » / « Mettez
l'application à jour. ».

États : « Chargement des tickets » ; « Impossible de lire les tickets. » et « Réessayer » ;
panne après une lecture : bandeau « Mise à jour de la liste impossible. » au-dessus de la liste ;
aucun ticket : « Aucun ticket pour l'instant. Les membres n'ont encore rien signalé. » ;
« À traiter » vide : « Rien à traiter. Tous les tickets ont reçu une décision. » ; « Bloqués »
vide : « Aucun ticket bloqué. » ; ces deux derniers avec « Afficher tous les tickets ».

**Fiche « Ticket d'un membre ».** Texte sélectionnable, dans cet ordre : icône et type ; titre ;
étiquette du statut (elle clignote trois fois quand le statut change, jamais au premier
affichage ni avec les animations réduites, et « Statut : Refusé » est annoncé) et « Issue #12 » ;
« Ouvrir l'Issue #12 », et pour un ticket livré « Ouvrir la PR #34 » (adresse `https` de
`github.com` seule, échec « Impossible d'ouvrir GitHub. ») ; pour un ticket En cours, « Ouvrir
la PR #34 » quand le serveur retient une seule pull request éligible (adresse
`https://github.com/ChinaFred/KassBeer/pull/<n>` seule) ; pour un envoi impossible,
« Essais d'envoi : 10 », « Dernière erreur : … » et « Relancer l'envoi », puis « Nouvel essai
demandé le jj/mm/aa à hh:mm. Il partira dans l'heure. » jusqu'au changement de statut (hors
ligne : « Nouvel essai enregistré sur cet appareil. Il partira au retour du réseau. », tant
que la relance attend le réseau, même après un changement de disposition ; échec :
« Relance non enregistrée. Réessayez. ») ; pour une Issue disparue, « Issue introuvable sur GitHub
depuis le jj/mm/aa. Vérifiez qu'elle n'a pas été supprimée. », précédé d'une icône de lien
coupé en ton d'erreur ; l'encadré du texte de
l'administrateur, titré comme côté membre ; la frise ; « Auteur : … », « Envoyé le … à … »,
« Envoyé avec : … », « Écran : … » ; « Description » (même titre de section que côté membre) ;
« Livraison (N) », section ouverte, pour un ticket En cours ou Livré, ou qui a déjà un compte
rendu de livraison (voir ci-dessous) ;
« Analyses (N) », pour un ticket qui a une Issue (voir ci-dessous) ;
« Lancements (N) », section repliée, pour un ticket qui a une Issue (voir ci-dessous) ;
« Décisions (N) », section repliée, la
plus récente en haut (« Refus demandé le jj/mm/aa à hh:mm · Appliqué », « Clôture demandée le …
· Échec : … », « Validation demandée le … · Refusée par le serveur : … »). États : « Chargement
du ticket », « Impossible de lire les tickets. », « Ce ticket n'existe plus. », « Ce ticket n'est
pas disponible hors ligne. », « Ticket illisible. Mettez l'application à jour. », avec « Retour
aux tickets ».

**Analyses (N).** Section toujours ouverte, lue par l'administrateur seul (ADR-008). Elle
montre ce que le compte du mainteneur a publié sur l'Issue : analyses (`## Analyse…`) et
précisions (`## Précisions…`), la plus ancienne en haut, séparées de 12 px. N compte les seules
analyses ; le titre reste « Analyses » sans nombre tant que la section n'est pas lue. Une
carte par entrée, dans l'encadré du texte de l'administrateur, titre en en-tête :

| Entrée | Icône, fond | Titre |
|---|---|---|
| analyse | loupe, fond de surface | « Analyse du jj/mm/aa à hh:mm » (sans date : « Analyse ») |
| réponse publiée par « Répondre » | flèche de réponse, fond secondaire | « Votre réponse du jj/mm/aa à hh:mm » |
| précisions publiées hors de l'application | bulle, fond de surface | « Précisions du jj/mm/aa à hh:mm », puis « Non publiée depuis l'application. » |

Le corps est rendu en Markdown (style GitHub), aux couleurs du thème, sans sa ligne de titre
`## …`. Une image n'est jamais chargée : « [Image non affichée : texte alternatif] », ou
« [Image non affichée] ». Un lien ne s'ouvre, hors de l'application, que s'il est en `http` ou
`https` avec un hôte ; un autre lien ne fait rien ; un échec affiche « Impossible d'ouvrir le
lien. ». Aucun HTML n'est rendu : une balise reste du texte. Le lien est lu comme un lien
activable. Un tableau large défile à l'horizontale. Entrée tronquée : « Analyse tronquée, voir
GitHub. » (« Réponse tronquée, voir GitHub. » pour une réponse, « Précisions tronquées, voir
GitHub. » pour des précisions non publiées depuis l'application) et « Ouvrir l'Issue #12 ».
Plus de dix entrées sur l'Issue : « Seules les 10 dernières entrées sont affichées. Les autres
sont sur GitHub. », puis « Ouvrir l'Issue #12 ».

États : barre de progression « Lecture des analyses » ; « Impossible de lire les analyses. » et
« Réessayer » (« Lecture en cours » pendant la relecture), dès que la lecture échoue, sauf si
des entrées sont déjà affichées : elles restent ; ticket reçu sans analyse : « Pas
encore analysé. Les analyses publiées sur l'Issue s'afficheront ici. » ; ticket au-delà de Reçu
sans relevé : « Analyse pas encore relevée. » et « Ouvrir l'Issue #12 » ; hors ligne, absent du
cache : « Analyses non disponibles hors ligne. » ; document illisible : « Analyses illisibles.
Mettez l'application à jour. ».

**Livraison (N).** Section ouverte, juste après « Description », lue par l'administrateur seul
(ADR-008, T5) : les comptes rendus de la session de livraison relevés sur l'Issue
(`## Livraison — blocage`, `## Livraison — terminée`, publiés par le compte du mainteneur
seul), du plus ancien au plus récent, dix au plus. N compte les comptes rendus ; le titre
reste « Livraison » sans nombre tant que la section n'est pas lue. Une carte par compte rendu :

| Compte rendu | Icône, fond | Titre |
|---|---|---|
| blocage | erreur, fond d'erreur du thème et texte accordé | « Blocage du jj/mm/aa à hh:mm » (sans date : « Blocage ») |
| terminée | validation en couleur primaire, fond de surface | « Livraison terminée le jj/mm/aa à hh:mm » (sans date : « Livraison terminée ») |

Le titre de la carte est un titre de section pour le lecteur d'écran. Le corps est rendu en
Markdown sans sa ligne de titre, avec les mêmes garde-fous que les Analyses (aucune image
chargée, liens `http` et `https` seuls, aucun HTML rendu). Compte rendu tronqué : « Compte
rendu tronqué, voir GitHub. » et « Ouvrir l'Issue #12 ».

États : barre de progression « Lecture de la livraison » ; « Impossible de lire la
livraison. » et « Réessayer » (« Lecture en cours » pendant la relecture), sous les comptes
rendus déjà affichés s'il y en a ; hors ligne, absent du cache : « Livraison non disponible
hors ligne. » ; document illisible : « Livraison illisible. Mettez l'application à jour. » ;
aucun : « Aucun compte rendu de livraison. », suivi de « Appuyez sur « Livrer », en bas de la
fiche. » quand le bouton « Livrer » est affiché et actif (pas pour « Relancer la
livraison »).

**Lancements (N).** Section repliée, lue par l'administrateur seul (ADR-008, T4) : les sessions
Claude Code lancées sur ce ticket, la plus récente en haut, vingt au plus. Le titre reste
« Lancements » sans nombre tant que la section n'est pas lue. Une carte par lancement, dans
l'encadré du texte de l'administrateur : « Analyse lancée », « Développement lancé »,
« Livraison lancée » ou « Correction lancée » (« Lancement » pour une action inconnue), « le jj/mm/aa à hh:mm par vous » (« par un autre
administrateur » sinon), puis le résultat : « Session créée » ; « Échec : <raison> » (« Échec :
raison inconnue ») en ton d'erreur ; « Résultat inconnu : vérifiez sur claude.ai/code ».
Session créée avec un lien `https` sur `claude.ai` : « Ouvrir la session » (hors de
l'application ; échec « Impossible d'ouvrir la session. »), bouton icône « Copier le lien »
(« Lien copié. »), « Visible seulement depuis le compte Claude de l'administrateur. » et « Pour
l'arrêter, ouvrez-la sur claude.ai/code. ». Autre lien : « Lien de session invalide. », rien
ne s'ouvre.

États : barre de progression « Lecture des lancements » ; « Impossible de lire les lancements. »
et « Réessayer » ; hors ligne, absent du cache : « Lancements non disponibles hors ligne. » ;
document illisible : « Lancements illisibles. Mettez l'application à jour. » ; aucun :
« Aucune session lancée pour ce ticket. », suivi, quand le bouton de lancement est affiché et
actif dans la barre (décisions lues, aucune décision ni réponse en cours, en ligne, plafond non
atteint, aucun appel en cours), de « Appuyez sur « Lancer l'analyse », en bas de la fiche. »
(ou « Appuyez sur « Lancer le développement », en bas de la fiche. »).

**Barre de décision.** Fixée en bas de la fiche (moitié de la hauteur au plus, défilante) ; sous
480 px de hauteur, elle passe en fin de fiche. Les boutons sont ceux que le serveur permet pour
ce ticket (`allowed_decisions`), jamais déduits du statut par l'application : « Refuser »,
« Répondre » (valeur `answer`) et « Clore » à gauche ; à droite, une seule action principale :

| Statut | Action principale |
|---|---|
| Reçu | « Lancer l'analyse » (valeur `launch_analysis`) ; après l'échéance d'un lancement sans changement de statut, « Relancer l'analyse » (bouton tonal) |
| Analysé | « Valider » |
| Validé dans l'application | « Lancer le développement » (valeur `launch_development`), ou « Relancer le développement » |
| Validé sur GitHub seul | « Valider » |
| En cours, validé dans l'application | selon la pull request (ci-dessous) : « Livrer » (valeur `launch_delivery`), « Relancer la livraison » (bouton tonal) ou « Relancer le développement » (valeur `relaunch_development`, bouton tonal) |
| En cours, validé sur GitHub seul, Livré, Refusé, Clos | aucune |

Les boutons passent les uns sous les autres quand la largeur manque. Le serveur offre
« Valider » sur un ticket analysé seul (ADR-008, T4) ; pour un ticket reçu, la ligne « Valider
sera possible une fois le ticket analysé. » suit les boutons. « Lancer le développement »
n'est offert qu'après un « Valider » fait dans l'application (ADR-008, décision du
2026-11-13). Une étiquette « validé » posée sur GitHub change le statut affiché en Validé, mais
le serveur offre alors « Valider » à la place du lancement, et la ligne « Validé sur GitHub :
validez depuis l'application pour lancer le développement. » suit les boutons. Un retour à
Reçu ou Analysé, un refus ou une clôture effacent la validation de l'application. « Répondre » et les lancements
appellent le serveur : hors ligne, ils sont inactifs, et la ligne « Répondre demande le
réseau. », « Lancer une session demande le réseau. » ou « Répondre et lancer une session
demandent le réseau. » le dit sous les boutons. Hors ligne, la ligne « Lancer une session
demande le réseau. » s'affiche dès que le serveur permet un lancement, même quand l'historique
des lancements, absent du cache, retient le bouton ; aucune barre de progression ne s'affiche
alors.

Un lancement est « en cours » tant que l'échéance écrite par le serveur n'est pas passée (une
heure pour une analyse, trois pour un développement) : pas de bouton de lancement, et la barre
se redessine à l'échéance. Pendant un développement en cours, « Répondre » est masqué. Pendant
la lecture de l'historique des lancements, en ligne, une barre de progression « Lecture des
lancements » remplace le bouton de lancement ; historique illisible ou en panne : pas de bouton. Au-dessus
des boutons, une seule ligne de lancement, dans cet ordre de priorité :

| Cas | Ligne |
|---|---|
| appel de la fiche en cours | barre de progression, « Lancement de l'analyse en cours. » ; le bouton est inactif |
| lancement en cours | « Analyse en cours depuis 14:05 » (autre jour : « … depuis le 12/11/26 à 14:05 ») |
| plafond atteint, ticket reçu ou validé | « Plafond atteint le 13/11 : 10 lancements sur 10. Le compteur repart à zéro peu après minuit. » ; le bouton est inactif |
| relance | « Le lancement du jj/mm/aa à hh:mm n'a rien changé au ticket. Vérifiez sur claude.ai/code qu'aucune session ne tourne encore. » |
| plafond atteint, ticket analysé ou validé sur GitHub seul | « Plafond atteint le 13/11 : 10 lancements sur 10. Vous pouvez valider. Le compteur repart à zéro peu après minuit. » |

La date est celle du compteur écrit par le serveur. Le serveur le remet à zéro à sa passe de
minuit (heure de Paris) : quelques secondes après minuit, la ligne du plafond disparaît.

**Ticket En cours** (ADR-008, T5). « Livrer » et « Relancer le développement » ne sont offerts
que pour un ticket validé dans l'application (décisions du 2026-11-14). La ligne au-dessus des
boutons se lit dans l'état de la pull request écrit par le serveur, l'historique des lancements
et le verrou des livraisons ; l'application ne recalcule rien. Une seule ligne, annoncée, dans
cet ordre de priorité :

| Cas | Ligne | Bouton principal |
|---|---|---|
| livraison de ce ticket en cours | « Livraison en cours depuis 14:05. » (autre jour : « … depuis le 12/11/26 à 14:05. ») | aucun ; « Refuser » et « Clore » masqués |
| correction de la PR en cours | « Correction de la PR #34 en cours depuis 14:05. » | aucun |
| lecture de la CI refusée au jeton GitHub (403), avec une seule pull request éligible | « Le jeton GitHub ne peut pas lire la CI : sur GitHub, donnez-lui le droit « Actions : lecture ». » en ton d'erreur | aucun |
| état de la pull request en lecture | barre de progression, « Lecture de la pull request » | aucun |
| état illisible (version plus récente) | « État de la pull request illisible. Mettez l'application à jour. » en ton d'erreur | aucun |
| état en panne de lecture | « État de la pull request illisible. » en ton d'erreur, bouton icône « Réessayer », inactif avec un indicateur pendant la relecture | aucun |
| hors ligne, état absent du cache | « État de la pull request non disponible hors ligne. » | aucun |
| plusieurs PR | « 3 pull requests ferment l'Issue #12 : fermez sur GitHub celles à abandonner. » | aucun |
| CI rouge, validé sur GitHub seul | « CI de la PR #34 en échec. Ouvrez la PR pour voir l'erreur. » | aucun |
| CI rouge pendant le développement | « CI de la PR #34 en échec. Développement lancé le 13/11/26 à 14:05 : relance possible après 17:05. » (échéance un autre jour : « … après le 14/11/26 à 02:05. ») | aucun |
| CI rouge | « CI de la PR #34 en échec. Une session peut la corriger sur la même branche. » (plafond atteint : ligne du plafond) | « Relancer le développement » |
| aucune PR, développement en cours | « Développement en cours depuis 14:05. La pull request n'est pas encore prête. » | aucun |
| aucune PR | « Aucune pull request prête pour l'Issue #12. » | aucun |
| CI en cours | « CI de la PR #34 en cours. « Livrer » sera proposé quand elle sera verte. » | aucun |
| CI annulée | « CI de la PR #34 terminée sans succès. Ouvrez la PR pour la suivre sur GitHub. » | aucun |
| CI absente (aucun run) | « CI de la PR #34 pas encore lancée. Ouvrez la PR pour la suivre sur GitHub. » | aucun |
| livraison d'un autre ticket en cours | « Livraison du ticket #9 en cours depuis 14:05. Une seule livraison à la fois. », puis « Ouvrir le ticket #9 » (à côté de la liste, la fiche est remplacée ; au téléphone, elle s'empile) | aucun |
| PR prête, validé sur GitHub seul | « PR #34 prête. Ce ticket a été validé sur GitHub : fusionnez la PR sur GitHub. » ; si le serveur offre « Valider » : « … fusionnez la PR sur GitHub, ou validez-le depuis l'application pour la livrer d'ici. » | aucun |
| appel de la fiche en cours | barre de progression, « Lancement de la livraison en cours. » (« … de la correction … ») | inactif |
| plafond atteint | ligne du plafond | « Livrer » inactif |
| dernière livraison close par un blocage (marquée par le serveur) | « La livraison du 13/11/26 à 14:05 s'est arrêtée. Lisez le blocage dans la section Livraison. » (ton d'erreur) | « Relancer la livraison » |
| échéance passée sans fusion ni blocage | « La livraison du 13/11/26 à 14:05 n'a rien fusionné en trois heures. Vérifiez sur claude.ai/code qu'aucune session ne tourne encore. » | « Relancer la livraison » |
| PR prête | « PR #34 prête : CI verte le 13/11/26 à 14:05. » (sans date : « PR #34 prête : CI verte. »), icône de validation en couleur primaire | « Livrer » |

Hors ligne, « Livrer » et « Relancer le développement » sont inactifs et « Lancer une session
demande le réseau. » s'affiche sous les boutons. La barre se redessine aux échéances du verrou,
de la livraison, de la correction et du développement. Refuser et Clore pendant la livraison
de ce ticket sont aussi refusés par le serveur (« Une livraison est en cours sur ce ticket.
Attendez sa fin. »).

La ligne des précisions en attente (ci-dessous) s'affiche aussi sous la ligne du plafond ou de
la relance. Seul un lancement en cours (appel de la fiche ou échéance non passée) la masque.
Pour un ticket
reçu dont la dernière réponse suit la dernière analyse, la ligne « Vos précisions du jj/mm/aa à
hh:mm seront lues par la prochaine analyse. » précède les boutons. Pendant la publication d'une
réponse, pas de boutons : barre de progression (« Publication en cours » pour un lecteur
d'écran) et « Publication de la réponse en cours sur GitHub. ». Pendant la publication, cette
ligne remplace celle de la dernière décision quand celle-ci n'a pas de barre de progression
(écartée, en échec, interrompue, écrite hors ligne, état inconnu). Liste vide : pas de barre. Liste pas encore écrite par le serveur : « Le serveur n'a pas
encore calculé les décisions possibles pour ce ticket. ». Pendant une décision en attente ou en
cours, pas de boutons. Pendant la lecture des décisions, une barre de progression (« Lecture des
décisions ») remplace la barre. Décisions illisibles : « Impossible de lire les décisions. » et
« Réessayer » dans la fiche, et aucun bouton de décision. Au-dessus des boutons, une ligne
d'état de la dernière décision, annoncée :

| État | Ligne |
|---|---|
| écrite sur l'appareil hors ligne | « Refus enregistré sur cet appareil. Il partira au retour du réseau. » |
| en attente ou en cours | barre de progression, « Refus en cours sur GitHub. » |
| en attente depuis plus de 2 min | barre de progression, « Le serveur n'a pas encore pris ce refus en compte. » |
| en cours, bail du serveur expiré | « Refus interrompu. Le serveur le reprendra dans l'heure. » |
| appliquée | pas de ligne ; l'étiquette du statut clignote |
| écartée par le serveur | sa raison (« Cette décision n'est plus possible pour ce statut. »…) ; les boutons reviennent |
| en échec | « Le refus n'a pas abouti : <raison> », puis « Réessayez, ou prenez une autre décision. », « Réessayer » (reprise de la même décision) et les boutons de décision ; une reprise demandée hors ligne remplace la ligne par « Nouvel essai enregistré sur cet appareil. Il partira au retour du réseau. », sans boutons, jusqu'au retour du réseau |

Les phrases s'accordent : « Validation enregistrée… Elle partira », « Clôture interrompue ».

**Boîte de lancement** (ADR-008, P39). « Lancer l'analyse » ou « Lancer le développement »
ouvre « Lancer l'analyse de ce ticket ? » / « Lancer le développement de ce ticket ? »
(relance : « Relancer l'analyse de ce ticket ? » / « Relancer le développement de ce
ticket ? »), qu'un
appui à côté ne ferme pas ; rien n'est appelé avant « Lancer ». Contenu : « Une session Claude
Code va lire l'Issue #12 et publier son analyse sur GitHub. » (développement : « … va écrire
le code de l'Issue #12 et ouvrir une pull request. Elle ne fusionne rien. ») ; la ligne du
quota, « Lancements restants le 13/11 : 7 sur 10. », « Plafond atteint le 13/11 : … » (« Lancer »
inactif) ou « Lancements restants : inconnu. » quand l'état des lancements manque ; pour une
relance, l'avertissement de la relance ; l'encadré « Facturé sur l'abonnement Claude de
l'administrateur. Ce coût n'apparaît pas dans le suivi des coûts de l'application. ». Boutons
« Annuler » (focus initial) et « Lancer » (« Relancer » pour une relance).

Pendant l'appel : « Lancer » inactif avec « Lancement en cours », « Annuler » devient « Fermer »,
ligne annoncée « Lancement en cours. Vous pouvez fermer : le résultat s'affichera dans la
section Lancements. ». « Fermer », le retour et Échap ferment la boîte sans couper l'appel ;
un seul appel part à la fois. Un refus du serveur reste dans la boîte, en ton d'erreur, avec
son motif (plafond, ticket changé sur GitHub, routine non configurée, en pause, jeton refusé,
limite de l'API…). Message en bas d'écran, boîte ouverte ou fermée : « Session lancée. Le lien
est dans la section Lancements. » ; « Résultat inconnu, compté dans les lancements du jour.
Vérifiez sur claude.ai/code avant de relancer. » (ou le message du serveur) ; « Réponse perdue.
Regardez la section Lancements avant de relancer. » quand la réponse n'arrive pas ; un refus
arrivé après « Fermer » affiche son motif.

**Boîte « Livrer »** (ADR-008, P39). Même boîte que les lancements. Titre « Livrer ce
ticket ? » (relance : « Relancer la livraison de ce ticket ? ») ; « Une session Claude Code va
mettre la PR #34 à jour avec main, la fusionner, puis suivre le déploiement. » ; « La fusion
met l'application en ligne pour tout le groupe, sur le web et sur Android, sans autre accord.
Appuyer sur « Livrer » vaut accord de fusion. » ; « Type du ticket : Bug. » ; ligne du quota
(une livraison compte dans les 10 lancements du jour) ; pour une relance, l'avertissement de
la ligne (blocage ou échéance passée) ; encadré du coût. Boutons « Annuler » (focus initial) et
« Livrer » (« Relancer »), « Livraison en cours » pendant l'appel. Refus propres à la
livraison, dans la boîte : fichier protégé (« La PR #34 modifie un fichier protégé (…).
Fusionnez-la vous-même après relecture. Rien n'a été lancé ni décompté. ») et liste de
fichiers trop longue (« … trop longue pour être vérifiée. Fusionnez-la vous-même après
relecture. … ») : « Livrer » reste alors inactif tant que la boîte est ouverte ; pull request
plus prête, CI pas verte, lecture de la CI refusée au jeton (« Le jeton GitHub ne peut pas
lire la CI : sur GitHub, donnez-lui le droit « Actions : lecture ». Rien n'a été lancé ni décompté. »), plusieurs pull
requests, livraison d'un autre ticket en cours, correction en cours. Aucun de ces refus ne compte un lancement.

**Boîte « Relancer le développement ? »** « Une session Claude Code va reprendre la PR #34,
corriger la CI et pousser sur la même branche. Elle ne fusionne pas. » ; ligne du quota ;
encadré du coût ; « Annuler » (focus initial) et « Relancer ». Refus : « La CI de la pull
request n'est pas en échec. Rien n'a été lancé ni décompté. », « Une livraison est en cours
sur ce ticket. Rien n'a été lancé ni décompté. », ou le message « en cours ». Une correction
qui s'arrête ne publie rien sur l'Issue : sa raison est dans le résumé de la session, ouvert
depuis la carte « Correction lancée ».

**Boîtes.** « Valider » demande « Valider ce ticket ? » / « L'étiquette « validé » sera posée
sur l'Issue. Le membre verra « Validé ». », avec « Annuler » et « Valider ». Sur un ticket validé
sur GitHub seul, le texte devient « La validation sera enregistrée dans l'application.
« Lancer le développement » sera ensuite proposé. ». « Refuser » et
« Clore » ouvrent une feuille du bas au téléphone, un dialogue sinon, que ni un appui à côté ni
un glissement ne ferment. Les deux portent l'encadré « Publié sur un site public : n'écrivez ni
nom ni adresse. Le membre lira aussi ce texte. », et pour un ticket en cours « Une pull request
est peut-être ouverte. Elle ne sera pas fermée. ».

- « Refuser ce ticket » : champ « Motif du refus », 3 à 8 lignes, compteur de 2 000, aide
  « L'Issue sera fermée comme non prévue. », erreur « Le motif doit faire au moins 5
  caractères. », boutons « Annuler » et « Refuser ».
- « Clore ce ticket » : « Le ticket passera à « Clos » et l'Issue sera fermée. », champ
  « Commentaire de clôture », aide « Le membre lira ce texte : réponse, ou raison de la
  clôture. », erreur « Le commentaire doit faire au moins 5 caractères. », boutons « Annuler »
  et « Clore ».

Le champ reçoit le focus, et le reprend après une erreur. La boîte se ferme dès l'écriture sur
l'appareil. Un texte non envoyé reste dans la fiche et revient à la réouverture ; après une
décision écartée ou en échec, la boîte reprend le texte envoyé. Une écriture refusée par le
serveur affiche « Décision non enregistrée. Réessayez. » et rend boutons et texte. Pas de
message de succès après une décision appliquée.

**Boîte « Répondre ».** Feuille du bas au téléphone, dialogue sinon, que ni un appui à côté ni
un glissement ne ferment. Titre « Répondre à l'analyse » (ticket reçu : « Répondre au ticket »),
sous-titre « Analyse du jj/mm/aa à hh:mm » s'il existe une analyse ; encadré « Publié sur un
site public : n'écrivez ni nom ni adresse. Le membre ne lira pas ce texte dans
l'application. » ; puis « Le ticket repassera à « Reçu ». La prochaine analyse lira votre
réponse. » (ticket reçu : « Ajoutez une précision avant l'analyse. Elle sera lue par la session
d'analyse. »), et pour un ticket validé « La validation sera retirée. ». Champ « Votre
réponse », 4 à 10 lignes, compteur de 4 000 (texte sans ses espaces de bord, un émoji compte
pour un caractère, comme au serveur ; la saisie n'est pas coupée au-delà ; lu « 3 994
caractères restants » ou « 12 caractères en trop » par un lecteur d'écran, annoncé pendant la
saisie), aide « Répondez aux questions de l'analyse. Les
adresses e-mail et les mentions seront retirées. » (ticket reçu : « Précisez votre demande. … »),
focus à l'ouverture ; erreurs « La réponse doit faire au moins 5 caractères. » et « La réponse
ne doit pas dépasser 4 000 caractères. » (libellé du serveur), et le focus revient au champ. Boutons « Annuler » et « Publier ». Le serveur retire adresses et mentions ;
l'application ne contrôle que la longueur.

- Pendant l'envoi : « Publier » inactif (« Publication en cours »), champ inactif, « Annuler »
  devient « Fermer », ligne annoncée « Publication en cours. Vous pouvez fermer : le résultat
  s'affichera dans un message. ». Fermer la boîte (retour, Échap, « Fermer ») ne coupe pas
  l'appel. Un seul appel part à la fois.
- Succès : la boîte se ferme et le message « Réponse publiée. Le ticket repasse à Reçu. »
  s'affiche (ticket reçu : « Réponse publiée. Elle sera lue par la prochaine analyse. »).
- Échec : la boîte reste ouverte avec le texte, et une ligne annoncée en ton d'erreur ; boîte
  fermée, un message en bas d'écran : « Réponse non publiée : <motif du serveur> Votre texte
  est gardé. » ; « Réponse non publiée : pas de réseau. Votre texte est gardé. » ; « Réponse non
  publiée : le serveur n'a pas répondu à temps. Vérifiez l'Issue avant de publier à
  nouveau. » ; « Réponse non publiée : accès administrateur refusé. » ; sinon « Réponse non
  publiée. Votre texte est gardé. ». Un motif qui porte sur le texte s'affiche sous le champ.
- Échec partiel (réponse publiée, ticket pas ramené à Reçu) : le texte passe en lecture seule
  et « Cette réponse est déjà publiée sur GitHub. Publier remet le ticket à Reçu. » s'affiche.
- Le texte non publié reste dans la fiche, même après un changement de disposition, et revient
  à la réouverture ; il s'efface après une publication réussie.

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
flottant « Nouvelle recette » sur téléphone, bouton en tête au-delà. « Importer » ouvre
Recettes › Importer : sur téléphone après « Toutes / Les miennes », au-delà à côté de
« Nouvelle recette ».

- Liste vide : « Aucune recette. Appuyez sur Nouvelle recette pour commencer, ou importez
  un fichier BeerXML ou BeerJSON. » ; « Les miennes » vide : « Vous n'avez pas encore de
  recette. Appuyez sur Nouvelle recette pour commencer, ou importez un fichier BeerXML ou
  BeerJSON. » ; les deux
  avec le bouton « Importer des recettes » ; recherche sans résultat : « Aucune recette ne correspond à « {texte} ». » et
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
  valeur énumérée sort du modèle, ou si une durée en minutes n'est pas entière. Depuis la
  v0.1.17 (L2a d'ADR-005), les valeurs du schéma que la v0.1.15 refusait se lisent : malt
  extrait liquide ou sec, miel, fruit, jus et « Autre » ; houblon à l'empâtage ou au
  conditionnement, jour d'ajout d'un houblon à cru ; formes de houblon cônes pressés,
  cônes frais, poudre et extrait ; quantité d'un houblon, d'un ajout ou d'une levure en
  litres. Un APK de la v0.1.16 ou antérieure affiche encore « Recette illisible » sur une recette qui en
  porte une. Une copie
  figée illisible rend le brassin illisible : « Brassin illisible » dans la liste, même
  sous-titre ; sur sa fiche, sa préparation et l'écran du jour, « Ce brassin ne peut pas
  s'afficher. Il a peut-être été enregistré par une version plus récente de Kass'Beer :
  mettez l'application à jour. L'erreur est signalée à l'administrateur. », avec le bouton
  « Revenir aux brassins », qui ramène à la liste. Relire le brassin rendrait le même
  document : la préparation garde « Réessayer » pour un brassin absent ou hors ligne
  seulement. Hors ligne, le rapport part au retour du réseau.

**Fiche.** Nom, style, « Recette de {auteur} » pour un autre brasseur. Boutons, dans
l'ordre : « Nouveau brassin », « Modifier » (auteur), « Dupliquer », « Exporter »,
« Supprimer » (auteur). Puis le bloc Calculs (voir
« Calculs affichés »), le bloc « Coût avec vos prix » (voir « Coût »), et les sections Général (type de recette, « Non renseigné » s'il
manque ; « Auteur indiqué par le fichier importé » quand une recette importée le porte ; volume en
fermenteur, durée d'ébullition, équipement), Malts et sucres, Houblons
(avec l'IBU apporté par chacun), Autres ajouts, Levure, Paliers d'empâtage, Chronologie du
jour, Notes. Chaque ligne d'ingrédient tient sur deux niveaux : nom, puis ses valeurs. Un
ajout porte son type en tête (« Correction de l'eau · 5 g · Empâtage · 60 min ») ; la levure
« Haute fermentation (ale) · 11 g · atténuation 75 % · Sèche » ; un malt son type en
tête (« Malt », « Sucre », ou pour une recette importée « Extrait liquide », « Extrait sec »,
« Miel », « Fruit », « Jus », « Autre ») ; un houblon « Ébullition 60 min · 30 g · 10 % alpha
· Pellets · 31 IBU », avec, pour une recette importée, les moments « Empâtage » et
« Conditionnement », les formes « Cônes pressés », « Cônes frais », « Poudre » et
« Extrait », et « ajout au jour 2 » après la durée d'un houblon à cru ; un palier « Infusion ·
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
duplique, avec les mêmes ingrédients, paliers et équipement, et l'auteur de la recette
d'origine s'il y en a un, sans fiche d'origine. La source
ne change pas. Possible sur toute recette, y compris celle d'un membre retiré. Message
« Recette dupliquée. » (hors ligne : « Recette dupliquée sur l'appareil. Elle partira au
retour du réseau. »), puis la fiche de la copie. Pendant la lecture du nom du compte, le
bouton affiche « Duplication » et ne répond pas : un double appui ne crée qu'une copie.

**Exporter** (tous les membres, toute recette lisible, y compris celle d'un membre retiré).
Feuille du bas sur téléphone, dialogue au-delà : « Exporter « {nom} » », « Le fichier ne
contient aucun prix. », choix « BeerJSON » (« Format le plus complet. », par défaut, non
mémorisé, inactif pendant un envoi) ou « BeerXML » (« Lu par la plupart des logiciels de brassage. »), puis un bloc
d'état lu par le lecteur d'écran à chaque changement.

- Prêt : « Prêt à exporter. », « Auteur dans le fichier : {nom}. », puis ce que le fichier ne garde pas : « Non exporté : le style
  « {style} » (BeerJSON demande sa catégorie). », « Non exporté : la chronologie du jour. »,
  « Non exporté : empâtage (aucun palier). » (recette sans palier ni température du grain,
  à l'extrait par exemple), « Non exporté : ébullition (durée non renseignée). ». Boutons
  sur Android : « Annuler », « Enregistrer » (bouton à contour ; sélecteur d'enregistrement
  du système, puis « Fichier enregistré. »), « Partager le fichier » (seul bouton plein ;
  feuille de partage du système). Sur le web : « Annuler », « Télécharger », puis
  « Téléchargement lancé : {fichier}. ». Nom du fichier : nom de la recette sans accents, en
  minuscules, avec des tirets (`ipa-maison.json`), `recette.json` si le nom n'a ni lettre ni
  chiffre. Échec : « Le fichier n'a pas pu être créé. » dans le bloc d'état de la feuille,
  rapporté ; les boutons restent actifs pour réessayer.
- Le fichier contient la recette, l'auteur, le rendement d'empâtage de l'équipement de la
  recette comme rendement de brassage, et les densités, le degré, l'amertume et la couleur
  calculés. L'auteur est celui indiqué par le fichier importé ; sinon, pour le membre qui a
  créé la recette, son nom. Jamais : prix, stock, coût, e-mail, identifiant du propriétaire
  ou de l'équipement, nom de l'équipement. Deux exports de la même recette sans changement
  donnent le même fichier.
- Recette d'un autre membre sans auteur indiqué par un fichier : bloquée, « Dupliquez la
  recette pour l'exporter à votre nom. », boutons « Fermer » et « Dupliquer » (la même action
  que sur la fiche) ; s'il manque d'autres valeurs, leur liste précède le message.
- Bloqué : « Export impossible : {n} valeurs à compléter. » et la liste, avec les libellés de
  « À compléter » et ceux-ci : « Type de recette non renseigné. », « Aucun palier
  d'empâtage : la température du grain demande un palier. », « Température du grain non
  renseignée. » (paliers saisis), « Type de palier non renseigné : {noms}. », « Type de
  levure non renseigné : {noms}. », « Forme de levure non renseignée : {noms}. », « Quantité
  de levure non renseignée : {noms}. », « Type d'ajout non renseigné : {noms}. », « Aucun
  équipement choisi : le rendement de brassage ne peut pas être calculé. » (hors ligne sans
  l'équipement en cache : « Équipement indisponible hors ligne. »), et, pour sa propre
  recette quand le compte n'a pas de nom, « Auteur inconnu : le compte qui a créé la recette
  n'a pas de nom. ». L'auteur voit « Annuler » et « Compléter la recette », qui ouvre
  l'éditeur. Un autre membre lit « Seul l'auteur complète cette recette. Dupliquez-la pour
  la compléter à votre nom. » et « Fermer ».
- BeerXML (ADR-005, E4) : au premier choix de BeerXML, « Lecture du style dans la
  Bibliothèque » et une roue, bouton « Fermer ». Le style de la recette est cherché par son nom
  exact dans la Bibliothèque, puis sa fiche est lue (catégorie, code, guide, plages). Ce qui
  a déjà été lu sert hors ligne. Index ou fiche illisibles : « La fiche du style n'a pas pu
  être lue dans la Bibliothèque. Vérifiez la connexion, puis réessayez. », boutons « Fermer »
  et « Réessayer ». Les autres états sont ceux du BeerJSON (prêt, bloqué, échec), avec le
  fichier `ipa-maison.xml`. En plus des valeurs du BeerJSON, BeerXML demande : « Style non
  renseigné : choisissez-le dans les suggestions du champ Style. » (recette sans style),
  « Style « {saisi} » absent de la Bibliothèque : choisissez-le dans les suggestions du champ
  Style. » (style absent de la Bibliothèque sous ce nom exact), « Fiche du style « {style} » incomplète dans la Bibliothèque : BeerXML
  demande sa catégorie et ses plages de densité, d'amertume et de couleur. Choisissez un autre
  style, ou exportez en BeerJSON. » (17 styles BJCP sans plage, et IPA Argenta sans densités ;
  seul manque, le titre devient « Export BeerXML impossible avec ce style. » et la feuille
  n'offre que « Fermer », sans « Compléter la recette » ; un style d'un autre type que bière,
  hydromel ou cidre a le même message), « Type de
  levure à préciser pour BeerXML : {levures}. Choisissez Haute fermentation (ale), Basse
  fermentation (lager), Kveik ou Culture mixte. » (levure sans type, de vin, de champagne ou
  « Autre » ; sans aucune levure : « Aucune levure : BeerXML classe le style selon
  la levure. Ajoutez une levure de type Haute fermentation (ale), Basse fermentation (lager),
  Kveik ou Culture mixte. »), « Durée d'ébullition non renseignée. », « Évaporation de
  l'équipement « {équipement} » non renseignée. », « Pertes au trub de l'équipement
  « {équipement} » non renseignées. », « Volume mort de la cuve d'ébullition de l'équipement
  « {équipement} » non renseigné. » (« de l'équipement » seul s'il n'est pas lu) ; quand
  l'équipement est celui du lecteur, le bouton « Compléter l'équipement » ferme la feuille et
  ouvre son éditeur ; quand seuls ces champs manquent, c'est le bouton plein, sans « Compléter
  la recette » ni texte pour dupliquer, « Type de recette sans équivalent
  BeerXML : {type}. », « Moment d'ajout non renseigné : {noms}. », « Durée d'ajout non
  renseignée : {noms}. », « Forme du houblon à compléter : {noms}. », « BeerXML ne connaît pas
  les houblons mesurés en volume : {noms}. ».

**Importer** (Recettes › Importer, tous les membres). Page pleine hors de la coquille, avec
la flèche de retour et le bandeau hors ligne ; Admin › Import ne change pas.

1. Avant le choix : « Choisissez un fichier BeerXML (.xml) ou BeerJSON (.json) exporté de
   votre logiciel de brassage. 500 recettes et 10 Mo au plus. Les prix et le stock du fichier
   ne sont pas importés. » et « Choisir un fichier », qui ne répond pas tant que le sélecteur est ouvert (Android). Le sélecteur du système s'ouvre sans filtre de
   type : le format se lit au contenu, jamais à l'extension. Fermer le sélecteur ramène à
   l'écran sans message. Aucun fichier n'est lu depuis le réseau ni depuis l'application.
2. « Lecture du fichier » pendant l'analyse, sur l'appareil.
3. Fichier refusé, avec le bouton plein « Choisir un autre fichier » : « Fichier trop gros : 12,4 Mo.
   Kass'Beer lit les fichiers de 10 Mo au plus. » (refusé avant la lecture) ; « Fichier
   illisible : « {fichier} » n'est ni un fichier BeerXML ni un fichier BeerJSON. » (JSON ou
   XML mal formé, encodage illisible ou non pris en charge, `DOCTYPE` ou entité XML inconnue
   compris) ; « Ce fichier JSON n'est pas au format BeerJSON. Dans votre logiciel, exportez la
   recette en BeerXML ou en BeerJSON. » ; « Fichier BeerSmith (.bsmx) non lu. Dans BeerSmith,
   exportez la recette en BeerXML. » ; « Version de BeerJSON non prise en charge ({version}). Kass'Beer lit
   les versions 1, 2 et 3. » ; « Aucune recette dans « {fichier} ». » (aussi pour un
   fichier BeerXML d'ingrédients, de styles ou d'équipements seuls). Ouverture impossible :
   « Impossible d'ouvrir le fichier. Réessayez ou choisissez un autre fichier. » et un seul
   bouton, « Réessayer ». Une panne inattendue de l'analyse affiche « Fichier illisible » et
   est rapportée (taille et type de l'erreur seulement).
4. Aperçu, sans aucune écriture : au-delà de 500 recettes, « Ce fichier contient plus de 500
   recettes : seules les 500 premières sont lues. » ; résumé chiffré accordé, sans les
   compteurs à zéro (« 3 prêtes · 1 incomplète · 2 refusées », « · 1 déjà importée »,
   « · 1 en double » s'il y en a) ; « Choisir un autre fichier » ; « Les prix et le stock du
   fichier ne sont pas importés. » ; « Équipement des recettes » (présélectionné si le membre
   n'a qu'un équipement, sinon « Aucun équipement » ; aide « Vous pourrez le changer dans
   chaque recette. ») ; un filtre avec le compte de chaque valeur : « Toutes (6) »,
   « Prêtes (3) », « Incomplètes (1) », « Déjà importées ou en double (0) », « Refusées
   (2) » ; « Toutes les recettes (N) » (« Toutes les recettes affichées (N) » quand un filtre
   est actif), qui coche ou décoche les recettes affichées ; « Aucune recette pour ce filtre. » quand un filtre n'en montre aucune ; puis une ligne par recette :
   case, nom, « style · volume · statut », et « Détails (n) » dépliable (lu « Détails de
   {nom} (n) ») avec « À compléter », « Modifié à l'import » et « Repris de la Bibliothèque ». Le statut s'écrit en toutes lettres : « Prête » (rien ne manque
   au calcul ni à l'export BeerJSON, cochée), « Incomplète » (cochée), « Déjà importée le
   {date} » (même contenu déjà importé par ce membre, décochée, cochable : une seconde copie),
   « En double dans le fichier » (décochée), « Refusée : {raison} » (sans case). Un même nom
   seul ne fait pas un doublon.
5. Raisons d'un refus : « Nom absent. », « Plus de 50 houblons (63). » (malts, ajouts,
   « Plus de 10 levures », « Plus de 20 paliers »), « Unité inconnue pour le volume :
   « barrels ». », « Valeur hors limites : quantité de Pils. », « Valeur illisible : … »,
   « Valeur absente : quantité de Cascade. », « Valeur inconnue pour le type de Pils :
   « adjunct ». », « Nom d'un malt absent ou sans lettre ni chiffre. », « Recette
   illisible. ». Aucune liste n'est tronquée.
6. « Modifié à l'import » : « Style : seul le nom « {style} » est gardé. », « Non importés :
   profil d'eau, étapes de fermentation, … », « Nom coupé à 120 caractères. », « Notes
   coupées à 10 000 caractères. », « Unités converties (livres, °F, Lovibond). », « Valeur
   0 lue comme absente : rendement d'extrait de Pils. », « Non importé : quantité de S-04 en
   « pkg ». », « Non importé : … , hors limites. » (au-delà de 1 000 kg ou de 1 000 L par
   ligne, de 10 000 L de volume, de 2 000 EBC, de 365 jours hors ébullition), « Durée de
   {nom} arrondie à la minute. », « Moment d'ajout simplifié : {nom}, compté à l'empâtage. »
   (ou à l'ébullition, à cru, au conditionnement), « Caractères de contrôle retirés des
   textes. », « {n} champs inconnus ignorés. ». Propres au BeerXML : « First Wort : {houblon}
   compté à l'ébullition, {n} min. » (« … compté à l'ébullition, durée à compléter. » sans
   durée d'ébullition dans le fichier), « Whirlpool sans durée : {houblon} compté à l'arrêt du
   feu. » (de même « Aroma sans durée : … »), « Aroma : {houblon} compté à l'ébullition,
   {n} min. Si c'est un whirlpool, choisissez Whirlpool dans la recette. », et « Non
   importés : … équipement du fichier, nom de l'empâtage ». Une seule tournure : « compté à
   l'ébullition », « compté à l'arrêt du feu ». Une quantité obligatoire au-delà de ces
   plafonds refuse la recette (« Valeur hors limites : quantité de Pils. »).
6 bis. « Repris de la Bibliothèque » (ADR-005, E5) : à l'ouverture de l'écran, les index des
   malts, houblons, levures et ajouts de la Bibliothèque sont lus une fois. Le nom d'une
   ligne se résout quand il est celui d'une entrée ou l'un de ses autres noms, après
   normalisation (casse, accents, ponctuation) ; pour une levure, aussi par sa souche
   (« Wyeast 1056 », « WLP001 »), sa référence (« US-05 ») ou son producteur et sa référence
   (« Fermentis US-05 »). Aucune correspondance approchée. Une valeur absente du fichier est
   reprise de l'entrée : couleur, rendement d'extrait et type d'un malt ; acides alpha et
   forme d'un houblon ; type, forme et atténuation d'une levure ; type d'un ajout. Une valeur
   du fichier n'est jamais remplacée. Chaque valeur reprise est listée : « Couleur de Pils reprise de la
   Bibliothèque. », « Rendement d'extrait de Pils repris de la Bibliothèque. », « Acides
   alpha de Saaz repris de la Bibliothèque. », « Type de Coriandre repris de la
   Bibliothèque. » (type d'un ajout). Hors ligne, ou si un index n'a pas pu être lu, l'import
   marche sans reprise, et l'aperçu comme le compte rendu affichent « Bibliothèque non lue
   ({natures}) : les valeurs absentes du fichier ne sont pas complétées. », avec les natures non
   lues (malts et sucres, houblons, ajouts, levures), suivi hors ligne de « Réessayez en ligne
   pour les reprendre. » ; si les index manquent parce que la Bibliothèque n'est pas encore remplie :
   « Bibliothèque vide : les valeurs absentes du fichier ne sont pas complétées.
   L'administrateur la remplit. ». Une lecture incomplète est refaite au choix du fichier
   suivant. Hors ligne, les index se lisent dans le cache seul, et l'aperçu ne les attend pas
   plus de 3 s après le choix du fichier ; au-delà, il s'ouvre avec « Bibliothèque non lue ». La nature d'un malt reprise s'écrit
   « Nature de Pils reprise de la Bibliothèque. ».
7. Barre fixe « Importer N recettes » ; sans case cochée, « Cochez au moins une recette. »
   au-dessus du bouton inactif ; sans recette importable, « Aucune recette à importer. ».
   Aucun dialogue de plus.
8. « Import en cours : 4 sur 10 » et une barre de progression ; une écriture par recette,
   au nom du membre ; le retour est bloqué tant que les écritures ne sont pas faites sur
   l'appareil.
9. « Import terminé », « 9 créées · 2 ignorées · 1 en erreur » ; hors ligne, « {n} recettes
   créées sur l'appareil. Elles partiront au retour du réseau. » ; sections « Créées »
   (toucher ouvre la fiche par-dessus le compte rendu, qui revient au retour ; « En attente
   du réseau » jusqu'à la réponse du serveur), « Ignorées » avec leur raison (« Saison —
   Non cochée », « Porter — Refusée : Nom absent. »), « En erreur » (« L'enregistrement de
   « {nom} » a échoué. ») ; boutons « Revenir aux recettes » et « Importer un autre
   fichier ». « Import terminé. » et le bilan sont annoncés une fois au lecteur d'écran, refus reçus pendant l'écriture compris ; un refus reçu
   pendant la lecture du compte rendu est annoncé. Un refus du serveur arrivé après la
   sortie de l'écran, ou après « Importer un autre fichier », s'annonce en un seul message :
   « Import : 2 recettes refusées par le serveur : Saison, Porter. ».
10. Après l'écriture, chaque nom qu'aucune entrée de la Bibliothèque ne résout est signalé
   une fois à l'administrateur (ADR-005, E6), sans le nom du fichier ni celui du membre,
   200 noms au plus par import ; au-delà, le compte rendu dit « {n} autres noms non reconnus
   non signalés. ». Rien d'autre ne s'affiche au membre. Hors ligne, le signalement part au
   retour du réseau. Un échec est rapporté et n'arrête pas l'import.

Une recette importée garde ce que le fichier dit, sans valeur inventée : un champ absent
reste absent, sauf une valeur reprise de la Bibliothèque (6 bis), et la recette se complète
dans l'éditeur, comme une recette saisie. Les
textes du fichier s'affichent en texte simple.

Un fichier BeerXML 1.0 se lit en UTF-8, ISO-8859-1 ou windows-1252, selon sa déclaration
(UTF-8 sans déclaration). Un fichier déclaré ISO-8859-1 qui contient une apostrophe
typographique (BeerSmith sous Windows) se lit juste. Le style garde son nom seul ; le profil
d'eau, les étapes de fermentation et l'équipement du fichier ne sont pas importés. Une
levure `Wheat` reste une levure de blé. Une quantité d'ajout ou de levure en litres reste en
litres (affichée en mL ou L).

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
  recette. », l'écran remonte au champ et y place le curseur), « Style (facultatif) »
  (aide « Tapez un code (21A) ou un nom, puis choisissez une suggestion. L'export BeerXML
  demande un style de la Bibliothèque. » ; à la frappe, 8 styles au plus, « American IPA » puis « 21A · IPA », par code
  ou par nom ; le choix écrit le nom exact du style ; la saisie libre reste possible),
  « Type de recette » (liste déroulante : « Non précisé », Tout grain, Empâtage partiel,
  Extrait), « Volume en fermenteur (L) » (plus de 0), « Durée d'ébullition (min) » (entier
  de 0 à 600), « Équipement » (« Aucun
  équipement », les siens, puis ceux du groupe avec leur auteur ; un équipement disparu
  s'affiche « Équipement supprimé »). Une nouvelle recette présélectionne l'équipement du
  brasseur s'il n'en a qu'un. Une recette incomplète s'enregistre. Une recette importée
  qui porte un auteur l'affiche en lecture seule (« Auteur indiqué par le fichier
  importé ») ;
  l'éditeur n'a pas de champ pour le saisir et le garde à l'enregistrement.
- Chaque section a son bouton : « Ajouter un malt ou un sucre », « Ajouter un houblon »,
  « Ajouter un ajout », « Ajouter une levure » (une seule levure), « Ajouter un palier ». Le
  formulaire s'ouvre en feuille du bas sur téléphone, en dialogue au-delà, avec « Annuler »,
  « Ajouter et continuer » (ajoute la ligne, vide le formulaire, remet le curseur sur « Nom »
  et annonce « « {nom} » ajouté. ») et « Ajouter » (« Enregistrer » pour une ligne
  existante).
- Nom d'un malt, d'un houblon, d'un ajout ou d'une levure (ADR-005, E2) : à la frappe, 8
  entrées de la Bibliothèque au plus, par nom ou autre nom (et, pour une levure, producteur
  et référence), avec une seconde ligne (« Malt · 3,9 EBC · 81 % », « Pellets · 6,5 % alpha »,
  « Fermentis US-05 · Sèche », « Épice » pour un ajout). L'index est lu à l'ouverture du
  formulaire, une fois par session. Choisir une entrée écrit son nom et remplit les valeurs
  vides : nature, couleur et
  rendement d'extrait d'un malt (une nature hors de Malt et Sucre s'affiche en troisième
  segment) ; acides alpha et forme d'un houblon ; type, forme et atténuation d'une levure ;
  type d'un ajout. Une ligne sous « Nom », annoncée au lecteur d'écran, liste les seules
  valeurs remplies : « Couleur et rendement d'extrait repris de la Bibliothèque. ». Une valeur
  déjà saisie ou choisie reste : quand elle diffère de l'entrée, « Reprendre les valeurs de la
  Bibliothèque » la remplace ; le bouton suit le dernier champ concerné (« Rendement
  d'extrait », « Forme » du houblon, « Forme » de la levure). Une nature hors de Malt et Sucre
  (extrait, miel, fruit) ne compte pas dans la différence quand le brasseur a choisi Malt ou
  Sucre. La saisie libre reste possible. La liste fait 280 px au plus, s'ouvre vers le haut
  quand il y a plus de place au-dessus, est nommée « Suggestions de la Bibliothèque » et
  annonce leur nombre (« 3 suggestions de la Bibliothèque ») ; l'option surlignée au clavier a
  le fond de focus et reste visible (en bas de la liste en descendant, en haut en montant).
  Entrée ou « Suivant » ne choisit l'option surlignée qu'après ↑ ou ↓ ; sinon le nom tapé reste
  et le focus passe au champ suivant (même règle pour le style). Un index arrivé après la frappe
  met la liste à jour sans autre touche. Après « Reprendre les valeurs de la Bibliothèque », la
  ligne sous « Nom » liste les valeurs reprises et le focus va au premier champ de saisie repris.
  Hors ligne, l'index se lit dans le cache seul. Index absent du serveur : « Bibliothèque vide :
  suggestions indisponibles. ». Sans index, l'aide
  du champ dit « Suggestions de la Bibliothèque indisponibles. Vous pouvez saisir le nom. », et
  la prise du focus suivante relit l'index.
- Malt ou sucre : « Nom », « Nature » (Malt, Sucre ; le type d'une recette importée,
  Extrait liquide, Extrait sec, Miel, Fruit, Jus ou Autre, reste visible et choisi en
  troisième segment, et l'enregistrement le garde ; pour « Autre », l'avertissement « Nature
  à préciser pour le calcul : choisissez Malt ou Sucre. » s'affiche sous le choix, en couleur
  d'avertissement, sans bloquer l'enregistrement), « Quantité (kg) » (obligatoire),
  « Couleur (EBC) » (aide « Sert au calcul de la couleur. »), « Rendement d'extrait (%) »
  (aide « Sert au calcul de la densité initiale. »).
- Houblon : « Nom », « Quantité (g) », « Acides alpha (%) », « Utilisation » (Ébullition,
  Whirlpool, À cru), durée, « Forme » (Pellets, Cônes, sans choix par défaut ; sinon
  « Choisissez une forme. », y compris pour un houblon sans forme d'une recette publique
  dupliquée, quand sa ligne est modifiée). La durée dépend du moment : « Durée d'ébullition (min) »,
  obligatoire, entier de 0 à 600 ; « Durée d'infusion (min) » au whirlpool, obligatoire,
  entier de 1 à 600 (« Champ obligatoire. » si vide ; à 0, « Au moins 1 min. Pour un ajout à
  l'arrêt du feu, choisissez Ébullition et 0 min. »), avec l'aide « Temps entre l'arrêt du
  feu et le refroidissement. Pour un ajout à l'arrêt du feu sans infusion, choisissez
  Ébullition et 0 min. », jamais coupée ; « Durée à cru (jours) », facultative, décimale
  permise, enregistrée en minutes entières (jours × 1 440, arrondi à la minute). Le
  formulaire garde une durée par moment : le texte saisi est mémorisé pour chaque moment,
  revenir à un moment remet son texte, un moment jamais saisi a un champ vide. Un houblon
  importé à l'empâtage ou au conditionnement garde son moment, affiché en quatrième segment
  d'« Utilisation », avec « Durée (min) » facultative et l'aide « Moment conservé du fichier
  importé ; le calcul de l'amertume ne le prend pas en charge. ». Une forme importée
  (Cônes pressés, Cônes frais, Poudre, Extrait) reste visible et choisie à côté de Pellets
  et Cônes. Pour un houblon d'ébullition pesé d'une forme Poudre ou Cônes frais,
  l'avertissement « Forme non prise en charge par le calcul de l'amertume : choisissez
  Pellets ou Cônes. » s'affiche sous « Forme » ; pour un extrait pesé, « Forme non prise en
  charge par le calcul de l'amertume. Pour un extrait, indiquez la quantité en ml. ». Pour la forme Extrait, pour une ligne déjà en
  volume, et tant que l'unité est ml, « Unité de la quantité » (g, ml) s'affiche avant la
  quantité ; le champ devient « Quantité (ml) », avec l'aide « Non compté dans l'amertume
  (mesuré en volume). ». Le jour d'ajout d'un houblon à cru
  importé est gardé tant que le houblon reste à cru (aide « Jour d'ajout du fichier
  importé conservé : jour 2. »).
- Autre ajout : « Nom », « Unité de la quantité » (g, ml ; g par défaut, placée avant la
  quantité), « Quantité (g) » ou « Quantité (ml) », « Type d'ajout » (liste déroulante : « Non
  précisé », Correction de l'eau, Clarifiant, Épice, Herbe, Arôme, Bois, Autre),
  « Utilisation » (facultative : Empâtage, Ébullition, Après ébullition, Fermentation,
  Embouteillage), « Durée (min) » (entier). Une durée sans utilisation est refusée :
  « Choisissez une utilisation. » ; ce message s'efface dès qu'une utilisation est choisie
  ou que la durée est vidée. Un ajout « Après ébullition » sans durée s'enregistre comme un
  ajout à 0 min d'ébullition et se relit « Ébullition · 0 min » ; tant que la durée est vide,
  l'aide « Sans durée, l'ajout est enregistré à l'arrêt du feu (Ébullition, 0 min). »
  s'affiche sous « Durée (min) ». Aucun calcul.
- Levure : « Nom », « Unité de la quantité » (g, ml ; g par défaut, avant la quantité),
  « Quantité (g) » ou « Quantité (ml) » (facultative, plus de 0, aide « Le coût compte un
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
- Choix par segments (nature, utilisation, forme, unité) : les segments passent l'un sous
  l'autre quand leurs libellés ne tiennent pas sur la largeur, à la taille de texte
  courante (360 dp à 200 %, par exemple). Les segments g et ml se lisent « grammes » et
  « millilitres ».
- Aucune valeur n'est choisie d'avance dans les nouveaux champs. Une valeur absente de ces
  listes mais connue du modèle (venue d'un futur import) s'affiche sous son libellé français
  et l'enregistrement la conserve. Types de recette : Cidre, Kombucha, Soda, Hydromel, Vin,
  Autre ; type de levure : Levure de blanche ; formes de levure : Gélose, Culture, Lie (la
  forme importée reste visible et choisie dans le formulaire, à côté de Sèche et Liquide).
  Ces valeurs ne sont pas proposées à la saisie.
- Un appui sur une ligne ouvre son formulaire. Le menu ⋮ propose « Dupliquer » et
  « Retirer » (sans confirmation ; la SnackBar « « {nom} » retiré. » propose « Annuler »),
  et pour un palier « Monter » et « Descendre ». Les malts et sucres se rangent par masse
  décroissante ; les houblons par moment (empâtage pour une recette importée, ébullition
  de la plus longue à la plus courte, whirlpool, à cru, conditionnement) ; l'ordre est
  enregistré tel quel.
- En-tête de la section Houblons : nombre de lignes et masse des seuls houblons pesés
  (« 3 · 45 g ») ; avec des houblons en volume, « 3 dont 1 en volume · 25 g », et sans
  masse si aucun n'est pesé (« 1 en volume »).
- Plafonds : 50 malts et sucres, 50 houblons, 50 ajouts, 20 paliers. Au plafond, le bouton
  d'ajout est inactif avec « 50 houblons au plus. » (etc.).
- Avertissements non bloquants : « Quantité inhabituelle : 22 400 g. Vérifiez la saisie. »
  au-delà de 1 000 g pour un houblon ou un ajout, de 1 L pour une quantité en volume
  (houblon, ajout), de 30 kg pour un malt ou un sucre ;
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
houblons et ajouts en grammes (« 22,4 g »), une quantité en volume en millilitres sous
1 L (« 5 ml ») et en litres au-delà (« 1,5 L »), « 20 L », « 67 °C », « 60 min », houblon à cru
« 3 jours » (« 1,5 jour » au singulier sous 2). Les tuiles des calculs s'élargissent avec la
taille du texte : à 200 %, elles passent sur une colonne plutôt que de couper « 1057,9 ».

### Bibliothèque

Consultation en lecture seule des styles, des ingrédients et des recettes publiques
(ADR-005, L4), ouverte à tout membre. Les données sont écrites par le script d'ingestion de
l'administrateur ; personne ne les modifie dans l'application.

**Accès.** Destination « Bibliothèque » de la navigation, après Recettes. L'adresse
`/bibliotheque` mène aux styles (`/bibliotheque/styles`). Six segments en puces :
« Styles », « Malts et sucres », « Houblons », « Levures », « Divers », « Recettes
publiques ». Chaque segment a son adresse (`/bibliotheque/houblons`…). Sous 600 px, les puces
tiennent sur une ligne qui défile à l'horizontale, et une icône d'information à leur droite
(infobulle « Sources des données ») ouvre « Sources des données ». À partir de 600 px, les
puces passent à la ligne et le lien « Sources des données » est écrit sous elles.

**Styles et ingrédients.** La liste du segment est lue à la première ouverture, puis gardée
pour la session. Ordre alphabétique, avec le nombre d'entrées (« 812 entrées », « 3 sur
812 » pendant une recherche, annoncé aux lecteurs d'écran). Chaque ligne :

- style : « 21A · American IPA », puis catégorie · degré · amertume (« IPA · 5,5 % vol à
  7,5 % vol · 40 IBU à 70 IBU ») ;
- malt ou sucre : nom, puis nom français · type · couleur · rendement ;
- houblon : nom, puis forme · « 6,5 % alpha » ;
- levure : nom, puis producteur et référence (« Wyeast 1056 ») · type · forme ·
  atténuation ;
- divers : nom, puis nom français · type.

« Rechercher par nom » (« Rechercher par nom ou code » pour les styles) filtre à la frappe,
sans lecture en base, sur le nom, les autres noms, le nom français, le code d'un style, le
producteur et la référence d'une levure ; majuscules et accents ne comptent pas. Sans
résultat : « Aucun résultat pour « {texte} ». » et « Effacer la recherche ». La recherche
n'est pas enregistrée ; elle reste en place au retour d'une fiche. Une entrée illisible est
écartée : « 1 entrée illisible n'est pas affichée. L'erreur est signalée à
l'administrateur. »

**Fiche d'une entrée** (`/bibliotheque/{segment}/{id}`, titre « Style », « Malt ou
sucre », « Houblon », « Levure » ou « Ajout divers », retour vers le segment). Nom, « Autres
noms : … », puis :

- style : « Classement » (code, catégorie « 21 · IPA », type traduit : « Bière », « Cidre »,
  « Hydromel »…, guide), « Plages » (densité initiale « 1056,0 à 1070,0 », densité finale,
  degré, amertume, couleur en EBC) ;
- malt ou sucre : nom français, type, couleur, rendement d'extrait, producteur, origine ;
- houblon : nom français, forme, acides alpha, acides bêta, usage (« Aromatique »,
  « Amérisant », « Aromatique et amérisant », « Double usage »), origine ;
- levure : producteur, type, forme, atténuation et température de fermentation en plages,
  floculation ;
- divers : nom français, type.

La ligne « Nom français » est masquée quand la valeur est absente. Une autre valeur absente
s'affiche « Non renseigné ». Une valeur que l'application ne sait pas traduire s'affiche
telle quelle. Section « Provenance » : une ligne courte par source, sans doublon,
« Brewtarget 5.2.3 · licence GPL-3.0 · relevé le 8 novembre 2026 » ou « DIY Dog · licence DIY
Dog (usage privé) · relevé le 8 novembre 2026 », et le lien « Sources des données », qui
donne le fichier et le commit. Le texte de la fiche est sélectionnable.

**Recettes publiques.** Les recettes DIY Dog, par pages de 50 dans l'ordre alphabétique.
Chaque ligne : nom, puis style · volume · « 4,5 % vol annoncés ». « Afficher les recettes
suivantes » lit la page suivante. « Rechercher par début de nom » (aide : « Le début du nom.
Validez pour chercher. ») cherche les noms qui commencent par le texte, sans tenir compte des
majuscules, des accents ni de la ponctuation, quand le membre valide (Entrée ou flèche
« Rechercher »), jamais à la frappe. Sans résultat : « Aucune recette ne commence par
« {texte} ». » et « Effacer la recherche ». Une recette illisible s'affiche « Recette
illisible · L'erreur est signalée à l'administrateur. ». Si la page suivante ne peut pas être
lue, la liste reste et le bandeau « Impossible de lire la page suivante. » propose
« Réessayer ».

**Fiche d'une recette publique** (`/bibliotheque/recettes/{id}`, titre « Recette
publique »). Nom, style, « Recette publique · DIY Dog », « Voir le style » quand le style est
reconnu dans la liste BJCP (ouvre sa fiche par-dessus ; les recettes DIY Dog n'en ont pas),
bouton « Dupliquer » et « Dupliquer copie la recette dans vos recettes, pour la modifier et la
brasser. ». Puis :

- « Annoncé par la source » : « Valeurs données par la recette d'origine. Kass'Beer ne les a
  pas calculées. », puis densité initiale, densité finale, degré, amertume et couleur
  annoncés (« Aucune valeur annoncée. » sans valeur) ;
- « Calculs » : les cinq tuiles de la fiche d'une recette, calculées sans équipement. Quand
  des valeurs manquent, un seul message remplace la liste « À compléter » : « Ces valeurs
  manquent à la recette d'origine (équipement, durées, forme des houblons) : dupliquez-la pour
  les compléter. » ;
- « Général » : type de recette, auteur (« BrewDog »), volume, durée d'ébullition ;
- malts et sucres, houblons, autres ajouts, levure, paliers et notes, comme la fiche d'une
  recette. Un houblon sans forme porte « forme non renseignée ». Un houblon dont la source ne
  donne pas la durée porte « moment d'origine : … », traduit avec la valeur de la source entre
  parenthèses : « début d'ébullition (start) », « milieu d'ébullition (middle) », « fin
  d'ébullition (end) », « houblonnage à cru (dry hop) », « whirlpool (Whirlpool) » ; une
  autre valeur s'affiche telle quelle (« FWH ») ;
- « Provenance », comme la fiche d'une entrée.

Aucun coût : une recette publique n'a pas de prix.

**Dupliquer** (tout membre). Le bouton affiche « Duplication » pendant la lecture du nom du
compte (3 s au plus). La recette est créée au nom du lecteur, avec le même nom, les mêmes
ingrédients, paliers et notes, l'auteur « BrewDog » et l'origine « DIY Dog · diydog-{id} ».
Elle n'a ni équipement ni chronologie. Un houblon sans forme reste sans forme : l'éditeur la
demande (« Choisissez une forme. ») quand la ligne est modifiée, et le calcul affiche « Forme
du houblon à compléter : {noms}. » tant qu'elle manque. Le message « Recette dupliquée dans
vos recettes. » (« Recette dupliquée sur l'appareil. Elle partira au retour du réseau. » hors
ligne) s'affiche, puis l'éditeur de la nouvelle recette s'ouvre par-dessus la fiche ;
« Fermer » revient à la fiche, « Enregistrer » ouvre la recette. Un refus du serveur affiche
« La duplication de « {nom} » a échoué. ». La recette publique ne change pas.

**États.** Chargement : indicateur « Chargement de la bibliothèque » (« Chargement des
recettes publiques », « Chargement de la fiche »). Segment vide : « Aucun houblon dans la
bibliothèque pour l'instant. L'administrateur la remplit. » (de même : « Aucun style… »,
« Aucun malt ni sucre… », « Aucune levure… », « Aucun ajout divers… ») et « Aucune recette
publique pour l'instant. ». Lecture impossible : « Impossible de lire la bibliothèque.
L'erreur est signalée à l'administrateur. » et « Réessayer ». Liste illisible : « Cette liste
ne peut pas s'afficher. L'erreur est signalée à l'administrateur. ». Fiche : « Cette fiche
n'existe pas ou a été retirée. », « Cette fiche ne peut pas s'afficher. … », « Impossible de
lire cette fiche. … », avec « Revenir à la bibliothèque » (« Revenir aux recettes
publiques »). Chaque panne et chaque document illisible est journalisé.

**Hors ligne.** La Bibliothèque est une consultation en ligne. Ce qui a déjà été lu reste
lisible depuis le cache. Sinon : « Bibliothèque indisponible hors ligne. Elle s'ouvre au
retour du réseau. » et « Réessayer » (« Fiche indisponible hors ligne. Elle s'ouvre au retour
du réseau. » pour une fiche), jamais un segment vide. Une liste de recettes lue du cache
porte « Hors ligne : liste lue sur l'appareil. Elle peut être incomplète. ». « Dupliquer »
marche hors ligne, comme la création d'une recette. Le jour de brassage ne lit rien de la
Bibliothèque.

### Sources des données

Ouvert depuis la Bibliothèque, depuis la section « Provenance » d'une fiche et depuis le menu
du compte, pour tout membre (adresse `/sources-des-donnees`). Plein écran, hors de la barre de
navigation, titre « Sources des données » et flèche retour (vers l'écran d'origine ; ouvert
par son adresse, vers la Bibliothèque). Texte sélectionnable, livré avec l'application : il
s'affiche sans réseau.

- « La Bibliothèque reprend des données publiées par d'autres. Voici leurs auteurs, leurs
  licences et ce que Kass'Beer en a changé. Chaque fiche indique sa source et sa licence. »
- Brewtarget : malts, sucres, houblons, levures et ajouts divers, noms et valeurs techniques
  des fichiers 001 à 005 de Brewtarget v5.2.3 (commit ea10908), licence GPL-3.0, sans notes
  ni descriptions.
- BJCP 2021 : noms, codes, catégories et plages chiffrées des styles, lus dans le fichier 002
  de Brewtarget, sans descriptions.
- beer-analytics.com : une partie des ingrédients du fichier 005 de Brewtarget, sous licence
  CC BY-SA 4.0, « Modifications : unités normalisées, doublons fusionnés. », l'adresse
  `https://creativecommons.org/licenses/by-sa/4.0/` en texte et le bouton « Lire la licence
  CC BY-SA 4.0 », qui l'ouvre hors de l'application. Si le système refuse : « Impossible
  d'ouvrir le lien. Il reste sélectionnable sur cette page. », et l'échec est journalisé.
- DIY Dog : recettes DIY Dog publiées par BrewDog, reprises pour un usage privé (version
  e6c12ab de leur transcription).

### Brassins

**Nouveau brassin** (fiche d'une recette, tous les membres). « Nom du brassin » (prérempli, 120
caractères), « Équipement » (les siens puis ceux du groupe avec leur auteur ; présélection :
celui de la recette, sinon son seul équipement ; obligatoire : « Choisissez un équipement. » ;
hors ligne sans équipement lu : « Équipement indisponible hors ligne. Reconnectez le téléphone
pour créer le brassin. »), « Processus », « Date prévue (facultatif) » (aujourd'hui par défaut,
effaçable), « Déroulé prévu ». Le brassin reçoit une copie de la recette et de l'équipement : la
recette peut changer ensuite, le brassin garde sa version.

« Processus » propose « Chronologie de la recette seule » puis les seuls processus du lecteur,
par nom ; aucun processus d'un autre membre n'est proposé. Présélection : le processus par
défaut du lecteur (« Mes processus »), sinon « Chronologie de la recette seule ». Aide :
« Ajoute les étapes de préparation et les journées après le brassage. ». Lien « Gérer mes
processus » (ferme le formulaire, ouvre « Mes processus »). États : « Lecture des processus »
(la création reste possible avec la chronologie seule) ; « Impossible de lire les processus. »
avec « Réessayer » ; « Aucun processus. » avec « Créer un processus » ; « Votre processus par
défaut a été supprimé. » ; hors ligne sans processus lu : « Processus indisponibles hors ligne.
Créez le brassin avec la chronologie de la recette seule, puis choisissez son processus sur sa
fiche au retour du réseau. » (texte d'information, pas d'erreur). Un processus qui ne
s'applique pas à la recette affiche sa cause et ne crée rien ; l'erreur est rapportée :
« La chronologie de cette recette est illisible. », « Ce processus donne plus de 120 étapes dans
la journée « {nom} ». Retirez des étapes du processus. », « Ce processus est invalide : corrigez-le dans Mes processus. », « Un
houblon à cru de cette recette a un jour d'ajout hors de 0 à 365 jours. ».

« Déroulé prévu » se recalcule à chaque changement de processus ou de date. Une ligne par
journée : « Brassage · sam. 21 nov. · 14 étapes · 6 h 10 », « Houblonnage à cru · mer. 25 nov.
(J+4) · 4 étapes », « Embouteillage · sam. 5 déc. (J+14) · 7 étapes » ; sans date prévue,
« Houblonnage à cru · J+4 · 4 étapes » ; jour d'ajout donné par la recette : « (J+3, jour fixé
par la recette) ». Les lignes se lisent telles quelles au lecteur d'écran ; « Déroulé prévu :
{processus}, 3 journées. » et les annonces sont relues à chaque changement (région live). Annonces :
« Houblons à cru du J+8 regroupés au J+6 : 5 journées au plus. », « La recette a 2 houblons à
cru. Ce processus n'a pas de journée pour eux. », « Recette sans houblon à cru : pas de journée
« Houblonnage à cru ». » (de même « Recette sans ajout à l'embouteillage : pas de journée
« {nom} ». » pour une journée d'embouteillage conditionnée à ses ajouts), « Chronologie de la
recette vide : paliers et ébullition préremplis. » suivie des avertissements du préremplissage
(« « Empâtage » : durée non renseignée, étape non ajoutée. »). Avec « Chronologie de la recette
seule », le texte de la chronologie reste celui d'avant : recette sans chronologie, le brassin
se crée sans étape à suivre.

Création : le brassin s'écrit, puis son déroulé, sans attendre le serveur, hors ligne compris.
Messages : « Brassin créé. », « Brassin créé sur l'appareil. Il partira au retour du réseau. »,
« La création de « {nom} » a échoué. ». Déroulé seul refusé : « Le déroulé de « {nom} » a été
refusé. Choisissez de nouveau le processus sur la fiche. ».

**Liste** (tous les brassins du groupe). En cours, puis En fermentation et En conditionnement,
puis prévus par date croissante, puis Terminés et Abandonnés, chaque groupe du plus récent au plus
ancien. « Tous » / « Les miens », non enregistré. Chaque ligne :
nom, « {statut} · {équipement} · {auteur} », date (« Prévu le sam. 15 nov. 2026 », « Commencé
aujourd'hui à 11:15 », « Brassé le 11 févr. 2024 », « Embouteillé le 3 déc. 2026 » en
conditionnement), étiquette « En attente du réseau ». En fermentation et en conditionnement, un
brassin qui a une journée après le brassage à venir affiche « Prochaine journée : Houblonnage à
cru, mer. 25 nov. » ou « Prochaine journée : Houblonnage à cru, aujourd'hui » à la place de sa
date. Pour les brassins du lecteur, la journée annoncée est celle que la fiche lui propose : la
première journée non terminée placée après la dernière journée terminée. Une journée faite avant
sa date n'est plus annoncée : la suivante l'est. Une journée commencée et pas terminée s'affiche
« Prochaine journée : Houblonnage à cru, en cours ». Une journée dont la date est passée, pas
commencée, s'affiche « Prochaine journée : Houblonnage à cru, en retard (prévue le
mer. 25 nov.) ». Une fois le brassin embouteillé, l'embouteillage compte comme fait : une
journée placée après lui dans le déroulé (« Dégustation ») reste annoncée ; sans journée
d'embouteillage dans le déroulé, aucune ne l'est. Aucune journée restante : la ligne reprend la
date du brassin (« Embouteillé le … »). Pour les brassins des autres membres, et pour les siens
tant que ses saisies ne sont pas lues (chargement sans copie sur l'appareil, lecture en échec),
la ligne suit les dates seules : la première journée dont la date n'est pas passée, parmi celles
placées après l'embouteillage une fois le brassin embouteillé. Vide :
« Aucun brassin. Ouvrez une recette et appuyez sur Nouveau brassin. ». Statuts : Prévu, En
cours, En fermentation, En conditionnement, Terminé, Abandonné.

**Fiche.** Nom, ligne de statut (« En fermentation · J+12 », « En conditionnement · Embouteillé
le 3 déc. 2026 », « Terminé · Embouteillé le 3 déc. 2026 »), lien vers la recette, « Brassin de
{auteur} » pour un autre membre. Prévu et En cours : bloc Calculs sur la copie figée, Déroulé
(voir ci-dessous), sections de la recette figée, Général (date prévue, brassé le,
équipement). Après le brassage, dans l'ordre : en fermentation, Relevé, Prévu et mesuré, Notes ;
en conditionnement, Prévu et mesuré, Embouteillage, Relevé, Notes ; terminé, Prévu et mesuré,
Embouteillage, Notes, Relevé ; abandonné, Relevé, Prévu et mesuré, Embouteillage (si `bottled_at`
existe), Notes. Puis Général, le pli « Déroulé » (fermé, résumé « 3 journées », ou le nombre
d'étapes d'un déroulé d'une seule journée), le pli « Recette et calculs prévus »
(fermé sur téléphone, ouvert à partir de 840 pixels). Un brassin en cours affiche aussi le relevé
s'il en existe un. Pour le propriétaire seul, le bloc « Coût » (voir « Coût ») suit
l'Embouteillage quand il existe (Terminé : avant les Notes), sinon Prévu et mesuré ; prévu et en
cours, il suit Général. Un autre membre, administrateur compris, ne voit ni ce bloc ni son titre. Propriétaire : « Préparer le brassage » (prévu), « Reprendre le brassage » (en
cours), « Marquer comme terminé » (en conditionnement), « Reprendre ce brassin » (abandonné).
En fermentation et en conditionnement, un brassin dont une journée après le brassage n'est pas
terminée affiche au-dessus « Prévue le mer. 25 nov. » ou « Prévue aujourd'hui », puis le bouton
« Préparer la journée « Houblonnage à cru » » (« Reprendre la journée « Houblonnage à cru » »
une fois commencée, qui ouvre l'écran de la journée) : la première journée non terminée placée
après la dernière journée terminée, dans l'ordre du déroulé. Une journée non terminée placée
avant une journée terminée n'est plus proposée. Une fois le brassin embouteillé, seule une
journée placée après la journée d'embouteillage reste proposée (en conditionnement) ; sans
journée d'embouteillage dans le déroulé, aucune ne l'est. La liste des brassins annonce la même
journée. « Marquer
comme terminé » et « Ajouter un relevé » passent alors en bouton secondaire. Avec une journée
d'embouteillage, « Embouteiller » quitte la fiche et passe dans le menu ⋮ : « Embouteiller sans
suivre la journée » (en fermentation), qui ouvre le même formulaire. À
partir de En cours, le menu ⋮ (« Plus d'actions ») porte « Modifier » (nom, date prévue, notes ;
quitter avec une modification : « Les modifications de ce brassin ne seront pas enregistrées. »),
« Revenir à {statut} », « Abandonner ce brassin » et « Supprimer » selon le statut ; un brassin
prévu garde ses boutons « Modifier » et « Supprimer ». Un appui sur une mesure ouvre sa correction.
Autre membre : aucun bouton, mêmes chiffres. La recette a changé depuis
la création : « La recette a changé depuis la création de ce brassin. Il garde la version du
{date}. » ; pour un brassin prévu sans saisie, « Recréer depuis la recette ».
« Préparé sur cet appareil » s'affiche quand la préparation a abouti pendant la session ; sans
cette information, rien ne s'affiche. « Recréer depuis la recette » applique de nouveau le
processus du brassin à la recette actuelle (« Son processus est appliqué de nouveau à la recette
actuelle. »). La confirmation dit d'avance quand ce n'est pas possible : « Son processus a été
supprimé : le nouveau brassin n'aura que la chronologie de la recette. », « Son processus ne
s'applique pas à la recette actuelle : le nouveau brassin n'aura que la chronologie de la
recette. », ou, sans processus lu sur l'appareil, « Son processus n'a pas pu être lu sur cet
appareil : le nouveau brassin n'aura que la chronologie de la recette. Pour le garder, annulez
et réessayez avec le réseau. » ; l'annonce est alors
« Brassin recréé depuis la recette, sans son processus. Choisissez de nouveau le processus sur
la fiche. ».

**Déroulé** (section de la fiche). En-tête « Processus : {nom du processus au moment du
choix} », ou « Chronologie de la recette seule » pour un brassin sans processus (brassins
antérieurs compris) ; « Modèle supprimé depuis ; ce brassin garde son déroulé. » quand le
processus d'origine n'existe plus. Journée de brassage : titre « Brassage · sam. 21 nov. »,
puis sa chronologie (heures, état, mesures ; un appui sur une mesure ouvre sa correction).
Journées suivantes, repliées : « Houblonnage à cru · mer. 25 nov. (J+4) », résumé « 4 étapes ·
25 min », étapes « nom · durée » ; « (J+3, jour fixé par la recette) », « (J+6, date
changée) » ; sans date de départ, « Houblonnage à cru · J+4 ». Les dates partent de la date du
brassage, sinon de la date prévue. Avant le départ, pour le propriétaire : « Changer de
processus » (feuille : liste des processus du lecteur et déroulé prévu, « Appliquer » ;
« Déroulé changé. », hors ligne « Déroulé changé sur l'appareil. Il partira au retour du
réseau. »). La feuille présélectionne le déroulé actuel : son processus, ou « {nom} (actuel) »
quand il n'est pas dans la liste lue (processus supprimé, liste en lecture, en panne ou hors
ligne), avec l'aperçu du déroulé actuel, dates changées comprises. Hors ligne sans processus
lu, la feuille affiche « Processus indisponibles hors ligne. Changez de processus au retour du
réseau. » ; « Votre processus par défaut a été supprimé. » ne s'affiche que dans « Nouveau
brassin ». « Appliquer » reste inactif,
avec « Choisissez un autre processus. », tant que le choix ne diffère pas du déroulé actuel ;
pendant la lecture, en panne ou hors ligne, seul « Chronologie de la recette seule », choisi par
le brasseur, s'applique ; le menu ⋮ d'une journée après le brassage porte « Changer la date » (sélecteur du
jour du brassage à J+365 ; sans date de départ, « Écart (jours après le brassage) ») et
« Rétablir la date du processus » quand la date a été changée et que le processus d'origine se
lit encore ; annonce « « Houblonnage à cru » prévu le ven. 27 nov. », hors ligne « Date de
« Houblonnage à cru » changée sur l'appareil. Elle partira au retour du réseau. ». Changer la date prévue
du brassin déplace toutes les journées. Après le départ : aucun bouton, « Le déroulé est figé
depuis le début du brassage. ». Autre membre : lecture seule. Déroulé illisible : « Déroulé
illisible. Mettez l'application à jour, ou prévenez l'administrateur. », rapporté, sans repli
sur la chronologie de la recette. Une journée après le brassage commencée (une étape commencée
ou sautée, ou une mesure saisie sur l'une de ses étapes) montre dans son pli sa chronologie :
heures, états et mesures sous leur étape, comme la journée de brassage ; un appui sur une mesure
ouvre sa correction (propriétaire). Les relevés « Sans étape » restent dans le relevé de
fermentation. Une journée terminée a pour résumé « Terminée · 3 faites, 1 sautée » (comptes
réels : faites, sautées, non faites), ou « Terminée » seul sans étape à compter. Pour le
propriétaire d'un brassin En fermentation ou En conditionnement, le menu ⋮ d'une journée après
le brassage non terminée, sans étape en cours, porte « Passer la journée » : « Passer la journée
« Houblonnage à cru » ? » / « Ses étapes non commencées seront marquées sautées. », « Garder la journée » /
« Passer la journée ». Chaque étape non commencée est marquée sautée, sans changement de statut ;
annonce « Journée « Houblonnage à cru » passée. », hors ligne « Journée « Houblonnage à cru »
passée sur l'appareil. Elle partira au retour du réseau. ». La journée d'embouteillage ne le
propose pas : « Embouteiller sans suivre la journée » en tient lieu.

**Prévu et réel** (Déroulé de la fiche, tous les lecteurs). Dès qu'une étape d'une journée a un
début et une fin, la journée passe en prévu et réel. La deuxième ligne de chaque étape devient
« Terminée · prévu 45 min · réel 57 min · +12 min » (écart « −5 min », « 0 min », « +1 h 15 » au-delà
d'une heure ; lu « 12 minutes de plus », « 5 minutes de moins », « sans écart »). Étape sautée
ou non faite : « prévu 45 min · réel — » (lu « pas de durée réelle ») ; à venir : « À venir · prévu
45 min » (lu « prévu 45 min ») ; en cours :
« réel en cours » ; commencée sans fin, ou restée en cours après la fin de la journée (brassage
terminé, journée terminée, brassin terminé ou abandonné) : « réel sans heure de fin ». Une
action de 0 min garde « Action ». La durée réelle d'une étape va de son premier début à sa
dernière fin retenue, arrondie à la minute la plus proche ; le prévu s'arrondit de même. Une
ligne « Durée totale : prévu 6 h 10 · réel 6 h 52, dont 32 min entre les étapes · +42 min » se place
sous le titre de la journée de brassage, et en tête du pli des journées suivantes (le résumé du pli
ne change pas). Le réel de la journée va du premier début à la dernière fin ; « dont … entre les
étapes » (écoulé moins la somme des réels des étapes) n'apparaît qu'à partir d'une minute. Étape
en cours : « réel en cours » ; étape sans fin : « réel inconnu : 1 étape sans heure de fin ». Lu :
« Durée totale : prévue 6 h 10, réelle 6 h 52 dont 32 minutes entre les étapes, 42 minutes de plus
que prévu. ». Aucune couleur : l'écart se lit au signe. Seuls le nombre et son unité (« 45 min »,
« 6 h 10 ») et l'espace avant « : » sont insécables : à 200 % sur un téléphone, la ligne se coupe
entre les mots, jamais au milieu d'un mot. Une journée jamais commencée garde son
affichage. Le prévu de la journée compte les étapes sautées. L'écran du jour et l'écran d'une
journée après le brassage ne changent pas. Un brassin sans processus (ancien, importé) montre
aussi ses durées quand ses étapes ont des heures.

**Mettre à jour mon processus avec ce brassin** (propriétaire). Bouton dans la section Déroulé,
sous « Le déroulé est figé depuis le début du brassage. », pour un brassin En fermentation, En
conditionnement, Terminé ou Abandonné dont le processus d'origine existe encore, appartient au
lecteur et a au moins une durée à reprendre. Il ne s'affiche jamais avec « Changer de
processus ». Processus en lecture, supprimé (« Modèle supprimé depuis ; ce brassin garde son
déroulé. »), d'un autre membre ou rien à proposer : pas de bouton. Hors ligne, processus absent
du cache : « Processus indisponible hors ligne. Mettez-le à jour au retour du réseau. ». Lecture en
panne : « Impossible de lire votre processus. » et « Réessayer ». Utilisable plusieurs fois : une
durée déjà reprise ne se propose plus. Un autre membre ne voit pas le bouton.

La feuille « Mettre à jour mon processus » montre « Processus : {nom} », l'aide « Cochez les durées
à reprendre. Les brassins existants gardent leur déroulé. », puis un groupe par journée du
processus, dans son ordre. Une étape du brassin se propose si elle vient d'une étape du processus
qui existe encore, si sa durée réelle est connue, de 1 à 600 min, et différente de la durée
actuelle du processus. Ligne : case décochée, nom actuel de l'étape dans le processus, « processus
30 min → réel 42 min ». Étape répétée sur plusieurs journées (houblonnage à cru 1 et 2) : en-tête
« Désinfection du matériel · processus 10 min », dans le style du titre d'une case, puis des
boutons radio « Garder 10 min » (choisi au départ), « réel 12 min · Houblonnage à cru 1 », « réel
9 min · Houblonnage à cru 2 », lus comme un groupe « Désinfection du matériel, processus
10 min » ; une journée sans valeur à proposer s'affiche en gris, sans bouton, avec sa raison
(« Houblonnage à cru 2 : pas de durée réelle », « Houblonnage à cru 1 : réel 10 min, déjà à cette
durée », « … : réel 0 min, hors de 1 à 600 min ») ; s'il ne reste qu'une valeur, une case avec le
nom de la journée. Sous la liste : « Non proposées : 2 sans durée réelle, 1 déjà à cette durée,
1 retirée du processus, 1 hors de 1 à 600 min. Les étapes tirées de la recette ne sont pas
proposées. » (raisons non nulles seules). Une étape du processus retirée depuis compte une fois,
même répétée sur plusieurs journées ; une étape sans lien avec le processus n'est pas comptée.
Si plus rien n'est à proposer pendant que la feuille est ouverte (processus changé ailleurs) :
« Aucune durée à reprendre. » et « Fermer » ; lecture en panne : « Impossible de lire votre
processus. », « Réessayer » et « Fermer » ; hors ligne sans cache : le message d'indisponibilité et
« Fermer ».
Sans coche : « Cochez au moins une durée. », bouton « Mettre à jour » inactif ; sinon « Mettre à
jour 1 durée », « Mettre à jour 3 durées ». Seule la durée des étapes choisies change dans le
processus ; le brassin, sa recette et les autres brassins ne changent pas. Processus invalide :
« Ce processus est invalide : corrigez-le dans Mes processus. » dans la feuille, rien n'est écrit.
Annonce « Processus « {nom} » mis à jour : 3 durées. » avec « Annuler » 10 s, qui réécrit les
durées d'avant (« Processus « {nom} » : 3 durées rétablies. », hors ligne « Processus « {nom} » :
3 durées rétablies sur l'appareil. Elles partiront au retour du réseau. », au singulier « 1 durée
rétablie… Elle partira… ») ; hors ligne « Processus « {nom} »
mis à jour sur l'appareil : 3 durées. Il partira au retour du réseau. » ; refus « L'enregistrement
de « {nom} » a échoué. ». Le dernier enregistrement l'emporte.

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
hors ligne passent. « Terminer la journée » ne change aucun statut ; « Embouteiller » depuis la
journée d'embouteillage passe le brassin En conditionnement, comme depuis la fiche.

**Brassin importé d'une fiche Excel** (Admin › Import, v0.6). Il appartient à l'administrateur
et se lit comme un brassin fini par « Terminer le brassage » : statut Terminé, date de brassage
à la première heure réelle de la fiche, étapes commencées sans fin, sans date d'embouteillage.
Ses notes commencent par « Notes de la fiche Excel » (en-tête recopié, remarques, quantités
réelles notées à côté) et ne portent ni prix ni prénom. Sa copie d'équipement n'a que son nom
et son type : la densité prévue est « à compléter », la densité mesurée, le degré mesuré et le
rendement réel restent calculés.

### Relevé de fermentation

Section « Relevé de fermentation » de la fiche, visible à partir de En fermentation, et dans tout
statut si un relevé existe. Relevés du plus récent au plus ancien ; sur téléphone, les 5 plus
récents puis « Voir les N relevés plus anciens ». Ligne : densité, température, écart au relevé
de densité précédent (« −3,0 pts »), puis « sam. 15 nov. 18:30 · J+5 », la note, et « En attente
du réseau ». Une densité ou une température saisie sur une étape d'une journée après le brassage
porte aussi sa journée et son étape : « mer. 25 nov. 09:20 · J+4 · Houblonnage à cru : Mesure
de densité ». J+N est l'écart en jours calendaires depuis le brassage. À partir de deux densités,
une courbe s'affiche au-dessus de la liste (densité en trait plein, température en pointillés,
légende écrite, info-bulle au toucher) ; sans date de brassage, seule la liste s'affiche. Une valeur
enregistrée que le calcul refuse affiche « Courbe indisponible : une valeur enregistrée est
refusée. » et la liste reste lisible.

Brassin importé d'une fiche sans relevé de fermentation : la densité finale de l'en-tête de la
fiche devient un relevé, daté par la fiche, sinon du jour du brassage + 28 jours à 12:00, avec la
note « Date estimée : jour du brassage + 28 jours. ». La date est fixée à la préparation du
fichier ; l'application n'en calcule aucune. Ce relevé compte dans la densité finale retenue.
Les relevés des fiches, qui n'ont pas d'heure, sont datés de 12:00.

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
par le serveur : Densité 1020,0 du 15 nov. 18:30. Elle n'est pas enregistrée. ». Un relevé sans
étape ne s'affiche pas dans le Déroulé, et une mesure du jour de brassage ne s'affiche pas dans
le relevé. Une mesure d'une journée après le brassage compte dans le relevé, la courbe et la
densité finale, jamais comme densité initiale automatique, et s'affiche aussi sous son étape ;
elle se corrige depuis la fiche (« Corriger le relevé ») ou depuis l'écran de la journée, sur le
même enregistrement.

États : « Chargement des relevés », « Impossible de lire les relevés. », « Aucun relevé. Appuyez
sur Ajouter un relevé. » (propriétaire qui peut en ajouter), « Aucun relevé. », « Relevés
indisponibles sur cet appareil hors ligne. ».

### Embouteillage

« Embouteiller » (propriétaire, En fermentation ; « Embouteiller sans suivre la journée » dans
le menu ⋮ quand le déroulé a une journée d'embouteillage ; ou « Embouteiller » en fin de journée
d'embouteillage, voir « Journée après le brassage ») ouvre le formulaire : « Date d'embouteillage »
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
se fige avec les prix et les frais déjà lus par la fiche, ou par « Préparer la journée » pour la
journée d'embouteillage, si tout est connu (voir « Coût »). Depuis la journée, l'application
revient sur la fiche, qui affiche les mêmes annonces.
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
(« Refroidissement · 8 nov. 15:20 · Dernière mesure », « Relevé J+12 · 20 nov. 18:30 · Choisie »,
« Houblonnage à cru · Mesure de densité · 26 nov. 09:20 · Dernière mesure » pour une mesure prise
sur une étape d'une journée après le brassage)
et « Changer » (propriétaire), qui liste les mesures possibles et, si une mesure est retenue, « Dernière mesure (automatique) ».
En fermentation sans choix : « Densité finale (dernière mesure) », et le degré suivi de
« provisoire ». Choisir une mesure écrit l'identifiant, jamais la valeur.

Indisponible, chaque raison nommée : « Aucune densité mesurée le jour du brassage. » (« Saisir la
densité initiale »), « Aucune densité mesurée en fermentation. », « Dépend de la densité
initiale. », « Dépend de la densité finale. », « Dépend des deux densités. ». Rendement :
« Aucune densité initiale mesurée. », « Aucun volume mesuré le jour du brassage. » (« Saisir le
volume en fermenteur »), « Rendement d'extrait non renseigné : {noms}. », « Indiquez si les ingrédients
ajoutés hors de l'empâtage étaient dans le moût à cette mesure. » (pour un autre membre : « Le
brasseur n'a pas indiqué si les ingrédients ajoutés hors de l'empâtage étaient dans le moût. »), « Nature inconnue dans la recette du brassin :
{noms}. Le rendement ne peut pas être calculé. » (malt ou sucre de type « Autre » d'une recette
importée) ; aucun malt : « Sans malt, le rendement ne s'applique pas. ». Si la copie contient
autre chose qu'un malt (sucre, extrait, miel, fruit, jus, type « Autre »), le propriétaire
répond à une question qui nomme ces ingrédients, tels que la recette les écrit : « Les
ingrédients ajoutés hors de l'empâtage (Candi, Miel) étaient-ils dans le moût à cette
mesure ? » (« L'ingrédient ajouté hors de l'empâtage (Candi) était-il… » pour un seul ; un
extrait de malt n'est pas empâté). Calcul impossible : « Calcul impossible : la densité finale dépasse la
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
fin vers 16:05 » ; avec un processus, « Brassage : 18 étapes · 6 h 10 · fin vers 16:05 » et
« Ensuite : Houblonnage à cru le mer. 25 nov., Embouteillage le sam. 5 déc. », ou « à J+4 »
sans date prévue), compte, écran gardé allumé, minuteurs (« Aucune alarme ne sonne écran
verrouillé : gardez l'écran visible. »). Réponse reçue : « Tout est prêt. Vous pouvez couper le
réseau. ». Sans réponse ni réseau : « Préparation impossible sans réseau. Le brassin est lisible
sur cet appareil, mais peut ne pas être à jour. ». « Commencer le brassage » passe le brassin « En
cours » avec l'heure de l'appareil, démarre la première étape si elle a une durée, et ouvre
l'écran du jour. Avec un processus, les étapes sont celles de la journée de brassage du
déroulé. Déroulé illisible : « Déroulé illisible. Mettez l'application à jour, ou prévenez
l'administrateur. » et « Commencer le brassage » bloqué. Sur le web : « Gardez cet onglet
ouvert. Une page rechargée sans réseau ne s'ouvre plus. ».

### Jour de brassage

Écran plein écran, réservé au propriétaire. L'écran reste allumé tant qu'il est ouvert. La
barre affiche le nom du brassin et l'heure de l'appareil, mise à jour avec le minuteur ; avec un
processus, la seconde ligne nomme la journée (« Brassage · 10:42 », lu « Journée Brassage, heure
actuelle 10:42 »), et l'écran suit les seules étapes de la journée de brassage du déroulé
(« Étape 3 sur 18 », « Fin prévue » de la journée). Quand le brassage
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

### Préparer la journée

Écran « Préparer la journée » d'une journée après le brassage (houblonnage à cru, embouteillage,
toute journée 2 ou suivante du déroulé), ouvert depuis la fiche, dans la barre de navigation,
retour vers la fiche. Titre : « Blonde · Houblonnage à cru · prévue le mer. 25 nov. » (« prévue
aujourd'hui »). « Préparez la journée sur le téléphone qui servira. ». Comme « Préparer le
brassage », il attend une réponse du serveur 15 s au plus, sans rien écrire, et liste :
« Brassin et déroulé figé », « Étapes » (« 4 étapes · 25 min · fin vers 10:40 »), compte, écran
gardé allumé, minuteurs, navigateur (web). Journée d'embouteillage : « Prix et frais », « Lus sur
l'appareil : le coût se figera à l'embouteillage. » ou « Prix indisponibles sur cet appareil hors
ligne. Le coût ne se figera pas. ». Informations : « Prévue le mer. 25 nov. Vous pouvez la
commencer aujourd'hui. » un autre jour que la date prévue ; « La journée « Houblonnage à cru »
n'est pas terminée. Ses étapes resteront non faites. » pour chaque journée précédente non
terminée. Réponse reçue : « Tout est prêt. Vous pouvez couper le réseau. » ; sinon
« Préparation impossible sans réseau. Le brassin est lisible sur cet appareil, mais peut ne pas
être à jour. ».

Bouton 72 px « Commencer la journée » : démarre la première étape si elle a une durée, sans
changer le statut du brassin, et ouvre l'écran de la journée ; « Reprendre la journée » une fois
commencée, sans rien écrire. Le bouton attend la lecture des saisies.

Refus, chacun avec « Voir le brassin » : autre membre « Seul le brasseur de ce brassin suit cette
journée. » ; brassin prévu ou en cours « Cette journée s'ouvre après la fin du brassage. » ;
embouteillage déjà fait « Cette journée est terminée. » ; brassin terminé « Ce brassin est
terminé. » ; abandonné « Ce brassin est abandonné. Reprenez-le pour suivre cette journée. » ;
journée absente du déroulé « Cette journée n'existe pas dans le déroulé de ce brassin. » ;
déroulé illisible « Déroulé illisible. Mettez l'application à jour, ou prévenez
l'administrateur. ».

### Journée après le brassage

Écran plein écran d'une journée 2 ou suivante, réservé au propriétaire (mêmes refus que
« Préparer la journée »), ouvert au statut En fermentation ou En conditionnement (En fermentation
seulement pour l'embouteillage). Il reprend l'écran du jour de brassage : barre « Blonde » puis
« Houblonnage à cru · 10:42 » (lu « Journée Houblonnage à cru, heure actuelle 10:42 »), panneau,
minuteurs, alerte de fin, étapes, corrections, « Fin prévue » de la journée, écran allumé. Départ
prévu de la journée : son premier début, sinon l'heure de l'appareil. Les étapes du brassage et
des autres journées n'y figurent pas et ne changent pas d'état.

Menu ⋮ : « Ajouter une note », « Voir la recette », puis « Terminer la journée » tant qu'il reste
une étape en cours ou à venir, ou « Embouteiller » pour la journée d'embouteillage. « Terminer la
journée » demande, s'il reste des étapes à venir, « Terminer la journée « Houblonnage à cru » ? »
/ « Les étapes non commencées seront marquées sautées. Vous pourrez encore corriger les
mesures. », « Continuer la journée » / « Terminer la journée » ; il termine l'étape en cours,
marque sautées les étapes à venir, et revient sur la fiche avec « Journée « Houblonnage à cru »
terminée. ». Quand la dernière étape est en cours, le bouton du bas devient « Terminer la
journée », sans confirmation. Toutes les étapes faites ou sautées : « Toutes les étapes sont
faites. Journée terminée. », bouton « Revenir au brassin », annonce « Journée « Houblonnage à cru »
terminée. » au lecteur d'écran.

**Journée d'embouteillage.** Le bouton du bas « Embouteiller » remplace « Terminer le brassage »
une fois toutes les étapes faites ; ⋮ « Embouteiller » reste possible à tout moment. S'il reste
des étapes : « Embouteiller maintenant ? » / « Les étapes non commencées resteront non faites. »
(« L'étape en cours se termine. Les étapes non commencées resteront non faites. » quand une
étape est en cours), « Continuer la journée » / « Embouteiller ». Puis le formulaire
d'embouteillage (voir « Embouteillage »), qui ne se ferme pas par un appui hors de la feuille ; à
l'envoi, l'étape en cours se termine à l'heure de l'envoi, les étapes non commencées restent
non faites, et l'application revient sur la fiche avec les annonces de l'embouteillage.

**Mesures.** Bouton « Mesure » : liste « Étape » limitée aux étapes de la journée, plus « Sans
étape » ; sous le type Densité ou Température, « Comptée dans le relevé de fermentation. », et,
après la date d'embouteillage, « Après l'embouteillage : ce relevé ne compte pas dans la densité
finale. ». « Mesure enregistrée. » avec « Annuler » 10 s. Une mesure s'affiche sous son étape ; une
mesure « Sans étape » du jour s'affiche sous « Sans étape » et compte comme un relevé de
fermentation ordinaire. Les notes de la journée sont aussi des notes du relevé.

### Hors ligne des journées

Les règles du « Hors ligne du jour de brassage » valent pour chaque journée après le brassage,
une fois « Préparer la journée » fait sur l'APK : étapes, mesures, notes, « Terminer la journée »
et l'embouteillage s'écrivent sur l'appareil sans attente ni erreur, pastille d'envoi comprise.
« Passer la journée » s'écrit aussi sans réseau. Prix, frais et coût figé lus à « Préparer la
journée » restent ouverts jusqu'à l'embouteillage ;
lus hors ligne sans cache, le coût ne se fige pas et l'embouteillage part quand même. La reprise
au lancement ne rouvre que le jour de brassage ; une journée se rouvre par la fiche. La liste des
brassins annonce, pour les brassins du lecteur, la journée que propose la fiche, d'après les
saisies lues sur l'appareil, y compris une journée placée après l'embouteillage ; sans saisies
lues, et pour les brassins des autres membres, elle suit les dates seules (voir « Liste »).

### Mes prix

« Mes prix » s'ouvre depuis le menu du compte (tout membre) : page pleine, hors de la barre de
navigation, avec retour. Chacun n'y voit que ses frais et ses prix. De haut en bas : « Mes
frais » (« 3 frais »), une ligne par frais triée par nom (« Électricité · 2,00 € par brassin »),
« Ajouter un frais » ; puis « Ingrédients », un pli par nature non vide (« Malts », « Sucres »,
« Houblons », « Levures », « Ajouts », résumé « 12 prix »), fermé sur téléphone, ouvert à partir
de 840 pixels. Ligne : « Pils », puis « 47,50 € les 25 kg · 1,90 €/kg » ; levure : « 3,99 € les
5 sachets · 0,80 €/sachet » ; prix au litre : « 6,50 € les 100 ml · 65,00 €/L » (« 30,00 € le
litre » pour 1 L). Le lecteur d'écran lit « 6,50 € les 100 millilitres, 65,00 € le litre »
(« 1 litre », « 1 millilitre » au singulier, « 1,90 € le kilogramme », « 0,80 € le
sachet »). Quantité en
kilogrammes à partir de 1 000 g, en millilitres sous 1 L. Montant saisi affiché
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
pour un malt ou un sucre, g pour un houblon ou un ajout) ; pour un houblon ou un ajout,
« Unité » propose aussi L et ml (v0.1.17 : prix au litre, enregistré en litres ; lus
« kilogrammes », « grammes », « litres », « millilitres »), choisis d'avance quand le prix
s'ouvre depuis une ligne mesurée en volume ; les quatre segments passent l'un sous
l'autre quand ils ne tiennent pas (360 dp à 150 % et au-delà), comme les choix de
l'éditeur. Sous l'unité, deux avertissements non bloquants : « Ce prix remplacera votre prix
au gramme, utilisé par les lignes pesées. » (ou « … votre prix au litre, utilisé par les
lignes en volume. ») quand la saisie remplace un prix de l'autre unité ; « Cette ligne est en
volume : un prix au gramme ne la comptera pas. » (ou « Cette ligne est pesée : un prix au
litre ne la comptera pas. ») quand le prix s'ouvre depuis une ligne d'une autre unité ;
« Quantité achetée (sachets) » pour une
levure (nombre entier). Tous sont obligatoires. Le prix 0 est un prix connu. Ligne de résultat :
« Soit 1,90 €/kg » (« €/sachet » pour une levure, « €/L » pour un prix au litre). « Prix
inhabituel : vérifiez la quantité. » au-delà de 50 €/kg pour un malt ou un sucre, 500 €/kg pour
un houblon ou un ajout, 50 € le sachet, 1 000 €/L, sans blocage. Nom sans lettre ni chiffre : « Le nom doit contenir une lettre ou un
chiffre. ». Nom dont le prix existe : « Un prix existe déjà pour « Pils ». Il sera remplacé. ».
« Corriger le prix » d'une unité incompatible laisse la quantité vide, avec « L'unité
enregistrée ne correspond pas : saisissez la quantité en kg. » (ou g, L, ml, ou sachets) ;
pour une ligne en volume face à un prix au gramme, la saisie s'ouvre en litres (et en grammes
dans le sens inverse). Un nom
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

### Mes processus

Un processus est un modèle de déroulé : de 1 à 5 journées (le brassage, puis par exemple le
houblonnage à cru et l'embouteillage), chacune avec son écart en jours depuis le brassage et
ses étapes de préparation et de nettoyage. Le groupe le lit ; seul son auteur le modifie. Le
brasseur le choisit dans « Nouveau brassin » ou sur la fiche d'un brassin prévu (voir
Brassins). Après le brassage, « Mettre à jour mon processus avec ce brassin » reprend dans son
processus les durées réelles qu'il coche (voir Brassins, Déroulé).

**Accès.** « Mes processus » s'ouvre depuis le menu du compte, sous « Mes prix » : page
pleine, hors de la barre de navigation, avec retour. Adresses : `/processus` (liste),
`/processus/nouveau`, `/processus/{id}` (fiche), `/processus/{id}/modifier`.

**Liste.** Titre « Mes processus ». Section « Mes processus » (les siens, par nom), puis
« Processus du groupe » (ceux des autres membres, par nom, avec leur auteur), masquée si elle
est vide. Ligne : nom, puis « 3 journées · J+0, J+4, J+14 ». Étiquette « Par défaut » sur le
processus choisi par défaut, « En attente du réseau » tant qu'une écriture n'a pas atteint le
serveur. Le lecteur d'écran lit chaque ligne d'un bloc : « {nom}, 3 journées, de {auteur}, par
défaut » ; le double appui ouvre la fiche. Bouton flottant « Nouveau processus » sur téléphone, bouton en tête au-delà ; une
colonne centrée sur 840 pixels.

- Chargement : « Chargement des processus ». Lecture impossible : « Impossible de lire les
  processus. », « Réessayer » et « Nouveau processus ». Une panne après une première lecture garde la liste, avec
  le bandeau « Mise à jour de la liste impossible. Elle peut ne plus être à jour. ».
- Aucun processus à soi : « Aucun processus. Un processus ajoute à vos brassins les étapes de
  préparation et de nettoyage, et les journées après le brassage. », avec « Partir du modèle
  d'exemple » et « Nouveau processus ». Le bouton flottant et le bouton en tête ne s'affichent
  pas en plus. La section du groupe reste dessous.
- Document illisible : ligne « Processus illisible » / « Le document contient une valeur
  inattendue. ». L'erreur est rapportée ; les autres processus restent affichés.
- Hors ligne : la liste vient du cache, les écritures attendent le réseau. Liste jamais lue
  sur l'appareil : « Processus indisponibles hors ligne. » et « Nouveau processus ».

**Modèle d'exemple.** « Partir du modèle d'exemple » ouvre « Nouveau processus » prérempli :
nom « Brassage, houblonnage à cru, embouteillage », notes « Durées typiques, à ajuster à votre
matériel. », trois journées (Brassage J+0 ; Houblonnage à cru J+4, seulement si la recette a
des houblons à cru ; Embouteillage J+14). Rien n'est écrit avant « Enregistrer » ; quitter
demande « Abandonner les modifications ? ». Il n'est proposé que si le lecteur n'a aucun
processus.

**Fiche.** Barre « Processus », retour vers la liste. Nom, « Processus de {auteur} » pour un
autre membre, notes. Une section par journée : « 1. Brassage · J+0 » ; la mention « Seulement
si la recette a des houblons à cru » (ou « … des ajouts à l'embouteillage ») si la journée en
dépend ; le résumé « 9 étapes · 4 h 15 + chronologie de la recette » (étapes du processus et
leur durée, puis le bloc), ou le bloc seul pour une journée sans étape (« Houblons à cru ») ; puis chaque étape (« Mise en place du matériel · 30 min ·
67 °C ») et chaque bloc tiré de la recette (« Chronologie de la recette », « Houblons à cru »,
« Ajouts à l'embouteillage »), sur fond `secondaryContainer`, lu « Bloc de la recette :
Houblons à cru ».

- L'auteur voit l'interrupteur « Proposer par défaut dans Nouveau brassin » (« Ce choix ne
  concerne que vous. »), « Modifier », « Supprimer » et, dans ⋮, « Dupliquer ». Pendant la
  lecture du choix, l'interrupteur est inactif, avec « Lecture du choix par défaut » ; en
  panne, « Impossible de lire votre choix par défaut. » et « Réessayer ». Annonces :
  « « {nom} » sera proposé par défaut. » / « Aucun processus proposé par défaut. ». Un seul
  processus est proposé par défaut ; le choix est privé.
- Un autre membre voit le seul bouton « Copier dans mes processus » (« Copie » pendant la
  lecture du nom du compte, 3 s au plus). La copie garde le nom, reçoit de nouvelles clés de
  journées et d'étapes, s'écrit au nom du lecteur et ouvre sa fiche : « Processus copié dans
  vos processus. » (hors ligne : « Processus copié sur l'appareil. Il partira au retour du
  réseau. »).
- « Dupliquer » crée « {nom} (copie) » et ouvre sa fiche : « Processus dupliqué. ». Pendant la
  lecture du nom du compte, ⋮ laisse place à « Duplication » : un second appui ne crée pas de
  seconde copie.
- Absent du serveur : « Ce processus n'existe pas ou a été supprimé. » et « Revenir à mes
  processus ». Absent du cache hors ligne : « Processus indisponible hors ligne. ».
  Illisible : « Processus illisible. Mettez l'application à jour, ou prévenez
  l'administrateur. », rapporté.

**Supprimer.** « Supprimer « {nom} » ? » / « Le processus disparaît pour tout le groupe. Les
brassins déjà créés gardent leur déroulé. », plus, si c'est le processus par défaut : « C'est
votre processus par défaut : Nouveau brassin proposera la chronologie de la recette seule. ».
Supprimer le processus par défaut remet le choix à « Chronologie de la recette seule », une
fois la suppression acceptée par le serveur ; refusée, le choix reste.
Annonce « Processus supprimé. ».

**Éditeur** (« Nouveau processus » / « Modifier le processus », plein écran, une colonne
centrée sur 920 pixels, « Enregistrer »). « Nom du processus » (obligatoire, 120 caractères ;
sinon « Donnez un nom au processus. », curseur sur le champ), « Notes (facultatif) »
(10 000 caractères). À la création seulement : « Proposer par défaut dans Nouveau brassin »,
coché si le lecteur n'a pas de processus par défaut. Tant que son choix n'est pas lu avec
certitude (lecture en cours, cache seul, document illisible, panne), l'interrupteur est
décoché et inactif, avec « Lecture du choix par défaut » ou « Votre choix actuel n'a pas pu
être lu. » : aucun défaut existant n'est remplacé. Un nouveau processus part de la journée
« Brassage » et de son bloc « Chronologie de la recette ».

- Journée 1 : fixe (ni retrait ni déplacement), « J+0, jour du brassage », bloc « Chronologie
  de la recette » d'office, non retirable (« Obligatoire dans la journée de brassage ») ;
  ⋮ « Renommer la journée » seul.
- Journées 2 à 5 : en-tête « 2. Houblonnage à cru · J+4 », lu « Journée 2 sur 3, Houblonnage
  à cru, J+4 » ; ⋮ « Modifier la journée », « Retirer la journée », et « Monter » ou
  « Descendre » seulement entre deux journées de même écart. Les journées se trient par écart à
  chaque changement ; un déplacement s'annonce (« « Embouteillage » passe en journée 3. »).
  Retirer une journée annonce « Journée « {nom} » retirée. » avec « Annuler ».
- Formulaire de journée (feuille du bas sur téléphone, dialogue au-delà) : « Nom de la
  journée » (obligatoire, 120 caractères, « Donnez un nom à la journée. »), « Écart (jours
  après le brassage) » (entier de 0 à 365, sans valeur d'avance : « Champ obligatoire. »,
  « Nombre entier attendu. », « Entre 0 et 365. »), aide « J+4 : quatre jours après le jour
  du brassage. Pour les houblons à cru, le jour fixé par la recette passe avant. » ;
  « Annuler », « Ajouter » ou « Enregistrer ».
- Étapes : le formulaire d'étape de la chronologie d'une recette (nom de 120 caractères, durée
  de 0 à 600 min, température de 0 à 100 °C). Ligne « 2. Désinfection du fermenteur » /
  « +30 min · 20 min · 67 °C ». Après la chronologie de la recette, dont la durée n'est connue
  qu'au brassin, le décalage se compte depuis elle (« +20 min après la chronologie de la
  recette »). Poignée de déplacement dans la journée ; l'éditeur défile pendant le
  glisser ; ⋮ « Monter », « Descendre »,
  « Dupliquer », « Retirer » (« « {nom} » retiré. » avec « Annuler »). Un déplacement
  s'annonce au lecteur d'écran (« « {nom} » en position 3. »). Une étape ne change pas de
  journée.
- Blocs : « Insérer un bloc de la recette » (journées 2 et suivantes) propose « Houblons à
  cru » et « Ajouts à l'embouteillage », chacun une fois dans le processus, un seul par
  journée. Un bloc déjà placé est inactif (« Déjà dans « Houblonnage à cru » ») ; un second
  bloc dans la même journée aussi (« Une journée porte un seul bloc de la recette. »). La ligne
  d'un bloc n'a pas de formulaire ; ⋮ « Monter », « Descendre », « Retirer ». Une insertion
  s'annonce au lecteur d'écran (« Houblons à cru ajouté en position 4. »). Sous la ligne du
  bloc, qu'il suit quand le bloc se déplace : « Seulement si la recette en a » (« Sans houblon à cru dans la
  recette, le brassin n'aura pas cette journée. » ou « Sans ajout à l'embouteillage dans la
  recette, le brassin n'aura pas cette journée. ») ; retirer le bloc éteint l'interrupteur.
- Bornes : « 60 étapes au plus dans une journée. » (blocs compris, boutons inactifs) ;
  « 5 journées au plus. » au-dessus du bouton inactif « Ajouter une journée ».
- Enregistrer : une journée sans étape est refusée (« La journée « {nom} » n'a aucune
  étape. », l'éditeur défile jusqu'à elle). Annonces « Processus enregistré. », hors ligne
  « Processus enregistré sur l'appareil. Il partira au retour du réseau. », refus
  « L'enregistrement de « {nom} » a échoué. ». La fiche s'ouvre. Quitter avec des
  changements : « Abandonner les modifications ? » / « Les changements de ce processus ne
  seront pas enregistrés. ».
- Un autre membre sur l'adresse de modification : « Seul l'auteur modifie ce processus. » et
  « Voir le processus ».

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
ligne par raison : « Pils · 5 kg » et « Saisir le prix » ; prix d'une autre unité que la
ligne : « {ligne} : votre prix est {au sachet, au gramme, au litre}. Saisissez un prix {unité
de la ligne} pour compter cette ligne. » (« Pils · 5 kg : votre prix est au sachet. Saisissez
un prix au gramme pour compter cette ligne. », « S-04 · 1 sachet : votre prix est au litre.
Saisissez un prix au sachet… ») et « Corriger le prix », lu par le lecteur d'écran avec la
quantité en toutes lettres ; « Pils : prix illisible. » et « Corriger le prix » ; pour un
houblon ou un ajout mesuré en volume, un prix au litre la chiffre (litres × prix par litre) ;
sans prix, « Acide lactique · 5 ml » et « Saisir le prix au litre » ; face à un prix au
gramme, « Acide lactique · 5 ml : votre prix est au gramme. Saisissez un prix au litre pour
compter cette ligne. » ; une ligne pesée face à un prix au litre, « Acide lactique · 5 g :
votre prix est au litre. Saisissez un prix au gramme pour compter cette ligne. » (aucune
densité n'est supposée) ; deux lignes de même nom, l'une en grammes et l'autre en volume : « Cascade :
quantités en grammes et en volume, qui ne s'additionnent pas. », suivi, pour l'auteur, de
« Mettez les deux lignes dans la même unité. » et « Compléter la recette », pour un autre
membre, de « Dupliquez la recette pour la corriger à votre nom. » ; « Volume en fermenteur
non renseigné. » (et « Compléter la recette » pour l'auteur) ; « Une ligne de cette recette n'a
pas de nom utilisable. » ; « Un de vos frais est illisible : il ne peut pas être compté. » et
« Ouvrir Mes prix ». « Saisir le prix » ouvre le formulaire de prix sans quitter la recette, pour
tout lecteur ; à l'enregistrement, la ligne sort de la liste et le focus revient sur l'en-tête ;
au dernier prix, le montant apparaît. Autres états : « Chargement de vos prix », « Impossible de
lire vos prix. » et « Réessayer », « Prix indisponibles sur cet appareil hors ligne. » (jamais
« manquant »), « Aucun ingrédient. » (jamais « 0,00 € »), « Calcul du coût impossible. » dans un
cadre d'erreur.

**Brassin importé d'une fiche Excel** (v0.6). Son coût est figé à l'import avec les prix et
les frais notés dans la fiche, pas avec « Mes prix » ni « Mes frais », qui ne changent pas ; il
est daté du jour du brassage et garde le nombre de bouteilles, le volume conditionné et la
nature du sucre de la fiche. Un prix manquant, ou un frais par bouteille sans nombre de
bouteilles, laisse le coût non figé : « Figer le coût » reste disponible sur le brassin.

**Brassin** (bloc « Coût », propriétaire seul). Tant que rien n'est figé : « Coût estimé avec
vos prix actuels », calculé sur la copie figée de la recette et le sucre de resucrage, « Total »,
« Par bouteille (50 bouteilles) » ou « Bouteille de 33 cl », « Par litre », l'hypothèse « Pour
20 L · 50 bouteilles » ou « Pour 20 L · environ 61 bouteilles de 33 cl, nombre de bouteilles non
renseigné », le détail. Ouvrir la fiche n'écrit rien.

En conditionnement, Terminé et Abandonné, sans coût figé : « Coût non figé », l'estimation ou ses
raisons, recalculées à l'affichage (manquants et « Saisir le prix » ; « Nature du sucre de
resucrage non renseignée. » et « Modifier l'embouteillage » ; « Nombre de bouteilles non
renseigné : les frais par bouteille ne peuvent pas être comptés. » et « Renseigner les
bouteilles », ces deux actions en En conditionnement et Terminé ; une ligne en volume se
chiffre et se fige avec un prix au litre, comme une autre ligne ; sans action possible sur
place, « Ce brassin compte {nom} en volume : saisissez un prix au litre dans Mes prix pour
figer son coût. » et « Ouvrir Mes prix » ; deux lignes de même nom en grammes et en volume :
« Ce brassin compte {nom} en grammes et en volume : ces quantités ne s'additionnent pas, son
coût ne peut pas être figé. » ; « Prix indisponibles sur cet
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

- Densité initiale : volume en fermenteur, au moins un malt ou sucre, la nature et le
  rendement d'extrait de chacun, et le rendement d'empâtage de l'équipement si la recette
  contient un malt. Un extrait liquide ou sec, un miel, un fruit ou un jus compte comme un
  sucre (100 % de son extrait, sans empâtage) ; « Autre » demande sa nature.
- Densité finale : densité initiale et atténuation de la levure. Degré : à partir des deux
  densités, avant refermentation en bouteille.
- Amertume (Tinseth) : volume ; un houblon d'ébullition demande ses acides alpha, sa durée,
  et la densité initiale (densité d'ébullition retenue). Sans houblon d'ébullition,
  l'amertume vaut 0 IBU, même sans densité initiale. Whirlpool et à cru comptent 0 IBU.
  Un houblon à l'empâtage ou au conditionnement rend l'amertume indisponible ; un houblon
  d'ébullition en poudre, en extrait ou en cônes frais aussi. Des cônes pressés se
  calculent comme des cônes. Un houblon mesuré en volume ne compte pas dans l'amertume :
  il apporte 0 IBU, ne demande rien, et la ligne « Non compté dans l'amertume (mesuré en
  volume) : {noms}. » s'affiche sous les hypothèses ; sa ligne et « Détail des calculs »
  portent « non compté dans l'amertume (mesuré en volume) ».
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
- « Nature à préciser : {noms}. » (malt ou sucre de type « Autre »), « Moment non pris en
  charge par le calcul : {noms}. » (houblon à l'empâtage ou au conditionnement), « Forme non
  prise en charge par le calcul : {noms}. » (houblon d'ébullition en poudre, en extrait ou en
  cônes frais), « Forme du houblon à compléter : {noms}. » (houblon d'ébullition sans forme,
  copié d'une recette publique)

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
- L'import marche sans réseau : les recettes sont créées sur l'appareil, partent au retour
  du réseau, et un refus du serveur s'annonce dans le compte rendu, ou en un seul message
  après la sortie de l'écran. « Déjà importée » se lit dans les recettes en cache.
- L'export marche sans réseau si la recette et son équipement sont dans le cache ; sinon
  « Équipement indisponible hors ligne. » bloque l'export.

### Configuration absente

Une version compilée sans configuration Firebase affiche « Configuration Firebase absente »
et la liste des clés manquantes, au lieu de démarrer.
