import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/shop/data/shop_repository.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

List<Map<String, dynamic>> hoursJson() => [
  {
    'day': 'Monday',
    'slot_id': 1,
    'is_day_off': false,
    'open_time': '09:00',
    'close_time': '20:00',
    'breaks': [
      {'break_start': '13:00', 'break_end': '14:00'},
    ],
  },
  {
    'day': 'Tuesday',
    'slot_id': 2,
    'is_day_off': true,
    'open_time': null,
    'close_time': null,
    'breaks': <Object>[],
  },
  {
    'day': 'Wednesday',
    'slot_id': 3,
    'is_day_off': false,
    'open_time': null,
    'close_time': null,
    'breaks': <Object>[],
  },
];

class FakeShop extends ShopRepository {
  FakeShop() : super(_NoApi());

  final calls = <String>[];
  List<ShopDay>? savedHours;
  Map<String, String>? savedContact;
  Failure? contactFails;

  @override
  Future<ShopSettings> settings() async => ShopSettings.fromJson({
    'general': {
      'service_reminder_day': 7,
      'service_default_duration': 30,
      'service_fee': '1.50',
      'invoice_mail_send_status': true,
    },
    'contact': {
      'footer_about': 'About us',
      'contact_address': '1 Main St',
      'contact_phone': '+1 780 555 0100',
      'contact_email': 'info@rosen.test',
      'support_email': null,
      'whatsapp': '17805550100',
      'website_url': 'rosen.test',
      'facebook_url': null,
    },
  });

  @override
  Future<String> saveGeneral({
    required int reminderDays,
    required int defaultDuration,
    required String serviceFee,
    required bool invoiceMail,
  }) async {
    calls.add(
      'general:$reminderDays:$defaultDuration:$serviceFee:$invoiceMail',
    );
    return 'Setting Updated Successfully.';
  }

  @override
  Future<String> saveContact(Map<String, String> values) async {
    savedContact = values;
    if (contactFails != null) throw contactFails!;
    return 'Contact details updated successfully. Changes are live on the website.';
  }

  @override
  Future<List<ShopDay>> hours() async => [
    for (final d in hoursJson()) ShopDay.fromJson(d),
  ];

  @override
  Future<String> saveHours(List<ShopDay> days) async {
    savedHours = days;
    return 'Slot configuration stored successfully.';
  }

  final closureRows = [
    {
      'id': 1,
      'date': '2026-12-25',
      'full_day': true,
      'start_time': null,
      'end_time': null,
      'label': 'Full Day Close',
      'reason': 'Christmas',
    },
    {
      'id': 2,
      'date': '2026-11-03',
      'full_day': false,
      'start_time': '09:00',
      'end_time': '11:00',
      'label': '09:00 AM - 11:00 AM',
      'reason': 'Plumber',
    },
  ];

  @override
  Future<PagedResult<ShopClosureItem>> closures({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('closures:$q');
    final hit = [
      for (final c in closureRows)
        if (q.isEmpty ||
            c['reason'].toString().toLowerCase().contains(q.toLowerCase()))
          ShopClosureItem.fromJson(c),
    ];
    return PagedResult(items: hit, hasMore: false, total: hit.length);
  }

  @override
  Future<String> createClosure(ClosureInput i) async {
    calls.add('create:${i.date}:${i.fullDay}:${i.start}:${i.end}:${i.reason}');
    return 'Shop closure created successfully.';
  }

  @override
  Future<String> deleteClosure(int id) async {
    calls.add('delete:$id');
    return 'Shop closure deleted successfully.';
  }
}
