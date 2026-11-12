# Biometric login / app lock: research, plan, review

Status: plan v2 (after review), 2026-10-29. Owner ask: "biometric login like other mobile apps".
Rules in force: web code untouched; no server change needed for this feature; test on the owner's phone and on an emulator.

---

## 1. What "biometric login" means here (and what it must not mean)

Other apps do one of three things. Only the first two fit this app.

| Model | How it works | Fit |
|---|---|---|
| **A. Unlock the saved session** | Sign in once with the password; the session token stays on the phone, locked behind the fingerprint/face. Opening the app (or returning after a while) asks for the biometric instead of the password. | **Chosen.** Works with our Sanctum tokens, needs no server change. |
| B. Device-bound key ("passkey style") | The phone holds a key pair; the server stores the public key; biometric signs a server challenge to get a new token (works after sign-out / token expiry). | Best long-term, but needs new API tables/endpoints and a web deploy. **Recorded as a later upgrade** (section 9). |
| C. Store the password and replay it | The password sits on the phone behind the biometric. | **Rejected.** A password must never be stored; this is what the OWASP guidance warns against. |

The password stays the root of trust. Biometric is a convenience in front of an already-signed-in session: sign out, a revoked token, or a token that ran out (30 days) all end in the password screen, as today.

---

## 2. Research (what the evidence says)

Sources are vendor docs, OWASP and the package source on this machine; where a claim comes from a blog it says so.

### 2.1 Security
* **OWASP MASTG (MASTG-TEST-0327, MASTG-BEST-0036):** biometric must be **crypto-bound, not event-bound**. A bare `authenticate()` returning "success" can be faked by hooking the callback; the secret must be a Keystore key created with `setUserAuthenticationRequired(true)` and used through a `BiometricPrompt.CryptoObject`, with a validity window of 0 (every use needs a fresh biometric). The older `setUserAuthenticationValidityDurationSeconds` is deprecated.
* **Verified in our dependency** (`flutter_secure_storage 11.2.0`, `android/.../KeyCipherImplementationAES23.java`): `AndroidOptions.biometric(...)` generates an AES-GCM Keystore key with `setUserAuthenticationRequired(true)`, `setUserAuthenticationParameters(0, BIOMETRIC_STRONG | DEVICE_CREDENTIAL)`, `setInvalidatedByBiometricEnrollment(true)`, and decrypts through `BiometricPrompt` + `CryptoObject` (`FlutterSecureStorage.java`, `authenticateUser`). `requireBiometricsPerOperation: true` makes every read/write prompt and never caches the key. So the exact OWASP pattern exists in a package we already ship; no native code of our own is needed.
* **Consequences of that key:** adding a fingerprint, removing the screen lock, or a Keystore reset **permanently invalidates** the key. That is the secure behaviour (someone who just enrolled their own finger must not inherit the session). We handle it as "sign in with your password again" (section 5.6). Coinbase Wallet offers the same idea as "Change protection: require recovery phrase if biometrics change" (Mobbin).
* **Strong vs weak:** Class 3 (strong) biometrics, or the phone's PIN/pattern, are accepted. Weak face unlock is not (Android treats it as convenience). `DEVICE_CREDENTIAL` as fallback also covers biometric lock-out (5 bad tries) without us writing lock-out logic; the OS counts the attempts.
* **API levels:** enforced biometric keys need Android 9 (API 28); strong-only fully enforced from API 30; the package minimum is API 23 (ours 24). Phones older than Android 9 simply do not get the feature (the offer is hidden).

### 2.2 Flutter plumbing
* `local_auth 3.0.2` (flutter.dev): `isDeviceSupported()` (a screen lock or biometric exists), `getAvailableBiometrics()` (fingerprint / face / strong / weak, empty = none enrolled). It also has `authenticate()`, but that is event-bound, so **we use it only to decide whether to offer the feature and what to call it** ("fingerprint" vs "screen lock"), never as the gate.
* `flutter_secure_storage` biometric mode errors arrive as `PlatformException` with the Android message `Biometric authentication error [N]: ...` (N = BiometricPrompt code: 10 user cancelled, 13 negative button, 5 cancelled, 7/9 lock-out, 11 none enrolled, 12 no hardware) or `BIOMETRIC_UNAVAILABLE: ...`. We parse N into a small enum in one place.
* `resetOnError` defaults to true (**deletes data when decrypt fails**). We set it to false and delete explicitly, so a cancelled prompt can never erase the session.

