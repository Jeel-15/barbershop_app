import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';

Bootstrap _boot({
  String version = 'v1',
  Map<String, bool>? modules,
  List<String> permissions = const ['appointments.view'],
  String name = 'API Admin',
}) {
  final j = bootstrapJson(
    permissions: permissions,
    modules: modules,
    name: name,
  );
  (j['user'] as Map)['permissions_version'] = version;
  j['server_time'] = DateTime.now().toIso8601String();
  return Bootstrap.fromJson(j);
}

/// A signed-in harness whose clock the test moves.
Future<(AuthHarness, SessionController, _Clock)> _signedIn({
  Bootstrap? first,
}) async {
  final repo = FakeAuthRepository()..bootstrapResult = first ?? _boot();
  final h = await AuthHarness.create(repo: repo, savedToken: 'abc');
  // The clock must be in place before the cold start runs (it stamps the time).
  final session = h.container.read(sessionControllerProvider.notifier);
  final clock = _Clock();
  session.clock = clock.call;
  await h.settle();
  return (h, session, clock);
}

class _Clock {
  DateTime now = DateTime(2026, 10, 29, 9);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

int _bootstrapCalls(AuthHarness h) =>
    h.repo.calls.where((c) => c == 'bootstrap').length;

void main() {
  test('the version travels with the user', () async {
    final (h, _, _) = await _signedIn(first: _boot(version: 'abc'));
    final s = h.container.read(sessionControllerProvider) as SignedIn;
    expect(s.bootstrap.user.permissionsVersion, 'abc');
  });

  group('a different version from the server', () {
    test('re-reads /bootstrap and the new access replaces the old', () async {
      final (h, session, clock) = await _signedIn();
      expect(_bootstrapCalls(h), 1);

      h.repo.bootstrapResult = _boot(
        version: 'v2',
        modules: {'invoices': false, 'invoice_write': false},
      );
      clock.advance(const Duration(seconds: 10));
      session.onServerPermissionsVersion('v2');
      await h.settle();

      expect(_bootstrapCalls(h), 2);
      final s = h.container.read(sessionControllerProvider) as SignedIn;
      expect(s.bootstrap.user.modules.invoices, isFalse);
      expect(s.bootstrap.user.permissionsVersion, 'v2');
      expect(h.container.read(accessNoticeProvider), 1);
    });

    test('the same version as the one held does nothing', () async {
      final (h, session, clock) = await _signedIn();
      clock.advance(const Duration(minutes: 5));
      session.onServerPermissionsVersion('v1');
      await h.settle();
      expect(_bootstrapCalls(h), 1);
    });

    test('many requests showing it at once cause ONE refresh', () async {
      final (h, session, clock) = await _signedIn();
      h.repo.bootstrapResult = _boot(version: 'v2', permissions: const []);
      clock.advance(const Duration(seconds: 10));
      for (var i = 0; i < 12; i++) {
        session.onServerPermissionsVersion('v2');
      }
      await h.settle();
      expect(_bootstrapCalls(h), 2);
    });

    test(
      'a refresh asked for within 3 seconds of the last is dropped',
      () async {
        final (h, session, clock) = await _signedIn();
        h.repo.bootstrapResult = _boot(version: 'v2', permissions: const []);
        clock.advance(const Duration(seconds: 10));
        session.onServerPermissionsVersion('v2');
        await h.settle();
        expect(_bootstrapCalls(h), 2);

        // A late answer still shows an even newer version, but too soon after.
        clock.advance(const Duration(seconds: 1));
        session.onServerPermissionsVersion('v3');
        await h.settle();
        expect(_bootstrapCalls(h), 2);

        clock.advance(const Duration(seconds: 3));
        session.onServerPermissionsVersion('v3');
        await h.settle();
        expect(_bootstrapCalls(h), 3);
      },
    );
  });

  group('a refused request (403)', () {
    test('refreshes, even though the version is unknown', () async {
      final (h, session, clock) = await _signedIn();
      clock.advance(const Duration(seconds: 10));
      session.onForbidden();
      await h.settle();
      expect(_bootstrapCalls(h), 2);
    });
  });

  group('coming back to the app', () {
    test('at most once a minute', () async {
      final (h, session, clock) = await _signedIn();

      clock.advance(const Duration(seconds: 59));
      session.onResume();
      await h.settle();
      expect(_bootstrapCalls(h), 1);

      clock.advance(const Duration(seconds: 2));
      session.onResume();
      await h.settle();
      expect(_bootstrapCalls(h), 2);

      clock.advance(const Duration(seconds: 30));
      session.onResume();
      await h.settle();
      expect(_bootstrapCalls(h), 2);
    });

    test('signed out: nothing is called', () async {
      final h = await AuthHarness.create();
      await h.settle();
      final session = h.container.read(sessionControllerProvider.notifier);
      session.onResume();
      session.onForbidden();
      await h.settle();
      expect(_bootstrapCalls(h), 0);
    });
  });

  group('a refresh that goes wrong stays quiet', () {
    test('no connection: still signed in, not offline, no note', () async {
      final (h, session, clock) = await _signedIn();
      h.repo.bootstrapFailure = const NetworkFailure();
      clock.advance(const Duration(seconds: 10));
      session.onForbidden();
      await h.settle();

      final s = h.container.read(sessionControllerProvider) as SignedIn;
      expect(s.offline, isFalse);
      expect(h.container.read(accessNoticeProvider), 0);
    });

    test('a server error changes nothing', () async {
      final (h, session, clock) = await _signedIn();
      final before = h.container.read(sessionControllerProvider);
      h.repo.bootstrapFailure = const ServerFailure();
      clock.advance(const Duration(seconds: 10));
      session.onForbidden();
      await h.settle();
      expect(h.container.read(sessionControllerProvider), same(before));
    });

    test('a failed refresh is not retried within the 3 seconds', () async {
      final (h, session, clock) = await _signedIn();
      h.repo.bootstrapFailure = const NetworkFailure();
      clock.advance(const Duration(seconds: 10));
      session.onForbidden();
      await h.settle();
      session.onForbidden();
      await h.settle();
      expect(_bootstrapCalls(h), 2);
    });
  });

  group('nothing changed', () {
    test(
      'the state is not replaced, so open screens are not rebuilt',
      () async {
        final (h, session, clock) = await _signedIn();
        final before = h.container.read(sessionControllerProvider);
        // Same data, only the server clock differs.
        clock.advance(const Duration(seconds: 10));
        session.onForbidden();
        await h.settle();
        expect(_bootstrapCalls(h), 2);
        expect(h.container.read(sessionControllerProvider), same(before));
        expect(h.container.read(accessNoticeProvider), 0);
      },
    );

    test('a change of something other than access updates quietly', () async {
      final (h, session, clock) = await _signedIn();
      h.repo.bootstrapResult = _boot(); // same access
      final raw = Map<String, dynamic>.of(h.repo.bootstrapResult!.raw);
      raw['shop'] = {'name': 'Rosenthal Barbershop', 'phone': '555'};
      h.repo.bootstrapResult = Bootstrap.fromJson(raw);
      clock.advance(const Duration(seconds: 10));
      session.onForbidden();
      await h.settle();

      final s = h.container.read(sessionControllerProvider) as SignedIn;
      expect(s.bootstrap.shop.phone, '555');
      expect(h.container.read(accessNoticeProvider), 0);
    });
  });

  test('a dead token found by the refresh ends the session', () async {
    final (h, session, clock) = await _signedIn();
    h.repo.bootstrapFailure = const UnauthorizedFailure();
    clock.advance(const Duration(seconds: 10));
    // The network layer calls expire() on a 401; the refresh itself stays silent.
    session.onForbidden();
    await h.settle();
    session.expire();
    expect(h.container.read(sessionControllerProvider), isA<SignedOut>());
  });

  group('AuthUser.sameAccessAs', () {
    test('ignores name changes, sees permission and module changes', () {
      final a = _boot().user;
      expect(a.sameAccessAs(_boot(name: 'Renamed').user), isTrue);
      expect(a.sameAccessAs(_boot(permissions: const []).user), isFalse);
      expect(a.sameAccessAs(_boot(modules: {'reports': false}).user), isFalse);
    });
  });
}
