import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/design_system/tokens/colors.dart';

/// One appointment in a list (Home, Appointments). Same shape for
/// `/dashboard/today|upcoming` and `/appointments`.
class AppointmentRow {
  const AppointmentRow({
    required this.id,
    required this.date,
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.staffNames,
    required this.lines,
    required this.actions,
    this.bookingCode,
  });

  factory AppointmentRow.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['customer'] as Map?) ?? const {});
    List<String> strings(Object? v) => [
      for (final e in (v as List? ?? const [])) e.toString(),
    ];
    return AppointmentRow(
      id: (j['id'] as num).toInt(),
      bookingCode: j['booking_code']?.toString(),
      date: (j['date'] ?? '').toString(),
      start: (j['start'] ?? '').toString(),
      end: (j['end'] ?? '').toString(),
      startLabel: (j['start_label'] ?? '').toString(),
      endLabel: (j['end_label'] ?? '').toString(),
      status: AppointmentStatus.fromCode((j['status'] as num?)?.toInt() ?? 0),
      customerName: (c['name'] ?? 'Guest').toString(),
      customerPhone: c['phone']?.toString(),
      staffNames: strings(j['staff_names']),
      lines: strings(j['lines']),
      actions: strings(j['actions']),
    );
  }

  final int id;
  final String? bookingCode;

  /// `yyyy-MM-dd` in shop time.
  final String date;

  /// `HH:mm`.
  final String start;
  final String end;
  final String startLabel;
  final String endLabel;
  final AppointmentStatus status;
  final String customerName;
  final String? customerPhone;
  final List<String> staffNames;

  /// "Allen: Men's cut" lines, as the web prints them.
  final List<String> lines;

  /// What the server allows in this status (confirm, cancel, reschedule, view).
  final List<String> actions;

  bool get canConfirm => actions.contains('confirm');
  bool get isOpen =>
      status != AppointmentStatus.completed &&
      status != AppointmentStatus.cancelled;

  /// Services only ("Men's cut · Beard"), without the barber names.
  String get servicesText {
    final names = <String>[];
    for (final l in lines) {
      final i = l.indexOf(': ');
      final s = i >= 0 ? l.substring(i + 2) : l;
      if (!names.contains(s)) names.add(s);
    }
    return names.join(' · ');
  }

  String get staffText => staffNames.join(', ');

  AppointmentRow copyWith({AppointmentStatus? status, List<String>? actions}) =>
      AppointmentRow(
        id: id,
        bookingCode: bookingCode,
        date: date,
        start: start,
        end: end,
        startLabel: startLabel,
        endLabel: endLabel,
        status: status ?? this.status,
        customerName: customerName,
        customerPhone: customerPhone,
        staffNames: staffNames,
        lines: lines,
        actions: actions ?? this.actions,
      );
}

/// Booking counts by status (`GET /appointments/counts`).
class AppointmentCounts {
  const AppointmentCounts({
    required this.all,
    required this.pending,
    required this.confirmed,
    required this.completed,
    required this.cancelled,
    required this.rescheduled,
  });

  factory AppointmentCounts.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['counts'] as Map?) ?? const {});
    int n(String k) => (c[k] as num?)?.toInt() ?? 0;
    return AppointmentCounts(
      all: n('all'),
      pending: n('pending'),
      confirmed: n('confirmed'),
      completed: n('completed'),
      cancelled: n('cancelled'),
      rescheduled: n('rescheduled'),
    );
  }

  static const zero = AppointmentCounts(
    all: 0,
    pending: 0,
    confirmed: 0,
    completed: 0,
    cancelled: 0,
    rescheduled: 0,
  );

  final int all;
  final int pending;
  final int confirmed;
  final int completed;
  final int cancelled;
  final int rescheduled;

  int forStatus(AppointmentStatus? s) => switch (s) {
    null => all,
    AppointmentStatus.pending => pending,
    AppointmentStatus.confirmed => confirmed,
    AppointmentStatus.completed => completed,
    AppointmentStatus.cancelled => cancelled,
    AppointmentStatus.rescheduled => rescheduled,
  };
}

/// Filters of the list (the web's filter form).
class AppointmentFilter {
  const AppointmentFilter({
    this.status,
    this.startDate,
    this.endDate,
    this.staffId,
    this.dayType,
    this.query = '',
  });

  final AppointmentStatus? status;

  /// `yyyy-MM-dd`; the server needs both dates together.
  final String? startDate;
  final String? endDate;
  final int? staffId;

  /// `Morning`, `Afternoon` or `Evening`.
  final String? dayType;
  final String query;

  bool get hasDates => startDate != null && endDate != null;

  /// How many filters the sheet has applied (status tabs and search do not count).
  int get activeCount =>
      (hasDates ? 1 : 0) +
      (staffId != null ? 1 : 0) +
      (dayType != null ? 1 : 0);

  AppointmentFilter copyWith({
    Object? status = _keep,
    Object? startDate = _keep,
    Object? endDate = _keep,
    Object? staffId = _keep,
    Object? dayType = _keep,
    String? query,
  }) {
    return AppointmentFilter(
      status: identical(status, _keep)
          ? this.status
          : status as AppointmentStatus?,
      startDate: identical(startDate, _keep)
          ? this.startDate
          : startDate as String?,
      endDate: identical(endDate, _keep) ? this.endDate : endDate as String?,
      staffId: identical(staffId, _keep) ? this.staffId : staffId as int?,
      dayType: identical(dayType, _keep) ? this.dayType : dayType as String?,
      query: query ?? this.query,
    );
  }

