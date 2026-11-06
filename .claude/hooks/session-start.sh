#!/bin/bash
# Démarrage d'une session Claude Code, sur le poste comme dans le cloud.
# 1. Vérifie que chaque agent et chaque skill peut se charger : un en-tête YAML
#    invalide les retire de la session sans message.
# 2. Lance .claude/hooks/setup-projet.sh s'il existe (installation de la chaîne
#    d'outils du projet, proposé par l'architecte, écrit par la session principale).
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
exit 0
