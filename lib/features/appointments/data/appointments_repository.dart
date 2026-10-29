import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/domain/booking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One page of the appointment list.
class AppointmentPage {
  const AppointmentPage({
    required this.items,
    required this.hasMore,
    required this.total,
  });

  final List<AppointmentRow> items;
  final bool hasMore;
  final int total;
}

/// APPT-1..5: list, counts, detail, confirm, cancel. Shared by Home, the
/// Calendar and the Appointments tab, so every screen asks the server the same
/// way and reads the same errors (409 = changed elsewhere).
class AppointmentsRepository {
  const AppointmentsRepository(this._api);

  final ApiClient _api;

  Future<AppointmentPage> list(
    AppointmentFilter filter, {
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/appointments',
      query: {...filter.toQuery(), 'page': page, 'per_page': perPage},
    );
    return AppointmentPage(
      items: [
        for (final e in (res.data['items'] as List? ?? const []))
          AppointmentRow.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      hasMore: res.meta['has_more'] == true,
      total: (res.meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<AppointmentCounts> counts() async {
    final res = await _api.get('/appointments/counts');
    return AppointmentCounts.fromJson(res.data);
  }

  Future<AppointmentDetail> detail(int id) async {
    final res = await _api.get('/appointments/$id');
    return AppointmentDetail.fromJson(
      Map<String, dynamic>.from(res.data['appointment'] as Map),
    );
  }

  /// Free times for these barbers and services on [date] (`yyyy-MM-dd`).
  Future<SlotsResult> slots({
    required String date,
    required List<int> staffIds,
    required List<int> serviceIds,
  }) async {
    final res = await _api.get(
      '/appointments/slots',
      query: {
        'date': date,
        'staff_ids[]': staffIds,
        'service_ids[]': serviceIds,
      },
    );
    final available = res.data['available'] == true;
    return SlotsResult(
      slots: available
          ? [
              for (final s in (res.data['slots'] as List? ?? const []))
                TimeSlot.fromJson(Map<String, dynamic>.from(s as Map)),
            ]
          : const [],
      message: available ? null : res.data['message']?.toString(),
    );
  }

  Future<void> reschedule(
    int appointmentId, {
    required String date,
    required String slotStart,
    required String slotEnd,
  }) async {
    await _api.post(
      '/appointments/$appointmentId/reschedule',
      body: {'date': date, 'slot_start': slotStart, 'slot_end': slotEnd},
    );
  }

  /// The services a booking can contain.
  Future<List<BookingCategory>> bookingOptions() async {
    final res = await _api.get('/calendar/booking-options');
    return [
      for (final c in (res.data['categories'] as List? ?? const []))
        BookingCategory.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
  }

  /// Barbers who offer these services (the web's "Select Staff").
  Future<List<BarberOption>> staffByService(List<int> serviceIds) async {
    final res = await _api.get(
      '/appointments/staff-by-service',
      query: {'service_ids': serviceIds.toSet().join(',')},
    );
    return [
      for (final s in (res.data['staff'] as List? ?? const []))
        BarberOption.fromJson(Map<String, dynamic>.from(s as Map)),
    ];
  }

  /// "Save Appointment": a new booking from the calendar.
  Future<void> createBooking(BookingDraft draft) async {
    await _api.post('/appointments', body: draft.toJson());
  }

  /// Update an existing booking (the calendar's edit form).
  Future<void> updateBooking(int id, BookingDraft draft) async {
    await _api.put('/appointments/$id', body: draft.toJson());
  }

  Future<void> confirm(int appointmentId) async {
    await _api.post('/appointments/$appointmentId/confirm');
  }

  Future<void> cancel(int appointmentId) async {
    await _api.post('/appointments/$appointmentId/cancel');
  }
}

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>(
  (ref) => AppointmentsRepository(ref.watch(apiClientProvider)),
);
