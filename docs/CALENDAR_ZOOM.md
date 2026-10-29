# Calendar: pinch to zoom (built)

Question: can the staff calendar be zoomed in and out with two fingers? Yes, and it is built (portrait calendar).
This file is the research, the plan, the review and the build notes.

## 1. Research

Mobbin (day / schedule views: Amie, Saturn Calendar, Structured, ClickUp, Tiimo):
- Amie shows the **same day at three densities** (tight 11 AM to 8 PM, roomy 12 PM to 10 PM): zooming the time scale is
  how a calendar fits "whole day at a glance" and "details" in one screen.
- Structured compresses the hours (3 PM to 10 PM small labels) when you zoom out to a week.
- Tiimo teaches the gesture with a **one-time tip card** ("Pinch with two fingers to switch between timeline and list").
  Lesson: a hidden gesture needs one gentle hint.
- ClickUp shows a fixed hour scale and users ask for a zoomable one on its feedback board.

Internet:
- Square Appointments (salon / barber software) users ask for [pinch-to-zoom to come back](https://community.squareup.com/t5/Appointments-Bookings/Can-we-get-pinch-to-zoom-back-on-the-mobile-calendar/m-p/818903):
  "zoom in for detail or zoom out to see more of the day without scrolling". Same job as ours.
- [ClickUp request](https://feedback.clickup.com/feature-requests/p/zoom-hour-time-scale-for-calendar-week-view) and a
  [Kolab ticket](https://git.kolab.org/T4497): a fixed hour scale is a known complaint; [BlackBerry Calendar](https://docs.blackberry.com/en/apps-for-android/calendar/latest/help/cfl1427810472099)
  does it with pinch (out = fewer hours, in = more hours shown).
- Desktop forum thread ([Hacker News](https://news.ycombinator.com/item?id=11846108)): users need a way to **discover** zoom
  and a non-pinch way for mouse users. For us: a button (accessibility needs a one-finger alternative to a two-finger gesture).

## 2. What the code allows (checked)

- `DayGrid` ([day_grid.dart](../lib/features/calendar/presentation/widgets/day_grid.dart)) draws everything from one
  constant, `DayGrid.hourHeight = 88`, used in about 14 places (event top/height, now-line, hour lines, tap to minute).
  Making it a value that can change is mechanical.
- Vertical scroll and horizontal scroll (lanes) already exist; events have tap, lanes have long-press.
- The landscape page has its own grid (separate hour height), so it is a second step.
- Needed because the zoom changes the height: keep the minute under the fingers fixed (anchor), and keep the tap to
  minute rounding (15 min) correct at every zoom.

## 3. Concepts

| # | Idea | Verdict |
|---|---|---|
| A | **Pinch changes px per hour** (continuous, 56 to 176, default 88). Anchored on the fingers. Remembered. | **Chosen** |
| B | Fixed three levels (Compact / Normal / Roomy) by pinch or button | Used as the **button** alternative |
| C | Scale a snapshot while pinching, relayout at the end | Fallback only (text would stretch); try A first and measure |
| D | Pinch changes the number of barber columns | Rejected: the columns already scroll sideways; mixing two zooms confuses |
| E | Zoom both ways (time and width) like a map | Rejected: time is the only axis that needs it |

## 4. Specification (A + B)

- **Gesture:** two fingers on the grid. Read with a pointer `Listener` (count of pointers and their distance), **not**
  the gesture arena, so it never fights the vertical scroll, the horizontal scroll, taps or long-press. While two fingers
  are down the scrolls are locked; one finger behaves exactly as today.
- **Scale:** `hour = clamp(start * distance_now / distance_start, 56, 176)`; slight rubber band past the ends (resistance,
  not a hard stop). A light haptic tick when it passes the default (88) and at each end.
- **Anchor:** the minute that was between the fingers when the pinch began stays between them: `offset = minute * hour - fingerY`.
- **Content follows the zoom** (no new data): below 64 px/hour half-hour lines are hidden and event cards show the name
  only; above 120 px/hour the quarter-hour lines and the service text show. Card text already adapts to its height.
- **Feedback:** a small pill with the level ("0.8x", "1x", "1.6x") fades in while pinching and out after 700 ms; tap it
  to go back to 1x.
- **Button (one-finger alternative, discoverable):** next to the full-screen button in the legend row: a "zoom" button that
  steps Compact (64) to Normal (88) to Roomy (132) and back. Same animated change (220 ms).
- **Remembered:** the level is stored (SharedPreferences), restored on open; a "reset" is the 1x pill.
- **Hint:** a one-time tip ("Pinch with two fingers to zoom the day") shown once, dismissable, like Tiimo.
- **Reduce motion:** the button change is instant; the pinch itself is direct manipulation and always follows the fingers.
- **Landscape:** step 2, same hour-height value, same gesture.

## 5. Review (second pass)

| Risk | Decision |
|---|---|
| Pinch fights scrolling | Pointer `Listener` and a scroll lock only while 2 fingers are down |
| A single-pointer user cannot zoom (WCAG: multipoint gestures need an alternative) | The zoom button |
| Relayout every frame is heavy (7 lanes x ~10 cards) | Cards are plain positioned widgets: measure with `FRAME_LOG` on the phone; fallback concept C only if frames > 16 ms |
| Tap to minute wrong when zoomed | Use the live value in `_onLaneTap`; test at 56, 88, 176 |
| Text too small at 56 | Name only, one line; `SMALL=1` test at 1.6x text scale |
| Event shorter than a card (15 min at 56 px/h is 14 px) | Minimum card height already clamps; hide the second line |
| Scroll position jumps when the range of hours changes | Zoom never changes the range, only the height |
| Discoverability | Button plus a one-time hint |
| Saved zoom surprises | The pill shows the level and resets with a tap |

## 6. Verdict and effort

Possible and useful: salon / barber apps are asked for exactly this. Risk is low with the Listener approach.
Medium job (about the size of the landscape calendar's grid work): `DayGrid` (value, anchor, content levels), the
gesture layer, the zoom button and hint, storage, tests (pinch with two test gestures, anchor, clamps, tap mapping, small
screen), a frame-time check on the phone, then landscape.

Open question for the owner: build it for portrait first and see it on the phone, then landscape? (recommended)

## 7. Build notes

Code: `day_grid.dart` (live `_hour`, pointer Listener, anchor, glide, pill, tip, compact card), `calendar_controller.dart`
(`calendarZoomProvider`, `calendarZoomHintProvider`, limits 64 to 176, default 88, button steps 64 / 88 / 132),
`storage.dart` (remembered), `calendar_page.dart` (zoom button next to the landscape button).
Tests: `test/features/calendar/calendar_zoom_test.dart` (9: spread, pinch in and limits, anchor, no booking after a pinch,
tap to minute at another zoom, button glide, pill reset, one-finger scroll and tip, extremes).

What building it changed in the plan:
- Minimum is 64 px/hour (not 56): a 30-minute booking stays readable. A booking under 38 px high becomes one line
  ("10:15 AM  Name"): this also fixed a 4 px overflow of 15-minute bookings.
- A lazy `AnimationController` created during dispose (same bug as in the pole refresh) was caught by a test.
- `size` cannot be read while building (button change): the glide starts after the frame.
- Frame times on the phone while the hours change (button steps): first version 12 to 18% slow frames, p90 17 to 19 ms.
  Now: the pinned header is the same widget object across frames, timelines and range are computed once per day,
  and **only the barber columns on screen are built while zooming** (all of them at rest). Result: p90 11 to 13 ms,
  4 to 5% slow frames, raster fine. A real two-finger pinch cannot be sent through adb; the button uses the same code path.

## 8. Landscape (step 2, built)

Time runs sideways there, so two fingers change the **pixels per hour across** (`landscape_calendar_page.dart`):
- Same raw-pointer approach (no fight with scrolling or taps); the time between the fingers stays between them.
- Lowest = the whole day fits the width; highest = 360 px/hour. The remembered value is `landscapeZoomProvider`
  (null = a preset).
- The top bar button still switches between the two presets ("whole day" / "more detail") and forgets a pinch.
- The pill shows the zoom as times the whole day ("2.1x"); tap it for the preset.
- While zooming only the booking blocks inside the screen (plus 80 px) are built.
- Tests: 5 more in `landscape_test.dart`.
- Not measured on the phone: `sendevent` (needed to inject a two-finger touch through adb) is denied on this phone, so
  the pinch itself was checked only in tests; the frame cost was not measured in landscape.
