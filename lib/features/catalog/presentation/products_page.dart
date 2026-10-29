import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/catalog/application/catalog_controllers.dart';
import 'package:barbershop_app/features/catalog/data/catalog_repository.dart';
import 'package:barbershop_app/features/catalog/domain/catalog_models.dart';
import 'package:barbershop_app/features/catalog/presentation/widgets/admin_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's Products page ("Manage retail products, pricing, and inventory").
class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key});

  Future<void> _form(
    BuildContext context,
    WidgetRef ref, [
    AdminProduct? p,
  ]) async {
    final msg = await context.push<String>(
      p == null ? '/app/products/new' : '/app/products/edit/${p.id}',
      extra: p,
    );
    if (msg != null && context.mounted) {
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(productsListProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AdminProduct p,
  ) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Product?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final msg = await ref.read(catalogRepositoryProvider).deleteProduct(p.id);
      if (!context.mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      ref.invalidate(productsListProvider);
    } on Failure catch (f) {
      if (context.mounted) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final query = ref.watch(productQueryProvider);
    final canEdit = user.can('Product-Edit');
    final canDelete = user.can('Product-Delete');
    return AdminListShell(
      title: 'Products',
      subtitle: 'Manage retail products, pricing, and inventory',
      addLabel: 'Add Product',
      onAdd: user.can('Product-Add') ? () => _form(context, ref) : null,
      searchHint: 'Search product, category or price',
      query: query,
      onSearch: (q) => ref.read(productQueryProvider.notifier).set(q),
      body: PagedBody<AdminProduct>(
        async: ref.watch(productsListProvider),
        countLabel: query.trim().isEmpty ? 'ALL PRODUCTS' : 'FOUND',
        emptyTitle: query.trim().isEmpty
            ? 'No products yet'
            : 'No products found',
        emptyMessage: query.trim().isEmpty
            ? 'Add the first retail product.'
            : 'Try another name, category or price.',
        onRefresh: () => ref.read(productsListProvider.notifier).refresh(),
        onRetry: () => ref.invalidate(productsListProvider),
        onMore: () => ref.read(productsListProvider.notifier).loadMore(),
        itemBuilder: (context, p) => AdminTile(
          title: p.name,
          imageUrl: p.imageUrl,
          icon: Icons.inventory_2_rounded,
          badge: StatusPill(
            label: p.active ? 'Active' : 'Deactive',
            color: p.active ? t.success : t.danger,
            compact: true,
          ),
          lines: [
            '${p.categoryName} · Stock ${p.stock}',
            'Commission ${p.commission}%',
          ],
          trailing: Padding(
            padding: const EdgeInsets.only(left: AppSpace.sm),
            child: Text(
              p.price.format(),
              style: AppType.bodyStrong.copyWith(color: t.text),
            ),
          ),
          menu: [
            if (canEdit) ('edit', 'Edit', false),
            if (canDelete) ('delete', 'Delete', true),
          ],
          onMenu: (v) =>
              v == 'edit' ? _form(context, ref, p) : _delete(context, ref, p),
          onTap: canEdit ? () => _form(context, ref, p) : null,
        ),
      ),
    );
  }
}
