# Fixes needed in the web admin panel (for the web developer)

**Project:** Rosenthal Barbershop web admin (`rosen_barber`, Laravel)
**Why this list exists:** while building the mobile app (Admin + Staff only) we copied the web's behaviour on purpose, so the app and the web always agree. Everything below is something the web does **wrongly or unsafely**. The app currently repeats it (or hides it) and will be corrected **after** the web is fixed.

**How to use this file:** fix the items, tick them off, send the file back. We then re-run our parity tests and switch the mobile app/API to the correct behaviour (see "After you fix it" in each row and the checklist at the end).

Severity: 🔴 money / security · 🟠 wrong data · 🟡 annoying / cleanup.
Numbers (Q1...) are the same ids used in `docs/API_PLAN.md` section 8.

---

## 1. Fix first: security (🔴)

| # | Where | Problem | Suggested fix | After you fix it |
|---|---|---|---|---|
| Q3 | `confirm_reject_action` (appointment confirm / cancel) | No ownership check, and it accepts **any** integer status (a completed invoice could be set to status 7). Any logged-in user can change any appointment. | Whitelist status `3` (confirm) and `2` (cancel); allow only valid transitions (Pending/Rescheduled to Confirmed; Pending/Confirmed/Rescheduled to Cancelled); staff only on their own appointments. | Nothing: the API already enforces this. |
| Q6 | `staff.change-password` | Any logged-in user can change **any** user's password by id. | Require `Staff-Edit` (or the user's own id plus the current password). | Add "Change my password" to the app (AUTH-9). |
| Q7 | `permission` resource (create / edit / delete) | Any logged-in user can add, edit or delete permissions. | Gate every action with a role permission (Super-admin only). | Nothing: the app never exposes it. |
| Q8 | Working hours update / delete / day-off | Not scoped to the logged-in staff: anyone can edit another barber's hours by id. | Check `staff_id == auth()->id()` (admin may edit any). | Nothing: the API already checks. |
| Q9 | POS invoice create / update | Totals, prices and discounts come from the browser and are saved as sent. A tampered request can create any amount. | Recompute every figure on the server from catalog prices, tax and discount percentages; ignore client totals. | Nothing: the API already recomputes. |
| Q43 | Staff create / edit / delete / password | Endpoints accept any role id (also Super-admin) and any user id (also the Admin). The form only hides them. | Whitelist the role ids the form offers and refuse Admin / Super-admin users. | Nothing: the API already restricts. |
| Q16 | GST | Un-defaulting or deleting the default GST leaves **no default**, so new invoices get **0 tax**. | Refuse the change unless another default is set in the same request. | Remove the app's extra warning. |
| Q44 | GST | Saving the default GST without ticking "default" silently un-defaults it. | Keep the default flag unless explicitly changed. | Same as Q16. |

## 2. Fix next: wrong money or wrong data (🟠 / 🔴)

