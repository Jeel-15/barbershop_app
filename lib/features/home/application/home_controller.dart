import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/design_system/tokens/colors.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/home/data/dashboard_repository.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

final homeProvider = AsyncNotifierProvider<HomeController, HomeData>(
  HomeController.new,
  // Failures reach the screen at once (its Try again button retries); no
  // hidden automatic retry loop behind a skeleton.
  retry: (_, _) => null,
);

/// Loads Home. Online: fresh data (and a saved copy). Offline or server down:
/// the saved copy with `fromCache` set, so the page can say so.
class HomeController extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() async {
    final user = ref.watch(currentUserProvider);
    final key = 'home:${user.id}';
    final cache = ref.read(readCacheProvider);
    try {
      final raw = await ref.read(dashboardRepositoryProvider).load();
      await cache.put(key, raw);
      return HomeData.fromRaw(raw);
    } on Failure catch (f) {
      final saved = cache.get(key, ttl: const Duration(days: 365));
      final retryable =
          f is NetworkFailure || f is TimeoutFailure || f is ServerFailure;
      if (saved != null && saved.value is Map && retryable) {
        return HomeData.fromRaw(
          Map<String, dynamic>.from(saved.value! as Map),
          fromCache: true,
        );
      }
      rethrow;
    }
  }

  /// Pull-to-refresh. Keeps the current data on screen until the new data lands.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// One-tap Confirm from Home: the pill flips at once, and flips back with
  /// the server's reason if it is refused (409: already changed elsewhere).
  Future<void> confirm(AppointmentRow row) async {
    final before = state.value;
    if (before == null) return;
    AppointmentRow flip(AppointmentRow r) => r.id == row.id
        ? r.copyWith(
            status: AppointmentStatus.confirmed,
            actions: const ['cancel', 'view'],
          )
        : r;
    state = AsyncData(before.withToday(before.today.map(flip).toList()));
    try {
      await ref.read(appointmentsRepositoryProvider).confirm(row.id);
    } on Failure {
      state = AsyncData(before);
      rethrow;
    } finally {
      // Counts and lists may have moved: reload quietly.
      ref.invalidateSelf();
    }
  }
}
