import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/design_system/design_system.dart';

/// The numbers under the profile of a staff member (web: Completed Services,
/// Total Visits, Tips, Total Earning).
class MyStats {
  const MyStats({
    required this.appointments,
    required this.visits,
    required this.tips,
    required this.serviceCommission,
    required this.productCommission,
    required this.totalEarning,
  });

  factory MyStats.fromJson(Map<String, dynamic> j) => MyStats(
    appointments: (j['appointments'] as num?)?.toInt() ?? 0,
    visits: (j['visits'] as num?)?.toInt() ?? 0,
    tips: Money.parse(j['tips']),
    serviceCommission: Money.parse(j['service_commission']),
    productCommission: Money.parse(j['product_commission']),
    totalEarning: Money.parse(j['total_earning']),
  );

  final int appointments;
  final int visits;
  final Money tips;
  final Money serviceCommission;
  final Money productCommission;
  final Money totalEarning;
}

/// `GET /me/profile`: the signed-in user, their assigned services and (staff only) stats.
class MyProfile {
  const MyProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.imageUrl,
    required this.services,
    required this.stats,
  });

  factory MyProfile.fromJson(Map<String, dynamic> j) {
    final u = Map<String, dynamic>.from((j['user'] as Map?) ?? const {});
    return MyProfile(
      name: (u['name'] ?? '').toString(),
      email: (u['email'] ?? '').toString(),
      phone: u['phone']?.toString(),
      role: (u['role'] ?? '').toString(),
      imageUrl: u['profile_image_url']?.toString(),
      services: [
        for (final s in (j['services'] as List? ?? const [])) s.toString(),
      ],
      stats: j['stats'] is Map
          ? MyStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map))
          : null,
    );
  }

  final String name;
  final String email;
  final String? phone;
  final String role;
  final String? imageUrl;
  final List<String> services;

  /// Null for the owner / admin (the web shows the block to staff only).
  final MyStats? stats;
}

/// The cards above the Staff Report (web: Total Earning, Product Commission,
/// Service Commission, Tip).
class ReportSummary {
  const ReportSummary({
    required this.totalEarning,
    required this.productCommission,
    required this.serviceCommission,
    required this.tips,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
    totalEarning: Money.parse(j['my_total_earning']),
    productCommission: Money.parse(j['my_product_commission']),
    serviceCommission: Money.parse(j['my_service_commission']),
    tips: Money.parse(j['my_tips']),
  );

  final Money totalEarning;
  final Money productCommission;
  final Money serviceCommission;
  final Money tips;
}

/// Appointments tab: Name, Contact No., Date, Time, Discount, Total Tip, Total Amount, Status.
class ReportAppointment {
  const ReportAppointment({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.date,
    required this.startLabel,
    required this.endLabel,
    required this.discount,
    required this.tip,
    required this.total,
    required this.status,
  });

  factory ReportAppointment.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['customer'] as Map?) ?? const {});
    return ReportAppointment(
      id: (j['id'] as num).toInt(),
      customerName: (c['name'] ?? '').toString(),
      customerPhone: c['phone']?.toString(),
      date: (j['date'] ?? '').toString(),
      startLabel: (j['start_label'] ?? '').toString(),
      endLabel: (j['end_label'] ?? '').toString(),
      discount: Money.parse(j['discount']),
      tip: Money.parse(j['tip']),
      total: Money.parse(j['total']),
      status: AppointmentStatus.fromCode((j['status'] as num?)?.toInt() ?? 0),
    );
  }

  final int id;
  final String customerName;
  final String? customerPhone;

  /// `yyyy-MM-dd`.
  final String date;
  final String startLabel;
  final String endLabel;
  final Money discount;
  final Money tip;
  final Money total;
  final AppointmentStatus status;
}

/// Service Earning tab: one row per service.
class ServiceEarning {
  const ServiceEarning({
    required this.name,
    required this.duration,
    required this.price,
    required this.appointments,
    required this.commission,
    required this.tips,
    required this.total,
  });

  factory ServiceEarning.fromJson(Map<String, dynamic> j) => ServiceEarning(
    name: (j['service_name'] ?? '').toString(),
    duration: (j['duration'] as num?)?.toInt() ?? 0,
    price: Money.parse(j['price']),
    appointments: (j['appointment_count'] as num?)?.toInt() ?? 0,
    commission: Money.parse(j['commission']),
    tips: Money.parse(j['tips']),
    total: Money.parse(j['total_earning']),
  );

  final String name;
  final int duration;
  final Money price;
  final int appointments;
  final Money commission;
  final Money tips;
  final Money total;
}

/// Daily Earning tab: one row per day.
class DailyEarning {
  const DailyEarning({
    required this.date,
    required this.productCommission,
    required this.tips,
    required this.serviceCommission,
    required this.total,
  });

  factory DailyEarning.fromJson(Map<String, dynamic> j) => DailyEarning(
    date: (j['date'] ?? '').toString(),
    productCommission: Money.parse(j['product_commission']),
    tips: Money.parse(j['tips']),
    serviceCommission: Money.parse(j['service_commission']),
    total: Money.parse(j['total_earning']),
  );

  final String date;
  final Money productCommission;
  final Money tips;
  final Money serviceCommission;
  final Money total;
}

/// One working-hours range of a day.
class WorkBlock {
  const WorkBlock({
    required this.id,
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
  });

  factory WorkBlock.fromJson(Map<String, dynamic> j) => WorkBlock(
    id: (j['id'] as num).toInt(),
    start: (j['start'] ?? '').toString(),
    end: (j['end'] ?? '').toString(),
    startLabel: (j['start_label'] ?? '').toString(),
    endLabel: (j['end_label'] ?? '').toString(),
  );

  final int id;

  /// `HH:mm`.
  final String start;
  final String end;

  /// `09:00 AM`.
  final String startLabel;
  final String endLabel;

  int get minutes => _min(end) - _min(start);

  static int _min(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}

/// One weekday of the schedule (web: a "day card").
class WorkDay {
  const WorkDay({
    required this.slotId,
    required this.name,
    required this.isDayOff,
    required this.blocks,
  });

  factory WorkDay.fromJson(Map<String, dynamic> j) => WorkDay(
    slotId: (j['slot_id'] as num).toInt(),
    name: (j['day_name'] ?? '').toString(),
    isDayOff: j['is_day_off'] == true,
    blocks: [
      for (final b in (j['blocks'] as List? ?? const []))
        WorkBlock.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
  );

  final int slotId;
  final String name;
  final bool isDayOff;
  final List<WorkBlock> blocks;

  /// The web's "Total Working Hours", e.g. `4` or `9.5`.
  String get totalHours {
    final minutes = blocks.fold<int>(0, (a, b) => a + b.minutes);
    final h = (minutes / 60 * 100).round() / 100;
    return h == h.roundToDouble() ? h.toStringAsFixed(0) : '$h';
  }
}
