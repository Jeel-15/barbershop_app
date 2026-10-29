import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

PosCatalog sampleCatalog() => const PosCatalog(
  categories: [
    CatalogCategory(
      id: 1,
      name: 'Haircuts',
      services: [
        CatalogService(
          id: 25,
          name: "Men's cut",
          price: Money(3000),
          durationMinutes: 30,
        ),
        CatalogService(
          id: 26,
          name: 'Skin fade',
          price: Money(3500),
          durationMinutes: 30,
        ),
      ],
    ),
  ],
  products: [
    CatalogProduct(id: 1, name: 'Hair oil', price: Money(2000), stock: 10),
  ],
  staff: [StaffOption(42, 'mike'), StaffOption(49, 'Mutaz')],
  paymentMethods: ['Cash', 'Online', 'Debit'],
  defaultPayment: 'Cash',
  taxLabel: 'GST 5% included',
);

/// Fake server: totals are the plain sum, minus the service discount, plus tip.
class FakePosRepo extends PosRepository {
  FakePosRepo() : super(_NoApi());

  final calls = <String>[];
  final drafts = <InvoiceDraft>[];

  @override
  Future<PosCatalog> catalog() async => sampleCatalog();

  @override
  Future<List<CustomerLookup>> lookupCustomer(String phone) async {
    calls.add('lookup:$phone');
    return phone == '7805550103'
        ? const [
            CustomerLookup(
              id: 7,
              name: 'Sam Patel',
              phone: '7805550103',
              email: 'sam@example.com',
              visits: 3,
              lastService: 'Skin fade',
              lastSpend: Money(8500),
            ),
          ]
        : const [];
  }

  @override
  Future<InvoiceTotals> preview(InvoiceDraft draft) async {
    var svc = 0;
    var prod = 0;
    for (final l in draft.lines) {
      final v = l.price.cents * l.qty;
      if (l.type == LineType.service) {
        svc += v;
      } else {
        prod += v;
      }
    }
    final disc = (svc * draft.serviceDiscount / 100).round();
    final sub = svc - disc + prod;
    return InvoiceTotals(
      serviceTotal: Money(svc),
      serviceDiscountPercent: draft.serviceDiscount,
      serviceDiscountAmount: Money(disc),
      productTotal: Money(prod),
      productDiscountPercent: 0,
      productDiscountAmount: Money.zero,
      subtotal: Money(sub),
      tax: Money((sub * 5 / 105).round()),
      taxRate: 5,
      taxIncluded: true,
      tip: draft.tip,
      finalTotal: Money(sub) + draft.tip,
    );
  }

  @override
  Future<void> completeAppointment(
    int appointmentId,
    InvoiceDraft draft,
  ) async {
    calls.add('complete:$appointmentId');
    drafts.add(draft);
  }

  @override
  Future<void> updateInvoice(int id, InvoiceDraft draft) async {
    calls.add('update:$id');
    drafts.add(draft);
  }

  @override
  Future<void> createInvoice(
    InvoiceDraft draft, {
    required String idempotencyKey,
  }) async {
    calls.add('create');
    drafts.add(draft);
  }
}
