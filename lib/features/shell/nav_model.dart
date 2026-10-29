import 'package:barbershop_app/features/auth/domain/auth_user.dart';

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

  /// Centre action of the bar.
  bool get canSell => modules.invoiceWrite;
}

/// Permission guard for the router: may this user open this location?
bool allowedFor(AuthUser user, String location) {
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
