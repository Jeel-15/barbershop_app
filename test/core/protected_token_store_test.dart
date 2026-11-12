import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:barbershop_app/core/storage/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A vault in memory that counts the prompts it would have opened.
class _FakeVault implements BiometricVault {
  String? stored;
  int saves = 0;
  int reads = 0;
  VaultException? failNext;

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<bool> hasToken() async => stored != null;

  @override
  Future<void> save(String token) async {
    saves++;
    _maybeFail();
    stored = token;
  }

  @override
  Future<String?> read() async {
    reads++;
    _maybeFail();
    return stored;
  }

  @override
  Future<void> delete() async => stored = null;
}

/// The pieces one phone keeps between launches: the open store, the vault, the flag.
class _Phone {
  final plain = MemoryTokenStore();
  final vault = _FakeVault();
  bool flag = false;

  /// A new "launch": empty memory, same disk.
  ProtectedTokenStore launch() => ProtectedTokenStore(
    plain: plain,
    vault: vault,
    readProtected: () => flag,
    writeProtected: (v) async => flag = v,
  );
}

void main() {
  group('feature off', () {
    test('behaves like the plain store and never opens a prompt', () async {
      final p = _Phone();
      final s = p.launch();
      await s.write('tok');
      expect(await s.read(), 'tok');
      expect(await p.plain.read(), 'tok');
      expect(p.vault.saves + p.vault.reads, 0);
      expect(s.isProtected, isFalse);
    });
  });

  group('protect', () {
    test(
      'moves the token into the vault: one prompt, open copy gone',
      () async {
        final p = _Phone();
        final s = p.launch();
        await s.write('tok');
        await s.protect();

        expect(s.isProtected, isTrue);
        expect(p.vault.stored, 'tok');
        expect(p.vault.saves, 1);
        expect(await p.plain.read(), isNull); // nothing left in the open
        // The running app keeps working from memory: no prompt per request.
        expect(await s.read(), 'tok');
        expect(await s.read(), 'tok');
        expect(p.vault.reads, 0);
      },
    );

    test('a cancelled prompt changes nothing', () async {
      final p = _Phone();
      final s = p.launch();
      await s.write('tok');
      p.vault.failNext = const VaultException(VaultFailure.cancelled);

      await expectLater(s.protect(), throwsA(isA<VaultException>()));
      expect(s.isProtected, isFalse);
      expect(await p.plain.read(), 'tok');
      expect(await s.read(), 'tok');
    });

    test('with no signed-in token it refuses', () async {
      final s = _Phone().launch();
      await expectLater(s.protect(), throwsA(isA<StateError>()));
    });
  });

  group('a new launch of a protected phone', () {
    Future<_Phone> protectedPhone() async {
      final p = _Phone();
      final first = p.launch();
      await first.write('tok');
      await first.protect();
      return p;
    }

    test('has no token and opens no prompt until it is unlocked', () async {
      final p = await protectedPhone();
      final s = p.launch();
      expect(s.isProtected, isTrue);
      expect(await s.read(), isNull);
      expect(p.vault.reads, 0);
    });

    test(
      'unlock gives the token once, then it is served from memory',
      () async {
        final p = await protectedPhone();
        final s = p.launch();
        expect(await s.unlock(), 'tok');
        expect(await s.read(), 'tok');
        expect(await s.read(), 'tok');
        expect(p.vault.reads, 1);
      },
    );

    test('a failed unlock leaves the store locked', () async {
      final p = await protectedPhone();
      final s = p.launch();
      p.vault.failNext = const VaultException(VaultFailure.lockedOut);
      await expectLater(s.unlock(), throwsA(isA<VaultException>()));
      expect(await s.read(), isNull);
    });
  });

  group('unprotect', () {
    test('needs the token in memory (unlock first)', () async {
      final p = _Phone();
      final first = p.launch();
      await first.write('tok');
      await first.protect();
      final later = p.launch();
      await expectLater(later.unprotect(), throwsA(isA<StateError>()));
    });

    test('puts the token back in the open and empties the vault', () async {
      final p = _Phone();
      final s = p.launch();
      await s.write('tok');
      await s.protect();
      await s.unprotect();

      expect(s.isProtected, isFalse);
      expect(p.vault.stored, isNull);
      expect(await p.plain.read(), 'tok');
      // The next launch opens straight away, with no prompt.
      final next = p.launch();
      expect(await next.read(), 'tok');
      expect(p.vault.reads, 0);
    });
  });

  group('clear (sign out / session ended)', () {
    test('wipes the open copy, the vault, the flag and the memory', () async {
      final p = _Phone();
      final s = p.launch();
      await s.write('tok');
      await s.protect();
      await s.clear();

      expect(await s.read(), isNull);
      expect(p.vault.stored, isNull);
      expect(await p.plain.read(), isNull);
      expect(p.flag, isFalse);
    });
  });

  group('what the phone says, in our words', () {
    PlatformException android(String message) =>
        PlatformException(code: 'Exception encountered', message: message);

    test('cancelled: closed the prompt, pressed the button, cancelled', () {
      for (final n in [5, 10, 13]) {
        expect(
          VaultException.fromPlatform(
            android('Biometric authentication error [$n]: cancelled'),
          ).failure,
          VaultFailure.cancelled,
          reason: '$n',
        );
      }
    });

    test('lock-out, temporary and permanent', () {
      for (final n in [7, 9]) {
        expect(
          VaultException.fromPlatform(
            android('Biometric authentication error [$n]: too many attempts'),
          ).failure,
          VaultFailure.lockedOut,
        );
      }
    });

    test('nothing to use: no hardware, none enrolled, no screen lock', () {
      for (final n in [1, 11, 12, 14]) {
        expect(
          VaultException.fromPlatform(
            android('Biometric authentication error [$n]: nothing'),
          ).failure,
          VaultFailure.notAvailable,
          reason: '$n',
        );
      }
      expect(
        VaultException.fromPlatform(
          android('BIOMETRIC_UNAVAILABLE: requires Android 9'),
        ).failure,
        VaultFailure.notAvailable,
      );
    });

    test(
      'a key the phone destroyed (new fingerprint, screen lock removed)',
      () {
        for (final m in [
          'android.security.keystore.KeyPermanentlyInvalidatedException',
          'Key permanently invalidated',
          'java.security.InvalidKeyException: Key user not authenticated',
          'javax.crypto.AEADBadTagException',
        ]) {
          expect(
            VaultException.fromPlatform(android(m)).failure,
            VaultFailure.invalidated,
            reason: m,
          );
        }
      },
    );

    test('anything else is unknown, never a crash', () {
      expect(
        VaultException.fromPlatform(android('something odd')).failure,
        VaultFailure.unknown,
      );
      expect(
        VaultException.fromPlatform(StateError('x')).failure,
        VaultFailure.unknown,
      );
    });
  });
}
