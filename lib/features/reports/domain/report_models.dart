import 'package:barbershop_app/core/utils/money.dart';

/// The filters of the Reports page (web: Start Date, End Date, Staff Name).
class ReportsFilter {
  const ReportsFilter({this.start, this.end, this.staffId});

  /// `yyyy-MM-dd`.
  final String? start;
  final String? end;

  /// Null = All Staff.
  final int? staffId;

  bool get isClear => start == null && end == null && staffId == null;

  int get activeCount =>
      (start != null || end != null ? 1 : 0) + (staffId != null ? 1 : 0);

  ReportsFilter copyWith({
    Object? start = _keep,
    Object? end = _keep,
    Object? staffId = _keep,
  }) => ReportsFilter(
    start: identical(start, _keep) ? this.start : start as String?,
    end: identical(end, _keep) ? this.end : end as String?,
    staffId: identical(staffId, _keep) ? this.staffId : staffId as int?,
  );

  static const _keep = Object();

  Map<String, dynamic> toQuery() => {
    'start_date': ?start,
    'end_date': ?end,
    'staff_id': ?staffId,
  };

  @override
  bool operator ==(Object other) =>
      other is ReportsFilter &&
      other.start == start &&
      other.end == end &&
      other.staffId == staffId;

  @override
  int get hashCode => Object.hash(start, end, staffId);
}

/// The four cards on top of the page and the Earning tab's four cards.
class ReportOverview {
  const ReportOverview({
    required this.revenue,
    required this.appointments,
    required this.discount,
    required this.tips,
    required this.earning,
    required this.productCommission,
    required this.serviceCommission,
    required this.serviceTips,
  });

  factory ReportOverview.fromJson(Map<String, dynamic> j) => ReportOverview(
    revenue: Money.parse(j['total_revenue']),
    appointments: (j['total_appointments'] as num?)?.toInt() ?? 0,
    discount: Money.parse(j['total_discount']),
    tips: Money.parse(j['total_tips']),
    earning: Money.parse(j['staff_total_earning']),
    productCommission: Money.parse(j['staff_total_product_commission']),
    serviceCommission: Money.parse(j['staff_total_service_commission']),
    serviceTips: Money.parse(j['staff_total_service_tip']),
  );

  final Money revenue;
  final int appointments;
  final Money discount;
  final Money tips;
  final Money earning;
  final Money productCommission;
  final Money serviceCommission;
  final Money serviceTips;
}

/// Earning tab row: Name, Date, Time, Sub Total, Discount, Total Amount, Total Tip, Status.
class EarningRow {
  const EarningRow({
    required this.id,
    required this.customerName,
    required this.date,
    required this.startLabel,
    required this.endLabel,
    required this.subTotal,
    required this.discount,
    required this.total,
    required this.tip,
  });

  factory EarningRow.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['customer'] as Map?) ?? const {});
    return EarningRow(
      id: (j['id'] as num).toInt(),
      customerName: (c['name'] ?? '').toString(),
      date: (j['date'] ?? '').toString(),
      startLabel: (j['start_label'] ?? '').toString(),
      endLabel: (j['end_label'] ?? '').toString(),
      subTotal: Money.parse(j['sub_total']),
      discount: Money.parse(j['discount']),
      total: Money.parse(j['total']),
      tip: Money.parse(j['tip']),
    );
  }

  final int id;
  final String customerName;
  final String date;
  final String startLabel;
  final String endLabel;
  final Money subTotal;
  final Money discount;
  final Money total;
  final Money tip;
}

/// Payment Methods tab: Method, Revenue.
class PaymentRow {
  const PaymentRow(this.method, this.revenue);

  factory PaymentRow.fromJson(Map<String, dynamic> j) =>
      PaymentRow((j['method'] ?? '').toString(), Money.parse(j['revenue']));

  final String method;
  final Money revenue;
}

/// Staff tab: a barber's performance.
class StaffPerformanceRow {
  const StaffPerformanceRow({
    required this.staffId,
    required this.name,
    required this.appointments,
    required this.tips,
    required this.serviceCommission,
    required this.productCommission,
    required this.totalEarning,
  });

