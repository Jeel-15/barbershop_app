import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> staffJson(
  int id,
  String name, {
  bool barber = true,
  bool active = true,
  String role = 'Staff',
  List<int> services = const [25],
}) => {
  'id': id,
  'name': name,
  'email': '${name.toLowerCase()}@rosen.test',
  'phone': '78055500$id',
  'panel_role': role == 'Accountant' ? 'Accountant' : 'Staff',
  'role_ids': [role == 'Accountant' ? 5 : 2],
  'role_names': [role],
  'commission': '10.00',
  'is_barber': barber,
  'active': active,
  'service_names': barber ? "Men's cut" : '',
  'photo_url': null,
  'created_at': '2026-01-15',
  'service_ids': services,
};

class FakeStaffRepo extends StaffRepository {
  FakeStaffRepo() : super(_NoApi());

  final calls = <String>[];
  final inputs = <StaffInput>[];
  Failure? saveFails;

  final rows = [
    staffJson(42, 'Mike'),
    staffJson(49, 'Mutaz', active: false),
    staffJson(50, 'Alice', barber: false, role: 'Accountant', services: []),
  ];

  @override
  Future<PagedResult<StaffMember>> list({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('list:$q');
    final hit = [
      for (final r in rows)
        if (q.isEmpty ||
            r['name'].toString().toLowerCase().contains(q.toLowerCase()))
          StaffMember.fromJson(r),
    ];
    return PagedResult(items: hit, hasMore: false, total: hit.length);
  }

  @override
  Future<StaffFormOptions> formOptions() async => StaffFormOptions.fromJson({
    'roles': [
      {'id': 2, 'name': 'Staff'},
      {'id': 5, 'name': 'Accountant'},
    ],
    'services': [
      {'id': 25, 'name': "Men's cut", 'active': true},
      {'id': 26, 'name': 'Skin fade', 'active': true},
    ],
  });

  @override
  Future<StaffProfile> profile(int id) async => StaffProfile.fromJson({
    'staff': rows.firstWhere((r) => r['id'] == id),
    'summary': {
      'total_visits': 9,
      'total_appointments': 12,
      'tips': '48.50',
      'product_commission': '15.00',
      'service_commission': '210.00',
      'total_earning': '273.50',
    },
  });

  @override
  Future<PagedResult<StaffAppointment>> appointments(
    int id, {
    String? start,
    String? end,
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('appointments:$id:${start ?? '-'}:${end ?? '-'}');
    return PagedResult(
      items: [
        StaffAppointment.fromJson({
          'id': 5,
          'date': '2026-10-25',
          'start_label': '09:30 AM',
          'end_label': '10:15 AM',
          'status': 1,
          'customer': {'name': 'Sam Patel', 'phone': '7805550103'},
          'staff_names': 'Mike',
        }),
      ],
      hasMore: false,
      total: 1,
    );
  }

  @override
  Future<PagedResult<ServiceEarning>> services(
    int id, {
    int page = 1,
    int perPage = 20,
  }) async => PagedResult(
    items: [
      ServiceEarning.fromJson({
        'service_name': "Men's cut",
        'duration': 30,
        'price': '30.00',
        'appointment_count': 4,
        'commission': '60.00',
        'tips': '12.00',
        'total_earning': '72.00',
      }),
    ],
    hasMore: false,
    total: 1,
  );

  @override
  Future<PagedResult<DailyEarning>> earnings(
    int id, {
    int page = 1,
    int perPage = 20,
  }) async => PagedResult(
    items: [
      DailyEarning.fromJson({
        'date': '2026-10-25',
        'product_commission': '3.00',
        'tips': '5.00',
        'service_commission': '20.00',
        'total_earning': '28.00',
      }),
    ],
    hasMore: false,
    total: 1,
  );

  @override
  Future<String> create(StaffInput input) async {
    calls.add('create');
    inputs.add(input);
    if (saveFails != null) throw saveFails!;
    return 'Staff added successfully';
  }

  @override
  Future<String> update(int id, StaffInput input) async {
    calls.add('update:$id');
    inputs.add(input);
    return 'Staff updated successfully';
  }

  @override
  Future<String> delete(int id) async {
    calls.add('delete:$id');
    return 'Staff deleted successfully';
  }

  @override
  Future<String> changePassword(int id, String password, String confirm) async {
    calls.add('password:$id:$password');
    return 'Password changed successfully';
  }

  @override
  Future<List<int>> assignedServices(int id) async => [25];

  @override
  Future<String> assignServices(int id, List<int> serviceIds) async {
    calls.add('assign:$id:${serviceIds.join(',')}');
    return 'Services assigned successfully';
  }
}
