import 'package:barbershop_app/core/config/env.dart';
import 'package:barbershop_app/features/appointments/application/booking_form_controller.dart';
import 'package:barbershop_app/features/appointments/presentation/appointments_page.dart';
import 'package:barbershop_app/features/appointments/presentation/booking_form_page.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:barbershop_app/features/auth/presentation/sign_in_screen.dart';
import 'package:barbershop_app/features/auth/presentation/update_required_screen.dart';
import 'package:barbershop_app/features/calendar/presentation/calendar_page.dart';
import 'package:barbershop_app/features/calendar/presentation/landscape_calendar_page.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/product_form_page.dart';
import 'package:barbershop_app/features/catalog/presentation/products_page.dart';
import 'package:barbershop_app/features/catalog/presentation/service_form_page.dart';
import 'package:barbershop_app/features/catalog/presentation/services_page.dart';
import 'package:barbershop_app/features/catalog/presentation/simple_catalog_pages.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:barbershop_app/features/content/presentation/gallery_page.dart';
import 'package:barbershop_app/features/content/presentation/testimonials_page.dart';
import 'package:barbershop_app/features/customers/presentation/customer_profile_page.dart';
import 'package:barbershop_app/features/customers/presentation/customers_page.dart';
import 'package:barbershop_app/features/dev/connection_screen.dart';
import 'package:barbershop_app/features/dev/gallery_screen.dart';
import 'package:barbershop_app/features/lock/presentation/lock_screen.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:barbershop_app/features/me/presentation/staff_report_page.dart';
import 'package:barbershop_app/features/me/presentation/working_hours_page.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_detail_page.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_form_page.dart';
import 'package:barbershop_app/features/pos/presentation/invoices_page.dart';
import 'package:barbershop_app/features/reports/presentation/reports_page.dart';
import 'package:barbershop_app/features/roles/presentation/role_form_page.dart';
import 'package:barbershop_app/features/roles/presentation/roles_page.dart';
import 'package:barbershop_app/features/shell/app_shell.dart';
import 'package:barbershop_app/features/shop/presentation/closures_page.dart';
import 'package:barbershop_app/features/shop/presentation/settings_page.dart';
import 'package:barbershop_app/features/shop/presentation/slots_page.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:barbershop_app/features/staff/presentation/staff_form_page.dart';
import 'package:barbershop_app/features/staff/presentation/staff_page.dart';
import 'package:barbershop_app/features/staff/presentation/staff_profile_page.dart';
import 'package:barbershop_app/features/home/presentation/home_page.dart';
import 'package:barbershop_app/features/shell/more_page.dart';
import 'package:barbershop_app/features/shell/nav_model.dart';
import 'package:barbershop_app/features/shell/placeholder_page.dart';
import 'package:barbershop_app/features/welcome/presentation/splash_screen.dart';
import 'package:barbershop_app/features/welcome/presentation/welcome_screen.dart';
import 'package:barbershop_app/features/shell/animated_branches.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Pages a signed-out person may see.
const _publicPaths = {'/', '/welcome', '/sign-in', '/forgot'};

/// The route guard, kept apart from the router so it can be tested on its own.
/// Returns the location to go to instead, or null to stay.
String? guardRedirect(SessionState session, String location) {
  switch (session) {
    case SessionLoading():
      return location == '/' ? null : '/';
    case UpdateRequired():
      return location == '/update' ? null : '/update';
    case SessionLocked():
      // A fingerprint-locked session: only the unlock screen, nothing else loads.
      return location == '/lock' ? null : '/lock';
    case SignedOut():
      if (location == '/update') return '/welcome';
      return _publicPaths.contains(location) || location.startsWith('/dev/')
          ? null
          : '/sign-in';
    case SignedIn(:final bootstrap):
      if (location == '/update' ||
          location == '/lock' ||
          _publicPaths.contains(location)) {
        return '/app/home';
      }
      if (!allowedFor(bootstrap.user, location)) return '/app/home';
      return null;
  }
}

