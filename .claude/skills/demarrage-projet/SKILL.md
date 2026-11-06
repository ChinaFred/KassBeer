---
name: demarrage-projet
description: "Démarrer un projet neuf à partir de ce réseau d'agents — recueillir l'intention fonctionnelle, les utilisateurs et les contraintes (local, réseau protégé ou ouvert, données, budget, plateformes), puis faire choisir la pile par l'agent architecte et remplir CLAUDE.md. À utiliser au premier travail sur le dépôt, quand on demande « démarre le projet », ou dès qu'une demande de code arrive alors que la section « Le projet » de CLAUDE.md contient encore ses chevrons."
---

# Démarrer un projet

La session principale conduit ce skill : elle seule peut poser des questions à
l'utilisateur. L'`architecte` travaille ensuite sur le brief qu'elle lui transmet.

Aucune ligne de code applicatif n'est écrite avant l'étape 5.

## 1. Recueillir l'intention

Poser les questions par petits groupes (trois ou quatre à la fois, avec l'outil de questions
quand il existe), et reformuler les réponses avant de passer au groupe suivant. Une réponse
« je ne sais pas » est une réponse : la noter comme question ouverte.

**But fonctionnel**

- Quel problème le projet résout-il, pour qui ? En une phrase.
- Que fait un utilisateur lors d'une visite type, du début à la fin ?
- À quoi verra-t-on, dans six mois, que le projet a réussi ?
- Qu'est-ce qui est explicitement hors du périmètre ?
- Existe-t-il un outil actuel (tableur, logiciel, papier) que le projet remplace ? Des
  données à reprendre ?

**Utilisateurs**

- Combien d'utilisateurs, et combien en même temps ?
- Quels rôles (lecture seule, contributeur, administrateur…) ?
- Sur quels appareils, dans quelles conditions (mobilité, bureau, atelier, hors connexion) ?
- Quelle langue, quelle accessibilité requise ?
- Quelle formule d'adresse les agents emploient-ils en tête de réponse (section « Ton » de
  `CLAUDE.md`) ?

## 2. Recueillir les contraintes

**Exposition et environnement**

- Le projet tourne-t-il **en local** (une machine, sans réseau), sur un **réseau protégé**
  (réseau d'entreprise, VPN, accès derrière un SSO), ou **ouvert sur Internet** ?
- Qui peut créer un compte : tout le monde, sur invitation, comptes fournis par une
  organisation ?
- Y a-t-il une infrastructure imposée (cloud de l'entreprise, serveur existant, fournisseur
  d'identité, base de données) ?

**Données**

- Quelles données sont manipulées ? Y a-t-il des données personnelles, de santé, financières,
  confidentielles ?
- Une réglementation s'applique-t-elle (RGPD, hébergement en Europe, secteur réglementé) ?
- Qui doit pouvoir lire quoi ? Quelles données sont privées à un utilisateur ?
- Durée de conservation, sauvegarde, besoin d'export ?

**Plateformes et exploitation**

- Quelles cibles : web, Android, iOS, desktop (lequel), ligne de commande, API ?
- Faut-il fonctionner hors connexion ?
- Qui maintient le projet, avec quelles compétences et quels langages déjà connus ?
- Comment les mises à jour atteignent-elles les utilisateurs ?

**Coûts et délais**

- Budget mensuel acceptable à l'arrêt, et à l'usage prévu ?
- Le projet appelle-t-il une IA ou une API facturée à l'usage ? Pour quoi faire ?
- Échéance d'une première version utilisable ?

## 3. Écrire `documentation/projet.md`

Remplir le modèle déjà présent avec les réponses, sans rien inventer. Les réponses absentes
vont dans « Questions ouvertes ». Le montrer à l'utilisateur et obtenir son accord.

## 4. Confier le choix de pile à l'architecte

Lancer l'agent `architecte` avec un brief qui contient :

- le chemin de `documentation/projet.md`, validé ;
- les préférences ou interdits techniques exprimés par l'utilisateur ;
- la demande : son livrable « Démarrage » (piles comparées, ADR-001 proposé, sections de
  `CLAUDE.md`, outillage, évolutions du réseau, questions ouvertes).

Présenter son livrable à l'utilisateur tel quel, sans le résumer au point d'en perdre les
coûts et les risques. Transmettre les questions ouvertes. Si l'utilisateur change un choix,
relancer l'`architecte` avec ce changement (`SendMessage` vers le même agent quand c'est
possible).

## 5. Appliquer, après le « oui »

1. Passer l'ADR-001 au statut « accepté », avec la date.
2. Remplir les sections `<!-- architecte -->` de `CLAUDE.md` et retirer les chevrons. Laisser
   vide le tableau « Contrôles propres au projet » s'il n'y a aucun contrôle accepté. Retirer
   les sections optionnelles que l'ADR écarte (coûts variables, bac à sable, logique
   dupliquée) ; une section retirée emporte son skill (`experience-sandbox`,
   `logique-dupliquee`) : dossier supprimé et ligne retirée du tableau des skills.
3. Écrire `.claude/formatters.json`, le chemin du fichier qui porte la version dans
   `.claude/version.json` et, si besoin, `.claude/hooks/setup-projet.sh`.
4. Appliquer les évolutions du réseau acceptées, avec le skill `evolution-reseau`.
5. Supprimer le `README.md` hérité d'agent-starter : il décrit le modèle, plus le projet.
   Écrire à sa place le `README.md` du projet (nom, intention, commandes). Mettre à jour
   `documentation/README.md`.
6. Lancer `node scripts/check-agents.mjs`.
7. Faire relire le tout par `relecteur-regles`, et l'ADR-001 avec les contrôles proposés par
   `securite` : le mode d'exposition et l'authentification fixent ce qu'il contrôlera.
8. Commit `Démarrage du projet : <pile retenue>` et version `0.1.0` avec son entrée au
   `CHANGELOG.md`. Une fois ce commit sur la branche principale, poser le tag `v0.1.0`
   (`CLAUDE.md`, « Chaîne de travail », étape 6).

Ensuite seulement, la première fonctionnalité suit la « Chaîne de travail ».
