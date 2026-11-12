import 'package:barbershop_app/core/router/app_router.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';
import 'package:barbershop_app/features/shell/nav_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';

void main() {
  final admin = SignedIn(adminBootstrap());
  final staff = SignedIn(staffBootstrap());

  group('guardRedirect', () {
    test('while loading everything waits at the splash', () {
      expect(guardRedirect(const SessionLoading(), '/'), isNull);
      expect(guardRedirect(const SessionLoading(), '/sign-in'), '/');
      expect(guardRedirect(const SessionLoading(), '/app/home'), '/');
    });

    test('signed out: public pages open, app pages go to Sign in', () {
      for (final p in ['/', '/welcome', '/sign-in', '/forgot']) {
        expect(guardRedirect(const SignedOut(), p), isNull, reason: p);
      }
      expect(guardRedirect(const SignedOut(), '/app/home'), '/sign-in');
      expect(guardRedirect(const SignedOut(), '/app/appointments'), '/sign-in');
    });

    test('signed in: auth pages bounce to the app', () {
      for (final p in ['/', '/welcome', '/sign-in', '/forgot']) {
        expect(guardRedirect(admin, p), '/app/home', reason: p);
      }
      expect(guardRedirect(admin, '/app/home'), isNull);
    });

    test('permission guard follows modules, not roles', () {
      expect(guardRedirect(admin, '/app/calendar'), isNull);
      expect(guardRedirect(admin, '/app/invoice/new'), isNull);
      expect(guardRedirect(staff, '/app/calendar'), '/app/home');
      expect(guardRedirect(staff, '/app/invoice/new'), '/app/home');
      expect(guardRedirect(staff, '/app/appointments'), isNull);
    });

    test('update required traps every location', () {
      const u = UpdateRequired(
        current: AppVersion(1, 0, 0),
        minimum: AppVersion(2, 0, 0),
        latest: AppVersion(2, 0, 0),
      );
      expect(guardRedirect(u, '/app/home'), '/update');
      expect(guardRedirect(u, '/update'), isNull);
    });
  });

  group('tabs', () {
    test('admin sees home, bookings, calendar, more and can sell', () {
      final u = adminBootstrap().user;
      expect(u.visibleTabs, [
        AppTab.home,
        AppTab.appointments,
        AppTab.calendar,
        AppTab.more,
      ]);
      expect(u.moreLabel, 'More');
      expect(u.canCreateInvoice, isTrue);
    });

    test('staff without calendar/sale sees home, bookings, me', () {
      final u = staffBootstrap().user;
      expect(u.visibleTabs, [AppTab.home, AppTab.appointments, AppTab.more]);
      expect(u.moreLabel, 'Me');
      expect(u.canCreateInvoice, isFalse);
    });
  });

  group('AppVersion', () {
    test('compares numerically, not as text', () {
      expect(AppVersion.parse('1.10.0') >= AppVersion.parse('1.9.0'), isTrue);
      expect(AppVersion.parse('1.0.0+5') == const AppVersion(1, 0, 0), isTrue);
      expect(AppVersion.parse('0.9.9') < AppVersion.parse('1.0.0'), isTrue);
      expect(AppVersion.parse('garbage'), const AppVersion(0, 0, 0));
    });
  });

  group('a fingerprint-locked session', () {
    test('only the unlock screen is reachable, nothing else loads', () {
      const locked = SessionLocked(name: 'API Admin');
      expect(guardRedirect(locked, '/lock'), isNull);
      for (final p in [
        '/',
        '/welcome',
        '/sign-in',
        '/app/home',
        '/app/invoices',
      ]) {
        expect(guardRedirect(locked, p), '/lock', reason: p);
      }
    });

    test('signed out or in, the lock screen is never kept', () {
      expect(guardRedirect(const SignedOut(), '/lock'), '/sign-in');
      expect(guardRedirect(admin, '/lock'), '/app/home');
    });
  });

  group('forms and actions need their own permission', () {
    // The module flag is true for any of Add / Edit / Delete; a form needs its own.
    SignedIn with_(List<String> perms) =>
        SignedIn(Bootstrap.fromJson(bootstrapJson(permissions: perms)));

    test('invoice: new and complete need Add, edit needs Edit', () {
      final addOnly = with_(const [Perm.posInvoiceAdd]);
      final editOnly = with_(const [Perm.posInvoiceEdit]);
      expect(guardRedirect(addOnly, '/app/invoice/new'), isNull);
      expect(guardRedirect(addOnly, '/app/invoice/complete/9'), isNull);
      expect(guardRedirect(addOnly, '/app/invoice/edit/9'), '/app/home');

      expect(guardRedirect(editOnly, '/app/invoice/new'), '/app/home');
      expect(guardRedirect(editOnly, '/app/invoice/complete/9'), '/app/home');
      expect(guardRedirect(editOnly, '/app/invoice/edit/9'), isNull);
    });

    test(
      'a user who can only edit cannot open the New form (and the reverse)',
      () {
        final editOnly = with_(const [Perm.serviceEdit, Perm.productAdd]);
        expect(guardRedirect(editOnly, '/app/services/edit/3'), isNull);
        expect(guardRedirect(editOnly, '/app/services/new'), '/app/home');
        expect(guardRedirect(editOnly, '/app/products/new'), isNull);
        expect(guardRedirect(editOnly, '/app/products/edit/3'), '/app/home');
      },
    );

    test('every form route is covered', () {
      final none = with_(const []);
      for (final p in [
        'services',
        'products',
        'testimonials',
        'roles',
        'staff',
      ]) {
        expect(guardRedirect(none, '/app/$p/new'), '/app/home', reason: p);
        expect(guardRedirect(none, '/app/$p/edit/1'), '/app/home', reason: p);
      }
    });

    test('the named questions match what the server asks', () {
      final viewer = with_(const [Perm.posInvoiceShowAll]).bootstrap.user;
      expect(viewer.canCreateInvoice, isFalse);
      expect(viewer.canMailInvoice, isFalse);
      expect(viewer.canCompleteBooking, isFalse);

      final editor = with_(const [Perm.posInvoiceEdit]).bootstrap.user;
      expect(editor.canCreateInvoice, isFalse); // the bar's + needs Add
      expect(editor.canCompleteBooking, isFalse);
      expect(editor.canMailInvoice, isTrue);
      expect(editor.canEditInvoice, isTrue);
    });
  });
}
