import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The filters the user chose (status tab, search, filter sheet).
class AppointmentFilterNotifier extends Notifier<AppointmentFilter> {
  @override
  AppointmentFilter build() => const AppointmentFilter();

  void set(AppointmentFilter f) => state = f;
}

final appointmentFilterProvider =
    NotifierProvider<AppointmentFilterNotifier, AppointmentFilter>(
      AppointmentFilterNotifier.new,
    );

/// Rows loaded so far plus what is needed to load the next page.
class AppointmentListState {
  const AppointmentListState({
    required this.items,
    required this.hasMore,
    required this.total,
    this.page = 1,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<AppointmentRow> items;
  final bool hasMore;
  final int total;
  final int page;
  final bool loadingMore;
  final bool loadMoreFailed;

  AppointmentListState copyWith({
    List<AppointmentRow>? items,
    bool? hasMore,
    int? page,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => AppointmentListState(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    total: total,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

final appointmentListProvider =
    AsyncNotifierProvider<AppointmentListController, AppointmentListState>(
      AppointmentListController.new,
      retry: (_, _) => null,
    );

/// The appointment list: reloads when a filter changes, loads the next page
/// when the user nears the end.
class AppointmentListController extends AsyncNotifier<AppointmentListState> {
  @override
  Future<AppointmentListState> build() async {
    ref.watch(currentUserProvider);
    final filter = ref.watch(appointmentFilterProvider);
    final page = await ref.read(appointmentsRepositoryProvider).list(filter);
    return AppointmentListState(
      items: page.items,
      hasMore: page.hasMore,
      total: page.total,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    ref.invalidate(appointmentCountsProvider);
    await future;
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final next = await ref
          .read(appointmentsRepositoryProvider)
          .list(ref.read(appointmentFilterProvider), page: s.page + 1);
      state = AsyncData(
        s.copyWith(
          items: [...s.items, ...next.items],
          hasMore: next.hasMore,
          page: s.page + 1,
          loadingMore: false,
        ),
      );
    } catch (_) {
      // Keep what is shown; the footer offers a retry.
      state = AsyncData(s.copyWith(loadingMore: false, loadMoreFailed: true));
    }
  }
}

final appointmentCountsProvider = FutureProvider<AppointmentCounts>((
  ref,
) async {
  ref.watch(currentUserProvider);
  return ref.read(appointmentsRepositoryProvider).counts();
});

final appointmentDetailProvider = FutureProvider.autoDispose
    .family<AppointmentDetail, int>((ref, id) async {
      return ref.read(appointmentsRepositoryProvider).detail(id);
    });
