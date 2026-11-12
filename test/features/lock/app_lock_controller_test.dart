import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:barbershop_app/features/lock/domain/lock_timeout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/lock_fixtures.dart';

/// A signed-in app whose session is locked behind the fingerprint.
class _Lock {
  _Lock(this.h, this.c, this.clock, this.timers);

  final AuthHarness h;
  final AppLockController c;
  final FakeClock clock;
  final List<ManualTimer> timers;

  AppLockState get state => h.container.read(appLockProvider);
  SessionState get session => h.container.read(sessionControllerProvider);
  ManualTimer? get armed {
    final live = timers.where((t) => t.isActive);
    return live.isEmpty ? null : live.last;
  }

  Future<void> away(Duration d) async {
    c.onPaused();
    clock.advance(d);
    c.onResumed();
  }
}

Future<_Lock> _ready({
  LockTimeout timeout = LockTimeout.fiveMinutes,
  bool protect = true,
}) async {
  final h = await AuthHarness.create(savedToken: 'abc');
  await h.settle();
  if (protect) await h.tokens.protect();
  await h.container.read(lockTimeoutProvider.notifier).set(timeout);
  final c = h.container.read(appLockProvider.notifier);
  final clock = FakeClock();
  final timers = <ManualTimer>[];
  c.clock = clock.call;
  c.timerFactory = (d, cb) {
    final t = ManualTimer(d, cb);
    timers.add(t);
    return t;
  };
  c.timeoutChanged(); // what Settings does after a change
  return _Lock(h, c, clock, timers);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('leaving and returning to the app', () {
    test('with the feature off nothing ever locks', () async {
      final l = await _ready(protect: false);
      await l.away(const Duration(hours: 3));
      expect(l.state.locked, isFalse);
      l.c.onInactive();
      expect(l.state.covered, isFalse);
    });

    test('back within the time: no lock', () async {
      final l = await _ready();
      await l.away(const Duration(minutes: 2));
      expect(l.state.locked, isFalse);
    });

    test('back after the time (or exactly on it): locked', () async {
      final l = await _ready();
      await l.away(const Duration(minutes: 5));
      expect(l.state.locked, isTrue);

      final m = await _ready(timeout: LockTimeout.oneMinute);
      await m.away(const Duration(minutes: 6));
      expect(m.state.locked, isTrue);
    });

    test('"immediately" locks on every return', () async {
      final l = await _ready(timeout: LockTimeout.immediately);
      await l.away(const Duration(seconds: 1));
      expect(l.state.locked, isTrue);
    });

    test('a clock set back is no way round the lock', () async {
      final l = await _ready();
      l.c.onPaused();
      l.clock.advance(const Duration(hours: -2));
      l.c.onResumed();
      expect(l.state.locked, isTrue);
    });

    test(
      'a short blip with no real pause (the phone prompt) never locks',
      () async {
        final l = await _ready();
        l.c.onInactive();
        expect(l.state.covered, isTrue);
        l.clock.advance(const Duration(hours: 1));
        l.c.onResumed();
        expect(l.state.covered, isFalse);
        expect(l.state.locked, isFalse);
      },
    );

    test('the cover is not shown over the lock panel itself', () async {
      final l = await _ready();
      l.c.lock();
      l.c.onInactive();
      expect(l.state.covered, isFalse);
    });
  });

  group('inactivity while the app is open', () {
    test(
      'a timer of the chosen length is armed and locks when it fires',
      () async {
        final l = await _ready(timeout: LockTimeout.oneMinute);
        expect(l.armed!.duration, const Duration(minutes: 1));
        l.armed!.fire();
        expect(l.state.locked, isTrue);
      },
    );

    test(
      'a touch starts the count again; touches within a second are ignored',
      () async {
        final l = await _ready();
        final first = l.armed!;
        l.clock.advance(const Duration(seconds: 30));
        l.c.touch();
        expect(first.cancelled, isTrue);
        final second = l.armed!;
        expect(second, isNot(same(first)));

        l.clock.advance(const Duration(milliseconds: 300));
        l.c.touch(); // too soon after the last one
        expect(l.armed, same(second));
      },
    );

    test(
      '"immediately" has no inactivity timer (the screen in use never locks)',
      () async {
        final l = await _ready(timeout: LockTimeout.immediately);
        expect(l.armed, isNull);
        l.c.touch();
        expect(l.armed, isNull);
      },
    );

    test('leaving the app stops the count; locking stops it too', () async {
      final l = await _ready();
      final t = l.armed!;
      l.c.onPaused();
      expect(t.cancelled, isTrue);

      final m = await _ready();
      m.c.lock();
      expect(m.armed, isNull);
    });

    test('with the feature off no timer is armed', () async {
      final l = await _ready(protect: false);
      expect(l.armed, isNull);
    });
  });

  group('unlocking the open app', () {
    test(
      'success clears the lock, opens one prompt and re-arms the count',
      () async {
        final l = await _ready();
        l.c.lock();
        await l.c.unlock();

        expect(l.state.locked, isFalse);
        expect(l.h.tokens.prompts, 2); // 1 to turn it on, 1 to unlock
        expect(l.armed, isNotNull);
      },
    );

    test('a second tap while the prompt is open is ignored', () async {
      final l = await _ready();
      l.c.lock();
      final first = l.c.unlock();
      final second = l.c.unlock();
      await Future.wait([first, second]);
      expect(l.h.tokens.prompts, 2);
    });

    test(
      'cancelling says nothing; the third miss offers the password',
      () async {
        final l = await _ready();
        l.c.lock();
        l.h.tokens.unlockError = const VaultException(VaultFailure.cancelled);

        await l.c.unlock();
        expect(l.state.locked, isTrue);
        expect(l.state.failures, 1);
        expect(l.state.message, isNull);
        expect(l.state.inTrouble, isFalse);

        await l.c.unlock();
        await l.c.unlock();
        expect(l.state.failures, 3);
        expect(l.state.inTrouble, isTrue);
      },
    );

    test('a lock-out and any other miss get a calm sentence', () async {
      final l = await _ready();
      l.c.lock();
      l.h.tokens.unlockError = const VaultException(VaultFailure.lockedOut);
      await l.c.unlock();
      expect(l.state.message, contains('Too many tries'));

      l.h.tokens.unlockError = const VaultException(VaultFailure.unknown);
      await l.c.unlock();
      expect(l.state.message, contains('did not work'));
    });

    test('a destroyed key ends the session and explains why', () async {
      final l = await _ready();
      l.c.lock();
      l.h.tokens.unlockError = const VaultException(VaultFailure.invalidated);
      await l.c.unlock();

      final s = l.session;
      expect(s, isA<SignedOut>());
      expect(
        (s as SignedOut).message,
        contains('fingerprints or screen lock changed'),
      );
      expect(await l.h.tokens.read(), isNull);
      expect(l.h.tokens.isProtected, isFalse);
      expect(l.state.locked, isFalse); // the sign-in screen takes over
    });

    test(
      '"Use password instead" signs this phone out on the server too',
      () async {
        final l = await _ready();
        l.c.lock();
        await l.c.usePassword();
        expect(l.session, isA<SignedOut>());
        expect(l.h.repo.calls, contains('logout'));
        expect(await l.h.tokens.read(), isNull);
      },
    );
  });

  group('launching a fingerprint-locked phone', () {
    Future<AuthHarness> locked({Map<String, Object> prefs = const {}}) async {
      final h = await AuthHarness.create(savedToken: 'abc', prefs: prefs);
      h.tokens.lockForColdStart();
      return h;
    }

    test('waits at the lock and asks the server nothing', () async {
      final h = await locked();
      expect(await h.settle(), isA<SessionLocked>());
      expect(h.repo.calls, isEmpty);
    });

    test('unlocking loads the launch data and opens the app', () async {
      final h = await locked();
      await h.settle();
      await h.container.read(appLockProvider.notifier).unlock();
      expect(h.container.read(sessionControllerProvider), isA<SignedIn>());
      expect(h.repo.calls, ['bootstrap']);
    });

    test(
      'a cancelled prompt leaves it locked, with the network untouched',
      () async {
        final h = await locked();
        await h.settle();
        h.tokens.unlockError = const VaultException(VaultFailure.cancelled);
        await h.container.read(appLockProvider.notifier).unlock();

        expect(
          h.container.read(sessionControllerProvider),
          isA<SessionLocked>(),
        );
        expect(h.container.read(appLockProvider).failures, 1);
        expect(h.repo.calls, isEmpty);
      },
    );

    test('a destroyed key signs out with the reason', () async {
      final h = await locked();
      await h.settle();
      h.tokens.unlockError = const VaultException(VaultFailure.invalidated);
      await h.container.read(appLockProvider.notifier).unlock();

      final s = h.container.read(sessionControllerProvider);
      expect(s, isA<SignedOut>());
      expect((s as SignedOut).message, contains('changed'));
      expect(await h.tokens.read(), isNull);
    });

    test(
      'a token the server no longer accepts: unlocked, then signed out',
      () async {
        final repo = FakeAuthRepository()
          ..bootstrapFailure = const UnauthorizedFailure();
        final h = await AuthHarness.create(repo: repo, savedToken: 'abc');
        h.tokens.lockForColdStart();
        await h.settle();
        await h.container.read(appLockProvider.notifier).unlock();

        final s = h.container.read(sessionControllerProvider);
        expect(s, isA<SignedOut>());
        expect((s as SignedOut).message, contains('session has ended'));
        expect(h.tokens.isProtected, isFalse);
      },
    );

    test(
      '"Use password instead" forgets the phone without a server call',
      () async {
        final h = await locked();
        await h.settle();
        await h.container.read(appLockProvider.notifier).usePassword();

        expect(h.container.read(sessionControllerProvider), isA<SignedOut>());
        expect(h.repo.calls, isNot(contains('logout')));
        expect(await h.tokens.read(), isNull);
      },
    );

    test('greets by name from the saved launch data', () async {
      final first = await AuthHarness.create(savedToken: 'abc');
      await first.settle(); // online start saves the copy
      final h = await locked(prefs: first.prefsSnapshot());
      final s = await h.settle();
      expect(s, isA<SessionLocked>());
      expect((s as SessionLocked).name, 'API Admin');
      expect(s.roleLabel, 'Admin');
    });
  });

  group('signing in with the password', () {
    test('starts clean: a leftover fingerprint lock is cleared', () async {
      final h = await AuthHarness.create();
      await h.settle();
      h.tokens.lockForColdStart(); // an old session's leftover
      await h.container
          .read(sessionControllerProvider.notifier)
          .signIn(email: 'a@b.co', password: 'x');

      expect(h.tokens.isProtected, isFalse);
      expect(await h.tokens.read(), 'tok-123');
    });

    test(
      'the offer appears when the phone can do it and it is not on yet',
      () async {
        final h = await AuthHarness.create(
          extra: [
            biometricCapabilityProvider.overrideWithValue(
              FakeCapability(BiometricKind.fingerprint),
            ),
          ],
        );
        await h.settle();
        await h.container
            .read(sessionControllerProvider.notifier)
            .signIn(email: 'a@b.co', password: 'x');
        await h.settle();
        expect(h.container.read(biometricOfferProvider), isTrue);
      },
    );

    test('no offer on a phone without a screen lock', () async {
      final h = await AuthHarness.create(
        extra: [
          biometricCapabilityProvider.overrideWithValue(
            FakeCapability(BiometricKind.none),
          ),
        ],
      );
      await h.settle();
      await h.container
          .read(sessionControllerProvider.notifier)
          .signIn(email: 'a@b.co', password: 'x');
      await h.settle();
      expect(h.container.read(biometricOfferProvider), isFalse);
    });

    test('the offer stops after two "Not now"', () async {
      final h = await AuthHarness.create(
        extra: [
          biometricCapabilityProvider.overrideWithValue(
            FakeCapability(BiometricKind.fingerprint),
          ),
        ],
      );
      await h.settle();
      final setup = h.container.read(biometricSetupProvider);
      await setup.declineOffer();
      expect(await setup.shouldOffer(), isTrue);
      await setup.declineOffer();
      expect(await setup.shouldOffer(), isFalse);
    });
  });

  group('turning it on and off', () {
    test('on: one prompt; the token is protected', () async {
      final h = await AuthHarness.create(savedToken: 'abc');
      await h.settle();
      final setup = h.container.read(biometricSetupProvider);
      expect(await setup.enable(), EnableOutcome.enabled);
      expect(setup.enabled, isTrue);
    });

    test('a closed prompt: nothing changes, nothing to say', () async {
      final h = await AuthHarness.create(savedToken: 'abc');
      await h.settle();
      h.tokens.unlockError = const VaultException(VaultFailure.cancelled);
      final setup = h.container.read(biometricSetupProvider);
      expect(await setup.enable(), EnableOutcome.cancelled);
      expect(setup.enabled, isFalse);
    });

    test('no screen lock / lock-out are told apart', () async {
      final h = await AuthHarness.create(savedToken: 'abc');
      await h.settle();
      final setup = h.container.read(biometricSetupProvider);
      h.tokens.unlockError = const VaultException(VaultFailure.notAvailable);
      expect(await setup.enable(), EnableOutcome.notAvailable);
      h.tokens.unlockError = const VaultException(VaultFailure.lockedOut);
      expect(await setup.enable(), EnableOutcome.failed);
    });

    test('off needs no prompt and keeps the session', () async {
      final h = await AuthHarness.create(savedToken: 'abc');
      await h.settle();
      final setup = h.container.read(biometricSetupProvider);
      await setup.enable();
      final before = h.tokens.prompts;
      await setup.disable();
      expect(setup.enabled, isFalse);
      expect(h.tokens.prompts, before);
      expect(await h.tokens.read(), 'abc');
    });
  });

  test('the lock time is kept and falls back to five minutes', () async {
    final h = await AuthHarness.create();
    expect(h.container.read(lockTimeoutProvider), LockTimeout.fiveMinutes);
    await h.container
        .read(lockTimeoutProvider.notifier)
        .set(LockTimeout.fifteenMinutes);
    expect(h.container.read(appPrefsProvider).lockTimeoutSeconds, 900);
    expect(LockTimeout.fromSeconds(123), LockTimeout.fiveMinutes);
  });
}
