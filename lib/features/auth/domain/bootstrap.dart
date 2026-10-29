import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/domain/auth_user.dart';

/// Everything the app needs at launch, from one call (`GET /bootstrap`):
/// the user and permissions, shop details, tax, payment methods, status
/// names, which actions each appointment status allows, shop hours, limits
/// and the app-version gate.
class Bootstrap {
  const Bootstrap({
    required this.user,
    required this.shop,
    required this.currencyCode,
    required this.currencySymbol,
    required this.timezone,
    required this.paymentMethods,
    required this.appointmentActions,
    required this.slotStepMinutes,
    required this.shopHours,
    required this.perPageMax,
    required this.uploadMaxKb,
    required this.apiVersion,
    required this.apiBuild,
    required this.minAppVersion,
    required this.latestAppVersion,
    required this.featureFlags,
    required this.raw,
    this.tax,
  });

  factory Bootstrap.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> map(Object? v) =>
        Map<String, dynamic>.from((v as Map?) ?? const {});
    final shop = map(j['shop']);
    final currency = map(j['currency']);
    final limits = map(j['limits']);
    final app = map(j['app']);
    final tax = j['tax'];

    return Bootstrap(
      user: AuthUser.fromJson(map(j['user'])),
      shop: ShopInfo(
        name: (shop['name'] ?? 'Rosenthal Barbershop').toString(),
        logoUrl: shop['logo_url']?.toString(),
        address: shop['address']?.toString(),
        phone: shop['phone']?.toString(),
        email: shop['email']?.toString(),
        whatsapp: shop['whatsapp']?.toString(),
        website: shop['website']?.toString(),
      ),
      currencyCode: (currency['code'] ?? 'CAD').toString(),
      currencySymbol: (currency['symbol'] ?? r'$').toString(),
      timezone: (j['timezone'] ?? 'America/Edmonton').toString(),
      tax: tax is Map
          ? TaxInfo(
              id: (tax['id'] as num).toInt(),
              name: tax['name'].toString(),
              rate: tax['rate'].toString(),
              inclusive: tax['type'].toString() != 'exclude',
            )
          : null,
      paymentMethods: [
        for (final m in (j['payment_methods'] as List? ?? const []))
          NamedItem((m['id'] as num).toInt(), m['name'].toString()),
      ],
      appointmentActions: [
        for (final row in (j['appointment_actions'] as List? ?? const []))
          [for (final a in (row as List)) a.toString()],
      ],
      slotStepMinutes: (j['slot_step_minutes'] as num?)?.toInt() ?? 10,
      shopHours: [
        for (final d in (j['shop_hours'] as List? ?? const []))
          ShopDay(
            day: d['day'].toString(),
            isDayOff: d['is_day_off'] == true,
            open: d['open']?.toString(),
            close: d['close']?.toString(),
          ),
      ],
      perPageMax: (limits['per_page_max'] as num?)?.toInt() ?? 50,
      uploadMaxKb: (limits['upload_max_kb'] as num?)?.toInt() ?? 2048,
      apiVersion: (app['api_version'] ?? 'v1').toString(),
      apiBuild: (app['build'] ?? '').toString(),
      minAppVersion: AppVersion.parse(
        (app['min_app_version'] ?? '0.0.0').toString(),
      ),
      latestAppVersion: AppVersion.parse(
        (app['latest_app_version'] ?? '0.0.0').toString(),
      ),
      featureFlags: {
        for (final e in map(app['feature_flags']).entries)
          e.key: e.value == true,
      },
      raw: j,
    );
  }

  final AuthUser user;
  final ShopInfo shop;
  final String currencyCode;
  final String currencySymbol;
  final String timezone;
  final TaxInfo? tax;
  final List<NamedItem> paymentMethods;

  /// Index = appointment status code (0 pending ... 4 rescheduled); values are
  /// the actions the web allows in that status: confirm, cancel, reschedule, view.
  final List<List<String>> appointmentActions;
  final int slotStepMinutes;
  final List<ShopDay> shopHours;
  final int perPageMax;
  final int uploadMaxKb;
  final String apiVersion;
  final String apiBuild;
  final AppVersion minAppVersion;
  final AppVersion latestAppVersion;
  final Map<String, bool> featureFlags;

  /// The JSON as received (kept for the offline cache).
  final Map<String, dynamic> raw;

  List<String> actionsFor(int statusCode) =>
      statusCode >= 0 && statusCode < appointmentActions.length
      ? appointmentActions[statusCode]
      : const ['view'];

  bool flag(String name) => featureFlags[name] ?? false;
}

class ShopInfo {
  const ShopInfo({
    required this.name,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.whatsapp,
    this.website,
  });

  final String name;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String? whatsapp;
  final String? website;
}

class TaxInfo {
  const TaxInfo({
    required this.id,
    required this.name,
    required this.rate,
    required this.inclusive,
  });

  final int id;
  final String name;
  final String rate;
  final bool inclusive;
}

class NamedItem {
  const NamedItem(this.id, this.name);

  final int id;
  final String name;
}

class ShopDay {
  const ShopDay({
    required this.day,
    required this.isDayOff,
    this.open,
    this.close,
  });

  final String day;
  final bool isDayOff;
  final String? open;
  final String? close;
}
