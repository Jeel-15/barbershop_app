#!/usr/bin/env bash
# Production APK: prod flavor (no http, no Demo tour), smaller (demo voice files left out),
# code obfuscated. Needs android/key.properties (tool/make_keystore.sh) for a publishable signature.
#   bash tool/build_prod.sh https://shop.example.com/api/v1
set -euo pipefail
cd "$(dirname "$0")/.."
API=${1:?usage: build_prod.sh <https api base url>}
case "$API" in https://*) ;; *) echo "production API must be https://"; exit 1;; esac
[ -f android/key.properties ] || echo "WARNING: no android/key.properties, APK will be debug-signed (do not publish)"
cp pubspec.yaml pubspec.yaml.bak
trap 'mv -f pubspec.yaml.bak pubspec.yaml' EXIT
sed -i '/assets\/demo\/audio\//d' pubspec.yaml
mkdir -p build/symbols
flutter build apk --release --dart-define=FLAVOR=prod --dart-define=API_BASE_URL="$API" \
  --obfuscate --split-debug-info=build/symbols
ls -la build/app/outputs/flutter-apk/app-release.apk
