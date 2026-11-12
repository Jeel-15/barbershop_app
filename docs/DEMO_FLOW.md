# Demo video flow: Rosenthal Barbershop app (Super-admin)

Audience: shop owner / client. Length about 9 to 11 minutes. Phone: Samsung, light theme (dark theme as a 10 second bonus).
Account: Super-admin (`apitest.admin@rosen.test`, shows as "API Test Admin" with the Super-admin chip).
Everything below was checked on the real phone against the demo data (1,146 invoices, 90 customers, 22 services).

## Before you press record (2 minutes)
1. Install the latest build, open once, sign in, then **More > Security > Fingerprint unlock = OFF** (so no prompt appears while filming). Turn it on again for scene 12.
2. Phone: Do Not Disturb on, battery above 50%, screen brightness 70%, Wi-Fi on, screen recording on (system recorder).
3. Pull to refresh the Dashboard once so the "Now" clock and Next up are fresh.
4. Do not use real customer data on screen: the demo customers are fine ("Jordan Ivanov 7805550118" exists with 26 visits).

## Scenes (what to show, what to say, what to tap)

| # | Time | Screen | Tap path | Say (one line) |
|---|---|---|---|---|
| 1 | 0:00 | Splash, Welcome | open app | "This is the Rosenthal admin app: everything the web panel does, in your pocket." |
| 2 | 0:20 | Sign in | Sign in, e-mail + password | "Sign in once. Wrong password and 'Forgot password' work like the website." |
| 3 | 0:50 | Dashboard | stay on Home | "Today at a glance: revenue, upcoming, customers, next appointment, who is free now." Scroll: Staff Calendar, top services, top staff. |
| 4 | 1:40 | Appointments | tab 2 | "Every booking, filter by status (Pending 140, Confirmed 125...), search, filter button." Open one: Confirm / Reschedule / Cancel. |
| 5 | 2:40 | Calendar | tab 4 | "One column per barber. Green = free, hatched = not available." Show: day strip, Pending/Confirmed chips, zoom button, **pinch to zoom**, landscape view. |
| 6 | 3:50 | New booking | Calendar + | "Phone number finds the customer. Pick service (with photos), barber, date, time." Save. |
| 7 | 4:50 | POS: Create Invoice | centre + button | "Type the phone: the customer's visits and spend appear. Add service, pick the barber, tip 15%, Cash, Create Invoice." Show the total update ($15.00 → $17.25 with tax and tip). |
| 8 | 6:00 | View Invoice | More > POS & Invoice > first row | "Send by e-mail, PDF, print, edit." |
| 9 | 6:40 | Customers, Reports | More > Customer; More > Report | Customer list, call/message; Reports: revenue, tips, earning tabs. |
| 10 | 7:40 | Catalog | More > Services / Service Category / Product / GST | "Services and products with photos. Add, edit, delete. Tax rates." Show one **Add** form and one **Delete** confirmation. |
| 11 | 8:40 | Shop + Team | More > Setting, Closures, Slots, Payment methods, Testimonials, Gallery, Staff, Roles | Fast tour, 5 seconds each. "Opening hours per day, holidays, website reviews, team and permissions." |
| 12 | 9:40 | Security + live access | More > Security | "Turn on fingerprint unlock: next time the app opens with your finger. Lock after: Immediately / 1 / 5 / 15 minutes." Leave the app, come back: lock screen, fingerprint, in. |
| 13 | 10:30 | Close | More > Appearance | "Light, dark, auto." End on the Dashboard. |

## Bonus scene (needs a second screen with the web admin): "change a permission, no logout"
1. Web: Roles, open a role, untick Calendar view, Update.
2. Phone (signed in as that role): open Appointments or pull to refresh the Dashboard: the **Calendar tab disappears** and a note says "Your access was updated by an administrator."
3. Web: tick it again: the tab returns on the next action.
Use a Staff-role account for this (a Super-admin works too, the Super-admin role in this shop is an ordinary role).

## Things to avoid on camera
* The **Developer** group at the bottom of More (design gallery, connection test): scroll past it quickly. It is hidden in the production build.
* Do not delete real data. The delete demo should use a throw-away record (we deleted the test GST "rttty" already).
* Do not open Gallery before adding pictures: it shows the friendly empty state, which is fine, but add one picture first if you want it to look full.
* The demo e-mail "Send Invoice Mail" really sends mail when the shop's mail settings are on; leave the switch off in Settings if you do not want that.

## Results of the full check (2026-10-29, phone, Super-admin)
Opened and worked: Home, Appointments, Calendar (+ new booking form), Create Invoice (customer lookup, service sheet with photos, staff chips, live total, create), View Invoice, Invoices list, Customers, Reports, Services, Service Categories, Products, GST (delete tested), Settings, Closures, Slots, Payment methods, Testimonials, Gallery (empty state), Staff, Roles, Security (switch, Lock after picker, lock on return).

Fixed during the check: long labels were cut ("Yes, confi...", "Save Ap...", "Do..." for Download PDF): buttons now shrink the text to fit; product rows no longer squeeze long names ("Aftersh...") next to the Active pill; amount tiles in Reports no longer wrap "$10,477.67" into two lines; a testimonial or staff row with a missing or slow photo shows the neutral tile instead of a blank hole.

Known and not touched: the Security row text is shortened to fit one line; the shop's demo data has some very long server images (up to 1.7 MB), so the first open of a photo list can take a moment on mobile data.
