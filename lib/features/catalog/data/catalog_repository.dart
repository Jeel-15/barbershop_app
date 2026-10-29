import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// CAT-1..5: services, categories, products, GST and payment methods.
/// Writes need the web's own permission per action (Service-Add, ...).
class CatalogRepository {
  const CatalogRepository(this._api);

  final ApiClient _api;

  PagedResult<T> _page<T>(
    ApiResponse res,
    T Function(Map<String, dynamic>) parse,
  ) => PagedResult(
    items: [
      for (final e in (res.data['items'] as List? ?? const []))
        parse(Map<String, dynamic>.from(e as Map)),
    ],
    hasMore: res.meta['has_more'] == true,
    total: (res.meta['total'] as num?)?.toInt() ?? 0,
  );

  // ---------------------------------------------------------- categories

  Future<List<AdminCategory>> categories() async {
    final res = await _api.get('/service-categories');
    return [
      for (final c in (res.data['items'] as List? ?? const []))
        AdminCategory.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
  }

  @visibleForTesting
  static Future<FormData> categoryForm({
    required String name,
    required String description,
    String? imagePath,
  }) async {
    final form = FormData()
      ..fields.addAll([
        MapEntry('name', name.trim()),
        MapEntry('description', description.trim()),
      ]);
    if (imagePath != null) {
      form.files.add(
        MapEntry('image', await MultipartFile.fromFile(imagePath)),
      );
    }
    return form;
  }

  Future<String> createCategory({
    required String name,
    required String description,
    String? imagePath,
  }) async => (await _api.post(
    '/service-categories',
    body: await categoryForm(
      name: name,
      description: description,
      imagePath: imagePath,
    ),
  )).message;

  Future<String> updateCategory(
    int id, {
    required String name,
    required String description,
    String? imagePath,
  }) async => (await _api.post(
    '/service-categories/$id',
    body: await categoryForm(
      name: name,
      description: description,
      imagePath: imagePath,
    ),
  )).message;

  Future<String> deleteCategory(int id) async =>
      (await _api.delete('/service-categories/$id')).message;

  // ------------------------------------------------------------ services

  Future<PagedResult<AdminService>> services({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async => _page(
    await _api.get(
      '/services',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'per_page': perPage,
      },
    ),
    AdminService.fromJson,
  );

  Future<AdminService> service(int id) async => AdminService.fromJson(
    Map<String, dynamic>.from(
      (await _api.get('/services/$id')).data['service'] as Map,
    ),
  );

  @visibleForTesting
  static Future<FormData> serviceForm(ServiceInput i) async {
    final form = FormData()
      ..fields.addAll([
        MapEntry('category_id', '${i.categoryId}'),
        MapEntry('name', i.name.trim()),
        MapEntry('price', i.price.trim()),
        MapEntry('duration', i.duration.trim()),
        if (i.commission.trim().isNotEmpty)
          MapEntry('commission', i.commission.trim()),
        MapEntry('description', i.description.trim()),
        MapEntry('active_status', i.active ? '1' : '0'),
        MapEntry('eligible_for_tip', i.eligibleForTip ? '1' : '0'),
      ]);
    if (i.imagePath != null) {
      form.files.add(
        MapEntry('image', await MultipartFile.fromFile(i.imagePath!)),
      );
    }
    return form;
  }

  Future<String> createService(ServiceInput i) async =>
      (await _api.post('/services', body: await serviceForm(i))).message;

  Future<String> updateService(int id, ServiceInput i) async =>
      (await _api.post('/services/$id', body: await serviceForm(i))).message;

  Future<String> deleteService(int id) async =>
      (await _api.delete('/services/$id')).message;

  /// The web's "Website Section" (null = none, `signature_grooming`).
  Future<String> setHomeSection(int id, String? section) async =>
      (await _api.patch(
        '/services/$id/home-section',
        body: {'home_section': section},
      )).message;

  // ------------------------------------------------------------ products

  Future<PagedResult<AdminProduct>> products({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async => _page(
    await _api.get(
      '/products',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'per_page': perPage,
      },
    ),
    AdminProduct.fromJson,
  );

  Future<AdminProduct> product(int id) async => AdminProduct.fromJson(
    Map<String, dynamic>.from(
      (await _api.get('/products/$id')).data['product'] as Map,
    ),
  );

  @visibleForTesting
  static Future<FormData> productForm(ProductInput i) async {
    final form = FormData()
      ..fields.addAll([
        MapEntry('category_id', '${i.categoryId}'),
        MapEntry('name', i.name.trim()),
        MapEntry('price', i.price.trim()),
        MapEntry('stock', i.stock.trim()),
        MapEntry('commission', i.commission.trim()),
        MapEntry('description', i.description.trim()),
        MapEntry('active_status', i.active ? '1' : '0'),
      ]);
    if (i.imagePath != null) {
      form.files.add(
        MapEntry('image', await MultipartFile.fromFile(i.imagePath!)),
      );
    }
    return form;
  }

  Future<String> createProduct(ProductInput i) async =>
      (await _api.post('/products', body: await productForm(i))).message;

  Future<String> updateProduct(int id, ProductInput i) async =>
      (await _api.post('/products/$id', body: await productForm(i))).message;

  Future<String> deleteProduct(int id) async =>
      (await _api.delete('/products/$id')).message;

  // ----------------------------------------------------------------- GST

  Future<List<GstItem>> gst() async {
    final res = await _api.get('/gst');
    return [
      for (final g in (res.data['items'] as List? ?? const []))
        GstItem.fromJson(Map<String, dynamic>.from(g as Map)),
    ];
  }

  Map<String, dynamic> _gstBody(
    String name,
    String rate,
    bool exclude,
    bool isDefault,
  ) => {
    'name': name.trim(),
    'rate': rate.trim(),
    'tax_type': exclude ? 'exclude' : 'include',
    'is_default': isDefault,
  };

  Future<String> createGst(
    String name,
    String rate, {
    required bool exclude,
    required bool isDefault,
  }) async => (await _api.post(
    '/gst',
    body: _gstBody(name, rate, exclude, isDefault),
  )).message;

  Future<String> updateGst(
    int id,
    String name,
    String rate, {
    required bool exclude,
    required bool isDefault,
  }) async => (await _api.put(
    '/gst/$id',
    body: _gstBody(name, rate, exclude, isDefault),
  )).message;

  /// The API's message says so when no default GST is left.
  Future<String> deleteGst(int id) async =>
      (await _api.delete('/gst/$id')).message;

  // ----------------------------------------------------- payment methods

  Future<List<PaymentMethodItem>> paymentMethods() async {
    final res = await _api.get('/payment-methods');
    return [
      for (final m in (res.data['items'] as List? ?? const []))
        PaymentMethodItem.fromJson(Map<String, dynamic>.from(m as Map)),
    ];
  }

  Future<String> createPayment(String name) async => (await _api.post(
    '/payment-methods',
    body: {'name': name.trim()},
  )).message;

  Future<String> updatePayment(int id, String name) async => (await _api.put(
    '/payment-methods/$id',
    body: {'name': name.trim()},
  )).message;

  Future<String> deletePayment(int id) async =>
      (await _api.delete('/payment-methods/$id')).message;
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);

final categoriesProvider = FutureProvider.autoDispose<List<AdminCategory>>(
  (ref) => ref.read(catalogRepositoryProvider).categories(),
);

final gstListProvider = FutureProvider.autoDispose<List<GstItem>>(
  (ref) => ref.read(catalogRepositoryProvider).gst(),
);

final paymentMethodsProvider =
    FutureProvider.autoDispose<List<PaymentMethodItem>>(
      (ref) => ref.read(catalogRepositoryProvider).paymentMethods(),
    );
