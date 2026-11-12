# Dashboard redesign: plan (v3, three review rounds, not built yet)

Client feedback (2026-11-05): the dashboard is crowded, has no New Appointment
button, its appointments look different from the Bookings tab, appointments
should sit above the calendar, and the Revenue card should move to More with a
hide / show eye. Owner's decisions: counts stay as small chips **without
revenue**; Highlights stay but in a new style (charts); eye state is our choice.

## Research used

- Mobbin, 3 rounds, about 30 screens (links under each part below).
- Web: dashboards work best with progressive disclosure, 3-5 headline items above
  the fold and detail one tap away (uxpilot, easy.bi, Toptal guides); extended
  FAB collapses to a normal FAB on scroll down and expands on scroll up, one FAB
  = the single main action, placed within thumb reach (SAP Fiori / Material 3
  guidance); Flutter: one `AnimationController` with `Interval`s for a stagger,
  read `MediaQuery.disableAnimationsOf(context)` and paint the final frame when
  it is on.
- Honest limit: Mobbin gives still images, so motion values below are our own
  choices from known patterns, to be judged on the phone.

## Decisions (final)

| Topic | Decision |
|---|---|
| Count chips | One swipeable row. Order: Pending, Confirmed, Completed, Customers, Rescheduled, Cancelled (first four fit the first screen). From `DashboardSummary` (`upcoming` is Pending). Tap opens Bookings filtered (existing `_openFiltered`). No money on a chip. |
| Next Up card | Kept but slimmer, and **shown only when the next open booking is within 2 hours** (countdown "in 25 min", customer, service, barber, Confirm). Otherwise hidden, so it never repeats the first Appointments row. |
| Appointments | Sliding Today / Upcoming switch (keeps `home.appts.switch`). Rows are the Bookings tab's `AppointmentTile` (replaces `CompactAppointmentTile`). 4 rows, then View all. |
| Staff Calendar | Below Appointments, existing card, same actions. |
| Highlights | One card, Services / Products switch. Services: ranked bars (rank, name, booking count, share %). Products: donut by units sold (the API gives units only) with the total in the centre and a legend. **No dollar amounts on Home** (same privacy rule as revenue). Upgrades the existing `HomeInsightsCard` / `_BarRow`. |
| New Appointment | Extended FAB "+ New", bottom right, 16 px above the nav bar (in the Home body, so it sits above `AppNavBar`). Collapses to "+" on scroll down, expands on scroll up. Opens `/app/appointment/new`. Shown only when the user may add bookings (same permission the calendar uses; confirm when building). The only New Appointment entry on Home. |
| Money card | Moves to More, right under the profile card. Admin: "Total revenue"; staff: "My earnings" (commission + tips), because `summary.revenue` is that for staff. Server `widgets` / scope rules unchanged. |
| Eye | Hidden (`••••`) at **every app launch**. Eye reveals with a count-up; hides again after 60 s or when the app goes to the background. Light haptic. Not saved to disk. |

## Layout, top to bottom (`lib/features/home`)

1. Header (greeting, date, avatar), compact.
2. Count chips.
3. Next Up (only when within 2 h).
4. Appointments (Today / Upcoming, 4 rows).
5. Staff Calendar.
6. Highlights (bars / donut).
7. FAB over everything, bottom right.

First screen: header, chips, Next Up (when it applies), the start of Appointments.

## Motion spec

- Stagger with one controller per page: blocks 60 ms apart, 320 ms easeOutCubic, rise 12 px.
- Count-up numbers 600 ms; bars grow 700 ms; donut sweep 800 ms.
- Sliding switch thumb 220 ms; FAB extend / collapse 180 ms; chip tap press-scale 0.97.
- Pull to refresh stays. Reduce-motion on: no stagger, no count-up, charts paint the final frame.
- Charts are `CustomPainter` inside `RepaintBoundary`, `shouldRepaint` only when values change. Colours only from design tokens (dark and light). No new package.

## Mobbin references

