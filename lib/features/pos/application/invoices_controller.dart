import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The search text of the Invoices list (invoice number, name or phone).
class InvoiceQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final invoiceQueryProvider = NotifierProvider<InvoiceQueryNotifier, String>(
  InvoiceQueryNotifier.new,
);

class InvoiceListState {
  const InvoiceListState({
    required this.items,
    required this.hasMore,
    required this.total,
    this.page = 1,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<InvoiceRow> items;
  final bool hasMore;
  final int total;
  final int page;
  final bool loadingMore;
  final bool loadMoreFailed;

  InvoiceListState copyWith({
    List<InvoiceRow>? items,
    bool? hasMore,
    int? page,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => InvoiceListState(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    total: total,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

final invoiceListProvider =
    AsyncNotifierProvider<InvoiceListController, InvoiceListState>(
      InvoiceListController.new,
      retry: (_, _) => null,
    );

/// The Invoices list, newest first: reloads on search, pages as it is scrolled.
/// The server already limits staff to the invoices they may see.
class InvoiceListController extends AsyncNotifier<InvoiceListState> {
  @override
  Future<InvoiceListState> build() async {
    ref.watch(currentUserProvider);
    final q = ref.watch(invoiceQueryProvider);
    final page = await ref.read(invoicesRepositoryProvider).list(q: q);
    return InvoiceListState(
      items: page.items,
      hasMore: page.hasMore,
      total: page.total,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final next = await ref
          .read(invoicesRepositoryProvider)
          .list(q: ref.read(invoiceQueryProvider), page: s.page + 1);
      state = AsyncData(
        s.copyWith(
          items: [...s.items, ...next.items],
          hasMore: next.hasMore,
          page: s.page + 1,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(s.copyWith(loadingMore: false, loadMoreFailed: true));
    }
  }
}
