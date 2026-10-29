import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/domain/booking.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> apptJson(
  int id,
  String date,
  String start,
  String end,
  int status,
  String name,
  List<String> lines, {
  String phone = '7805550101',
  List<String> staff = const ['mike'],
}) {
  String label(String hhmm) {
    final h = int.parse(hhmm.split(':').first);
    final m = hhmm.split(':').last;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:$m ${h < 12 ? 'AM' : 'PM'}';
  }

  const actions = {
    0: ['confirm', 'complete', 'cancel', 'reschedule', 'view'],
    1: ['view'],
    2: ['reschedule', 'view'],
    3: ['cancel', 'complete', 'view'],
    4: ['confirm', 'complete', 'cancel', 'view'],
  };
  return {
    'id': id,
    'booking_code': 'BCB-2026-$id',
    'date': date,
    'start': start,
    'end': end,
    'start_label': label(start),
    'end_label': label(end),
    'status': status,
    'customer': {'id': id, 'name': name, 'phone': phone},
    'staff_names': staff,
    'lines': lines,
    'actions': actions[status],
  };
}

List<AppointmentRow> sampleRows() => [
  for (final j in [
    apptJson(5, '2026-10-28', '13:00', '13:30', 0, 'Ben Carter', [
      'mike: Skin fade',
    ]),
    apptJson(
      4,
      '2026-10-27',
      '10:00',
      '10:45',
      3,
      'Luke Tremblay',
      ["Mutaz: Men's cut", 'Mutaz: Beard (trim line up)'],
      staff: ['Mutaz'],
    ),
    apptJson(3, '2026-10-26', '16:00', '16:30', 0, 'Ahmed Khan', [
      "mike: Men's cut",
    ]),
    apptJson(2, '2026-10-26', '09:30', '10:15', 4, 'Daniel Okafor', [
      "mike: Men's cut",
    ]),
    apptJson(
      1,
      '2026-10-13',
      '22:11',
      '22:11',
      1,
      'Guest Customer',
      ['John: Senior cut'],
      staff: ['John'],
    ),
  ])
    AppointmentRow.fromJson(j),
];

Map<String, dynamic> detailJson({int status = 0}) => {
  ...apptJson(
    4,
    '2026-10-27',
    '10:00',
    '10:45',
    status,
    'Luke Tremblay',
    const [],
  ),
  'is_invoiced': false,
  'invoice_number': null,
  'notes': 'Prefers a number 2 on the sides.',
  'customer': {
    'id': 4,
    'name': 'Luke Tremblay',
    'phone': '7805550106',
    'email': 'luke@example.com',
  },
  'services_grouped': [
    {
      'service_id': 25,
      'service_name': "Men's cut",
      'price': '30.00',
      'duration': 30,
      'qty': 1,
      'line_total': '30.00',
      'duration_total': 30,
      'staff_names': ['Mutaz'],
      'staff_ids': [49],
    },
    {
      'service_id': 33,
      'service_name': 'Beard (trim line up)',
      'price': '20.00',
      'duration': 15,
      'qty': 1,
      'line_total': '20.00',
      'duration_total': 15,
      'staff_names': ['Mutaz'],
      'staff_ids': [49],
    },
  ],
  'staff_grouped': [
    {
      'staff_id': 49,
      'staff_name': 'Mutaz',
      'is_first_available': false,
      'assigned_staff_name': null,
      'services': [],
    },
  ],
  'subtotal': '50.00',
  'total': '50.00',
};

/// Repository with fixed answers; records what was called.
class FakeAppointmentsRepo extends AppointmentsRepository {
  FakeAppointmentsRepo({List<AppointmentRow>? rows, this.detailStatus = 0})
    : rows = rows ?? sampleRows(),
      super(_NoApi());

  final List<AppointmentRow> rows;
  final int detailStatus;
  final calls = <String>[];
  final filters = <AppointmentFilter>[];

