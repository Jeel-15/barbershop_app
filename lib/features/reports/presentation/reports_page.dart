import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/me/presentation/widgets/earning_cards.dart';
import 'package:barbershop_app/features/reports/application/reports_controller.dart';
import 'package:barbershop_app/features/reports/domain/report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _Tab { earning, payments, staff, invoice, product, top }

/// The web's Reports ("Analyze revenue, appointments, staff performance, and
/// sales"): a filter, four headline cards and six tabs.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  final _scroll = ScrollController();
  _Tab _tab = _Tab.earning;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) {
        switch (_tab) {
          case _Tab.earning:
            ref.read(reportEarningProvider.notifier).loadMore();
          case _Tab.invoice:
            ref.read(reportInvoicesProvider.notifier).loadMore();
          case _Tab.product:
            ref.read(reportProductSalesProvider.notifier).loadMore();
          case _Tab.payments || _Tab.staff || _Tab.top:
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openFilter() async {
    final draft = _Draft(ref.read(reportsFilterProvider));
    final staff = ref.read(reportStaffOptionsProvider).value ?? const [];
    final res = await showAppSheet<ReportsFilter>(
      context,
      title: 'Reports Filter',
      builder: (_) => _FilterBody(draft: draft, staff: staff),
      footer: (ctx) => Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Clear',
              variant: AppButtonVariant.secondary,
              compact: true,
              onPressed: () => Navigator.of(ctx).pop(const ReportsFilter()),
            ),
          ),
          const SizedBox(width: AppSpace.sm + 2),
          Expanded(
            flex: 2,
            child: ListenableBuilder(
              listenable: draft,
              builder: (_, _) => AppButton(
                label: 'Filter',
                icon: Icons.filter_alt_rounded,
                compact: true,
                onPressed: () => Navigator.of(ctx).pop(draft.value),
              ),
            ),
          ),
        ],
      ),
    );
    if (res != null) ref.read(reportsFilterProvider.notifier).set(res);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filter = ref.watch(reportsFilterProvider);
    final overview = ref.watch(reportOverviewProvider);
    final staff = ref.watch(reportStaffOptionsProvider).value ?? const [];

    return Scaffold(
      body: SafeArea(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reports',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          'Analyze revenue, appointments, staff performance, and sales',
                          maxLines: 2,
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  HeaderIconButton(
                    icon: Icons.tune_rounded,
                    label: 'Reports Filter',
                    count: filter.activeCount,
                    onTap: _openFilter,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppRefresh(
                onRefresh: () async {
                  ref.invalidate(reportOverviewProvider);
                  ref.invalidate(reportEarningProvider);
                  ref.invalidate(reportPaymentsProvider);
                  ref.invalidate(reportStaffProvider);
                  ref.invalidate(reportInvoicesProvider);
                  ref.invalidate(reportProductSalesProvider);
                  ref.invalidate(reportTopProductsProvider);
                },
                child: ListView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpace.xxl),
                  children: [
                    if (!filter.isClear)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.page,
                          0,
                          AppSpace.page,
                          AppSpace.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _filterText(filter, staff),
                                style: AppType.caption.copyWith(
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => ref
                                  .read(reportsFilterProvider.notifier)
                                  .set(const ReportsFilter()),
                              child: Text(
                                'Clear',
                                style: AppType.label.copyWith(
                                  color: t.accentText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      child: _Headline(
                        async: overview,
                        onRetry: () => ref.invalidate(reportOverviewProvider),
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    ChipsRow<_Tab>(
                      compact: true,
                      selected: _tab,
                      onChanged: (v) => setState(() => _tab = v),
                      options: const [
                        ChipOption(_Tab.earning, 'Earning'),
                        ChipOption(_Tab.payments, 'Payment Methods'),
                        ChipOption(_Tab.staff, 'Staff'),
                        ChipOption(_Tab.invoice, 'Invoice'),
                        ChipOption(_Tab.product, 'Product'),
                        ChipOption(_Tab.top, 'Top Selling Products'),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      child: _body(overview),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _filterText(ReportsFilter f, List<({int id, String name})> staff) {
    final parts = <String>[];
    if (f.start != null || f.end != null) {
      String d(String? s) =>
          s == null ? '…' : ShopTime.fullDate(ShopTime.parseDate(s));
      parts.add('${d(f.start)} – ${d(f.end)}');
    }
    if (f.staffId != null) {
      parts.add(
        staff.where((s) => s.id == f.staffId).firstOrNull?.name ?? 'Staff',
      );
    }
    return parts.join(' · ');
  }

  Widget _body(AsyncValue<ReportOverview> overview) {
    final t = context.tokens;
    switch (_tab) {
      case _Tab.earning:
        final o = overview.value;
        return Column(
          children: [
            if (o != null) _MiniCards(o: o),
            const SizedBox(height: AppSpace.md),
            PagedRows<EarningRow>(
              async: ref.watch(reportEarningProvider),
              empty: 'No completed appointments in this period.',
              builder: (r) => _EarningCard(r: r),
              onRetry: () => ref.invalidate(reportEarningProvider),
              onMore: () => ref.read(reportEarningProvider.notifier).loadMore(),
            ),
          ],
        );
      case _Tab.payments:
        return _Simple<PaymentRow>(
          title: 'Payment Method Analytics',
          async: ref.watch(reportPaymentsProvider),
          empty: 'No payments in this period.',
          onRetry: () => ref.invalidate(reportPaymentsProvider),
          builder: (r) => InfoBox(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.method,
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                ),
                Text(
                  r.revenue.format(),
                  style: AppType.bodyStrong.copyWith(color: t.accentText),
                ),
              ],
            ),
          ),
        );
      case _Tab.staff:
        return _Simple<StaffPerformanceRow>(
          title: 'Staff Performance',
          async: ref.watch(reportStaffProvider),
          empty: 'No staff earnings in this period.',
          onRetry: () => ref.invalidate(reportStaffProvider),
          builder: (r) => _StaffCard(r: r),
        );
      case _Tab.invoice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoices', style: AppType.subheading.copyWith(color: t.text)),
            const SizedBox(height: AppSpace.sm + 2),
            PagedRows<InvoiceReportRow>(
              async: ref.watch(reportInvoicesProvider),
              empty: 'No invoices in this period.',
              builder: (r) => _InvoiceCard(r: r),
              onRetry: () => ref.invalidate(reportInvoicesProvider),
              onMore: () =>
                  ref.read(reportInvoicesProvider.notifier).loadMore(),
            ),
          ],
        );
      case _Tab.product:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Product Sell History',
              style: AppType.subheading.copyWith(color: t.text),
            ),
            const SizedBox(height: AppSpace.sm + 2),
            PagedRows<ProductSaleRow>(
              async: ref.watch(reportProductSalesProvider),
              empty: 'No products sold in this period.',
              builder: (r) => _SaleCard(r: r),
              onRetry: () => ref.invalidate(reportProductSalesProvider),
              onMore: () =>
                  ref.read(reportProductSalesProvider.notifier).loadMore(),
            ),
          ],
        );
      case _Tab.top:
        return _TopProductsTab(async: ref.watch(reportTopProductsProvider));
    }
  }
}

/// Total Revenue, Total Appointment, Discount Amount, Total Tips.
class _Headline extends StatelessWidget {
  const _Headline({required this.async, required this.onRetry});

  final AsyncValue<ReportOverview> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final o = async.value;
    if (o == null) {
      return async.hasError
          ? ErrorState(
              message: async.error is Failure
                  ? (async.error! as Failure).userMessage
                  : 'Could not load the report.',
              onRetry: onRetry,
            )
          : const SkeletonLoader(child: SkeletonBox(height: 170, radius: 20));
    }
    Widget tile(
      String label,
      String value,
      IconData icon, {
      bool big = false,
    }) => Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: big ? t.accent.withValues(alpha: 0.5) : t.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: t.accentText),
          const SizedBox(height: 6),
          Text(value, style: AppType.title.copyWith(color: t.text)),
          Text(label, style: AppType.caption.copyWith(color: t.textSecondary)),
        ],
      ),
    );
    return TileGrid(
      children: [
        tile(
          'Total Revenue',
          o.revenue.format(),
          Icons.payments_rounded,
          big: true,
        ),
        tile(
          'Total Appointment',
          '${o.appointments}',
          Icons.event_available_rounded,
        ),
        tile('Discount Amount', o.discount.format(), Icons.sell_rounded),
        tile('Total Tips', o.tips.format(), Icons.volunteer_activism_rounded),
      ],
    );
  }
}

