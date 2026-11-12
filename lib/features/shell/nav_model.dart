import 'package:barbershop_app/features/auth/domain/auth_user.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

/// The four fixed branches of the shell, in route order. Which of them show
/// in the bar is decided from the server's `modules` flags, not from roles.
enum AppTab { home, appointments, calendar, more }

extension AppTabVisibility on AuthUser {
  bool showsTab(AppTab tab) => switch (tab) {
    AppTab.home || AppTab.more => true,
    AppTab.appointments => modules.appointments,
    AppTab.calendar => modules.calendar,
  };

  List<AppTab> get visibleTabs => [
    for (final t in AppTab.values)
      if (showsTab(t)) t,
  ];

  /// Staff see their own space; the owner sees the whole menu.
  String get moreLabel => isStaff ? 'Me' : 'More';
}

/// Form pages by list path. The module flag is true for any of Add / Edit /
/// Delete, so a form needs its own permission: `new` the Add one, `edit/:id`
/// the Edit one (the server asks for exactly these when the form is saved).
const _formRoutes = <String, ({String add, String edit})>{
  '/app/services': (add: Perm.serviceAdd, edit: Perm.serviceEdit),
  '/app/products': (add: Perm.productAdd, edit: Perm.productEdit),
  '/app/testimonials': (add: Perm.testimonialAdd, edit: Perm.testimonialEdit),
  '/app/roles': (add: Perm.roleAdd, edit: Perm.roleEdit),
  '/app/staff': (add: Perm.staffAdd, edit: Perm.staffEdit),
  '/app/invoice': (add: Perm.posInvoiceAdd, edit: Perm.posInvoiceEdit),
};

/// Permission guard for the router: may this user open this location?
bool allowedFor(AuthUser user, String location) {
  // Completing a booking makes its invoice: the same permission as a new one.
  if (location.startsWith('/app/invoice/complete/')) {
    return user.canCreateInvoice;
  }
  for (final entry in _formRoutes.entries) {
    if (location == '${entry.key}/new') return user.can(entry.value.add);
    if (location.startsWith('${entry.key}/edit/')) {
      return user.can(entry.value.edit);
    }
  }
  if (location.startsWith('/app/appointments')) {
    return user.modules.appointments;
  }
  if (location.startsWith('/app/calendar') ||
      location.startsWith('/app/appointment/')) {
    return user.modules.calendar;
  }
  // Reading invoices (list, one invoice) vs. writing them (new, edit, complete).
  if (location.startsWith('/app/invoices') ||
      RegExp(r'^/app/invoice/\d+$').hasMatch(location)) {
    return user.modules.invoices;
  }
  if (location.startsWith('/app/invoice')) return user.modules.invoiceWrite;
  if (location.startsWith('/app/customer')) return user.modules.customers;
  if (location.startsWith('/app/staff')) {
    // The list and forms are for Staff-Add/Edit/Delete; one profile is also open to the member.
    return user.modules.staff || RegExp(r'^/app/staff/\d+$').hasMatch(location);
  }
  if (location.startsWith('/app/services')) return user.modules.services;
  if (location.startsWith('/app/service-categories')) {
    return user.modules.serviceCategories;
  }
  if (location.startsWith('/app/products')) return user.modules.products;
  if (location.startsWith('/app/gst')) return user.modules.gst;
  if (location.startsWith('/app/payment-methods')) {
    return user.modules.paymentMethods;
  }
  if (location.startsWith('/app/roles')) return user.modules.roles;
  if (location.startsWith('/app/settings')) return user.modules.settings;
  if (location.startsWith('/app/slots')) return user.modules.slots;
  if (location.startsWith('/app/shop-closures')) {
    return user.modules.shopClosures;
  }
  if (location.startsWith('/app/profile')) return user.modules.profile;
  if (location.startsWith('/app/testimonials')) {
    return user.modules.testimonials;
  }
  if (location.startsWith('/app/gallery')) return user.modules.gallery;
  if (location.startsWith('/app/reports')) return user.modules.reports;
  if (location.startsWith('/app/report')) return user.modules.staffReport;
  if (location.startsWith('/app/working-hours')) {
    return user.modules.workingHours;
  }
  return true;
}
