# Rosenthal Barbershop — Mobile App Master Plan (Admin + Staff)

Written 2026-10-23. Companion to `docs/API_PLAN.md` (the backend, finished: ~170 routes, all tested against the web).
Audience: the owner (to review on a phone after every phase) and whoever maintains the code later.

---

## 0. How this plan works

**Goal.** One Flutter app that does *everything the web admin panel does, for Admin and Staff only* (no customer booking, ever), but faster, clearer and one-handed on a phone.

**The loop for every phase** (this is what makes each phase reviewable):

| Step | What happens | Who |
|---|---|---|
| 1. Design brief | Mobbin research for that phase's screens (queries listed below), decisions written down | me |
| 2. Build | Screens + state + API wiring, all states (loading, empty, error, offline, no-permission) | me |
| 3. Verify | `flutter analyze`, unit/widget tests, rendered screenshots with real fonts, API-backed integration test | me |
| 4. Hand-over | A runnable build + a *phone review checklist* (every phase has one below) | me |
| 5. Review | You run it on your phone, tick the checklist, send feedback (screens / words / "feels slow here") | you |
| 6. Close | Fixes, docs updated, phase marked done, next phase starts | me |

**Rules inherited from the project** (do not change without asking the owner):
1. The web is the contract: same flow, same rules, same numbers. The app may be *better looking and easier*, never *different in outcome*. Web bugs are listed in `API_PLAN.md` section 8 (Q1-Q50) for the web developer; the app mirrors them until the web is fixed.
2. The web code is never edited; the app talks only to `/api/v1`.
3. Local first (`http://localhost/rosen_barber/public`); live deploy later through `backend_api_patch/`.
4. Money is exact: the app never uses floating point for money.

---

## 1. Product decisions

### 1.1 Who uses it and what they need

| Role (from the web) | How the app decides | Main jobs on the phone |
|---|---|---|
| **Admin / Super-admin** (`users.role = Admin`) | server flags from `/bootstrap` | see the shop's day, manage bookings, ring up sales, manage staff/catalog/settings, read reports |
| **Manager** (stored as `Staff` role + many permissions, Q24) | permissions from `/bootstrap` | same as Admin minus reports (web blocks them) |
| **Staff / Barber** | `isStaff` + permissions | my day, my calendar, confirm/cancel, ring up a sale, my earnings, my working hours |
| **Accountant / Owner / POS Manager** | permissions only | whatever their permissions allow (invoices, customers, products...) |

**Navigation and every button are driven by permissions** returned by `/bootstrap` (`modules` + `permissions`), never by role names in the app. A user sees only what the web would let them open.

### 1.2 Information architecture (one-handed, 5 slots)

```
Bottom bar (floating pill, solid surface):
  Home | Calendar | [ + New sale ] | Appointments | More
```
* **Home**: today's numbers and next clients (per role).
* **Calendar**: day view with barber lanes. The biggest screen of the app.
* **+ New sale** (centre, always reachable): the POS. Walk-in revenue is the thing that must be fastest.
* **Appointments**: list with status tabs, search, filters.
* **More** (admin) / **Me** (staff): everything else, as grouped lists (see map below).

```
More (admin/manager)                          Me (staff)
├─ Customers                                  ├─ My earnings (summary, days, services, bookings)
├─ Invoices                                   ├─ My working hours
├─ Reports (admin only)                       ├─ Profile & photo
├─ Catalog: Services · Categories ·           ├─ Appearance · Haptics · About
│  Products · GST · Payment methods           └─ Sign out / sign out everywhere
├─ Shop: Settings · Opening hours · Closures
├─ People: Staff · Roles & permissions
├─ Website: Testimonials · Gallery
└─ Profile · Appearance · About · Sign out
```
Entries a user may not open are **hidden, not greyed** (greyed items invite support calls).

### 1.3 UX principles (the "top of the top UX" checklist)

1. **Thumb zone first.** Primary actions at the bottom (sticky bars, bottom sheets); filters and secondary actions at the top.
2. **Fewest taps for the daily five**: confirm a booking (1 tap), call a customer (1 tap), start a sale (1 tap), see today (0 taps, it is Home), find a customer (type 3 letters).
3. **Skeletons, not spinners**; content appears in place; pull-to-refresh everywhere there is a list.
4. **Optimistic where safe** (confirm, cancel, toggles) with a 5 s **Undo** snackbar; **pessimistic where money or schedule is involved** (invoice, booking, reschedule) with a clear progress state.
5. **Never lose input.** Drafts of forms/carts survive a phone call, a crash, a lock screen. Double-tap protection on every write (button locks; invoices also send an `Idempotency-Key`).
6. **Say what happened and what to do.** Every error has a plain sentence plus an action (Retry, Refresh, Sign in again). Server `request_id` is shown as "Support code" under *Details* so problems can be traced in `api-*.log`.
7. **Shop time, always.** All "today / tomorrow / now" use America/Edmonton even if the phone is elsewhere (decision D14).
8. **Native conveniences**: tap-to-call / WhatsApp / SMS on a customer, share an invoice, camera or gallery for pictures, haptics on confirm/success, numeric keypads for money/phone, system date/time pickers where they are best and wheel pickers for time ranges.
9. **Calm motion**: 150-300 ms ease-out, one motion per intent (state change, hero, success); respects the OS "reduce motion" switch.
10. **Accessible**: 48 px targets, contrast >= 4.5:1, supports large text (layouts reflow, no clipping), semantic labels, no colour-only status (every status pill has an icon + text).

