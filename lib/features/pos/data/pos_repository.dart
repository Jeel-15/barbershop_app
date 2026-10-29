import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A returning customer found by phone (the web's "Search Customer" card).
class CustomerLookup {
  const CustomerLookup({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.visits,
    required this.lastService,
    required this.lastSpend,
  });

  factory CustomerLookup.fromJson(Map<String, dynamic> j) => CustomerLookup(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    phone: (j['phone'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    visits: (j['visits'] as num?)?.toInt() ?? 0,
    lastService: (j['last_service'] ?? '—').toString(),
    // The web hides spend from staff: the server sends null for them.
    lastSpend: j['total_spend'] == null ? null : Money.parse(j['total_spend']),
  );

  final int id;
  final String name;
  final String phone;
  final String email;
  final int visits;
  final String lastService;

  /// Null for staff.
  final Money? lastSpend;
}

/// POS-1, POS-8, POS-3 and APPT-11: what can be sold, the server's totals,
/// and saving the invoice (new, or by completing an appointment).
class PosRepository {
  const PosRepository(this._api);

  final ApiClient _api;

  /// The web's phone search (from 10 digits): who this number belongs to.
  Future<List<CustomerLookup>> lookupCustomer(String phone) async {
    final res = await _api.get('/pos/customer-lookup', query: {'phone': phone});
    return [
      for (final c in (res.data['customers'] as List? ?? const []))
        CustomerLookup.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
  }

  Future<PosCatalog> catalog() async {
    final res = await _api.get('/pos/catalog');
    return PosCatalog.fromJson(res.data);
  }

  Future<InvoiceTotals> preview(InvoiceDraft draft) async {
    final res = await _api.post(
      '/invoices/preview',
      body: draft.toCart(withCustomer: false),
    );
    return InvoiceTotals.fromJson(res.data);
  }

  /// Completes a booked appointment into a paid invoice (the web's "Complete").
  Future<void> completeAppointment(
    int appointmentId,
    InvoiceDraft draft,
  ) async {
    await _api.post(
      '/appointments/$appointmentId/complete',
      body: draft.toCart(withCustomer: false),
    );
  }

  /// A new invoice. [idempotencyKey] makes a retry harmless: the same key never
  /// creates a second invoice.
  Future<void> createInvoice(
    InvoiceDraft draft, {
    required String idempotencyKey,
  }) async {
    await _api.post(
      '/invoices',
      body: draft.toCart(),
      headers: {'Idempotency-Key': idempotencyKey},
    );
  }

  /// Saves the edits of an existing invoice (the web's "Update").
  Future<void> updateInvoice(int id, InvoiceDraft draft) async {
    await _api.put('/invoices/$id', body: draft.toCart());
  }
}

final posRepositoryProvider = Provider<PosRepository>(
  (ref) => PosRepository(ref.watch(apiClientProvider)),
);

final posCatalogProvider = FutureProvider.autoDispose<PosCatalog>(
  (ref) => ref.read(posRepositoryProvider).catalog(),
);

final customerLookupProvider = FutureProvider.autoDispose
    .family<List<CustomerLookup>, String>(
      (ref, phone) => ref.read(posRepositoryProvider).lookupCustomer(phone),
    );