- Home, next job, FAB: Jobber (https://mobbin.com/screens/bc7ab501-113a-46c8-8489-92e99140ea45), Google Calendar, ClickUp.
- Sliding switch: Todoist (https://mobbin.com/screens/e205122f-c5db-458f-b65e-3f8083165bb4), Jomo (https://mobbin.com/screens/d3600dba-fe6d-4dbb-95fc-80c3065ade9c).
- Hidden amount and eye: KOHO (https://mobbin.com/screens/0f4eb399-e870-4b82-a06c-936c04015421), Fidelity (https://mobbin.com/screens/ddd554f3-3f85-45b4-a2be-9fe049b674fd).
- Ranked bars and donut: Alta (https://mobbin.com/screens/cdc35a1a-97d8-42e7-9955-f387b7035c25), Shopify, Forest (https://mobbin.com/screens/9fc6bb6c-76fd-4301-ac03-3073f177c118).
- Appointment rows and countdown: Fresha (https://mobbin.com/screens/6fcf6069-889a-476e-a60a-2477b9feb995), Zocdoc (https://mobbin.com/screens/14e7f095-1b94-4e03-96e3-1b3fec5c9aa5), Jobber today's appointments (https://mobbin.com/screens/f50ec472-c3f8-4bdc-8bd5-dbd856936025), Formula 1 countdown card (https://mobbin.com/screens/fc6dd715-36b6-4d81-aee5-cc821741dae2).

## Review log

- **Round 1:** tour breaks, staff must not see shop money, FAB must not cover the last row, web deviation to document.
- **Round 2 (checked against the code):** `summary.revenue` is staff earnings for staff, so the More card is labelled by role; `TopProduct` has units only, so the donut uses units and Home shows no dollars; six counts are too many, so only four lead; the old Next Up repeated the first row, so it now shows only within 2 hours; `/app/appointment/new` already exists, no new route; the old `CompactAppointmentTile` goes away.
- **Round 3 (risks):** the large-font case (text scale 1.3) must not overflow the chips (chips size to content and scroll); the demo tour has 34 `home.*` coverage elements (`home.revenue` becomes a More element), so beats, `coverage.json` and audio change in a separate step; the iOS reduce-motion flag was reported unreliable, our phone is Android, verify on the device.

## Built (2026-11-05)

- More: `MoneyCard` (`features/home/presentation/widgets/money_card.dart`) with the eye; state in `money_visibility.dart` (hidden at start, 60 s auto-hide, hides on background, resets for another user).
- Home: `HomeCountChips`, slim Next Up (only within 2 h, `startsSoon`), Appointments with the Bookings tab's `AppointmentTile` (four rows), Staff Calendar below it, Highlights as ranked bars (Services) and donut (Products), `NewAppointmentFab` (collapses on scroll down).
- Admin chips stay three (Upcoming, Customers, Completed) and staff chips five, exactly as the web's cards, so no number appears that the web does not show.
- Deviation from the web dashboard (client request): no money on Home, Next Up is conditional, Highlights are charts, a New button exists.

## Steps

1. More: money card with eye (hidden by default, auto re-hide). Tests.
2. Home: new order, chips, `AppointmentTile` rows, slim Next Up, Staff Calendar below. Tests.
3. FAB with collapse on scroll. Tests.
4. Highlights: bars and donut painters, Services / Products switch. Tests.
5. Tour beats, `coverage.json`, audio regenerate; `docs` note on the web deviation.
6. Phone screenshot loop (`adb screencap`): dark and light, small phone, text scale 1.3, against the references; repeat until it matches.

## Tests to add

- Money card hidden at start, shows after the eye, hides after 60 s (fake clock) and on background.
- Chip order and tap route; staff sees "My earnings" and no shop money.
- Appointments rows are `AppointmentTile`; Today / Upcoming switch.
- FAB hidden without permission; collapses on scroll down, expands on scroll up.
- Reduce-motion on: charts show the final value at once.
- No overflow at text scale 1.3 on a 360 px wide screen.
