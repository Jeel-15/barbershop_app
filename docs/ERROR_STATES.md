# Offline and error states: "calm, not alarming"

Goal: when the internet is gone or something unexpected happens, the user should feel
"a small pause, my data is safe", never "the app broke".

## 1. Research

Mobbin (no-internet and error screens of Zomato, Binance, CHOPT, GoPay, Opera, MyDyson, Qantas,
Noom, Clue, Freenow, PayPal, Spotify, Fanatics, Glow; offline banners of Alta, Particle News, LARQ, Linktree):

- The best ones use **one friendly figure** (brand object), a **short human title**, one sentence of **what to do**, and **one button**.
- Spotify: "We'll be here when you're back online" and Fanatics: "Where's the internet?" turn the problem into a calm line.
- Qantas / Clue: the technical code is tiny and secondary (Clue: "Copy error information").
- Alta, Particle News: the connection state is a **strip at the top** ("Network offline. Reconnecting...") and the content stays.
- Linktree: a green "Successfully connected" strip closes the loop when the connection returns.
- Weak ones: a red triangle, "Error occured", no reassurance, a code as the headline.

Web: [NN/g error-message guidelines](https://www.nngroup.com/articles/error-message-guidelines/): plain language (no codes),
precise, constructive, polite; never rely on colour or animation alone.
Offline-first patterns ([Oracle sales mobile](https://docs.oracle.com/en/cloud/saas/sales/cocsm/how-cx-sales-mobile-continues-to-work-offline.html),
[Next.js offline guide](https://nextjs.org/docs/app/guides/offline-support)): keep showing saved data, say it in a banner,
retry by itself when the connection returns.

## 2. Decisions

| Idea | Verdict |
|---|---|
| One brand figure: the barber pole, standing still with a badge (wifi-off, hourglass...). While retrying the **pole turns** (same language as pull to refresh) | Chosen |
| Five moods with their own words (offline, can't connect, slow, our-side hiccup, other); none blames the user, all say nothing is lost | Chosen |
| Global strip at the top: amber "You're offline. Showing saved data." then green "Back online" and it folds away | Chosen |
| Retry by itself once when the phone comes back online | Chosen |
| Support code folded under "Details" | Chosen |
| A widget that throws shows a quiet card instead of the red/grey box | Chosen |
| Full-screen "offline" blocking page | Rejected: saved data must stay usable |
| Lottie / character illustration | Rejected: a new asset to maintain, the pole is already the brand |

## 3. What was built

- `lib/core/network/connectivity.dart`: `connectivityProvider` (connectivity_plus; unknown counts as online).
- `lib/design_system/components/connection_banner.dart`: the strip. It grows from the top (it also tints the status bar),
  the page loses only the inset the strip now covers, so nothing jumps; the app tree keeps its shape so no state is lost.
- `connection_scope.dart`: tells the state views whether the phone is online (the design system stays provider-free).
- `error_state.dart`: `ErrorState` (same constructor for the 35 call sites). Mood is read from the failure's sentence and the connection.
  A screen's own title ("Could not load times") is kept.
- `friendly_error_widget.dart` + `bootstrap.dart`: `ErrorWidget.builder` and `PlatformDispatcher.onError` (logged, never a red box).
- Home's own "saved data" line now shows only when the phone is online but the server did not answer.
- Reduce motion: no breathing, no spin, no pulse; the words still change.

Tests: `test/error_states_test.dart` (11), previews: `tool/preview/error_preview_test.dart`.
