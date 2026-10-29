import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/design_system/tokens/colors.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';

/// `GET /dashboard/summary`. Admin sees shop money; everyone else sees their
/// own earnings (commission + tips), exactly like the web cards.
class DashboardSummary {
  const DashboardSummary({
    required this.isAdmin,
    required this.upcoming,
    required this.completed,
    required this.cancelled,
    required this.confirmed,
    required this.rescheduled,
    required this.customers,
    required this.revenue,
    required this.tips,
    required this.commission,
    required this.showToday,
    required this.showUpcoming,
    required this.showTopServices,
    required this.showTopProducts,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> map(Object? v) =>
        Map<String, dynamic>.from((v as Map?) ?? const {});
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final a = map(j['appointments']);
    final m = map(j['money']);
    final w = map(j['widgets']);
    return DashboardSummary(
      isAdmin: j['scope'] == 'admin',
      upcoming: n(a['upcoming']),
      completed: n(a['completed']),
      cancelled: n(a['cancelled']),
      confirmed: n(a['confirmed']),
      rescheduled: n(a['rescheduled']),
      customers: n(j['customers']),
      revenue: Money.parse(m['revenue']),
      tips: Money.parse(m['tips']),
      commission: Money.parse(m['commission']),
      showToday: w['today'] == true,
      showUpcoming: w['upcoming'] == true,
      showTopServices: w['top_services'] == true,
      showTopProducts: w['top_products'] == true,
    );
  }

  final bool isAdmin;
  final int upcoming;
  final int completed;
  final int cancelled;
  final int confirmed;
  final int rescheduled;
  final int customers;

  /// Admin: shop revenue. Staff: earnings (commission + tips).
  final Money revenue;
  final Money tips;
  final Money commission;
  final bool showToday;
  final bool showUpcoming;
  final bool showTopServices;
  final bool showTopProducts;

  int countFor(AppointmentStatus s) => switch (s) {
    AppointmentStatus.pending => upcoming,
    AppointmentStatus.completed => completed,
    AppointmentStatus.cancelled => cancelled,
    AppointmentStatus.confirmed => confirmed,
    AppointmentStatus.rescheduled => rescheduled,
  };
}

class TopService {
  const TopService(this.name, this.revenue, this.count);

  factory TopService.fromJson(Map<String, dynamic> j) => TopService(
    (j['service_name'] ?? '').toString(),
    Money.parse(j['total_revenue']),
    (j['appointment_count'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final Money revenue;
  final int count;
}

class TopProduct {
  const TopProduct(this.name, this.sold);

  factory TopProduct.fromJson(Map<String, dynamic> j) => TopProduct(
    (j['product_name'] ?? '').toString(),
    (j['total_sold'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final int sold;
}

/// Everything Home shows, built from one set of API answers (or its saved copy).
class HomeData {
  const HomeData({
    required this.summary,
    required this.today,
    required this.upcoming,
    required this.topServices,
    required this.products,
    required this.raw,
    this.fromCache = false,
  });

  factory HomeData.fromRaw(Map<String, dynamic> raw, {bool fromCache = false}) {
    List<Map<String, dynamic>> items(String key) => [
      for (final e in (raw[key] as List? ?? const []))
        Map<String, dynamic>.from(e as Map),
    ];
    return HomeData(
      summary: DashboardSummary.fromJson(
        Map<String, dynamic>.from(raw['summary'] as Map),
      ),
      today: items('today').map(AppointmentRow.fromJson).toList(),
      upcoming: items('upcoming').map(AppointmentRow.fromJson).toList(),
      topServices: items('topServices').map(TopService.fromJson).toList(),
      products: items('products').map(TopProduct.fromJson).toList(),
      raw: raw,
      fromCache: fromCache,
    );
  }

  final DashboardSummary summary;
  final List<AppointmentRow> today;
  final List<AppointmentRow> upcoming;
  final List<TopService> topServices;
  final List<TopProduct> products;
  final Map<String, dynamic> raw;

  /// True when this is the saved copy (the phone could not reach the server).
  final bool fromCache;

  /// The first booking of today that is still to be served.
  AppointmentRow? get nextUp {
    for (final a in today) {
      if (a.isOpen) return a;
    }
    return null;
  }

  HomeData withToday(List<AppointmentRow> rows) => HomeData(
    summary: summary,
    today: rows,
    upcoming: upcoming,
    topServices: topServices,
    products: products,
    raw: raw,
    fromCache: fromCache,
  );
}
