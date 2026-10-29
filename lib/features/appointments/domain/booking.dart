import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:flutter/foundation.dart';

/// A service that can go into a booking (`GET /calendar/booking-options`).
class BookingService {
  const BookingService({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.imageUrl,
  });

  factory BookingService.fromJson(Map<String, dynamic> j) => BookingService(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    price: Money.parse(j['price']),
    durationMinutes: (j['duration'] as num?)?.toInt() ?? 0,
    imageUrl: j['image_url']?.toString(),
  );

  final int id;
  final String name;
  final Money price;
  final int durationMinutes;

  /// The service's picture (null when it has none).
  final String? imageUrl;
}

class BookingCategory {
  const BookingCategory({required this.name, required this.services});

  factory BookingCategory.fromJson(Map<String, dynamic> j) => BookingCategory(
    name: (j['name'] ?? '').toString(),
    services: [
      for (final s in (j['services'] as List? ?? const []))
        BookingService.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );

  final String name;
  final List<BookingService> services;
}

/// A barber who offers the chosen services (`GET /appointments/staff-by-service`).
class BarberOption {
  const BarberOption({
    required this.id,
    required this.name,
    required this.isFirstAvailable,
    this.offersServiceIds = const [],
  });

  factory BarberOption.fromJson(Map<String, dynamic> j) => BarberOption(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    isFirstAvailable: j['is_first_available'] == true,
    offersServiceIds: [
      for (final i in (j['offers_service_ids'] as List? ?? const []))
        (i as num).toInt(),
    ],
  );

  final int id;
  final String name;
  final bool isFirstAvailable;

  /// Which of the asked-for services this barber does (the server lists barbers
  /// who do at least one).
  final List<int> offersServiceIds;
}

/// One service of the booking and how many of it.
@immutable
class BookingLine {
  const BookingLine(this.service, this.qty);

  final BookingService service;
  final int qty;

  BookingLine withQty(int q) => BookingLine(service, q);
}

/// What the "Add Appointment" form has collected.
@immutable
class BookingDraft {
  const BookingDraft({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.lines = const [],
    this.staffId,
    this.date,
    this.slot,
  });

  final String name;
  final String phone;
  final String email;
  final String notes;
  final List<BookingLine> lines;
  final int? staffId;

  /// `yyyy-MM-dd`.
  final String? date;
  final TimeSlot? slot;

  int get totalMinutes =>
      lines.fold(0, (a, l) => a + l.service.durationMinutes * l.qty);
  Money get total =>
      lines.fold(Money.zero, (a, l) => a + l.service.price * l.qty);
  int get serviceCount => lines.fold(0, (a, l) => a + l.qty);

  /// Repeats mean quantity: the slot finder reads "25, 25" as two of service 25.
  List<int> get serviceIds => [
    for (final l in lines)
      for (var i = 0; i < l.qty; i++) l.service.id,
  ];

  BookingDraft copyWith({
    String? name,
    String? phone,
    String? email,
    String? notes,
    List<BookingLine>? lines,
    Object? staffId = _keep,
    String? date,
    Object? slot = _keep,
  }) => BookingDraft(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    notes: notes ?? this.notes,
    lines: lines ?? this.lines,
    staffId: identical(staffId, _keep) ? this.staffId : staffId as int?,
    date: date ?? this.date,
    slot: identical(slot, _keep) ? this.slot : slot as TimeSlot?,
  );

  static const _keep = Object();

  /// The body of `POST /appointments` and `PUT /appointments/{id}`.
  Map<String, dynamic> toJson() => {
    'date': date,
    'time': slot?.start,
    'staff_id': staffId,
    'services': [
      for (final l in lines) {'id': l.service.id, 'qty': l.qty},
    ],
    'name': name.trim(),
    'phone': phone.trim(),
    if (email.trim().isNotEmpty) 'email': email.trim(),
    if (notes.trim().isNotEmpty) 'notes': notes.trim(),
  };
}
