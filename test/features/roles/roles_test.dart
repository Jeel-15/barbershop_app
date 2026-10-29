import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/roles/data/roles_repository.dart';
import 'package:barbershop_app/features/roles/domain/role_models.dart';
import 'package:barbershop_app/features/roles/presentation/role_form_page.dart';
import 'package:barbershop_app/features/roles/presentation/roles_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/roles_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

const _all = ['Role-Add', 'Role-Edit', 'Role-Delete'];

Future<FakeRoles> _open(
  WidgetTester tester,
  String start, {
  List<String> perms = _all,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeRoles();
  final boot = adminBootstrapWith(perms);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/app/roles', builder: (_, _) => const RolesPage()),
      GoRoute(path: '/app/roles/new', builder: (_, _) => const RoleFormPage()),
      GoRoute(
        path: '/app/roles/edit/:id',
        builder: (_, s) =>
            RoleFormPage(roleId: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        rolesRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push(start));
  await _settle(tester);
  return repo;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
  });

  test(
    'a permission label follows the web: after the dash, words capitalised',
    () {
      expect(const PermissionItem(1, 'Staff-Add').label, 'Add');
      expect(const PermissionItem(2, 'Pos_invoice-Show_All').label, 'Show All');
      expect(
        const PermissionItem(3, 'Setting-Payment_Method').label,
        'Payment Method',
      );
    },
  );

  group('Roles list', () {
    testWidgets('roles with counts; a system role is marked, not deletable', (
      tester,
    ) async {
      await _open(tester, '/app/roles');
      expect(find.text('Roles'), findsOneWidget);
      expect(find.text('Manage user roles and permissions'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('2 of 3 permissions'), findsOneWidget);
      expect(find.text('4 users'), findsOneWidget);
      expect(find.text('0 users'), findsOneWidget);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('Delete asks in the web words and shows the server refusal', (
      tester,
    ) async {
      final r = await _open(tester, '/app/roles');
      r.deleteFails = const ConflictFailure(
        'This role is still assigned to staff. Give them another role first.',
      );
      await tester.tap(find.byTooltip('More').last);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Are you sure to delete Role?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('delete:6'));
      expect(find.textContaining('still assigned to staff'), findsOneWidget);
    });

    testWidgets('no rights: no Add, no menu', (tester) async {
      await _open(tester, '/app/roles', perms: const []);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('Role form', () {
    testWidgets('Add New Role: the name is required, in the web words', (
      tester,
    ) async {
      final r = await _open(tester, '/app/roles/new');
      expect(find.text('Add New Role'), findsWidgets);
      expect(find.text('Role Permissions'), findsOneWidget);
      expect(find.text('Administrator Access'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await _settle(tester);
      expect(find.text('Please Enter Role Name'), findsOneWidget);
      expect(r.calls, isEmpty);
    });

    testWidgets('permissions are grouped and ticked one by one', (
      tester,
    ) async {
      final r = await _open(tester, '/app/roles/new');
      expect(find.text('Pos_invoice'), findsOneWidget);
      expect(find.text('Show All'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Role Name'),
        'Cashier',
      );
      await tester.tap(find.widgetWithText(AppChoiceChip, 'Show All'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await _settle(tester);
      expect(r.calls, contains('create:Cashier:3'));
    });

    testWidgets('Administrator Access ticks everything', (tester) async {
      final r = await _open(tester, '/app/roles/new');
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Role Name'),
        'Boss',
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await _settle(tester);
      expect(r.calls, contains('create:Boss:1,2,3'));
    });

    testWidgets("Edit opens with the role's permissions ticked", (
      tester,
    ) async {
      final r = await _open(tester, '/app/roles/edit/2');
      expect(find.text('Edit Role'), findsOneWidget);
      expect(
        find.text('A system role: its name cannot be changed.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await _settle(tester);
      expect(r.calls, contains('update:2:Staff:1,2'));
    });

    testWidgets('a taken name is shown under the field', (tester) async {
      final r = await _open(tester, '/app/roles/new');
      r.saveFails = const ValidationFailure(
        'invalid',
        fieldErrors: {
          'name': ['The name has already been taken.'],
        },
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Role Name'),
        'Staff',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Submit'));
      await _settle(tester);
      expect(find.text('The name has already been taken.'), findsOneWidget);
    });
  });
}
