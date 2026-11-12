import 'dart:async';

import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:barbershop_app/features/lock/presentation/biometric_offer.dart';
import 'package:barbershop_app/features/lock/presentation/lock_overlay.dart';
import 'package:barbershop_app/features/lock/presentation/lock_panel.dart';
import 'package:barbershop_app/features/lock/presentation/security_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/lock_fixtures.dart';
import '../../helpers/pump_app.dart';

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A signed-in app with a fingerprint-locked session and a scripted phone.
Future<AuthHarness> _signedIn(
  WidgetTester tester, {
  BiometricKind kind = BiometricKind.fingerprint,
  bool protect = false,
}) async {
  final h = await AuthHarness.create(
    savedToken: 'abc',
    extra: [
      biometricCapabilityProvider.overrideWithValue(FakeCapability(kind)),
    ],
  );
  h.container.read(sessionControllerProvider);
  await _settle(tester, 3);
  if (protect) await h.tokens.protect();
  // Timers that fire only when the test says so (a real one would outlive the test).
  h.container.read(appLockProvider.notifier).timerFactory = (d, cb) =>
      ManualTimer(d, cb);
  return h;
}

Widget _app(AuthHarness h, Widget home) => UncontrolledProviderScope(
  container: h.container,
  child: MaterialApp(theme: AppTheme.light, home: home),
);

LockPanel _panel({
  BiometricKind kind = BiometricKind.fingerprint,
  AppLockState state = const AppLockState(),
  String? name = 'API Admin',
  String? role = 'Super-admin',
  Future<void> Function()? onUnlock,
  Future<void> Function()? onUsePassword,
  bool autoPrompt = false,
}) => LockPanel(
  kind: kind,
  state: state,
  name: name,
  roleLabel: role,
  onUnlock: onUnlock ?? () async {},
  onUsePassword: onUsePassword ?? () async {},
  autoPrompt: autoPrompt,
);

