import 'package:barbershop_app/core/router/app_router.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
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
      expect(u.canSell, isTrue);
    });

    test('staff without calendar/sale sees home, bookings, me', () {
      final u = staffBootstrap().user;
      expect(u.visibleTabs, [AppTab.home, AppTab.appointments, AppTab.more]);
      expect(u.moreLabel, 'Me');
      expect(u.canSell, isFalse);
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
}
