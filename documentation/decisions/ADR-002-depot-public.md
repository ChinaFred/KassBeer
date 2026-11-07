# ADR-002 — Dépôt GitHub public

- **Statut** : accepté le 2026-11-07, décision de l'utilisateur
- **Date** : 2026-11-07
- **Remplace** : — (modifie ADR-001 sur deux points : dépôt privé, minutes de la CI)

## Contexte

`projet.md` (Contraintes › Exposition et environnement) et ADR-001 posaient un dépôt GitHub
`ChinaFred/KassBeer` privé, sur le plan GitHub Free. Le 2026-11-07 à 10 h 47 UTC, l'API
GitHub le donnait privé. La pose d'une protection de `main` répondait 403 : « Upgrade to
GitHub Pro or make this repository public ».

Sans protection de `main`, rien sur GitHub n'empêchait la fusion d'une PR dont la CI
échoue. La session vérifiait la CI avant de fusionner ; c'était le seul contrôle
(`exigences-techniques.md`, « Réglages sur GitHub »). Un `deploy.yml` poussé sur `main`
obtient l'accès du compte `github-deploy`, qui publie les règles Firestore.

L'utilisateur a passé le dépôt en public le 2026-11-07. Ce choix publie :

- tout l'historique Git (27 commits à la date de la revue `securite`) et les tags ;
- les PR #1 à #3 ;
- les journaux des runs GitHub Actions ;
- les artefacts de `deploy.yml` (APK signé et site web), gardés un jour ;
- `brewing/test/fixtures/cost.json` : 80 prix d'achat et 5 totaux de coût tirés des fiches, tirés
  des fiches de l'administrateur ;
- dans l'historique, des prénoms de tiers (deux amis et un troisième nom), présents dans les
  fixtures avant la v0.1.3 ;
- les deux adresses e-mail de l'utilisateur, dans les métadonnées des commits et des tags ;
- `firestore.rules`, `firebase.json`, les workflows et les identifiants de production
  (`exigences-techniques.md`, « État de la production »).

Ce fichier est lui-même public. Il ne cite ni les prénoms ni les adresses e-mail.

## Options

