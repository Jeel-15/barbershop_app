#!/usr/bin/env bash
# One command before every hand-over: formatting, analysis, all tests.
#   bash tool/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:/c/src/bin"

echo "== format";  dart format --set-exit-if-changed lib test tool >/dev/null || { echo "run: dart format lib test tool"; exit 1; }
echo "== analyze"; flutter analyze
echo "== tests";   flutter test
echo "ALL GOOD"