### 2.3 UX (Mobbin, iOS references; Mobbin has no Android set)
Patterns seen across Fidelity, N26, Zopa, QuestMobile, Dave, Revolut, Vivid, Deel, Zing, Betterment, GoHenry, Shopee, Trust Wallet, Solflare, Remote:
1. **Offer after the first successful password sign-in**, never at the first launch. Primary "Turn on / Enable / Set up", secondary "Not now / Skip / Maybe later" (all of them). The blogs found say the same (opt-in is much higher after a first success; always keep a password path).
2. **Say what it covers.** Fidelity and GoHenry add: "any fingerprint/face registered on this phone will be able to open the app"; QuestMobile / Shopee: "we never store your fingerprint, the phone does". Worth one short line.
3. **Returning-user screen** (PayPal, Wealthsimple, ShopBack): who you are (name/e-mail), one primary biometric button, a secondary "Try another way / Use password".
4. **Settings toggles** (Splitwise, Plum, Octopus, Oportun, Quicken, Setel, Up): one switch with a one-line explanation; Octopus says "every time you open the app and resume from background"; **Up: "Require log in after three minutes of inactivity"**; Coinbase: "Require unlock when: opening the app / making a transaction".
5. **Failure** (Wealthsimple/Crypto.com/DoorDash): calm sentence + Retry + the alternative; never a dead end. Crypto.com shows the lock-out rule in words.
6. Passcode-only apps (Setel, Crypto.com) are out: the phone's own PIN is already the fallback inside the system prompt.

### 2.4 Timeouts (no standard number; common practice)
Banking apps: lock on every return to the app, or after 1-5 minutes of inactivity. Heritage Bank's FAQ: after a longer idle spell the saved biometric is removed and the full password is needed again. **Our token already ends at 30 days (14 for admin, Phase E)**, which plays that role.

---

## 3. Decisions (v1)

1. Model A, crypto-bound through `flutter_secure_storage` `AndroidOptions.biometric`, `requireBiometricsPerOperation: true`, `enforceBiometrics: true`, `biometricType: biometricOrDeviceCredential`, `resetOnError: false`, its own `storageNamespace`.
2. The session token lives in **either** the normal secure store (feature off) **or** the biometric vault (feature on), never both. In memory it is cached after the first unlock so the HTTP layer never triggers a prompt.
3. **Opt-in for everyone** (owner, staff). Offered after a password sign-in; also a switch in More / Me > Security. Admin accounts are offered at every sign-in until they answer twice; staff the same (kept simple: 2 declines, then only Settings).
4. Lock triggers: cold start, returning after the chosen time in the background, and **foreground inactivity** for the same time (a phone left open on the counter). Choices: Immediately, 1 minute, **5 minutes (default)**, 15 minutes.
5. Unlock UI: one panel (`LockPanel`) used by the full-screen cold-start route and by the overlay shown over the running app (so scroll position and forms survive a short lock).
6. Failure never signs the user out by itself. "Use password instead" does (after a confirm), and so does an invalidated key (with an explanation).
7. No server change. No password storage. No biometric data ever seen by the app.

---

## 4. Architecture

```
lib/core/security/
  biometric_vault.dart        BiometricVault (interface) + SecureBiometricVault (plugin) + VaultFailure (enum, parsed from the platform error)
  biometric_capability.dart   BiometricCapability (interface) + LocalAuthCapability: supported?, kind (fingerprint / face / screenLock)
lib/core/storage/storage.dart
  ProtectedTokenStore         TokenStore + unlock()/protect()/unprotect(); memory cache; plain store <-> vault
  AppPrefs                    biometricEnabled, lockTimeoutSeconds, biometricOfferDeclines
lib/features/lock/
  domain/lock_timeout.dart    LockTimeout enum (immediately, 1m, 5m, 15m)
  application/app_lock_controller.dart   overlay lock: Unlocked | Locked(prompting, failures, message); lifecycle + idle timer; injectable clock
  application/biometric_setup.dart       enable / disable / offer rules (uses vault, capability, token store, prefs)
  presentation/lock_panel.dart           the returning-user panel (crest, name, big biometric button, password link, calm errors)
  presentation/lock_screen.dart          route /lock (cold start)
  presentation/lock_overlay.dart         overlay + privacy cover + back-button block
  presentation/biometric_offer_sheet.dart
  presentation/security_card.dart        More / Me: switch + timeout picker
features/auth/application/session_controller.dart
  SessionLocked state; restore(): protected token -> Locked; unlockWith(token) -> bootstrap; sign-out clears vault
core/router/app_router.dart   guard: SessionLocked -> /lock
app.dart                      lifecycle listener (paused -> remember time, resumed -> maybe lock), overlay, back blocker
```

