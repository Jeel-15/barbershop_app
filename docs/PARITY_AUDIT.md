# Web vs App parity audit

Source of truth: `rosen_barber/routes/web.php` (admin group) + the blade views.
Legend: ✅ done · 🟡 partly · ❌ not built yet (API exists unless noted).

| # | Web page (route) | App | Notes / gaps |
|---|---|---|---|
| 1 | Dashboard (`dashboard`, today/upcoming/top-services/staff-performance) | ✅ | Hero money, overview tiles + filters, next-up, Staff Calendar block, Today's / Upcoming, Top Services, Top Product. Staff-performance block: 🟡 (earnings only on Me page, not built yet) |
| 2 | Appointments list (`appointment`, filters, search, counts) | ✅ | Filter: Date / Day Type / Staff Name; tabs by status |
| 3 | Appointment actions (confirm / reject / complete / reschedule / cancel) | ✅ | Status matrix from `/bootstrap` |
| 4 | Add / Update Appointment (`appointMentBook`, get-staff-by-service, slots) | ✅ | Staff, Date, Select Time always visible; custom time; Make Payment in edit |
| 5 | Calendar (`incalender`, fetch, staff-availability, break) | ✅ | Day grid, lanes, closed hours, now line, Break, Filter by Staff, tap-slot-to-book. Staff column order: drag in the Staff sheet (kept on the phone). |
| 6 | Invoice list (`invoice`) | ✅ | Newest first, search (invoice no / name / phone), paged; Add Invoice by permission; staff only see what the server allows |
| 7 | Invoice create (`invoice/create`, `getCustomer`) | ✅ | Services + products, staff per line, preview, idempotent submit, complete-from-appointment, phone lookup (from 10 digits) |
| 8 | Invoice view / edit / email / PDF print | ✅ | View Invoice receipt (services, discounts, tax, tip, total), Edit Invoice (same form, Update), Send Invoice Mail (asks for an address when the customer has none), Print + Download PDF (real A4 PDF) |
| 9 | Customers list / add / edit / delete (`customers`) | ✅ | Search, Add/Update modal (web fields + messages), Delete confirm; buttons by Customer-Add/Edit/Delete |
| 10 | Customer profile (`customer-profile`, appointments table) | ✅ | Name, email, phone, member since, Total Visits, appointments list; Call / Message / Copy. Total Spent left out (web Q35) |
| 11 | Staff list / add / edit / delete / change-password (`staff`) | ✅ | Search, Add / Update Staff (all web fields + messages, Accountant hides barber fields), Delete confirm, Change Password |
| 12 | Staff profile (appointments, assigned services, daily earning) | ✅ | Cards + tabs Appointments (Start / End Date) / Assign Services / Earnings |
| 13 | Staff Service assignment (`staff-service`) | ✅ | "Assign Services" in the row / profile menu (barbers), Save Assignments |
| 14 | Working Hours (`working-hour`, full-day-off) — staff only | ✅ | Day cards, + Add, Day Off switch, Total Working Hours, edit / delete, Quick select + Custom time, overlap message |
| 15 | Staff Report (`staff-report`: appointments, services, earning) | ✅ | Earning cards, Reports Filter (Start / End / Status), tabs Appointments / Service Earning / Daily Earning. Staff see only their own numbers |
| 16 | Service Category (`service-category`) | ✅ | List + search, Add / Update sheet (name, image, description), Delete |
| 17 | Service (`service`, home-section toggle) | ✅ | List + search, Add / Update (all web fields), Website Section, Delete |
| 18 | Product (`product`) | ✅ | List + search, Add / Update (all web fields), Delete |
| 19 | GST (`gst`) | ✅ | List with Default mark, Add / Update (name, rate, Include/Exclude, Default), Delete |
| 20 | Payment Method (`payment-method`, `setting`) | ✅ | Payment Options list, Add / Update / Delete (inside Settings) |
| 21 | Slot (shop hours, `slot`) | ✅ | Day cards: Day Off, Shop Open / Close Time; breaks kept as they are (the web page has no break editor) |
| 22 | Shop Closures (`shop-closures`) | ✅ | List + search, Add / Update (Date, Full Day Closure, Start / End Time, Reason), Delete |
| 23 | Roles & Permissions (`roles`, role permissions) | ✅ | Roles list (users / permissions count, System mark), Add / Edit form with grouped permissions and Administrator Access (Select All), Delete |
| 24 | Reports: appointment, payment, staff performance, customer invoices, product sell, top-selling product | ✅ | One Reports page: Reports Filter (Start / End Date, Staff Name), 4 headline cards, tabs Earning / Payment Methods / Staff / Invoice / Product / Top Selling Products |
| 25 | Testimonials (`testimonial`) | ✅ | List + search, Add / Update (name, title, review, rating, order, Show on website, photo), Delete |
| 26 | Gallery (`gallery`, image upload) | ✅ | Picture grid, Add Image (upload), open + Delete |
| 27 | My Profile (`profile`) | ✅ | Hero, Assigned Services, stats (staff), Edit Profile (Name, Email, Phone, Role, Profile Photo upload) |
| 28 | Auth (login, logout, forgot password) | ✅ | |

## Out of scope on purpose
SEO admin (`/seo-admin`) and the public website booking (`get-slot-by-staff`, `submit-appointment-details`): not admin/staff features.

## Build order (proposal)
1. Customers (list/profile/add/edit/delete) + phone lookup in Create Invoice
2. Invoices (list/detail/edit/email/PDF)
3. Me / Staff Report + My Profile + Working Hours (what staff use daily)
4. Staff admin + Staff Service + Roles
5. Catalog: Category, Service, Product, GST, Payment Method
6. Settings: Slot, Shop Closures
7. Reports (6)
8. Testimonials, Gallery
9. Hardening (overflow/offline review, release)


Settings (General Settings, Contact Details, Payment Options) are done too; the web's "Change Password" tab is commented out there, so the app has none.