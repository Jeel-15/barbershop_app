# Commands cheat-sheet (Windows)

Project folder: `J:\barbershop_app\barbershop_app` (Flutter app) and `J:\laragon\www\rosen_barber` (Laravel web + API).
Use **PowerShell** unless a line says otherwise. Replace `PHONE` with the phone's `IP:PORT` shown in
*Settings > Developer options > Wireless debugging* (the port changes every time you switch it on).

```powershell
$adb = "C:\Users\jeelp\AppData\Local\Android\Sdk\platform-tools\adb.exe"
```

---

## 1. Start the local server (do this first, the app needs it)

Laragon sometimes stops Apache/MySQL. Easiest: open **Laragon** and press **Start All**.

If you want it from the terminal:

```powershell
# MySQL
Start-Process "J:\laragon\bin\mysql\mysql-8.0.30-winx64\bin\mysqld.exe" -ArgumentList "--defaults-file=J:\laragon\bin\mysql\mysql-8.0.30-winx64\my.ini" -WindowStyle Hidden
# Apache
Start-Process "J:\laragon\bin\apache\httpd-2.4.54-win64-VS16\bin\httpd.exe" -WindowStyle Hidden -WorkingDirectory "J:\laragon\bin\apache\httpd-2.4.54-win64-VS16\bin"
```

Check that the API answers (should print `200`):

```powershell
(Invoke-WebRequest -UseBasicParsing http://localhost/rosen_barber/public/api/v1/health).StatusCode
```

---

## 2. Connect the phone (wireless)

On the phone: *Developer options > Wireless debugging > on*. Phone and PC must be on the **same Wi-Fi**.

```powershell
& $adb mdns services                 # shows the phone's IP:PORT (the line with 192.168.0.195:xxxxx)
& $adb connect PHONE                 # e.g. 192.168.0.195:40251
& $adb devices                       # must say "device" (not "offline")
```

First time only (pairing): *Wireless debugging > Pair device with pairing code*, then

```powershell
& $adb pair PAIR_IP:PAIR_PORT        # type the 6-digit code when asked
```

If the connection drops: switch Wireless debugging **off and on**, then run `& $adb mdns services` again (the port is new).

---

## 3. Let the phone reach the local API (every time you reconnect)

The app is built to call `localhost:8081`, so forward that port to the PC's port 80:

```powershell
& $adb -s PHONE reverse tcp:8081 tcp:80
& $adb -s PHONE reverse --list       # should show tcp:8081 tcp:80
```

(Port 80 itself cannot be used on Android, that is why it is 8081.)

---

## 4. Build and install the app

```powershell
cd J:\barbershop_app\barbershop_app

# Build (about 2 minutes)
flutter build apk --release --target-platform android-arm64 `
  --dart-define=API_BASE_URL=http://localhost:8081/rosen_barber/public/api/v1 `
  --dart-define=FLAVOR=dev

# Install on the phone and open it
flutter install -d PHONE
& $adb -s PHONE shell monkey -p ca.rosenthalbarbershop.app -c android.intent.category.LAUNCHER 1
```

The APK file is also here, if you want to copy it to the phone by hand:
`J:\barbershop_app\barbershop_app\build\app\outputs\flutter-apk\app-release.apk`

Faster while developing (hot reload, needs the phone connected):

```powershell
flutter run -d PHONE --dart-define=API_BASE_URL=http://localhost:8081/rosen_barber/public/api/v1 --dart-define=FLAVOR=dev
```

Over the Wi-Fi without `reverse`: use the PC's address instead (phone and PC on the same Wi-Fi, firewall must allow port 80):
`--dart-define=API_BASE_URL=http://192.168.0.194/rosen_barber/public/api/v1`

---

## 5. Check the code (before you trust a build)

```powershell
cd J:\barbershop_app\barbershop_app
bash tool/check.sh          # format + analyze + all tests (needs Git Bash)
flutter analyze             # only the analyzer
flutter test                # only the tests
dart format lib test tool   # tidy the code
```

