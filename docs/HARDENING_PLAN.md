# Hardening, Live Permissions and Release Plan

Status: PLAN ONLY. No code is changed by this document.
Written 2026-10-29. Facts below were checked in the repo on that date; items marked (research) come from general
industry guidance (blogs, not OWASP primary pages) and should be re-checked against MASVS/MASTG before the store release.

Rules that stay in force: web code is never edited (only additive API changes); every phase ends with
`bash tool/check.sh` ALL GOOD, a release APK that prints "Built ...apk", install on the owner's phone, and a
"what to test" list.

---

## 0. What exists today (verified)

| Area | Today | Where |
|---|---|---|
| HTTP | Dio, one `ApiClient`; interceptors: auth, retry (GET only), log | `lib/core/network/api_client.dart` |
| Token | `flutter_secure_storage` (Keystore) | `lib/core/storage/storage.dart` |
| Session | `SessionController` (Loading / SignedOut / SignedIn / UpdateRequired); cold start calls `/bootstrap` | `features/auth/application/session_controller.dart` |
| Permissions | `AuthUser.can()` and `AppModules[...]`, 37 uses, all reactive through `currentUserProvider` | `features/auth/domain/auth_user.dart` |
| Route guard | `guardRedirect` + `allowedFor`; re-runs on every `SignedIn` state | `core/router/app_router.dart`, `features/shell/nav_model.dart` |
| 401 | interceptor -> `expire()` -> SignedOut | `api_client.dart`, `bootstrap.dart` |
| 403 | becomes `ForbiddenFailure`, nothing else happens | `api_client.dart` |
| App resume | not handled anywhere | - |
| `X-Permissions-Version` | not read; server does not send it yet | - |
| Token life | server already sets 30 days (`api_v1.token_days`), returns `expires_at`; app reads it and ignores it | `AuthController.php`, `auth_repository.dart` |
| Release signing | debug keystore | `android/app/build.gradle.kts` |
| Cleartext HTTP | enabled in the main manifest | `AndroidManifest.xml` |
| App id | `com.example.barbershop_app` | `android/app/build.gradle.kts` |
| Obfuscation / crash reports | none | - |
| Git | neither the app nor the web project is a git repository | - |
| Images | `Image.network` (no disk cache) although `cached_network_image` is a dependency | `pick_row.dart` |
| Junk | `hs_err_pid*.log`, `replay_pid*.log` JVM crash logs inside `android/` | `android/` |

---

## 1. Order of work (and why)

```
Phase A  Safety net        git, backups, clean junk             (1 hour, blocks nothing, protects everything)
Phase B  Live permissions  the original request                 (the user-visible win)
Phase C  Release basics    keystore, HTTPS, app id, backup flags (store blocker)
Phase D  Observability     crash reports, obfuscation symbols   (you must see failures)
Phase E  Session hardening token expiry, idle lock (admin)      (security)
Phase F  Performance       images, startup, size, profile run   (measure first)
Phase G  Long-term         CI, dependency routine, 16 KB check  (stays healthy)
```

A first because every later phase edits many files. B before C because it is the thing the owner asked for and it
needs no store account. C and D must both be done before any staff member uses the app daily.

---

## Phase A - Safety net

| # | Task | Done when |
|---|---|---|
| A1 | `git init` the app; first commit; `.gitignore` already exists. Add `key.properties`, `*.jks`, `*.keystore`, `symbols/` to it BEFORE the first commit | `git status` clean, secrets not tracked |
| A2 | Private remote (GitHub private repo) so a dead laptop does not lose the project | pushed |
| A3 | Same for `rosen_barber` is the web developer's decision; we only keep our additive patches in `backend_api_patch/` and list each one in `docs/WEB_DEV_FIXES.md` | list is current |
| A4 | Delete `android/hs_err_pid*.log` and `replay_pid*.log`; add them to `.gitignore` | gone |
| A5 | Copy the DB backup + seed tooling note into `tool/seed/README` (restore command) | exists |

Risk: none. Do first.

---

## Phase B - Live permissions (no logout needed)

**STATUS 2026-10-29: IMPLEMENTED** (server header + `permissions_version`, `ApiClient` interceptor, `SessionController.syncPermissions`,
resume listener in `app.dart`, "access updated" note in `AppShell`). Tests: `test/core/permissions_header_test.dart` (7),
`test/features/auth/live_permissions_test.dart` (15), one widget test in `auth_flow_test.dart`. Deviations from the text
below: the refresh call is `/bootstrap` (not `/auth/me`); the version is read from `user.permissions_version`
(login also returns it, but the app gets it through the bootstrap that follows). Server notes: `WEB_DEV_FIXES.md` Q65.

