import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
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

/// The web's Customer Profile ("View visit history and pending appointments"):
/// who they are, Total Visits, and every appointment with date, time, staff and status.
class CustomerProfilePage extends ConsumerStatefulWidget {
  const CustomerProfilePage({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<CustomerProfilePage> createState() =>
      _CustomerProfilePageState();
}

class _CustomerProfilePageState extends ConsumerState<CustomerProfilePage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) {
        ref
            .read(customerAppointmentsProvider(widget.customerId).notifier)
            .loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _edit(CustomerSummary c) async {
    final saved = await showCustomerFormSheet(context, editing: c);
    if (saved == null || !mounted) return;
    showToast(
      context,
      'Customer updated successfully.',
      kind: ToastKind.success,
    );
    ref.invalidate(customerSummaryProvider(widget.customerId));
    ref.invalidate(customerListProvider);
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
      ref.invalidate(customerListProvider);
      if (!mounted) return;
      showToast(
        context,
        'Customer deleted successfully.',
        kind: ToastKind.success,
      );
      context.canPop() ? context.pop() : context.go('/app/customers');
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final summary = ref.watch(customerSummaryProvider(widget.customerId));
    final appts = ref.watch(customerAppointmentsProvider(widget.customerId));
    final c = summary.value;
    final canEdit = user.can(Perm.customerEdit);
    final canDelete = user.can(Perm.customerDelete);

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
                        : context.go('/app/customers'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      'Customer Profile',
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                  if (c != null && (canEdit || canDelete))
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: Icon(Icons.more_vert_rounded, color: t.text),
                      color: t.surfaceRaised,
                      onSelected: (v) => v == 'edit' ? _edit(c) : _delete(c),
                      itemBuilder: (_) => [
                        if (canEdit)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                        if (canDelete)
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete',
                              style: TextStyle(color: t.danger),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (summary) {
                AsyncError(:final error) when c == null => ErrorState(
                  message: error is Failure
                      ? error.userMessage
                      : 'Could not load this customer.',
                  supportCode: error is Failure ? error.requestId : null,
                  onRetry: () => ref.invalidate(
                    customerSummaryProvider(widget.customerId),
                  ),
                ),
                _ when c == null => const Padding(
                  padding: EdgeInsets.all(AppSpace.page),
                  child: SkeletonLoader(
                    child: Column(
                      children: [
                        SkeletonBox(height: 170, radius: 20),
                        SizedBox(height: AppSpace.md),
                        SkeletonBox(height: 90, radius: 16),
                      ],
                    ),
                  ),
                ),
                _ => AppRefresh(
                  onRefresh: () async {
                    ref.invalidate(customerSummaryProvider(widget.customerId));
                    ref.invalidate(
                      customerAppointmentsProvider(widget.customerId),
                    );
                  },
                  child: ListView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.page,
                      AppSpace.sm,
                      AppSpace.page,
                      AppSpace.xxl,
                    ),
                    children: [
                      _Hero(customer: c),
                      const SizedBox(height: AppSpace.lg),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              icon: Icons.content_cut_rounded,
                              label: 'Total Visits',
                              value: c.totalVisits,
                              color: t.success,
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: StatTile(
                              icon: Icons.event_note_rounded,
                              label: 'Appointments',
                              value: c.appointmentsTotal,
                              color: t.info,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xl),
                      Text(
                        'APPOINTMENTS',
                        style: AppType.overline.copyWith(color: t.textMuted),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      ..._appointments(appts),
                    ],
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _appointments(AsyncValue<CustomerAppointmentsState> appts) {
    final s = appts.value;
    if (s == null) {
      if (appts.hasError) {
        return [
          ErrorState(
            message: 'Could not load appointments.',
            onRetry: () =>
                ref.invalidate(customerAppointmentsProvider(widget.customerId)),
          ),
        ];
      }
      return const [SkeletonRows(count: 3)];
    }
    if (s.items.isEmpty) {
      return const [
        QuietState(
          title: 'No appointments yet',
          message: 'Their bookings will be listed here.',
        ),
      ];
    }
    return [
      for (final a in s.items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
          child: _AppointmentRow(appointment: a),
        ),
      if (s.loadingMore)
        const Padding(
          padding: EdgeInsets.all(AppSpace.lg),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = customer;
    final since = c.memberSince == null
        ? null
        : ShopTime.fullDate(ShopTime.parseDate(c.memberSince!));
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          AppAvatar(name: c.name, size: 76, ring: true),
          const SizedBox(height: AppSpace.md),
          Text(
            c.name,
            textAlign: TextAlign.center,
            style: AppType.title.copyWith(color: t.text),
          ),
          if (!c.isActive) ...[
            const SizedBox(height: 6),
            StatusPill(label: 'Inactive', color: t.danger, compact: true),
          ],
          const SizedBox(height: AppSpace.md),
          if (c.hasPhone) _Line(Icons.call_outlined, 'Phone', c.phone!),
          if (c.hasEmail) _Line(Icons.mail_outline_rounded, 'Email', c.email!),
          if (since != null)
            _Line(Icons.calendar_today_rounded, 'Member since', since),
          if (c.hasPhone) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Call',
                    icon: Icons.call_rounded,
                    compact: true,
                    onPressed: () => callCustomer(context, c.phone),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: AppButton(
                    label: 'Message',
                    icon: Icons.sms_rounded,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    onPressed: () => messageCustomer(context, c.phone),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                HeaderIconButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy number',
                  onTap: () => copyPhone(context, c.phone),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.textMuted),
          const SizedBox(width: AppSpace.sm),
          Text('$label: ', style: AppType.caption.copyWith(color: t.textMuted)),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.appointment});

  final CustomerAppointment appointment;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = appointment;
    final day = ShopTime.parseDate(a.date);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: t.statusColor(a.status),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ShopTime.fullDate(day),
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                  Text(
                    '${a.startLabel} - ${a.endLabel}',
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  if (a.staffNames.isNotEmpty)
                    Text(
                      a.staffNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: t.textMuted),
                    ),
                ],
              ),
            ),
            AppointmentStatusPill(a.status, compact: true),
          ],
        ),
      ),
    );
  }
}