Cold start with the feature on: `restore()` finds `biometricEnabled` -> state `SessionLocked` (no network call yet) -> router shows `/lock` -> panel auto-prompts -> vault `read()` returns the token -> cached -> `/bootstrap` -> `SignedIn`. A 401 there ends the session as today.

Running app: `paused` stores the time; `resumed` locks if more than the timeout passed (or the clock went backwards); a single resettable timer locks after foreground inactivity. Locking sets `AppLockState.locked`; the overlay covers everything above the Navigator (dialogs and sheets too) and absorbs touches; unlocking = vault `read()` (prompt). The token stays in memory so nothing in flight fails.

---

## 5. UX specification

### 5.1 Offer (after a password sign-in, once the dashboard is up)
Bottom sheet (existing `showAppSheet`): icon in a gold ring, title **"Open Rosenthal with your fingerprint?"** (or "...with your phone's screen lock" when no fingerprint), body "Next time, skip typing your password. Your fingerprint stays on your phone; we never see it.", a quiet note "Anyone whose fingerprint is saved on this phone will be able to open the app.", buttons **Turn on** / **Not now**. Turn on -> the system prompt ("Turn on fingerprint unlock") -> toast "Fingerprint unlock is on".

### 5.2 Lock panel (cold start and overlay)
Crest, "Welcome back" (display serif), the person's name + role chip, a large round fingerprint button with a breathing ring while the prompt is open, primary text "Unlock", secondary "Use password instead", small footnote "Locked to keep the shop safe". The prompt opens by itself the moment the panel appears; if it is cancelled the button stays for a retry. After 3 failed/cancelled tries the retry is still there but the password link becomes the highlighted action with "Having trouble? Use your password."

### 5.3 Settings (More / Me > Security)
Switch "Unlock with fingerprint" (subtitle explains). When on: row "Lock after" -> Immediately / 1 minute / 5 minutes / 15 minutes, subtitle "...when you leave the app or stop using it". Off needs no prompt.

### 5.4 Privacy cover
When the app is inactive/paused and the feature is on, a brand cover replaces the content (hides the Recents thumbnail as far as Android allows).

### 5.5 Copy rules
Plain words; "fingerprint" or "screen lock" (never "biometrics" to staff); errors calm: "That did not work. Try again, or use your phone's PIN." Lock-out: "Too many tries. Wait a moment, or use your password."

### 5.6 Key invalidated (new fingerprint added / screen lock removed)
Silent sign-out of this phone, then the Sign in screen with a banner: "Your phone's fingerprints or screen lock changed, so for your safety please sign in with your password." After the sign-in the offer appears again.

---

## 6. Security analysis
| Threat | Answer |
|---|---|
| Lost phone, screen unlocked, app in background | Overlay lock after the chosen time; privacy cover. |
| Someone adds their fingerprint then opens the app | Key invalidated on enrollment; password required. |
| Rooted phone, storage copied | Token only decryptable through the TEE after a fresh biometric (per-operation key). |
| Hooked "success" callback | Not event-bound: the secret is the decryption itself. |
| Brute force the prompt | OS lock-out counts and escalates to PIN; we add nothing weaker. |
| Clock changed to dodge the timeout | Wall clock; going back = lock; going forward = locks earlier. |
| Token revoked / expired / password changed | 401 -> existing sign-out; vault wiped by `expire()`. |
| Cancelled prompt erases the session | `resetOnError: false`; deletes are explicit only. |
| Token in logs / crash reports | Never logged; the vault returns it only in memory. |
| Backup/restore of preferences without the Keystore key | `biometricEnabled` true but vault unreadable -> treated as "invalidated" -> password. (Also `allowBackup=false`, Phase C.) |

