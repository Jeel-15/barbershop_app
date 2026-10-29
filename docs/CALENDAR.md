# Calendar: the rules

The app's calendar follows the web's staff calendar (`admin-staff-calendar.js`,
`AppointmentController::fetch` / `fetchStaffAvailability`). Code: `lib/features/calendar/`.
The rules live in one pure class, `domain/day_timeline.dart` (`LaneTimeline`), with tests in
`test/features/calendar/day_timeline_test.dart`.

## What is drawn

| What | Look | Meaning |
|---|---|---|
| Free | soft green box, "Free · 1h 15m" | working time with nothing booked (the web's green "AVAILABLE" boxes) |
| Not available | grey hatching, "Not available" / "Day off" / "No working hours set" / "Shop closed" | outside the barber's working hours, a day off, or the shop is closed |
| Pending | amber, **dashed** outline, hourglass icon | waiting to be confirmed |
| Confirmed | blue, check icon | confirmed |
| Rescheduled | violet, swap icon | moved |
| Completed | green, check icon, slightly faded | done (the web hides invoiced bookings; rare here) |
| Break | grey hatching + coffee icon | a break |
| Red line + badge | now | earlier time of today is dimmed |

Colour is never the only signal: every status also has its own icon, and tall cards print the status word.
The strip under the dates is the legend: a chip per status with the day's count; tapping one keeps those bookings
bright and dims the rest. "Guide" opens a sheet explaining everything.

## What a tap does

1. **Free spot** -> marks it ("Book 11:45 AM", dashed gold). Tapping the mark opens Add Appointment with the barber,
   date and time filled. Tapping anywhere else moves or clears the mark. (A single tap never opens a form by itself:
   scrolling with a finger cannot start a booking by accident.)
2. **Not available / day off / shop closed / past / break** -> no form, a short message says why
   (the web: "Staff Not Available").
3. **A booking** -> its details and actions (Confirm, Complete, Cancel, Reschedule, Edit).
4. **+ (top right of the header)** -> Add Appointment for the shown day, any time (also in the past, for back entry).

## Column order (drag)

The web lets you drag a column header. In the app: tap the groups icon (or hold a barber's header) -> "Column order" ->
hold the handle and drag a barber up/down. The order is kept on the phone. Tap the date in the header to jump to any day.

## Availability rules (same as the web)

- A barber's working time is `tbl_breaks` with `break_type = 1` for that weekday. **No working hours = the whole
  column is "Not available"** (the old app treated this as "the shop hours": fixed).
- A barber the server sent no data for (or when the server could not be asked) is not blocked: the shop hours apply.
- Breaks (today's `break_type = 2`) and bookings take time out of the free stretches. Overlapping bookings do not
  leave a gap; a booking with no length still takes 15 minutes.
- Today: the clock plays no part; earlier free time can still be booked (back entry), like the web.
- The shop-closed day blocks every column (the web only greys it; the booking engine would refuse it anyway).
- The availability answer is re-asked every time the calendar is refreshed or Working Hours / Slots change
  (before, it was cached for the life of the app).

## Landscape view (full screen)

The button at the right end of the legend strip (the corners icon) opens the day full screen and turns the phone sideways.

- **Rows = barbers, time runs across** (the "resource timeline"). Portrait columns answer "what happens during the day"; rows answer "who is free when, compared across everyone", which is what a wide screen is for. Every barber is on screen at once (5 barbers fit a 360 dp tall phone), the names are pinned on the left and the hours on top.
- **Detail / whole day**: the zoom button switches between about 110 px per hour (names readable, scroll sideways, opens at "now") and the whole day fitted to the width.
- **Same rules as portrait**: green = free working time, hatched = not available, bookings in status colours, breaks grey, red line + pin = now. Tap a booking for its details and actions; tap free time to mark it ("Book 11:45 AM"), tap the mark to open the form; tap anywhere else and a short message says why not.
- **Forms open in portrait** (the keyboard fills a landscape screen); the day comes back in landscape after saving.
- Close (X or back) turns the phone back to portrait. Code: `landscape_calendar_page.dart`, route `/app/calendar/landscape`.
- Android 16 on screens 600 dp and wider ignores app orientation requests; phones are fine.
