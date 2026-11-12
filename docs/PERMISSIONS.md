# Permissions in the app: the rules

Goal: a user is **never shown something they cannot use**. If the server would answer 403, the control is not on the screen at all
(hide, do not grey out: they have no way to get the permission from the app). The server still enforces everything; the 403 handler
and the live refresh (`docs/HARDENING_PLAN.md` Phase B) are only the safety net.

## Where permissions live
* `lib/features/auth/domain/perm.dart`: every permission name, once (`Perm.serviceAdd`...). No loose strings anywhere else.
* `AuthUser` (`auth_user.dart`): `can(Perm.x)`, `canAny([...])` and **named questions** for actions that need more than one
  permission or a rule (`canCreateInvoice`, `canMailInvoice`, `canCompleteBooking`, `canSeeStaffServices`...).
* `AuthUser.modules` (from the server): whether a whole module/screen is available. A module flag is true for ANY of
  Add / Edit / Delete, so it is **not** enough for a button or a form: use the specific permission.
* `lib/features/shell/nav_model.dart`: `allowedFor` (router guard, also deep links and the back stack). Form routes (`/new`, `/edit/:id`)
  need the Add / Edit permission, not just the module.

## Adding a screen or a button
1. Find what the API asks for: `bash tool/live/export_permission_contract.sh`, then look the route up in `test/fixtures/api_permissions.json`.
2. Show the control only when `user.can(...)` (or a named question) says the server will accept it.
3. If the route needs several permissions or a rule, add a named getter on `AuthUser` (with a comment saying what the server asks).
4. Add a test with a user that lacks it: the control is **absent** (`find...findsNothing`), see `test/features/pos/invoices_test.dart`
   ("Invoice actions follow the permissions") and `route_guard_test.dart`.

## What the contract test guards (`test/permissions_contract_test.dart`)
* every `Perm` name exists on the server (a typo would silently hide a button);
* every permission the server stores (and every one a write route asks for) is known to the app: a new server permission fails the build until it is added;
* every Add / Edit / Delete the server enforces is used by some screen (no button that can only fail);
* no screen writes a permission as a string, or calls `can('...')`.
Re-export the fixture when the web project adds or renames permissions or routes.

## Known server quirks
`Pos_invoice-Show_All` and `Gallery-Edit` are asked for by routes but are not stored (WEB_DEV_FIXES Q67).
