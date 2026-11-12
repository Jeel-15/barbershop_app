# Run the app on your phone

Your setup (checked 2026-10-23): Windows PC and the Samsung phone (SM-G781B, Android 13) are on the same Wi-Fi (`192.168.0.x`).
Apache (Laragon) listens on all addresses, port 80, so the phone can reach the API at

```
http://<PC Wi-Fi address>/rosen_barber/public/api/v1      # today: http://192.168.0.194/rosen_barber/public/api/v1
```
(`ipconfig` shows the PC address under "Wireless LAN adapter Wi-Fi". If the router hands out a new address, use the new one.)

## 1. Install the release build (fast, realistic: use this to judge speed)

```bash
cd J:\barbershop_app\barbershop_app
flutter build apk --release --target-platform android-arm64 ^
  --dart-define=API_BASE_URL=http://192.168.0.194/rosen_barber/public/api/v1 ^
  --dart-define=FLAVOR=dev
flutter install -d 192.168.0.195:41245        # the phone's wireless-debugging address (see `flutter devices`)
```
The APK is `build\app\outputs\flutter-apk\app-release.apk`: you can also copy it to the phone (USB, Drive, WhatsApp to yourself) and open it (allow "install unknown apps" once).

## 2. Live coding with hot reload (debug build)

```bash
flutter run -d 192.168.0.195:41245 --dart-define=API_BASE_URL=http://192.168.0.194/rosen_barber/public/api/v1
```
Press `r` for hot reload. Debug builds are slower than release: do not judge speed in debug.

## 3. Check the connection inside the app

On the welcome screen **long-press "ROSENTHAL"** (top left) -> **Design gallery** -> the Wi-Fi icon at the top right opens **Connection test**:
green = the phone reaches the API, database and schema are fine; red tells you what failed.

## If the phone cannot reach the PC

1. Phone and PC must be on the **same Wi-Fi** (not guest Wi-Fi, not mobile data).
2. Windows Firewall must allow port 80 for the private network. In an **Administrator PowerShell**:
   ```powershell
   New-NetFirewallRule -DisplayName "Laragon Apache 80" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -Profile Private
   ```
3. Open `http://192.168.0.194/rosen_barber/public/api/v1/health` in the phone's browser: you should see `{"status":1,...}`.
4. USB alternative (Android): `adb reverse tcp:8081 tcp:80` (Android refuses port 80: "Permission denied"), and the app uses `http://localhost:8081/rosen_barber/public/api/v1` (now also its default when no `API_BASE_URL` is given). In VS Code pick the launch entry "Barbershop (phone on USB, local server)".
5. Away from home: a tunnel (ngrok is already on this PC): `ngrok http 80`, then use the https address it prints.

## Build flavors

| `--dart-define` | Meaning |
|---|---|
| `API_BASE_URL=...` | where the API lives (defaults to `http://localhost:8081/rosen_barber/public/api/v1`) |
| `FLAVOR=dev` (default) / `staging` / `prod` | `prod` hides the review tools (gallery, connection test) and must also turn off cleartext http (Phase 12) |

## One command before every hand-over

```bash
bash tool/check.sh        # format, analyze, all tests
```
