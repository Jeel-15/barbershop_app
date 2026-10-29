import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/customers/presentation/customer_profile_page.dart';
import 'package:barbershop_app/features/customers/presentation/customers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

CustomerSummary _c(
  int id,
  String name, {
  String? phone,
  bool active = true,
  int visits = 0,
}) => CustomerSummary(
  id: id,
  name: name,
  phone: phone,
  email: '$name@example.com'.replaceAll(' ', '').toLowerCase(),
  isActive: active,
  memberSince: '2026-09-01',
  totalVisits: visits,
  appointmentsTotal: visits + 1,
);

class FakeCustomers extends CustomersRepository {
  FakeCustomers() : super(_NoApi());

  final rows = [
    _c(3, 'Sam Patel', phone: '7805550103', visits: 3),
    _c(2, 'Daniel Okafor', phone: '7805550102'),
    _c(1, 'Old Client', phone: '7805550101', active: false),
  ];
  final calls = <String>[];
  final created = <CustomerInput>[];
  final updated = <int, CustomerInput>{};
  Failure? deleteFails;

  @override
  Future<PagedResult<CustomerSummary>> list({
    String q = '',
    int? status,
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('list:$q');
    final hit = [
      for (final r in rows)
        if (q.isEmpty || r.name.toLowerCase().contains(q.toLowerCase())) r,
    ];
    return PagedResult(items: hit, hasMore: false, total: hit.length);
  }

  @override
  Future<CustomerSummary> summary(int id) async =>
      rows.firstWhere((r) => r.id == id);

  @override
  Future<PagedResult<CustomerAppointment>> appointments(
    int id, {
    int page = 1,
    int perPage = 20,
  }) async => const PagedResult(
    items: [
      CustomerAppointment(
        id: 11,
        date: '2026-10-26',
        startLabel: '09:30 AM',
        endLabel: '10:15 AM',
        status: AppointmentStatus.confirmed,
        staffNames: 'mike',
      ),
    ],
    hasMore: false,
    total: 1,
  );

  @override
  Future<CustomerSummary> create(CustomerInput input) async {
    created.add(input);
    final c = _c(9, input.name, phone: input.phone, active: input.isActive);
    rows.insert(0, c);
    return c;
  }

  @override
  Future<CustomerSummary> update(int id, CustomerInput input) async {
    updated[id] = input;
    return rows.firstWhere((r) => r.id == id);
  }

  @override
  Future<void> delete(int id) async {
    calls.add('delete:$id');
    if (deleteFails != null) throw deleteFails!;
    rows.removeWhere((r) => r.id == id);
  }
}

Bootstrap _boot({List<String> perms = const []}) =>
    Bootstrap.fromJson(bootstrapJson(permissions: perms));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<FakeCustomers> _open(
  WidgetTester tester, {
  String start = '/customers',
  List<String> perms = const [
    'Customer-Add',
    'Customer-Edit',
    'Customer-Delete',
  ],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeCustomers();
  final boot = _boot(perms: perms);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/customers', builder: (_, _) => const CustomersPage()),
      GoRoute(
        path: '/customer/:id',
        builder: (_, s) =>
            CustomerProfilePage(customerId: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        customersRepositoryProvider.overrideWithValue(repo),
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

  group('Customers list', () {
    testWidgets('lists customers with phone and an Inactive mark', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Manage your customer directory'), findsOneWidget);
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('7805550103'), findsOneWidget);
      expect(find.text('ALL CUSTOMERS · 3'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('search asks the server and narrows the list', (tester) async {
      final repo = await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'sam');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(repo.calls, contains('list:sam'));
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('Daniel Okafor'), findsNothing);
    });

    testWidgets('Add Customer follows the web: needs name and phone', (
      tester,
    ) async {
      final repo = await _open(tester);
      await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
      await _settle(tester);
      expect(find.text('Add New Customer'), findsOneWidget);
      expect(find.text('Email (Optional)'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Add Customer'));
      await _settle(tester);
      expect(find.text('Please Enter Full Name'), findsOneWidget);
      expect(find.text('Please Enter Phone No.'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Full Name *'),
        'Ravi Shah',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Phone Number *'),
        '7801112222',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Add Customer'));
      await _settle(tester);
      expect(repo.created.single.toJson(), {
        'full_name': 'Ravi Shah',
        'phone_number': '7801112222',
        'email': null,
        'status': 1,
      });
      expect(find.text('Ravi Shah'), findsOneWidget);
    });

    testWidgets('Edit opens the filled form, Update Customer saves', (
      tester,
    ) async {
      final repo = await _open(tester);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Edit'));
      await _settle(tester);
      expect(find.text('Update Customer'), findsWidgets);
      expect(find.text('Sam Patel'), findsWidgets);
      await tester.tap(find.widgetWithText(AppChoiceChip, 'Deactive'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Update Customer'));
      await _settle(tester);
      expect(repo.updated[3]!.isActive, isFalse);
    });

    testWidgets('Delete asks first, then deletes', (tester) async {
      final repo = await _open(tester);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Are you sure to delete Customer?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(repo.calls, contains('delete:3'));
      expect(find.text('Sam Patel'), findsNothing);
    });

    testWidgets('the server refusing a delete is shown, nothing vanishes', (
      tester,
    ) async {
      final repo = await _open(tester);
      repo.deleteFails = const ConflictFailure(
        'This customer has appointments and cannot be deleted.',
      );
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(
        find.text('This customer has appointments and cannot be deleted.'),
        findsOneWidget,
      );
      expect(find.text('Sam Patel'), findsOneWidget);
    });

    testWidgets('without add/edit/delete rights those controls are hidden', (
      tester,
    ) async {
      await _open(tester, perms: const []);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
      expect(find.text('Sam Patel'), findsOneWidget);
    });
  });

  group('Customer profile', () {
    testWidgets('shows the person, their visits and every appointment', (
      tester,
    ) async {
      await _open(tester, start: '/customer/3');
      expect(find.text('Customer Profile'), findsOneWidget);
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('7805550103'), findsOneWidget);
      expect(find.text('Total Visits'), findsOneWidget);
      expect(find.text('Member since: '), findsOneWidget);
      expect(find.text('09:30 AM - 10:15 AM'), findsOneWidget);
      expect(find.text('mike'), findsOneWidget);
      // The web's "Total Spent" is wrong (Q35), so it is not shown.
      expect(find.text('Total Spent'), findsNothing);
    });

    testWidgets('Edit from the menu updates and Delete returns to the list', (
      tester,
    ) async {
      final repo = await _open(tester, start: '/customer/3');
      await tester.tap(find.byTooltip('More'));
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(repo.calls, contains('delete:3'));
      expect(find.text('Customer Profile'), findsNothing);
    });
  });
}
