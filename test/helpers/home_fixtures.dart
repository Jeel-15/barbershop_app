import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';

Map<String, dynamic> _row(
  int id,
  String date,
  String start,
  String end,
  int status,
  String name,
  List<String> lines, {
  String? phone = '7805550101',
  List<String> staff = const ['JOJO'],
}) {
  String label(String hhmm) {
    final h = int.parse(hhmm.split(':').first);
    final m = hhmm.split(':').last;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:$m ${h < 12 ? 'AM' : 'PM'}';
  }

  const actions = {
    0: ['confirm', 'cancel', 'reschedule', 'view'],
    1: ['view'],
    2: ['reschedule', 'view'],
    3: ['cancel', 'view'],
    4: ['confirm', 'cancel', 'view'],
  };
  return {
    'id': id,
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

/// Raw dashboard answers shaped like the real API (admin).
Map<String, dynamic> adminHomeRaw({String today = '2026-10-26'}) => {
  'summary': {
    'scope': 'admin',
    'appointments': {
      'upcoming': 6,
      'completed': 17,
      'cancelled': 1,
      'confirmed': 3,
      'rescheduled': 1,
    },
    'customers': 11,
    'money': {'kind': 'revenue', 'revenue': '713.09', 'tips': '58.00'},
    'widgets': {
      'today': true,
      'upcoming': true,
      'top_services': true,
      'top_products': true,
    },
  },
  'today': [
    _row(1, today, '10:00', '10:30', 1, 'Marcus Lee', ["JOJO: Men's cut"]),
    _row(2, today, '11:00', '11:50', 3, 'Daniel Okafor', [
      "JOJO: Men's cut",
      'JOJO: Beard (trim line up)',
    ]),
    _row(
      3,
      today,
      '13:30',
      '14:00',
      0,
      'Sam Patel',
      ['Jack Sparrow: Skin fade'],
      staff: const ['Jack Sparrow'],
    ),
    _row(4, today, '16:00', '16:30', 0, 'Ahmed Khan', ["JOJO: Men's cut"]),
  ],
  'upcoming': [
    _row(
      5,
      '2026-10-27',
      '10:00',
      '10:30',
      3,
      'Luke Tremblay',
      ["Jack Sparrow: Men's cut"],
      staff: const ['Jack Sparrow'],
    ),
    _row(6, '2026-10-28', '13:00', '13:30', 0, 'Ben Carter', [
      'JOJO: Skin fade',
    ]),
  ],
  'topServices': [
    {
      'service_name': "Men's cut",
      'total_revenue': '351.75',
      'appointment_count': 17,
    },
    {
      'service_name': 'Beard (trim line up)',
      'total_revenue': '180.50',
      'appointment_count': 3,
    },
    {
      'service_name': 'Buzz cut (with fade)',
      'total_revenue': '130.00',
      'appointment_count': 5,
    },
  ],
  'products': [
    {'product_id': 1, 'product_name': 'Hair oil', 'total_sold': 4},
    {'product_id': 3, 'product_name': 'Beard Oil', 'total_sold': 2},
  ],
};

Map<String, dynamic> emptyStaffHomeRaw() => {
  'summary': {
    'scope': 'staff',
    'appointments': {
      'upcoming': 0,
      'completed': 0,
      'cancelled': 0,
      'confirmed': 0,
      'rescheduled': 0,
    },
    'customers': 11,
    'money': {
      'kind': 'earnings',
      'revenue': '0.00',
      'tips': '0.00',
      'commission': '0.00',
    },
    'widgets': {
      'today': true,
      'upcoming': true,
      'top_services': false,
      'top_products': false,
    },
  },
  'today': <Object>[],
  'upcoming': <Object>[],
  'topServices': <Object>[],
  'products': <Object>[],
};

/// Home controller that returns fixed data (no network).
class FixedHome extends HomeController {
  FixedHome(this.raw, {this.fromCache = false});

  final Map<String, dynamic> raw;
  final bool fromCache;
  final confirmed = <int>[];

  @override
  Future<HomeData> build() async => HomeData.fromRaw(raw, fromCache: fromCache);

  @override
  Future<void> confirm(AppointmentRow row) async {
    confirmed.add(row.id);
  }
}