| # | Where | Problem | Suggested fix | After you fix it |
|---|---|---|---|---|
| Q1 / Q36 | Dashboard **Top Services**, **Staff performance**, staff report, report summaries | `SUM(DISTINCT total_amt)` and `SUM(DISTINCT commission)`: two appointments with the same amount count **once**; cancelled / pending appointments are counted too; staff performance counts joined rows, not appointments. | Sum per appointment (no DISTINCT), completed appointments only, and `COUNT(DISTINCT appointment_id)` for counts. Same for the admin **Total Revenue** card (it sums every appointment of every status). | The app currently shows **booking counts only** for Top services and hides revenue/team performance. After the fix we add the money back. |
| Q29 | Dashboard (Admin) "Tips" | The tip total joins appointments to their service lines and sums `total_tip` per **joined row**: an appointment with 3 services counts its tip 3 times. (Local data: web shows $58.00, real total is $52.00.) | `SUM(total_tip)` over `tbl_appointment` without the join. | The app does not show admin tips yet; we will add it. |
| Q5 | Appointments / Dashboard "Complete" button | **Root cause found.** The button links to `invoice/edit/{id}`. `InvoiceController@edit` (line ~684) and `@update` (line ~1044) both start with `$this->invoicesVisibleToCurrentUser()`, and that helper (line 47) begins with `Appointment::where('is_invoiced', 1)`. A booked appointment has `is_invoiced = NULL`, so `->firstOrFail()` throws and the browser shows **404**. (For staff the helper also keeps only rows where `invoice_created_by` is the staff, which a booking never has.) The page itself and `update()` are fine: `update()` already turns the row into an invoice (`status = 1`, `is_invoiced = 1`, new invoice number). | Add a second helper for these two actions and use it in `edit()` and `update()` (keep `invoicesVisibleToCurrentUser()` for the invoice **list**):<br>`private function appointmentForInvoicing($id) { $q = Appointment::where('appointment_id', $id)->where(fn($q) => $q->where('is_invoiced', 1)->orWhereIn('status', [0, 3, 4])); $u = auth()->user(); if ($u && $u->isStaffUser() && !$u->can('Pos_invoice-Show_All')) { $q->where(fn($q) => $q->where('invoice_created_by', $u->getKey())->orWhereHas('services', fn($s) => $s->where('staff_id', $u->getKey()))); } return $q; }`<br>Then `$appointment = $this->appointmentForInvoicing($id)->firstOrFail();` in `edit($id)` and `$this->appointmentForInvoicing($request->input('appointment_id'))->firstOrFail();` in `update()`. In `update()` also add `'invoice_created_by' => $appointment->invoice_created_by ?? auth()->id()` to the `$appointment->update([...])` array, otherwise staff cannot open the invoice they just made. | **Done on our side already (2026-10-26):** the app's Complete button opens the invoice page for the appointment and saves through APPT-11 (flag `complete_from_appointment` is ON). The web still 404s, so staff must use the app for this until the web is fixed. |
| Q51 | Calendar (new) | The calendar only has a column for staff with `is_barber = 1`. A booking created for any other staff (for example JOJO, Jack Sparrow in the local DB) is **invisible** in the calendar. Calendar create does not check `is_barber`. | Either refuse booking a staff who is not a barber, or show a column for every staff who has bookings. Mark the real barbers as `is_barber = 1` in the data. | The app follows the web (barber columns only). After the fix nothing to change if you choose "refuse"; if you show all staff we copy that. |
| Q4 | Reschedule | No slot validation (double booking possible) and no ownership check. | Validate against the slot engine, check staff ownership. | Nothing: the API already validates. |
| Q26 / Q32 | Calendar create | Overlap check compares `TIME` columns with full datetimes, is inclusive (an appointment starting exactly when another ends is refused) and ignores status (a **cancelled** appointment still blocks the slot). | Compare times correctly, make the end boundary exclusive, ignore status `2`. | The API will drop its mirrored behaviour. |
| Q21 | POS mail | The invoice email is sent **inside** the DB transaction; if mail fails the invoice is rolled back. | Send after commit (queued). | Nothing: the API already sends after commit. |
| Q12 | Customers | Duplicate phone numbers allowed; booking uses the first match; POS can create a duplicate. | Unique digits-only phone; reuse the existing customer. | Nothing: the API matches on digits. |
| Q24 | Manager role | Stored with `users.role = 'Staff'`, so a Manager is scoped like staff and blocked from reports. | Give Manager its own panel role or scope by Spatie role. | The app then shows Manager the admin menu. |
| Q40 | Staff create | New barber's default hours (09:00-13:00, 14:00-18:00) are saved as `break_type = 2` (a break), but "My working hours" reads `break_type = 1`, so new staff start with an empty hours page. | Save them as `break_type = 1`. | The app's empty state goes away on its own. |
| Q41 / Q42 | Staff profile cards | Revenue / appointments / visits are for the **whole shop**, only tips and commission are the person's own; the staff's total product commission is repeated on every day row. | Scope every card to the staff, show the product commission per day. | We drop the "shop-wide" labels. |
| Q35 | Customer profile | "Total spend" adds each invoice once **per service line**, plus every product commission ever generated. | Sum each invoice once. | The app shows the correct total. |
| Q38 | Edit invoice | Re-prices every line at **today's** catalog price, rewriting history. | Keep the stored price of unchanged lines. | Nothing: the API already keeps stored prices. |
| Q39 | Invoice tip | The tip split is stored as unrounded floats (1.6666666667). | Split in cents so the parts add up. | Nothing: the API already splits in cents. |
| Q46 / Q2 | Staff earnings report | The row query ignores the **end date** (start date is written twice); the summary honours both. | Apply both dates in the main query. | The API drops its mirrored behaviour. |
| Q47 | Customer invoices report | "Amount" is what the staff earned (commission + tips), not the invoice total. | Rename the column or show the invoice total. | We relabel. |
| Q48 / Q49 | Top products / appointments / payments reports | Top products grouped by product **and** discount (several rows per product); appointments report rows need an invoiced appointment but its summary only needs status 1; payments report ignores the staff filter. | Make rows and summaries use the same rules; honour the filter. | The API drops its mirrored behaviour. |
| Q14 / Q50 | Gallery | "Replace image" writes a `description` column that does not exist (SQL error). Gallery routes have no permission check (only the buttons are hidden). | Fix the column; add `can:` middleware. | We add description editing. |
| Q15 | Service / Product update | A missing `active_status` checkbox silently sets status 0. | Send an explicit value (hidden input) or keep the old value. | Nothing: the API uses explicit booleans. |
| Q17 | POS | Product **stock never decreases** when a product is sold. | Decrement stock on sale (and restore on edit / delete). | The app shows live stock. |
| Q10 | Calendar fetch | Returns every appointment ever and every break, no date range. | Require `start` / `end`. | Nothing: the API already requires a range. |
| Q18 | Shop hours (`SlotController`) | Rows found by **day name only**; a staff row can be overwritten if it sorts first. | Look up by `staff_id = 0` plus day. | Nothing. |
| Q34 | Edit appointment | The customer record is found by phone and **not renamed** when the name changes. | Update the customer name too, or tell the user. | Nothing. |
| Q45 | Payment methods | A deleted method's name stays reserved (the unique rule counts deleted rows). | Ignore soft-deleted rows in the unique rule. | Nothing. |
| Q31 | Reschedule | A service booked with quantity 2 is checked as one unit. | Use the real quantity. | The API drops its mirrored behaviour. |
| Q33 | Staff-by-service | Ignores the barber's `active_status`. | Filter inactive barbers. | Same. |

