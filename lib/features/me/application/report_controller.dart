import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Start Date / End Date / Status the staff member chose.
class ReportFilterNotifier extends Notifier<ReportFilter> {
  @override
  ReportFilter build() => const ReportFilter();

  void set(ReportFilter f) => state = f;
}

final reportFilterProvider =
    NotifierProvider<ReportFilterNotifier, ReportFilter>(
      ReportFilterNotifier.new,
    );

/// The four earning cards; follows the filter.
final reportSummaryProvider = FutureProvider.autoDispose<ReportSummary>((ref) {
  ref.watch(currentUserProvider);
  return ref
      .read(meRepositoryProvider)
      .reportSummary(ref.watch(reportFilterProvider));
});

final reportAppointmentsProvider =
    AsyncNotifierProvider.autoDispose<
      ReportAppointmentsController,
      PagedState<ReportAppointment>
    >(ReportAppointmentsController.new, retry: (_, _) => null);

class ReportAppointmentsController extends PagedNotifier<ReportAppointment> {
  @override
  Future<PagedResult<ReportAppointment>> fetch(int page) => ref
      .read(meRepositoryProvider)
      .reportAppointments(ref.read(reportFilterProvider), page: page);

  @override
  Future<PagedState<ReportAppointment>> build() {
    ref.watch(reportFilterProvider);
    return super.build();
  }
}

final reportServicesProvider =
    AsyncNotifierProvider.autoDispose<
      ReportServicesController,
      PagedState<ServiceEarning>
    >(ReportServicesController.new, retry: (_, _) => null);

class ReportServicesController extends PagedNotifier<ServiceEarning> {
  @override
  Future<PagedResult<ServiceEarning>> fetch(int page) =>
      ref.read(meRepositoryProvider).reportServices(page: page);
}

final reportDaysProvider =
    AsyncNotifierProvider.autoDispose<
      ReportDaysController,
      PagedState<DailyEarning>
    >(ReportDaysController.new, retry: (_, _) => null);

class ReportDaysController extends PagedNotifier<DailyEarning> {
  @override
  Future<PagedResult<DailyEarning>> fetch(int page) =>
      ref.read(meRepositoryProvider).reportDays(page: page);
}
