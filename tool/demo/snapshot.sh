#!/usr/bin/env bash
# Saves the LOCAL demo database before a tour run, so everything the tour creates
# (customer, booking, invoice...) can be undone with restore.sh.
#   bash tool/demo/snapshot.sh
# LOCAL TEST DATABASE ONLY. Never run against the live server.
set -euo pipefail
cd "$(dirname "$0")"
MYSQLDUMP=${MYSQLDUMP:-/j/laragon/bin/mysql/mysql-8.0.30-winx64/bin/mysqldump.exe}
mkdir -p snapshots
out="snapshots/before_tour.sql"
"$MYSQLDUMP" -uroot --single-transaction --routines barber_shop_db > "$out"
echo "saved $out ($(wc -c < "$out") bytes)"
