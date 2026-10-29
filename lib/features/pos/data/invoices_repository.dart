import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// POS-4, POS-5, POS-7: the invoice list, one invoice, and mailing it.
/// (Creating and editing live in [PosRepository], next to the totals.)
class InvoicesRepository {
  const InvoicesRepository(this._api);

  final ApiClient _api;

  Future<PagedResult<InvoiceRow>> list({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/invoices',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'per_page': perPage,
      },
    );
    return PagedResult(
      items: [
        for (final r in (res.data['items'] as List? ?? const []))
          InvoiceRow.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
      hasMore: res.meta['has_more'] == true,
      total: (res.meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<InvoiceDetail> detail(int id) async {
    final res = await _api.get('/invoices/$id');
    return InvoiceDetail.fromJson(
      Map<String, dynamic>.from(res.data['invoice'] as Map),
    );
  }

  /// "Send Invoice Mail". [email] overrides the customer's address.
  /// Returns the server's message.
  Future<String> sendEmail(int id, {String? email}) async {
    final res = await _api.post(
      '/invoices/$id/email',
      body: {
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
    );
    return res.message;
  }
}

final invoicesRepositoryProvider = Provider<InvoicesRepository>(
  (ref) => InvoicesRepository(ref.watch(apiClientProvider)),
);

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<InvoiceDetail, int>(
      (ref, id) => ref.read(invoicesRepositoryProvider).detail(id),
    );