---

## 7. Edge cases (all handled in code and tests)
No lock screen on the phone / no hardware / API < 28 (offer hidden, setting disabled with a hint); user cancels the enable prompt (stays off, no decline counted); enable fails midway (the plain token is only removed after the vault write succeeds); disable while locked (impossible, panel only); app killed in background (cold start = locked); prompt interrupts lifecycle (`inactive` ignored while prompting); rotation (portrait only); text scale 2.0; dark mode; TalkBack labels; double taps; sign out while locked ("Use password instead"); sign out everywhere; account deactivated (401 after unlock).

---

## 8. Test plan
* Unit: `LockTimeout`; `AppLockController` (lock after timeout, immediate, clock back, idle timer reset, no lock while prompting, 3-failure counter, unlock success, invalidated, lock-out message); `ProtectedTokenStore` (cache, switch plain<->vault, failure leaves the plain token, clear wipes both); `VaultFailure` parsing of every platform message; offer rules (supported, not enabled, declines < 2, signed-in only).
* Session: cold start locked -> unlock -> signed in; unlock cancelled stays locked; invalidated -> signed out with message; dead token after unlock -> signed out; sign out clears the vault.
* Widget: lock panel states and wording, offer sheet, security card (switch, timeout picker), overlay blocks taps and back, privacy cover, large text, dark mode.
* Emulator (Android 35, WHPX): set a PIN, enrol a fingerprint, use `adb emu finger touch` for success and a wrong finger, add a second fingerprint to prove invalidation, background/resume timing.
* Owner's phone: real fingerprint; checklist at the end.

---

## 9. Later (not now)
* Model B (device-bound key + server challenge) so biometric also works after sign-out or token expiry; needs additive API tables/endpoints and a web deploy (add to `WEB_DEV_FIXES.md` when we decide).
* iOS: `AppleOptions` already has biometric access control; the Dart layer here is platform-neutral.
* `FLAG_SECURE` while the app is locked (hides the Recents image reliably).

---

## 10. Review of plan v1 (second pass) and what changed

| # | Finding in v1 | Fix in v2 |
|---|---|---|
| 1 | A prompt per read would fire on every HTTP request (the auth interceptor reads the token each time). | `ProtectedTokenStore` caches the token in memory after unlock; the vault is touched only to enable, unlock and delete. |
| 2 | While locked at cold start any stray request would carry no token and a 401 would sign the user out. | Cold start uses a dedicated `SessionLocked` state: the router guard keeps `/app/**` unmounted, `syncPermissions`/401 handlers ignore a non-signed-in state. |
| 3 | `resetOnError: true` (plugin default) could wipe the token after a failed decrypt. | Set to false; explicit deletes only. |
| 4 | Back button would pop the page under the overlay (the overlay is not a route). | An early `WidgetsBindingObserver.didPopRoute` consumes back while locked (registered before the router's). |
| 5 | The BiometricPrompt itself makes the app `inactive`; counting that as "background" would lock the user right after unlocking. | Only `paused` records the time; `inactive` only shows the cover; lifecycle ignored while a prompt is open. |
| 6 | Monotonic clocks stop while the phone sleeps, so a stopwatch would under-count the time away. | Wall clock with the "went backwards = lock" rule. |
| 7 | Idle lock in the foreground was missing (counter phone left open). | One resettable timer fed by a root pointer listener. |
| 8 | Offering the feature on devices without a screen lock ends in an error after the tap. | `local_auth` capability check decides whether to offer and what to call it. |
| 9 | Re-enabling after sign-out would show the offer forever to someone who keeps saying no. | `biometricOfferDeclines` (2 declines, then Settings only). |
| 10 | Weak face unlock on some phones would read as "biometric" but is not accepted. | The label comes from `getAvailableBiometrics`: fingerprint/strong -> "fingerprint", otherwise "phone screen lock". |
| 11 | Disabling must not leave the token unprotected in two places. | Order: write plain, verify, then delete the vault entry; enabling: write vault, verify, then delete plain. |
| 12 | Background refresh / permission sync while the overlay is up could show a toast under it. | Harmless (covered); after unlock a normal resume sync runs. |

Result: plan v2 is the one implemented.
