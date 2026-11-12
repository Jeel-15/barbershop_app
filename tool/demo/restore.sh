#!/usr/bin/env bash
# Puts the LOCAL demo database back exactly as snapshot.sh saved it.
#   bash tool/demo/restore.sh
# Sign-in sessions are part of the database too: the phone stays signed in if it was signed in when the snapshot was taken.
# LOCAL TEST DATABASE ONLY.
set -euo pipefail
cd "$(dirname "$0")"
MYSQL=${MYSQL:-/j/laragon/bin/mysql/mysql-8.0.30-winx64/bin/mysql.exe}
src="snapshots/before_tour.sql"
[ -f "$src" ] || { echo "no snapshot yet: run snapshot.sh first"; exit 1; }
"$MYSQL" -uroot barber_shop_db < "$src"
echo "restored from $src"