/// Earning tab: Total Earning, Product Commission, Service Commission, Tip.
class _MiniCards extends StatelessWidget {
  const _MiniCards({required this.o});

  final ReportOverview o;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget small(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppType.bodyStrong.copyWith(color: t.text)),
            Text(
              label,
              maxLines: 2,
              style: AppType.caption.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Earning',
                style: AppType.label.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                o.earning.format(),
                style: AppText.display(30, color: t.accentText),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm + 2),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              small('Product Commission', o.productCommission.format()),
              const SizedBox(width: AppSpace.sm + 2),
              small('Service Commission', o.serviceCommission.format()),
              const SizedBox(width: AppSpace.sm + 2),
              small('Tip', o.serviceTips.format()),
            ],
          ),
        ),
      ],
    );
  }
}

/// A non-paged tab: title and rows.
class _Simple<T> extends StatelessWidget {
  const _Simple({
    required this.title,
    required this.async,
    required this.empty,
    required this.onRetry,
    required this.builder,
  });

  final String title;
  final AsyncValue<List<T>> async;
  final String empty;
  final VoidCallback onRetry;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = async.value;
    Widget body;
    if (items == null) {
      body = async.hasError
          ? ErrorState(
              message: async.error is Failure
                  ? (async.error! as Failure).userMessage
                  : 'Could not load this tab.',
              onRetry: onRetry,
            )
          : const SkeletonRows(count: 4);
    } else if (items.isEmpty) {
      body = QuietState(title: 'Nothing here', message: empty);
    } else {
      body = Column(
        children: [
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
              child: builder(i),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppType.subheading.copyWith(color: t.text)),
        const SizedBox(height: AppSpace.sm + 2),
        body,
      ],
    );
  }
}

