import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SHOP-1..: business settings, the shop's opening hours and closures.
class ShopRepository {
  const ShopRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------ settings

  Future<ShopSettings> settings() async =>
      ShopSettings.fromJson((await _api.get('/settings')).data);

  Future<String> saveGeneral({
    required int reminderDays,
    required int defaultDuration,
    required String serviceFee,
    required bool invoiceMail,
  }) async => (await _api.put(
    '/settings/general',
    body: {
      'service_reminder_day': reminderDays,
      'service_default_duration': defaultDuration,
      'service_fee': serviceFee.trim(),
      'invoice_mail_send_status': invoiceMail,
    },
  )).message;

  Future<String> saveContact(Map<String, String> values) async =>
      (await _api.put(
        '/settings/contact',
        body: {for (final e in values.entries) e.key: e.value.trim()},
      )).message;

  // --------------------------------------------------------------- hours

  Future<List<ShopDay>> hours() async {
    final res = await _api.get('/shop-hours');
    return [
      for (final d in (res.data['days'] as List? ?? const []))
        ShopDay.fromJson(Map<String, dynamic>.from(d as Map)),
    ];
  }

  Future<String> saveHours(List<ShopDay> days) async => (await _api.put(
    '/shop-hours',
    body: {
      'days': [for (final d in days) d.toJson()],
    },
  )).message;

  // ------------------------------------------------------------ closures

  Future<PagedResult<ShopClosureItem>> closures({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.get(
      '/shop-closures',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'per_page': perPage,
      },
    );
    return PagedResult(
      items: [
        for (final c in (res.data['items'] as List? ?? const []))
          ShopClosureItem.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      hasMore: res.meta['has_more'] == true,
      total: (res.meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> createClosure(ClosureInput i) async =>
      (await _api.post('/shop-closures', body: i.toJson())).message;

  Future<String> updateClosure(int id, ClosureInput i) async =>
      (await _api.put('/shop-closures/$id', body: i.toJson())).message;

  Future<String> deleteClosure(int id) async =>
      (await _api.delete('/shop-closures/$id')).message;
}

final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) => ShopRepository(ref.watch(apiClientProvider)),
);

final shopSettingsProvider = FutureProvider.autoDispose<ShopSettings>(
  (ref) => ref.read(shopRepositoryProvider).settings(),
);

final shopHoursProvider = FutureProvider.autoDispose<List<ShopDay>>(
  (ref) => ref.read(shopRepositoryProvider).hours(),
);
