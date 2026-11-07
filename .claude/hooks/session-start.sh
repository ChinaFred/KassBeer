#!/bin/bash
# Démarrage d'une session Claude Code, sur le poste comme dans le cloud.
# 1. Vérifie que chaque agent et chaque skill peut se charger : un en-tête YAML
#    invalide les retire de la session sans message.
# 2. Lance .claude/hooks/setup-projet.sh s'il existe (installation de la chaîne
#    d'outils du projet, proposé par l'architecte, écrit par la session principale).
# 3. Avertit quand l'adresse des commits n'est pas une adresse noreply de GitHub :
#    le dépôt est public, et l'adresse d'un commit poussé ne s'efface plus (ADR-002).
# N'échoue jamais : un avertissement part sur stdout, que la session lit.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if command -v node >/dev/null 2>&1; then
  node "$ROOT/scripts/check-agents.mjs" --warn || true
else
  echo "session-start : node absent, agents et skills non vérifiés."
fi

if [ -f "$ROOT/.claude/hooks/setup-projet.sh" ]; then
  bash "$ROOT/.claude/hooks/setup-projet.sh" \
    || echo "session-start : setup-projet.sh a échoué ; les contrôles du projet risquent de ne pas tourner."
fi

# Pas de préfixe « ATTENTION — » : CLAUDE.md le réserve à un agent absent.
if command -v git >/dev/null 2>&1; then
  # git var lit l'adresse que prendra le prochain commit, GIT_AUTHOR_EMAIL compris.
  ident=$(git -C "$ROOT" var GIT_AUTHOR_IDENT 2>/dev/null || true)
  email=$(printf '%s' "$ident" | sed -n 's/.*<\(.*\)>.*/\1/p' | tr '[:upper:]' '[:lower:]')
  case "$email" in
    *@users.noreply.github.com) ;;
    *) echo "session-start : l'adresse des commits (git var GIT_AUTHOR_IDENT) n'est pas une adresse noreply de GitHub. Le dépôt est public (ADR-002) : régler git config user.email <id>+<compte>@users.noreply.github.com avant de commiter." ;;
  esac
fi
exit 0
