import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';

/// Dashboard calls (DASH-1..4, DASH-6). Team performance (DASH-5) is not on
/// the web dashboard, so Home does not load it.
class DashboardRepository {
  const DashboardRepository(this._api);

  final ApiClient _api;

  /// Fetches what this user may see (the server's `widgets` flags decide) and
  /// returns the raw answers, ready to be cached and parsed by
  /// [HomeData.fromRaw]. The sections load in parallel.
  Future<Map<String, dynamic>> load() async {
    final summary = await _api.get('/dashboard/summary');
    final w = Map<String, dynamic>.from(
      (summary.data['widgets'] as Map?) ?? const {},
    );

    Future<List<dynamic>> items(String path, {bool allowed = true}) async {
      if (!allowed) return const [];
      try {
        final res = await _api.get(path, query: {'per_page': 50});
        return (res.data['items'] as List?) ?? const [];
      } on ForbiddenFailure {
        return const [];
      }
    }

    final results = await Future.wait([
      items('/dashboard/today', allowed: w['today'] == true),
      items('/dashboard/upcoming', allowed: w['upcoming'] == true),
      items('/dashboard/top-services', allowed: w['top_services'] == true),
      items('/dashboard/top-products', allowed: w['top_products'] == true),
    ]);

    return {
      'summary': summary.data,
      'today': results[0],
      'upcoming': results[1],
      'topServices': results[2],
      'products': results[3],
    };
  }
}
