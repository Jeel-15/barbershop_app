import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';

void main() {
  group('cold start', () {
    test('no saved token -> signed out, no network call', () async {
      final h = await AuthHarness.create();
      expect(await h.settle(), isA<SignedOut>());
      expect(h.repo.calls, isEmpty);
    });

    test('saved token -> bootstrap -> signed in with permissions', () async {
      final h = await AuthHarness.create(savedToken: 'abc');
      final s = await h.settle();
      expect(s, isA<SignedIn>());
      final user = (s as SignedIn).bootstrap.user;
      expect(user.name, 'API Admin');
      expect(user.modules.invoiceWrite, isTrue);
      expect(s.offline, isFalse);
    });

    test(
      'dead token (401) -> signed out with a message and token cleared',
      () async {
        final repo = FakeAuthRepository()
          ..bootstrapFailure = const UnauthorizedFailure();
        final h = await AuthHarness.create(repo: repo, savedToken: 'old');
        final s = await h.settle();
        expect(s, isA<SignedOut>());
        expect((s as SignedOut).message, contains('session has ended'));
        expect(await h.tokens.read(), isNull);
      },
    );

    test('offline with a saved copy -> signed in offline', () async {
      final h = await AuthHarness.create(savedToken: 'abc');
      await h.settle(); // online start saves the copy
      final repo = FakeAuthRepository()
        ..bootstrapFailure = const NetworkFailure();
      final again = await AuthHarness.create(
        repo: repo,
        savedToken: 'abc',
        prefs: h.prefsSnapshot(),
      );
      final s = await again.settle();
      expect(s, isA<SignedIn>());
      expect((s as SignedIn).offline, isTrue);
    });

    test(
      'offline with nothing saved -> signed out with the network message',
      () async {
        final repo = FakeAuthRepository()
          ..bootstrapFailure = const NetworkFailure();
        final h = await AuthHarness.create(repo: repo, savedToken: 'abc');
        final s = await h.settle();
        expect(s, isA<SignedOut>());
        expect((s as SignedOut).message, contains('No connection'));
      },
    );

    test('server needs a newer app -> UpdateRequired', () async {
      final repo = FakeAuthRepository()
        ..bootstrapResult = Bootstrap.fromJson(
          bootstrapJson(minVersion: '2.0.0', latestVersion: '2.1.0'),
        );
      final h = await AuthHarness.create(repo: repo, savedToken: 'abc');
      final s = await h.settle();
      expect(s, isA<UpdateRequired>());
      expect((s as UpdateRequired).latest, const AppVersion(2, 1, 0));
    });
  });

  group('sign in / out', () {
    test('success stores token and last e-mail, ends signed in', () async {
      final h = await AuthHarness.create();
      await h.settle();
      await h.container
          .read(sessionControllerProvider.notifier)
          .signIn(email: ' apitest.admin@rosen.test ', password: 'x');
      expect(h.container.read(sessionControllerProvider), isA<SignedIn>());
      expect(await h.tokens.read(), 'tok-123');
      expect(h.repo.calls, contains('login: apitest.admin@rosen.test '));
    });

    test('wrong password throws the failure and stays signed out', () async {
      final repo = FakeAuthRepository()
        ..loginFailure = const UnauthorizedFailure(
          'Invalid email or password.',
        );
      final h = await AuthHarness.create(repo: repo);
      await h.settle();
      await expectLater(
        h.container
            .read(sessionControllerProvider.notifier)
            .signIn(email: 'a@b.co', password: 'bad'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(h.container.read(sessionControllerProvider), isA<SignedOut>());
      expect(await h.tokens.read(), isNull);
    });

    test('token without launch data is not kept', () async {
      final repo = FakeAuthRepository()
        ..bootstrapFailure = const ServerFailure();
      final h = await AuthHarness.create(repo: repo);
      await h.settle();
      await expectLater(
        h.container
            .read(sessionControllerProvider.notifier)
            .signIn(email: 'a@b.co', password: 'x'),
        throwsA(isA<ServerFailure>()),
      );
      expect(await h.tokens.read(), isNull);
    });

    test(
      'sign out forgets token and cached data even if the server is unreachable',
      () async {
        final h = await AuthHarness.create(savedToken: 'abc');
        await h.settle();
        await h.container.read(sessionControllerProvider.notifier).signOut();
        expect(h.container.read(sessionControllerProvider), isA<SignedOut>());
        expect(await h.tokens.read(), isNull);
        expect(h.repo.calls, contains('logout'));
      },
    );

    test(
      'a 401 anywhere (expire) returns to signed out with a message',
      () async {
        final h = await AuthHarness.create(savedToken: 'abc');
        await h.settle();
        h.container.read(sessionControllerProvider.notifier).expire();
        final s = h.container.read(sessionControllerProvider);
        expect(s, isA<SignedOut>());
        expect((s as SignedOut).message, isNotNull);
      },
    );
  });
}
