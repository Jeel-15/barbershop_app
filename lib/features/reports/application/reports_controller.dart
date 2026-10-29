import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/reports/data/reports_repository.dart';
import 'package:barbershop_app/features/reports/domain/report_models.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Start Date / End Date / Staff Name, shared by every tab.
class ReportsFilterNotifier extends Notifier<ReportsFilter> {
  @override
  ReportsFilter build() => const ReportsFilter();

  void set(ReportsFilter f) => state = f;
}

final reportsFilterProvider =
    NotifierProvider<ReportsFilterNotifier, ReportsFilter>(
      ReportsFilterNotifier.new,
    );

/// The people the "Staff Name" filter offers: the team list, or (without the
/// rights for it) the barbers of the invoice screen. Empty = no filter.
final reportStaffOptionsProvider =
    FutureProvider.autoDispose<List<({int id, String name})>>((ref) async {
      ref.watch(currentUserProvider);
      try {
        final page = await ref.read(staffRepositoryProvider).list(perPage: 50);
        return [
          for (final s in page.items)
            if (s.panelRole == 'Staff') (id: s.id, name: s.name),
        ];
      } catch (_) {
        try {
          final catalog = await ref.read(posRepositoryProvider).catalog();
          return [for (final s in catalog.staff) (id: s.id, name: s.name)];
        } catch (_) {
          return const [];
        }
      }
    });

final reportOverviewProvider = FutureProvider.autoDispose<ReportOverview>((
  ref,
) {
  ref.watch(currentUserProvider);
  return ref
      .read(reportsRepositoryProvider)
      .overview(ref.watch(reportsFilterProvider));
});

final reportPaymentsProvider = FutureProvider.autoDispose<List<PaymentRow>>(
  (ref) => ref
      .read(reportsRepositoryProvider)
      .payments(ref.watch(reportsFilterProvider)),
);

final reportStaffProvider =
    FutureProvider.autoDispose<List<StaffPerformanceRow>>(
      (ref) => ref
          .read(reportsRepositoryProvider)
          .staff(ref.watch(reportsFilterProvider)),
    );

final reportTopProductsProvider = FutureProvider.autoDispose<TopProducts>(
  (ref) => ref
      .read(reportsRepositoryProvider)
      .topProducts(ref.watch(reportsFilterProvider)),
);

final reportEarningProvider =
    AsyncNotifierProvider.autoDispose<
      EarningController,
      PagedState<EarningRow>
    >(EarningController.new, retry: (_, _) => null);

class EarningController extends PagedNotifier<EarningRow> {
  @override
  Future<PagedResult<EarningRow>> fetch(int page) => ref
      .read(reportsRepositoryProvider)
      .earning(ref.read(reportsFilterProvider), page: page);

  @override
  Future<PagedState<EarningRow>> build() {
    ref.watch(reportsFilterProvider);
    return super.build();
  }
}

final reportInvoicesProvider =
    AsyncNotifierProvider.autoDispose<
      InvoicesReportController,
      PagedState<InvoiceReportRow>
    >(InvoicesReportController.new, retry: (_, _) => null);

class InvoicesReportController extends PagedNotifier<InvoiceReportRow> {
  @override
  Future<PagedResult<InvoiceReportRow>> fetch(int page) => ref
      .read(reportsRepositoryProvider)
      .invoices(ref.read(reportsFilterProvider), page: page);

  @override
  Future<PagedState<InvoiceReportRow>> build() {
    ref.watch(reportsFilterProvider);
    return super.build();
  }
}

final reportProductSalesProvider =
    AsyncNotifierProvider.autoDispose<
      ProductSalesController,
      PagedState<ProductSaleRow>
    >(ProductSalesController.new, retry: (_, _) => null);

class ProductSalesController extends PagedNotifier<ProductSaleRow> {
  @override
  Future<PagedResult<ProductSaleRow>> fetch(int page) => ref
      .read(reportsRepositoryProvider)
      .productSales(ref.read(reportsFilterProvider), page: page);

  @override
  Future<PagedState<ProductSaleRow>> build() {
    ref.watch(reportsFilterProvider);
    return super.build();
  }
}