| Option | Pour | Contre | Coût (arrêt / usage) |
|---|---|---|---|
| Repasser en privé, plan Free (état d'ADR-001) | code, historique et journaux de nouveau fermés aux tiers | aucune protection de `main` ni règle sur les tags ; la session reste le seul contrôle avant la fusion ; 2 000 minutes de CI par mois ; ce qui a été copié pendant la période publique le reste | 0 $ / 0 $ jusqu'à 2 000 minutes |
| A. Privé, plan GitHub Pro | protection de branche sur un dépôt privé ; données de test et métadonnées non publiées | facturé chaque mois ; effet des rulesets et des environnements sur un dépôt privé Pro à vérifier ; mêmes copies déjà faites | ≈ 4 $ par mois (à vérifier) |
| B. Public (retenu) | rulesets sur `main` et sur les tags `v*`, secret scanning, push protection, sans abonnement ; minutes des runners standard gratuites | code, historique, PR, journaux et artefacts lisibles par tous ; PR de fork possibles ; exposition irréversible pour ce qui est déjà publié | 0 $ / 0 $ |
| C. Recréer un dépôt à l'historique réécrit, puis public | prénoms et e-mails absents de l'historique publié | nouvel identifiant numérique du dépôt : condition Workload Identity Federation, environnement `production`, dix variables et quatre secrets à refaire ; PR #1 à #3 et runs perdus ; tags à reposer ; copies déjà faites inchangées | 0 $ / 0 $, environ une demi-journée de réglages |

## Décision

Option B. Le dépôt reste public. Cette visibilité obtient la protection de `main` et des
tags sans abonnement, et rend la CI gratuite.

Arbitrage de l'utilisateur : les prix et coûts de `brewing/test/fixtures/cost.json` restent
publics, dans l'arbre et l'historique. Les noms de personnes sortent des fichiers versionnés
(v0.1.3) ; leur présence dans l'historique est acceptée. Les adresses e-mail sont masquées
pour les commits à venir.

## Réponses aux questions de l'architecte

1. **Où tourne chaque morceau de code** : inchangé pour l'application. La CI tourne sur
   les runners standard de GitHub. Une PR de fork ne lance ses workflows qu'après
   approbation du propriétaire.
2. **Ce qui existera en double** : rien.
3. **Ce qui pèse au démarrage** : sans objet.
4. **Compilation de chaque cible** : inchangée. Le job « Android — compilation » reste la
   seule compilation de l'APK depuis une session cloud.
5. **Qui voit quoi** : tout le monde lit le code, l'historique, les fixtures, les PR et les
   journaux des runs. Un compte GitHub connecté peut télécharger les artefacts pendant leur
   jour de conservation : l'APK signé et le site web, déjà distribués par App Distribution
   et Hosting. Les données de l'application ne changent pas de place : elles vivent dans
   Firestore, derrière `firestore.rules`. P5 porte sur ces données. Les prix de test des
   fixtures en sont exclus par décision de l'utilisateur. Les règles Firestore publiées
   restent le seul contrôle d'accès ; leur lecture par un tiers ne doit ouvrir aucun droit,
   ce que vérifient les tests de `rules-tests/` (P4, P11).
6. **Ce qui coûte à l'usage, plafond** : 0 $. Les minutes des runners standard sont
   gratuites sur un dépôt public : le plafond de 2 000 minutes d'ADR-001 ne s'applique plus.
   L'approbation des workflows pour tout contributeur externe empêche un tiers de lancer
   des runs. L'alerte budgétaire Firebase à 5 € est inchangée.
7. **Exposition** : le code passe de privé à public. L'application reste ouverte sur
   Internet, sur invitation (ADR-001). Surface ajoutée :
   - PR de fork : `ci.yml` tourne en `contents: read`, sans secret ni `id-token` ;
     `deploy.yml` n'a pas de déclencheur `pull_request` ni `pull_request_target` (P14) ;
   - environnement `production` restreint à `main` ;
   - la condition Workload Identity Federation (`repository_id`, `ref` `main`, environnement
     `production`, `workflow_ref` `deploy.yml@refs/heads/main`) ne dépend pas de la
     visibilité ;
   - `deploy.yml` écrit `VARS_JSON: ${{ toJSON(vars) }}` dans un bloc `env:` (lignes 113 et
     288), que GitHub affiche dans le journal public. Ce bloc contient aujourd'hui des
     identifiants publics du client. Une variable sensible ajoutée plus tard y serait
     publiée ;
   - une PR de fork peut modifier `.claude/**`, `CLAUDE.md` et `scripts/check-agents.mjs`.
     `session-start.sh` lance `check-agents.mjs` et `setup-projet.sh` à l'ouverture d'une
     session sur cette branche, sur le poste de l'utilisateur.

   Revue `securite` du 2026-11-07 : aucun secret dans les 27 commits de l'historique.
8. **Exploitation, sauvegarde, mise à jour** : GitHub applique désormais ce que la session
   vérifiait seule. Ruleset sur `main` : PR requise, 0 approbation, les quatre contrôles de
   `ci.yml` requis, branche à jour avec `main`, ni force push ni suppression. Ruleset sur
   les tags `v*` : ni suppression ni mise à jour. Approbation des workflows pour tout
   contributeur externe. Actions autorisées limitées et épinglées par SHA. Secret scanning,
   push protection, alertes Dependabot, signalement privé de failles, suppression
   automatique des branches fusionnées. Les commits faits sur le poste portent une adresse `noreply`
   (`git config user.email` du dépôt). Les fusions faites sur GitHub prennent l'adresse
   principale du compte, tant que « Keep my email addresses private » n'est pas coché dans
   Settings › Emails : réglage à faire par l'utilisateur. Sauvegarde et mise à jour des utilisateurs inchangées.
9. **Coût de sortie** : repasser en privé prend un clic. Il retire les rulesets et la
   gratuité des minutes, et ne retire pas les copies faites pendant la période publique.
   Ne jamais recréer le dépôt : son identifiant numérique figure dans la condition Workload
   Identity Federation, et un nouveau dépôt la rendrait fausse.

## Conséquences

Plus simple : une PR rouge ne se fusionne plus, un tag poussé ne se déplace plus, un secret
poussé est bloqué par la push protection. La CI ne compte plus ses minutes.

Plus difficile : chaque fichier versionné, chaque message de commit, chaque description de
PR et chaque journal de run est public. Une donnée réelle (prénom, adresse e-mail) qui y
entre ne peut plus en être retirée. Une branche venue d'un fork s'ouvre avec précaution :
ses hooks tournent sur le poste.

Règles et contrôles proposés pour `CLAUDE.md` : extension de P10 à `.claude/**`,
`CLAUDE.md` et `scripts/**` pour une branche externe ; règle et contrôle sur les données
réelles dans les fichiers versionnés ; contrôle de `toJSON(vars)` dans les workflows
(livrable de l'architecte, 2026-11-07).

## Sources

Consultées le 2026-11-07.

- Minutes gratuites des runners standard sur un dépôt public ; plan Free exprimé en
  12 $ de calcul inclus par mois (≈ 2 000 minutes Linux à 0,006 $) :
  https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Repository rules réservées aux dépôts publics sur le plan Free :
  https://github.com/pricing (la page ne liste pas GitHub Pro).
- GitHub Pro : protected branches et required reviewers sur un dépôt privé :
  https://docs.github.com/en/get-started/learning-about-github/githubs-plans (prix non
  donné ; ≈ 4 $ par mois, à vérifier).
- Réponse 403 de l'API de protection de branche, dépôt privé, plan Free : constatée par la
  session le 2026-11-07.
