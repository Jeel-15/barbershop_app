#!/usr/bin/env bash
# Writes test/fixtures/api_permissions.json from the web project: every permission the
# server stores and, for each v1 route, the permission(s) it asks for. The contract test
# (test/permissions_contract_test.dart) reads it. Run after the API's permissions change:
#   bash tool/live/export_permission_contract.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
WEB=${WEB:-/j/laragon/www/rosen_barber}
PHP=${PHP:-/j/laragon/bin/php/php-8.1.10-Win32-vs16-x64/php.exe}
MYSQL=${MYSQL:-/j/laragon/bin/mysql/mysql-8.0.30-winx64/bin/mysql.exe}

perms=$("$MYSQL" -uroot barber_shop_db -N -e "select name from permissions order by name")
routes=$(cd "$WEB" && "$PHP" artisan route:list --path=api/v1 --json)

PERMS="$perms" ROUTES="$routes" node -e '
const perms = process.env.PERMS.split(/\r?\n/).filter(Boolean);
const routes = JSON.parse(process.env.ROUTES).map(r => {
  const needs = [];
  for (const m of r.middleware) {
    const hit = /RequirePermission:(.+)$/.exec(m);
    if (hit) needs.push(...hit[1].split(","));
  }
  return { method: r.method.split("|")[0], uri: r.uri.replace(/^api\/v1\//, ""), needs };
}).sort((a, b) => (a.uri + a.method).localeCompare(b.uri + b.method));
process.stdout.write(JSON.stringify({ permissions: perms, routes }, null, 1) + "\n");
' > test/fixtures/api_permissions.json
echo "wrote test/fixtures/api_permissions.json"
