#!/usr/bin/env bash
# One command to run the demo tour on the phone and look at what happened.
#   bash tool/demo/run.sh fast                 whole tour, no voice, short pauses
#   bash tool/demo/run.sh fast --chapter=c01   one chapter
#   bash tool/demo/run.sh fast --chapter=c01 --from=c01_05 --to=c01_10   only those beats
#   bash tool/demo/run.sh real --chapter=c00   real voice and real pauses (what you record)
#   add --no-build to reuse the APK already on the phone: the script (assets/demo/tour.json)
#   is pushed to the phone and used instead of the bundled one, so a script change needs no
#   rebuild. (Voice files are bundled: a changed sentence needs make_audio.mjs and a build.)
#
# It: checks the server, puts the LOCAL demo database back (restore.sh), builds the APK with
# the switches, installs it, starts the tour, waits for "[tour] finished", pulls the log and
# a screenshot of every action, prints every FAIL, and makes contact sheets.
# Results: tool/demo/runs/<time>/   (log.txt, pictures, sheet_XX.png)
# LOCAL TEST SERVER AND DATABASE ONLY. It starts the app on the phone: do not run it while
# the phone is in use.
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="$PATH:/c/src/bin"
export MSYS_NO_PATHCONV=1

MODE=fast
CHAPTER=""
FROM=""
TO=""
NOBUILD=0
for a in "$@"; do
  case "$a" in
    fast|real) MODE=$a ;;
    --no-build) NOBUILD=1 ;;
    --chapter=*) CHAPTER=${a#*=} ;;
    --from=*) FROM=${a#*=} ;;
    --to=*) TO=${a#*=} ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done

ADB_EXE=${ADB_EXE:-/c/Users/jeelp/AppData/Local/Android/Sdk/platform-tools/adb.exe}
SERIAL=$("$ADB_EXE" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
[ -n "$SERIAL" ] || { echo "no phone connected (USB debugging, or Wireless debugging off and on)"; exit 1; }
ADB="$ADB_EXE -s $SERIAL"
PKG=ca.rosenthalbarbershop.app
FILES=/sdcard/Android/data/$PKG/files
SHOTS=$FILES/tour
API=http://localhost/rosen_barber/public/api/v1

echo "== server"
ok=0
for i in 1 2 3 4 5; do
  code=$(curl -s -m 10 -o /dev/null -w "%{http_code}" $API/health || true)
  [ "$code" = "200" ] && { ok=1; break; }
  sleep 3
done
[ $ok = 1 ] || { echo "the local server does not answer (start Laragon: Start All)"; exit 1; }

echo "== script check"
node tool/demo/coverage_check.mjs | sed -n 1,4p

echo "== data back to the snapshot"
bash tool/demo/restore.sh || { echo "restore failed (is MySQL on port 3306 the Laragon one?)"; exit 1; }

if [ $NOBUILD = 0 ]; then
  FLAGS="--dart-define=TOUR_AUTOSTART=true --dart-define=TOUR_SHOTS=true"
  [ "$MODE" = "fast" ] && FLAGS="$FLAGS --dart-define=TOUR_FAST=true"
  [ -n "$CHAPTER" ] && FLAGS="$FLAGS --dart-define=TOUR_CHAPTER=$CHAPTER"
  [ -n "$FROM" ] && FLAGS="$FLAGS --dart-define=TOUR_FROM=$FROM"
  [ -n "$TO" ] && FLAGS="$FLAGS --dart-define=TOUR_TO=$TO"
  echo "== build ($MODE $CHAPTER $FROM $TO)"
  flutter build apk --release --target-platform android-arm64 \
    --dart-define=API_BASE_URL=http://localhost:8081/rosen_barber/public/api/v1 \
    --dart-define=FLAVOR=dev $FLAGS > tool/demo/last_build.txt 2>&1 \
    || { tail -20 tool/demo/last_build.txt; echo "build failed"; exit 1; }
  $ADB install -r build/app/outputs/flutter-apk/app-release.apk | tail -1
fi

# The script on the phone wins over the bundled one in test builds.
$ADB shell mkdir -p $FILES
$ADB push assets/demo/tour.json $FILES/tour.json >/dev/null

OUT=tool/demo/runs/$(date +%Y%m%d_%H%M%S)_$MODE
mkdir -p "$OUT"
$ADB reverse tcp:8081 tcp:80 >/dev/null
$ADB shell rm -rf $SHOTS
$ADB logcat -c
$ADB shell am force-stop $PKG
$ADB shell am start --user 0 -n $PKG/.MainActivity >/dev/null
echo "== running (log: $OUT/log.txt)"

if [ "$MODE" = "fast" ]; then limit=900; else limit=4200; fi
waited=0
while ! $ADB logcat -d -s flutter 2>/dev/null | grep -q "\[tour\] finished"; do
  sleep 5; waited=$((waited + 5))
  [ $waited -ge $limit ] && { echo "!! timeout after ${limit}s"; break; }
done

$ADB logcat -d -s flutter 2>/dev/null | grep "\[tour\]" | sed -E 's/^.*\[tour\]/[tour]/' > "$OUT/log.txt"
$ADB pull $SHOTS/. "$OUT/" >/dev/null 2>&1
echo "== result"
grep -E "FAIL|ERROR|HUNG|voice .*FAILED|skipped" "$OUT/log.txt" | head -60
echo "-- $(grep -c 'FAIL\|ERROR' "$OUT/log.txt") failing step(s); $(ls "$OUT"/*.png 2>/dev/null | wc -l) pictures"
tail -2 "$OUT/log.txt"
[ -f tool/demo/node_modules/pngjs/package.json ] && node tool/demo/contact_sheet.mjs "$OUT" 8 | tail -1
echo "folder: $OUT"