### B0. Decision record (blunt)
* Use the existing `/bootstrap` as the refresh call. It already returns user, permissions and modules and drives the whole
  UI. `/auth/me` returns only `user` and would need a server change. Plan text in the request says `/auth/me`; our
  contract is `/bootstrap`. `refreshMe()` in the request = `SessionController.refreshBootstrap()` here.
* Server header `X-Permissions-Version` does not exist yet. The app logic is built to switch on when the header appears;
  until then resume and 403 are the triggers. Server addition is a small additive middleware (see B7), needs owner OK.

### B1. Server contract (additive, optional but recommended)
1. Compute `permissions_version` = short hash of (role, roles, permissions, revoked permissions, staff scope).
2. Add it to the `/bootstrap` data and the login response (`data.permissions_version`).
3. Middleware adds header `X-Permissions-Version` to every authenticated response.
4. Tests: change a role in DB -> hash changes; unrelated change -> hash same.

### B2. App - data
* `Bootstrap` gets `permissionsVersion` (nullable String). Absent -> null.
* Stored in the existing cached bootstrap JSON (nothing new to persist).

### B3. App - `PermissionsSync` service (one new file, provider-free core + Riverpod wrapper)
Responsibilities, all in one place:
* `onServerVersion(String? v)`: if `v` is non-null, differs from the current version, and a refresh is not running ->
  `refresh()`.
* `refresh({reason})`: **single-flight** (hold the in-flight `Future`; callers share it), **debounce** 3 s after the last
  finish, background mode.
* Background mode differs from `refreshBootstrap` today: no offline fallback (never flip the app to the "offline"
  banner from a silent refresh), swallow every `Failure` except 401, 401 -> `expire()`.
* If the new bootstrap equals the old one (same version, or same permissions+modules) -> do NOT replace state (no rebuild,
  open forms keep their text).
* If the new bootstrap is `UpdateRequired` -> go there (existing behaviour of `_gate`).

### B4. App - triggers
| Trigger | Rule |
|---|---|
| Response header differs | interceptor calls `onServerVersion` (ignores `/bootstrap` and `/auth/*` paths) |
| HTTP 403 | interceptor calls `refresh(reason: 403)` once; the failure still reaches the screen |
| App resume | one `AppLifecycleListener` in `app.dart`; refresh if >= 60 s since last refresh |
| Cold start | unchanged (`restore()` already calls `/bootstrap`) |
| Pull-to-refresh | profile page only today; leave |
| Timers / polling | none |

Interceptor wiring follows the existing `onUnauthorized` pattern: `ApiClient` gets `onServerVersion` and `onForbidden`
callbacks; `providers.dart` connects them. The design system stays provider-free.

### B5. App - UX when access changes
* A removed permission: `guardRedirect` already sends the user to `/app/home` (deep link and back stack included).
  Add a one-line toast on that redirect: "Your access was updated by an administrator."
* An added permission: the menu simply appears; no toast needed. Optional small dot on "More" (decide after seeing it).
* A 403 on a tap: the existing error mood plus the silent refresh; buttons vanish afterwards.
* Forms in progress: never rebuilt (see B3, unchanged state is not replaced).

### B6. Central helpers
`can()` and `AppModules` already exist and are used in 37 places. Add only:
* `ref.can('perm')` / `ref.hasModule('key')` extension sugar? **Decision: skip** unless a screen needs it; do not churn 37
  call sites for style. Instead add a test that fails if a page uses a role-name check (grep guard in `check.sh`).

### B7. Tests (must exist before the APK)
* Unit: single-flight (10 parallel header hits -> 1 call); debounce; 3 s window; background refresh swallows
  NetworkFailure; 401 expires; unchanged data does not change state identity.
* Widget: SignedIn with permission removed -> redirect + toast; form text survives an unchanged refresh.
* Interceptor: header read case-insensitively; `/bootstrap` response does not trigger itself (no loop!).
* Resume: fake lifecycle events, 59 s vs 61 s.
Loop risk to test explicitly: refresh -> its own response carries the header -> triggers refresh. Guard by path.

