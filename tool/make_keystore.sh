#!/usr/bin/env bash
# One-time: creates the release keystore and android/key.properties.
#   bash tool/make_keystore.sh
# You type the password yourself. BACK UP the .jks and the password somewhere safe
# (password manager + offline copy): if either is lost the app can never be updated on Google Play.
set -euo pipefail
cd "$(dirname "$0")/../android"
KEYTOOL=${KEYTOOL:-keytool}
JKS="$HOME/rosenthal-release.jks"
[ -f "$JKS" ] && { echo "$JKS already exists, not touching it."; exit 1; }
read -r -s -p "Choose a keystore password (min 8 chars): " PW; echo
read -r -s -p "Repeat: " PW2; echo
[ "$PW" = "$PW2" ] && [ ${#PW} -ge 8 ] || { echo "passwords differ or too short"; exit 1; }
"$KEYTOOL" -genkeypair -v -keystore "$JKS" -alias rosenthal -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PW" -keypass "$PW" -dname "CN=Rosenthal Barbershop, O=Rosenthal Barbershop, L=Edmonton, ST=Alberta, C=CA"
cat > key.properties <<P
storeFile=$JKS
storePassword=$PW
keyAlias=rosenthal
keyPassword=$PW
P
echo "Done. Keystore: $JKS  (outside the project, back it up!)"