## 3. Cleanup (🟡)

| # | Where | Problem | Suggested fix |
|---|---|---|---|
| Q11 | Many joins | `tbl_appointment.customer_id` is `varchar` joined to a bigint (no index use); `Schema::hasColumn()` is called inside list endpoints (each is an `information_schema` query). | Change the column type; cache schema checks. |
| Q13 | `getStaffByService` | HTTP 500 when `service_ids` is missing. | Validate input. |
| Q19 | Invoice number | Random 4 digits (collisions are retried). | Sequence-based number. |
| Q20 | POS guest customer | Placeholder email / phone of another brand (`info@bluecrownbarbers.com`, `(555) 123-4567`). | Use Rosenthal's or leave blank. |
| Q22 / Q27 | Dashboard vs appointments list | Staff dashboard counts "first available" lines for the staff, the staff list excludes them; "today" excludes invoiced appointments. | Make both screens use one rule. |
| Q23 | `Appointment::$appends = ['staff_names']` | N+1 query on every serialized appointment. | Load once with the list query. |
| Q25 | Scheduler | `email:service-followups` runs **every minute**. | Reduce the frequency. |
| Q28 | Timezones | Laravel uses `America/Edmonton` but MySQL `NOW()` uses the server clock (about 6 h different). Raw `NOW()` mixes the two. | Use one timezone everywhere (or pass Carbon times, never `NOW()`). |
| Q30 | Appointments search | A search that matches through a **staff name** shows only that staff member's lines in the row. | Search without filtering the joined rows. |
| Q37 | POS catalog | The POS lists **inactive** services/products too. | Hide inactive items. |
| Q52 (new) | Dashboard permissions | The permission `Dashboard-Top_Staff` exists and `getStaffPerformance` is built, but the dashboard page has no staff-performance widget. | Remove the unused endpoint/permission, or add the widget (with the Q1 fix). |

---

## After you fix it: what we do on our side

When the web fixes are done, tell us which ids are fixed. We then:

1. Re-run our parity tests against the fixed web.
2. Remove the "mirrored" behaviour in the API for the fixed ids (see "After you fix it").
3. Turn on the features that were waiting: **Complete appointment** (Q5), **change my password** (Q6), live **stock** (Q17), **revenue / tips** figures on Home (Q1, Q29).
4. Rebuild and re-test the mobile app with both roles.

## Local test data to ignore / clean up

* Test accounts: `apitest.admin@rosen.test`, `apitest.staff@rosen.test` (password in our notes; delete before going live).
* Demo bookings with notes `APITEST-home` (created through the API for screenshots); they can be deleted.
* Local DB only: JOJO (id 47) and Jack Sparrow (id 40) are **not** marked as barbers (`is_barber = 0`), which is why they have no calendar column (see Q51).
* The local `.env` has the **live SMTP credentials**: never send test mail from it.

_Last updated: 2026-10-26. Source of truth for details and evidence: `docs/API_PLAN.md` section 8 (Q1-Q50)._

## Q53 — Customer profile: wrong table title and broken status filter

- `customer-profile.blade.php` titles the table **"Pending Appointment"**, but `PendingAppointmentgetTableData` returns *every* appointment of the customer (any status). The app calls it **Appointments**.
- Same method: `if ($request->filled("status")) $query->where("a.status",);` — the value is missing, so the status filter would throw/never filter. (The API version filters correctly.)
- `CustomerController::destroy` deletes a customer who still has appointments; the API refuses (409) instead.

## Q54 — Invoices page

- The list loads **every** invoice in one go (`->get()`, no paging) and renders them server-side: it will get slow as invoices grow. The API pages them.
- "Date" is `updated_at`, so editing an invoice moves its date.
- The invoice preview prints Qty = 1 for every line and prefixes lines with "Service #" / "Product #"; the PDF file is always named `Blue-Crown-Barbers-invoice.pdf`.
- "Send Invoice Mail" silently does nothing for the guest placeholder address (`info@bluecrownbarbers.com`) but still answers "Mail Successfully Send". The API answers 422 instead; the app asks for an address.
- The preview "Subtotal + Tax + Tip" does not add up to "Total Amount" when tax is included in the prices.

## Q55 — Profile, Staff Report, Working Hours

- `ProfileController::staffStats` counts `Completed Services` with `count(b.appointment_id)` over the service rows, so an appointment with 3 services counts 3 times (and "Total Visits" counts customers, not visits).
- Staff Report cards (`StaffreportController`) and the profile cards use different filters (the report also counts non-invoiced appointments) so the two pages can show different earnings for the same staff.
- Working Hours: `update()` / `destroy()` use `Breaks::findOrFail($id)` without checking that the range belongs to the signed-in staff member — any staff can edit or delete someone else's hours by id. `updateFullDayOffStaff` has the same problem (`where id = dayId`). The API checks ownership.
- Working Hours `store()` accepts `end_time` after `start_time` as plain strings (`after:start_time`), so `09:00` / `9:00 PM` formats can be mixed.

## Q56 — Staff

- `changePassword()` (`staff/change-password`) has no permission check and no existence check: any signed-in user can POST a `staff_row_id` and reset any account's password (including the owner's), and an unknown id is a 500 (`User::find()` returns null). The route sits outside the `Staff-Edit` middleware. The API requires `Staff-Edit` and answers 404.
- Validation failures of the password form return HTTP 200 with `success:false`, while the rest of the page checks `status`.
- `destroy()` lets a user delete their own account and the system "First available" staff entry the booking calendar needs. The API refuses both (409).
- `staff-profile/{id}` can be opened by any signed-in user for any id (the page reads `User::find`); the API limits it to the member themself or Staff-Add/Edit.
- A new staff member gets their weekly slots with the default hours stored as *breaks* (`break_type = 2`), not working hours (type 1), so a new barber shows as "Not Available" on the calendar until they set Working Hours.

## Q57 — Catalog (Services, Categories, Products, GST, Payments)