### B8. Manual test list (on the phone, admin + staff)
1. Remove "invoices" permission on web -> in app do any call -> Invoices disappears, no logout.
2. Add it back -> next call or resume -> appears.
3. Background the app for 2 min, change on web, reopen -> updated.
4. Tap an action whose permission was just removed -> friendly message, UI refreshes.
5. Fire many requests at once (calendar + home) with a new version -> server log shows ONE `/bootstrap`.
6. Revoke token on web -> app goes to Sign in with the "session ended" message.
7. Airplane mode + resume -> no offline banner flip, no crash.

Estimate: B1 0.5 day, B2-B6 1 day, tests 0.5 day.

---

## Phase C - Release basics (store blockers)

| # | Task | Notes |
|---|---|---|
| C1 | Choose the final `applicationId` (e.g. `ca.rosenthalbarbershop.app`). It can never change after the Play release | OWNER DECISION |
| C2 | Create the upload keystore; `android/key.properties` (git-ignored); `signingConfigs.release` in `build.gradle.kts`; release uses it | back up the .jks in TWO places + password manager; losing it = no more updates (Play App Signing softens this, still do it) |
| C3 | Cleartext only in debug: move `usesCleartextTraffic` to `android/app/src/debug/AndroidManifest.xml` and `profile/`; main manifest has none | needs the production API on HTTPS first |
| C4 | `android:allowBackup="false"` and `dataExtractionRules` excluding everything | token is in Keystore, cache is not worth backing up |
| C5 | Production `API_BASE_URL` + `FLAVOR=prod` build command in `docs/COMMANDS.md` | HTTPS only; check TLS grade |
| C6 | App name, icon, splash final (already native assets); version/build number scheme | semver `1.0.0+1` |
| C7 | Network security config: system CAs only; no user CAs in release | one small XML |
| C8 | `minSdk`: keep Flutter default; check the shop's oldest phone | - |
| C9 | Build artefacts: `.apk` for sideload, `.aab` for Play | |

Gate for C: `adb shell dumpsys package <id> | grep -i cleartext` shows no cleartext in release; `apksigner verify` shows
the release cert, not "Android Debug".

Estimate: 0.5-1 day (HTTPS availability is the unknown).

---

## Phase D - Observability

| # | Task | Notes |
|---|---|---|
| D1 | Crash reporting: **Sentry** (recommended) or Firebase Crashlytics. Initialise in `bootstrap.dart`, wrap `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.onError` (we already have `_calmErrors`) | DSN via `--dart-define`, empty in dev |
| D2 | Scrub: no tokens, no names, emails, phone numbers, no request bodies; user id only | privacy for Canadian clients (PIPEDA/Alberta PIPA, research - confirm with a lawyer if needed) |
| D3 | Release build flags `--obfuscate --split-debug-info=symbols/<version>`; upload symbols to Sentry; keep `symbols/` private and versioned | without the symbols crashes are unreadable |
| D4 | Breadcrumbs: screen changes and API path + status (we already log one line per call in debug) | no bodies |
| D5 | Release health: crash-free session rate visible | alert on a new issue by e-mail |

Gate: force a test crash in a release build, see it readable in the dashboard, with no personal data.
Estimate: 0.5 day.

---

## Phase E - Session hardening

| # | Task | Notes |
|---|---|---|
| E1 | Use `expires_at`: store it with the token; at resume, if < 3 days left, show a calm "sign in again soon" note; if expired, go to Sign in without waiting for a 401 | server already issues 30-day tokens |
| E2 | Server: consider shorter token life for the admin role (7-14 days) via `api_v1.token_days` by role | additive, OWNER DECISION |
| E3 | Idle lock for **admin** accounts: after N minutes in background, require biometric/device credential (`local_auth`). Staff: off by default. Settings switch | optional; a phone left on the counter exposes money data |
| E4 | Sign out clears: token, read cache, any image cache of private data | already clears token + cache; verify with a test |
| E5 | Clipboard / screenshots: no change (the owner shares reports) | decision recorded |
| E6 | Deep-link audit: none exported besides MAIN; keep it so | manifest check in review |
| E7 | Do NOT add: certificate pinning (renewal would brick every phone), root detection (bypassable, false positives), offline write queue (money) | decisions recorded |

Estimate: 1 day (E3 +0.5).

---

## Phase F - Performance

Measure first, then change. Profile mode on the oldest staff phone.