### 1.4 Visual direction

* Continues the splash/welcome identity: **espresso/ink + antique gold**, the real crest as the brand mark. Playfair Display for brand/hero numbers, Manrope for UI. **Fonts are bundled in the app** (no runtime download: works offline, no layout shift).
* **Dark first, light supported from day one** (Settings -> Appearance: System / Dark / Light). All colours are *tokens* with dark and light values, so the second theme costs nothing later.
* **Glass only on hero surfaces** (welcome, headers, sheets). **Lists, calendar and tables use solid surfaces**: blur under scrolling content is the #1 cause of dropped frames on mid-range Android.
* Status colours (shared everywhere): Pending amber, Confirmed green, Rescheduled blue, Completed gold-green, Cancelled red; always icon + label.

---

## 2. Architecture and codebase

### 2.1 Stack (each choice has a reason; fewer, boring, maintained packages)

| Concern | Choice | Why |
|---|---|---|
| State / DI | **flutter_riverpod** (AsyncNotifier, family providers) | compile-time safe, testable, fine-grained rebuilds (`select`), caching + invalidation built in |
| Routing | **go_router** with redirect guards + `StatefulShellRoute` | permission/auth guards in one place, tab state kept alive, deep links later |
| HTTP | **dio** + interceptors | auth header, envelope unwrap, error mapping, request-id logging, retry for idempotent GETs, cancel tokens |
| Models | **freezed + json_serializable** (build_runner) | immutable, equality, copyWith, generated JSON: removes a whole class of bugs |
| Secure storage | **flutter_secure_storage** (token), **shared_preferences** (prefs, small caches) | tokens never in plain prefs |
| Time | **timezone** (America/Edmonton) + **intl** | shop-time correctness |
| Money | own `Money` value class (integer cents, parsed from the API's `"NN.NN"`) | no float errors, exact totals |
| Images | **cached_network_image**, **image_picker**, **flutter_image_compress** | disk cache, <= 2 MB uploads (the API limit) |
| Charts | **fl_chart** | bars, donut, lines; lightweight |
| Native bits | url_launcher (call/WhatsApp/SMS), share_plus, package_info_plus, connectivity_plus | |
| Quality | **very_good_analysis** lints, mocktail, integration_test, golden tests | |
| Crash/diagnostics | Sentry or Firebase Crashlytics (decision D5) | know about problems before the owner does |

*Not used on purpose*: GetX (untestable globals), Bloc (more boilerplate for the same result), Hive/Isar (unneeded; shared_preferences + JSON is enough for the small read cache), heavy UI kits (we have our own design system).

### 2.2 Folder structure (feature-first, layered)

```
lib/
  main.dart  app.dart  bootstrap.dart        # entry, MaterialApp.router, startup (env, tz, fonts, storage)
  core/
    config/      env.dart (dart-define: API_BASE_URL, FLAVOR), feature flags
    network/     dio_client.dart, interceptors/ (auth, envelope, retry, logging), api_exception.dart
    storage/     secure_store.dart, prefs.dart, read_cache.dart
    errors/      failure.dart (Validation/Unauthorized/Forbidden/NotFound/Conflict/RateLimited/Server/Network)
    router/      app_router.dart, guards.dart, routes.dart
    utils/       money.dart, shop_time.dart, debounce.dart, formatters.dart, result.dart
  design_system/
    tokens/      colors.dart, typography.dart, spacing.dart, radii.dart, motion.dart, elevation.dart
    theme/       app_theme.dart (dark + light)
    components/  buttons, inputs, pills, cards, kpi_tile, list_tile, avatar, skeleton, empty_state,
                 error_state, bottom_sheet, confirm_dialog, snackbar_undo, date_strip, segmented,
                 money_text, section_header, filter_chips, charts/
    gallery/     component gallery screen (debug only): the review surface for design
  features/<name>/                           # auth, home, appointments, calendar, booking, pos, invoices,
    data/        <name>_api.dart, dto/, <name>_repository_impl.dart       customers, me, catalog, shop,
    domain/      entities, <name>_repository.dart (interface), rules      staff, roles, reports, content, welcome
    presentation/ screens/, widgets/, controllers/ (Riverpod)
  l10n/                                      # arb ready (English first; Gujarati/French possible later)
test/            mirrors lib/; plus golden/ and integration/
tool/            scripts: gen, preview screenshots, api smoke against local Laravel
```
**Rules:** presentation never calls Dio; a feature never imports another feature's `presentation`; shared UI lives only in `design_system`; business rules (e.g. which actions an appointment allows) come from the server (`appointment_actions` in `/bootstrap`) so the app cannot drift from the web.

### 2.3 Data flow and caching

```
Widget -> Controller (AsyncNotifier) -> Repository -> Api (Dio) -> /api/v1
                         ^                    |
                         +-- read cache (stale-while-revalidate, TTL per resource)
```
* **Stale-while-revalidate**: show cached data instantly, refresh in the background, update in place (no flicker). TTLs: bootstrap 10 min, catalog 10 min, today's appointments 30 s, calendar day 30 s, reports 2 min.
* **Rate limit budget** (server: 240 req/min per user): each screen opens with <= 3 calls; providers dedupe in-flight requests; list screens cancel requests on leave; search is debounced 350 ms; calendar auto-refresh every 60 s only while visible + on app resume.
* **Pagination**: infinite scroll with `page/per_page`, prefetch the next page at 70% scroll.
* **Optimistic updates** go through one helper (apply -> call -> rollback on failure -> snackbar).

### 2.4 Errors, validation, auth (one place each)

* The API envelope (`{status, message, data, meta}` / `{status:0, message, errors, request_id}`) is unwrapped in one interceptor into either data or a typed `Failure`.
* **422** -> field errors mapped onto the form fields (`errors.<field>`); **409** -> dialog with the server's sentence + automatic refresh of the stale screen; **403** -> "You do not have permission" and the entry disappears after the next `/bootstrap` refresh; **401** -> clear token, go to Sign in, keep the user's place in the stack; **429** -> back-off + "Slow down a moment" (uses `Retry-After`); **5xx/timeout** -> friendly retry with Support code.
* Token: 30-day Sanctum bearer in secure storage; `/bootstrap` on every cold start (user, permissions, modules, feature flags, min app version); `min_app_version` blocks outdated builds with an update screen.

### 2.5 Quality gates (every phase)

* `flutter analyze` clean (very_good_analysis), `dart format` clean.
* **Tests per feature**: repository tests (mock Dio), controller tests (Riverpod overrides), widget tests for every screen state, golden tests for design-system components, and **API integration tests** that run against the local Laravel with the seeded APITEST data (we already have `testdata.js`).
* **Performance gate**: profile on a low-end Android profile build; targets in section 3.
* **Definition of done for a screen**: matches the design brief; has loading/empty/error/offline/forbidden states; large-text and dark/light checked; haptics + motion reviewed; tests green; a rendered screenshot attached to the phase report.

### 2.6 Environments and releases

* Flavors via `--dart-define`: `dev` (local PC), `staging` (live server test), `prod`. Base URL, log level, Sentry DSN per flavor.
* Versioning `x.y.z+build`; API `min_app_version` / `latest_app_version` already exist.
* Android: debug build for you to test now; release `.apk` for sideloading, `.aab` for Play later. iOS needs a Mac + Apple developer account (decision D4).

---

## 3. Performance budget

| Metric | Target (mid-range Android, release build) |
|---|---|
| Cold start to interactive Home | <= 2.0 s (splash is a *brand moment*, skippable, never blocks real loading: bootstrap runs behind it) |
| Warm start | <= 0.8 s |
| Scroll jank (lists, calendar) | < 1% frames over 16 ms |
| Tap -> visible feedback | < 100 ms (press state + haptic), optimistic UI where safe |
| API calls on screen open | <= 3, none duplicated |
| APK size | < 35 MB (split-per-abi, tree-shaken icons, compressed images) |
| Memory | no unbounded lists (page windows), image cache capped |

**Tactics:** `const` widgets; `ListView.builder`/slivers only; `RepaintBoundary` around animations; `select()` to limit rebuilds; avoid `Opacity`/`BackdropFilter` in scrolling content; images resized to display size; precache the crest and fonts during splash; JSON parsing in `compute` only for big payloads (reports); release builds only for judging speed (debug is always slower).

---

## 4. Security

Token only in secure storage; sign out clears caches; "Sign out everywhere" (`/auth/logout-all`); idle auto-lock + optional biometric unlock (P12); no sensitive data in logs (the logger redacts tokens/passwords/phones); screenshots of Home allowed, password fields excluded from the recents thumbnail; HTTPS only for staging/prod (cleartext allowed only in the debug manifest for the local PC); no secrets in the repo (SMTP password in the web `.env` is the owner's live credential and never touches the app).

---

## 5. Getting the app onto your phone (needed from Phase 1)

The API runs on your PC (`http://localhost/rosen_barber/public/api/v1`). A phone cannot reach `localhost`, so one of:

| Option | Steps | Best for |
|---|---|---|
| **A. Same Wi-Fi** | find the PC's LAN IP (`ipconfig`, e.g. 192.168.1.20); make Laragon/Apache listen on all interfaces; allow port 80 in Windows Firewall; run the app with `--dart-define=API_BASE_URL=http://192.168.1.20/rosen_barber/public/api/v1` | iPhone or Android, no cable |
| **B. USB + adb reverse** (Android) | `adb reverse tcp:80 tcp:80`, then the base URL stays `http://localhost/...` | most reliable, no firewall |
| **C. Tunnel** | Cloudflare Tunnel / ngrok to the PC | testing away from home |

Install: Android phone with USB debugging -> `flutter run --release` (fast, realistic), or send the release `.apk`. iPhone testing needs a Mac (otherwise review the Flutter-web build in Safari: `flutter run -d web-server --web-hostname 0.0.0.0`). A short "Run on my phone" note is produced in Phase 0.

---

## 6. Phases

Sizes: S = a short session, M = a long session, L = two sessions. Phases 0-5 deliver the daily-driver app; 6-11 complete full web parity; 12 hardens and ships.

### Phase 0 — Foundations and design system   `M`
**Goal:** the invisible base that makes every later screen fast to build and consistent.
* Tokens (dark + light), typography with bundled fonts, theme, motion, haptics helper.
* Components (section 2.2 list), each with all states, plus a **debug-only Component Gallery** screen (`/dev/gallery`): *this is what you review first*: buttons, inputs with errors, pills, KPI tiles, skeletons, empty/error states, sheets, date strip, charts, light/dark toggle.
* Core: env flavors, Dio client + interceptors, envelope/Failure mapping, secure store, read cache, `Money`, `ShopTime`, router skeleton with guards, logger, lints, CI script (`tool/check.sh`: analyze + test).
* Migrate the existing splash/welcome into `features/welcome`; crest widget into `design_system`.
* "Run on my phone" guide (section 5) verified on your device.
**Mobbin research:** component-level references (list rows, chips, bottom sheets, tabs), see section 8.
**You review:** open the Gallery on your phone: colours, text sizes, button feel, dark vs light, skeleton look, haptics. Approve the visual language before screens multiply.
**Done when:** analyze clean, gallery renders on phone, a test proves `Money`/`ShopTime`/envelope mapping, API health call works from the phone.

### Phase 1 — Sign in, session, app shell   `M`
**Screens:** Sign in; Forgot password (4 steps: email -> 6-digit OTP with resend timer -> new password -> success); Session expired; Update required; the **role-aware shell** (bottom bar built from `/bootstrap` modules) with placeholder tabs.
**API:** AUTH-1..8, `/auth/me`, `/auth/logout`, `/auth/logout-all`, `/bootstrap`, `/health`.
**UX details:** email keyboard, show/hide password, inline server errors ("These credentials do not match"), 10/min login limiter message, keep email after failure, autofill hints, biometric-ready, OTP boxes with auto-advance + paste support, resend countdown (3 per 10 min limit shown honestly), "Remember me" is implicit (30-day token), device name sent for the sessions list.
**Mobbin:** login/password reset screens (section 8.1).
**You review:** sign in as Admin and as Staff (test accounts), wrong password, forgot-password flow (real email goes only if mail is configured, otherwise we use the fake mailer in the dev build), kill the app and reopen (stays signed in), sign out.
**Done when:** both roles land on the right shell with the right tabs; 401 handling sends you back to Sign in; tests for all failure branches.

### Phase 2 — Home dashboard   `M`
**Screens:** Home (Admin version, Staff version), "Next up" strip, quick actions (New sale, Book walk-in, Call next client).
**API:** DASH-1..3 (+ DASH-4..6 for admins who have those permissions).
**Content:** greeting + date (shop time); KPI row (bookings today, revenue/earnings, tips; admin numbers vs "my earnings" for staff exactly as the web); hour-by-hour bars (from today's list); **Today** list (cards with time, customer, services, barber, status pill, 1-tap Confirm/Call); **Upcoming**; admin widgets: Top services, Staff performance, Top products (collapsible).
**UX:** pull-to-refresh; skeletons; numbers count up once; empty state "No bookings today: quiet day" with a Book walk-in button; widgets appear only if the permission exists (web parity).
**Mobbin:** home/dashboard references (8.2).
**You review:** numbers equal the web dashboard for the same user; speed of first paint; how Today reads at a glance in the shop.
**Done when:** parity with web numbers (API already parity-tested) + visual sign-off.

### Phase 3 — Appointments   `L`
**Screens:** Appointments list (status tabs with counts, search, filter sheet), Appointment detail, action sheets (Confirm, Cancel with reason-free confirm, Complete off by flag), customer quick actions.
**API:** APPT-1..5 (+ APPT-11 stays hidden behind its flag).
**UX:** tabs = All / Pending / Confirmed / Rescheduled / Completed / Cancelled with live counts (`/appointments/counts`); filter sheet = date range chips (Today/Tomorrow/This week/Custom), barber, time of day; each row shows time, customer, services, barber(s) with avatars, **status pill**; **actions come from the server** (`actions` per row) so the buttons are exactly the web's; swipe-right = Confirm, swipe-left = Cancel (with Undo); detail screen: header with status, customer card (call/WhatsApp/SMS), services with durations, barber, notes, booking code, timeline; sticky action bar.
**Mobbin:** list + filters + detail + destructive confirm (8.3).
**You review:** confirm/cancel from list and detail, filters, search by name/phone, behaviour when two phones act on the same booking (409 message).
**Done when:** every status transition matches the web rules; optimistic + undo verified; list stays smooth with 500+ rows.

### Phase 4 — Calendar, booking, reschedule, breaks, working hours   `L` (the hardest screen set)
**Screens:** Calendar (day), barber picker, week strip, Appointment/Break bottom sheet, **New booking** form, **Edit booking**, **Reschedule** (slot picker), Add break sheet, **My working hours** (staff).
**API:** CAL-1..3, APPT-6..10 (slots, create, edit, reschedule, staff-by-service), ME-7..11.
**UX:**
* Day view = vertical time axis with **barber lanes** (2 visible, swipe for more; staff users see only their lane, exactly like the web). Date strip on top with a dot on busy days; "Today" chip; **now line**; breaks hatched; outside opening hours greyed; shop closure shows a banner and blocks booking.
* Tap an empty slot -> **quick-book sheet** (time and barber prefilled). Tap an event -> detail sheet with actions. First-available lane shown like the web.
* **Booking form** (single scrolling page, sticky summary bar "2 services · 55 min · $64.98 · Book"): 1) Customer (phone first; typeahead finds existing customer; new one created by phone like the web), 2) Services with quantity steppers (duration shown), 3) Barber (only those who offer the services; "First available"), 4) Date + **slot picker** (grid of times from the slot engine; taken/closed handled; "next available date" shortcut when fully booked), 5) Notes. Conflicts (409) explain who is booked at that time.
* Reschedule: only from Pending/Cancelled (web rule); same slot picker.
* Working hours (staff): day rows with a switch, one or more time ranges, add/remove block, wheel time pickers, validation of overlaps in the same words as the web.
**Mobbin:** slot pickers, day strips, calendar/event sheets, hours editors (8.4).
**You review:** book a walk-in end to end; reschedule; add a break; see a closure; double-booking attempt; staff vs admin view; working-hours editing.
**Done when:** every write equals the web's rows (API tests prove it); calendar scroll stays at 60 fps with 3 lanes x 40 events.
**API gap to confirm here:** a light `GET /staff/options` (barbers for pickers without `Staff-*` permission). If needed it is an additive endpoint, tested like the others.