  factory StaffPerformanceRow.fromJson(Map<String, dynamic> j) =>
      StaffPerformanceRow(
        staffId: (j['staff_id'] as num?)?.toInt(),
        name: (j['staff_name'] ?? '-').toString(),
        appointments: (j['appointments'] as num?)?.toInt() ?? 0,
        tips: Money.parse(j['tips']),
        serviceCommission: Money.parse(j['service_commission']),
        productCommission: Money.parse(j['product_commission']),
        totalEarning: Money.parse(j['total_earning']),
      );

  final int? staffId;
  final String name;
  final int appointments;
  final Money tips;
  final Money serviceCommission;
  final Money productCommission;
  final Money totalEarning;
}

/// Invoice tab row.
class InvoiceReportRow {
  const InvoiceReportRow({
    required this.id,
    required this.number,
    required this.customerName,
    required this.staffNames,
    required this.date,
    required this.staffEarned,
    required this.total,
  });

  factory InvoiceReportRow.fromJson(Map<String, dynamic> j) => InvoiceReportRow(
    id: (j['id'] as num).toInt(),
    number: (j['invoice_number'] ?? '').toString(),
    customerName: (j['customer_name'] ?? '-').toString(),
    staffNames: (j['staff_names'] ?? '-').toString(),
    date: (j['date'] ?? '').toString(),
    staffEarned: Money.parse(j['amount']),
    total: Money.parse(j['total']),
  );

  final int id;
  final String number;
  final String customerName;
  final String staffNames;
  final String date;

  /// The web's "Amount" column: commission + tips of the staff on this invoice.
  final Money staffEarned;

  /// What the customer paid.
  final Money total;
}

/// Product tab row: Product Name, Sell By, Customer Name, Date, Product Price.
class ProductSaleRow {
  const ProductSaleRow({
    required this.id,
    required this.product,
    required this.customer,
    required this.staff,
    required this.date,
    required this.amount,
  });

  factory ProductSaleRow.fromJson(Map<String, dynamic> j) => ProductSaleRow(
    id: (j['id'] as num).toInt(),
    product: (j['product_name'] ?? '').toString(),
    customer: (j['customer_name'] ?? '').toString(),
    staff: (j['staff_name'] ?? '-').toString(),
    date: (j['sell_date'] ?? '').toString(),
    amount: Money.parse(j['amount']),
  );

  final int id;
  final String product;
  final String customer;
  final String staff;
  final String date;
  final Money amount;
}

/// Top Selling Products tab row.
class TopProductRow {
  const TopProductRow({
    required this.name,
    required this.price,
    required this.units,
    required this.discount,
    required this.commission,
    required this.revenue,
  });

  factory TopProductRow.fromJson(Map<String, dynamic> j) => TopProductRow(
    name: (j['product_name'] ?? '').toString(),
    price: Money.parse(j['price']),
    units: (j['units_sold'] as num?)?.toInt() ?? 0,
    discount: Money.parse(j['discount']),
    commission: Money.parse(j['commission']),
    revenue: Money.parse(j['revenue']),
  );

  final String name;
  final Money price;
  final int units;
  final Money discount;
  final Money commission;
  final Money revenue;
}

/// Top Selling Products: rows plus the four cards.
class TopProducts {
  const TopProducts({
    required this.rows,
    required this.amount,
    required this.discount,
    required this.commission,
    required this.revenue,
    required this.units,
  });

  factory TopProducts.fromJson(
    List<dynamic> items,
    Map<String, dynamic> summary,
  ) => TopProducts(
    rows: [
      for (final r in items)
        TopProductRow.fromJson(Map<String, dynamic>.from(r as Map)),
    ],
    amount: Money.parse(summary['total_product_amount']),
    discount: Money.parse(summary['total_discount']),
    commission: Money.parse(summary['total_commission']),
    revenue: Money.parse(summary['total_revenue']),
    units: (summary['total_units_sold'] as num?)?.toInt() ?? 0,
  );

  final List<TopProductRow> rows;
  final Money amount;
  final Money discount;
  final Money commission;
  final Money revenue;
  final int units;
}
