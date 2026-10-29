import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The search text of the Customers list.
class CustomerQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final customerQueryProvider = NotifierProvider<CustomerQueryNotifier, String>(
  CustomerQueryNotifier.new,
);

class CustomerListState {
  const CustomerListState({
    required this.items,
    required this.hasMore,
    required this.total,
    this.page = 1,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<CustomerSummary> items;
  final bool hasMore;
  final int total;
  final int page;
  final bool loadingMore;
  final bool loadMoreFailed;

  CustomerListState copyWith({
    List<CustomerSummary>? items,
    bool? hasMore,
    int? page,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => CustomerListState(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    total: total,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

final customerListProvider =
    AsyncNotifierProvider<CustomerListController, CustomerListState>(
      CustomerListController.new,
      retry: (_, _) => null,
    );

/// The Customers list: reloads when the search changes, pages as it is scrolled.
class CustomerListController extends AsyncNotifier<CustomerListState> {
  @override
  Future<CustomerListState> build() async {
    ref.watch(currentUserProvider);
    final q = ref.watch(customerQueryProvider);
    final page = await ref.read(customersRepositoryProvider).list(q: q);
    return CustomerListState(
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
          .read(customersRepositoryProvider)
          .list(q: ref.read(customerQueryProvider), page: s.page + 1);
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

class CustomerAppointmentsState {
  const CustomerAppointmentsState({
    required this.items,
    required this.hasMore,
    required this.total,
    this.page = 1,
    this.loadingMore = false,
  });

  final List<CustomerAppointment> items;
  final bool hasMore;
  final int total;
  final int page;
  final bool loadingMore;
}

final customerAppointmentsProvider = AsyncNotifierProvider.autoDispose
    .family<CustomerAppointmentsController, CustomerAppointmentsState, int>(
      CustomerAppointmentsController.new,
      retry: (_, _) => null,
    );

/// The profile's appointment table, newest first.
class CustomerAppointmentsController
    extends AsyncNotifier<CustomerAppointmentsState> {
  CustomerAppointmentsController(this.customerId);

  final int customerId;

  @override
  Future<CustomerAppointmentsState> build() async {
    final page = await ref
        .read(customersRepositoryProvider)
        .appointments(customerId);
    return CustomerAppointmentsState(
      items: page.items,
      hasMore: page.hasMore,
      total: page.total,
    );
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(
      CustomerAppointmentsState(
        items: s.items,
        hasMore: s.hasMore,
        total: s.total,
        page: s.page,
        loadingMore: true,
      ),
    );
    try {
      final next = await ref
          .read(customersRepositoryProvider)
          .appointments(customerId, page: s.page + 1);
      state = AsyncData(
        CustomerAppointmentsState(
          items: [...s.items, ...next.items],
          hasMore: next.hasMore,
          total: s.total,
          page: s.page + 1,
        ),
      );
    } catch (_) {
      state = AsyncData(
        CustomerAppointmentsState(
          items: s.items,
          hasMore: s.hasMore,
          total: s.total,
          page: s.page,
        ),
      );
    }
  }
}