### Phase 5 — POS and invoices   `L`
**Screens:** New sale (catalog + cart), Customer step, Payment step, Success, Invoices list, Invoice detail, Edit invoice, Email invoice.
**API:** POS-1..8 (+ `Idempotency-Key`), APPT-11 hidden.
**UX:** two-pane feel on one screen: top **category chips + search**, grid/list of services and products with price, tap to add (long-press = quantity); **cart sheet** peeks at the bottom with live total (`/invoices/preview`, debounced, so the screen can never disagree with the server); each line has a **barber chip** (defaults to me for staff, last used for admin); discount % (service/product), **tip chips** (none / 10% / 15% / 20% / custom, shown in dollars), payment-method segmented control; customer = phone lookup (found / new / guest) with last-visit hint; Pay -> success animation (check + haptic) with *Email invoice*, *New sale*, *View invoice*; a serrated-edge receipt look for the summary. Offline or flaky network: the cart is kept and the same idempotency key is reused, so a retry can never double-charge.
Invoices: list with search/date filter, detail with line breakdown, edit (permission `Pos_invoice-Edit`), email, staff see only their own (web rule).
**Mobbin:** checkout + tip + payment summary, receipts (8.5).
**You review:** ring up 5 different sales (service only, product only, mixed, discounts, tips, guest); compare totals with the web invoice for the same cart; edit an invoice; email.
**Done when:** totals equal the web in all golden carts; no double invoice under retry; sale in under 30 s for a single service.

