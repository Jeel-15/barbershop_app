import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/reports/data/reports_repository.dart';
import 'package:barbershop_app/features/reports/domain/report_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeReports extends ReportsRepository {
  FakeReports() : super(_NoApi());

  final calls = <String>[];

  String _f(ReportsFilter f) =>
      '${f.start ?? '-'}:${f.end ?? '-'}:${f.staffId ?? '-'}';

  @override
  Future<ReportOverview> overview(ReportsFilter f) async {
    calls.add('overview:${_f(f)}');
    return ReportOverview.fromJson({
      'total_revenue': '1250.00',
      'total_appointments': 42,
      'total_discount': '60.00',
      'total_tips': '88.50',
      'staff_total_earning': '510.00',
      'staff_total_product_commission': '30.00',
      'staff_total_service_commission': '400.00',
      'staff_total_service_tip': '80.00',
    });
  }

  @override
  Future<PagedResult<EarningRow>> earning(
    ReportsFilter f, {
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('earning:${_f(f)}');
    return PagedResult(
      items: [
        EarningRow.fromJson({
          'id': 5,
          'date': '2026-10-25',
          'start_label': '09:30 AM',
          'end_label': '10:15 AM',
          'customer': {'name': 'Sam Patel', 'phone': '7805550103'},
          'sub_total': '78.50',
          'discount': '6.50',
          'tip': '5.00',
          'total': '83.50',
        }),
      ],
      hasMore: false,
      total: 1,
    );
  }

  @override
  Future<List<PaymentRow>> payments(ReportsFilter f) async => [
    PaymentRow.fromJson({'method': 'Cash', 'revenue': '800.00'}),
    PaymentRow.fromJson({'method': 'Online', 'revenue': '450.00'}),
  ];

  @override
  Future<List<StaffPerformanceRow>> staff(ReportsFilter f) async => [
    StaffPerformanceRow.fromJson({
      'staff_id': 42,
      'staff_name': 'Mike',
      'appointments': 12,
      'tips': '48.50',
      'service_commission': '210.00',
      'product_commission': '15.00',
      'total_earning': '273.50',
    }),
  ];

  @override
  Future<PagedResult<InvoiceReportRow>> invoices(
    ReportsFilter f, {
    int page = 1,
    int perPage = 20,
  }) async => PagedResult(
    items: [
      InvoiceReportRow.fromJson({
        'id': 5,
        'invoice_number': 'GEN-2610-0005',
        'date': '2026-10-25',
        'customer_name': 'Sam Patel',
        'staff_names': 'Mike',
        'amount': '30.00',
        'total': '83.50',
      }),
    ],
    hasMore: false,
    total: 1,
  );

  @override
  Future<PagedResult<ProductSaleRow>> productSales(
    ReportsFilter f, {
    int page = 1,
    int perPage = 20,
  }) async => PagedResult(
    items: [
      ProductSaleRow.fromJson({
        'id': 1,
        'product_name': 'Hair oil',
        'customer_name': 'Sam Patel',
        'staff_name': 'Mike',
        'sell_date': '2026-10-25',
        'amount': '20.00',
      }),
    ],
    hasMore: false,
    total: 1,
  );

  @override
  Future<TopProducts> topProducts(ReportsFilter f) async =>
      TopProducts.fromJson(
        [
          {
            'product_id': 1,
            'product_name': 'Hair oil',
            'price': '20.00',
            'units_sold': 7,
            'commission': '7.00',
            'revenue': '120.00',
            'discount': '4.00',
          },
        ],
        {
          'total_product_amount': '140.00',
          'total_discount': '4.00',
          'total_commission': '7.00',
          'total_revenue': '120.00',
          'total_units_sold': 7,
        },
      );
}