  @override
  Future<AppointmentPage> list(
    AppointmentFilter filter, {
    int page = 1,
    int perPage = 20,
  }) async {
    filters.add(filter);
    final q = filter.query.toLowerCase();
    final items = rows
        .where((r) => filter.status == null || r.status == filter.status)
        .where((r) => q.isEmpty || r.customerName.toLowerCase().contains(q))
        .toList();
    return AppointmentPage(items: items, hasMore: false, total: items.length);
  }

  @override
  Future<AppointmentCounts> counts() async => const AppointmentCounts(
    all: 5,
    pending: 2,
    confirmed: 1,
    completed: 1,
    cancelled: 0,
    rescheduled: 1,
  );

  @override
  Future<AppointmentDetail> detail(int id) async =>
      AppointmentDetail.fromJson(detailJson(status: detailStatus));

  /// Free times the fake offers on any day.
  static const offered = [
    TimeSlot(
      start: '09:30',
      end: '10:00',
      startLabel: '09:30 AM',
      endLabel: '10:00 AM',
    ),
    TimeSlot(
      start: '09:00',
      end: '09:30',
      startLabel: '09:00 AM',
      endLabel: '09:30 AM',
    ),
    TimeSlot(
      start: '13:30',
      end: '14:00',
      startLabel: '01:30 PM',
      endLabel: '02:00 PM',
    ),
    TimeSlot(
      start: '17:00',
      end: '17:30',
      startLabel: '05:00 PM',
      endLabel: '05:30 PM',
    ),
  ];

  @override
  Future<SlotsResult> slots({
    required String date,
    required List<int> staffIds,
    required List<int> serviceIds,
  }) async {
    calls.add('slots:$date:${staffIds.join(',')}:${serviceIds.join(',')}');
    return const SlotsResult(slots: offered, message: null);
  }

  @override
  Future<void> reschedule(
    int appointmentId, {
    required String date,
    required String slotStart,
    required String slotEnd,
  }) async => calls.add('reschedule:$appointmentId:$date:$slotStart-$slotEnd');

  final created = <BookingDraft>[];
  final updated = <(int, BookingDraft)>[];

  @override
  Future<List<BookingCategory>> bookingOptions() async => const [
    BookingCategory(
      name: 'Haircuts',
      services: [
        BookingService(
          id: 25,
          name: "Men's cut",
          price: Money(3000),
          durationMinutes: 30,
        ),
        BookingService(
          id: 26,
          name: 'Skin fade',
          price: Money(3500),
          durationMinutes: 30,
        ),
        BookingService(
          id: 33,
          name: 'Beard (trim line up)',
          price: Money(2000),
          durationMinutes: 15,
        ),
      ],
    ),
  ];

  @override
  Future<List<BarberOption>> staffByService(List<int> serviceIds) async {
    calls.add('barbers:${serviceIds.toSet().join(',')}');
    return const [
      BarberOption(id: 42, name: 'mike', isFirstAvailable: false),
      BarberOption(id: 49, name: 'Mutaz', isFirstAvailable: false),
    ];
  }

  @override
  Future<void> createBooking(BookingDraft draft) async => created.add(draft);

  @override
  Future<void> updateBooking(int id, BookingDraft draft) async =>
      updated.add((id, draft));

  @override
  Future<void> confirm(int appointmentId) async =>
      calls.add('confirm:$appointmentId');

  @override
  Future<void> cancel(int appointmentId) async =>
      calls.add('cancel:$appointmentId');
}

class FakeCustomersRepo extends CustomersRepository {
  FakeCustomersRepo() : super(_NoApi());

  @override
  Future<List<CustomerSummary>> search(String q) async => const [
    CustomerSummary(
      id: 7,
      name: 'Sam Patel',
      phone: '7805550103',
      email: 'sam@example.com',
      isActive: true,
      memberSince: '2026-09-01',
      totalVisits: 3,
      appointmentsTotal: 3,
    ),
  ];

  @override
  Future<CustomerSummary> summary(int id) async => const CustomerSummary(
    id: 4,
    name: 'Luke Tremblay',
    phone: '7805550106',
    email: 'luke@example.com',
    isActive: true,
    memberSince: '2026-10-01',
    totalVisits: 7,
    appointmentsTotal: 9,
  );
}
