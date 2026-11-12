import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/customers/application/customers_controller.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/customers/presentation/customer_form_sheet.dart';
import 'package:barbershop_app/shared/contact_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

/// The web's Customers page ("Manage your customer directory"): a searchable
/// list with Add Customer, and per row View / Edit / Delete by permission.
class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(customerListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final saved = await showCustomerFormSheet(context);
    if (saved == null || !mounted) return;
    showToast(
      context,
      'Customer created successfully.',
      kind: ToastKind.success,
    );
    await ref.read(customerListProvider.notifier).refresh();
  }

  Future<void> _edit(CustomerSummary c) async {
    final saved = await showCustomerFormSheet(context, editing: c);
    if (saved == null || !mounted) return;
    showToast(
      context,
      'Customer updated successfully.',
      kind: ToastKind.success,
    );
    await ref.read(customerListProvider.notifier).refresh();
  }

  Future<void> _delete(CustomerSummary c) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Customer?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(customersRepositoryProvider).delete(c.id);
      if (!mounted) return;
      showToast(
        context,
        'Customer deleted successfully.',
        kind: ToastKind.success,
      );
      await ref.read(customerListProvider.notifier).refresh();
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final list = ref.watch(customerListProvider);
    final query = ref.watch(customerQueryProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.sm,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  RoundBackButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/app/more'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      'Customers',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                  if (user.can(Perm.customerAdd))
                    HeaderIconButton(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Add Customer',
                      onTap: _add,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                0,
                AppSpace.page,
                AppSpace.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Manage your customer directory',
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.page,
                vertical: AppSpace.sm,
              ),
              child: AppSearchField(
                hint: 'Search name, phone or email',
                initial: query,
                onChanged: (q) =>
                    ref.read(customerQueryProvider.notifier).set(q),
              ),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: AppRefresh(
                onRefresh: () =>
                    ref.read(customerListProvider.notifier).refresh(),
                child: switch (list) {
                  AsyncData(:final value) => _List(
                    state: value,
                    controller: _scroll,
                    canEdit: user.can(Perm.customerEdit),
                    canDelete: user.can(Perm.customerDelete),
                    searching: query.trim().isNotEmpty,
                    onOpen: (c) => context.push('/app/customer/${c.id}'),
                    onEdit: _edit,
                    onDelete: _delete,
                    onRetryMore: () =>
                        ref.read(customerListProvider.notifier).loadMore(),
                  ),
                  AsyncError(:final error) => _Scrollable(
                    child: ErrorState(
                      message: error is Failure
                          ? error.userMessage
                          : 'Could not load customers.',
                      supportCode: error is Failure ? error.requestId : null,
                      onRetry: () => ref.invalidate(customerListProvider),
                    ),
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.only(top: AppSpace.md),
                    child: SkeletonRows(count: 7),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [SizedBox(height: 480, child: child)],
  );
}

class _List extends StatelessWidget {
  const _List({
    required this.state,
    required this.controller,
    required this.canEdit,
    required this.canDelete,
    required this.searching,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onRetryMore,
  });

  final CustomerListState state;
  final ScrollController controller;
  final bool canEdit;
  final bool canDelete;
  final bool searching;
  final ValueChanged<CustomerSummary> onOpen;
  final ValueChanged<CustomerSummary> onEdit;
  final ValueChanged<CustomerSummary> onDelete;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (state.items.isEmpty) {
      return _Scrollable(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: QuietState(
            title: searching ? 'No customers found' : 'No customers yet',
            message: searching
                ? 'Try another name, phone or email.'
                : 'Customers appear here after their first booking.',
          ),
        ),
      );
    }
    return ListView.builder(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.md,
        AppSpace.page,
        AppSpace.xxl,
      ),
      itemCount: state.items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              '${searching ? 'FOUND' : 'ALL CUSTOMERS'} · ${state.total}',
              style: AppType.overline.copyWith(color: t.textMuted),
            ),
          );
        }
        if (i == state.items.length + 1) {
          if (state.loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            );
          }
          if (state.loadMoreFailed) {
            return TextButton(
              onPressed: onRetryMore,
              child: const Text('Could not load more. Tap to retry'),
            );
          }
          return const SizedBox.shrink();
        }
        final c = state.items[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
          child: _CustomerTile(
            customer: c,
            onTap: () => onOpen(c),
            onEdit: canEdit ? () => onEdit(c) : null,
            onDelete: canDelete ? () => onDelete(c) : null,
          ),
        );
      },
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final CustomerSummary customer;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = customer;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          AppSpace.xs,
          AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            AppAvatar(name: c.name, size: 46),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                  if (c.hasPhone)
                    Text(
                      c.phone!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                  if (!c.isActive) ...[
                    const SizedBox(height: 4),
                    StatusPill(
                      label: 'Inactive',
                      color: t.danger,
                      compact: true,
                    ),
                  ],
                ],
              ),
            ),
            if (c.hasPhone)
              IconButton(
                tooltip: 'Call',
                icon: Icon(Icons.call_rounded, size: 20, color: t.accentText),
                onPressed: () => callCustomer(context, c.phone),
              ),
            if (onEdit != null || onDelete != null)
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: t.textSecondary,
                ),
                color: t.surfaceRaised,
                onSelected: (v) =>
                    v == 'edit' ? onEdit?.call() : onDelete?.call(),
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: t.danger)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
