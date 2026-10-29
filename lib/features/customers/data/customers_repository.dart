import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A customer as the web lists and edits them (`/customers`). The profile
/// numbers ([totalVisits], [appointmentsTotal]) are only filled by `GET /customers/{id}`.
/// "Total spend" is left out on purpose: the web adds each invoice once per
/// service line, so the figure is wrong (see docs/WEB_DEV_FIXES.md, Q35).
class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.isActive,
    required this.memberSince,
    required this.totalVisits,
    required this.appointmentsTotal,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    phone: j['phone']?.toString(),
    email: j['email']?.toString(),
    isActive: (j['status'] as num?)?.toInt() == 1,
    memberSince: j['created_at']?.toString(),
    totalVisits: (j['total_visits'] as num?)?.toInt() ?? 0,
    appointmentsTotal: (j['appointments_total'] as num?)?.toInt() ?? 0,
  );

  final int id;
  final String name;
  final String? phone;
  final String? email;
  final bool isActive;

  /// `yyyy-MM-dd`.
  final String? memberSince;
  final int totalVisits;
  final int appointmentsTotal;

  bool get hasPhone => (phone ?? '').trim().isNotEmpty;
  bool get hasEmail => (email ?? '').trim().isNotEmpty;
}

/// One row of the profile's appointment table (web: Date, Time, Staff Name, Status).
class CustomerAppointment {
  const CustomerAppointment({
    required this.id,
    required this.date,
    required this.startLabel,
    required this.endLabel,
    required this.status,
    required this.staffNames,
  });

  factory CustomerAppointment.fromJson(Map<String, dynamic> j) =>
      CustomerAppointment(
        id: (j['id'] as num).toInt(),
        date: (j['date'] ?? '').toString(),
        startLabel: (j['start_label'] ?? '').toString(),
        endLabel: (j['end_label'] ?? '').toString(),
        status: AppointmentStatus.fromCode((j['status'] as num?)?.toInt() ?? 0),
        staffNames: (j['staff_names'] ?? '').toString(),
      );

  final int id;

  /// `yyyy-MM-dd`.
  final String date;
  final String startLabel;
  final String endLabel;
  final AppointmentStatus status;
  final String staffNames;
}

/// What the Add / Update Customer form sends (the web's four fields).
class CustomerInput {
  const CustomerInput({
    required this.name,
    required this.phone,
    required this.email,
    required this.isActive,
  });

  final String name;
  final String phone;
  final String email;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'full_name': name.trim(),
    'phone_number': phone.trim(),
    // The web sends the empty string when the optional e-mail is left blank.
    'email': email.trim().isEmpty ? null : email.trim(),
    'status': isActive ? 1 : 0,
  };
}

/// CUST-1..6: list, profile, the profile's appointments, add, update, delete.
class CustomersRepository {
  const CustomersRepository(this._api);

  final ApiClient _api;

  /// Customers matching a name, phone or e-mail.
  Future<PagedResult<CustomerSummary>> list({
    String q = '',
    int? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/customers',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'status': ?status,
        'page': page,
        'per_page': perPage,
      },
    );
    return PagedResult(
      items: [
        for (final c in (res.data['items'] as List? ?? const []))
          CustomerSummary.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      hasMore: res.meta['has_more'] == true,
      total: (res.meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Suggestions for the booking form while the phone or name is typed.
  Future<List<CustomerSummary>> search(String q) async =>
      (await list(q: q, perPage: 5)).items;

  Future<CustomerSummary> summary(int id) async {
    final res = await _api.get('/customers/$id');
    return CustomerSummary.fromJson(
      Map<String, dynamic>.from(res.data['customer'] as Map),
    );
  }

  Future<PagedResult<CustomerAppointment>> appointments(
    int id, {
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/customers/$id/appointments',
      query: {'page': page, 'per_page': perPage},
    );
    return PagedResult(
      items: [
        for (final a in (res.data['items'] as List? ?? const []))
          CustomerAppointment.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      hasMore: res.meta['has_more'] == true,
      total: (res.meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<CustomerSummary> create(CustomerInput input) async {
    final res = await _api.post('/customers', body: input.toJson());
    return CustomerSummary.fromJson(
      Map<String, dynamic>.from(res.data['customer'] as Map),
    );
  }

  Future<CustomerSummary> update(int id, CustomerInput input) async {
    final res = await _api.put('/customers/$id', body: input.toJson());
    return CustomerSummary.fromJson(
      Map<String, dynamic>.from(res.data['customer'] as Map),
    );
  }

  /// Refused by the server (409) while the customer still has appointments.
  Future<void> delete(int id) async {
    await _api.delete('/customers/$id');
  }
}

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(apiClientProvider)),
);

final customerSummaryProvider = FutureProvider.autoDispose
    .family<CustomerSummary, int>(
      (ref, id) => ref.read(customersRepositoryProvider).summary(id),
    );

/// Suggestions for the booking form while the phone or name is typed.
final customerSearchProvider = FutureProvider.autoDispose
    .family<List<CustomerSummary>, String>(
      (ref, q) => ref.read(customersRepositoryProvider).search(q),
    );
