Rosenthal mobile API (Admin + Staff app) - additive patch. Nothing in the existing web code is edited.
Build: Phase 0 + 1 + 2 + 3 + 4 + 5 = ALL planned APIs (foundation, auth, forgot-password, dashboard, appointments, profile,
       slot finder, book/edit/reschedule, calendar, breaks, own working hours,
       customers, dashboard top lists, staff earnings report, POS and invoices,
       services/categories/products/GST/payment methods, shop settings/hours/closures, staff administration, admin reports, testimonials, gallery, roles).
See ../docs/API_PLAN.md for the full plan (Sections 14-19 = what exists and how it was verified).

NEW FILES (copy as-is, keeping folders):
  app/Http/Controllers/Api/V1/*.php   ApiController, AuthController, PasswordResetController, BootstrapController,
                                      HealthController, FallbackController, DashboardController, AppointmentController,
                                      ProfileController, ModuleAccess, CalendarController,
                                      WorkingHoursController, CustomerController, StaffReportController,
                                      PosController, InvoiceController, CatalogController, ShopController, StaffController, ReportController,
                                      ContentController, RoleController
  app/Http/Middleware/Api/*.php       ForceJson, ApiRequestLog, ApiEnvelope, ApiAuthenticate, ApiRateLimit, RequirePermission, RequireStaff, RequireNotStaff
  app/Services/Api/*.php              UserPresenter, Money, AppointmentReader, AppointmentActions, DashboardReader,
                                      SlotGuard, SlotEngine, Media, AppointmentBooking, CalendarReader,
                                      CalendarBreaks, WorkingHours, CustomerService, DashboardLists, StaffReport, PosService, CatalogAdmin, ShopAdmin, StaffAdmin,
                                      ReportAdmin, ContentAdmin, RoleAdmin
  config/api_v1.php

ONE EDIT (append, never overwrite):
  routes/api.php  -> paste the contents of routes_api_append.php.txt at the BOTTOM.
  If the live routes/api.php has other routes, keep them and only add this block.

NO new composer packages. Laravel Sanctum is already in composer.lock.
Do NOT copy .env or bootstrap/cache/*.php between machines.

LIVE DATABASE MUST HAVE: personal_access_tokens, password_reset_otps,
  tbl_appointment.invoice_created_by (the web code already needs the last two).
  Check with:  GET /api/v1/health   (schema_ok must be true)

TESTS (node 20+, run against a LOCAL copy, never against live data):
  tools/api_smoke.js                     Phase 0 foundation (15 checks)
  tools/parity_phase1.js                 API vs web, same numbers (50 checks)       needs the APITEST-* test appointments
  tools/api_phase1_test.js               behaviour, permissions, scope (24 checks)  needs the APITEST-* test appointments
  tools/phase1_password_reset_test.php   forgot-password flow with a FAKE mailer (24 checks)
  tools/parity_phase2.js                 calendar/slots/availability API vs web (19 checks)
  tools/api_phase2_test.js               booking/edit/reschedule/breaks/working hours + write parity (38 checks)
  tools/parity_phase3a.js                customers, profile, dashboard top lists, staff report API vs web (17 checks)
  tools/api_phase3a_test.js              customer create/edit/delete + write parity (7 checks)
  tools/api_phase3b_test.js              POS totals vs the web page formulas, invoice create/edit write parity,
                                         visibility, idempotency, validation (26 checks)
  tools/phase3b_invoice_mail_test.php    invoice emails with a FAKE mailer, never a real mail (9 checks)
  tools/phase3b_complete_test.php        "complete appointment into invoice" behind its feature flag (6 checks)
  tools/api_phase4a_test.js              catalog + shop admin: read parity, write parity, images, restore of shared data (22 checks)
  tools/api_phase4b_test.js              staff admin: profile parity, create/edit/delete parity, role-escalation block, sessions (17 checks)
  tools/api_phase5_test.js               admin reports parity (4 filter sets), testimonials, gallery, roles (14 checks)
  Usage and arguments are at the top of each file.

ROLLBACK: delete the Api folders, app/Services/Api, config/api_v1.php and the appended route block.

FEATURE FLAGS (config/api_v1.php):
  complete_from_appointment = false   APPT-11 stays off until the web developer fixes the web (Q5).
