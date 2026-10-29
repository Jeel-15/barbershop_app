import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/design_system/design_system.dart';

/// A team member as the web's Staff list and form know them.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.panelRole,
    required this.roleIds,
    required this.roleNames,
    required this.commission,
    required this.isBarber,
    required this.active,
    required this.serviceNames,
    required this.photoUrl,
    required this.createdAt,
    required this.serviceIds,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    phone: j['phone']?.toString(),
    panelRole: (j['panel_role'] ?? '').toString(),
    roleIds: [
      for (final r in (j['role_ids'] as List? ?? const [])) (r as num).toInt(),
    ],
    roleNames: [
      for (final r in (j['role_names'] as List? ?? const [])) r.toString(),
    ],
    commission: Money.parse(j['commission']),
    isBarber: j['is_barber'] == true,
    active: j['active'] == true,
    serviceNames: (j['service_names'] ?? '').toString(),
    photoUrl: j['photo_url']?.toString(),
    createdAt: j['created_at']?.toString(),
    serviceIds: [
      for (final s in (j['service_ids'] as List? ?? const []))
        (s as num).toInt(),
    ],
  );

  final int id;
  final String name;
  final String email;
  final String? phone;

  /// `Staff` or `Accountant` (the panel role).
  final String panelRole;
  final List<int> roleIds;
  final List<String> roleNames;

  /// Product commission, in percent (e.g. `10.00`).
  final Money commission;
  final bool isBarber;
  final bool active;

  /// "Men's cut, Skin fade" (list rows only).
  final String serviceNames;
  final String? photoUrl;

  /// `yyyy-MM-dd`.
  final String? createdAt;

  /// Only filled by `GET /staff/{id}` (the form).
  final List<int> serviceIds;

  bool get hasPhone => (phone ?? '').trim().isNotEmpty;

  /// The role shown on the row: the spatie role, else the panel role.
  String get roleLabel => roleNames.isNotEmpty ? roleNames.first : panelRole;
}

class RoleOption {
  const RoleOption(this.id, this.name);

  final int id;
  final String name;

  bool get isAccountant => name.toLowerCase() == 'accountant';
}

class ServiceOption {
  const ServiceOption(this.id, this.name, {this.active = true});

  final int id;
  final String name;
  final bool active;
}

/// What the Add / Update Staff form offers (the Role and Service lists).
class StaffFormOptions {
  const StaffFormOptions({required this.roles, required this.services});

  factory StaffFormOptions.fromJson(Map<String, dynamic> j) => StaffFormOptions(
    roles: [
      for (final r in (j['roles'] as List? ?? const []))
        RoleOption((r['id'] as num).toInt(), r['name'].toString()),
    ],
    services: [
      for (final s in (j['services'] as List? ?? const []))
        ServiceOption(
          (s['id'] as num).toInt(),
          s['name'].toString(),
          active: s['active'] != false,
        ),
    ],
  );

  final List<RoleOption> roles;
  final List<ServiceOption> services;
}

/// What the form sends (web names: Staff Name, Email, Phone, Password, Barber,
/// Service, Product Commission (%), Status, Role, Staff Profile Image).
class StaffInput {
  const StaffInput({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.isBarber,
    required this.serviceIds,
    required this.commission,
    required this.active,
    required this.roleId,
    this.photoPath,
  });

  final String name;
  final String email;
  final String phone;
  final String password;
  final bool isBarber;
  final List<int> serviceIds;
  final String commission;
  final bool active;
  final int roleId;
  final String? photoPath;
}

/// The cards on the Staff Profile (web: Complete Services, Total Earn Tip,
/// Total Product Commission, Total Service Commission, Total Earning).
class StaffSummary {
  const StaffSummary({
    required this.visits,
    required this.appointments,
    required this.tips,
    required this.productCommission,
    required this.serviceCommission,
    required this.totalEarning,
  });

  factory StaffSummary.fromJson(Map<String, dynamic> j) => StaffSummary(
    visits: (j['total_visits'] as num?)?.toInt() ?? 0,
    appointments: (j['total_appointments'] as num?)?.toInt() ?? 0,
    tips: Money.parse(j['tips']),
    productCommission: Money.parse(j['product_commission']),
    serviceCommission: Money.parse(j['service_commission']),
    totalEarning: Money.parse(j['total_earning']),
  );

  final int visits;
  final int appointments;
  final Money tips;
  final Money productCommission;
  final Money serviceCommission;
  final Money totalEarning;
}

/// The Staff Profile's header: the person and their numbers.
class StaffProfile {
  const StaffProfile({required this.staff, required this.summary});

  factory StaffProfile.fromJson(Map<String, dynamic> j) => StaffProfile(
    staff: StaffMember.fromJson(Map<String, dynamic>.from(j['staff'] as Map)),
    summary: StaffSummary.fromJson(
      Map<String, dynamic>.from(j['summary'] as Map),
    ),
  );

  final StaffMember staff;
  final StaffSummary summary;
}

/// Appointments tab of the profile: Name, Contact No., Date, Time, Assign To, Status.
class StaffAppointment {
  const StaffAppointment({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.date,
    required this.startLabel,
    required this.endLabel,
    required this.staffNames,
    required this.status,
  });

  factory StaffAppointment.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['customer'] as Map?) ?? const {});
    return StaffAppointment(
      id: (j['id'] as num).toInt(),
      customerName: (c['name'] ?? '').toString(),
      customerPhone: c['phone']?.toString(),
      date: (j['date'] ?? '').toString(),
      startLabel: (j['start_label'] ?? '').toString(),
      endLabel: (j['end_label'] ?? '').toString(),
      staffNames: (j['staff_names'] ?? '').toString(),
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
  final String staffNames;
  final AppointmentStatus status;
}