class _EarningCard extends StatelessWidget {
  const _EarningCard({required this.r});

  final EarningRow r;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.customerName.isEmpty ? '-' : r.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              const AppointmentStatusPill(
                AppointmentStatus.completed,
                compact: true,
              ),
            ],
          ),
          Text(
            '${ShopTime.fullDate(ShopTime.parseDate(r.date))} · ${r.startLabel} - ${r.endLabel}',
            style: AppType.caption.copyWith(color: t.textMuted),
          ),
          Divider(height: AppSpace.lg, color: t.border),
          KvLine('Sub Total', r.subTotal.format()),
          KvLine('Discount', r.discount.format()),
          KvLine('Total Tip', r.tip.format()),
          KvLine('Total Amount', r.total.format()),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.r});

  final StaffPerformanceRow r;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final card = InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name,
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              Text(
                r.totalEarning.format(),
                style: AppType.bodyStrong.copyWith(color: t.accentText),
              ),
            ],
          ),
          Divider(height: AppSpace.lg, color: t.border),
          KvLine('Appointments', '${r.appointments}'),
          KvLine('Tips', r.tips.format()),
          KvLine('Service Comm.', r.serviceCommission.format()),
          KvLine('Product Comm.', r.productCommission.format()),
        ],
      ),
    );
    return r.staffId == null
        ? card
        : Pressable(
            onTap: () => context.push('/app/staff/${r.staffId}'),
            scale: 0.99,
            minSize: 0,
            child: card,
          );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.r});

  final InvoiceReportRow r;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: () => context.push('/app/invoice/${r.id}'),
      scale: 0.99,
      minSize: 0,
      child: InfoBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.number,
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                ),
                StatusPill(label: 'Paid', color: t.success, compact: true),
              ],
            ),
            Text(
              '${r.customerName} · ${ShopTime.fullDate(ShopTime.parseDate(r.date))}',
              style: AppType.caption.copyWith(color: t.textSecondary),
            ),
            Text(
              r.staffNames,
              style: AppType.caption.copyWith(color: t.textMuted),
            ),
            Divider(height: AppSpace.lg, color: t.border),
            KvLine('Total', r.total.format()),
            // The web's "Amount": what the staff earned on it (commission + tips).
            KvLine('Staff earned', r.staffEarned.format()),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.r});

  final ProductSaleRow r;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.product,
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              Text(
                r.amount.format(),
                style: AppType.bodyStrong.copyWith(color: t.accentText),
              ),
            ],
          ),
          Text(
            'Sell By ${r.staff} · ${r.customer}',
            style: AppType.caption.copyWith(color: t.textSecondary),
          ),
          Text(
            ShopTime.fullDate(ShopTime.parseDate(r.date)),
            style: AppType.caption.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

class _TopProductsTab extends StatelessWidget {
  const _TopProductsTab({required this.async});

  final AsyncValue<TopProducts> async;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = async.value;
    if (d == null) {
      return async.hasError
          ? ErrorState(
              message: async.error is Failure
                  ? (async.error! as Failure).userMessage
                  : 'Could not load this tab.',
            )
          : const SkeletonRows(count: 4);
    }
    Widget card(String label, String value) => Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: AppType.title.copyWith(color: t.text)),
          Text(label, style: AppType.caption.copyWith(color: t.textSecondary)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Selling Products',
          style: AppType.subheading.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.sm + 2),
        TileGrid(
          children: [
            card('Total Product Amount', d.amount.format()),
            card('Total Discount Paid', d.discount.format()),
            card('Total Commission Paid', d.commission.format()),
            card('Total Revenue', d.revenue.format()),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        if (d.rows.isEmpty)
          const QuietState(
            title: 'Nothing here',
            message: 'No products sold in this period.',
          )
        else
          for (final r in d.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
              child: InfoBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                    Text(
                      r.price.format(),
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                    Divider(height: AppSpace.lg, color: t.border),
                    KvLine('Sell Unit', '${r.units}'),
                    KvLine('Total Discount Paid', r.discount.format()),
                    KvLine('Total Commission', r.commission.format()),
                    KvLine('Total Revenue', r.revenue.format()),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// The filter being edited in the sheet.
class _Draft extends ChangeNotifier {
  _Draft(this.value);

  ReportsFilter value;

  void set(ReportsFilter f) {
    value = f;
    notifyListeners();
  }
}

class _FilterBody extends StatelessWidget {
  const _FilterBody({required this.draft, required this.staff});

  final _Draft draft;
  final List<({int id, String name})> staff;

  Future<void> _pick(BuildContext context, {required bool start}) async {
    final f = draft.value;
    final cur = start ? f.start : f.end;
    final now = ShopTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: cur == null ? now : ShopTime.parseDate(cur),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    final ymd = ShopTime.ymd(picked);
    draft.set(start ? f.copyWith(start: ymd) : f.copyWith(end: ymd));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final f = draft.value;
        Widget dateField(String label, String? v, {required bool start}) =>
            Expanded(
              child: Pressable(
                onTap: () => _pick(context, start: start),
                minSize: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppType.caption.copyWith(color: t.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        v == null
                            ? 'Any'
                            : ShopTime.fullDate(ShopTime.parseDate(v)),
                        style: AppType.bodyStrong.copyWith(color: t.text),
                      ),
                    ],
                  ),
                ),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                dateField('Start Date', f.start, start: true),
                const SizedBox(width: AppSpace.sm + 2),
                dateField('End Date', f.end, start: false),
              ],
            ),
            if (staff.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Text(
                'Staff Name',
                style: AppType.label.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppChoiceChip(
                    label: 'All Staff',
                    selected: f.staffId == null,
                    onTap: () => draft.set(f.copyWith(staffId: null)),
                  ),
                  for (final s in staff)
                    AppChoiceChip(
                      label: s.name,
                      selected: f.staffId == s.id,
                      onTap: () => draft.set(f.copyWith(staffId: s.id)),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