| # | Task | Gate |
|---|---|---|
| F1 | Baseline: cold start time, home -> calendar -> invoice flow with `FRAME_LOG=true`; record in `docs/PERF.md` | numbers written down |
| F2 | Replace `Image.network` in `PickRow` (and other photos) with `cached_network_image` (already a dependency): disk cache, `memCacheWidth` | second open of the sheet shows images instantly |
| F3 | Server thumbnails: ask the web developer for a 200 px variant or a `?w=` resize param (images are up to 1.7 MB today). Until then the app downsamples only after download | WEB DEV ITEM -> `WEB_DEV_FIXES.md` |
| F4 | Release flags: `--split-per-abi` for sideload APKs, AAB for Play, `--tree-shake-icons` (default) | size recorded before/after |
| F5 | Startup: defer non-critical work after first frame; keep splash animation; check `bootstrap()` main path | cold start target < 2.5 s on the old phone (set after F1) |
| F6 | Rebuild audit: `ref.watch(currentUserProvider)` on big pages causes full rebuilds on every refresh; after B3 (unchanged state is not replaced) this is acceptable; otherwise use `select` | no jank in FRAME_LOG |
| F7 | List screens: confirm `ListView.builder` and const constructors; calendar already culled | |
| F8 | Dependencies: remove unused (`video_player`? `printing`/`pdf` only if used) after a usage grep | smaller APK |

Estimate: 1-1.5 days.

---

## Phase G - Long-term health

| # | Task | Notes |
|---|---|---|
| G1 | CI (GitHub Actions): `flutter analyze`, `flutter test`, build debug APK on every push | same steps as `tool/check.sh` |
| G2 | Monthly routine: `flutter pub outdated`, upgrade, run check.sh, review changelogs of `dio`, `flutter_secure_storage`, `go_router` | calendar reminder |
| G3 | Google Play 16 KB page-size and target-SDK rules (enforced in 2026, research): build with the current Flutter stable and current plugins; verify with Play Console pre-launch report or `zipalign -c -P 16` | do before the first store upload |
| G4 | API contract tests: parse fixtures of each endpoint; unknown or missing fields must not crash (models already tolerant) | |
| G5 | Min-app-version gate stays (bootstrap `min_app_version`) | |
| G6 | Release checklist file `docs/RELEASE_CHECKLIST.md`: version bump, symbols upload, changelog, tag in git, APK/AAB checksum | |
| G7 | Accessibility + text-scale pass (plan Phase 12 item) | |
| G8 | Play listing: privacy policy URL, data-safety form (collects: name, email, phone of customers - staff-facing), content rating | OWNER |

---

## 2. Decisions (taken 2026-10-29, owner delegated: "decide with best practice")

| # | Question | Decision | Why |
|---|---|---|---|
| 1 | App id | `ca.rosenthalbarbershop.app` (Android `applicationId` and iOS bundle id, test target `.RunnerTests`) | Reverse-DNS of the shop's own domain (the web sends mail from `noreply@rosenthalbarbershop.ca`, so the domain exists). Never `com.example.*`; cannot change after the first store release. **Check the owner controls rosenthalbarbershop.ca; if not, tell me and we pick another before C1.** |
| 2 | HTTPS | Production API must be HTTPS-only on the shop's domain (suggested `https://app.rosenthalbarbershop.ca` or the existing web host). Today `.env` is `APP_URL=http://localhost/...` and `APP_ENV=local`, so no production server exists yet. | Cleartext is removed from release builds (C3). Until the server is deployed, phases B, D, E, F proceed against local dev; C3/C5 wait for the real URL. Web side (not us): valid TLS cert, HSTS, `APP_ENV=production`, `APP_DEBUG=false`. |
| 3 | Distribution | Sideload signed APK now (staff phones), **Play Store internal/closed testing track as the target** for 1.0 | Play gives auto-update, Play App Signing (key-loss insurance), and the 16 KB / target-SDK checks. Sideload has no update path for non-technical staff. Ship the same signed build to both. |
| 4 | `X-Permissions-Version` | YES, build it (B1) | Without it, "permission added" is invisible until resume; 403 only catches removals. Small additive middleware + hash. |
| 5 | Biometric/idle lock | YES for Admin role (after 5 min in background), OFF for Staff by default, switch in settings | Admin sees money and can change roles; staff phones are personal and always with them. Use `local_auth` with device-credential fallback. |
| 6 | Crash reporting | Sentry (EU/Canada region if offered), `sendDefaultPii=false`, user id only | Good Flutter obfuscation-symbol support, free tier enough, scrubbing hooks. Firebase would add Google services files and analytics defaults we do not need. |
| 7 | Token life | Staff 30 days (unchanged). Admin 14 days, via `api_v1.token_days` chosen by role at login (server-side, additive) | Balance: admins sign in rarely but hold the highest power; 7 days would annoy daily use, 30 is long for a role that can edit roles. With E1 the app warns 3 days before expiry. |

