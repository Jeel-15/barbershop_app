// Live round trips against the LOCAL web API with the app's real repositories.
// Not part of tool/check.sh. Run:
//   flutter test tool/live/live_crud_test.dart
// Everything it creates is named "ZZ AUDIT ..." and is deleted again.
import 'dart:io';

import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/features/auth/data/auth_repository.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/content/data/content_repository.dart';
import 'package:barbershop_app/features/content/domain/content_models.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/roles/data/roles_repository.dart';
import 'package:barbershop_app/features/shop/data/shop_repository.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:flutter_test/flutter_test.dart';

// A deleted row keeps its name reserved (see docs/WEB_DEV_FIXES.md), so every
// run uses its own names.
final _tag = DateTime.now().millisecondsSinceEpoch % 1000000;

const _base = 'http://localhost/rosen_barber/public/api/v1';

Future<ApiClient> _client(String email) async {
  final anon = ApiClient(
    baseUrl: _base,
    readToken: () async => null,
    log: false,
  );
  final r = await AuthRepository(
    anon,
  ).login(email: email, password: 'Rosen@12345', deviceName: 'live-test');
  return ApiClient(baseUrl: _base, readToken: () async => r.token, log: false);
}

void main() {
  late ApiClient admin;

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test blocks real HTTP by default
    admin = await _client('apitest.admin@rosen.test');
    // Leftovers of an earlier failed run.
    final cat = CatalogRepository(admin);
    for (final c in await cat.categories()) {
      if (c.name.startsWith('ZZ AUDIT')) await cat.deleteCategory(c.id);
    }
    final roles = RolesRepository(admin);
    for (final r in (await roles.load()).roles) {
      if (r.name.startsWith('ZZ AUDIT')) await roles.delete(r.id);
    }
  });

  test('catalog: category, service, product, gst, payment method', () async {
    final repo = CatalogRepository(admin);

    const img = 'assets/images/rosenthal_crest.png';
    await repo.createCategory(
      name: 'ZZ AUDIT Cat $_tag',
      description: 'audit',
      imagePath: img,
    );
    final cats = await repo.categories();
    final cat = cats.firstWhere((c) => c.name == 'ZZ AUDIT Cat $_tag');
    await repo.updateCategory(
      cat.id,
      name: 'ZZ AUDIT Cat $_tag 2',
      description: 'x',
    );
    expect(
      (await repo.categories()).any((c) => c.name == 'ZZ AUDIT Cat $_tag 2'),
      isTrue,
    );

    await repo.createService(
      ServiceInput(
        categoryId: cat.id,
        name: 'ZZ AUDIT Service $_tag',
        price: '12.50',
        duration: '25',
        commission: '10',
        active: true,
        eligibleForTip: true,
        description: 'd',
        imagePath: img,
      ),
    );
    var svc = (await repo.services(q: 'ZZ AUDIT Service $_tag')).items.single;
    expect(svc.name, 'ZZ AUDIT Service $_tag');
    await repo.updateService(
      svc.id,
      ServiceInput(
        categoryId: cat.id,
        name: 'ZZ AUDIT Service $_tag B',
        price: '15',
        duration: '30',
        commission: '5',
        active: false,
        eligibleForTip: false,
        description: 'e',
      ),
    );
    svc = await repo.service(svc.id);
    expect(svc.name, 'ZZ AUDIT Service $_tag B');
    await repo.setHomeSection(svc.id, null);

    await repo.createProduct(
      ProductInput(
        categoryId: cat.id,
        name: 'ZZ AUDIT Product $_tag',
        price: '9.99',
        stock: '4',
        commission: '0',
        active: true,
        description: 'p',
        imagePath: img,
      ),
    );
    final prods = (await repo.products(q: 'ZZ AUDIT Product $_tag')).items;
    expect(prods.map((p) => p.name).toList(), ['ZZ AUDIT Product $_tag']);
    final prod = prods.single;
    await repo.updateProduct(
      prod.id,
      ProductInput(
        categoryId: cat.id,
        name: 'ZZ AUDIT Product $_tag B',
        price: '10',
        stock: '5',
        commission: '1',
        active: true,
        description: 'q',
      ),
    );
    expect((await repo.product(prod.id)).name, 'ZZ AUDIT Product $_tag B');

    await repo.createGst(
      'ZZ AUDIT GST $_tag',
      '7',
      exclude: true,
      isDefault: false,
    );
    final gst = (await repo.gst()).firstWhere(
      (g) => g.name == 'ZZ AUDIT GST $_tag',
    );
    await repo.updateGst(
      gst.id,
      'ZZ AUDIT GST $_tag B',
      '8',
      exclude: false,
      isDefault: false,
    );
    expect(
      (await repo.gst()).any((g) => g.name == 'ZZ AUDIT GST $_tag B'),
      isTrue,
    );

    await repo.createPayment('ZZ AUDIT Pay $_tag');
    final pay = (await repo.paymentMethods()).firstWhere(
      (p) => p.name == 'ZZ AUDIT Pay $_tag',
    );
    await repo.updatePayment(pay.id, 'ZZ AUDIT Pay $_tag B');

    await repo.deletePayment(pay.id);
    await repo.deleteGst(gst.id);
    await repo.deleteProduct(prod.id);
    await repo.deleteService(svc.id);
    await repo.deleteCategory(cat.id);
    expect(
      (await repo.categories()).any((c) => c.name.startsWith('ZZ AUDIT')),
      isFalse,
    );
  });

  test('customers: add, edit, search, delete', () async {
    final repo = CustomersRepository(admin);
    final c = await repo.create(
      const CustomerInput(
        name: 'ZZ Audit Customer',
        phone: '7805559991',
        email: 'zz.audit@example.com',
        isActive: true,
      ),
    );
    final u = await repo.update(
      c.id,
      const CustomerInput(
        name: 'ZZ Audit Customer B',
        phone: '7805559991',
        email: '',
        isActive: false,
      ),
    );
    expect(u.name, 'ZZ Audit Customer B');
    expect((await repo.search('ZZ Audit')).length, 1);
    expect((await repo.summary(c.id)).id, c.id);
    expect((await repo.appointments(c.id)).items, isEmpty);
    await repo.delete(c.id);
    expect(await repo.search('ZZ Audit'), isEmpty);
  });

  test('shop: closure round trip, settings round trip (restored)', () async {
    final repo = ShopRepository(admin);
    await repo.createClosure(
      const ClosureInput(
        date: '2030-01-15',
        fullDay: true,
        start: null,
        end: null,
        reason: 'ZZ AUDIT closure',
      ),
    );
    final item = (await repo.closures(q: 'ZZ AUDIT')).items.single;
    await repo.updateClosure(
      item.id,
      const ClosureInput(
        date: '2030-01-16',
        fullDay: false,
        start: '10:00',
        end: '12:00',
        reason: 'ZZ AUDIT closure B',
      ),
    );
    await repo.deleteClosure(item.id);
    expect((await repo.closures(q: 'ZZ AUDIT')).items, isEmpty);

    final before = await repo.settings();
    final g = before.general;
    await repo.saveGeneral(
      reminderDays: g.reminderDays,
      defaultDuration: g.defaultDuration,
      serviceFee: g.serviceFee.toApi(),
      invoiceMail: g.invoiceMail,
    );
    final hours = await repo.hours();
    await repo.saveHours(hours);
  });

  test('roles + staff: create with services, edit, password, delete', () async {
    final roles = RolesRepository(admin);
    final data = await roles.load();
    final perms = data.groups.first.permissions;
    await roles.create('ZZ AUDIT Role', [perms.first.id]);
    var role = (await roles.load()).roles.firstWhere(
      (r) => r.name == 'ZZ AUDIT Role',
    );
    await roles.update(role.id, 'ZZ AUDIT Role B', [
      for (final p in perms.take(2)) p.id,
    ]);

    // A deleted staff keeps its e-mail reserved (web), so each run needs its own.
    final email =
        'zz.audit.${DateTime.now().millisecondsSinceEpoch}@example.com';
    final staff = StaffRepository(admin);
    final opts = await staff.formOptions();
    final services = (await CatalogRepository(admin).services()).items;
    await staff.create(
      StaffInput(
        name: 'ZZ Audit Staff',
        email: email,
        phone: '7805559992',
        password: 'Audit@12345',
        isBarber: true,
        serviceIds: [services.first.id],
        commission: '10',
        active: true,
        roleId: opts.roles.first.id,
      ),
    );
    final m = (await staff.list(q: 'ZZ Audit')).items.single;
    await staff.update(
      m.id,
      StaffInput(
        name: 'ZZ Audit Staff B',
        email: email,
        phone: '7805559992',
        password: '',
        isBarber: true,
        serviceIds: [services.first.id, services.last.id],
        commission: '12',
        active: true,
        roleId: opts.roles.first.id,
      ),
    );
    expect(await staff.assignedServices(m.id), contains(services.first.id));
    await staff.assignServices(m.id, [services.first.id]);
    await staff.changePassword(m.id, 'Audit@54321', 'Audit@54321');
    expect((await staff.profile(m.id)).staff.name, 'ZZ Audit Staff B');
    await staff.delete(m.id);
    role = (await roles.load()).roles.firstWhere(
      (r) => r.name == 'ZZ AUDIT Role B',
    );
    await roles.delete(role.id);
  });

  test('content: testimonial round trip', () async {
    final repo = ContentRepository(admin);
    await repo.createTestimonial(
      const TestimonialInput(
        name: 'ZZ Audit',
        role: 'Tester',
        review: 'Great',
        rating: 5,
        sortOrder: '1',
        active: false,
      ),
    );
    final t = (await repo.testimonials(q: 'ZZ Audit')).items.single;
    await repo.updateTestimonial(
      t.id,
      const TestimonialInput(
        name: 'ZZ Audit B',
        role: 'Tester',
        review: 'Better',
        rating: 4,
        sortOrder: '2',
        active: false,
      ),
    );
    await repo.deleteTestimonial(t.id);
    expect((await repo.testimonials(q: 'ZZ Audit')).items, isEmpty);
    await repo.gallery();
  });
}
