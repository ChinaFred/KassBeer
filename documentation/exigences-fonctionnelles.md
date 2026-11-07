# Exigences fonctionnelles

État actuel du produit. L'historique vit dans `CHANGELOG.md`.

## Rôles et droits

Un compte n'ouvre l'application que si l'administrateur l'a invité : un document
`members/{e-mail}` existe pour l'adresse de son compte Google. Aucun e-mail n'est envoyé à
l'invitation.

| Rôle | Peut |
|---|---|
| `brewer` (Brasseur) | se connecter ; ouvrir Recettes, Brassins et Équipements ; voir son nom, son e-mail et la version dans le menu du compte ; se déconnecter |
| `admin` (Administrateur) | tout ce que peut un brasseur ; ouvrir Admin ; inviter un compte (adresse, nom facultatif, rôle) ; retirer un brasseur. Il ne peut ni se retirer lui-même, ni retirer un autre administrateur : un administrateur se retire depuis la console Firebase |
| compte non invité | voir l'écran « Compte non invité », copier son adresse, vérifier à nouveau, se déconnecter. Rien d'autre |

Pas de changement de rôle : l'administrateur retire le compte puis le réinvite. Seul
l'administrateur saisit le nom d'un membre. Retirer un compte ne supprime ni ses recettes ni
ses brassins, qui restent visibles du groupe.

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

Recettes, Brassins et Équipements ne contiennent encore qu'un message : « Les recettes
arriveront dans une prochaine version. », et de même pour les brassins et les équipements.

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

### Configuration absente

Une version compilée sans configuration Firebase affiche « Configuration Firebase absente »
et la liste des clés manquantes, au lieu de démarrer.
