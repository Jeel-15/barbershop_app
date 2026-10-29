# Rosenthal Barbershop — Mobile API Master Plan (Admin + Staff app)

> **Status:** **Phases 0 and 1 are built and tested** (113 automated checks green). Done: `AUTH-1..8`, `BOOT-1`, `SYS-1`, `DASH-1..3`, `APPT-1..5`, `ME-1..2`. Everything else is still plan. See Sections 14 and 15 for exactly what exists and how it was verified.
> **Written:** 2026-10-23 · **Web project studied:** `J:\laragon\www\rosen_barber` (Laravel 9.52, PHP 8.3, MySQL `barber_shop_db`)
> **Audience:** the project owner, and any future developer or AI session who must build the API without re-reading the whole web project.
> **How this was made:** every admin/staff controller (≈8,300 lines), the models, the middleware, the invoice/calendar JavaScript, the route table (211 routes) and the live local database were read. Nothing in the web project was edited.

---

## 0. How to read this document

| Section | What it answers |
|---|---|
| 1 | The rules we agreed (what we may and may not touch) |
| 2 | Hard facts about the system (roles, permissions, status codes, data conventions) |
| 3 | Data model, including the traps in it |
| 4 | API design principles (envelope, auth, pagination, money, caching…) |
| 5 | **Every endpoint**, grouped by module, with the web source it mirrors |
| 6 | Money / commission / tip / tax specification (the part that must be exact) |
| 7 | The booking-slot engine (how availability is computed) |
| 8 | **Web quirks and risks register** (things in the web that are wrong or dangerous) |
| 9 | Performance plan |
| 10 | Security plan |
| 11 | Future-proofing and live-deploy plan |
| 12 | Build phases and test plan |
| 13 | **Decisions the owner must make** (with my recommendation for each) |
| 14 | **Phase 0 as built** (foundation, how it was verified, lessons) |
| 15 | **Phase 1 as built** (dashboard, appointments, profile, forgot password, 113 checks) |
| Appendix A | Web route → API coverage table (all 195 distinct web actions, generated, none missing) |

Status legend used below: ✅ built · 🟦 planned (phase shown) · ⚠️ needs an owner decision · 🚫 deliberately not in the app.

---

## 1. Ground rules (from the owner)

1. The app is for **Admin and Staff only**. No customer booking, no guest flow.
2. **Function and flow must match the web exactly.** UI/UX must be better than the web.
3. **No edits to existing web code.** Allowed: append to `routes/api.php`, and add new files under `app/Http/Controllers/Api/V1/`, `app/Http/Requests/Api/V1/`, `app/Services/Api/`.
4. Everything runs **locally** now (project + database). The web project is **live in production**, so whatever we add must be safe to copy to live later.
5. Reading the local database is allowed. Schema changes are **not** made without asking (two additive fixes were already applied locally: `tbl_appointment.invoice_created_by` and table `password_reset_otps`; the web code needs both).
6. Brand: **Rosenthal Barbershop, Edmonton AB**. Currency CAD (`$`), timezone `America/Edmonton`.

---

## 2. Ground truth about the system

### 2.1 Stack and URLs
| Item | Value |
|---|---|
| Framework | Laravel 9.52.20, PHP 8.3.1 (Laragon Apache) |
| Auth packages | `laravel/sanctum` 3 (installed, `personal_access_tokens` table exists), `spatie/laravel-permission` 6.21, `yajra/laravel-datatables-oracle` 10.11 |
| Web base (local) | `http://localhost/rosen_barber/public` |
| API base | `/api/v1` (prefix `api` is wired by `RouteServiceProvider`) |
| Default API rate limit | 60/min per user (`RateLimiter::for('api')`), login limited to 10/min |
| Timezone | `America/Edmonton` (`APP_TIMEZONE`). All "today / now" logic uses it |
| Tax | One default GST row: **5%, `include`** (price already contains tax) |
| Booking step | `tbl_setting.service_default_duration` (currently 10 min; code clamps 5–60) |
| Service fee | `tbl_setting.service_fee` = 1.50 — deducted **only** inside the commission formula, never shown on invoices |

### 2.2 Roles and permissions (42 permissions, 6 roles)
| Role (spatie) | # perms | Notes |
|---|---|---|
| Super-admin | 42 | everything |
| Manager | 41 | admin-like |
| POS Manager | 9 | invoices-focused |
| Accountant | 8 | `users.role = 'Accountant'` |
| Owner | 7 | no users currently |
| Staff | 6 | `Dashboard-Today_Appointments`, `Dashboard-Upcoming_Appointments`, `Appointment-View`, `Pos_invoice-Add`, `Calender-View`, `Report-View` |

All 42 permission names: `Dashboard-Today_Appointments, Dashboard-Upcoming_Appointments, Dashboard-Top_Services, Dashboard-Top_Selling_Product, Appointment-View, Customer-Add/Edit/Delete, Product-Add/Edit/Delete, Service-Add/Edit/Delete, Service_Category-Add/Edit/Delete, Slot-Update, General_Setting-Update, Payment_Setting-Update, Gst-Add/Edit/Delete, Staff-Add/Edit/Delete, Shop_Closures-Add/Edit/Delete, Pos_invoice-Add/Edit, Calender-View, Gallery-Add/Delete, Report-View, Setting-Payment_Method, Role-Add/Edit/Delete, Testimonial-Add/Edit/Delete`.
(`Dashboard-Top_Staff`, `Pos_invoice-Show_All` and `Gallery-Edit` are referenced by code but **do not exist** in the permissions table.)

> **Critical rule — "staff scoping" is decided by `users.role`, not by the spatie role.**
> `User::isStaffUser()` is `users.role === 'Staff'`. Every "show only my own data" filter and the `not.staff` middleware use it.
> Consequence: a user whose spatie role is *Manager* but whose `users.role` is `Staff` (this is how the 4 old Manager users were stored) is treated as staff: sees only their own appointments and is **blocked from Reports** even though Manager has `Report-View`.
> The API must reuse `isStaffUser()` unchanged so behaviour matches the web. (Decision D12.)

### 2.3 Appointment status codes (`tbl_appointment.status`)
| Code | Label | Set by |
|---|---|---|
| 0 | Pending | new booking (website, calendar) |
| 1 | Completed | invoice saved (POS) |
| 2 | Cancelled / "Reject" | `confirm_reject_action` with 2 |
| 3 | Confirmed | `confirm_reject_action` with 3 |
| 4 | Rescheduled | `submit_reschedule_appointment` |

**Action matrix the web shows per status** (the API will send this as a server-driven `actions` list so the app can never drift):

| Status | Allowed actions |
|---|---|
| 0 Pending | confirm, complete, cancel, reschedule, view |
| 1 Completed | view |
| 2 Cancelled | reschedule, view |
| 3 Confirmed | cancel, complete, view |
| 4 Rescheduled | confirm, complete, cancel, view |

`is_invoiced` (a **varchar**) is `'1'` only for appointments that have an invoice. `status = 1` and `is_invoiced = 1` always go together.

### 2.4 Things with special meaning
* **"First available"** is a *pseudo staff user* (id 19, `role=Staff`, `is_barber=0`, inactive). It is detected **by name** (`first available%`, case-insensitive) in ~15 places. Bookings made for it store `is_first_available=1` on the service line and get resolved to a real barber at booking time.
* **`tbl_breaks.break_type`**: `1` = working-hours block (what the staff "Working Hours" page edits); `2` = legacy seed hours **and** ad-hoc breaks from the calendar. The slot engine treats type-2 rows as *hours* when no type-1 rows exist. Shop-level breaks created by Shop Hours are saved as type 1 on the shop's day row.
* **Ad-hoc breaks have no date column in this project.** The day they apply to is `DATE(created_at)`. (The SaaS copy added `break_date`; this project did not.)
* **Soft deletes** exist on: users, services, service categories, products, payment methods, testimonials. **Not** on: customers, GST, shop closures, gallery, roles, permissions (those deletes are permanent).

---

## 3. Data model (what the API reads and writes)

| Table | Rows now | Purpose | Traps |
|---|---|---|---|
| `users` | 34 (10 live) | admins + staff + accountants | `role` is a free string (`Admin/Staff/Accountant`); `service_id` legacy CSV mirrors `tbl_staff_service`; `commission` per staff exists but the invoice formula uses **service/product** commission, not this |
| `customers` | 11 | customer records | **No unique phone**; no soft delete; `customer_status` varchar |
| `tbl_appointment` | 26 | booking **and** invoice header | `customer_id`, `is_invoiced`, `payment_method` are **varchar**; money is `double(8,2)`; `date` + `slot_start/slot_end` (time) |
| `tbl_appointment_service` | 38 | one row per service **unit** (qty = repeated rows) per staff | commission/tip/amount columns are **varchar**; `requested_staff_id`, `is_first_available` |
| `tbl_appointment_product` | 0 | product lines on an invoice | `amount` varchar; `product_commision` (sic) |
| `tbl_service`, `tbl_service_category`, `tbl_product` | 46 / 11 / 3 | catalog | products belong to a *service* category; `service.commission` is a **percent** |
| `tbl_gst` | 2 | tax rates | exactly one should have `default_status=1` |
| `tbl_payment_method` | 4 | Cash, … | invoices store the **name string**, not an id |
| `tbl_setting` | 1 | shop settings + contact | single row, `id = 1` is hard-coded in code |
| `tbl_slots` | 224 | weekly schedule: `staff_id = 0` is the **shop**; per-staff rows hold day-off flags | no unique key on (`staff_id`,`day_name`) |
| `tbl_breaks` | 446 | working-hour blocks / breaks | see 2.4 |
| `tbl_shop_closure` | 0 | closed dates (full day or time window) | `start_time/end_time` are varchar |
| `tbl_staff_service` | 70 | who can do which service | source of truth; `users.service_id` is the fallback |
| `tbl_testimonial`, `galleries`, `seo_pages` | 3 / 0 / 0 | website content | `galleries` has **no** `description` column (web update code writes one → error) |
| `roles`, `permissions`, `model_has_roles`, `role_has_permissions` | 6 / 42 / 47 / – | spatie | |
| `personal_access_tokens` | 0 | Sanctum | used by the app |
| `password_reset_otps` | 0 | OTP reset | added locally; **must exist on live** |

**Missing indexes (matter once data grows; optional, needs approval):**
```sql
ALTER TABLE tbl_appointment         ADD INDEX idx_appt_date_status (date, status), ADD INDEX idx_appt_invoiced_date (is_invoiced, date), ADD INDEX idx_appt_customer (customer_id(20));
ALTER TABLE tbl_appointment_service ADD INDEX idx_aps_appt (appointment_id), ADD INDEX idx_aps_staff_appt (staff_id, appointment_id), ADD INDEX idx_aps_service (service_id);
ALTER TABLE tbl_appointment_product ADD INDEX idx_app_appt (appointment_id), ADD INDEX idx_app_staff (staff_id);
ALTER TABLE tbl_slots               ADD INDEX idx_slots_staff_day (staff_id, day_name);
ALTER TABLE tbl_breaks              ADD INDEX idx_breaks_slot_type (slot_id, break_type), ADD INDEX idx_breaks_staff_type_created (staff_id, break_type, created_at);
ALTER TABLE customers               ADD INDEX idx_cust_phone (customer_phone);
ALTER TABLE users                   ADD INDEX idx_users_role_barber (role, is_barber, active_status);
```
At 26 appointments none of this is needed for speed; it is for the day there are 50,000. They are additive and safe, but they touch the live schema, so they are **recommendations only**.

---

## 4. API design principles

### 4.1 Conventions
| Topic | Rule |
|---|---|
| Versioning | Everything under `/api/v1`. v1 is **additive-only** (new fields/endpoints never remove or rename old ones). Breaking change ⇒ `/api/v2`. |
| Format | JSON only. Middleware forces `Accept: application/json` so Laravel never answers with an HTML redirect. |
| Envelope | **Built.** Success `{ "status": 1, "message": "OK", "data": {…}, "meta": {…}? }`, failure `{ "status": 0, "message": "first error", "errors": {"field": ["…"]}?, "request_id": "…" }`. `status` mirrors the web's JSON so developers recognise it. `data` is always an object (`{}` when empty). |
| HTTP codes | 200/201 ok · 401 not logged in · 403 forbidden (message names the missing permission) · 404 not found · 409 conflict (slot taken, double action) · 422 validation · 429 throttled · 500 generic (never leaks SQL; `APP_DEBUG=false` on live) |
| IDs / dates / times | ints; dates `YYYY-MM-DD`; times `HH:MM` 24h; every time also has a ready `*_label` (`"10:30 AM"`) so the app never formats times itself. Server time zone is the **shop's**, not the phone's. |
| Money | **Decimal strings with 2 dp** (`"25.00"`), never floats. New server arithmetic is done in integer cents. A `currency` object (`code`, `symbol`) comes from `/bootstrap`. |
| Images | Absolute URLs built with `asset('storage/…')` so the host automatically matches how the phone reached the server (LAN IP locally, domain live). Every image field is `*_url`, with a placeholder URL when empty. |
| Lists | `page` (default 1), `per_page` (default 20, max 50), `q` (search), explicit filters. `meta`: `{page, per_page, total, has_more}`. Default sort = the web's default sort. |
| Booleans in forms | The web uses checkbox presence (`active_status` absent ⇒ 0). The API takes **explicit booleans** and only changes fields that are sent (partial update), so a missing key can never silently switch something off. |
| File upload | `multipart/form-data`; jpg/jpeg/png/gif (+webp for testimonials), max 2 MB (same as web). Updates that carry a file use `POST … ` with `_method=PUT` (PHP cannot read multipart on PUT). |
| Server-driven UI | Rows carry `actions: ["confirm","cancel",…]` and the app renders buttons from it. Business rules live on the server only. |

