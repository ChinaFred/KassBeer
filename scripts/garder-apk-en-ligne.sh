#!/usr/bin/env bash
# Recopie dans <dossier> l'APK et son manifeste actuellement en ligne sur
# Firebase Hosting (ADR-012). Lancé par le job deploy de deploy.yml quand aucun
# APK n'est construit, avant l'authentification Google : un déploiement de
# Hosting remplace tout le site par <dossier>, et sans cette copie l'APK et le
# manifeste lus par l'application Android disparaîtraient.
#
# Hosting sert index.html en 200 pour un fichier absent : le contenu est jugé,
# pas le code HTTP. Contrôle minimal (ADR-012, arbitrage 9) :
#   - manifeste : objet JSON, version X.Y.Z, build_number entier de 1 à
#     2 100 000 000, size_bytes entier de 1 à 200 000 000, sha256 de 64
#     caractères [0-9a-f] ;
#   - APK : commence par « PK », taille égale à size_bytes, SHA-256 égal à sha256.
#
# Issues :
#   - paire cohérente : recopiée ;
#   - paire absente : rien n'est recopié, avertissement (l'application ne
#     propose rien) ;
#   - APK seul : recopié sans manifeste, avertissement ;
#   - manifeste seul, manifeste JSON hors des formes, ou paire incohérente :
#     échec du déploiement ;
#   - site injoignable ou code d'erreur : échec (rien ne dit si une paire existe).
#
# Usage : garder-apk-en-ligne.sh <dossier> <site https://…>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage : $0 <dossier> <site https://…>" >&2
  exit 2
fi

dir="$1"
site="${2%/}"
apk="$dir/app-release.apk"
manifest="$dir/apk_release.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$dir"

# Un fichier absent rend index.html : curl réussit, le contenu est jugé plus bas.
# Une panne de réseau ou un code d'erreur fait échouer l'étape : sans lecture,
# rien ne dit si une paire existe. --max-time : un téléchargement bloqué échoue
# en cinq minutes au lieu d'occuper le job jusqu'à sa limite.
stamp=$(date +%s)
curl -sS --fail --max-time 300 -o "$work/apk" "$site/app-release.apk?t=$stamp"
curl -sS --fail --max-time 60 -o "$work/manifest" "$site/apk_release.json?t=$stamp"

manifest_ok=false
if jq -e '
  type == "object"
  and (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
  and (.build_number | type == "number" and . == floor and . >= 1 and . <= 2100000000)
  and (.size_bytes | type == "number" and . == floor and . >= 1 and . <= 200000000)
  and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
' "$work/manifest" > /dev/null 2>&1; then
  manifest_ok=true
fi
# Un objet JSON hors de ces formes n'est pas la page de repli de Hosting : c'est
# un manifeste faux, qui arrête le déploiement.
if ! $manifest_ok && jq -e 'type == "object"' "$work/manifest" > /dev/null 2>&1; then
  echo "::error::Manifeste en ligne hors des formes attendues (version, build_number, size_bytes, sha256) : déploiement arrêté."
  exit 1
fi
apk_ok=false
if [ "$(head -c 2 "$work/apk")" = "PK" ]; then apk_ok=true; fi

if $apk_ok && $manifest_ok; then
  version=$(jq -r .version "$work/manifest")
  build=$(jq -r .build_number "$work/manifest")
  size=$(jq -r .size_bytes "$work/manifest")
  sha=$(jq -r .sha256 "$work/manifest")
  actual_size=$(stat -c %s "$work/apk")
  actual_sha=$(sha256sum "$work/apk" | cut -d' ' -f1)
  if [ "$size" != "$actual_size" ]; then
    echo "::error::APK en ligne de $actual_size octets, manifeste annonçant $size : paire incohérente, déploiement arrêté."
    exit 1
  fi
  if [ "$sha" != "$actual_sha" ]; then
    echo "::error::SHA-256 de l'APK en ligne différent de celui du manifeste : paire incohérente, déploiement arrêté."
    exit 1
  fi
  cp "$work/apk" "$apk"
  cp "$work/manifest" "$manifest"
  echo "APK en ligne conservé : v$version, build $build, $actual_size octets."
elif $apk_ok; then
  rm -f "$manifest"
  cp "$work/apk" "$apk"
  echo "::warning::APK en ligne sans manifeste lisible : recopié, l'application ne propose aucune mise à jour."
elif ! $manifest_ok; then
  rm -f "$apk" "$manifest"
  echo "::warning::Aucun APK en ligne : rien n'est recopié, l'application ne propose aucune mise à jour."
else
  echo "::error::Manifeste en ligne sans APK : il annoncerait une version absente, déploiement arrêté."
  exit 1
fi
