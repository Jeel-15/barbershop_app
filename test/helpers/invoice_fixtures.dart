import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// `GET /invoices/{id}` as the API sends it (trimmed). [guest] = the web's
/// placeholder customer.
Map<String, dynamic> invoiceJson(
  int id, {
  String name = 'Sam Patel',
  String? email = 'sam@example.com',
  String? phone = '7805550103',
  bool guest = false,
}) => {
  'id': id,
  'invoice_number': 'GEN-2610-000$id',
  'customer': {
    'id': 3,
    'name': guest ? 'Guest Customer' : name,
    'phone': guest ? '(555) 123-4567' : phone,
    'email': guest ? 'info@bluecrownbarbers.com' : email,
  },
  'staff_names': 'mike',
  'date': '2026-10-25',
  'invoiced_at': '2026-10-25 15:10:00',
  'payment_method': 'Cash',
  'total': '83.50',
  'status_label': 'Paid',
  'can_edit': true,
  'notes': null,
  'lines': [
    {
      'type': 'service',
      'id': 25,
      'name': "Men's cut",
      'staff_id': 42,
      'staff_name': 'mike',
      'price': '30.00',
    },
    {
      'type': 'service',
      'id': 26,
      'name': 'Skin fade',
      'staff_id': 42,
      'staff_name': 'mike',
      'price': '35.00',
    },
    {
      'type': 'product',
      'id': 1,
      'name': 'Hair oil',
      'staff_id': 42,
      'staff_name': 'mike',
      'price': '20.00',
    },
  ],
  'cart': [
    {'type': 'service', 'id': 25, 'staff_id': 42, 'qty': 1},
    {'type': 'service', 'id': 26, 'staff_id': 42, 'qty': 1},
    {'type': 'product', 'id': 1, 'staff_id': 42, 'qty': 1},
  ],
  'breakdown': {
    'service_total': '65.00',
    'service_discount_percent': '10.00',
    'product_total': '20.00',
    'product_discount_percent': '0.00',
    'total_discount': '6.50',
    'tax': '4.00',
    'tip': '5.00',
    'total': '83.50',
  },
};

class FakeInvoicesRepo extends InvoicesRepository {
  FakeInvoicesRepo({this.guest = false}) : super(_NoApi());

  final bool guest;
  final calls = <String>[];

  @override
  Future<PagedResult<InvoiceRow>> list({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('list:$q');
    final all = [
      InvoiceRow.fromJson(invoiceJson(5, guest: guest)),
      InvoiceRow.fromJson(invoiceJson(4, name: 'Daniel Okafor')),
    ];
    final hit = [
      for (final r in all)
        if (q.isEmpty || r.customerName.toLowerCase().contains(q.toLowerCase()))
          r,
    ];
    return PagedResult(items: hit, hasMore: false, total: hit.length);
  }

  @override
  Future<InvoiceDetail> detail(int id) async =>
      InvoiceDetail.fromJson(invoiceJson(id, guest: guest));

  @override
  Future<String> sendEmail(int id, {String? email}) async {
    calls.add('mail:$id:${email ?? '-'}');
    return 'Mail Successfully Send';
  }
}