### 4.2 Authentication
* Sanctum **Bearer token**, one per device (`device_name`), **30-day expiry**, revoked on logout, on password change, and when the user is deactivated or soft-deleted (checked on every request by a small middleware).
* Login is **email + password** (the web's phone-number branch queries a `contact_no` column that does not exist, so it is broken in the web).
* `GET /auth/me` returns the user, their `permissions`, and a `modules` map that mirrors each web route's middleware exactly, plus `home` (the module the web would open first). The app builds its navigation from `modules`, never from role names.

### 4.3 Authorization (two layers, both mandatory)
1. **Permission layer** — same permission(s) as the web route's `can:/canany:` middleware (table in Appendix A).
2. **Object layer** — if `isStaffUser()`: only rows that belong to that staff member (`tbl_appointment_service.staff_id = me`, own invoices when lacking `Pos_invoice-Show_All`, own working hours, own earnings). The web does this inconsistently (see Quirks Q3, Q8, Q9); the API does it everywhere.

### 4.4 Reuse vs re-implement (how we guarantee "same as web")
| Web piece | Strategy | Why |
|---|---|---|
| `WebsiteController::get_slot_by_staff` (slot engine), `get_appointment_details` | **Delegate**: the API controller calls the existing public method with a built `Request` and re-wraps the JSON | identical availability results; zero duplicated logic; stays correct if the web engine is fixed later |
| DataTables endpoints (dashboard, lists, reports) | **Re-implement** as clean queries returning typed JSON, no HTML, real pagination | the web returns HTML button strings and `"$ 12.00"` text, unusable for a native app |
| Money writes (POS) | **Re-implement** as a pure, unit-tested calculator (Section 6) | must be exact and auditable |
| **Parity tests** | For every re-implemented list/report, a script calls the web endpoint and the API endpoint with the same filters and compares totals | proves "same numbers as web" instead of assuming it |

### 4.5 Caching and speed
* `GET /bootstrap` returns everything the app needs at launch in **one call** (user, modules, settings, currency, default GST, payment methods, statuses, shop hours, server time, app-version flags).
* Catalog lists (services, staff, products, GST, payment methods) send an **ETag** built from `COUNT(*)` + `MAX(updated_at)`. The app sends `If-None-Match`; unchanged data costs one tiny query and a `304`.
* No per-request `Schema::hasColumn()` (the web does this inside many calls; each one is an `information_schema` query). The API assumes the columns exist and a **health check** (`SYS-1`) verifies them.

### 4.6 Observability
Every request gets an `X-Request-Id`, logged to `storage/logs/api-YYYY-MM-DD.log` with user id, route, status, ms. No passwords, tokens, or customer phone/email in logs.

---

## 5. Endpoint catalogue

> Permission column uses the web's own permission names. "Scope" = object-level rule. "Web source" = the controller method the behaviour is copied from.

### 5.1 AUTH — sign-in and account
| ID | Endpoint | Permission / Scope | Web source | Phase | Notes |
|---|---|---|---|---|---|
| AUTH-1 | `POST /auth/login` | public, throttle 10/min | `AuthController@postLogin` | ✅ | email+password, refuses `active_status≠1` |
| AUTH-2 | `GET /auth/me` | token | – | ✅ | user + permissions + modules + home |
| AUTH-3 | `POST /auth/logout` | token | `AuthController@logout` | ✅ | revokes current token |
| AUTH-4 | `POST /auth/logout-all` | token | – | ✅ P0 | revoke every token of the user |
| AUTH-5 | `POST /auth/forgot-password` | public, 5/min per email+ip | `ForgotPasswordController@sendOtp` | ✅ P1 | stateless (the email is sent with every step); like the web, an unknown/inactive email is reported as "could not find an active account"; 6-digit OTP hashed in `password_reset_otps`, emailed, never returned |
| AUTH-6 | `POST /auth/verify-otp` | public, throttle 10/min | `@verifyOtp` | ✅ P1 | OTP valid 10 min, max 5 wrong tries (from `config/password_reset_otp.php`); returns a short-lived `reset_token` (15 min) |
| AUTH-7 | `POST /auth/resend-otp` | public, throttle 3 per 10 min | `@resendOtp` | ✅ P1 | |
| AUTH-8 | `POST /auth/reset-password` | `reset_token` | `@resetPassword` | ✅ P1 | min length 6; revokes all tokens |
| AUTH-9 | `PUT /me/password` | token | **none in web** | 🚫 not built | The web has no self-service password change, and the owner decided the web is the contract. Build only if the owner asks |

> Local-test warning: OTP emails use the project's SMTP settings (`MAIL_HOST=rosenthalbarbershop.ca`). Before testing AUTH-5 locally set `MAIL_MAILER=log` in the **local** `.env`, otherwise a real email may go out.

### 5.2 BOOT — launch data
| ID | Endpoint | Permission | Notes | Phase |
|---|---|---|---|---|
| BOOT-1 | `GET /bootstrap` | token | **Built.** `user` (+`modules`, `permissions`, `home`), `shop{name,logo_url,address,phone,email,whatsapp,website}`, `currency{code,symbol}`, `timezone`, `server_time`, `tax{id,name,rate,type}` (null ⇒ no tax), `payment_methods[]`, `statuses[]`, `appointment_actions{status→actions}`, `slot_step_minutes`, `shop_hours[7]`, `limits`, `app{api_version,build,min_app_version,latest_app_version,feature_flags}` | ✅ P0 |
| SYS-1 | `GET /health` | public | **Built.** `{db, schema_ok, version, build, time}`; HTTP 503 when the DB is down or a required table/column is missing (`config/api_v1.php → required_schema`); the list of what is missing is shown only when `APP_ENV=local`; cached 60 s | ✅ P0 |

### 5.3 DASH — dashboard
Web: `DashboardController`. Each widget is permission-gated in the web view with `@can`; the web **API endpoints themselves are not gated** (Q2), the app endpoints are.

| ID | Endpoint | Permission | Scope | Web source | Phase |
|---|---|---|---|---|---|
| DASH-1 | `GET /dashboard/summary` | any dashboard perm | staff ⇒ own | `index` (cards) | ✅ P1 |
| DASH-2 | `GET /dashboard/today` | `Dashboard-Today_Appointments` | staff ⇒ own lines | `GetTodayGetTableData` | ✅ P1 |
| DASH-3 | `GET /dashboard/upcoming` | `Dashboard-Upcoming_Appointments` | staff ⇒ own lines | `GetUpcomingGetTableData` | ✅ P1 |
| DASH-4 | `GET /dashboard/top-services` | `Dashboard-Top_Services` | all | `TopServicesGetTableData` | ✅ P3 |
| DASH-5 | `GET /dashboard/staff-performance` | `Dashboard-Top_Services` (no dedicated perm exists) | all | `getStaffPerformance` | ✅ P3 |
| DASH-6 | `GET /dashboard/top-products` | `Dashboard-Top_Selling_Product` | all | `index` ($products) | ✅ P3 |

**DASH-1 cards (exact web logic):**
* `upcoming` = appointments with `date > today` and `is_invoiced IS NULL`.
* `completed` (status 1), `cancelled` (2), `confirmed` (3), `rescheduled` (4) — counts of **distinct** appointments; staff ⇒ only appointments having a service line for that staff.
* `customers` = total customer rows.
* **Admin (`users.role = 'Admin'`)**: `revenue = SUM(total_amt − total_tax − total_tip)` over **all** appointments (any status!), `tips = SUM(total_tip)`.
* **Everyone else**: `tips = SUM(service_tip)` of own lines, `commission = SUM(service_commission) + SUM(product_commision)` of own lines, `revenue(earnings) = tips + commission`.
* Note the web's revenue figure includes non-completed appointments; see Q1. The API returns the web's number **and** a `revenue_completed_only` field so the owner can compare (D1).

**DASH-2 / DASH-3 filters (exact):** today = `a.date = today`; upcoming = `a.date > today`; both only where `is_invoiced = 0 OR NULL`; staff ⇒ `s.staff_id = me`. Row fields: id, date, start/end (+labels), status, customer name/phone, staff names, "staff: service" lines (`First available` shown when `is_first_available=1`), `staff_ids`, `service_ids`, `actions`.

### 5.4 APPT — appointments
Web: `AppointmentController` (+ public `WebsiteController` slot engine). Permission for the whole module: `Appointment-View` (web gates the list/detail routes; the confirm/cancel/reschedule routes have **no** gate, the API adds `Appointment-View` + object scope).

| ID | Endpoint | Scope | Web source | Phase | Notes |
|---|---|---|---|---|---|
| APPT-1 | `GET /appointments` | staff ⇒ own lines, **and excluding** `is_first_available=1` lines (that is what the web list does) | `getTableData` | ✅ P1 | filters `start_date,end_date,status,staff_id,day_type(Morning 06:00–11:59 / Afternoon 12:00–16:59 / Evening 17:00–22:00)`, `q` searches id/name/phone/staff name; sort date desc, start desc |
| APPT-2 | `GET /appointments/counts` | same scope | `countAppointmentsByStatus` | ✅ P1 | all / confirmed / completed / cancelled / rescheduled (+ pending) |
| APPT-3 | `GET /appointments/{id}` | own if staff | `get_appointment_details`, `get_customer_appointment_details`, `groupAppointmentDetailRows` | ✅ P1 | returns **grouped** services (qty, line_total, duration_total) and per-staff groups; staff see **only their own service lines**; never 404s just because `customer_id` is missing (the web's inner join does) |
| APPT-4 | `POST /appointments/{id}/confirm` | own if staff | `confirm_reject_action` status 3 | ✅ P1 | allowed from 0, 4. 409 if already in a state that forbids it |
| APPT-5 | `POST /appointments/{id}/cancel` | own if staff | `confirm_reject_action` status 2 | ✅ P1 | allowed from 0, 3, 4. **Refuses completed/invoiced** (the web would silently allow it) |
| APPT-6 | `POST /appointments/{id}/reschedule` | own if staff | `submit_reschedule_appointment` | ✅ P2 | body `date, slot_start, slot_end`; **validates the slot is free** (web does not, Q4); sets status 4 |
| APPT-7 | `GET /appointments/slots` | staff ⇒ own | delegates to `WebsiteController::get_slot_by_staff` | ✅ P2 | query `date, staff_ids[], service_ids[]`; returns slot groups per barber incl. "First available" |
| APPT-8 | `POST /appointments` | `Appointment-View` + `Calender-View` | `calenderAppointMentStore` (create) | ✅ P2 | walk-in/phone booking: `start (datetime), total_duration, staff_id, service_id[], name, phone, email, notes`; finds customer by phone else creates; **requires phone** and ≥1 service; 409 on overlap with the same staff |
| APPT-9 | `PUT /appointments/{id}` | same | `calenderAppointMentStore` (edit branch) | ✅ P2 | resets status to 0, replaces only that staff lane's service rows (exact web behaviour) |
| APPT-10 | `GET /appointments/staff-by-service?service_ids[]=` | token | `get_staff_by_service`, `StaffController@getStaffByService` | ✅ P2 | staff offering ≥1 of the services; includes "First available" |
| APPT-11 | `POST /appointments/{id}/complete` | `Pos_invoice-Add` | **web is broken here** ⚠️ D2 | ✅ P3 (flag off) | turns a pending/confirmed appointment into an invoice (see Q5) |

### 5.5 CAL — calendar
Web: `AppointmentController@calenderIndex/fetch/fetchStaffAvailability/breakFormSubmit`. Permission `Calender-View`. Staff are locked to their own lane; admins see all lanes. The web returns **every appointment ever** with no date range (Q10); the API requires a range.

| ID | Endpoint | Notes | Phase |
|---|---|---|---|
| CAL-1 | `GET /calendar/events?from=&to=&staff_id=` | events are **lanes**: one per (appointment, staff) with merged service names and summed duration, plus a "First available" lane, plus break events. Hides cancelled (2) and invoiced appointments exactly like the web | ✅ P2 |
| CAL-2 | `GET /calendar/availability?date=&staff_id=` | shop open/close (fallback 09:00–21:00), day-off flag, per-staff working hours (type-1 blocks, fallback to open/close) and that day's breaks | ✅ P2 |
| CAL-3 | `POST /calendar/breaks` | body `staff_id, restoftheday(0/1), hour, minute, break_type(2)`; creates an ad-hoc break from *now* (or the rest of the day). Validates the staff exists | ✅ P2 |
| CAL-4 | `DELETE /calendar/breaks/{id}` | **new** (web cannot remove a break); only creator/admin | ⚠️ optional, P2 |

### 5.6 POS — invoices and point of sale
Web: `InvoiceController`. Permissions: list `Pos_invoice-Add|Edit|Show_All`; create/edit `Pos_invoice-Add|Edit`. Staff without `Pos_invoice-Show_All` see **only invoices they created** (`invoice_created_by`).

| ID | Endpoint | Web source | Phase | Notes |
|---|---|---|---|---|
| POS-1 | `GET /pos/catalog` | `create`/`edit` data | ✅ P3 | categories→services (price, duration, tip_status, commission **hidden from staff**), products (price, stock), staff (barbers + role Staff), default GST, payment methods |
| POS-2 | `GET /pos/customer-lookup?phone=` | `getCustomerDetails` | ✅ P3 | customer + visit count + last services; **spend totals hidden from staff** |
| POS-8 | `POST /invoices/preview` | **new** | ✅ P3 | server-side totals for a draft cart (Section 6). The app uses it for the live total, so the app and server can never disagree |
| POS-3 | `POST /invoices` | `store` | ✅ P3 | creates a **new** completed appointment+invoice (date/time = now). Atomic. Mail sent **after commit** and queued (the web sends inside the transaction: if mail fails the invoice is rolled back, Q21). Idempotency key supported |
| POS-4 | `GET /invoices` | `index` | ✅ P3 | paginated (web loads everything), newest first, scope rule above |
| POS-5 | `GET /invoices/{id}` | `edit` data | ✅ P3 | full breakdown: lines, staff, discount %, tax, tip, total, payment method, invoice number |
| POS-6 | `PUT /invoices/{id}` | `update` | ✅ P3 | replaces lines (web deletes and re-inserts), keeps invoice number, **does not change `invoice_created_by`**, sets date/time = now (web behaviour) |
| POS-7 | `POST /invoices/{id}/email` | `SendInvoiceMail` | ✅ P3 | refuses the placeholder address `info@bluecrownbarbers.com`; queued |

### 5.7 CUST — customers
Web: `CustomerController`. Permission `Customer-Add|Edit|Delete` (module visible with any of them).

| ID | Endpoint | Notes | Phase |
|---|---|---|---|
| CUST-1 | `GET /customers?q=&status=` | paginated; `q` matches name/phone/email | ✅ P3 |
| CUST-2 | `GET /customers/{id}` | profile: visits (invoiced), total spend, last services (web `customer_profile`) | ✅ P3 |
| CUST-3 | `GET /customers/{id}/appointments` | with the same filters as APPT-1 (web `PendingAppointmentgetTableData`; its `status` filter is broken, `where('a.status',)` has no value, the API fixes it) | ✅ P3 |
| CUST-4 | `POST /customers` | `full_name, phone_number (req), email?, status?` | ✅ P3 |
| CUST-5 | `PUT /customers/{id}` | | ✅ P3 |
| CUST-6 | `DELETE /customers/{id}` | **permanent** in the web; the API refuses when the customer has appointments (409) ⚠️ D17 | ✅ P3 |

### 5.8 STAFF — staff administration
Web: `StaffController`, `StaffServiceController`. Permission `Staff-Add|Edit|Delete`. A staff member may view their own profile (web rule: `id == me` or `Staff-Edit|Add`).

| ID | Endpoint | Web source | Notes | Phase |
|---|---|---|---|---|
| STAFF-1 | `GET /staff?q=&barber=` | `GetTableData` | lists users with `role IN (Staff, Accountant)`: name, email, phone, commission, is_barber, status, photo, role ids, service names | ✅ P4 |
| STAFF-2 | `GET /staff/form-options` | `index` | assignable roles = all roles **except ids 1 (Super-admin) and 4 (POS Manager)** (web rule), services list | ✅ P4 |
| STAFF-3 | `GET /staff/{id}` | `staff_profile` | earnings summary for completed (status 1) appointments in a date range: revenue (`total_amt−tax−tip`), appointments, visits, tips, service commission, product commission, total earning | ✅ P4 |
| STAFF-4 | `GET /staff/{id}/earnings` | `DailyEarningGetTableData` | per day: service commission, tips, product commission, total | ✅ P4 |
| STAFF-5 | `GET /staff/{id}/services` | `AssignServicesGetTableData` | per service: count, commission, tips | ✅ P4 |
| STAFF-6 | `GET /staff/{id}/appointments` | `AppointmentGetTableData` | | ✅ P4 |
| STAFF-7 | `POST /staff` | `store` | rules: name req, email req+unique (case-insensitive), password ≥6, `service_id[]` req when barber, commission ≥0, status req, role_id req, photo ≤2MB. Side effects (exact): assigns role, syncs `tbl_staff_service`, and for panel role Staff **creates 7 `tbl_slots` rows and 14 `tbl_breaks` rows** (09:00–13:00 and 14:00–18:00, type 2) | ✅ P4 |
| STAFF-8 | `PUT /staff/{id}` | `update` | same rules, password optional, `syncRoles`, replaces photo | ✅ P4 |
| STAFF-9 | `DELETE /staff/{id}` | `destroy` | soft delete + remove photo; API also **revokes that user's tokens** and refuses to delete yourself | ✅ P4 |
| STAFF-10 | `PUT /staff/{id}/password` | `changePassword` | min 6, confirmation; **the web has no permission check here** (Q6), API requires `Staff-Edit` (or self via AUTH-9) | ✅ P4 |
| STAFF-11 | `GET /staff/{id}/assigned-services` | `getAssignedServices` | ids, with the legacy-CSV fallback | ✅ P4 |
| STAFF-12 | `PUT /staff/{id}/assigned-services` | `assignServices` | `StaffService::syncForStaff` (keeps the legacy CSV in sync) | ✅ P4 |

### 5.9 ME — staff self-service (the only things a plain Staff user manages)
| ID | Endpoint | Web source | Notes | Phase |
|---|---|---|---|---|
| ME-1 | `GET /me/profile` | `ProfileController@index` | profile + assigned service names + own stats | ✅ P1 |
| ME-2 | `POST /me/profile` (`_method=PUT`) | `ProfileController@update` | name, email (unique), phone, photo | ✅ P1 |
| ME-3 | `GET /me/report/summary?start_date=&end_date=` | `StaffreportController@index` + summary | needs `Report-View`; includes `service_fee` | ✅ P3 |
| ME-4 | `GET /me/report/earnings` | `DailyEarningGetTableData` | per day | ✅ P3 |
| ME-5 | `GET /me/report/services` | `AssignServicesGetTableData` | | ✅ P3 |
| ME-6 | `GET /me/report/appointments` | `getAppointmentsTableData` | | ✅ P3 |
| ME-7 | `GET /me/working-hours` | `WorkinghoursController@index` | days → blocks (type 1) | ✅ P2 |
| ME-8 | `POST /me/working-hours` | `store` | `day_id, start_time, end_time(after start)`; rejects overlaps; turns the day **on** | ✅ P2 |
| ME-9 | `PUT /me/working-hours/{blockId}` | `update` | **must belong to me** (web does not check, Q8) | ✅ P2 |
| ME-10 | `DELETE /me/working-hours/{blockId}` | `destroy` | last block removed ⇒ day becomes **off** | ✅ P2 |
| ME-11 | `PUT /me/working-hours/days/{slotId}/day-off` | `updateFullDayOffStaff` | **must belong to me** | ✅ P2 |

### 5.10 RPT — reports (admin side)
Web: `ReportController`; permission `Report-View` **and** `not.staff` (so staff cannot open them). Every report returns `rows` (paginated) and `summary`. Parity tests are mandatory (Q1, Q2 describe numbers that look wrong in the web).

| ID | Endpoint | Web source | Filters | Phase |
|---|---|---|---|---|
| RPT-1 | `GET /reports/appointments` | `getAppointmentsTableData` | `start_date,end_date,staff_id,q` | ✅ P5 |
| RPT-2 | `GET /reports/payments` | `getPaymentMethodsTableData` | dates | ✅ P5 |
| RPT-3 | `GET /reports/staff-earnings` | `GetStaffEarnGetTableData` | dates, staff | ✅ P5 |
| RPT-4 | `GET /reports/customer-invoices` | `ReportCustomerInvoices` | dates, staff | ✅ P5 |
| RPT-5 | `GET /reports/product-sales` | `ProductSellReport` | dates, staff | ✅ P5 |
| RPT-6 | `GET /reports/top-products` | `TopSellingProductReport` | dates, staff | ✅ P5 |

### 5.11 CAT — catalog administration
| ID | Endpoints | Permission | Web source | Key rules | Phase |
|---|---|---|---|---|---|
| CAT-1 | `GET/POST/PUT/DELETE /services` | `Service-Add|Edit|Delete` | `ServiceController` | create: category exists, name ≤255, price ≥0, duration int ≥1, **image required**, commission 0–100 nullable, description; `active_status`/`eligible_for_tip` explicit booleans; delete = soft + removes image | ✅ P4 |
| CAT-1b | `PATCH /services/{id}/home-section` | `Service-Edit` | `updateHomeSection` | value `signature_grooming` or null (controls the public website) | ✅ P4 |
| CAT-2 | `GET/POST/PUT/DELETE /service-categories` | `Service_Category-*` | `ServicecategoryController` | name req; optional image; soft delete (services stay but vanish from the website) | ✅ P4 |
| CAT-3 | `GET/POST/PUT/DELETE /products` | `Product-*` | `ProductController` | name, category (a **service** category), price ≥0, stock int ≥0, commission ≥0, status bool, **image required**; soft delete + image removed | ✅ P4 |
| CAT-4 | `GET/POST/PUT/DELETE /gst` + `POST /gst/{id}/default` | `Gst-*` | `GstController` | name, rate ≥0, `tax_type` in include/exclude; making one default clears the others; **deleting or un-defaulting the default leaves the shop with no tax** (Q16) | ✅ P4 |
| CAT-5 | `GET/POST/PUT/DELETE /payment-methods` | `Setting-Payment_Method` | `PaymentmethodController` | name unique; soft delete (old invoices keep the text) | ✅ P4 |

### 5.12 SHOP — shop configuration
| ID | Endpoint | Permission | Web source | Notes | Phase |
|---|---|---|---|---|---|
| SHOP-1 | `GET /settings` | `Setting-Payment_Method` | `SettingController@index` | general + contact | ✅ P4 |
| SHOP-1a | `PUT /settings/general` | same | `update` (section general) | `service_reminder_day` int ≥1, `service_default_duration` int ≥1 (engine clamps 5–60), `service_fee` ≥0, `invoice_mail_send_status` bool | ✅ P4 |
| SHOP-1b | `PUT /settings/contact` | same | `updateContactDetails` | address, phone, email required; whatsapp digits only; URLs nullable | ✅ P4 |
| SHOP-2 | `GET/PUT /shop-hours` | `Slot-Update` | `SlotController` | 7 days × {is_day_off, open, close, breaks[]}; API addresses rows **by `staff_id = 0`** (web finds by day name only, Q18) | ✅ P4 |
| SHOP-3 | `GET/POST/PUT/DELETE /shop-closures` | `Shop_Closures-*` | `ShopcloseController` | full-day or partial window; partial needs start<end (the web auto-fixes `00:55`→`12:55`; API keeps that rule); date required | ✅ P4 |

### 5.13 CONT — website content
| ID | Endpoints | Permission | Web source | Phase |
|---|---|---|---|---|
| CONT-1 | `GET/POST/PUT/DELETE /testimonials` | `Testimonial-*` | `TestimonialController` (name, role, review ≤2000, rating 1–5, sort, status, optional image) | ✅ P5 |
| CONT-2 | `GET/POST/DELETE /gallery` (+ replace image) | `Gallery-Add|Delete` | `GalleryController` (web `update` writes a non-existent `description` column → error, Q14) | ✅ P5 |

### 5.14 ROLE — roles and permissions
| ID | Endpoint | Permission | Notes | Phase |
|---|---|---|---|---|
| ROLE-1 | `GET /roles` | `Role-Add|Edit` | roles + their permission ids + the permission catalog grouped by prefix | ✅ P5 |
| ROLE-2 | `POST/PUT/DELETE /roles` | `Role-Add/Edit/Delete` | name unique; the API **refuses to delete or rename Super-admin and Staff**, and refuses to delete a role that still has users (the web allows both) | ✅ P5 |
| – | permissions CRUD | – | 🚫 **not exposed**: in the web any logged-in user can add/edit/delete permissions (Q7); a mobile admin does not need it | – |

### 5.15 Deliberately out of scope 🚫
Public website pages, customer-facing booking (`/book`, `/submit-appointment-details`, `/track-booking*`), SEO admin (`/seo/admin/*`), `/cache-clear`, `/storage-link`, `/mail` test routes, `assign-role-super-admin`, backups. (The slot engine is reused internally through APPT-7 but the public routes are not exposed.)

### 5.16 Future (needs new storage → explicit approval)
| ID | Idea | Needs |
|---|---|---|
| NOTIF-1 | Push notification when a customer books on the website (huge value for barbers) | a `devices` table + FCM key + a scheduler job that watches new appointments (no web code change, but live cron + schema) |
| NOTIF-2 | Appointment reminders to barbers (15 min before) | same |
| SYNC-1 | `GET /sync?since=` incremental sync for offline mode | `updated_at` is present on most tables, no schema change for read-only sync |

---

## 6. Money specification (exactness matters)

Extracted from `create-invoice.blade.php` / `edit.blade.php` JavaScript (identical in both) and `InvoiceController@store/update`.

**Inputs:** list of lines `{flag: "S"|"P", id, staff_id, price}` (one line per unit; qty = repeated lines), `service_discount_pct`, `product_discount_pct`, `tip`, `payment_method`, customer.
*The UI discount type is hidden and is always **percentage**; the server commission code also treats the value as a percent.*

```
serviceTotal   = Σ price(S)           productTotal = Σ price(P)
serviceDisc    = serviceTotal * service_discount_pct / 100
productDisc    = productTotal * product_discount_pct / 100
discountedTotal= (serviceTotal - serviceDisc) + (productTotal - productDisc)
GST (default row, rate R):
   exclude:  tax = discountedTotal * R / 100          final = discountedTotal + tax + tip
   include:  tax = discountedTotal * R / (100 + R)    final = discountedTotal + tip     ← current (5% include)
store on appointment:
   total_amt = final   total_discount = round(serviceDisc,2)+round(productDisc,2)
   total_tax = tax     total_tip = tip   discount_type = 1 (constant)
   service_discount / product_discount = the two percents
```

**Tip distribution (per service unit):** eligible = services with `tip_status = 1`.
`if eligible > 0 → tip / eligible to each eligible unit; else → tip / (number of service units) to every service unit`. Products never get tips. *(Web stores unrounded floats such as 1.6666666667. The API distributes in cents with the remainder given to the first lines, so the per-line values always add up to exactly the tip.)*

**Service commission (per service unit):**
```
base  = price                      if service_discount_pct == 0
base  = price - price*pct/100      if service_discount_pct > 0
commission = max(0, base - service_fee) * service.commission / 100     # service_fee from tbl_setting
stored with 2 decimals; service.commission NULL/0 ⇒ 0
```
**Product commission:** `(price − price*product_discount_pct/100) * product.commission / 100` (no service fee). `qty` stored as 1 per line.

**Invoice number:** `INV-YYYYMMDD-NNNN` random 4 digits, regenerated until unique (the API keeps the format but uses a loop with a cap and a unique check inside the transaction).
**Customer on invoice:** match by phone; else create; if name+phone+email all empty ⇒ shared placeholder customer `Guest Customer / (555) 123-4567 / info@bluecrownbarbers.com`. *Note the placeholder email is another brand ("Blue Crown"); the API keeps the placeholder for parity but never emails it.*
**Stock:** the web **never decrements product stock** (Q17). Parity: the API does not either; flagged for a decision (D11).

**Server-side rules the API adds (web trusts the browser, Q9):** the server **recomputes every number** from catalog prices and the percents; client-sent totals are ignored (the app shows totals from POS-8). Line prices come from the catalog; editing an existing invoice keeps the stored price for unchanged service/product lines so history is not rewritten. Reject negative values, discounts > 100, tip < 0, unknown ids, inactive services/products, a staff id that is not an active staff user.

**Golden test cases** (to be encoded as unit tests before POS-3 is written): single $30 service no discount; two units same service + tip $5 (eligible vs non-eligible); 10% service discount with fee 1.50; mixed service+product with both discounts; GST include vs exclude; tip with zero eligible services; rounding at x.xx5.

---

## 7. Slot engine (availability) — what it does

Source: `WebsiteController` (1,977 lines; same engine the web booking page, the reschedule dialog and APPT-7 use).

1. **Shop day**: row `tbl_slots staff_id=0 & day_name`. Missing ⇒ "Shop hours not configured". `is_day_off=1` ⇒ "Shop is Closed". A **full-day closure** on that date (`tbl_shop_closure.closure_status=1`) ⇒ closed.
2. **Staff working blocks**: type-1 `tbl_breaks` of the staff's day row; if none, type-2 rows are used as hours (legacy); if none, the staff row's open/close; if none, the shop hours. Every block is clipped to shop open/close. Staff `is_day_off=1` ⇒ no slots.
3. **Blocked windows**: partial shop closures (`closure_status=0`) · ad-hoc breaks (`slot_id=0`, same `created_at` date) · existing bookings of that staff with `a.status IN (0,1,3,4)`.
4. **Duration** = sum of selected service durations (default 30 if unknown); **step** = `service_default_duration` clamped 5–60; **today** only starts ≥ now + 10 min.
5. **"First available"** is resolved to a real barber who offers *all* those services; slots are generated per staff group and merged.
6. Returns groups: `{key, staff_id, staff_name, flexible, duration, services[], slots[{start,end}]}` plus a flat `slots` list.

Known limits (kept for parity): the reschedule dialog's own current slot still counts as busy (Q4); ad-hoc breaks of **any past date** are matched only by `created_at` date.

---

## 8. Web quirks and risks register

> The web developer's to-do list built from this register is **`docs/WEB_DEV_FIXES.md`** (grouped by priority, with what we change after each fix).

Severity: 🔴 money/security · 🟠 wrong data · 🟡 annoying. "API" = what the new API does about it. "Decision" refers to Section 13.

| # | Sev | Where | What is wrong | API handling | Decision |
|---|---|---|---|---|---|
| Q1 | 🔴 | Dashboard top-services & staff-performance; Report staff-earnings summary; staff-report services | `SUM(DISTINCT total_amt)` / `SUM(DISTINCT commission)`: two appointments with the same amount count **once**; also counts cancelled/pending appointments | return the **web number** (parity) plus a `strict` figure computed correctly (per appointment, completed only) so the owner can compare | D1 |
| Q2 | 🟠 | Report staff-earnings | filter `end_date` is **missing** in the main query (start_date is written twice); summary has it | API applies both dates | D1 |
| Q3 | 🔴 | `confirm_reject_action` | no login-scope, no ownership, accepts **any** integer status (could set a completed invoice to 7) | whitelist 3 and 2 only; transition matrix; ownership for staff | – |
| Q4 | 🟠 | `submit_reschedule_appointment` | no slot validation, no staff ownership | validates against the slot engine; ownership | – |
| Q5 | 🔴 | Dashboard/Appointments "Complete" button | goes to `invoice/edit/{id}` which only opens **already-invoiced** appointments ⇒ **404 for every pending/confirmed appointment** (verified on appointment #26). Today the only way to create an invoice is the stand-alone POS, so booked appointments never reach "Completed" (9 of 26 rows sit at status 0) | APPT-11 `complete` creates the invoice *from* the appointment (the SaaS copy does exactly this) | **D2** |
| Q6 | 🔴 | `staff.change-password` | any logged-in user can change **any** user's password by id | needs `Staff-Edit`; self-change via AUTH-9 with current password | D5 |
| Q7 | 🔴 | `permission` resource | any logged-in user can create/edit/delete permissions | not exposed | D6 |
| Q8 | 🔴 | Working hours update/destroy/day-off | not scoped to the logged-in staff (edit anyone's hours by id) | owner check | – |
| Q9 | 🔴 | POS store/update | totals, prices, discount values come from the browser and are saved as-is | server recompute (Section 6) | D3 |
| Q10 | 🟠 | Calendar `fetch` | returns every appointment ever and every ad-hoc break, no date range; breaks placed by `created_at` | mandatory `from/to`; same break rule | – |
| Q11 | 🟡 | many joins | `tbl_appointment.customer_id` is **varchar** joined to a bigint ⇒ no index use; repeated `Schema::hasColumn()` calls (each is an `information_schema` query) inside list/detail endpoints | cast/join carefully, schema checked once at startup | – |
| Q12 | 🟠 | customers | duplicate phones allowed; booking picks the first match; POS can create a duplicate | match on **digits-only** phone, return the oldest; do not create duplicates | D16 |
| Q13 | 🟡 | `getStaffByService` | 500 when `service_ids` is missing | validated input | – |
| Q14 | 🟠 | Gallery update | writes `description`, column does not exist ⇒ SQL error | only image replace is offered | – |
| Q15 | 🟠 | Service/Product update | checkbox semantics: a missing `active_status` silently sets status 0 | explicit booleans, partial update | – |
| Q16 | 🔴 | GST | un-defaulting or deleting the default GST leaves no default ⇒ invoices get **0 tax** | API refuses (409) unless another default is set in the same request | D13 |
| Q17 | 🟠 | POS | product stock never decreases | parity (no change) until the owner decides | D11 |
| Q18 | 🟠 | Shop hours (`SlotController`) | rows looked up by **day name only**; a staff row could be overwritten if it sorted first | address `staff_id = 0` explicitly | – |
| Q19 | 🟡 | Invoice number | random 4 digits (collisions are retried) | keep format, capped retry | – |
| Q20 | 🟡 | POS guest | placeholder `info@bluecrownbarbers.com` and `(555) 123-4567` (another brand) | keep for parity, never email it | – |
| Q21 | 🟠 | POS mail | email is sent **inside** the DB transaction; a mail failure rolls the invoice back | send after commit, queued | – |
| Q22 | 🟡 | Dashboard vs list | staff dashboard counts "first available" lines for the staff, staff appointment list excludes them | document; keep each as the web does | – |
| Q23 | 🟡 | `Appointment::$appends = ['staff_names']` | an N+1 query on every serialized appointment | API never serializes the model directly | – |
| Q24 | 🟠 | Manager role | stored with `users.role='Staff'` ⇒ scoped as staff and blocked from reports | keep `isStaffUser()`; data fix suggested to the dev | D12 |
| Q25 | 🟡 | Scheduler | `email:service-followups` runs **every minute** | not our scope; mention to the dev | – |
| Q26 | 🟠 | Calendar create | overlap check compares `TIME` columns with full datetimes, ignores appointment status (a cancelled appointment still blocks the slot) | compare times correctly; ignore status 2 | – |
| Q27 | 🟡 | Today/upcoming | dashboard "today" lists exclude invoiced appointments, so completing hides them (expected) | same | – |
| Q28 | 🟡 | Timezones | Laravel h differenstores timestamps in `America/Edmonton`, but MySQL's own `NOW()` uses the PC/server clock zone (currently about 6 t). Any raw-SQL `NOW()` mixes the two | the API never uses SQL `NOW()`; it always passes PHP/Carbon times | – |
| Q29 | 🟠 | Dashboard (admin) "Tips Received" | the tip total joins the appointment to its service lines and sums `total_tip` per **joined row**, so an appointment with 3 service lines counts its tip 3 times | the API reproduces the web's figure (parity, D1) | D1 |
| Q30 | 🟡 | Appointments search | the search term is a `WHERE` on joined rows, so an appointment found only through a **staff name** shows only that staff member's lines in its row | reproduced exactly (parity test covers it) | – |
| Q31 | 🟡 | Reschedule | the web reschedule derives service ids with DISTINCT, so a service booked with quantity 2 is checked for the slot as a single unit; the API does the same (mirrors web). Allowed only from Pending and Cancelled (the web shows no button otherwise). |
| Q32 | 🟡 | Calendar booking overlap | the web overlap check is inclusive (an appointment starting exactly when another ends is refused) and ignores status (cancelled ones still block); the API mirrors it. |
| Q33 | 🟡 | Staff-by-service | ignores the barber's `active_status`; mirrored. |
| Q34 | 🟡 | Edit appointment | the customer record is looked up by phone and NOT renamed when the name changes in an edit; only the appointment row holds the new name. |
| Q35 | 🟡 | Customer profile | "total spend" adds each invoice once per service line (join duplicates) plus every product commission the customer ever generated; mirrored. |
| Q36 | 🟡 | Dashboard top lists | Top Services / Staff performance use `SUM(DISTINCT total_amt)`, so two appointments with the same amount count once; staff performance counts joined rows, not appointments. Mirrored. |
| Q37 | 🟡 | POS catalog | the web POS lists inactive services/products too; the app hides them and the server refuses them (plan decision). |
| Q38 | 🟡 | Edit invoice | the web re-prices every line at today's catalog price when an invoice is edited (history is rewritten); mirrored. |
| Q39 | 🟡 | Invoice tip | the web stores the tip split as unrounded floats (1.6666666667); the API splits in whole cents so the parts add up to the tip exactly. |
| Q40 | 🟠 | Staff create | the web stores the new barber's default 09:00-13:00 / 14:00-18:00 blocks as `break_type = 2` (a break), while "My working hours" reads `break_type = 1`. Staff created in the web therefore start with an empty working-hours page (real data: staff 34-49 have only type 2). Mirrored; the app shows the empty state and lets them add hours. |
| Q41 | 🟠 | Staff profile cards | revenue, appointments and visits are for **all** completed appointments of the shop, only tips/commissions are the person's own. The API returns them as `shop_*` fields beside the person's own numbers. |
| Q42 | 🟡 | Staff profile daily earnings | the staff member's total product commission is repeated on every day row. Mirrored. |
| Q43 | 🔴 | Staff create/edit/delete/password | the web endpoints accept any role id (also Super-admin) and any user id (also the Admin) - the form only hides them. The API accepts only the roles the form offers and only Staff/Accountant users (security). |
| Q44 | 🟡 | GST | saving the default GST without the default flag un-defaults it; deleting the default leaves the shop with no tax (Q16). The app always sends the flag; the API answers a delete of the default with a warning. |
| Q45 | 🟡 | Payment methods | a deleted method's name stays reserved (the unique rule counts deleted rows). Mirrored. |
| Q46 | 🟠 | Staff earnings report | the rows ignore the end date (the start date filter is written twice); the summary honours both. Mirrored. |
| Q47 | 🟡 | Customer invoices report | its "Amount" is what the staff earned on the invoice (commission + tips), not the invoice total. The API returns it as `amount` and the invoice total as `total`. |
| Q48 | 🟡 | Top products report | grouped by product and the invoice's product discount, so one product can have several rows. Mirrored. |
| Q49 | 🟡 | Reports | the appointments report rows need an invoiced, completed appointment but its summary only needs status 1; the payments report ignores the staff filter. Mirrored. |
| Q51 | 🟠 | Calendar | only `is_barber = 1` staff get a column; bookings on other staff (JOJO, Jack in the local DB) are invisible; booking create does not check `is_barber` | the app follows the web (barber columns only); listed in `docs/WEB_DEV_FIXES.md` | – |
| Q52 | 🟡 | Dashboard | permission `Dashboard-Top_Staff` and `getStaffPerformance` exist, but the page has no staff-performance widget | the app does not show it | – |
| Q50 | 🟡 | Gallery | the web "replace image" writes a column that does not exist and fails; the API replaces the picture only. Gallery routes in the web have no permission check (buttons are hidden by permission). |

---

## 9. Performance plan

1. **One round-trip at launch** (`/bootstrap`), ETag/304 on catalogs, `per_page ≤ 50`, columns selected explicitly (no `SELECT *`, no `appends`).
2. Replace the web's `GROUP_CONCAT` + 3–4 left-joins list query with: page of appointment ids first, then one query for their service lines (two small indexed queries beat one fat join).
3. Aggregates (dashboard/reports) pre-aggregate in sub-queries per appointment (exactly like the web's `leftJoinSub`), never `SUM(DISTINCT)`.
4. `Cache::remember` (30–60 s) only for pure aggregates that many users repeat (dashboard top lists); never for anything an action changes.
5. Recommended indexes (Section 3) once the owner approves.
6. Response compression (gzip) on Apache; image URLs are static files served by Apache directly.
7. **Measured baseline (Phase 0):** the API's own work is **15–70 ms** per request (from `api-*.log`), but every request on this PC takes ~320–500 ms wall-clock, the same as the web's `/admin/login` page (~320 ms). The cause is PHP start-up: `php.ini` has **no OPcache** enabled. Enabling OPcache in Laragon's `php.ini` would speed up web *and* API 2–3× with no code change (a local/dev-server tuning item, not part of the API). Budgets are therefore set on server time (`api-*.log`), and the smoke script only warns above 600 ms and fails above 1,500 ms wall-clock.

## 10. Security plan

* HTTPS only on live; `APP_DEBUG=false`; generic 500 text.
* Token 30 days, revoke on password change / deactivate / delete; limit tokens per user (e.g. 5 devices, oldest dropped).
* Throttles: login 10/min, OTP endpoints as the web, writes 30/min, reports 20/min.
* Every endpoint declares permission **and** object scope; a test matrix (role × endpoint) fails the build if any endpoint is missing a check.
* Validation with FormRequest classes; strict whitelists (status codes, enums); uploads: image mime + extension + 2 MB, random filenames (Laravel `store()`), never trust client names.
* Output: hide commission/spend/financial totals from staff exactly where the web hides them (`getCustomerDetails`), and never return `password`, `remember_token`, tokens.
* CORS: currently `Access-Control-Allow-Origin: *` on `/api/*` (needed only for testing the Flutter *web* build). Native apps do not need CORS; restrict it before going live (this is a web config file, so it needs the owner's OK).
* Logs contain no tokens/passwords/phones.

## 11. Future-proofing and live deploy

* **Additive only** in v1; deprecations announced via a `Deprecation` response header; `min_app_version` in `/bootstrap` lets us force an upgrade.
* **Feature flags** in `/bootstrap` (e.g. `complete_from_appointment`, `strict_numbers`) so behaviour changes without an app release.
* **No schema changes without approval.** If one is ever needed it ships as a numbered `.sql` file in `backend_api_patch/sql/` plus a rollback.
* **Patch bundle** `backend_api_patch/` always mirrors exactly what to copy to live: new files + one append to `routes/api.php`. Never copy `.env` or `bootstrap/cache/*`.
* **Live checklist:** (1) tables `personal_access_tokens`, `password_reset_otps`, column `tbl_appointment.invoice_created_by` exist; (2) copy the patch files; (3) append the route block (do not overwrite `routes/api.php`); (4) `php artisan route:list --path=api/v1`; (5) run the smoke script against the live URL with a test account; (6) rollback = delete the folder `Api/V1` and the appended block.
* **Contract:** an `openapi.yaml` is produced alongside the code; the Flutter client models are generated from it so the app and API cannot drift.
* **Backups:** before first live use of any write endpoint, the dev takes a DB backup.

## 12. Build phases and tests

| Phase | Deliverable | Enables in the app |
|---|---|---|
| **P0** Foundation ✅ **DONE** | envelope + error handler, permission/scope helpers, token-validity middleware, `/bootstrap`, `/health`, AUTH-1..4 in the final envelope, request-id logging, smoke script | login, navigation by permissions |
| **P1** Daily driver ✅ **DONE** | DASH-1/2/3, APPT-1/2/3/4/5, ME-1/2, AUTH-5..8 (AUTH-9 dropped: not in the web) | dashboard, today's list, confirm/cancel, profile, forgot password |
| **P2** Scheduling ✅ **DONE** | APPT-6/7/8/9/10, CAL-1/2/3, ME-7..11 | calendar, create/edit/reschedule, working hours |
| **P3** Money ✅ **DONE** | POS-1..8, APPT-11, CUST-1..6, DASH-4/5/6, ME-3..6 | POS, invoices, customers, staff report |
| **P4** Administration ✅ **DONE** | STAFF-1..12, CAT-1..5, SHOP-1..3 | manage staff, catalog, settings, hours, closures |
| **P5** ✅ **DONE** Reports & content | RPT-1..6, CONT-1/2, ROLE-1/2 | owner reports, website content, roles |
| **P6** Extras | NOTIF/SYNC (needs approval) | push, offline |

**Test plan (every phase):**
1. *Parity tests* — web endpoint vs API with identical filters; counts and totals must match (documented exceptions: Q1/Q2).
2. *Permission matrix* — for each endpoint × each of the 6 roles + a user with no role: expected 200/403.
3. *Object-scope tests* — a staff user can never read or change another staff's data (appointments, invoices, working hours, earnings).
4. *Money unit tests* — the golden cases of Section 6, plus a randomized comparison of the PHP calculator against the web's JavaScript formulas.
5. *Concurrency* — double confirm, two bookings for the same slot (second gets 409), double POS submit (idempotency key).
6. *Data states* — empty database, soft-deleted staff, "First available" user, appointment without a customer, deactivated user holding an old token.
7. *Upload tests* — oversize, wrong mime, replace and delete cleans the old file.
8. *Smoke + timing script* — logs in as admin and staff, hits every GET, prints status and milliseconds, fails on any 5xx or budget miss.
Definition of done for an endpoint: documented here, validated, permission + scope enforced, parity/permission/scope tests green, no new line in `storage/logs/laravel.log`, listed in `openapi.yaml`.

---

## 13. Decisions the owner must make

### 13.0 Owner's answers (recorded 2026-10-23) — these override the recommendations below
1. **The web is the contract.** For now the API reproduces what the web does, including its quirks. Later the owner will talk to the web developer and have the web fixed; after that the API is adjusted to match. Section 8 is the list to hand to the web developer.
2. **App audience = Admin and Staff only.** No end-user/customer features, ever, in this app.
3. Consequences for the open decisions:
   * **D1 → parity only.** Numbers equal the web. The extra `strict` figures are *not* shown in the app for now (kept in the API code behind a flag, off).
   * **D2 → ON since 2026-10-26** (owner asked for the web's Complete button in the app; the app creates the invoice itself, so it works even though the web's Complete 404s). Originally: off.
* ~~D2 → off.~~ (superseded)
* **D2 (old) → off.** `APPT-11` (complete an appointment into an invoice) is **not enabled**; the web cannot do it today (Q5). It is built behind the feature flag `complete_from_appointment = false` and switched on only after the web developer fixes the web.
   * **D3 → web outcome.** Invoice totals are computed with the exact web formulas (Section 6). The server still validates inputs and ownership (these checks are invisible to an honest user and do not change any result).
   * **D12 → keep the web rule** (`users.role` decides staff scoping); tell the web developer (Q24).
   * Everything that only *adds protection* without changing an honest result (permission checks, ownership checks, input validation, refusing impossible status values) stays in, because the API is a new public surface.
   * Anything the web does **not** do at all (AUTH-9 self password change, CAL-4 delete break, POS-8 preview, Phase 6 extras) is optional and not built unless the owner asks.

| # | Question | My recommendation |
|---|---|---|
| **D1** | Dashboard/report numbers: copy the web's formulas exactly even where they look wrong (Q1, Q2), or use correct ones? | **Parity first** (numbers equal the web), with a `strict` value beside each affected figure; switch with a flag after you compare |
| **D2** | The web cannot complete a booked appointment (Q5). Add "complete appointment → invoice" to the app? | **Yes** (APPT-11). It is the natural flow and the SaaS copy already does it |
| **D3** | POS: trust browser totals (web) or recompute on the server? | **Server recomputes** (no change to what an honest user sees) |
| **D4** | Response envelope: keep flat like the web or `data`? | **`data`** (decided in Section 4.1) |
| **D5** | Staff changing their **own** password in the app (the web has none)? | **Yes**, with current password (AUTH-9) |
| **D6** | Expose permission add/edit/delete? | **No** |
| **D7** | Role management inside the app? | **Phase 5, Super-admin only** |
| **D8** | Push notifications for new website bookings? | **Phase 6**; needs a new table + Firebase key |
| **D9** | Offline mode? | **Read-only cache** of today's appointments, calendar and catalog; writes require internet |
| **D10** | Token lifetime | **30 days**, revoked on password change/deactivate |
| **D11** | Decrement product stock at invoice? | Web does not. **Keep parity**, add later as an option |
| **D12** | "Manager" users are stored as `users.role='Staff'` so they are scoped as staff and blocked from reports | **Keep the web rule** in the API, but ask the developer to store managers as `Admin` |
| **D13** | Refuse to leave the shop without a default GST? | **Yes** |
| **D14** | App always shows **shop time** (Edmonton) even if the phone is elsewhere | **Yes** |
| **D15** | Staff appointment list hides "First available" lines but the dashboard counts them (Q22) | keep as the web does |
| **D16** | Customer phone matching on digits only to avoid duplicates | **Yes** |
| **D17** | Customer delete: permanent (web) or refuse when they have appointments? | **Refuse** (409) |
| **D18** | Optional DB indexes (Section 3) on live | **Yes, later**, via the developer |

---

## 14. Phase 0 as built (2026-10-23)

**Files (all new; also mirrored in `backend_api_patch/`):**
| File | Purpose |
|---|---|
| `routes/api.php` (appended block) | `/api/v1`: `GET health`, `POST auth/login`, then signed-in `GET auth/me`, `POST auth/logout`, `POST auth/logout-all`, `GET bootstrap`, and a last catch-all `ANY {any}` → JSON 404 |
| `Middleware/Api/ForceJson` | forces `Accept: application/json` (a request without it can no longer be redirected to the web login) |
| `Middleware/Api/ApiRequestLog` | `X-Request-Id` header + one line per request in `storage/logs/api-DATE.log` (id, user, method, path, status, ms, ip; no bodies/queries/tokens) |
| `Middleware/Api/ApiEnvelope` | converts every exception into the error envelope; hides internals (SQL, paths) unless `APP_DEBUG=true`; adds `request_id` |
| `Middleware/Api/ApiAuthenticate` | Sanctum bearer auth; refuses and **revokes the token of a deactivated account**; soft-deleted users cannot authenticate |
| `Middleware/Api/ApiRateLimit` | envelope-shaped 429 with `retry_after`; login limit = 10 / minute per IP+email |
| `Middleware/Api/RequirePermission` | `canany`-style gate for later phases (`…::class . ':Appointment-View'`) |
| `Controllers/Api/V1/ApiController` | `ok()`, `fail()`, `listing()`, `pageParams()` helpers |
| `Controllers/Api/V1/AuthController` · `BootstrapController` · `HealthController` · `FallbackController` · `ModuleAccess` | endpoints and the web-route→module permission map |
| `Services/Api/UserPresenter` | one definition of how a user looks to the app |
| `config/api_v1.php` | token days (30), max devices (5), page limits, shop name/currency, `min_app_version`, `feature_flags`, `required_schema` for `/health` |
| `backend_api_patch/tools/api_smoke.js` | the smoke + timing test |

**Verified (smoke test 15/15 + manual edge cases):** `/health` public; 401 returns a JSON envelope even with **no** `Accept` header; unknown endpoint → JSON 404; `X-Request-Id` present and equal to `request_id` in error bodies; validation → 422 with `errors{}`; wrong password and unknown email give the **same** message and similar timing; login gives a 30-day token and the user with `modules`; staff modules equal the web's staff access exactly; `/bootstrap` returns every field (`tax 5.00% include`, step 10 min, 4 payment methods, 7 shop days, `America/Edmonton`); only the newest 5 tokens per user survive; `logout` revokes one token, `logout-all` revokes all; login rate limit → 429 envelope; a **deactivated** user is refused and their token deleted; an **expired** token → 401; a **soft-deleted** user's token → 401; error bodies never leak SQL or paths (unit check of every exception type). Web re-checked after the change: all public pages and 8 admin pages still 200, `laravel.log` unchanged.

**Lessons recorded for the next phases**
1. Laravel's router pipeline turns an exception thrown in a controller into a response *before* outer middleware sees it, so `try/catch` in middleware does nothing. `ApiEnvelope` therefore also re-renders `$response->exception`. Any future middleware that needs to react to errors must do the same.
2. Do not use the `auth:` / `throttle:` aliases on API routes: Laravel re-orders them by a priority list and they can run outside the JSON middleware (the earlier test returned an HTML 302 for an API call without `Accept`).
3. `->skip()` without `->take()` is invalid MySQL (`OFFSET` needs `LIMIT`). Slice collections in PHP instead.

---

## 15. Phase 1 as built (2026-10-23)

**Endpoints (all under `/api/v1`):**
| ID | Route | Notes |
|---|---|---|
| AUTH-5..8 | `POST auth/forgot-password · verify-otp · resend-otp · reset-password` | web rules: OTP 10 min, 5 wrong tries, token 15 min, password ≥ 6 with letters+numbers; a successful reset also signs the user out of every device |
| DASH-1 | `GET dashboard/summary` | admin ⇒ shop revenue/tips; everyone else ⇒ own earnings/tips/commission; `widgets{}` says which blocks the web would draw for this user |
| DASH-2/3 | `GET dashboard/today · dashboard/upcoming` | `?q=&page=&per_page=`; staff ⇒ own lines |
| APPT-1 | `GET appointments` | `status, start_date+end_date (both, like the web), staff_id, day_type, q`; sorted date desc, start desc |
| APPT-2 | `GET appointments/counts` | all / pending / confirmed / completed / cancelled / rescheduled |
| APPT-3 | `GET appointments/{id}` | grouped services (qty, line total, duration) and staff groups; staff only see their own lines; 404 if they have none |
| APPT-4/5 | `POST appointments/{id}/confirm · cancel` | web transitions only: confirm from Pending/Rescheduled, cancel from Pending/Confirmed/Rescheduled; 409 otherwise (already done, or completed); row locked in a transaction |
| ME-1/2 | `GET me/profile · POST me/profile` | photo upload (jpg/png/gif ≤ 2 MB) goes to the web's `public` disk (`public/storage/profile_images`), the old photo is deleted |

**Row shape shared by every appointment list:** `id, booking_code, date, start, end, start_label, end_label, slot_label, status, status_key, status_label, customer{id,name,phone}, staff_names[], staff_ids[], service_ids[], lines[], actions[]`. `actions` comes from the status matrix (2.3) with `complete` removed while `feature_flags.complete_from_appointment` is false.

**Verification (all re-runnable from `backend_api_patch/tools/`):**
| Suite | Result | What it proves |
|---|---|---|
| `api_smoke.js` | 15/15 | Phase 0 foundation still works |
| `parity_phase1.js` | **50/50** | admin **and** staff, same filters as the web: appointment list (no filter, status 0/2/3/4, staff, date range, "only start date", morning/afternoon/evening, 3 searches), dashboard today/upcoming (with searches), status counts, dashboard cards, and 38 detail views — record counts, ids, **order**, status, slot, staff names, service lines, customer, totals all equal the web's |
| `api_phase1_test.js` | 24/24 | transition rules, completed appointments untouchable, staff cannot see/act on another barber's appointment, role-less user gets 403, widgets mirror `@can`, validation, paging clamps, typed money, profile save/unique email/photo upload+replace+reject, 300-call burst ⇒ 429 envelope with no 5xx |
| `phase1_password_reset_test.php` | 24/24 | full OTP flow in-process with a fake mailer (no real email): unknown email, OTP stored hashed, wrong tries counted and locked, resend invalidates the old OTP, expiry, reset token single-use, weak password, old token signed out, inactive account |

**What the parity run found and fixed (worth remembering for later phases):**
1. The web's DataTables output is HTML-escaped (`Men&#039;s cut`); the API returns raw text (`Men's cut`). Parity tests must unescape before comparing.
2. Q30: a search WHERE on joined rows also trims the displayed lines. The first API version returned all lines; fixed to match.
3. Laravel's default `throttle:api` (60/min) answers outside our envelope and, with `APP_DEBUG=true`, leaks exception and file path. The v1 route group now excludes it (`withoutMiddleware('throttle:api')`) and uses `ApiRateLimit` (240/min per user).
4. A rate limiter built on `check then count` is **not atomic on the file cache**: a burst of parallel requests all pass the check. `ApiRateLimit` now does it under a cache lock. On Windows the file lock can itself fail under heavy parallel load (`Unable to create lockable file`); that case falls back to the plain check instead of returning a 500.
5. The web's `public` filesystem disk root is `public/storage` (not `storage/app/public`), so API uploads land exactly where web uploads do.
6. MySQL reserves `LINES` (a test SQL alias broke); `DB::select` helpers should avoid reserved words.

**Not built on purpose:** AUTH-9 (self password change; not in the web), APPT-11 (complete appointment; flag off until the web is fixed).

---

## 16. Phase 2 as built (2026-10-23)

**Endpoints:** APPT-6 reschedule, APPT-7 slots, APPT-8 create, APPT-9 edit, APPT-10 staff-by-service, CAL-1 events, CAL-2 availability, CAL-3 breaks, ME-7..11 own working hours (17 routes). CAL-4 (delete break) not built: the web cannot do it.

**How:** the slot engine is not re-implemented; `SlotEngine` calls `WebsiteController::get_slot_by_staff` so web and app can never disagree. Create/edit/reschedule run under a per-barber cache lock (`SlotGuard`, 15 s) so two phones cannot take the same slot (verified: one 201, one 409). Staff can only book/edit/block/reschedule on their own calendar. Working-hour endpoints are staff-only, ownership enforced (404 on another barber's block).

**Verification (all against the local DB, with the real web endpoints as reference):**

| Script | Result | What it proves |
|---|---|---|
| `parity_phase2.js` | 19/19 | calendar events/lanes/availability, slot finder (7 service combos x 5 dates incl. First available), staff-by-service: identical to the web |
| `api_phase2_test.js` | 38/38 | create/edit/reschedule rules, overlaps, race conditions, breaks, working hours, permissions, plus **write parity**: web and API leave identical rows for create, edit, reschedule, break and working-hour block |
| earlier suites | 15 + 50 + 24 + 19 | Phase 0/1 still green |

No 5xx during the Phase 2 runs; public and admin web pages still 200.

**Found while testing:** Windows `mysql` output ends lines with CRLF (test helper bug, not an API bug); the same-time race test must use different times per record.

---

## 17. Phase 3 as built (2026-10-23)

**Endpoints (30 routes):** DASH-4/5/6 top lists, CUST-1..6 customers, ME-3..6 own earnings report, POS-1 catalog, POS-2 customer lookup, POS-8 preview, POS-3 create invoice, POS-4 list, POS-5 detail, POS-6 edit, POS-7 email invoice, APPT-11 complete (route exists, **feature flag off**: answers 404 "not available yet").

**How:**
* Reads re-run the web's own queries (same joins, same `DISTINCT` quirks) and add paging/search; the customer profile numbers are the web's literal queries.
* **Invoice money is computed on the server with the web page's formulas** (Section 6): service/product discount as %, GST include/exclude from the default GST row, tip, commission with the shop service fee, tip split. The app sends only *what was sold* (type, id, barber, qty) plus discount %, tip, payment method and customer; client-sent totals do not exist. `POST /invoices/preview` returns the same numbers the save will store, so the screen and the database cannot disagree.
* Create/edit are transactions; the invoice number keeps the `INV-YYYYMMDD-NNNN` format with a uniqueness loop; edit keeps number and creator; `Idempotency-Key` header makes a retried submit return the first invoice (201 then 200, also under a simultaneous double tap).
* Visibility is the web rule: a Staff user without `Pos_invoice-Show_All` only sees invoices they created (others answer 404). Commission rates and per-line commission are not shown to Staff users; customer spend is hidden from staff in the lookup (web does the same).
* Email: sent **after** the invoice is saved and never fatal (the web mails inside the transaction, so a mail error loses the invoice, Q21). The Guest placeholder address is never mailed; POS-7 says so with 422.
* Customer rules copied from the web: known phone is reused; no data at all = shared Guest customer; otherwise a new customer with the web's placeholder phone/email for whatever is missing.
* Delete customer (CUST-6) is refused with 409 while the customer has appointments (D17).

**Verification:**

| Script | Result | What it proves |
|---|---|---|
| `parity_phase3a.js` | 17/17 | customer list/search/profile numbers, customer appointments with filters, top services, staff performance, top products, staff summary cards, earnings, services, appointments: equal to the web's tables |
| `api_phase3a_test.js` | 7/7 | customer create/edit/delete with write parity, validation, permissions |
| `api_phase3b_test.js` | 26/26 | totals equal the web page's JavaScript for 6 golden carts + exclude-GST; web `invoice/store` and `invoice/update` vs API leave the same header, service and product rows; visibility, idempotency, race, validation, permissions |
| `phase3b_invoice_mail_test.php` | 9/9 | emails with a fake mailer: send-after-save, override address, placeholder never mailed, mailer failure → 502 and the invoice stays |
| `phase3b_complete_test.php` | 6/6 | APPT-11 off by default; logic works when switched on |
| earlier suites | 15 + 50 + 24 + 19 + 38 | Phase 0/1/2 still green |

**Not built on purpose:** AUTH-9, CAL-4, product stock decrement (Q17/D11), APPT-11 switched on.

---

## 18. Phase 4 as built (2026-10-23)

**Endpoints (about 60 routes):** CAT-1 services (+ website section), CAT-2 categories, CAT-3 products, CAT-4 GST (+ make default), CAT-5 payment methods, SHOP-1 settings (general, contact), SHOP-2 shop hours, SHOP-3 closures, STAFF-1..12.

**How:**
* Each module copies the web controller's rules and the same storage folders (`service_images`, `product_images`, `profile_images` on the `public` disk), so a picture saved from the app shows on the website. Pictures need multipart; editing therefore accepts POST as well as PUT.
* Service/product forms send explicit booleans (`active_status`, `eligible_for_tip`): in the web a missing checkbox silently switches the item off.
* Per-action permissions follow the web buttons (Add/Edit/Delete); the web's routes only check "any of the three".
* Shop hours address the shop's own rows (`staff_id = 0`); the breaks are replaced exactly like the web slot save. Closures keep the "00:55 becomes 12:55" fix.
* Staff create copies every side effect of the web (role, service links, legacy CSV, 7 slot rows and 14 default blocks for panel Staff). Delete is a soft delete plus picture removal, and also ends that person's app sessions; so does a password change or switching the account off.
* Protection beyond the web (does not change an honest result): only the roles the form offers can be assigned, only Staff/Accountant users can be edited/deleted/re-passworded, nobody can delete themselves or the "First available" pseudo barber, invalid images and out-of-range numbers are rejected.

**Verification:**

| Script | Result | What it proves |
|---|---|---|
| `api_phase4a_test.js` | 22/22 | lists equal the web tables; create/update/delete equal the web by the rows left behind (multipart pictures included, old files deleted); GST default switching; payment method rules; settings, hours and closures written through the web form and through the API leave the same rows; closure and day-off reach the slot finder; staff user gets 403 everywhere; shared data restored |
| `api_phase4b_test.js` | 17/17 | staff list/profile cards/earnings/services/appointments equal the web; create (barber and accountant) and update equal the web incl. role, services, 7 slots + 14 blocks; role escalation and editing the admin are refused; password change and deactivation end old sessions; assigned services parity; delete rules |
| earlier suites | all green | Phase 0-3 unchanged |

**Not built on purpose:** deleting a break (CAL-4), self password change (AUTH-9).

---

## 19. Phase 5 as built (2026-10-23)

**Endpoints (20 routes):** RPT-1..6 admin reports, CONT-1 testimonials, CONT-2 gallery, ROLE-1/2 roles and permissions. With this the planned API is complete: every web screen an Admin or Staff user can reach has an endpoint (see Appendix A), except what is listed under "Not built on purpose".

**How:**
* Reports use the web's queries and add paging/search; each answers with `meta.summary` (the cards above the web tables). Same gate as the web: `Report-View` and not a Staff-role user (so Managers, stored as Staff, are refused like on the web, Q24).
* Testimonials/gallery use the web's disk folders so the website shows the pictures; the bundled default pictures are never deleted.
* Roles: the web lets anyone with Role-Delete delete any role by crafted request; the API refuses Super-admin, Staff, POS Manager and Accountant (code refers to them) and any role still given to people, and refuses renaming those. Permissions are read-only (D6).

**Verification:** `api_phase5_test.js` 14/14 (reports equal the web tables for 4 filter sets each, content and roles by the rows left behind). Full regression after Phase 4: smoke 15, parity P1 50, P1 24, parity P2 19, P2 38, parity P3a 17, P3a 7, P3b 26, mail 9, complete 6, P4a 22, P4b 17: all green.

**Not built on purpose:** AUTH-9 (self password change), CAL-4 (delete a break), permission add/edit/delete (D6), APPT-11 switched on, product stock decrement (D11).

---

<!-- ROUTE_COVERAGE_START -->
## Appendix A — Web route → API coverage (generated)

Every distinct web action (**195**, from `php artisan route:list`, 203 routes) is listed. **Unmapped: 0.** The generator fails if a web action has no entry, so this table cannot silently miss a route.
"Guard" is the web middleware that protects the route today (`canany:`/`can:` are spatie permissions). The API enforces the same permission **plus** the object-level scope from Section 4.3.

| Web action | Web route(s) | Web guard | API |
|---|---|---|---|
| `AppointmentController@GetTableData` | POST /admin/appointment-action | — (login only) | APPT-1 |
| `AppointmentController@breakFormSubmit` | POST /admin/breakFormSubmit | — (login only) | CAL-3 |
| `AppointmentController@calenderAppointMentStore` | POST /admin/appointMentBook | — (login only) | APPT-8 (create) + APPT-9 (edit) |
| `AppointmentController@calenderIndex` | GET /admin/incalender | canany:Calender-View | PAGE (HTML only) → data via CAL-1, CAL-2 |
| `AppointmentController@confirm_reject_action` | POST /admin/appointment.confirm-reject-action | — (login only) | APPT-4 (confirm) + APPT-5 (cancel) |
| `AppointmentController@create` | GET /admin/appointment/create | canany:Appointment-View | empty method in the web (no behaviour) — nothing to build |
| `AppointmentController@destroy` | DELETE /admin/appointment/{appointment} | canany:Appointment-View | empty method in the web (no behaviour) — nothing to build |
| `AppointmentController@edit` | GET /admin/appointment/{appointment}/edit | canany:Appointment-View | empty method in the web (no behaviour) — nothing to build |
| `AppointmentController@fetch` | GET /admin/appointments/fetch | — (login only) | CAL-1 |
| `AppointmentController@fetchStaffAvailability` | GET /admin/staff-availability | — (login only) | CAL-2 |
| `AppointmentController@get_appointment_details` | POST /admin/appointment.get-appointment-details | — (login only) | APPT-3 |
| `AppointmentController@get_customer_appointment_details` | POST /admin/appointment.get-customer-appointment-details | — (login only) | APPT-3 |
| `AppointmentController@get_staff_by_service` | POST /admin/appointment.get-staff-by-service | — (login only) | APPT-10 |
| `AppointmentController@index` | GET /admin/appointment | canany:Appointment-View | PAGE (HTML only) → data via APPT-1, APPT-2 |
| `AppointmentController@show` | GET /admin/appointment/{appointment} | canany:Appointment-View | empty method in the web (no behaviour) — nothing to build |
| `AppointmentController@store` | POST /admin/appointment | canany:Appointment-View | empty method in the web (no behaviour) — nothing to build |
| `AppointmentController@submit_reschedule_appointment` | POST /admin/appointment.submit-reschedule-appointment | — (login only) | APPT-6 |
| `AppointmentController@update` | PUT\|PATCH /admin/appointment/{appointment} | canany:Appointment-View | empty method in the web (no behaviour) — nothing to build |
| `CustomerController@GetTableData` | POST /admin/customers-action | — (login only) | CUST-1 |
| `CustomerController@PendingAppointmentgetTableData` | POST /admin/customer-pending-appointment-action | — (login only) | CUST-3 |
| `CustomerController@create` | GET /admin/customers/create | canany:Customer-Add,Customer-Edit,Customer-Delete | empty method in the web (no behaviour) — nothing to build |
| `CustomerController@customer_profile` | GET /admin/customer-profile/{id} | — (login only) | CUST-2 |
| `CustomerController@destroy` | DELETE /admin/customers/{customer} | canany:Customer-Add,Customer-Edit,Customer-Delete | CUST-6 |
| `CustomerController@edit` | GET /admin/customers/{customer}/edit | canany:Customer-Add,Customer-Edit,Customer-Delete | empty method in the web (no behaviour) — nothing to build |
| `CustomerController@index` | GET /admin/customers | canany:Customer-Add,Customer-Edit,Customer-Delete | PAGE (HTML only) → data via CUST-1 |
| `CustomerController@show` | GET /admin/customers/{customer} | canany:Customer-Add,Customer-Edit,Customer-Delete | empty method in the web (no behaviour) — nothing to build |
| `CustomerController@store` | POST /admin/customers | canany:Customer-Add,Customer-Edit,Customer-Delete | CUST-4 |
| `CustomerController@update` | PUT\|PATCH /admin/customers/{customer} | canany:Customer-Add,Customer-Edit,Customer-Delete | CUST-5 |
| `DashboardController@GetTodayGetTableData` | POST /admin/get-today-appointment | — (login only) | DASH-2 |
| `DashboardController@GetUpcomingGetTableData` | POST /admin/get-upcoming-appointment | — (login only) | DASH-3 |
| `DashboardController@TopServicesGetTableData` | POST /admin/top-services | — (login only) | DASH-4 |
| `DashboardController@getStaffPerformance` | POST /admin/staff-performance | — (login only) | DASH-5 |
| `DashboardController@index` | GET /admin/dashboard | canany:Dashboard-Today_Appointments,Dashboard-Upcoming_Appointments,Dashboard-Top_Services,Dashboard-Top_Staff | DASH-1 (cards) + DASH-6 (top products) |
| `GstController@GetTableData` | POST /admin/gst-action | — (login only) | CAT-4 (list) |
| `GstController@create` | GET /admin/gst/create | canany:Gst-Add,Gst-Edit,Gst-Delete | empty method in the web (no behaviour) — nothing to build |
| `GstController@destroy` | DELETE /admin/gst/{gst} | canany:Gst-Add,Gst-Edit,Gst-Delete | CAT-4 (delete) |
| `GstController@edit` | GET /admin/gst/{gst}/edit | canany:Gst-Add,Gst-Edit,Gst-Delete | empty method in the web (no behaviour) — nothing to build |
| `GstController@index` | GET /admin/gst | canany:Gst-Add,Gst-Edit,Gst-Delete | PAGE (HTML only) → data via CAT-4 |
| `GstController@show` | GET /admin/gst/{gst} | canany:Gst-Add,Gst-Edit,Gst-Delete | empty method in the web (no behaviour) — nothing to build |
| `GstController@store` | POST /admin/gst | canany:Gst-Add,Gst-Edit,Gst-Delete | CAT-4 (create) |
| `GstController@update` | PUT\|PATCH /admin/gst/{gst} | canany:Gst-Add,Gst-Edit,Gst-Delete | CAT-4 (update) |
| `InvoiceController@SendInvoiceMail` | POST /admin/send-invoice-mail | canany:Pos_invoice-Add,Pos_invoice-Edit | POS-7 |
| `InvoiceController@create` | GET /admin/invoice/create | canany:Pos_invoice-Add,Pos_invoice-Edit | PAGE (HTML only) → data via POS-1 |
| `InvoiceController@edit` | GET /admin/invoice/edit/{id} | canany:Pos_invoice-Add,Pos_invoice-Edit | PAGE (HTML only) → data via POS-5 + POS-1 |
| `InvoiceController@getCustomerDetails` | GET /admin/getCustomer | canany:Pos_invoice-Add,Pos_invoice-Edit | POS-2 |
| `InvoiceController@index` | GET /admin/invoice | canany:Pos_invoice-Add,Pos_invoice-Edit,Pos_invoice-Show_All | PAGE (HTML only) → data via POS-4 |
| `InvoiceController@store` | POST /admin/invoice/store | canany:Pos_invoice-Add,Pos_invoice-Edit | POS-3 (+ POS-8 preview) |
| `InvoiceController@update` | POST /admin/invoice/update | canany:Pos_invoice-Add,Pos_invoice-Edit | POS-6 |
| `PaymentmethodController@create` | GET /admin/payment-method/create | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `PaymentmethodController@destroy` | DELETE /admin/payment-method/{payment_method} | can:Setting-Payment_Method | CAT-5 (delete) |
| `PaymentmethodController@edit` | GET /admin/payment-method/{payment_method}/edit | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `PaymentmethodController@index` | GET /admin/payment-method | can:Setting-Payment_Method | PAGE (HTML only) → data via CAT-5 |
| `PaymentmethodController@show` | GET /admin/payment-method/{payment_method} | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `PaymentmethodController@store` | POST /admin/payment-method | can:Setting-Payment_Method | CAT-5 (create) |
| `PaymentmethodController@update` | PUT\|PATCH /admin/payment-method/{payment_method} | can:Setting-Payment_Method | CAT-5 (update) |
| `PermissionController@GetTableData` | POST /admin/permission-action | — (login only) | 🚫 not exposed (any logged-in user can edit permissions in the web, Q7) |
| `PermissionController@create` | GET /admin/permission/create | — (login only) | empty method in the web (no behaviour) — nothing to build |
| `PermissionController@destroy` | DELETE /admin/permission/{permission} | — (login only) | 🚫 not exposed (any logged-in user can edit permissions in the web, Q7) |
| `PermissionController@edit` | GET /admin/permission/{permission}/edit | — (login only) | empty method in the web (no behaviour) — nothing to build |
| `PermissionController@index` | GET /admin/permission | — (login only) | 🚫 not exposed (any logged-in user can edit permissions in the web, Q7) |
| `PermissionController@show` | GET /admin/permission/{permission} | — (login only) | empty method in the web (no behaviour) — nothing to build |
| `PermissionController@store` | POST /admin/permission | — (login only) | 🚫 not exposed (any logged-in user can edit permissions in the web, Q7) |
| `PermissionController@update` | PUT\|PATCH /admin/permission/{permission} | — (login only) | 🚫 not exposed (any logged-in user can edit permissions in the web, Q7) |
| `ProductController@GetTableData` | POST /admin/product-action | — (login only) | CAT-3 (list) |
| `ProductController@create` | GET /admin/product/create | canany:Product-Add,Product-Edit,	Product-Delete | empty method in the web (no behaviour) — nothing to build |
| `ProductController@destroy` | DELETE /admin/product/{product} | canany:Product-Add,Product-Edit,	Product-Delete | CAT-3 (delete) |
| `ProductController@edit` | GET /admin/product/{product}/edit | canany:Product-Add,Product-Edit,	Product-Delete | empty method in the web (no behaviour) — nothing to build |
| `ProductController@index` | GET /admin/product | canany:Product-Add,Product-Edit,	Product-Delete | PAGE (HTML only) → data via CAT-3 |
| `ProductController@show` | GET /admin/product/{product} | canany:Product-Add,Product-Edit,	Product-Delete | empty method in the web (no behaviour) — nothing to build |
| `ProductController@store` | POST /admin/product | canany:Product-Add,Product-Edit,	Product-Delete | CAT-3 (create) |
| `ProductController@update` | PUT\|PATCH /admin/product/{product} | canany:Product-Add,Product-Edit,	Product-Delete | CAT-3 (update) |
| `ProfileController@index` | GET /admin/profile | — (login only) | ME-1 |
| `ProfileController@update` | PUT /admin/profile | — (login only) | ME-2 |
| `ReportController@GetStaffEarnGetTableData` | POST /admin/get-staff-performance | canany:Report-View · not staff | RPT-3 |
| `ReportController@ProductSellReport` | POST /admin/sell-product-report | canany:Report-View · not staff | RPT-5 |
| `ReportController@ReportCustomerInvoices` | POST /admin/customer-report-invoice | canany:Report-View · not staff | RPT-4 |
| `ReportController@TopSellingProductReport` | POST /admin/top-selling-product-report | canany:Report-View · not staff | RPT-6 |
| `ReportController@getAppointmentsTableData` | POST /admin/get-report-appointment | canany:Report-View · not staff | RPT-1 |
| `ReportController@getPaymentMethodsTableData` | POST /admin/get-report-payment | canany:Report-View · not staff | RPT-2 |
| `ReportController@index` | GET /admin/reports | canany:Report-View · not staff | PAGE (HTML only) → data via RPT-1..6 |
| `RolesController@GetTableData` | POST /admin/roles-action | — (login only) | ROLE-1 |
| `RolesController@create` | GET /admin/roles/create | — (login only) | empty method in the web (no behaviour) — nothing to build |
| `RolesController@destroy` | DELETE /admin/roles/{role} | — (login only) | ROLE-2 (with safety rules) |
| `RolesController@edit` | GET /admin/roles/{role}/edit | — (login only) | empty method in the web (no behaviour) — nothing to build |
| `RolesController@getRolePermissions` | POST /admin/admin/roles/{id}/permissions | — (login only) | ROLE-1 |
| `RolesController@index` | GET /admin/roles | — (login only) | PAGE (HTML only) → data via ROLE-1 |
| `RolesController@show` | GET /admin/roles/{role} | — (login only) | empty method in the web (no behaviour) — nothing to build |
| `RolesController@store` | POST /admin/roles | — (login only) | ROLE-2 |
| `RolesController@update` | PUT\|PATCH /admin/roles/{role} | — (login only) | ROLE-2 |
| `ServiceController@GetTableData` | POST /admin/service-action | — (login only) | CAT-1 (list) |
| `ServiceController@create` | GET /admin/service/create | canany:Service-Add,Service-Edit,Service-Delete | empty method in the web (no behaviour) — nothing to build |
| `ServiceController@destroy` | DELETE /admin/service/{service} | canany:Service-Add,Service-Edit,Service-Delete | CAT-1 (delete) |
| `ServiceController@edit` | GET /admin/service/{service}/edit | canany:Service-Add,Service-Edit,Service-Delete | empty method in the web (no behaviour) — nothing to build |
| `ServiceController@index` | GET /admin/service | canany:Service-Add,Service-Edit,Service-Delete | PAGE (HTML only) → data via CAT-1 |
| `ServiceController@show` | GET /admin/service/{service} | canany:Service-Add,Service-Edit,Service-Delete | empty method in the web (no behaviour) — nothing to build |
| `ServiceController@store` | POST /admin/service | canany:Service-Add,Service-Edit,Service-Delete | CAT-1 (create) |
| `ServiceController@update` | PUT\|PATCH /admin/service/{service} | canany:Service-Add,Service-Edit,Service-Delete | CAT-1 (update) |
| `ServiceController@updateHomeSection` | POST /admin/service-home-section | — (login only) | CAT-1b |
| `ServicecategoryController@GetTableData` | POST /admin/service-category-action | — (login only) | CAT-2 (list) |
| `ServicecategoryController@create` | GET /admin/service-category/create | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | empty method in the web (no behaviour) — nothing to build |
| `ServicecategoryController@destroy` | DELETE /admin/service-category/{service_category} | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | CAT-2 (delete) |
| `ServicecategoryController@edit` | GET /admin/service-category/{service_category}/edit | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | empty method in the web (no behaviour) — nothing to build |
| `ServicecategoryController@index` | GET /admin/service-category | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | PAGE (HTML only) → data via CAT-2 |
| `ServicecategoryController@show` | GET /admin/service-category/{service_category} | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | empty method in the web (no behaviour) — nothing to build |
| `ServicecategoryController@store` | POST /admin/service-category | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | CAT-2 (create) |
| `ServicecategoryController@update` | PUT\|PATCH /admin/service-category/{service_category} | canany:	Service_Category-Add,Service_Category-Edit,	Service_Category-Delete | CAT-2 (update) |
| `SettingController@create` | GET /admin/setting/create | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `SettingController@destroy` | DELETE /admin/setting/{setting} | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `SettingController@edit` | GET /admin/setting/{setting}/edit | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `SettingController@index` | GET /admin/setting | can:Setting-Payment_Method | SHOP-1 |
| `SettingController@show` | GET /admin/setting/{setting} | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `SettingController@store` | POST /admin/setting | can:Setting-Payment_Method | empty method in the web (no behaviour) — nothing to build |
| `SettingController@update` | PUT\|PATCH /admin/setting/{setting} | can:Setting-Payment_Method | SHOP-1a (general) + SHOP-1b (contact) |
| `ShopcloseController@GetTableData` | POST /admin/shop-closures-action | — (login only) | SHOP-3 (list) |
| `ShopcloseController@create` | GET /admin/shop-closures/create | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | empty method in the web (no behaviour) — nothing to build |
| `ShopcloseController@destroy` | DELETE /admin/shop-closures/{shop_closure} | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | SHOP-3 (delete) |
| `ShopcloseController@edit` | GET /admin/shop-closures/{shop_closure}/edit | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | empty method in the web (no behaviour) — nothing to build |
| `ShopcloseController@index` | GET /admin/shop-closures | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | PAGE (HTML only) → data via SHOP-3 |
| `ShopcloseController@show` | GET /admin/shop-closures/{shop_closure} | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | empty method in the web (no behaviour) — nothing to build |
| `ShopcloseController@store` | POST /admin/shop-closures | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | SHOP-3 (create) |
| `ShopcloseController@update` | PUT\|PATCH /admin/shop-closures/{shop_closure} | canany:Shop_Closures-Add,Shop_Closures-Edit,Shop_Closures-Delete | SHOP-3 (update) |
| `SlotController@create` | GET /admin/slot/create | canany:Slot-Update | empty method in the web (no behaviour) — nothing to build |
| `SlotController@destroy` | DELETE /admin/slot/{slot} | canany:Slot-Update | empty method in the web (no behaviour) — nothing to build |
| `SlotController@edit` | GET /admin/slot/{slot}/edit | canany:Slot-Update | empty method in the web (no behaviour) — nothing to build |
| `SlotController@index` | GET /admin/slot | canany:Slot-Update | SHOP-2 (read) |
| `SlotController@show` | GET /admin/slot/{slot} | canany:Slot-Update | empty method in the web (no behaviour) — nothing to build |
| `SlotController@store` | POST /admin/slot | canany:Slot-Update | SHOP-2 (save) |
| `SlotController@update` | PUT\|PATCH /admin/slot/{slot} | canany:Slot-Update | SHOP-2 (save; duplicate of store) |
| `StaffController@AppointmentGetTableData` | POST /admin/staff-profile-appointment-action | — (login only) | STAFF-6 |
| `StaffController@AssignServicesGetTableData` | POST /admin/staff-profile-service-assign-action | — (login only) | STAFF-5 |
| `StaffController@DailyEarningGetTableData` | POST /admin/staff-profile-daily-earning-action | — (login only) | STAFF-4 |
| `StaffController@GetTableData` | POST /admin/staff-action | — (login only) | STAFF-1 |
| `StaffController@changePassword` | POST /admin/change-password | — (login only) | STAFF-10 (self: AUTH-9) |
| `StaffController@create` | GET /admin/staff/create | canany:Staff-Add,Staff-Edit,Staff-Delete | empty method in the web (no behaviour) — nothing to build |
| `StaffController@destroy` | DELETE /admin/staff/{staff} | canany:Staff-Add,Staff-Edit,Staff-Delete | STAFF-9 |
| `StaffController@edit` | GET /admin/staff/{staff}/edit | canany:Staff-Add,Staff-Edit,Staff-Delete | empty method in the web (no behaviour) — nothing to build |
| `StaffController@getStaffByService` | GET /admin/getstaffByService | — (login only) | APPT-10 |
| `StaffController@index` | GET /admin/staff | canany:Staff-Add,Staff-Edit,Staff-Delete | PAGE (HTML only) → data via STAFF-2 |
| `StaffController@show` | GET /admin/staff/{staff} | canany:Staff-Add,Staff-Edit,Staff-Delete | empty method in the web (no behaviour) — nothing to build |
| `StaffController@staff_profile` | GET /admin/staff-profile/{id} | — (login only) | STAFF-3 |
| `StaffController@store` | POST /admin/staff | canany:Staff-Add,Staff-Edit,Staff-Delete | STAFF-7 |
| `StaffController@update` | PUT\|PATCH /admin/staff/{staff} | canany:Staff-Add,Staff-Edit,Staff-Delete | STAFF-8 |
| `StaffServiceController@GetTableData` | POST /admin/staff-service-action | — (login only) | STAFF-1 (barber filter) |
| `StaffServiceController@assignServices` | POST /admin/staff-service/save | — (login only) | STAFF-12 |
| `StaffServiceController@getAssignedServices` | POST /admin/staff-service/get-services | — (login only) | STAFF-11 |
| `StaffServiceController@index` | GET /admin/staff-service | canany:Staff-Add,Staff-Edit,Staff-Delete | PAGE (HTML only) → data via STAFF-11 |
| `StaffreportController@AssignServicesGetTableData` | POST /admin/staff-report-assign-service | staff only · can:Report-View | ME-5 |
| `StaffreportController@DailyEarningGetTableData` | POST /admin/staff-report-earning | staff only · can:Report-View | ME-4 |
| `StaffreportController@getAppointmentsTableData` | POST /admin/staff-report-appointment | staff only · can:Report-View | ME-6 |
| `StaffreportController@index` | GET /admin/staff-report | staff only · can:Report-View | ME-3 |
| `TestimonialController@destroy` | DELETE /admin/testimonial/{id} | can:Testimonial-Delete | CONT-1 (delete) |
| `TestimonialController@getTableData` | POST /admin/testimonial/gettabledata | — (login only) | CONT-1 (list) |
| `TestimonialController@index` | GET /admin/testimonial | canany:Testimonial-Add,Testimonial-Edit,Testimonial-Delete | PAGE (HTML only) → data via CONT-1 |
| `TestimonialController@store` | POST /admin/testimonial | can:Testimonial-Add | CONT-1 (create) |
| `TestimonialController@update` | PUT /admin/testimonial/{id} | can:Testimonial-Edit | CONT-1 (update) |
| `WorkinghoursController@create` | GET /admin/working-hour/create | staff only · can:Calender-View | empty method in the web (no behaviour) — nothing to build |
| `WorkinghoursController@destroy` | DELETE /admin/working-hour/{working_hour} | staff only · can:Calender-View | ME-10 |
| `WorkinghoursController@edit` | GET /admin/working-hour/{working_hour}/edit | staff only · can:Calender-View | empty method in the web (no behaviour) — nothing to build |
| `WorkinghoursController@index` | GET /admin/working-hour | staff only · can:Calender-View | ME-7 |
| `WorkinghoursController@show` | GET /admin/working-hour/{working_hour} | staff only · can:Calender-View | empty method in the web (no behaviour) — nothing to build |
| `WorkinghoursController@store` | POST /admin/working-hour | staff only · can:Calender-View | ME-8 |
| `WorkinghoursController@update` | PUT\|PATCH /admin/working-hour/{working_hour} | staff only · can:Calender-View | ME-9 |
| `WorkinghoursController@updateFullDayOffStaff` | POST /admin/working-hour/full-day-off-staff | — (login only) | ME-11 |
| `Auth/AuthController@RoleAssignSuperAdmin` | GET /admin/assign-role-super-admin | — (login only) | 🚫 developer helper that hard-codes user 2 / role 4; never exposed |
| `Auth/AuthController@index` | GET /admin/login | — (login only) | PAGE (login form) → AUTH-1 |
| `Auth/AuthController@logout` | POST /admin/logout | — (login only) | AUTH-3 ✅ |
| `Auth/AuthController@postLogin` | POST /admin/post-login | — (login only) | AUTH-1 ✅ |
| `Auth/ForgotPasswordController@resendOtp` | POST /admin/forgot-password/resend-otp | throttle:forgot-password-resend | AUTH-7 |
| `Auth/ForgotPasswordController@resetPassword` | POST /admin/forgot-password/reset-password | throttle:forgot-password | AUTH-8 |
| `Auth/ForgotPasswordController@sendOtp` | POST /admin/forgot-password | throttle:forgot-password | AUTH-5 |
| `Auth/ForgotPasswordController@showForgotForm` | GET /admin/forgot-password | — (login only) | PAGE → AUTH-5 |
| `Auth/ForgotPasswordController@showResetForm` | GET /admin/forgot-password/reset-password | — (login only) | PAGE → AUTH-8 |
| `Auth/ForgotPasswordController@showVerifyOtp` | GET /admin/forgot-password/verify-otp | — (login only) | PAGE → AUTH-6 |
| `Auth/ForgotPasswordController@verifyOtp` | POST /admin/forgot-password/verify-otp | throttle:forgot-password-otp | AUTH-6 |
| `Closure` | GET //<br>GET /about<br>GET /barbers<br>(+6) | — (login only) | 🚫 closures: public pages (`/`, `/home`, `/about`, `/services`, `/barbers`, `/contact`) and dev utilities (`/cache-clear`, `/storage-link`, `/mail`) |
| `GalleryController@destroy` | DELETE /admin/gallery/{id} | — (login only) | CONT-2 (delete) |
| `GalleryController@getTableData` | POST /admin/gallery/gettabledata | — (login only) | CONT-2 (list) |
| `GalleryController@index` | GET /admin/gallery | — (login only) | PAGE (HTML only) → data via CONT-2 |
| `GalleryController@store` | POST /admin/gallery | — (login only) | CONT-2 (add) |
| `GalleryController@update` | PUT /admin/gallery/{id} | — (login only) | CONT-2 (replace image; description write is broken in web, Q14) |
| `Illuminate/Routing/RedirectController` | GET\|POST\|PUT\|PATCH\|DELETE\|OPTIONS /gallery | — (login only) | 🚫 `/gallery` redirect on the public site |
| `SeoAdminController@dashboard` | GET /seo/admin/dashboard | EnsureSeoAdminAuthenticated | 🚫 SEO admin (separate tool) — out of scope |
| `SeoAdminController@login` | POST /seo/admin/login | throttle:5,1 | 🚫 SEO admin (separate tool) — out of scope |
| `SeoAdminController@logout` | POST /seo/admin/logout | EnsureSeoAdminAuthenticated | 🚫 SEO admin (separate tool) — out of scope |
| `SeoAdminController@page` | GET /seo/admin/page/{pageKey} | EnsureSeoAdminAuthenticated | 🚫 SEO admin (separate tool) — out of scope |
| `SeoAdminController@savePage` | POST /seo/admin/page/{pageKey} | EnsureSeoAdminAuthenticated | 🚫 SEO admin (separate tool) — out of scope |
| `SeoAdminController@showLogin` | GET /seo/admin | — (login only) | 🚫 SEO admin (separate tool) — out of scope |
| `Web/TrackingController@index` | GET /track-booking | — (login only) | 🚫 public website / customer side — out of scope |
| `Web/TrackingController@search` | POST /track-booking/search | — (login only) | 🚫 public website / customer side — out of scope |
| `Web/TrackingController@show` | GET /track-booking/{code} | — (login only) | 🚫 public website / customer side — out of scope |
| `Web/WebsiteController@get_appointment_details` | POST /get-appointment-details | — (login only) | 🚫 public route (customer confirm screen) |
| `Web/WebsiteController@get_slot_by_staff` | POST /get-slot-by-staff | — (login only) | 🚫 public route; its method is **reused internally** by APPT-7 |
| `Web/WebsiteController@get_staff_service` | POST /get-staff-service | — (login only) | 🚫 public route; logic mirrored by APPT-10 |
| `Web/WebsiteController@index` | GET /book | — (login only) | 🚫 public website / customer side — out of scope |
| `Web/WebsiteController@submit_appointment_details` | POST /submit-appointment-details | — (login only) | 🚫 public website / customer side — out of scope |

<!-- ROUTE_COVERAGE_END -->
