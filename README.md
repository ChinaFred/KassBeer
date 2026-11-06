# agent-starter

Réseau d'agents Claude Code pour démarrer un projet d'application déjà outillé : sept agents,
cinq skills, deux hooks, des règles d'écriture et de code, et les leçons tirées d'un projet
antérieur. Sans CI, sans déploiement, sans intégration aux Issues GitHub.

## Démarrer un projet

Sur GitHub, ce dépôt est un modèle : bouton **Use this template**, puis cloner le nouveau
dépôt. Le bouton n'apparaît que si la case **Settings › Template repository** est cochée
sur ce dépôt (réglage fait à la main). Ou, en ligne de commande :

```bash
git clone https://github.com/ChinaFred/agent-starter.git mon-projet
cd mon-projet
rm -rf .git && git init -b main
git add -A && git commit -m "Départ depuis agent-starter"
```

Sous PowerShell, remplacer `rm -rf .git` par `Remove-Item -Recurse -Force .git`.

Puis ouvrir Claude Code dans le dossier et écrire :

> démarre le projet

La session pose les questions d'intention et de contraintes, l'agent `architecte` compare des
piles techniques et écrit l'ADR-001, puis la session remplit `CLAUDE.md` après votre
validation.

Ce `README.md` décrit agent-starter, pas le projet. Le skill `demarrage-projet` le supprime
à la validation de l'ADR-001 et écrit à sa place le `README.md` du projet.

## Prérequis

- Claude Code (CLI, extension VS Code ou claude.ai/code).
- Node 18 ou plus récent, pour les hooks et les scripts de `scripts/`.
- Git ; sous Windows, Git for Windows (son `bash` sert au hook de démarrage).

## Contenu

| Chemin | Rôle |
|---|---|
| `CLAUDE.md` | règles du projet, chaîne de travail, sections remplies au démarrage |
| `.claude/agents/` | `architecte`, `analyste-metier`, `ux-designer`, `developpeur`, `relecteur-regles`, `securite`, `product-owner` |
| `.claude/skills/` | `demarrage-projet`, `changement-lourd`, `evolution-reseau`, `logique-dupliquee`, `experience-sandbox` |
| `.claude/hooks/` | vérification des agents au démarrage, formatage à l'écriture |
| `scripts/check-agents.mjs` | vérifie que chaque agent et skill se charge |
| `scripts/check-version.mjs` | avant une fusion, vérifie que la version de la branche dépasse celle de la branche principale, que son tag n'existe pas encore, et que `CHANGELOG.md` a son entrée |
| `documentation/` | modèles (projet, ADR, exigences, changelog), leçons apprises, guide du réseau |

Le fonctionnement complet : `documentation/guide-reseau.md`.

## Mettre à jour le réseau d'un projet existant

Voir `documentation/guide-reseau.md`, section 5.
