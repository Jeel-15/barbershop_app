# Demo tour v2: coverage plan (final, after four passes)

## Status (2026-10-29, evening)
| Milestone | State |
|---|---|
| M1 harness + audio truth | Harness done (`tool/demo/run.sh`, one command, tested end to end). The app plays the voice to the end (log). **Your confirmation that you hear it is the only open item.** |
| M2 engine + Dashboard chapter | **Written, not yet run on the phone** (you asked me not to run the app). Engine v2: beats (voice and action start together), ring around the whole card or button (`grow`), scroll until the thing is built (`scrollTo`), real finger swipes and pull-to-refresh, optional targets, the script can be changed without a rebuild. Script: chapters **c00 (shell, 13 elements) and c01 (Dashboard, 31 elements), 38 beats, all covered** (`coverage_check`: exact). Unit tests and `check.sh` pass. |
| M3 to M6 | Not started (chapters c05, c04, c02, c03, c06 to c12). |

What is **not proven** until it runs on the phone: that every target word is found on the real Dashboard (a mismatch shows as a FAIL line in the log and a picture),
that the ring lands on the card and not on a label, and that the swipes and the pull-to-refresh move the real lists.

Owner's rule: **nothing of the app may be missed**, every screen is explained in depth (also what scrolls sideways), the design and
animations are never hidden, and the tour must be accurate, not "roughly right". So the plan was made in four passes and only the last
one is built. Everything below is checkable by tools in `tool/demo/`.

## Pass 1: what the app has (from the source, not from memory)
* `node tool/demo/inventory.mjs > docs/DEMO_INVENTORY.md` reads all 57 screen files and lists their words, buttons, tabs, menus, sheets,
  pickers and sideways scrollers (`docs/DEMO_INVENTORY.md`).
* From it and from reading Home, Calendar, Booking, Invoices, Reports, Team: **`assets/demo/coverage.json`** is the one list of what a
  person can see or do: **13 chapters, 34 screens, 345 elements** (kind: explain / press / type / sideways-scroll / sheet / gesture),
  plus a `waive` list of what is deliberately not shown and why (sign-in screens, fingerprint prompt, staff-only pages, real e-mail...).
* The elements include the "soft" features that are easy to forget: pull-to-refresh (barber pole), pinch and double-tap zoom, drag to
  reorder columns, toasts and success animations, skeleton loading, dark/light, "each person sees only what you allow", live permission update.

## Pass 2: compare with what the tour has today
`node tool/demo/coverage_check.mjs` (the old 44-part script against the 345 elements):