  static const _keep = Object();

  Map<String, dynamic> toQuery() => {
    if (status != null) 'status': status!.code,
    if (hasDates) 'start_date': startDate,
    if (hasDates) 'end_date': endDate,
    'staff_id': ?staffId,
    'day_type': ?dayType,
    if (query.trim().isNotEmpty) 'q': query.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is AppointmentFilter &&
      other.status == status &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.staffId == staffId &&
      other.dayType == dayType &&
      other.query == query;

  @override
  int get hashCode =>
      Object.hash(status, startDate, endDate, staffId, dayType, query);
}

/// A service line on the detail screen (grouped, with quantity).
class ServiceLine {
  const ServiceLine({
    required this.serviceId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    required this.durationMinutes,
    required this.staffNames,
    required this.staffIds,
  });

  factory ServiceLine.fromJson(Map<String, dynamic> j) => ServiceLine(
    serviceId: (j['service_id'] as num?)?.toInt() ?? 0,
    name: (j['service_name'] ?? '').toString(),
    qty: (j['qty'] as num?)?.toInt() ?? 1,
    unitPrice: Money.parse(j['price']),
    lineTotal: Money.parse(j['line_total']),
    durationMinutes: (j['duration_total'] as num?)?.toInt() ?? 0,
    staffNames: [
      for (final s in (j['staff_names'] as List? ?? const [])) s.toString(),
    ],
    staffIds: [
      for (final s in (j['staff_ids'] as List? ?? const [])) (s as num).toInt(),
    ],
  );

  final int serviceId;
  final String name;
  final int qty;
  final Money unitPrice;
  final Money lineTotal;
  final int durationMinutes;
  final List<String> staffNames;

  /// The barbers who did this service (for completing into an invoice).
  final List<int> staffIds;
}

/// Full appointment (`GET /appointments/{id}`), the web's "Appointment Details".
class AppointmentDetail {
  const AppointmentDetail({
    required this.row,
    required this.customerEmail,
    required this.customerId,
    required this.notes,
    required this.isInvoiced,
    required this.invoiceNumber,
    required this.services,
    required this.barbers,
    required this.total,
    required this.staffIds,
    required this.serviceIds,
  });

  factory AppointmentDetail.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from((j['customer'] as Map?) ?? const {});
    final staff = <String>[
      for (final g in (j['staff_grouped'] as List? ?? const []))
        if ((g['is_first_available'] == true))
          'First available'
        else
          (g['staff_name'] ?? '').toString(),
    ];
    return AppointmentDetail(
      row: AppointmentRow.fromJson({
        ...j,
        'staff_names': staff,
        'lines': const <String>[],
      }),
      customerEmail: c['email']?.toString(),
      customerId: (c['id'] as num?)?.toInt(),
      notes: j['notes']?.toString(),
      isInvoiced: j['is_invoiced'] == true,
      invoiceNumber: j['invoice_number']?.toString(),
      services: [
        for (final s in (j['services_grouped'] as List? ?? const []))
          ServiceLine.fromJson(Map<String, dynamic>.from(s as Map)),
      ],
      barbers: staff,
      total: Money.parse(j['total']),
      staffIds: [
        for (final g in (j['staff_grouped'] as List? ?? const []))
          if ((g['staff_id'] as num?) != null) (g['staff_id'] as num).toInt(),
      ],
      // A service booked twice is listed twice (the slot finder reads repeats as quantity).
      serviceIds: [
        for (final s in (j['services_grouped'] as List? ?? const []))
          for (var i = 0; i < ((s['qty'] as num?)?.toInt() ?? 1); i++)
            (s['service_id'] as num).toInt(),
      ],
    );
  }

  final AppointmentRow row;
  final String? customerEmail;
  final int? customerId;
  final String? notes;
  final bool isInvoiced;
  final String? invoiceNumber;
  final List<ServiceLine> services;
  final List<String> barbers;
  final Money total;

  /// For the slot finder when rescheduling.
  final List<int> staffIds;
  final List<int> serviceIds;

  int get totalMinutes => services.fold(0, (a, s) => a + s.durationMinutes);
}

/// One free time on a day (`GET /appointments/slots`).
class TimeSlot {
  const TimeSlot({
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
    this.custom = false,
  });

  /// A time chosen by hand (the web lets you type any time).
  factory TimeSlot.at(int hour, int minute) {
    final hhmm =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final label =
        '${h12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
    return TimeSlot(
      start: hhmm,
      end: hhmm,
      startLabel: label,
      endLabel: label,
      custom: true,
    );
  }

  factory TimeSlot.fromJson(Map<String, dynamic> j) => TimeSlot(
    start: (j['start'] ?? '').toString(),
    end: (j['end'] ?? '').toString(),
    startLabel: (j['start_label'] ?? '').toString(),
    endLabel: (j['end_label'] ?? '').toString(),
  );

  /// `HH:mm`.
  final String start;
  final String end;
  final String startLabel;
  final String endLabel;

  /// True when the time was typed in, not offered by the slot finder.
  final bool custom;

  int get startHour => int.tryParse(start.split(':').first) ?? 0;
}

/// The day's free times, or the reason there are none.
class SlotsResult {
  const SlotsResult({required this.slots, required this.message});

  final List<TimeSlot> slots;

  /// The server's sentence when the day cannot be booked (shop closed...).
  final String? message;
}
