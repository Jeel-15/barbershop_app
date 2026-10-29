import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/reports/domain/report_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RPT-1..6: the six admin reports. All take the same filters.
class ReportsRepository {
  const ReportsRepository(this._api);

  final ApiClient _api;

  Map<String, dynamic> _summary(ApiResponse r) =>
      Map<String, dynamic>.from((r.meta['summary'] as Map?) ?? const {});

  PagedResult<T> _page<T>(
    ApiResponse res,
    T Function(Map<String, dynamic>) parse,
  ) => PagedResult(
    items: [
      for (final e in (res.data['items'] as List? ?? const []))
        parse(Map<String, dynamic>.from(e as Map)),
    ],
    hasMore: res.meta['has_more'] == true,
    total: (res.meta['total'] as num?)?.toInt() ?? 0,
  );

  /// The cards (Total Revenue, Total Appointment, ...), from the first row's summary.
  Future<ReportOverview> overview(ReportsFilter f) async {
    final res = await _api.get(
      '/reports/appointments',
      query: {...f.toQuery(), 'per_page': 1},
    );
    return ReportOverview.fromJson(_summary(res));
  }

  /// Earning tab.
  Future<PagedResult<EarningRow>> earning(
    ReportsFilter f, {
    int page = 1,
    int perPage = 20,
  }) async => _page(
    await _api.get(
      '/reports/appointments',
      query: {...f.toQuery(), 'page': page, 'per_page': perPage},
    ),
    EarningRow.fromJson,
  );

  /// Payment Methods tab.
  Future<List<PaymentRow>> payments(ReportsFilter f) async {
    final res = await _api.get('/reports/payments', query: f.toQuery());
    return [
      for (final r in (res.data['items'] as List? ?? const []))
        PaymentRow.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Staff tab.
  Future<List<StaffPerformanceRow>> staff(ReportsFilter f) async {
    final res = await _api.get('/reports/staff-earnings', query: f.toQuery());
    return [
      for (final r in (res.data['items'] as List? ?? const []))
        StaffPerformanceRow.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Invoice tab.
  Future<PagedResult<InvoiceReportRow>> invoices(
    ReportsFilter f, {
    int page = 1,
    int perPage = 20,
  }) async => _page(
    await _api.get(
      '/reports/customer-invoices',
      query: {...f.toQuery(), 'page': page, 'per_page': perPage},
    ),
    InvoiceReportRow.fromJson,
  );

  /// Product tab (Product Sell History).
  Future<PagedResult<ProductSaleRow>> productSales(
    ReportsFilter f, {
    int page = 1,
    int perPage = 20,
  }) async => _page(
    await _api.get(
      '/reports/product-sales',
      query: {...f.toQuery(), 'page': page, 'per_page': perPage},
    ),
    ProductSaleRow.fromJson,
  );

  /// Top Selling Products tab.
  Future<TopProducts> topProducts(ReportsFilter f) async {
    final res = await _api.get('/reports/top-products', query: f.toQuery());
    return TopProducts.fromJson(
      (res.data['items'] as List? ?? const []),
      _summary(res),
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);