| | |
|---|---|
| Covered, even with generous keyword matching | **208 of 345 (60%)**, the real figure is lower (words like "call", "name", "total" match by accident) |
| Not mentioned at all | **137** (whole sideways scrollers, filter sheets, forms' fields, menus, empty states, Reports tabs, Settings tabs, Staff profile tabs, Roles form...) |
| Explained in depth | almost none: one sentence per screen, and the ring points at a word, not at the control |

Worse, the old design cannot be fixed by adding sentences. What the compare showed (and the phone run proved):

| # | Cause (evidence) | Effect |
|---|---|---|
| 1 | Targets are found only among widgets that are already built. The booking form is a lazy list; the date strip was never built, so "30" was "not found" (s17.1, 7 s timeout) | the whole booking failed |
| 2 | One failed step is followed by the rest of the scene and then the next scenes, with no check of where the app is | after the failed booking the tour stayed on the form and "explained" the appointments list over it (your screenshot); 40 steps failed in a row |
| 3 | One long audio for a whole scene, while the actions run on their own clock | the voice says "Pending" while the finger is somewhere else |
| 4 | The ring is drawn around a *text* (e.g. "TOTAL REVENUE"), not around the button or card | looks inaccurate |
| 5 | Scrolls are fixed pixel amounts ("560 px") | wrong when the content differs |
| 6 | Nothing is explained deeper than the first word of a card | what you saw on the dashboard |
| 7 | The harness builds I installed were fast mode (`TOUR_FAST`): voice off **by design**. A real-audio build did play (log: s01 and s02 played to the end, 0 errors, media volume full) | "no audio" in every harness run. Whether you can hear the real-audio build is **not confirmed yet** (M1) |
| 8 | The server (Apache/MySQL on this PC) can be down; the tour does not check | a run fails with 40 "not found" and no real reason |

## Pass 3: review of the plan itself (what could still go wrong, and the answer)
| Risk | Answer built into the final plan |
|---|---|
| A failed step cascades | **Scenes** with an entry check; a failed scene is logged, the app is reset to a known place, the next scene starts clean |
| Lazy lists hide targets | `scrollTo` searches the main list in steps, down then up, until the target is built and on screen |
| Moving targets (animations, loaders) | Wait until no skeleton is on screen, then measure the target twice 120 ms apart; press only when both agree; **measure again right before the press** |
| Ring on a word instead of the control | `grow: tap` (nearest tappable parent), `grow: card` (nearest card/row), or a number of parents |
| Voice and finger out of step | **Beats**: one sentence = one beat = one audio file; its action starts with the sentence; the beat ends when both are done. A `sweep` rings several items evenly across one sentence |
| Sideways content not explained | `swipeX` (a real finger-drag along the scroller) and `scrollX` (to an item); a beat per item. Real drags and pinches will be produced as touch events inside the app; whether the app's own pinch handler responds to them is proven at gate M4 |
| Real saves duplicate data | `restore.sh` before every run (the run script does it); preflight: the tour refuses to start if Olivia already exists |
| Server down | preflight: `/health` and `/bootstrap` must answer, else the tour shows a plain message and stops |
| Phone sleeps during a 30 min tour | `wakelock_plus` while the tour runs |
| Keyboard covers the screen (autofocus on the customer form) | hide the keyboard after every `type`; typing never opens it |
| App lock or fingerprint offer appears mid-tour | both are suppressed while the tour runs |
| Day with no free slot / closed day | `pickFreeDay`: tries the next days until slots exist |
| Demo data goes stale (seed covers 14 Sep to 11 Nov 2026) | documented; a re-seed script shifted to the new date is part of the final handover |
| Landscape page | its own scene with its own check; if it fails the rest still runs; portrait narration is the fallback |
| Audio really silent on some phone | an audio check screen at the start ("Do you hear this?") and a visible **FAST (silent)** tag in test builds so nobody mistakes it again |
| Everything too long for a client | **chapters** that run alone or in order, and a `quick` flag on the beats for a ~10 minute version |
| UI changes later and the tour silently breaks | `coverage_check --strict` + script lint tests + a phone run script that fails on any logged FAIL |

## Pass 4: the plan that will be built

### 4.1 Script format v2 (replaces the 44-part list)
```
chapter { id, name, start route, needs, scenes[] }
scene   { id, at (route or visible anchor), enter[] (how to get there), beats[] }
beat    { id, say (one or two sentences, spoken), cap (optional subtitle override),
          quick (true = in the 10 minute version), covers [element ids],
          do [ actions ], expect [ visible/gone checks ] }
```
Actions: `ring` (target, grow), `tap`, `type`, `scrollTo`, `swipeY/swipeX` (finger drag), `scrollX`, `pinch`, `doubleTap`, `pull`, `sweep`,
`nav`, `go`, `back`, `closeSheet`, `pickFreeDay`, `wait`, `snapshot`. Targets: text, starts, regex, icon, hint, with `in`, `sel`, `grow`.

### 4.2 Engine changes (in this order, each verified on the phone before the next)
1. **E1 Harness truth**: `tool/demo/run.sh` (restore, build, install, run, pull the log and the screenshots, make contact sheets) and a
   "FAST (silent)" tag. Preflight (server, Olivia absent). Wakelock. Keyboard hidden. Lock and offer suppressed.
2. **E2 Finding**: `scrollTo` (main list, both directions), stable-rect measuring, skeleton wait, `grow`.
3. **E3 Scenes and recovery**: entry checks, `closeSheet`, reset to a known screen, per-scene result in the log.
4. **E4 Beats and voice**: beat audio, subtitles from the sentence (placed away from the ring), `sweep`, durations read from the files.
5. **E5 Real gestures**: finger-drag swipes, pinch (two dots), double tap, pull-to-refresh.
6. **E6 Contact sheets**: every run produces pictures with ring and subtitle, 12 per sheet, for review by eye.

### 4.3 Chapters (order matters: Olivia is created early and reused)
| Ch | Name | Screens (all elements in coverage.json) | Beats (est.) | Quick |
|---|---|---|---|---|
| c00 | Welcome and the app shell | bottom bar, voice/subtitles, motion, toasts, loading, permissions, themes | 14 | 6 |
| c01 | Dashboard | every card, tile, lane, strip, switch, highlight, pull-to-refresh | 34 | 10 |
| c05 | Customers (first: creates Olivia) | list, search, menu, add form (every field, validation), profile | 24 | 6 |
| c04 | Book an appointment | form, service picker, barber, date strip, slots, custom time, bar, save | 28 | 9 |
| c02 | Appointments | list, chips, search, filter sheet, appointment sheet, confirm, reschedule, cancel ask | 38 | 9 |
| c03 | Calendar | header, staff sheet, break sheet, strip, legend, guide, zoom, pinch, lanes, cards, free, closed day, landscape | 46 | 10 |
| c06 | Invoices and POS | list, create (every field), pickers, totals, detail, mail/PDF/print/edit | 38 | 9 |
| c07 | Reports | filter, headline cards, six tabs in depth | 22 | 5 |
| c08 | Catalog | services, section sheet, categories, products, GST, payment methods and their forms | 44 | 8 |
| c09 | Shop settings | three tabs, opening hours, closures | 24 | 5 |
| c10 | Website content | testimonials, gallery | 14 | 3 |
| c11 | Team and roles | staff list/form/profile/tabs/sheets, roles list/form/permissions | 36 | 7 |
| c12 | Your account and the app | More menu, appearance, haptics, security, profile, sign out | 18 | 5 |
| | **Total** | 345 elements | **~380 beats, about 40 minutes** | **~10 minutes** |

Chapters can be recorded one by one (2 to 6 minutes each), so you can also send a client only the chapters he cares about.

### 4.4 How "nothing is missed" is enforced
* `coverage_check --strict` fails when any element has no beat that `covers` it, or a beat covers an unknown element.
* A unit test (same rule) runs inside `check.sh`.
* A phone run fails if any beat logs FAIL; the contact sheets are looked at by eye for ring position and subtitle.
* When a screen changes, the inventory is regenerated and the diff shows what the tour must learn.

### 4.5 Milestones, each with its own gate (I do not move on before the gate passes)
| M | What | Gate |
|---|---|---|
| M1 | E1 harness + audio truth (you listen to a 30 s real-voice run) | you confirm you hear Clara; run.sh works end to end |
| M2 | E2 + E3 on c01 Dashboard (full depth) | run on the phone: 0 FAIL, ring/finger exactly on the control in every sheet; coverage 100% for c00+c01 |
| M3 | c05 Customers + c04 Booking (the chain that failed) | 0 FAIL, the booking is really saved and Olivia appears on the calendar |
| M4 | E4 beats/sync + E5 gestures on c02 + c03 | voice names the thing the finger/ring is on; pinch really zooms |
| M5 | c06 to c12 chapter by chapter | each chapter alone: 0 FAIL and 100% coverage |
| M6 | Full run in real time with voice, quick run, handover docs | one uninterrupted run, two videos' worth, `check.sh` ALL GOOD, production build without tour flags |

Time: about 4 to 5 working days. The long part is not the engine but writing and checking ~380 sentences and running each chapter on the phone.

## What I need from you
1. Confirm **Complete = ~40 minutes in chapters, Quick = ~10 minutes** (or tell me a target length).
2. Say **yes/no to a pre-login chapter** (Welcome slides, Sign in, Forgot password): it needs the tour to sign out and sign in again with the test account.
3. During M1 only: listen to a 30 second real-voice run and tell me if you hear it (phone speaker, not Bluetooth).
