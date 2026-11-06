---
name: experience-sandbox
description: "Ajouter, faire avancer, porter ou retirer une expérience du bac à sable (écran d'essai réservé à l'administrateur). À utiliser dès qu'une demande parle d'essayer, de prototyper ou d'expérimenter une fonctionnalité avant de l'écrire dans l'application, ou de porter une expérience validée dans sa feature. Sans objet si la section « Bac à sable » a été retirée de CLAUDE.md."
---

# Expérience du bac à sable

Les règles sont dans la section « Bac à sable » de `CLAUDE.md`. Ce skill donne l'ordre des
gestes. Si le projet n'a pas encore de bac à sable, sa création est un changement lourd :
l'`architecte` fixe le dossier client, le point d'entrée serveur unique et les points
d'accrochage (route, entrée de menu, export serveur), une fois pour toutes.

## 0. Avant la première ligne : où tournera le code une fois porté ?

Dire, et faire valider, si le code finira sur l'appareil ou sur le serveur. N'employer que des
bibliothèques disponibles là-bas. Exemple à ne pas refaire : une bibliothèque de traitement
d'image qui n'existait que côté client a imposé, sans débat, que le traitement reste sur
l'appareil, donc synchrone, donc l'utilisateur attend.

## 1. Ajouter une expérience

- Tout vit sous le dossier du bac à sable. Le code de l'application se lit, s'importe,
  s'appelle ; il ne s'édite pas. Pour changer un comportement, copier et modifier la copie.
- Une entrée dans le registre des expériences, un écran, et au besoin un cas dans le point
  d'entrée serveur unique, qui exige le rôle administrateur.
- Un appel à une API facturée porte son propre poste de coût, sous le groupe « Bac à sable ».

## 2. Règles qui ne changent pas

- Rien n'est enregistré sur les chemins de production : tout reste en mémoire.
- Aucun `catch` silencieux.
- Étapes empilées : chaque bloc n'apparaît que si le précédent a abouti. Valider un palier
  avant d'écrire le suivant.
- Hors livraison : rien dans `exigences-fonctionnelles.md`.

## 3. Porter une expérience validée

Elle se **réécrit** dans sa feature, avec tests, gestion d'erreur et documentation, en
suivant la « Chaîne de travail ». Prompts, seuils et constantes se recopient à l'identique.
Un calcul qui doit exister des deux côtés passe par le skill `logique-dupliquee`. Puis
**supprimer** l'expérience : entrée du registre, écran, cas serveur.
