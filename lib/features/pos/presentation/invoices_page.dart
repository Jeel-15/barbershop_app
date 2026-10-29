import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/pos/application/invoices_controller.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's Invoices page ("View, edit, and send customer invoices"): the
/// newest first, search, Add Invoice. Staff only see what the server allows.
class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(invoiceListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final list = ref.watch(invoiceListProvider);
    final query = ref.watch(invoiceQueryProvider);

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
                      'Invoices',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                  if (user.can('Pos_invoice-Add'))
                    HeaderIconButton(
                      icon: Icons.add_rounded,
                      label: 'Add Invoice',
                      onTap: () => context.push('/app/invoice/new'),
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
                  'View, edit, and send customer invoices',
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
                hint: 'Search invoice, name or phone',
                initial: query,
                onChanged: (q) =>
                    ref.read(invoiceQueryProvider.notifier).set(q),
              ),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: AppRefresh(
                onRefresh: () =>
                    ref.read(invoiceListProvider.notifier).refresh(),
                child: switch (list) {
                  AsyncData(:final value) => _List(
                    state: value,
                    controller: _scroll,
                    searching: query.trim().isNotEmpty,
                    onOpen: (i) => context.push('/app/invoice/${i.id}'),
                    onRetryMore: () =>
                        ref.read(invoiceListProvider.notifier).loadMore(),
                  ),
                  AsyncError(:final error) => _Scrollable(
                    child: ErrorState(
                      message: error is Failure
                          ? error.userMessage
                          : 'Could not load invoices.',
                      supportCode: error is Failure ? error.requestId : null,
                      onRetry: () => ref.invalidate(invoiceListProvider),
                    ),
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.only(top: AppSpace.md),
                    child: SkeletonRows(count: 6),
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
    required this.searching,
    required this.onOpen,
    required this.onRetryMore,
  });

  final InvoiceListState state;
  final ScrollController controller;
  final bool searching;
  final ValueChanged<InvoiceRow> onOpen;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (state.items.isEmpty) {
      return _Scrollable(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: QuietState(
            title: searching ? 'No invoices found' : 'No invoices yet',
            message: searching
                ? 'Try another invoice number, name or phone.'
                : 'Completed appointments and new invoices show up here.',
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
              '${searching ? 'FOUND' : 'ALL INVOICES'} · ${state.total}',
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
        final inv = state.items[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
          child: _InvoiceTile(invoice: inv, onTap: () => onOpen(inv)),
        );
      },
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.onTap});

  final InvoiceRow invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final inv = invoice;
    final day = inv.day == null
        ? null
        : ShopTime.fullDate(ShopTime.parseDate(inv.day!));
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                size: 21,
                color: t.accentText,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inv.customerName.isEmpty ? '-' : inv.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                  Text(
                    inv.number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  if (inv.staffNames.isNotEmpty || day != null)
                    Text(
                      [
                        ?day,
                        if (inv.staffNames.isNotEmpty) inv.staffNames,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: t.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  inv.total.format(),
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
                const SizedBox(height: 4),
                StatusPill(label: 'Paid', color: t.success, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
