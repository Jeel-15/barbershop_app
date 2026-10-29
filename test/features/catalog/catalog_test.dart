import 'dart:async';
import 'dart:io';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/product_form_page.dart';
import 'package:barbershop_app/features/catalog/presentation/products_page.dart';
import 'package:barbershop_app/features/catalog/presentation/service_form_page.dart';
import 'package:barbershop_app/features/catalog/presentation/services_page.dart';
import 'package:barbershop_app/features/catalog/presentation/simple_catalog_pages.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/catalog_fixtures.dart';
import '../../helpers/load_fonts.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

const _all = [
  'Service-Add',
  'Service-Edit',
  'Service-Delete',
  'Product-Add',
  'Product-Edit',
  'Product-Delete',
  'Service_Category-Add',
  'Service_Category-Edit',
  'Service_Category-Delete',
  'Gst-Add',
  'Gst-Edit',
  'Gst-Delete',
];

Future<FakeCatalog> _open(
  WidgetTester tester,
  String start, {
  List<String> perms = _all,
  String? photo,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeCatalog();
  final boot = adminBootstrapWith(perms);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/app/services', builder: (_, _) => const ServicesPage()),
      GoRoute(
        path: '/app/services/new',
        builder: (_, _) => const ServiceFormPage(),
      ),
      GoRoute(
        path: '/app/services/edit/:id',
        builder: (_, s) => ServiceFormPage(
          editId: int.parse(s.pathParameters['id']!),
          service: s.extra is AdminService ? s.extra! as AdminService : null,
        ),
      ),
      GoRoute(path: '/app/products', builder: (_, _) => const ProductsPage()),
      GoRoute(
        path: '/app/products/new',
        builder: (_, _) => const ProductFormPage(),
      ),
      GoRoute(
        path: '/app/products/edit/:id',
        builder: (_, s) => ProductFormPage(
          editId: int.parse(s.pathParameters['id']!),
          product: s.extra is AdminProduct ? s.extra! as AdminProduct : null,
        ),
      ),
      GoRoute(
        path: '/app/service-categories',
        builder: (_, _) => const CategoriesPage(),
      ),
      GoRoute(path: '/app/gst', builder: (_, _) => const GstPage()),
      GoRoute(
        path: '/app/payment-methods',
        builder: (_, _) => const PaymentMethodsPage(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        catalogRepositoryProvider.overrideWithValue(repo),
        photoPickerProvider.overrideWithValue(() async => photo),
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
  });

  group('multipart forms', () {
    test(
      'a service sends the web fields and the picture only when picked',
      () async {
        final form = await CatalogRepository.serviceForm(
          const ServiceInput(
            categoryId: 1,
            name: " Men's cut ",
            price: '30',
            duration: '30',
            commission: '',
            active: true,
            eligibleForTip: false,
            description: 'x',
          ),
        );
        final f = {for (final e in form.fields) e.key: e.value};
        expect(f['name'], "Men's cut");
        expect(f['active_status'], '1');
        expect(f['eligible_for_tip'], '0');
        expect(f.containsKey('commission'), isFalse);
        expect(form.files, isEmpty);
      },
    );

    test('a product always sends commission and stock', () async {
      final form = await CatalogRepository.productForm(
        const ProductInput(
          categoryId: 2,
          name: 'Oil',
          price: '20',
          stock: '5',
          commission: '5',
          active: false,
          description: '',
        ),
      );
      final f = {for (final e in form.fields) e.key: e.value};
      expect(f['stock'], '5');
      expect(f['commission'], '5');
      expect(f['active_status'], '0');
    });
  });

  group('Services', () {
    testWidgets('list with category, duration, price and an Inactive mark', (
      tester,
    ) async {
      await _open(tester, '/app/services');
      expect(find.text('Services'), findsOneWidget);
      expect(
        find.text('Manage service offerings, pricing, and duration'),
        findsOneWidget,
      );
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Haircuts · 30 min'), findsNWidgets(2));
      expect(find.text(r'$30.00'), findsNWidgets(2));
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('ALL SERVICES · 2'), findsOneWidget);
    });

    testWidgets('search, then the row menu and the delete wording', (
      tester,
    ) async {
      final r = await _open(tester, '/app/services');
      await tester.enterText(find.byType(TextField).first, 'skin');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(r.calls, contains('services:skin'));
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Website Section'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Are you sure to delete Service?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('deleteService:26'));
    });

    testWidgets('Website Section saves Signature Grooming Menu', (
      tester,
    ) async {
      final r = await _open(tester, '/app/services');
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Website Section'));
      await _settle(tester);
      expect(find.text('Select Section'), findsOneWidget);
      await tester.tap(find.text('Signature Grooming Menu'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      expect(r.calls, contains('section:25:signature_grooming'));
    });

    testWidgets('no rights: no Add and no Edit / Delete in the menu', (
      tester,
    ) async {
      await _open(tester, '/app/services', perms: const []);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Website Section'), findsOneWidget);
    });

    testWidgets('Add Service: the web checks, in the web words', (
      tester,
    ) async {
      final r = await _open(tester, '/app/services/new');
      expect(find.text('Add Service'), findsWidgets);
      expect(find.text('Service Name *'), findsOneWidget);
      expect(find.text('Duration (Minutes) *'), findsOneWidget);
      expect(find.text('Commission (%)'), findsOneWidget);
      expect(find.text('Eligible for Tip'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('Please select a category'), findsOneWidget);
      expect(find.text('Please enter service name'), findsOneWidget);
      expect(find.text('Please enter price'), findsOneWidget);
      expect(find.text('Please upload a service image'), findsOneWidget);
      expect(r.calls, isNot(contains('createService')));
    });

    testWidgets('Add Service saves with the picked picture', (tester) async {
      // The picker answers with a real (tiny) file: the size is checked.
      final pic = File('${Directory.systemTemp.path}/rosen_test_pic.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(pic.deleteSync);
      final r = await _open(tester, '/app/services/new', photo: pic.path);
      await _tapVisible(tester, find.widgetWithText(AppChoiceChip, 'Haircuts'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Service Name *'),
        'Beard',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Price (\$) *'),
        '15',
      );
      await _tapVisible(tester, find.text('Choose photo'));
      // The size check reads the file: real I/O, outside the fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      final i = r.serviceInputs.single;
      expect(i.categoryId, 1);
      expect(i.name, 'Beard');
      expect(i.price, '15');
      expect(i.duration, '30');
      expect(i.imagePath, pic.path);
      expect(i.active, isTrue);
    });

    testWidgets('Update opens filled and needs no new picture', (tester) async {
      final r = await _open(tester, '/app/services/edit/25');
      expect(find.text('Update Service'), findsWidgets);
      expect(find.text("Men's cut"), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      expect(r.calls, contains('updateService:25'));
      expect(r.serviceInputs.single.imagePath, isNull);
    });
  });

  group('Products', () {
    testWidgets('list shows stock, commission, price and status', (
      tester,
    ) async {
      await _open(tester, '/app/products');
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Hair oil'), findsOneWidget);
      expect(find.text('Retail · Stock 8'), findsOneWidget);
      expect(find.text('Commission 5.00%'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('delete asks in the web words', (tester) async {
      final r = await _open(tester, '/app/products');
      await tester.tap(find.byTooltip('More'));
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Are you sure to delete Product?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('deleteProduct:1'));
    });

    testWidgets('Add Product validation words', (tester) async {
      await _open(tester, '/app/products/new');
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('Please enter Product Name'), findsOneWidget);
      expect(find.text('Please select a Category'), findsOneWidget);
      expect(find.text('Please enter Price'), findsOneWidget);
      expect(find.text('Please enter Stock quantity'), findsOneWidget);
    });
  });

  group('Service Categories', () {
    testWidgets('list, add with the web word, delete wording', (tester) async {
      final r = await _open(tester, '/app/service-categories');
      expect(find.text('Service Categories'), findsOneWidget);
      expect(find.text('Organize services into categories'), findsOneWidget);
      expect(find.text('Haircuts'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _settle(tester);
      expect(find.text('Add Service Category'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('Please Enter Category Name'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Category Name *'),
        'Beard care',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(r.calls, contains('createCategory:Beard care'));

      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(
        find.text('Are you sure to delete Service category?'),
        findsOneWidget,
      );
    });
  });

  group('GST Settings', () {
    testWidgets('rates with type and the Default mark', (tester) async {
      await _open(tester, '/app/gst');
      expect(find.text('GST Settings'), findsOneWidget);
      expect(
        find.text('Configure tax rates for services and products'),
        findsOneWidget,
      );
      expect(find.text('5.00% · Include'), findsOneWidget);
      expect(find.text('7.00% · Exclude'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('Add GST: web words and payload', (tester) async {
      final r = await _open(tester, '/app/gst');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('Please enter GST Name'), findsOneWidget);
      expect(find.text('Please enter GST Rate'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'GST Name'),
        'HST',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Total Rate'),
        '13',
      );
      await tester.tap(find.widgetWithText(AppChoiceChip, 'Exclude'));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(r.calls, contains('createGst:HST:13:x:d'));
    });

    testWidgets('delete says Gst, like the web', (tester) async {
      final r = await _open(tester, '/app/gst');
      await tester.tap(find.byTooltip('More').last);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Are you sure to delete Gst?'), findsOneWidget);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('deleteGst:2'));
    });
  });

  group('Payment Options', () {
    testWidgets('add, duplicate name shown, delete wording', (tester) async {
      final r = await _open(tester, '/app/payment-methods');
      expect(find.text('Payment Options'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _settle(tester);
      expect(find.text('Add Payment Method'), findsWidgets);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('Please Enter Payment Method'), findsOneWidget);

      r.saveFails = const ValidationFailure(
        'invalid',
        fieldErrors: {
          'name': ['The name has already been taken.'],
        },
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Payment Method'),
        'Cash',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('The name has already been taken.'), findsOneWidget);
    });

    testWidgets('delete asks in the web words', (tester) async {
      final r = await _open(tester, '/app/payment-methods');
      await tester.tap(find.byTooltip('More').first);
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(
        find.text('Are you sure to delete Payment Method?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('deletePayment:1'));
    });
  });
}