Owner answers (2026-10-29): the live web site already runs on HTTPS but has NO mobile APIs yet. The owner builds and
tests the APIs in the local web project (allowed to add APIs only); the web developer then deploys them to the live
server. So: production base URL = the live site's HTTPS URL + `/api/v1` (exact URL still to be filled in, see H1);
decision 2 is settled (HTTPS exists); decision 1 (domain ownership) is still unconfirmed. The deployment is done by the
web developer, so Phase H (hand-off package) was added.

Still open: the live site URL and the domain ownership check. Everything else in the plan is unblocked.

---

## Phase H - API hand-off to the web developer (added 2026-10-29)

Because the live server has no APIs yet, the app and the live server must go out together, in a safe order.

| # | Task | Notes |
|---|---|---|
| H1 | Record the live URL in `docs/COMMANDS.md` (prod `API_BASE_URL`); confirm `https://<live>/api/v1/health` style check once deployed | owner gives the URL |
| H2 | One **deploy package** for the web developer: list of new/changed files (the additive API code only), new routes, migrations (if any), config keys (`api_v1.*`, token days), `.env` values, cache/route clear commands. Source is `backend_api_patch/` + `WEB_DEV_FIXES.md`; keep it current at the end of every phase | web dev must not need to read our app |
| H3 | **Zero-risk rule**: every API change is additive; no existing web route, view, controller behaviour or table column is altered. Verify with a diff review before hand-off | web admin panel keeps working untouched |
| H4 | Migrations safe to run live: only new tables/columns, nullable, reversible `down()`; DB backup before running | |
| H5 | Staging step: web developer runs the package on a copy (or the live server with the API route group switched by a config flag) and runs our contract smoke script (`tool/live/`) | script prints PASS/FAIL per endpoint |
| H6 | Rollout order: (1) deploy API, (2) smoke test, (3) give the app build with the live URL, never the other way round | the app's `min_app_version` gate protects old builds |
| H7 | Production server checks (web dev): `APP_ENV=production`, `APP_DEBUG=false`, valid TLS, HSTS, rate limits on, logs not public, `storage/` and `.env` not web-reachable | list handed over |
| H8 | After go-live: a day-in-shop dry run with the release build; watch Sentry and the server log for 401/403/500 spikes | |
| H9 | Seed/demo data is LOCAL ONLY. `tool/seed/seed_demo.php` must never be run on the live database | documented warning in the package |

Phase C3 (remove cleartext from release) can be done now, since the live site is HTTPS.

### H-note: how the web project reaches the web developer (NOT decided yet, owner 2026-10-29)
Options still open: zip the whole web project, or push it to git. The plan works with either, so nothing is blocked:

* We always keep a **self-contained API package** (only the additive files + routes snippet + migrations + config +
  deploy steps + smoke script). This is the thing the web developer applies, whatever the transport.
* If **git**: preferred. Put the API work on its own branch (`feature/mobile-api`) so the web developer reviews a diff
  and can revert it with one command. Never commit `.env`, `storage/`, `vendor/`, uploads or the local DB.
* If **zip of the whole project**: rule: the web developer must NOT replace the live project with it (that would
  overwrite the live `.env`, uploaded images, `storage/` and any live-only edits). He copies only the files listed in
  the package manifest. We also ship a `MANIFEST.txt` (file list with checksums) and exclude `.env`, `vendor/`,
  `storage/`, `public/uploads`, `node_modules`, logs.
* Either way the local `.env` (`APP_ENV=local`, local DB) never leaves this PC.

## 3. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Lost keystore | cannot update the app | two backups + Play App Signing |
| Refresh loop (header on the refresh response) | hammering the server | ignore auth/bootstrap paths; test |
| Silent refresh shows "offline" | confusing banner | background mode without offline fallback |
| Rebuild wipes a form | lost work | do not replace unchanged state; widget test |
| Obfuscation without symbols | unreadable crashes | automate symbols save + upload |
| HTTPS not ready | cannot ship C3 | do B, D, F first; C3 last |
| Server images huge | slow sheets on mobile data | F2 now, F3 with web dev |

## 4. Definition of done for "ready for staff"

* A, B, C, D finished, E1 done, F1 baseline recorded.
* Release APK signed with the release key, HTTPS only, obfuscated, crash reports verified.
* Owner's day-in-shop dry run with both roles passes with no logout surprise.
