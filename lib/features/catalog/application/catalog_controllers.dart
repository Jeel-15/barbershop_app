import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _QueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

/// Search text of the Services list.
final serviceQueryProvider = NotifierProvider<_QueryNotifier, String>(
  _QueryNotifier.new,
);

/// Search text of the Products list.
final productQueryProvider = NotifierProvider<_QueryNotifier, String>(
  _QueryNotifier.new,
);

final servicesListProvider =
    AsyncNotifierProvider<ServicesListController, PagedState<AdminService>>(
      ServicesListController.new,
      retry: (_, _) => null,
    );

class ServicesListController extends PagedNotifier<AdminService> {
  @override
  Future<PagedResult<AdminService>> fetch(int page) => ref
      .read(catalogRepositoryProvider)
      .services(q: ref.read(serviceQueryProvider), page: page);

  @override
  Future<PagedState<AdminService>> build() {
    ref.watch(currentUserProvider);
    ref.watch(serviceQueryProvider);
    return super.build();
  }
}

final productsListProvider =
    AsyncNotifierProvider<ProductsListController, PagedState<AdminProduct>>(
      ProductsListController.new,
      retry: (_, _) => null,
    );

class ProductsListController extends PagedNotifier<AdminProduct> {
  @override
  Future<PagedResult<AdminProduct>> fetch(int page) => ref
      .read(catalogRepositoryProvider)
      .products(q: ref.read(productQueryProvider), page: page);

  @override
  Future<PagedState<AdminProduct>> build() {
    ref.watch(currentUserProvider);
    ref.watch(productQueryProvider);
    return super.build();
  }
}