- Service `update()` and `store()` set `status` / `tip_status` from `$request->has("active_status")`: a missing switch silently turns the service **off** (and the web form starts with Active unticked). The API takes explicit true/false; the app starts a new service as Active.
- `ServicecategoryController::store` checks `$category->service_img` (a column that does not exist) when a picture is uploaded; harmless on create, but the delete-old-image branch never runs there.
- Deleting a **category** (soft delete) leaves its services and products pointing at it; the Services/Products lists use an inner join to the category, so they still show, but the category no longer appears in the form dropdowns and cannot be re-selected.
- Product `commission` is required in the validation but the form label has no asterisk; the services list says "30 Minite".
- The GST "Default" checkbox only clears the other rows when ticked; unticking the only default leaves the shop with no default tax (new invoices get no tax). The API warns when the default is deleted.
- Payment methods: `store`/`update` validate uniqueness but a soft-deleted name still counts as taken.

## Q58 — Slots, Shop Closures, Settings

- `SlotController::store()` looks the day up with `Slot::firstOrNew(['day_name' => $day])` — **without `staff_id = 0`**. The first row with that day name is whatever comes first, usually a *staff member's* slot, so saving the shop hours can overwrite one barber's hours and leave the shop's own row unchanged. The page reads `where('staff_id', 0)`. The API always uses `staff_id = 0`.
- `SlotController::update()` (never routed) drops `open_time`/`close_time` and the break type.
- The Slot page has no validation: an open day can be saved with empty times (the booking engine then falls back to 09:00-21:00).
- Shop Closures: the server accepts an empty `close_reason`, the JS requires it; `update()` overwrites `created_by` with the editor.
- Shop Closures delete answers HTTP 200 with `status: 0` for a missing row.
- Settings: the `whatsapp` number is reduced to digits server-side, so a typed "+1 780..." comes back as "1780...".
- Settings: the whole "Change Password" tab is commented out in `setting/index.blade.php` (the subtitle still promises "account security").

## Q59 — Roles & Permissions

- `RolesController::destroy` deletes a role that is still assigned to staff (spatie then leaves those users without the role, so they lose every permission silently) and only the *button* is hidden for ids 1, 2 and 4; the route itself accepts any id. The API refuses system roles and roles still in use.
- `update()` lets anyone with `Role-Edit` rename the system roles (`Staff`, `Accountant`, `POS Manager`, `Super-admin`); the app and API code look roles up by those names, so renaming one breaks sign-in rules. The API refuses the rename.
- `Role-Edit` can grant itself any permission (including `Role-*` and `Staff-*`): there is no check that you may only hand out permissions you hold.
- Permission labels are derived from the name (`Show_All` -> "Show All"); a few groups (`Pos_invoice`, `Service_Category`) show the raw code as the group title.

## Q60 — Reports (more of what Q47 started)

- **Staff tab / Earning cards:** `GetStaffEarnGetTableData` filters `a.date >= start_date` **twice** and never applies `end_date` to the rows (only to the summary), so the table ignores the End Date.
- **Staff tab:** `SUM(DISTINCT p.product_commision)` removes equal commissions (two products with the same commission count once), and the product join is on (appointment, staff) so a staff with two services on one invoice sees the product commission repeated.
- **Payment Methods:** `LEFT JOIN ... WHERE a.status = 1` is an inner join; a method with no sale is missing from the table instead of showing $0.00, and the staff filter is ignored for the rows.
- **Invoice tab:** the **Amount** column is what the staff earned (commission + tips), not the invoice amount, under a header the owner reads as the invoice total (Q47). The app shows both: "Total" and "Staff earned".
- **Earning tab:** the table only lists *completed and invoiced* appointments but the card "Total Appointment" counts status 1 only, so a cancelled booking never shows; the 4 cards on the Earning tab come from a different query than the 4 headline cards and can disagree for the same filter.
- **Top Selling Products:** the revenue formula applies `a.product_discount` after subtracting commission and groups by the discount, so the same product appears on several rows when invoices had different discounts.
- The "Staff Performance Details" and "Service Details" modals are left-over mock-ups ("John Doe", "Bread Color"); no button opens them.

## Q61 — Testimonials and Gallery