/// Route table: public pages, the guarded shell under `/app`, dev tools.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (previous, next) {
    // Only a change of kind (or of permissions) can move the user.
    if (previous.runtimeType != next.runtimeType || next is SignedIn) {
      refresh.value++;
    }
  });

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) =>
        guardRedirect(ref.read(sessionControllerProvider), state.uri.path),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          // The crest flies from the splash into this screen (Hero) while it fades in.
          transitionDuration: const Duration(milliseconds: 1100),
          child: const WelcomeScreen(),
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween(begin: 1.07, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/forgot',
        builder: (context, state) => ForgotPasswordScreen(
          initialEmail: state.extra is String ? state.extra! as String : null,
        ),
      ),
      GoRoute(path: '/lock', builder: (context, state) => const LockScreen()),
      GoRoute(
        path: '/update',
        builder: (context, state) => const UpdateRequiredScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        // Same as an indexed stack, plus a fade when the tab changes.
        navigatorContainerBuilder: (context, shell, children) =>
            AnimatedBranches(navigationShell: shell, children: children),
        // Branch order = AppTab order.
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/appointments',
                builder: (context, state) => const AppointmentsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/calendar',
                builder: (context, state) => const CalendarPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/more',
                builder: (context, state) => const MorePage(),
              ),
            ],
          ),
        ],
      ),
      // The day as one wide landscape view (turns the phone, no tab bar).
      GoRoute(
        path: '/app/calendar/landscape',
        builder: (context, state) => const LandscapeCalendarPage(),
      ),
      // The calendar's Add Appointment / Update Appointment form.
      GoRoute(
        path: '/app/appointment/new',
        builder: (context, state) => BookingFormPage(
          target: BookingTarget(
            staffId: int.tryParse(state.uri.queryParameters['staff'] ?? ''),
            date: state.uri.queryParameters['date'],
            time: state.uri.queryParameters['time'],
          ),
        ),
      ),
      GoRoute(
        path: '/app/appointment/edit/:id',
        builder: (context, state) => BookingFormPage(
          target: BookingTarget(
            editId: int.tryParse(state.pathParameters['id'] ?? ''),
            staffId: int.tryParse(state.uri.queryParameters['staff'] ?? ''),
          ),
        ),
      ),
      // The web's invoice wizard: blank (Create Invoice) or for an appointment (Complete).
      GoRoute(
        path: '/app/invoice/new',
        builder: (context, state) => const InvoiceFormPage(),
      ),
      // The web's Invoices list, View Invoice and Edit Invoice.
      GoRoute(
        path: '/app/invoices',
        builder: (context, state) => const InvoicesPage(),
      ),
      GoRoute(
        path: '/app/invoice/:id',
        builder: (context, state) => InvoiceDetailPage(
          invoiceId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/app/invoice/edit/:id',
        builder: (context, state) => InvoiceFormPage(
          invoiceId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/app/invoice/complete/:id',
        builder: (context, state) => InvoiceFormPage(
          appointmentId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      // The web's Customers list and Customer Profile.
      GoRoute(
        path: '/app/customers',
        builder: (context, state) => const CustomersPage(),
      ),
      GoRoute(
        path: '/app/customer/:id',
        builder: (context, state) => CustomerProfilePage(
          customerId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      // The web's Catalog: Services, Service Category, Product, GST, Payment Options.
      GoRoute(
        path: '/app/services',
        builder: (context, state) => const ServicesPage(),
      ),
      GoRoute(
        path: '/app/services/new',
        builder: (context, state) => const ServiceFormPage(),
      ),
      GoRoute(
        path: '/app/services/edit/:id',
        builder: (context, state) => ServiceFormPage(
          editId: int.tryParse(state.pathParameters['id'] ?? ''),
          service: state.extra is AdminService
              ? state.extra! as AdminService
              : null,
        ),
      ),
      GoRoute(
        path: '/app/service-categories',
        builder: (context, state) => const CategoriesPage(),
      ),
      GoRoute(
        path: '/app/products',
        builder: (context, state) => const ProductsPage(),
      ),
      GoRoute(
        path: '/app/products/new',
        builder: (context, state) => const ProductFormPage(),
      ),
      GoRoute(
        path: '/app/products/edit/:id',
        builder: (context, state) => ProductFormPage(
          editId: int.tryParse(state.pathParameters['id'] ?? ''),
          product: state.extra is AdminProduct
              ? state.extra! as AdminProduct
              : null,
        ),
      ),
      GoRoute(path: '/app/gst', builder: (context, state) => const GstPage()),
      GoRoute(
        path: '/app/payment-methods',
        builder: (context, state) => const PaymentMethodsPage(),
      ),
      // The website content: Testimonials and Gallery.
      GoRoute(
        path: '/app/testimonials',
        builder: (context, state) => const TestimonialsPage(),
      ),
      GoRoute(
        path: '/app/testimonials/new',
        builder: (context, state) => const TestimonialFormPage(),
      ),
      GoRoute(
        path: '/app/testimonials/edit/:id',
        builder: (context, state) => TestimonialFormPage(
          testimonial: state.extra is Testimonial
              ? state.extra! as Testimonial
              : null,
        ),
      ),
      GoRoute(
        path: '/app/gallery',
        builder: (context, state) => const GalleryPage(),
      ),
      // The web's Reports (admin).
      GoRoute(
        path: '/app/reports',
        builder: (context, state) => const ReportsPage(),
      ),
      // The web's Roles and the role form.
      GoRoute(
        path: '/app/roles',
        builder: (context, state) => const RolesPage(),
      ),
      GoRoute(
        path: '/app/roles/new',
        builder: (context, state) => const RoleFormPage(),
      ),
      GoRoute(
        path: '/app/roles/edit/:id',
        builder: (context, state) => RoleFormPage(
          roleId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      // The web's shop pages: Settings, Slot Configuration, Shop Closures.
      GoRoute(
        path: '/app/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/app/slots',
        builder: (context, state) => const SlotsPage(),
      ),
      GoRoute(
        path: '/app/shop-closures',
        builder: (context, state) => const ClosuresPage(),
      ),
      // The web's Staff list, Add / Update Staff and Staff Profile.
      GoRoute(
        path: '/app/staff',
        builder: (context, state) => const StaffPage(),
      ),
      GoRoute(
        path: '/app/staff/new',
        builder: (context, state) => const StaffFormPage(),
      ),
      GoRoute(
        path: '/app/staff/edit/:id',
        builder: (context, state) => StaffFormPage(
          editId: int.tryParse(state.pathParameters['id'] ?? ''),
          member: state.extra is StaffMember
              ? state.extra! as StaffMember
              : null,
        ),
      ),
      GoRoute(
        path: '/app/staff/:id',
        builder: (context, state) => StaffProfilePage(
          staffId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      // "Me": My Profile, the staff's own Report and Working Hours.
      GoRoute(
        path: '/app/profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '/app/report',
        builder: (context, state) => const StaffReportPage(),
      ),
      GoRoute(
        path: '/app/working-hours',
        builder: (context, state) => const WorkingHoursPage(),
      ),
      GoRoute(
        path: '/app/coming',
        builder: (context, state) => PlaceholderPage(
          title: state.extra as String? ?? '',
          icon: Icons.construction_rounded,
          message: 'This screen is built in a later phase.',
          padForBar: false,
        ),
      ),
      // Review tools: present in dev/staging builds, never in production.
      if (!Env.isProd) ...[
        GoRoute(
          path: '/dev/gallery',
          builder: (context, state) => const GalleryScreen(),
        ),
        GoRoute(
          path: '/dev/connection',
          builder: (context, state) => const ConnectionScreen(),
        ),
      ],
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
