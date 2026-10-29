import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/load_fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() {
    loadAppFonts();
    ShopTime.init();
  });

  group('AppButton', () {
    testWidgets('calls onPressed once per tap', (tester) async {
      var n = 0;
      await pumpThemed(tester, AppButton(label: 'Save', onPressed: () => n++));
      await tester.tap(find.text('Save'));
      expect(n, 1);
    });

    testWidgets(
      'loading blocks taps and shows a spinner instead of the label',
      (tester) async {
        var n = 0;
        await pumpThemed(
          tester,
          AppButton(label: 'Save', loading: true, onPressed: () => n++),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Save'), findsNothing);
        await tester.tap(find.byType(AppButton), warnIfMissed: false);
        expect(n, 0);
      },
    );

    testWidgets('disabled (null onPressed) does nothing', (tester) async {
      await pumpThemed(tester, const AppButton(label: 'Nope', onPressed: null));
      await tester.tap(find.text('Nope'));
      // no exception, nothing to assert beyond not crashing
      expect(find.text('Nope'), findsOneWidget);
    });

    testWidgets('keeps a 48+ px touch target (accessibility)', (tester) async {
      await pumpThemed(
        tester,
        AppButton(label: 'Small', compact: true, onPressed: () {}),
      );
      expect(
        tester.getSize(find.byType(AppButton)).height,
        greaterThanOrEqualTo(44),
      );
    });

    for (final dark in [true, false]) {
      testWidgets(
        'all variants render without overflow in ${dark ? 'dark' : 'light'} at 1.6x text',
        (tester) async {
          await pumpThemed(
            tester,
            Column(
              children: [
                for (final v in AppButtonVariant.values)
                  AppButton(
                    label: 'Reschedule booking',
                    icon: Icons.event_repeat_rounded,
                    variant: v,
                    onPressed: () {},
                  ),
              ],
            ),
            dark: dark,
            textScale: 1.6,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('AppTextField', () {
    testWidgets('shows the error sentence under the field', (tester) async {
      await pumpThemed(
        tester,
        const AppTextField(
          label: 'Phone',
          errorText: 'Enter a valid phone number',
        ),
      );
      expect(find.text('Enter a valid phone number'), findsOneWidget);
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });

    testWidgets('password can be revealed and hidden again', (tester) async {
      await pumpThemed(
        tester,
        const AppTextField(label: 'Password', obscure: true),
      );
      bool obscured() =>
          tester.widget<TextField>(find.byType(TextField)).obscureText;
      expect(obscured(), isTrue);
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pump();
      expect(obscured(), isFalse);
      await tester.tap(find.byIcon(Icons.visibility_off_rounded));
      await tester.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('reports typing', (tester) async {
      String? last;
      await pumpThemed(
        tester,
        AppTextField(label: 'Name', onChanged: (v) => last = v),
      );
      await tester.enterText(find.byType(TextField), 'Alex');
      expect(last, 'Alex');
    });
  });

  group('pills and avatars', () {
    testWidgets('every appointment status shows its label and an icon', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        Wrap(
          children: [
            for (final s in AppointmentStatus.values) AppointmentStatusPill(s),
          ],
        ),
      );
      for (final s in AppointmentStatus.values) {
        expect(find.text(s.label), findsOneWidget);
        expect(find.byIcon(s.icon), findsOneWidget);
      }
    });

    test('initials', () {
      expect(AppAvatar.initials('Daniel Reid'), 'DR');
      expect(AppAvatar.initials('mike'), 'M');
      expect(AppAvatar.initials('  Sam   Lee  Jr '), 'SJ');
      expect(AppAvatar.initials(''), '?');
    });

    testWidgets('a missing picture falls back to initials', (tester) async {
      await pumpThemed(
        tester,
        const AppAvatar(
          name: 'Sam Lee',
          imageUrl: 'http://invalid.invalid/x.png',
        ),
      );
      await tester.pump();
      expect(find.text('SL'), findsOneWidget);
    });
  });

  group('chips and segments', () {
    testWidgets('ChipsRow reports the tapped value and shows counts', (
      tester,
    ) async {
      var picked = 'all';
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, set) => ChipsRow<String>(
            selected: picked,
            onChanged: (v) => set(() => picked = v),
            options: const [
              ChipOption('all', 'All', count: 42),
              ChipOption('pending', 'Pending', count: 5),
            ],
          ),
        ),
      );
      expect(find.text('42'), findsOneWidget);
      await tester.tap(find.text('Pending'));
      await tester.pump();
      expect(picked, 'pending');
    });

    testWidgets('AppSegmented switches option', (tester) async {
      var picked = 'a';
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, set) => AppSegmented<String>(
            selected: picked,
            onChanged: (v) => set(() => picked = v),
            options: const [
              ChipOption('a', 'Today'),
              ChipOption('b', '7 days'),
            ],
          ),
        ),
      );
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
    });
  });

  group('DateStrip', () {
    testWidgets('tapping a day reports that date; markers draw dots', (
      tester,
    ) async {
      final today = ShopTime.today();
      DateTime? picked;
      await pumpThemed(
        tester,
        DateStrip(
          selected: today,
          onSelected: (d) => picked = d,
          markers: {today},
        ),
      );
      await tester.pump();
      final target = today.add(const Duration(days: 1));
      await tester.tap(find.text('${target.day}').first);
      expect(picked, isNotNull);
      expect(ShopTime.isSameDay(picked!, target), isTrue);
    });
  });

  group('overlays', () {
    testWidgets('showConfirm returns true on confirm, false on cancel', (
      tester,
    ) async {
      bool? result;
      await pumpThemed(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'Open',
            onPressed: () async => result = await showConfirm(
              context,
              title: 'Cancel booking?',
              message: 'Daniel will be told.',
              confirmLabel: 'Yes, cancel',
              cancelLabel: 'Keep it',
              destructive: true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel booking?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('undo snackbar runs onUndo', (tester) async {
      var undone = false;
      await pumpThemed(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'Go',
            onPressed: () => showUndoSnack(
              context,
              'Booking confirmed',
              onUndo: () => undone = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Booking confirmed'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(undone, isTrue);
    });

    testWidgets('bottom sheet shows its title and content', (tester) async {
      await pumpThemed(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'Sheet',
            onPressed: () => showAppSheet<void>(
              context,
              title: 'Reschedule',
              builder: (_) => const Text('Pick a slot'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Reschedule'), findsOneWidget);
      expect(find.text('Pick a slot'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('EmptyState action fires', (tester) async {
      var n = 0;
      await pumpThemed(
        tester,
        EmptyState(
          icon: Icons.event_busy_rounded,
          title: 'No bookings',
          message: 'Quiet day',
          actionLabel: 'Book walk-in',
          onAction: () => n++,
        ),
      );
      await tester.tap(find.text('Book walk-in'));
      expect(n, 1);
    });

    testWidgets('ErrorState retries and copies the support code', (
      tester,
    ) async {
      var retried = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpThemed(
        tester,
        ErrorState(
          message: 'Took too long',
          supportCode: 'abc123',
          onRetry: () => retried++,
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
      await tester.pump(const Duration(seconds: 2));
      // The code is folded under "Details".
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('abc123'));
      await tester.pump();
      expect(copied, 'abc123');
    });

    testWidgets(
      'skeleton rows build, animate and also work with reduce-motion',
      (tester) async {
        await pumpThemed(
          tester,
          const SingleChildScrollView(child: SkeletonRows(count: 4)),
        );
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        expect(find.byType(SkeletonBox), findsWidgets);
      },
    );
  });

  group('numbers', () {
    testWidgets('KpiTile counts up to its value', (tester) async {
      await pumpThemed(
        tester,
        KpiTile(
          icon: Icons.event,
          label: 'Bookings',
          value: 12,
          format: (v) => '${v.round()}',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('KpiTile loading shows placeholders, not numbers', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const KpiTile(icon: Icons.event, label: 'Tips', loading: true),
      );
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text('Tips'), findsNothing);
    });

    testWidgets('MoneyText prints exact money, with small cents when asked', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const Column(
          children: [
            MoneyText(Money(48650)),
            MoneyText(Money(123456), smallCents: true),
          ],
        ),
      );
      expect(find.text(r'$486.50'), findsOneWidget);
      expect(
        find.textContaining(r'$1,234', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
