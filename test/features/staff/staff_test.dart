import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:barbershop_app/features/staff/presentation/staff_form_page.dart';
import 'package:barbershop_app/features/staff/presentation/staff_page.dart';
import 'package:barbershop_app/features/staff/presentation/staff_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/staff_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

const _all = ['Staff-Add', 'Staff-Edit', 'Staff-Delete'];

Future<FakeStaffRepo> _open(
  WidgetTester tester, {
  String start = '/app/staff',
  List<String> perms = _all,
  bool staffModule = true,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeStaffRepo();
  final boot = Bootstrap.fromJson(
    bootstrapJson(permissions: perms, modules: {'staff': staffModule}),
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/app/staff', builder: (_, _) => const StaffPage()),
      GoRoute(path: '/app/staff/new', builder: (_, _) => const StaffFormPage()),
      GoRoute(
        path: '/app/staff/edit/:id',
        builder: (_, s) => StaffFormPage(
          editId: int.parse(s.pathParameters['id']!),
          member: s.extra is StaffMember ? s.extra! as StaffMember : null,
        ),
      ),
      GoRoute(
        path: '/app/staff/:id',
        builder: (_, s) =>
            StaffProfilePage(staffId: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        staffRepositoryProvider.overrideWithValue(repo),
        photoPickerProvider.overrideWithValue(() async => null),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push(start));
  await _settle(tester);
  return repo;
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  formTests();

  group('Staff list', () {
    testWidgets('shows the team with status, role and services', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Staff'), findsOneWidget);
      expect(
        find.text('Manage team members, roles, and commissions'),
        findsOneWidget,
      );
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('mike@rosen.test'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Deactive'), findsOneWidget);
      expect(find.text('TEAM · 3'), findsOneWidget);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
    });

    testWidgets('search goes to the server', (tester) async {
      final r = await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'alice');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(r.calls, contains('list:alice'));
      expect(find.text('Mike'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('the row menu follows the permissions', (tester) async {
      await _open(tester);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Assign Services'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('no rights: no Add, no menu', (tester) async {
      await _open(tester, perms: const []);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
    });

    testWidgets('Delete asks in the web words, then deletes', (tester) async {
      final r = await _open(tester);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Are you sure to delete Staff?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('delete:42'));
    });

    testWidgets('Change Password checks length and match, in web words', (
      tester,
    ) async {
      final r = await _open(tester);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Change Password'));
      await _settle(tester);
      expect(find.text('New Password *'), findsOneWidget);
      expect(find.text('Confirm New Password *'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Update Password'));
      await _settle(tester);
      expect(find.text('Please enter a new password'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'New Password *'),
        '123',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Update Password'));
      await _settle(tester);
      expect(
        find.text('Password must be at least 6 characters long'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(AppTextField, 'New Password *'),
        'secret1',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Confirm New Password *'),
        'secret2',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Update Password'));
      await _settle(tester);
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(r.calls.where((c) => c.startsWith('password')), isEmpty);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Confirm New Password *'),
        'secret1',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Update Password'));
      await _settle(tester);
      expect(r.calls, contains('password:42:secret1'));
    });

    testWidgets('Assign Services saves the ticked services', (tester) async {
      final r = await _open(tester);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Assign Services'));
      await _settle(tester);
      await tester.tap(find.text('Skin fade'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save Assignments'));
      await _settle(tester);
      expect(r.calls, contains('assign:42:25,26'));
    });
  });

  group('Add / Update Staff', () {
    testWidgets('has the web fields', (tester) async {
      await _open(tester, start: '/app/staff/new');
      expect(find.text('Add Staff'), findsWidgets);
      expect(find.text('Staff Name *'), findsOneWidget);
      expect(find.text('Email *'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Password *'), findsOneWidget);
      expect(find.text('Role *'), findsOneWidget);
      expect(find.text('Barber'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Product Commission (%)'), findsOneWidget);
      expect(find.text('Status *'), findsOneWidget);
      expect(find.text('Staff Profile Image'), findsOneWidget);
    });

    testWidgets('the web validation words', (tester) async {
      final r = await _open(tester, start: '/app/staff/new');
      await tester.tap(find.widgetWithText(AppButton, 'Add Staff'));
      await _settle(tester);
      expect(find.text('Please enter Staff Name'), findsOneWidget);
      expect(find.text('Please enter Staff Email'), findsOneWidget);
      expect(find.text('Please enter Password'), findsOneWidget);
      expect(find.text('Please select Role'), findsOneWidget);
      expect(find.text('Please select at least one Service'), findsOneWidget);
      expect(r.calls, isNot(contains('create')));
    });

    testWidgets('a valid barber is created with services and commission', (
      tester,
    ) async {
      final r = await _open(tester, start: '/app/staff/new');
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Staff Name *'),
        'Leo',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Email *'),
        'leo@rosen.test',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Password *'),
        'secret1',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Product Commission (%)'),
        '12.5',
      );
      await _tapVisible(tester, find.widgetWithText(AppChoiceChip, 'Staff'));
      await tester.pump();
      await _tapVisible(tester, find.text('Select Service'));
      await _settle(tester);
      await tester.tap(find.text("Men's cut"));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Done'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Add Staff'));
      await _settle(tester);
      final i = r.inputs.single;
      expect(i.name, 'Leo');
      expect(i.isBarber, isTrue);
      expect(i.serviceIds, [25]);
      expect(i.commission, '12.5');
      expect(i.active, isTrue);
      expect(i.roleId, 2);
    });

    testWidgets('an Accountant is not a barber: no services, no commission', (
      tester,
    ) async {
      await _open(tester, start: '/app/staff/new');
      await _tapVisible(
        tester,
        find.widgetWithText(AppChoiceChip, 'Accountant'),
      );
      await tester.pump();
      expect(find.text('Barber'), findsNothing);
      expect(find.text('Service'), findsNothing);
      expect(find.text('Product Commission (%)'), findsNothing);
    });

    testWidgets('a taken email is shown under the field', (tester) async {
      final r = await _open(tester, start: '/app/staff/new');
      r.saveFails = const ValidationFailure(
        'The given data was invalid.',
        fieldErrors: {
          'email': [
            'This email is already registered. Please use a different email.',
          ],
        },
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Staff Name *'),
        'Leo',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Email *'),
        'mike@rosen.test',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Password *'),
        'secret1',
      );
      await _tapVisible(
        tester,
        find.widgetWithText(AppChoiceChip, 'Accountant'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Add Staff'));
      await _settle(tester);
      expect(
        find.text(
          'This email is already registered. Please use a different email.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Update Staff opens filled, password is optional', (
      tester,
    ) async {
      final r = await _open(tester, start: '/app/staff/edit/42');
      expect(find.text('Update Staff'), findsWidgets);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('mike@rosen.test'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Update Staff'));
      await _settle(tester);
      expect(r.calls, contains('update:42'));
      expect(r.inputs.single.password, isEmpty);
      expect(r.inputs.single.serviceIds, [25]);
    });
  });

  group('Staff Profile', () {
    testWidgets(
      'a member with no Staff permission has no Assign Services tab',
      (tester) async {
        // The server lists a member's services only to Staff-Add/Edit/Delete.
        await _open(
          tester,
          start: '/app/staff/42',
          perms: const [],
          staffModule: false,
        );
        expect(find.text('Earnings'), findsOneWidget);
        expect(find.text('Assign Services'), findsNothing);
      },
    );

    testWidgets('the web cards and the three tabs', (tester) async {
      await _open(tester, start: '/app/staff/42');
      expect(find.text('Staff Profile'), findsOneWidget);
      expect(
        find.text('Track appointments, services, and earnings'),
        findsOneWidget,
      );
      expect(find.text('Mike'), findsWidgets);
      expect(find.text('Total Visits'), findsOneWidget);
      expect(find.text('Complete Services'), findsOneWidget);
      expect(find.text('Total Earn Tip'), findsOneWidget);
      expect(find.text('Total Product Commission'), findsOneWidget);
      expect(find.text('Total Service Commission'), findsOneWidget);
      expect(find.text('Total Earning'), findsOneWidget);
      // Appointments tab first
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('Assign To'), findsOneWidget);

      await tester.tap(find.text('Assign Services'));
      await _settle(tester);
      expect(find.text('Total Service Commision'), findsOneWidget);

      await tester.tap(find.text('Earnings'));
      await _settle(tester);
      expect(find.text('Product Commision'), findsOneWidget);
    });

    testWidgets('Start Date / End Date reload the appointments', (
      tester,
    ) async {
      final r = await _open(tester, start: '/app/staff/42');
      expect(r.calls, contains('appointments:42:-:-'));
      expect(find.text('Start Date:'), findsOneWidget);
      expect(find.text('End Date:'), findsOneWidget);
    });
  });
}

void formTests() {
  test('services go as service_ids[] so PHP reads a list', () async {
    final form = await StaffRepository.buildForm(
      const StaffInput(
        name: 'Leo',
        email: 'leo@rosen.test',
        phone: '',
        password: '',
        isBarber: true,
        serviceIds: [25, 26],
        commission: '12.5',
        active: true,
        roleId: 2,
      ),
    );
    final keys = [for (final f in form.fields) f.key];
    expect(keys.where((k) => k == 'service_ids[]').length, 2);
    expect(keys, isNot(contains('service_ids')));
    expect(keys, isNot(contains('password')));
    expect(form.fields.firstWhere((f) => f.key == 'is_barber').value, '1');
  });

  test('a non-barber sends no services or commission', () async {
    final form = await StaffRepository.buildForm(
      const StaffInput(
        name: 'Alice',
        email: 'a@rosen.test',
        phone: '',
        password: 'secret1',
        isBarber: false,
        serviceIds: [25],
        commission: '10',
        active: false,
        roleId: 5,
      ),
    );
    final keys = [for (final f in form.fields) f.key];
    expect(keys.any((k) => k.startsWith('service_ids')), isFalse);
    expect(keys, isNot(contains('commission')));
    expect(form.fields.firstWhere((f) => f.key == 'active_status').value, '0');
  });
}
