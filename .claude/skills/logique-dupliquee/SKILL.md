---
name: logique-dupliquee
description: "Corriger, étendre ou créer une logique métier qui existe à la fois côté client et côté serveur (parseur, calcul, règle de décision, vocabulaire partagé), avec une fixture JSON rejouée par les deux suites de tests. À utiliser dès qu'un fichier du tableau « Logique dupliquée » de CLAUDE.md doit changer, ou avant d'écrire une logique qui pourrait exister des deux côtés."
---

# Logique dupliquée client ↔ serveur

Une fixture JSON partagée est rejouée par les deux suites. Corriger un seul côté fait
échouer l'autre suite. L'ordre ci-dessous évite ce cycle.

## 0. Faut-il vraiment deux côtés ?

Vérifier que **les deux** côtés en ont un besoin propre : le client pour afficher ou
travailler hors ligne, le serveur pour décider sans lui. Sinon, l'écrire d'un seul côté.

Si la logique dépend d'une donnée (prix, taux, liste de référence), déplacer la donnée là où
les deux la lisent (base de données, fichier de configuration servi) et ne garder en double
que le calcul. Jamais de valeur de repli figée dans le code.

Une nouvelle logique dupliquée est un changement lourd : skill `changement-lourd`.

## 1. Trouver les fichiers

Le tableau « Logique dupliquée » de `CLAUDE.md` donne la fixture, le fichier client et le
fichier serveur. Retrouver les tests qui la rejouent :

```bash
grep -rln "<fixture>.json" <dossier des tests client> <dossier des tests serveur>
```

## 2. Écrire le cas dans la fixture d'abord

Ajouter le cas qui reproduit le bug, ou qui décrit le nouveau comportement, au format des
cas voisins. Lancer les deux suites : elles doivent **échouer** toutes les deux sur ce cas.
Un cas qui passe déjà ne prouve rien.

## 3. Corriger les deux côtés, dans le même commit

Même algorithme, mêmes noms de fonctions quand c'est possible. Ne pas « améliorer » un côté au
passage. Un écart assumé vit dans une section `divergences` de la fixture, avec sa raison.

## 4. Vérifier et le dire

Lancer analyse, formatage et tests des deux côtés (« Commandes utiles » de `CLAUDE.md`). Le
message de commit nomme la fixture, le cas ajouté et les deux fichiers modifiés.
