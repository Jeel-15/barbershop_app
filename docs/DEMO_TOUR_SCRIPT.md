# In-app demo tour: script (DRAFT v1, SUPERSEDED)

> Superseded by `assets/demo/tour.json` (the real script, one sentence per beat) and `docs/DEMO_COVERAGE_PLAN.md`
> (the plan and its status). This 15-scene outline is kept only for the persona and the safety rules below.

Audience: the Canadian client (and the owner's other prospects). Language: English (Canadian). Voice: Microsoft neural `en-CA`
(`ClaraNeural` female or `LiamNeural` male: samples in `tool/demo/samples/`). Length about 9 minutes. Super-admin flow.
Started from More > Demo tour; plays by itself; the person recording only presses the phone's screen recorder
(Sound: Media sounds) and puts the phone down.

## How the tour looks (the design must stay fully visible)
* **No dimming, no blur, no scrim.** Every animation of the real app keeps playing underneath.
* A **thin animated gold ring** (and a soft pulse) around the control being talked about, never a filled cut-out.
* A small **caption pill** (1 or 2 short lines, like film subtitles) near the bottom; it never covers what the ring points at
  (it moves to the top when the target is low). Captions can be turned off in the tour start screen (voice only).
* A **fake finger dot** shows each tap (a small ring that shrinks onto the control), so viewers see what is being pressed.
* Typing is real: the field fills letter by letter at a human speed. Saves are real.
* Before it starts: a 3-2-1 countdown. While it plays: no fingerprint prompt, no toasts about the tour, no system dialogs.

## The persona the tour creates (Canadian, Edmonton)
New customer **Olivia Tremblay**, phone **780 555 0777**, e-mail **olivia.tremblay@example.com** (not in the database yet).
Barber: **Mike**. Service: **Men's cut** (+ **Beard (razor line)**). Product: **Beard Oil**. Pays by **Visa/Credit Card**, tip 15%.
Everything it creates is undone by `tool/demo/restore.sh` (take `tool/demo/snapshot.sh` first).

## Scenes (narration is what the voice says; caption is the short subtitle)

**1. Welcome** (Dashboard)
Narration: "Welcome to the Rosenthal Barbershop app. This is your whole shop in your pocket: bookings, the calendar, invoices, customers and reports. Let me walk you through it, the way a shop owner would use it on a normal day."
Caption: "Your whole shop, in your pocket."

**2. The dashboard** (scroll slowly: revenue card, Next up, Staff Calendar, top services, top staff)
Narration: "The dashboard shows how the shop is doing right now. Total revenue, upcoming appointments, customers and completed visits. Below that, who is next, and a live view of every barber: who is with a client, who is free, and who is off today."
Caption: "Live shop status."

**3. Add a customer** (More > Customer > the add button; fill; Save)
Narration: "Let's add a new customer. A name, a phone number and an e-mail. Olivia Tremblay. One tap to save, and she is in the directory, ready for bookings and invoices."
Caption: "New customer: Olivia Tremblay."
Real: creates the customer.

**4. The calendar** (Calendar tab; day strip; barber lanes; free slots; zoom button)
Narration: "The calendar is the heart of the app. One column for each barber. Green blocks are free time, hatched areas mean not available, and every booking shows its status. You can zoom the day in or out to see more detail, with a pinch or with this button."
Caption: "One column per barber."

**5. Book an appointment** (Calendar + ; phone number finds Olivia; service; Mike; date; time; Save)
Narration: "Now a booking for Olivia. Type her number and the app finds her. Choose the service, choose the barber, pick a day, and the app only offers the times that are really free. Save, and it appears on the calendar."
Caption: "Only real free times are offered."
Real: creates the booking.

**6. Confirm it** (Appointments tab; filter Pending; open Olivia's booking; Confirm)
Narration: "Every booking lives in the appointments list, with filters for Pending, Confirmed and more. Open one to confirm it, reschedule it or cancel it. Let's confirm Olivia's."
Caption: "Confirm, reschedule or cancel."
Real: confirms the booking.

**7. Create an invoice** (centre + button; phone; service; barber; product; tip 15%; Visa; Create Invoice)
Narration: "When the haircut is done, tap the plus button to create the invoice. Olivia's history appears as soon as you type her number. Add the services, pick the barber who did the work, add a product, choose a tip and the payment method. The total, tax and tip are calculated live. Create the invoice."
Caption: "Invoice in under a minute."
Real: creates the invoice.

**8. The invoice** (View Invoice: totals; scroll; the buttons)
Narration: "Here is the finished invoice, with the shop details, the services, tax and tip. You can e-mail it to the customer, download a PDF, print it, or edit it later."
Caption: "E-mail, PDF, print."
(No mail is sent.)

**9. Reports** (More > Report: cards; Earning tab; Payment Methods; Staff)
Narration: "The reports page turns all of that into numbers: revenue, tips, discounts, earnings by barber and the way customers pay. Filter by date to see any week or month."
Caption: "Revenue, tips and earnings."

**10. Services and products** (More > Services; Service Category; Product; GST)
Narration: "Your menu lives here. Services with their photos, prices and durations, grouped in categories. Retail products with stock and commission. And the tax rates used on every invoice. Everything can be added, edited or removed."
Caption: "Your menu, prices and tax."

**11. Shop settings** (More > Setting; Closures & holidays; Slots; Payment methods)
Narration: "Shop settings cover your contact details, opening hours for each day, holidays and early closings, and the payment methods you accept. Closed days are respected by the booking page automatically."
Caption: "Hours, holidays, payments."

**12. Website content** (Testimonials; Gallery)
Narration: "The reviews and pictures shown on your website are managed here too, so the website always stays fresh without calling a developer."
Caption: "Reviews and gallery."

**13. Your team** (Staff; open a barber profile; Roles & Permissions; a role)
Narration: "Add your barbers, set their commission and the services they offer. Then decide exactly what each person may do with roles and permissions. When you change a role on the website, the app follows by itself, with no sign-out."
Caption: "Team, roles and permissions."

**14. Security and style** (More > Security: the fingerprint row only; Appearance: Dark, then Light)
Narration: "For safety, you can unlock the app with your fingerprint, and choose how soon it locks again. And if you prefer a darker look, switch the appearance in one tap."
Caption: "Fingerprint lock, light and dark."
(The fingerprint switch is shown, not turned on, so no prompt appears.)

**15. Goodbye** (Dashboard)
Narration: "That is the Rosenthal Barbershop app. Everything the website admin panel does, simple, fast and always with you. Thank you for watching."
Caption: "Rosenthal Barbershop."

## Technical notes (not part of the video)
* Audio: one mp3 per scene, generated from the narration text above by `tool/demo/make_audio.mjs` (edge neural voice), stored in `assets/demo/`.
* Step timing: each step waits for its audio to finish, plus a short pause; typing and taps run while the voice speaks.
* Targets are found by keys we add to the real widgets; a widget test per scene keeps the tour from silently breaking when a screen changes.
* The tour only runs from the More menu and only on dev/demo builds (hidden in production).
