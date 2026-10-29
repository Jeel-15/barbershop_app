import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:barbershop_app/features/me/presentation/staff_report_page.dart';
import 'package:barbershop_app/features/me/presentation/working_hours_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/me_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<FakeMe> _open(
  WidgetTester tester,
  Widget page, {
  bool staff = true,
  String? photo,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final me = FakeMe(staff: staff);
  final boot = staff ? staffBootstrap() : adminBootstrap();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/page', builder: (_, _) => page),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        meRepositoryProvider.overrideWithValue(me),
        photoPickerProvider.overrideWithValue(() async => photo),
        refreshAccountProvider.overrideWithValue(() async {
          me.calls.add('refresh');
        }),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push('/page'));
  await _settle(tester);
  return me;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  group('My Profile', () {
    testWidgets('shows the person, services and (staff) the numbers', (
      tester,
    ) async {
      await _open(tester, const ProfilePage());
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('View and update your account details'), findsOneWidget);
      expect(find.text('Mike Staff'), findsWidgets);
      expect(find.text('Assigned Services'), findsOneWidget);
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Completed Services'), findsOneWidget);
      expect(find.text('Total Visits'), findsOneWidget);
      expect(find.text(r'$273.50'), findsOneWidget);
      expect(find.text('View full stats'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('JPG, PNG or GIF. Max 2MB.'), findsOneWidget);
    });

    testWidgets('the owner gets no numbers block', (tester) async {
      await _open(tester, const ProfilePage(), staff: false);
      expect(find.text('Completed Services'), findsNothing);
      expect(find.text('Total Visits'), findsNothing);
    });

    testWidgets('Save Changes sends the form, then refreshes the account', (
      tester,
    ) async {
      final me = await _open(tester, const ProfilePage());
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Phone'),
        '7801112222',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.widgetWithText(AppButton, 'Save Changes'));
      await _settle(tester);
      expect(
        me.calls,
        contains('profile:Mike Staff|mike@rosen.test|7801112222|-'),
      );
      expect(me.calls, contains('refresh'));
    });

    testWidgets('name and email are required, in words', (tester) async {
      final me = await _open(tester, const ProfilePage());
      await tester.enterText(find.widgetWithText(AppTextField, 'Name *'), '');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.widgetWithText(AppButton, 'Save Changes'));
      await _settle(tester);
      expect(find.text('The name field is required.'), findsOneWidget);
      expect(me.calls.where((c) => c.startsWith('profile')), isEmpty);
    });

    testWidgets('server field errors (taken email) show under the field', (
      tester,
    ) async {
      final me = await _open(tester, const ProfilePage());
      me.profileFail = const ValidationFailure(
        'The given data was invalid.',
        fieldErrors: {
          'email': ['The email has already been taken.'],
        },
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.widgetWithText(AppButton, 'Save Changes'));
      await _settle(tester);
      expect(find.text('The email has already been taken.'), findsOneWidget);
    });

    testWidgets('only JPG, PNG or GIF can be chosen as the photo', (
      tester,
    ) async {
      await _open(tester, const ProfilePage(), photo: '/tmp/doc.pdf');
      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.widgetWithText(AppButton, 'Choose photo'));
      await _settle(tester);
      expect(find.text('JPG, PNG or GIF only.'), findsOneWidget);
    });
  });

  group('Staff Report', () {
    testWidgets('earning cards, then the Appointments tab', (tester) async {
      await _open(tester, const StaffReportPage());
      expect(find.text('Staff Report'), findsOneWidget);
      expect(find.text('Total Earning'), findsOneWidget);
      expect(find.text(r'$273.50'), findsOneWidget);
      expect(find.text('Product Commission'), findsOneWidget);
      expect(find.text('Service Commission'), findsOneWidget);
      expect(find.text('Tip'), findsOneWidget);
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('Total Amount'), findsOneWidget);
      expect(find.textContaining('Complete'), findsOneWidget);
    });

    testWidgets('Service Earning and Daily Earning tabs use the web columns', (
      tester,
    ) async {
      await _open(tester, const StaffReportPage());
      await tester.tap(find.text('Service Earning'));
      await _settle(tester);
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Total Appointment'), findsOneWidget);
      expect(find.text('Total Service Commision'), findsOneWidget);
      expect(find.text('Total Earn'), findsOneWidget);

      await tester.tap(find.text('Daily Earning'));
      await _settle(tester);
      expect(find.text('Product Commision'), findsOneWidget);
      expect(find.text('Service Commision'), findsOneWidget);
      expect(find.text(r'$28.00'), findsOneWidget);
    });

    testWidgets('Reports Filter: a status narrows both cards and rows', (
      tester,
    ) async {
      final me = await _open(tester, const StaffReportPage());
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await _settle(tester);
      expect(find.text('Reports Filter'), findsWidgets);
      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('End Date'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppChoiceChip, 'Confirm'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Filter'));
      await _settle(tester);
      expect(me.calls, contains('summary:-:-:3'));
      expect(me.calls, contains('appointments:3'));
      expect(find.text('Confirm'), findsWidgets);
    });
  });

  group('Working Hours', () {
    testWidgets('a card per day, in the web words', (tester) async {
      await _open(tester, const WorkingHoursPage());
      expect(find.text('Working Hours'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(
        find.text('Total Working Hours: 8.5 hours', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('09:00 AM – 01:00 PM'), findsOneWidget);
      expect(find.text('No Working Hours Set'), findsOneWidget);
      expect(find.text('No Hours Set (Day Off)'), findsOneWidget);
    });

    testWidgets('+ Add: Quick select Morning saves 09:00-13:00', (
      tester,
    ) async {
      final me = await _open(tester, const WorkingHoursPage());
      await tester.tap(find.text('+ Add').at(1)); // Tuesday
      await _settle(tester);
      expect(find.text('Set Working Hours / Add Break'), findsOneWidget);
      expect(
        find.text('Configure your schedule for Tuesday', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Morning (9:00 AM - 1:00 PM)'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(me.calls, contains('add:2:09:00-13:00'));
    });

    testWidgets('an overlap is refused in the web words', (tester) async {
      final me = await _open(tester, const WorkingHoursPage());
      me.hoursFail = const ConflictFailure(
        'This time slot overlaps with an existing working hour. Please choose another time.',
      );
      await tester.tap(find.text('+ Add').first);
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(
        find.textContaining('overlaps with an existing working hour'),
        findsOneWidget,
      );
    });

    testWidgets('Edit fills the range, Delete asks first', (tester) async {
      final me = await _open(tester, const WorkingHoursPage());
      await tester.tap(find.byTooltip('Edit').first);
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(me.calls, contains('update:10:09:00-13:00'));

      await tester.tap(find.byTooltip('Delete').first);
      await _settle(tester);
      expect(find.text('Are you sure to delete Work Time?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(me.calls, contains('delete:10'));
    });

    testWidgets('the Day Off switch is saved', (tester) async {
      final me = await _open(tester, const WorkingHoursPage());
      await tester.tap(find.byType(Switch).first);
      await _settle(tester);
      expect(me.calls, contains('off:1:true'));
    });

    test('total hours: 4 + 4.5 = 8.5, whole numbers have no decimals', () {
      final d = WorkDay.fromJson(weekJson().first);
      expect(d.totalHours, '8.5');
      final full = WorkDay.fromJson({
        'slot_id': 9,
        'day_name': 'Friday',
        'is_day_off': false,
        'blocks': [
          {
            'id': 1,
            'start': '09:00',
            'end': '13:00',
            'start_label': '',
            'end_label': '',
          },
        ],
      });
      expect(full.totalHours, '4');
    });
  });
}