- `GalleryController` lives in `App\Http\Controllers` (not `Admin`) and its routes have **no permission middleware**: any signed-in admin-panel user can open the page and POST/PUT/DELETE gallery images; only the Delete *button* is hidden by `Gallery-Delete`. The API checks `Gallery-Add/Edit/Delete`.
- `Gallery::update()` accepts a `description` that no screen ever shows or sets (the column is always empty), and the gallery list has no order or caption.
- Testimonials: the form's "Show on website" starts **unticked** (so a freshly added review is Hidden until the switch is turned on); the table silently trims the review to 80 characters; `sort_order` ties are not broken, so equal "Display Order" values come out in id order.
- Testimonials delete only removes the picture if it is not under `frontend/` (the seeded ones); deleting such a testimonial leaves the file, which is intended but undocumented.
- Testimonial/gallery pictures are saved under `storage/` and shown through the public symlink; if `php artisan storage:link` is missing on a server every picture is a broken image.

## Q62 — Staff calendar (what the app had to match, and the web's gaps)

- `AppointmentController::fetch` only returns appointments with `is_invoiced IS NULL` (`->where(fn ($q) => $q->orWhereNull('is_invoiced'))`) and `status != 2`: a **completed (invoiced) booking disappears** from the calendar the moment it is paid, and cancelled ones are never shown. There is no way to see the day's finished work there.
- All appointments are drawn in one style (`is-appt`); pending, confirmed and rescheduled look the same, so the calendar cannot tell "needs confirming" from "confirmed".
- Clicking is only blocked by the availability overlay: a booking can be started in the past and on a day when the *shop* is closed (`shop_day_off` is returned but not used by the JS).
- A barber with **no working-hours rows** is shown as completely "Not Available", with no hint of why (see Q56: new staff get their default hours as breaks, type 2).
- A break belongs to a *day* through its `created_at`, not a real date column, so a break made late at night near midnight (server time) can land on the wrong day.
- Column order is a browser-only setting (`localStorage`), not shared between devices or people.

## Q63 - Booking conflicts (found by the live audit, fixed in the API)

- `AppointmentController::calenderAppointMentStore` (web) refuses a booking when another appointment of the same barber *touches or overlaps* the time, and it **does not look at the status**: a **cancelled** booking keeps blocking its slot even though the calendar hides it, and a booking that ends at 10:30 blocks one that starts at 10:30 (`whereBetween` is inclusive at both ends).
- The slot list said such a time was free, then saving answered "This staff already has an appointment in this time slot."
- The API (`AppointmentBooking::overlaps`) now ignores cancelled bookings and uses a real overlap (start < other end and end > other start). The web page itself is untouched, so it still has the old behaviour.

## Q64 - Deleted rows keep their name (found by the live audit)

- Payment methods, GST, categories, services, products and staff are **soft deleted**, but the name / e-mail stays reserved: after deleting a payment method "Cash2" you cannot add "Cash2" again ("The name has already been taken."), and a deleted staff member's e-mail can never be used again.
- Deleting a service **category** does not delete or hide its services; they stay in the list with a category that no longer exists.

## Q65 - Live permissions for the app (API addition, nothing in the web changed)

- When an admin changes a user's role or permissions on the web, the app must follow without a sign-out. The API now sends a short fingerprint of the user's access:
  - `X-Permissions-Version: <12 characters>` on **every answer to a signed-in user** (200, 403, 422... not on public routes or on a 401). Added in `ApiEnvelope::withPermissionsVersion`.
  - `permissions_version` in `data.user` and at the top of `data` of `POST /auth/login`, `GET /auth/me` and `GET /bootstrap` (`UserPresenter::version`).
- The hash covers: panel role, spatie roles, every permission (direct and via roles), the module flags, home module, staff scope, barber flag. It changes when any of these change and only then (verified: revoking one permission changes it, rolling back restores it).
- Cost: the role/permission relations are re-read once per request (2-3 small queries) so a change made in the same request is counted.
- The app re-reads `/bootstrap` when the header differs from the one it holds, on a 403, and when it returns to the foreground (once a minute at most). No polling.
- Deploy: these four files only (`UserPresenter.php`, `ApiEnvelope.php`, `AuthController.php`, `BootstrapController.php`); no migration, no config.

## Q66 - Super-admin is a normal role: its permissions can be removed, which can lock everyone out (found while testing live permissions)

