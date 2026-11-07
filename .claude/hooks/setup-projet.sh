#!/bin/bash
# Session cloud seulement : installe Flutter (même version que ci.yml) et les dépendances,
# pour rejouer analyze, format et tests. Pas de SDK Android : l'APK se compile dans la CI.
# Proposé par l'architecte (ADR-001), repris du hook de Kass'Dalle. Chaque étape dépend
# de l'existence de son dossier, pour que le script tourne avant le premier code.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

FLUTTER_VERSION="3.44.6"   # aligner sur .github/workflows/ci.yml
FLUTTER_ROOT="$HOME/flutter"
ROOT="$CLAUDE_PROJECT_DIR"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ] \
  || ! grep -Eq "\"frameworkVersion\": *\"$FLUTTER_VERSION\"" "$FLUTTER_ROOT/bin/cache/flutter.version.json" 2>/dev/null; then
  rm -rf "$FLUTTER_ROOT"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$HOME"
fi
git config --global --get-all safe.directory | grep -qx "$FLUTTER_ROOT" \
  || git config --global --add safe.directory "$FLUTTER_ROOT"
export PATH="$FLUTTER_ROOT/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_ROOT/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
flutter config --no-analytics >/dev/null

[ -f "$ROOT/app/pubspec.yaml" ] && (cd "$ROOT/app" && flutter pub get)
[ -f "$ROOT/brewing/pubspec.yaml" ] && (cd "$ROOT/brewing" && dart pub get)
[ -f "$ROOT/rules-tests/package-lock.json" ] && (cd "$ROOT/rules-tests" && npm ci --no-audit --no-fund)

if ! java -version 2>&1 | grep -Eq 'version "(2[1-9]|[3-9][0-9])'; then
  echo "setup-projet : Java 21 absent ; npm test de rules-tests échouera."
fi
exit 0
