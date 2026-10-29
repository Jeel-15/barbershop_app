import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> profileJson({bool staff = true}) => {
  'user': {
    'name': 'Mike Staff',
    'email': 'mike@rosen.test',
    'phone': '7805550142',
    'role': staff ? 'Staff' : 'Admin',
    'profile_image_url': null,
  },
  'services': ["Men's cut", 'Skin fade'],
  'stats': staff
      ? {
          'appointments': 12,
          'visits': 9,
          'tips': '48.50',
          'service_commission': '210.00',
          'product_commission': '15.00',
          'total_earning': '273.50',
        }
      : null,
};

List<Map<String, dynamic>> weekJson() => [
  {
    'slot_id': 1,
    'day_name': 'Monday',
    'is_day_off': false,
    'blocks': [
      {
        'id': 10,
        'start': '09:00',
        'end': '13:00',
        'start_label': '09:00 AM',
        'end_label': '01:00 PM',
      },
      {
        'id': 11,
        'start': '14:00',
        'end': '18:30',
        'start_label': '02:00 PM',
        'end_label': '06:30 PM',
      },
    ],
  },
  {
    'slot_id': 2,
    'day_name': 'Tuesday',
    'is_day_off': false,
    'blocks': <Object>[],
  },
  {
    'slot_id': 3,
    'day_name': 'Wednesday',
    'is_day_off': true,
    'blocks': <Object>[],
  },
];

class FakeMe extends MeRepository {
  FakeMe({this.staff = true}) : super(_NoApi());

  final bool staff;
  final calls = <String>[];
  Failure? hoursFail;
  Failure? profileFail;
  var days = weekJson();

  @override
  Future<MyProfile> profile() async =>
      MyProfile.fromJson(profileJson(staff: staff));

  @override
  Future<MyProfile> updateProfile({
    required String name,
    required String email,
    required String phone,
    String? photoPath,
  }) async {
    calls.add('profile:$name|$email|$phone|${photoPath ?? '-'}');
    if (profileFail != null) throw profileFail!;
    return MyProfile.fromJson(profileJson(staff: staff));
  }

  @override
  Future<ReportSummary> reportSummary(ReportFilter f) async {
    calls.add('summary:${f.start ?? '-'}:${f.end ?? '-'}:${f.status ?? '-'}');
    return ReportSummary.fromJson({
      'my_total_earning': '273.50',
      'my_product_commission': '15.00',
      'my_service_commission': '210.00',
      'my_tips': '48.50',
    });
  }

  @override
  Future<PagedResult<ReportAppointment>> reportAppointments(
    ReportFilter f, {
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('appointments:${f.status ?? '-'}');
    return PagedResult(
      items: [
        ReportAppointment.fromJson({
          'id': 5,
          'date': '2026-10-25',
          'start_label': '09:30 AM',
          'end_label': '10:15 AM',
          'status': 1,
          'customer': {'name': 'Sam Patel', 'phone': '7805550103'},
          'discount': '6.50',
          'tip': '5.00',
          'total': '83.50',
        }),
      ],
      hasMore: false,
      total: 1,
    );
  }

  @override
  Future<PagedResult<ServiceEarning>> reportServices({
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
  Future<PagedResult<DailyEarning>> reportDays({
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
  Future<List<WorkDay>> workingHours() async => [
    for (final d in days) WorkDay.fromJson(d),
  ];

  @override
  Future<String> addHours(int slotId, String start, String end) async {
    calls.add('add:$slotId:$start-$end');
    if (hoursFail != null) throw hoursFail!;
    return 'Working Hours Added Successfully.';
  }

  @override
  Future<String> updateHours(int blockId, String start, String end) async {
    calls.add('update:$blockId:$start-$end');
    return 'Working Hours Updated Successfully.';
  }

  @override
  Future<String> deleteHours(int blockId) async {
    calls.add('delete:$blockId');
    return 'Working hours deleted successfully.';
  }

  @override
  Future<void> setDayOff(int slotId, {required bool off}) async {
    calls.add('off:$slotId:$off');
  }
}