- The web has no "Super-admin bypass" (no `Gate::before` anywhere in `app/`). `Super-admin` is just a spatie role that happens to have every permission ticked; `$user->can('X')` is true only while that row exists in `role_has_permissions`.
- On the Roles page (`RolesController::update`, line ~176) the permission ticks of **any** role, Super-admin included, can be removed, and with nothing ticked `syncPermissions([])` empties the role completely. Only the *rename* and the *delete button* are protected for roles 1, 2 and 4.
- Result: an admin who unticks `Role-Edit` (or `Role-View`) on their own role can no longer open the Roles page. Nobody can undo it from the panel; it has to be fixed in the database. Verified on the test DB: removing `Calender-View` from Super-admin made `can()` false and the Calendar vanished for that user (and was restored afterwards).
- Related and already listed in Q59: `Role-Edit` can grant itself any permission.
- Suggested fix (web developer), either:
  1. one line in `AuthServiceProvider::boot()`: `Gate::before(fn ($user) => $user->hasRole('Super-admin') ? true : null);` so Super-admin always passes every check, or
  2. in `RolesController::update`, refuse to save a locked role (ids 1, 2, 4) without its `Role-View` / `Role-Edit` permissions, and refuse an empty permission list for Super-admin.
- The app needs no change for either: it only follows what the server says (`permissions`, `modules`, `permissions_version`).
- Optional API-side guard (needs the owner's OK): `RoleAdmin::update` answers 409 "System role" when a locked role would lose `Role-View` / `Role-Edit`, so the app cannot cause the lock-out either.

## Q67 - Permissions that the code asks for but that do not exist (found by the app's permission contract test)

- `Pos_invoice-Show_All` (web: `InvoiceController`, the `canany` middleware on the invoice routes) and `Gallery-Edit` (API gallery routes, mirrored from the web) are **not rows in the `permissions` table**. Nobody can be given them on the Roles page, so they never grant anything; spatie's `can()` on an unknown name just answers false.
- Effect today: a Staff-role user always sees only their own invoices (the "see all" case can never be switched on), and Gallery edit is covered by `Gallery-Add` alone.
- Fix (web developer): either add the two rows to the permissions seeder / table (then the Roles page can grant them), or stop referring to them. The app does not depend on either.
- The app now checks this automatically: `tool/live/export_permission_contract.sh` exports the stored permissions and each route's required permission; `test/permissions_contract_test.dart` fails when the app names a permission the server does not know, when the server stores a new one the app does not know yet, or when an Add/Edit/Delete the server enforces guards no button.

## Q68 - Staff money: commission audit (checked against the local database, 2026-11-04)

**Fix first (🔴 wrong money shown to the owner):**

1. **Staff > a staff member > Earnings tab: the same product commission on every day row.** `StaffController.php` lines ~123-154: `$productSub` is grouped by `staff_id` only (the staff's whole product commission) and joined to the daily rows with `s.staff_id = p.staff_id`, then the rows are grouped by `a.date, s.staff_id, p.product_commission`. So every day shows the staff's **total**, and `total_earn` per day is inflated by it. Proof (staff 49, six day rows): the table shows **$63.85 on every row**; the real product commission per day is **4.60, 1.70, 0.00, 3.30, 0.00, 1.00** (sum 63.85). The summary cards above the table are correct. Fix: group `$productSub` by `appointment_id, staff_id`, join it on `a.appointment_id = p.appointment_id AND p.staff_id = s.staff_id`, and use `SUM(p.product_commission)` per date.
2. **`SUM(DISTINCT ...)` on commission and tip (Reports > Staff tab, the barber's own Staff Report, dashboard Top Services).** It adds each *different amount* once, so every repeated amount (most services have a fixed price, so most commissions repeat) disappears. Measured for staff 49, October 2026, 150 invoices: real service commission **$1,336.28**, `SUM(DISTINCT)` gives **$284.13** (under-reported by about 79%). Same issue for tips and for `SUM(DISTINCT total_amt)` revenue. Fix: sum per appointment without `DISTINCT` (the join is already one row per appointment and staff, so a plain `SUM` is right); keep `COUNT(DISTINCT appointment_id)` for counts. This is Q1/Q36 with real numbers: please treat it as the top priority, the owner uses these figures to pay staff.

**Cleanup (🟡):**

3. **`users.commission` is never used.** The Staff form has a "Commission" field and 25 staff have a value (up to 55%), but every invoice takes its commission from the **service** (`tbl_service.commission`) and the **product** (`tbl_product.commission`). Changing the staff value changes nothing, which will mislead whoever sets it. Fix: remove the field, or really use it (and say which of the two wins).
4. **Commission is on the discounted price** (a 10% invoice discount lowers the stored commission: a $35 skin fade at 10% pays $3.15, not $3.50). That is consistent, but nobody has said it is intended; confirm it with the owner. The app copies it.

**Checked and correct (no change needed):** invoice total = lines - discount + tip (1150 of 1150 invoices; tax is included in the price, `total_tax` is informational); `appointment.total_tip` = sum of the line tips (1150/1150); stored product commission = product amount x product % (132/132); no commission on cancelled or non-invoiced appointments; no orphan service/product lines; no duplicate invoice numbers; no invoiced appointment without lines; no negative stock. Tip split still has 15 lines with more than 2 decimals (Q39).

**After you fix it:** the app's Earnings tab and Reports use the same API code, so we change the same queries (own API classes, no web code touched) and add tests with the numbers above.

## Q69 - Security and hygiene found in the web code (audit 2026-11-04)

**Fix first (🔴):**

1. **Public maintenance URLs, no login.** `routes/web.php` lines 60-90: `GET /cache-clear` (runs `cache:clear`, `route:clear`, `view:clear`, `config:cache`, `config:clear`), `GET /storage-link` and `GET /mail` are reachable by anyone (tested: `/rosen_barber/public/cache-clear` answers 200). `/mail` sends a real mail through the live SMTP account to a personal address and ends in `dd()`. Anyone can hit them in a loop (slow site, mail abuse). Fix: delete these three routes (run the commands from the terminal).
2. **`GET /admin/assign-role-super-admin`** (`routes/web.php` line 252, `AuthController@RoleAssignSuperAdmin`): left-over helper that gives user id 2 the role id 4. It sits inside the `checklogin` group, so **any logged-in user** can call it. Fix: delete the route and the method.
3. **No brute-force protection on the admin login** (`admin/post-login`, `AuthController@postLogin`): no throttle, no lockout, and it accepts the phone number as login too. Only the SEO login (`throttle:5,1`) and forgot-password are limited. Fix: `->middleware('throttle:5,1')` on the route, or a `RateLimiter` keyed by login + IP; log failed attempts.
4. **Booking tracking can be enumerated** (`track-booking/search`, `TrackingController@search`). The booking code is `BCB-YYYYMMDD-NNNN` (date + a 4-digit counter), so anyone can guess other people's codes and see the booking page (name, services, staff). There is no throttle or captcha. Fix: add a random part to the code (6+ characters), `throttle:10,1`, and show only what the person needs. (Also: the `BCB` prefix is another brand, see Q20.)
5. **Debug mode and secrets.** `.env` has `APP_DEBUG=true` and `APP_ENV=local`. With debug on, any error page shows code, queries and environment values. The live SMTP password is in the local `.env` and `backup/.env` (a copy of `.env` inside the project folder). Fix on the live server: `APP_ENV=production`, `APP_DEBUG=false`; delete `backup/.env`; rotate the SMTP password if the project folder was ever shared or zipped.

**Cleanup (🟡):**

6. **Weak password rule:** staff passwords only need 6 characters (`StaffController` lines 493, 567, 707). Fix: minimum 10, and refuse very common passwords (`Password::min(10)->uncompromised()`).
7. **Public booking forms have no throttle or captcha** (`submit-appointment-details`, `get-slot-by-staff`, `get-staff-service`): a script can fill the calendar with fake bookings. Fix: `throttle:20,1` plus a honeypot field or captcha on the submit.
8. **Sessions** use the `file` driver with a 120-minute lifetime and `SESSION_SECURE_COOKIE` / `SESSION_ENCRYPT` are not set. Fix on live (HTTPS): `SESSION_SECURE_COOKIE=true`, `SESSION_SAME_SITE=lax`.

**Checked and fine:** no raw SQL built from user input in the admin controllers; every `{!! !!}` in the views is wrapped in `e()`; image uploads validate type and size (2 MB); no `$guarded = []` models; CSRF has no exceptions; no duplicate customer phones, no double-booked staff, no customer ids pointing nowhere, all passwords are bcrypt.