---

## 5b. Live audit against the local API

```powershell
# The app's real repositories against http://localhost/rosen_barber/public/api/v1 (laragon must run).
# Creates rows named "ZZ AUDIT ..." / phone 7805559993 and removes them again
# (the web only soft deletes some of them, see WEB_DEV_FIXES Q64).
flutter test -j 1 tool/live

# Every test on a 320x640 phone with 1.6x text (overflow check; a few finders cannot see off-screen widgets there)
$env:SMALL='1'; flutter test
```

---

## 6. Test accounts and demo data

| Who | E-mail | Password |
|---|---|---|
| Admin | `apitest.admin@rosen.test` | `Rosen@12345` |
| Staff | `apitest.staff@rosen.test` | `Rosen@12345` |

Demo bookings have the note `APITEST-home`. To remove them from the local database (PowerShell):

```powershell
$m = "J:\laragon\bin\mysql\mysql-8.0.30-winx64\bin\mysql.exe"
& $m -uroot barber_shop_db -e "delete from tbl_appointment_service where appointment_id in (select appointment_id from tbl_appointment where notes='APITEST-home'); delete from tbl_appointment where notes='APITEST-home'; delete from customers where customer_phone like '780555%';"
```

Quick look at the database:

```powershell
& $m -uroot barber_shop_db -e "select appointment_id,date,status,is_invoiced,name from tbl_appointment order by appointment_id desc limit 10;"
```

---

## 7. Laravel / API (only when you change the backend)

```powershell
cd J:\laragon\www\rosen_barber
$php = "J:\laragon\bin\php\php-8.3.1-nts-Win32-vs16-x64\php.exe"
& $php artisan route:list --path=api/v1      # all app API routes
& $php -l app\Http\Controllers\Api\V1\CalendarController.php   # syntax check one file
& $php artisan config:clear                  # after editing config/api_v1.php
& $php artisan cache:clear
```

Do **not** run `php artisan migrate` on this database (the tables already exist, it would fail).

After changing API files, copy them into the bundle that goes to the live server:
`J:\barbershop_app\barbershop_app\backend_api_patch\` (same folder structure). Never copy `.env`.

---

## 7b. Things that go wrong

| Problem | Fix |
|---|---|
| App says "No connection" | Step 1 (server running?) then step 3 (`reverse`). Phone's Wi-Fi/data must be on. |
| `adb devices` shows nothing / offline | Step 2: switch Wireless debugging off/on, `mdns services`, `connect`. |
| `flutter install` says "No target device" | Phone not connected: step 2. |
| Build fails on a file lock | Close the app on the phone, run `flutter clean`, build again. |
| API returns 500 after editing PHP | `php -l file.php` for a syntax error, look at `storage\logs\laravel.log`. |

---

## 8. Useful files

| File | What |
|---|---|
| `docs/APP_PLAN.md` | the 13-phase plan |
| `docs/API_PLAN.md` | every API endpoint and the web quirks |
| `docs/WEB_DEV_FIXES.md` | the list to give the web developer |
| `docs/RUN_ON_PHONE.md` | older phone setup notes |
| `backend_api_patch/` | the API files to put on the live server |

---

## Status bar and system bars

- The app draws behind the status bar and the bottom bar (`SystemUiMode.edgeToEdge`); both are transparent.
- `SystemBars` (`lib/design_system/components/system_bars.dart`) picks readable icons: light icons on a dark screen, dark icons on a light one. It wraps the whole app (follows the theme); the splash and the welcome screen are always dark and say so (`lightIcons: true`).
- Native launch window (`android/app/src/main/res/values*/styles.xml`): brand ink background, transparent bars, white icons, `shortEdges` (draws under the camera cut-out, no black strip in landscape), and on Android 12+ the system splash is ink with the crest.
- A pushed screen rises on its own still background (`AppPageTransitionsBuilder`); without it the strip it left at the top showed the near-black splash underneath.