### Phase 6 — Customers   `M`
**Screens:** Customers list, Customer profile, Add/Edit customer, appointment history.
**API:** CUST-1..6.
**UX:** search (name/phone/email) debounced, status filter, add button; profile header (avatar initials, member since, visits, total spend with the web's definition), quick actions (call, WhatsApp, SMS, new booking, new sale), appointment history with status pills; edit sheet; delete explains "has appointments" (409) instead of a bare error.
**Mobbin:** customer profile + history (8.6).
**You review:** find a customer in 3 letters, call from the app, create a booking from the profile.

### Phase 7 — Me: earnings, profile, settings   `M`
**Screens:** My earnings (summary cards, per day, per service, bookings), Profile (name, phone, email, photo), Appearance, About, Sessions.
**API:** ME-1..6, AUTH logout variants.
**UX:** period chips (Today / 7 days / 30 days / Month / Custom) with big total, commission vs tips split ring, day list with bars (fl_chart), the service-fee note from the API, profile photo from camera/gallery with crop + compress to <= 2 MB.
**Mobbin:** stats/trend screens (8.7), profile/settings lists (8.8).
**You review:** your own earnings vs the web staff report; change photo; switch theme.

### Phase 8 — Admin catalog   `L`
**Screens:** Services (grouped by category, images, active switch), Service form, Categories, Products (+ stock), Product form, GST (default badge, switch default), Payment methods.
**API:** CAT-1..5.
**UX:** list rows with image, price, duration, tip-eligible badge; **inline active switch** (optimistic); forms with image picker (camera/gallery, compress), money keypad, validation from server; deleting asks with the exact consequence ("Past invoices keep the name"); GST screen warns when no default exists (Q16/Q44).
**Mobbin:** catalog/product management lists + forms (8.9).
**You review:** add a service with a photo, toggle active, edit price, add a product, change GST default, add a payment method; verify on the web.

### Phase 9 — Admin shop settings, hours, closures   `M`
**Screens:** Settings (general: reminder days, default duration, service fee, invoice email switch; contact/website details), **Shop opening hours** (7 days, ranges, breaks), **Closures** (list + add/edit: date, full day or time window).
**API:** SHOP-1..3.
**UX:** the hours editor is shared with staff working hours (same component); wheel time pickers; "copy Monday to all weekdays" shortcut; closure form shows the "00:55 becomes 12:55" fix as a friendly hint; the invoice-email switch explains what it does before saving (it sends real mail).
**Mobbin:** weekly schedule editors, time wheels, date-range choosers (8.4).
**You review:** change Sunday hours and see slots vanish in the calendar; add a closure and see the banner.

### Phase 10 — People: staff and roles   `L`
**Screens:** Staff list, Staff profile (earnings cards, services, appointments), Staff form (photo, role, barber switch, services multi-select, commission, status), Reset password sheet, Assigned services, Roles list, Role editor (permission groups with switches), lock icons on system roles.
**API:** STAFF-1..12, ROLE-1/2.
**UX:** the profile labels **shop-wide** numbers clearly (web quirk Q41) so no one mistakes them for the person's own; creating a barber explains it creates a week of slots; deactivate/delete confirm shows the effect (signs the person out); role editor groups permissions by area with "select all in group" and a diff summary before save.
**Mobbin:** team/people management + permission toggles (8.10).
**You review:** create a test barber, sign in as them, see their limited app; edit a role and watch the menu change.

### Phase 11 — Insights and website content   `L`
**Screens:** Reports hub, six reports (Appointments, Payments, Staff earnings, Customer invoices, Product sales, Top products), Testimonials (list/form with star input), Gallery (grid, add, replace, delete).
**API:** RPT-1..6, CONT-1/2.
**UX:** every report = range chips + summary cards + chart + list; payments as donut, staff earnings as bars; empty states; share/export as PDF/CSV is a later optional extra; gallery = masonry grid with pinch-to-preview, multi-add from gallery, long-press delete.
**Mobbin:** analytics, charts, tables on mobile (8.7).
**You review:** each report equals the web for the same dates.

### Phase 12 — Hardening, polish, release   `L`
* **Offline read cache** for bootstrap, catalog, today's list, calendar day (banner "You're offline: showing saved data", writes disabled with a clear message).
* Performance pass on a low-end device (profile mode), jank hunt, image sizing, startup trimming.
* Accessibility pass (TalkBack/VoiceOver, large text, contrast), reduce-motion handling.
* Error-state audit (kill the server mid-request, expired token, 429, 500) and empty-state audit.
* Biometric unlock + idle lock (optional), crash reporting, app icon/splash native assets (done), store listing assets, in-app "What's new", short in-app help.
* Security review, dependency audit, bundle size check, release `.apk/.aab`, final UAT with both roles.
* Sync with the web developer's fixes (re-run parity tests, adjust the API/app together).
**You review:** a full-day dry run in the shop with the release build.

---

## 7. Web -> app parity map (nothing is left behind)

| Web module (admin panel) | App place | Phase | API ids |
|---|---|---|---|
| Login, forgot/reset password | Sign in, Forgot password | 1 | AUTH-1..8 |
| Dashboard (cards, today, upcoming, top lists) | Home | 2 | DASH-1..6 |
| Appointments list/detail/status | Appointments | 3 | APPT-1..5 |
| Calendar, add/edit booking, reschedule, breaks | Calendar + sheets | 4 | CAL-1..3, APPT-6..10 |
| Working hours (staff) | Me -> Working hours | 4 | ME-7..11 |
| POS / Invoices (create, edit, email) | + New sale, Invoices | 5 | POS-1..8 |
| Customers + profile | More -> Customers | 6 | CUST-1..6 |
| My profile, staff report | Me | 7 | ME-1..6 |
| Services, categories, products, GST, payment methods | More -> Catalog | 8 | CAT-1..5 |
| Settings, shop hours, closures | More -> Shop | 9 | SHOP-1..3 |
| Staff, staff services, staff profile | More -> People | 10 | STAFF-1..12 |
| Roles and permissions | More -> Roles | 10 | ROLE-1/2 |
| Reports | More -> Reports | 11 | RPT-1..6 |
| Testimonials, gallery | More -> Website | 11 | CONT-1/2 |

**Intentionally not in the app:** customer booking/guest flows (never), permission add/edit/delete (D6), self password change (not in the web, AUTH-9), delete a break (not in the web, CAL-4), "complete appointment into invoice" (APPT-11, off until the web is fixed).

---

## 8. Mobbin reference map (iOS, researched 2026-10-23)

Each phase starts with a fresh, deeper Mobbin pass for its exact screens; these are the references already selected and what to take from them.

**8.1 Sign in / password** — [WHOOP password step](https://mobbin.com/screens/f0e9ba3a-6772-4a2c-ae3c-89a96314bdd9) (dark, one field per step, circular Next), [MacroFactor](https://mobbin.com/screens/bc6ddff8-5f0c-4470-96dd-2b79646ad4ce) (icons in fields, visibility eye, Forgot password aligned right), [Garmin Connect](https://mobbin.com/screens/e8ecf0e0-57b1-484b-ad8b-0720e6fabac0) (dark form on photo), [Tripadvisor](https://mobbin.com/screens/39a5fcdd-854c-4963-adcb-df951ab795a5) (inline loading in the button), [ShopBack](https://mobbin.com/screens/6e39fa14-aadb-4221-b5fe-eff234f360a0) (helper text under password). *Take:* one clear primary button, eye toggle, loading inside the button, Forgot password under the field.

**8.2 Home / dashboard** — [Copilot](https://mobbin.com/screens/39e851c1-7c5d-4f1e-bf81-1c3be05e5566) (hero number + chart + "to review" list), [Shopify Home](https://mobbin.com/screens/635cf029-446c-4cdb-a3aa-bb1278e8291e) (compact KPI strip with range chip, "that's it for now" empty state), [Bevel](https://mobbin.com/screens/1ae91520-000e-4722-ba34-69f1a3cbf5d4) (ring cards, floating pill nav with centre action), [BitePal](https://mobbin.com/screens/a293713d-ead0-4d61-8ef9-fb19cabe2c54) (day strip), Revolut Business [flow](https://mobbin.com/flows/7469d0cd-b4df-40cd-a2db-9cd0bdc2a3a5) and Turo [Business flow](https://mobbin.com/flows/20d5ead0-ea0c-4f20-b6f1-b3b70fd744e4) (owner tabs: earnings / performance). *Take:* one hero number, a KPI strip, lists with status pills, calm empty states, floating nav.

**8.3 Appointments list, filters, detail, destructive confirm** — [Bevel filter chips + search](https://mobbin.com/screens/14ec5d61-dea6-4228-b1c5-3d514759ee93), [Insight Timer chips](https://mobbin.com/screens/a515e117-c16e-4f6d-a34a-df952b01c603), [Shopify search with status pills](https://mobbin.com/screens/83a79099-6b71-454f-817e-a701eb23811e), [Apple Music date sheet](https://mobbin.com/screens/5e0192a0-f150-4fb8-9dd6-9c5c3a34ed8c) (quick range chips above the month), [Public filter sheet](https://mobbin.com/screens/c5eed293-3b17-4880-8bed-16c72b416679) (Clear all / Apply), [Fresha booking detail](https://mobbin.com/screens/fba90558-d255-4d0e-aa0f-7d9e7a5b22ea) (status pill, date, action list), [Fresha overview](https://mobbin.com/screens/59efcea9-3e9f-4c36-901a-9bf4351a8293) (services + total card), [Swiggy confirmation card](https://mobbin.com/screens/ced90a3d-a220-4f7a-b25d-6d1c589e1a44), [Mindtrip destructive sheet](https://mobbin.com/screens/71569684-1ac1-416f-aa8f-139bae9013bd) (red confirm + safe "No, keep it").

**8.4 Calendar, slot picker, hours editors** — [Fresha slot picker](https://mobbin.com/screens/ef4d88db-668c-4671-a51a-b581b98d0464) and [with waitlist link](https://mobbin.com/screens/e7f0bf07-0aa9-402e-9b35-182a0345ac82) (date strip + time list), [Fresha fully booked empty state](https://mobbin.com/screens/f82d8a36-8251-4140-bcef-e1a35cd4119e) ("go to next available date"), [Fresha continue bar with price/duration](https://mobbin.com/screens/e179026c-8d72-4f07-9530-1d42e471cfe4) (sticky summary bar), [Insight Timer week strip](https://mobbin.com/screens/99b72dab-62f1-4521-9e08-731322952128), [Joi](https://mobbin.com/screens/42d0a9d1-00cf-404f-b199-9e7889813a4b) and [Structured](https://mobbin.com/screens/a5f31dc9-8707-447a-9ae4-7ec2e9a4a802) (month sheet with busy dots), [Future Pro two-column times](https://mobbin.com/screens/fcbe692b-cc6f-45f7-9612-4cf544a3cd56), [Fresha opening times](https://mobbin.com/screens/e3a593d6-df18-42fe-a403-da9fb695e7d2); editors: [WHOOP schedule](https://mobbin.com/screens/efdec0c0-ea7e-493d-8718-edd04d52df09), [Insight Timer weekday chips](https://mobbin.com/screens/afb57a33-34ce-45a1-a924-07f1d75207e3), [Mindtrip time wheels](https://mobbin.com/screens/bf75ee9c-1d71-44a5-8079-5cef10ddbf63), [Fresha time wheel sheet](https://mobbin.com/screens/5f1d47e4-3f85-43d3-91d1-4dbb0f2b823b), [Jomo rule card](https://mobbin.com/screens/7b449ed2-2e8d-4d75-8f0a-b8ef1540c08e), [Lloyds range radios](https://mobbin.com/screens/676e38c8-e741-44a4-add9-5eeb8c18392e). *Note:* Mobbin has few true multi-staff business calendars; the lane calendar is designed from first principles (time axis + lanes + sheets) and validated on your phone in Phase 4.

**8.5 POS / checkout / receipt** — [Swiggy tip chips](https://mobbin.com/screens/bff03947-5bf9-4b6d-a7c7-b108c94c8c09), [talabat tip + pay with](https://mobbin.com/screens/ab9a3d30-2e11-4140-a644-cb94b3b6b229), [Fresha payment summary](https://mobbin.com/screens/00e2ac90-58dc-43e5-b446-3a3c5821ac03), [Glovo serrated receipt summary](https://mobbin.com/screens/53bacd52-0e65-4a93-b4ad-959f124b7f3b), [Subway tip percentages with dollar amounts](https://mobbin.com/screens/8bcfb90c-3f4e-48f5-a84a-6e4b9dd22049), [Grab tip chips](https://mobbin.com/screens/c7078094-4142-410f-af6b-3f67f46a0d51). *Take:* tip chips showing % and $, running summary above a full-width pay button, receipt-style totals.

**8.6 Customer profile** — [Shopify customer](https://mobbin.com/screens/41b067de-2c35-47f3-ad20-adae9e642d45) (history + timeline), [Cash App history header](https://mobbin.com/screens/4815bd58-215c-436d-adf4-24f118b70079), [Brink profile list](https://mobbin.com/screens/6cb9deed-0d23-4f56-8021-ddc7f9d227da).

**8.7 Reports / earnings** — [WHOOP trend](https://mobbin.com/screens/e2217a0e-7bb4-4aac-9edb-20a890bd9788) (range segmented control + avg + bars), [Insight Timer stats](https://mobbin.com/screens/c22e09fb-2eac-4792-8c0d-d348b440ef47), [Google Health](https://mobbin.com/screens/87da4565-88e3-4345-9001-744c9dafab89) (W/M/3M/Y chips + daily list), [Shopify analytics table](https://mobbin.com/screens/5750de77-2b45-42d0-b568-aec8e33cd8c1), [Public donut breakdown](https://mobbin.com/screens/80326ed3-4cec-4479-91f9-07294ce77e1a), [LinkedIn analytics](https://mobbin.com/screens/7b9e2b5a-dd08-43dd-b90e-65c486638dc4).

**8.8 Profile / More / settings lists** — [Agoda account](https://mobbin.com/screens/aa223f16-4167-41e9-8720-86ded0c66815), [Yami account](https://mobbin.com/screens/69493b42-308d-4b21-8b87-8e41a95196fd), [Brink](https://mobbin.com/screens/6cb9deed-0d23-4f56-8021-ddc7f9d227da): grouped cards, icon + label + chevron, header with name and role.

**8.9 / 8.10 Catalog, people, permissions** — researched at the start of Phases 8 and 10 (product/inventory lists with active switches, team lists with role chips, permission toggle groups); Shopify admin patterns above already cover lists + search + status pills.

**Splash/welcome references used earlier:** Any Distance (luminous halo mark), Moonly and Ultrahuman (metallic shimmer), Tiimo and WHOOP (live UI preview onboarding), Revolut Business (dark glass cards).

---

## 9. Test strategy and test data

* **Accounts for review** (local only): the existing `apitest.admin@rosen.test` (Admin) and `apitest.staff@rosen.test` (Staff, barber) plus seeded APITEST appointments/customers/invoices (`testdata.js create`), removed again afterwards. Add a Manager and an Accountant test account in Phase 10.
* **Contract tests**: a Dart test hits the local API for `/bootstrap`, lists and one write per module and checks the DTOs still parse (catches API/app drift instantly).
* **Parity checks with the web** are already done on the API side; the app adds *screen-level* checks (numbers shown = numbers returned) and golden screenshots.
* **Manual UAT script** per phase = the "You review" lists above, kept in `docs/UAT.md` and ticked off.
* **Device matrix**: your phone (primary), one low-end Android profile (performance), tablet/landscape = best-effort (portrait locked for now).

---

## 10. Risks and decisions for the owner

| # | Question | Recommendation |
|---|---|---|
| D1 | Light theme: ship both? | Yes: tokens support both from day 1; default Dark (brand), follow system optional |
| D2 | Languages | English only now; strings are ARB-ready (Gujarati/French later is cheap) |
| D3 | Offline | Read-only cache (Phase 12). Writes always need internet (no risky offline queue for money) |
| D4 | iPhone | Needs a Mac + Apple developer account. Until then Android release + Safari web preview |
| D5 | Crash reporting | Sentry (free tier) or Firebase Crashlytics; recommended before staff use it daily |
| D6 | Push notifications (new website booking) | Later phase: needs a small backend table + Firebase key (API_PLAN D8) |
| D7 | Biometric/idle lock | Optional switch in Phase 12 |
| D8 | Distribution | Sideload `.apk` for the team first; Play Store (private/internal track) when stable |
| D9 | Export (PDF/CSV share of reports) | Nice-to-have after Phase 11 |
| D10 | Web quirks fix timing | Hand `API_PLAN.md` section 8 to the web developer any time; app + API follow their fixes in one small update |

**Main risks:** (1) the calendar is the densest screen: mitigated by building it on its own phase with real-device review; (2) phone cannot reach the PC API: mitigated by the connectivity guide in Phase 0; (3) rate limit 240/min: mitigated by the call budget and caching; (4) web quirks surprising users: every mirrored quirk gets a visible, honest label in the app (e.g. "shop totals").

---

## 11. Suggested order and what you get when

| After phase | You can do on your phone |
|---|---|
| 0 | Judge the whole visual language (Gallery), light/dark, fonts, buttons |
| 1 | Sign in as Admin/Staff, forgot password, see the right menu |
| 2 | See the shop's day on Home (the first "wow") |
| 3 | Run the day's bookings: confirm/cancel/call |
| 4 | Take walk-in and phone bookings, move them, manage breaks and hours |
| 5 | Ring up and email invoices (the shop can work from the phone) |
| 6-7 | Customers, my earnings, profile |
| 8-9 | Manage prices, products, hours, closures from anywhere |
| 10-11 | Manage the team, roles, reports, website content: full web parity |
| 12 | Release build the whole team can install |

**Recommended start:** Phase 0 now (small, invisible, but it is the base for speed and consistency), then Phases 1 and 2 back-to-back so you have something real to hold in your hand quickly.