void main() {
  setUpAll(loadAppFonts);

  group('the unlock panel', () {
    testWidgets('greets by first name, shows the role and the way in', (
      tester,
    ) async {
      await pumpThemed(tester, _panel(), scaffold: false);
      expect(find.text('Welcome back,'), findsOneWidget);
      expect(find.text('API'), findsOneWidget);
      expect(find.text('Super-admin'), findsOneWidget);
      expect(find.text('Unlock with fingerprint'), findsWidgets);
      expect(find.text('Use password instead'), findsOneWidget);
      expect(find.text('Locked to keep the shop safe'), findsOneWidget);
    });

    testWidgets('no name: a plain welcome', (tester) async {
      await pumpThemed(tester, _panel(name: null, role: null), scaffold: false);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('says what it will use, in the person\'s words', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        _panel(kind: BiometricKind.screenLock),
        scaffold: false,
      );
      expect(find.text('Unlock with phone screen lock'), findsWidgets);
    });

    testWidgets('opens the prompt by itself, once', (tester) async {
      var opened = 0;
      await pumpThemed(
        tester,
        _panel(autoPrompt: true, onUnlock: () async => opened++),
        scaffold: false,
      );
      expect(opened, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(opened, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(opened, 1);
    });

    testWidgets('does not open it by itself when told not to', (tester) async {
      var opened = 0;
      await pumpThemed(
        tester,
        _panel(onUnlock: () async => opened++),
        scaffold: false,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(opened, 0);
    });

    testWidgets(
      'the big button tries again; while the prompt is open it waits',
      (tester) async {
        var opened = 0;
        await pumpThemed(
          tester,
          _panel(onUnlock: () async => opened++),
          scaffold: false,
        );
        await tester.tap(find.byIcon(Icons.fingerprint_rounded));
        await tester.pump();
        expect(opened, 1);

        await pumpThemed(
          tester,
          _panel(
            state: const AppLockState(prompting: true),
            onUnlock: () async => opened++,
          ),
          scaffold: false,
        );
        await tester.pump();
        expect(find.text('Waiting for you…'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.fingerprint_rounded));
        await tester.pump();
        expect(opened, 1); // no second prompt on top of the first
      },
    );

    testWidgets(
      'a miss shows one calm sentence; three misses offer the password',
      (tester) async {
        await pumpThemed(
          tester,
          _panel(
            state: const AppLockState(
              failures: 1,
              message: 'That did not work. Try again, or use your password.',
            ),
          ),
          scaffold: false,
        );
        expect(find.byKey(const Key('lock-message')), findsOneWidget);
        expect(find.text('Having trouble?'), findsNothing);

        await pumpThemed(
          tester,
          _panel(state: const AppLockState(failures: 3)),
          scaffold: false,
        );
        await tester.pump();
        expect(find.text('Having trouble?'), findsOneWidget);
      },
    );

    testWidgets('"Use password instead" asks first, then signs out', (
      tester,
    ) async {
      var out = 0;
      await pumpThemed(
        tester,
        _panel(onUsePassword: () async => out++),
        scaffold: false,
      );
      await tester.tap(find.text('Use password instead'));
      await tester.pump();
      expect(find.byKey(const Key('lock-exit-confirm')), findsOneWidget);
      expect(out, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.byKey(const Key('lock-exit-confirm')), findsNothing);

      await tester.tap(find.text('Use password instead'));
      await tester.pump();
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(out, 1);
    });

    for (final dark in [false, true]) {
      testWidgets(
        'fits a small phone at 2x text (${dark ? 'dark' : 'light'})',
        (tester) async {
          await pumpThemed(
            tester,
            _panel(
              state: const AppLockState(
                failures: 3,
                message: 'That did not work. Try again, or use your password.',
              ),
            ),
            scaffold: false,
            size: const Size(320, 560),
            textScale: 2,
            dark: dark,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('the cover over the running app', () {
    Future<void> pumpGate(
      WidgetTester tester,
      AuthHarness h,
      void Function() onUnderlyingTap,
    ) async {
      await tester.pumpWidget(
        _app(
          h,
          LockGate(
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: onUnderlyingTap,
                  child: const Text('Underlying'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('while unlocked it is invisible and the app works', (
      tester,
    ) async {
      final h = await _signedIn(tester, protect: true);
      var taps = 0;
      await pumpGate(tester, h, () => taps++);
      expect(find.byKey(const Key('lock-overlay')), findsNothing);
      await tester.tap(find.text('Underlying'));
      expect(taps, 1);
    });

    testWidgets('locked: the panel covers everything and swallows touches', (
      tester,
    ) async {
      final h = await _signedIn(tester, protect: true);
      h.tokens.unlockError = const VaultException(VaultFailure.cancelled);
      var taps = 0;
      await pumpGate(tester, h, () => taps++);

      h.container.read(appLockProvider.notifier).lock();
      await tester.pump();
      expect(find.byKey(const Key('lock-overlay')), findsOneWidget);
      expect(find.text('Unlock with fingerprint'), findsWidgets);

      await tester.tap(find.text('Underlying'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('unlocking uncovers the app again', (tester) async {
      final h = await _signedIn(tester, protect: true);
      var taps = 0;
      await pumpGate(tester, h, () => taps++);
      h.container.read(appLockProvider.notifier).lock();
      await tester.pump();

      await h.container.read(appLockProvider.notifier).unlock();
      await tester.pump();
      expect(find.byKey(const Key('lock-overlay')), findsNothing);
      await tester.tap(find.text('Underlying'));
      expect(taps, 1);
    });

    testWidgets('leaving the screen shows the crest, not the shop\'s data', (
      tester,
    ) async {
      final h = await _signedIn(tester, protect: true);
      await pumpGate(tester, h, () {});
      h.container.read(appLockProvider.notifier).onInactive();
      await tester.pump();
      expect(find.byKey(const Key('privacy-cover')), findsOneWidget);

      h.container.read(appLockProvider.notifier).onResumed();
      await tester.pump();
      expect(find.byKey(const Key('privacy-cover')), findsNothing);
    });

    testWidgets('with the feature off there is never a cover', (tester) async {
      final h = await _signedIn(tester);
      await pumpGate(tester, h, () {});
      h.container.read(appLockProvider.notifier).onInactive();
      await tester.pump();
      expect(find.byKey(const Key('privacy-cover')), findsNothing);
    });
  });

  group('Security in More / Me', () {
    Widget page(AuthHarness h) => _app(
      h,
      Scaffold(
        body: ListView(
          children: [
            SecurityGroup(
              leading: (icon) => Icon(icon, key: const Key('row-icon')),
            ),
          ],
        ),
      ),
    );

    testWidgets('a phone without a screen lock sees nothing', (tester) async {
      final h = await _signedIn(tester, kind: BiometricKind.none);
      await tester.pumpWidget(page(h));
      await _settle(tester);
      expect(find.text('Security'), findsNothing);
    });

    testWidgets('the switch turns it on, shows the time row and says so', (
      tester,
    ) async {
      final h = await _signedIn(tester);
      await tester.pumpWidget(page(h));
      await _settle(tester);
      expect(find.text('Fingerprint unlock'), findsOneWidget);
      expect(find.text('Lock after'), findsNothing);

      await tester.tap(find.byKey(const Key('biometric-switch')));
      await _settle(tester);

      expect(h.container.read(biometricSetupProvider).enabled, isTrue);
      expect(find.text('Lock after'), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('Fingerprint unlock is on.'), findsOneWidget);
    });

    testWidgets('a closed prompt leaves it off and says nothing', (
      tester,
    ) async {
      final h = await _signedIn(tester);
      h.tokens.unlockError = const VaultException(VaultFailure.cancelled);
      await tester.pumpWidget(page(h));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('biometric-switch')));
      await _settle(tester);

      expect(h.container.read(biometricSetupProvider).enabled, isFalse);
      expect(find.text('Lock after'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a phone that refuses is told what to do', (tester) async {
      final h = await _signedIn(tester);
      h.tokens.unlockError = const VaultException(VaultFailure.notAvailable);
      await tester.pumpWidget(page(h));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('biometric-switch')));
      await _settle(tester);
      expect(find.textContaining('Set a screen lock'), findsOneWidget);
    });

    testWidgets('turning it off needs no prompt', (tester) async {
      final h = await _signedIn(tester, protect: true);
      final before = h.tokens.prompts;
      await tester.pumpWidget(page(h));
      await _settle(tester);
      expect(find.text('Lock after'), findsOneWidget);

      await tester.tap(find.byKey(const Key('biometric-switch')));
      await _settle(tester);

      expect(h.container.read(biometricSetupProvider).enabled, isFalse);
      expect(h.tokens.prompts, before);
      expect(find.text('Fingerprint unlock is off.'), findsOneWidget);
    });

    testWidgets('"Lock after" offers the four times and keeps the choice', (
      tester,
    ) async {
      final h = await _signedIn(tester, protect: true);
      await tester.pumpWidget(page(h));
      await _settle(tester);

      await tester.tap(find.text('Lock after'));
      await _settle(tester);
      for (final label in [
        'Immediately',
        '1 minute',
        '5 minutes',
        '15 minutes',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('15 minutes').last);
      await _settle(tester);

      expect(h.container.read(appPrefsProvider).lockTimeoutSeconds, 900);
      expect(find.text('15 minutes'), findsOneWidget); // the row's subtitle
    });
  });

  group('the offer after signing in', () {
    testWidgets(
      'the sheet explains, warns about other fingerprints, offers both buttons',
      (tester) async {
        late BuildContext ctx;
        await pumpThemed(
          tester,
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        );
        bool? answer;
        unawaited(
          showBiometricOffer(
            ctx,
            BiometricKind.fingerprint,
          ).then((v) => answer = v),
        );
        await _settle(tester);

        expect(
          find.text('Open Rosenthal with your fingerprint?'),
          findsOneWidget,
        );
        expect(find.textContaining('shop never sees it'), findsOneWidget);
        expect(
          find.textContaining('fingerprint is saved on this phone'),
          findsOneWidget,
        );
        await tester.tap(find.text('Not now'));
        await _settle(tester);
        expect(answer, isFalse);
      },
    );

    testWidgets('a phone with only a screen lock says so', (tester) async {
      late BuildContext ctx;
      await pumpThemed(
        tester,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      unawaited(showBiometricOffer(ctx, BiometricKind.screenLock));
      await _settle(tester);
      expect(
        find.text("Open Rosenthal with your phone's screen lock?"),
        findsOneWidget,
      );
      expect(find.textContaining("phone's PIN"), findsOneWidget);
    });

    Future<AuthHarness> shown(WidgetTester tester) async {
      final h = await _signedIn(tester);
      await tester.pumpWidget(
        _app(h, const BiometricOfferHost(child: Scaffold(body: Text('home')))),
      );
      await h.container.read(biometricOfferProvider.notifier).consider();
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      return h;
    }

    testWidgets('"Turn on" opens the phone prompt and confirms', (
      tester,
    ) async {
      final h = await shown(tester);
      expect(
        find.text('Open Rosenthal with your fingerprint?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Turn on'));
      await _settle(tester);
      expect(h.container.read(biometricSetupProvider).enabled, isTrue);
      expect(find.text('Fingerprint unlock is on.'), findsOneWidget);
      expect(h.container.read(appPrefsProvider).biometricOfferDeclines, 0);
    });

    testWidgets('"Not now" is counted; after two the offer stops', (
      tester,
    ) async {
      final h = await shown(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(h.container.read(biometricSetupProvider).enabled, isFalse);
      expect(h.container.read(appPrefsProvider).biometricOfferDeclines, 1);
    });
  });
}
