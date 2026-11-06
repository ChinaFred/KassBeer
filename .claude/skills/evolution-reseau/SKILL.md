---
name: evolution-reseau
description: "Ajouter, modifier ou retirer un agent, un skill, un hook ou un contrôle du réseau d'agents — y compris appliquer les propositions de l'architecte et tirer une règle d'un incident. À utiliser dès qu'un fichier de .claude/, CLAUDE.md ou le tableau « Contrôles propres au projet » doit changer."
---

# Faire évoluer le réseau d'agents

La session principale applique ce skill, après un « oui » explicite de l'utilisateur.
`architecte`, `relecteur-regles` et `securite` ne se retirent pas (`CLAUDE.md`, « Agents »). Un
agent ne modifie jamais son propre fichier ni celui d'un autre agent.

## 1. Choisir la bonne forme

| Besoin | Forme |
|---|---|
| Un relecteur doit vérifier un point de plus | ligne `Pn` dans « Contrôles propres au projet » de `CLAUDE.md` |
| Une règle vaut pour tout le monde | section ou puce dans `CLAUDE.md` |
| Une procédure qui revient (suite de gestes) | skill dans `.claude/skills/<nom>/SKILL.md` |
| Un rôle avec son propre jugement, ou une relecture indépendante | agent dans `.claude/agents/<nom>.md` |
| Une action automatique à chaque événement (écriture, démarrage) | hook dans `.claude/settings.json` |

Préférer la forme la plus légère. Un contrôle dans le tableau ne demande aucun fichier
nouveau, et les relecteurs le lisent déjà.

## 2. Écrire

**Contrôle** : `| Pn | <ce qui est vérifié, vérifiable par grep ou par une commande> |
<agent> | <ADR-NNN ou incident daté> |`. Un contrôle sans origine ne s'ajoute pas.

**Agent ou skill** : en-tête YAML avec `name` (identique au nom du fichier ou du dossier) et
`description`. **Une `description` qui contient « : » se met entre guillemets doubles** ; sans
eux, l'en-tête est invalide et Claude Code écarte l'agent sans message. Un relecteur n'a ni
`Edit` ni `Write` dans `tools`. L'agent lit `CLAUDE.md` et n'en recopie pas les règles. Son
livrable a un format fixe.

**Hook** : un script Node ou bash qui sort en code 0 sur un échec non bloquant. Un hook qui
sort en code 2 bloque l'outil : à réserver à une vraie interdiction.

## 3. Inscrire

- Un agent ou un skill ajouté, renommé ou retiré met à jour les tableaux « Agents » de
  `CLAUDE.md`. `scripts/check-agents.mjs` vérifie que chaque nom cité a son fichier.
- `documentation/guide-reseau.md` décrit le changement.
- Une règle née d'un incident ajoute son entrée dans `documentation/lecons-apprises.md` :
  date, ce qui s'est passé, ce qui a changé.

## 4. Vérifier

```bash
node scripts/check-agents.mjs
```

Puis relecture par `relecteur-regles` (contrôle 13). Une nouvelle session est nécessaire pour
que Claude Code charge un agent ou un skill ajouté.
