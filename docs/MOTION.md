# Motion: one set of rules

Where the app moves, and why. Code: `lib/design_system/motion/`, `lib/features/shell/animated_branches.dart`.

## Rules (from Material motion + what we measured)

- **200-300 ms** for anything the user waits on (screen, tab, tab content); **150 ms** for press feedback.
- **Decelerate in** (`easeOutCubic`), **accelerate out** (`easeInCubic`). Nothing bounces except the success check (small overshoot on purpose).
- Move little: a rise of 10 px or 3.5% of the screen, never a full slide.
- **Everything respects "Remove animations"** (`MediaQuery.disableAnimations`): the view just switches, no ticker runs.
- No animation may run while its screen is hidden (tabs are `TickerMode`-disabled, `PulseDot` stops with its ticker).
- Nothing heavy under motion: no `BackdropFilter` on scrolling content, no shader-based splash.

## Where it moves

| Moment | What | Where |
|---|---|---|
| A screen is opened (forms, details) | rises 3.5% and fades in 280 ms; the screen below dims a little | `AppPageTransitionsBuilder` (theme) |
| Tab changes (Dashboard / Appointments / Calendar / More) | new tab fades in and rises 10 px, 240 ms; tabs stay alive | `AnimatedBranches` |
| Home loads | skeleton cross-fades into the page | `SoftSwitcher` in `HomePage` |
| Today <-> Upcoming, Services <-> Products, "Show more" | content swaps with a fade, height follows | `SoftSwitcher` |
| A list opens | first 8 rows come in one after another (40 ms apart); rows that scroll in later do not | `EntranceHost` / `StaggerIn` |
| Something worked | toast shows a check that draws itself; big moments (booking saved, invoice done) also show a center check with ring and sparks | `AnimatedCheck`, `showSuccessBurst` |
| Live time | the "NOW" pill has a pulsing dot | `PulseDot` |
| Profile pictures | fade in over the initials | `AppAvatar` |
| Pull to refresh | the Rosenthal barber pole turns with the finger, hops and glows when armed, spins while loading, stops with a glint and "Updated 2:41 PM" (docs/PULL_TO_REFRESH.md) | `AppRefresh` |
| Pressing | small scale | `Pressable` (existing) |

## Smoothness fixes

- The sparkle ink splash (`InkSparkle`) compiles a shader on first use, a visible hitch on the first tap. Replaced by `InkRipple` (no shader).
- The pulsing NOW dot rests after 3 pulses: an endless animation made the phone draw 60 frames a second while idle (measured: idle now draws nothing).
- The splash blur is half as strong (it costs the GPU on every frame it shows).
- Pictures decode at display size (`cacheWidth`), no abrupt swap when they arrive.
- Only what changes is rebuilt when a segment switches.

## Measuring (real phone, release build)

```powershell
flutter build apk --release --target-platform android-arm64 `
  --dart-define=API_BASE_URL=http://localhost:8081/rosen_barber/public/api/v1 --dart-define=FLAVOR=dev `
  --dart-define=FRAME_LOG=true
adb -s PHONE logcat -c
# ...use the app...
adb -s PHONE logcat -d -s flutter | findstr frames
```

Every 120 frames it prints build and raster time (p50, p90, max) and how many frames were over 16 ms.
Healthy: p50 under 4 ms, p90 under 8 ms, a few spikes at first open of a screen.
Off in normal builds.

## Measured on the owner's phone (release build, FRAME_LOG)

| Moment | Before | After |
|---|---|---|
| Home scroll | build p50 1.5 ms, raster p50 3 ms | same (already smooth) |
| App start (splash) | 12 slow raster frames | 5 |
| Idle on Home | drawing every frame (with the pulse) | no frames |
| First open of a tab | one build spike of ~25 ms (3 frames) | same, now hidden by the fade-in |

## Offline and error states
See docs/ERROR_STATES.md: the pole turns while "Try again" works, the offline strip grows from the top and folds after "Back online".
