import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> serviceJson(
  int id,
  String name, {
  bool active = true,
  String? section,
}) => {
  'id': id,
  'name': name,
  'category_id': 1,
  'category_name': 'Haircuts',
  'price': '30.00',
  'duration': 30,
  'active': active,
  'eligible_for_tip': true,
  'commission_percent': '10.00',
  'description': 'Classic',
  'image_url': null,
  'home_section': section,
};

Map<String, dynamic> productJson(int id, String name) => {
  'id': id,
  'name': name,
  'category_id': 2,
  'category_name': 'Retail',
  'price': '20.00',
  'stock': 8,
  'commission_percent': '5.00',
  'active': true,
  'description': null,
  'image_url': null,
};

class FakeCatalog extends CatalogRepository {
  FakeCatalog() : super(_NoApi());

  final calls = <String>[];
  final serviceInputs = <ServiceInput>[];
  final productInputs = <ProductInput>[];
  Failure? saveFails;

  final cats = [
    {'id': 1, 'name': 'Haircuts', 'description': 'All cuts', 'image_url': null},
    {'id': 2, 'name': 'Retail', 'description': null, 'image_url': null},
  ];
  var gstRows = [
    {
      'id': 1,
      'name': 'GST',
      'rate': '5.00',
      'tax_type': 'include',
      'is_default': true,
    },
    {
      'id': 2,
      'name': 'PST',
      'rate': '7.00',
      'tax_type': 'exclude',
      'is_default': false,
    },
  ];
  var methods = [
    {'id': 1, 'name': 'Cash'},
    {'id': 2, 'name': 'Online'},
  ];

  @override
  Future<List<AdminCategory>> categories() async => [
    for (final c in cats) AdminCategory.fromJson(c),
  ];

  @override
  Future<PagedResult<AdminService>> services({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('services:$q');
    final all = [
      serviceJson(25, "Men's cut"),
      serviceJson(26, 'Skin fade', active: false),
    ];
    final hit = [
      for (final s in all)
        if (q.isEmpty ||
            s['name'].toString().toLowerCase().contains(q.toLowerCase()))
          AdminService.fromJson(s),
    ];
    return PagedResult(items: hit, hasMore: false, total: hit.length);
  }

  @override
  Future<AdminService> service(int id) async =>
      AdminService.fromJson(serviceJson(id, "Men's cut"));

  @override
  Future<String> createService(ServiceInput i) async {
    calls.add('createService');
    serviceInputs.add(i);
    if (saveFails != null) throw saveFails!;
    return 'Service created successfully.';
  }

  @override
  Future<String> updateService(int id, ServiceInput i) async {
    calls.add('updateService:$id');
    serviceInputs.add(i);
    return 'Service updated successfully.';
  }

  @override
  Future<String> deleteService(int id) async {
    calls.add('deleteService:$id');
    return 'Service deleted successfully.';
  }

  @override
  Future<String> setHomeSection(int id, String? section) async {
    calls.add('section:$id:${section ?? '-'}');
    return 'Website section updated successfully.';
  }

  @override
  Future<PagedResult<AdminProduct>> products({
    String q = '',
    int page = 1,
    int perPage = 20,
  }) async {
    calls.add('products:$q');
    return PagedResult(
      items: [AdminProduct.fromJson(productJson(1, 'Hair oil'))],
      hasMore: false,
      total: 1,
    );
  }

  @override
  Future<AdminProduct> product(int id) async =>
      AdminProduct.fromJson(productJson(id, 'Hair oil'));

  @override
  Future<String> createProduct(ProductInput i) async {
    calls.add('createProduct');
    productInputs.add(i);
    return 'Product created successfully.';
  }

  @override
  Future<String> updateProduct(int id, ProductInput i) async {
    calls.add('updateProduct:$id');
    productInputs.add(i);
    return 'Product updated successfully.';
  }

  @override
  Future<String> deleteProduct(int id) async {
    calls.add('deleteProduct:$id');
    return 'Product deleted successfully.';
  }

  @override
  Future<String> createCategory({
    required String name,
    required String description,
    String? imagePath,
  }) async {
    calls.add('createCategory:$name');
    return 'Category created successfully.';
  }

  @override
  Future<String> updateCategory(
    int id, {
    required String name,
    required String description,
    String? imagePath,
  }) async {
    calls.add('updateCategory:$id:$name');
    return 'Category updated successfully.';
  }

  @override
  Future<String> deleteCategory(int id) async {
    calls.add('deleteCategory:$id');
    return 'Category deleted successfully.';
  }

  @override
  Future<List<GstItem>> gst() async => [
    for (final g in gstRows) GstItem.fromJson(g),
  ];

  @override
  Future<String> createGst(
    String name,
    String rate, {
    required bool exclude,
    required bool isDefault,
  }) async {
    calls.add(
      'createGst:$name:$rate:${exclude ? 'x' : 'i'}:${isDefault ? 'd' : '-'}',
    );
    return 'GST record created successfully.';
  }

  @override
  Future<String> deleteGst(int id) async {
    calls.add('deleteGst:$id');
    return 'GST record deleted successfully.';
  }

  @override
  Future<List<PaymentMethodItem>> paymentMethods() async => [
    for (final m in methods) PaymentMethodItem.fromJson(m),
  ];

  @override
  Future<String> createPayment(String name) async {
    calls.add('createPayment:$name');
    if (saveFails != null) throw saveFails!;
    return 'Payment method created successfully';
  }

  @override
  Future<String> deletePayment(int id) async {
    calls.add('deletePayment:$id');
    return 'Payment method deleted successfully';
  }
}
