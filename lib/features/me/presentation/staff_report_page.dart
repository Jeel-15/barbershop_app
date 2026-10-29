import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/me/application/report_controller.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:barbershop_app/features/me/presentation/widgets/earning_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _Tab { appointments, services, daily }

/// The web's Staff Report: the earning cards, the Reports Filter (Start Date,
/// End Date, Status) and the three tabs Appointments, Service Earning and
/// Daily Earning. A staff member sees their own numbers only.
class StaffReportPage extends ConsumerStatefulWidget {
  const StaffReportPage({super.key});

  @override
  ConsumerState<StaffReportPage> createState() => _StaffReportPageState();
}

class _StaffReportPageState extends ConsumerState<StaffReportPage> {
  final _scroll = ScrollController();
  _Tab _tab = _Tab.appointments;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) {
        switch (_tab) {
          case _Tab.appointments:
            ref.read(reportAppointmentsProvider.notifier).loadMore();
          case _Tab.services:
            ref.read(reportServicesProvider.notifier).loadMore();
          case _Tab.daily:
            ref.read(reportDaysProvider.notifier).loadMore();
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
    final current = ref.read(reportFilterProvider);
    final ctl = _FilterDraft(current);
    final res = await showAppSheet<ReportFilter>(
      context,
      title: 'Reports Filter',
      builder: (_) => _FilterBody(draft: ctl),
      footer: (ctx) => ListenableBuilder(
        listenable: ctl,
        builder: (_, _) => Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Clear',
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => Navigator.of(ctx).pop(const ReportFilter()),
              ),
            ),
            const SizedBox(width: AppSpace.sm + 2),
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'Filter',
                icon: Icons.filter_alt_rounded,
                compact: true,
                onPressed: () => Navigator.of(ctx).pop(ctl.value),
              ),
            ),
          ],
        ),
      ),
    );
    if (res != null) ref.read(reportFilterProvider.notifier).set(res);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filter = ref.watch(reportFilterProvider);
    final summary = ref.watch(reportSummaryProvider);

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
                    child: Text(
                      'Staff Report',
                      style: AppType.heading.copyWith(color: t.text),
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
                  ref.invalidate(reportSummaryProvider);
                  ref.invalidate(reportAppointmentsProvider);
                  ref.invalidate(reportServicesProvider);
                  ref.invalidate(reportDaysProvider);
                },
                child: ListView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpace.xxl),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      child: _Cards(
                        summary: summary,
                        onRetry: () {
                          ref.invalidate(reportSummaryProvider);
                        },
                      ),
                    ),
                    if (!filter.isClear)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.page,
                          AppSpace.sm,
                          AppSpace.page,
                          0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _filterText(filter),
                                style: AppType.caption.copyWith(
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => ref
                                  .read(reportFilterProvider.notifier)
                                  .set(const ReportFilter()),
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
                    const SizedBox(height: AppSpace.lg),
                    ChipsRow<_Tab>(
                      compact: true,
                      selected: _tab,
                      onChanged: (v) => setState(() => _tab = v),
                      options: const [
                        ChipOption(_Tab.appointments, 'Appointments'),
                        ChipOption(_Tab.services, 'Service Earning'),
                        ChipOption(_Tab.daily, 'Daily Earning'),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      child: switch (_tab) {
                        _Tab.appointments => PagedRows<ReportAppointment>(
                          async: ref.watch(reportAppointmentsProvider),
                          empty: 'No appointments in this period.',
                          builder: (a) => _AppointmentCard(a: a),
                          onRetry: () =>
                              ref.invalidate(reportAppointmentsProvider),
                          onMore: () => ref
                              .read(reportAppointmentsProvider.notifier)
                              .loadMore(),
                        ),
                        _Tab.services => PagedRows<ServiceEarning>(
                          async: ref.watch(reportServicesProvider),
                          empty: 'No service earnings yet.',
                          builder: (s) => ServiceEarningCard(s: s),
                          onRetry: () => ref.invalidate(reportServicesProvider),
                          onMore: () => ref
                              .read(reportServicesProvider.notifier)
                              .loadMore(),
                        ),
                        _Tab.daily => PagedRows<DailyEarning>(
                          async: ref.watch(reportDaysProvider),
                          empty: 'No daily earnings yet.',
                          builder: (d) => DailyEarningCard(d: d),
                          onRetry: () => ref.invalidate(reportDaysProvider),
                          onMore: () =>
                              ref.read(reportDaysProvider.notifier).loadMore(),
                        ),
                      },
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

  String _filterText(ReportFilter f) {
    final parts = <String>[];
    if (f.start != null || f.end != null) {
      String d(String? s) =>
          s == null ? '…' : ShopTime.fullDate(ShopTime.parseDate(s));
      parts.add('${d(f.start)} – ${d(f.end)}');
    }
    if (f.status != null) parts.add(_statusName(f.status!));
    return parts.join(' · ');
  }
}

/// The web's status names for the Status dropdown.
String _statusName(int code) => switch (code) {
  0 => 'Pending',
  1 => 'Completed',
  2 => 'Cancel',
  3 => 'Confirm',
  4 => 'Reschedule',
  _ => 'Unknown',
};

class _Cards extends StatelessWidget {
  const _Cards({required this.summary, required this.onRetry});

  final AsyncValue<ReportSummary> summary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = summary.value;
    if (s == null) {
      if (summary.hasError) {
        return ErrorState(
          message: summary.error is Failure
              ? (summary.error! as Failure).userMessage
              : 'Could not load your earnings.',
          onRetry: onRetry,
        );
      }
      return const SkeletonLoader(child: SkeletonBox(height: 190, radius: 20));
    }
    Widget small(String label, String value, IconData icon) => Expanded(
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
            Icon(icon, size: 18, color: t.accentText),
            const SizedBox(height: 8),
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
            border: Border.all(color: t.accent.withValues(alpha: 0.5)),
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
                s.totalEarning.format(),
                style: AppText.display(34, color: t.accentText),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm + 2),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              small(
                'Product Commission',
                s.productCommission.format(),
                Icons.inventory_2_rounded,
              ),
              const SizedBox(width: AppSpace.sm + 2),
              small(
                'Service Commission',
                s.serviceCommission.format(),
                Icons.content_cut_rounded,
              ),
              const SizedBox(width: AppSpace.sm + 2),
              small('Tip', s.tips.format(), Icons.volunteer_activism_rounded),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.a});

  final ReportAppointment a;

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
                  a.customerName.isEmpty ? '-' : a.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              AppointmentStatusPill(a.status, compact: true),
            ],
          ),
          if ((a.customerPhone ?? '').isNotEmpty)
            Text(
              a.customerPhone!,
              style: AppType.caption.copyWith(color: t.textSecondary),
            ),
          Text(
            '${ShopTime.fullDate(ShopTime.parseDate(a.date))} · ${a.startLabel} - ${a.endLabel}',
            style: AppType.caption.copyWith(color: t.textMuted),
          ),
          Divider(height: AppSpace.lg, color: t.border),
          KvLine('Discount', a.discount.format()),
          KvLine('Total Tip', a.tip.format()),
          KvLine('Total Amount', a.total.format()),
        ],
      ),
    );
  }
}

/// The filter being edited in the sheet.
class _FilterDraft extends ChangeNotifier {
  _FilterDraft(ReportFilter f) : value = f;

  ReportFilter value;

  void set(ReportFilter f) {
    value = f;
    notifyListeners();
  }
}

class _FilterBody extends StatelessWidget {
  const _FilterBody({required this.draft});

  final _FilterDraft draft;

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.md,
                  ),
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
            const SizedBox(height: AppSpace.lg),
            Text(
              'Status',
              style: AppType.label.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChoiceChip(
                  label: 'All',
                  selected: f.status == null,
                  onTap: () => draft.set(f.copyWith(status: null)),
                ),
                // The web's order and words.
                for (final c in const [0, 3, 2, 1, 4])
                  AppChoiceChip(
                    label: _statusName(c),
                    selected: f.status == c,
                    onTap: () => draft.set(f.copyWith(status: c)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
