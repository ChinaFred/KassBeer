---
name: changement-lourd
description: "Soumettre un changement lourd à l'agent architecte avant tout cadrage ou code — nouveau framework, base de données, fournisseur (hébergement, authentification, IA), nouvelle plateforme ou mode d'exploitation, migration de données, logique déplacée entre client et serveur, dépendance qui pèse sur le démarrage ou la compilation, nouvelle source de coût variable. À utiliser dès qu'une demande entre dans la liste « Changement lourd » de CLAUDE.md, ou qu'un agent signale un écart à un ADR."
---

# Changement lourd

## 1. Reconnaître le cas

Comparer la demande à la liste « Changement lourd » de `CLAUDE.md`. En cas de doute, le
traiter comme lourd : un avis de l'architecte prend quelques minutes, revenir sur une
architecture déjà codée demande de réécrire les modules concernés.

Dire à l'utilisateur, en une phrase, que la demande passe d'abord par l'`architecte`, et
pourquoi.

## 2. Écrire le brief

Le brief de l'`architecte` contient :

- la demande, dans les mots de l'utilisateur ;
- ce qui la motive (bug, limite atteinte, coût, nouvelle cible) ;
- les ADR qu'elle touche, par numéro ;
- la demande de livrable : « Changement lourd » (avis, options dont « ne pas le faire »,
  coût, ADR proposé, évolutions du réseau, questions ouvertes).

## 3. Présenter l'avis

Présenter l'avis, les options et le coût à l'utilisateur. Attendre sa décision.

- **Refus** : l'ADR proposé passe au statut « rejeté », avec la raison. Il reste dans
  `documentation/decisions/` : la question ne se reposera pas sans élément nouveau.
- **Accord** : l'ADR passe à « accepté » ; un ADR qu'il remplace passe à « remplacé par
  ADR-NNN ». Mettre à jour la section « Le projet » de `CLAUDE.md` si la pile change.
  Appliquer les évolutions du réseau acceptées (skill `evolution-reseau`). Puis la demande
  reprend la « Chaîne de travail » à l'étape 1.
