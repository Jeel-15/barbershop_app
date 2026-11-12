import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/me/presentation/widgets/earning_cards.dart';
import 'package:barbershop_app/features/staff/application/staff_controller.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:barbershop_app/features/staff/presentation/widgets/assign_services_sheet.dart';
import 'package:barbershop_app/features/staff/presentation/widgets/change_password_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/features/auth/domain/perm.dart';

enum _Tab { appointments, services, earnings }

/// The web's Staff Profile ("Track appointments, services, and earnings"):
/// the person, their numbers, and the tabs Appointments, Assign Services, Earnings.
class StaffProfilePage extends ConsumerStatefulWidget {
  const StaffProfilePage({super.key, required this.staffId});

  final int staffId;

  @override
  ConsumerState<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends ConsumerState<StaffProfilePage> {
  final _scroll = ScrollController();
  _Tab _tab = _Tab.appointments;
  StaffRange _range = const StaffRange();

  int get _id => widget.staffId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) {
        switch (_tab) {
          case _Tab.appointments:
            ref
                .read(staffAppointmentsProvider((_id, _range)).notifier)
                .loadMore();
          case _Tab.services:
            ref.read(staffServicesProvider(_id).notifier).loadMore();
          case _Tab.earnings:
            ref.read(staffEarningsProvider(_id).notifier).loadMore();
        }
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final cur = start ? _range.start : _range.end;
    final now = ShopTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: cur == null ? now : ShopTime.parseDate(cur),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    final ymd = ShopTime.ymd(picked);
    setState(
      () => _range = start
          ? StaffRange(start: ymd, end: _range.end)
          : StaffRange(start: _range.start, end: ymd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final async = ref.watch(staffProfileProvider(_id));
    final p = async.value;
    final canEdit = user.can(Perm.staffEdit);
    // Access can change while this page is open: never stay on a tab that is gone.
    if (_tab == _Tab.services && !user.canSeeStaffServices) {
      _tab = _Tab.appointments;
    }

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
                        : context.go('/app/staff'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff Profile',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          'Track appointments, services, and earnings',
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (p != null && canEdit)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: Icon(Icons.more_vert_rounded, color: t.text),
                      color: t.surfaceRaised,
                      onSelected: (v) async {
                        switch (v) {
                          case 'edit':
                            final msg = await context.push<String>(
                              '/app/staff/edit/$_id',
                              extra: p.staff,
                            );
                            if (msg != null && context.mounted) {
                              showToast(context, msg, kind: ToastKind.success);
                              ref.invalidate(staffProfileProvider(_id));
                              ref.invalidate(staffListProvider);
                            }
                          case 'password':
                            await showChangePasswordSheet(context, p.staff);
                          case 'assign':
                            final saved = await showAssignServicesSheet(
                              context,
                              p.staff,
                            );
                            if (saved == true) {
                              ref.invalidate(staffListProvider);
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        if (p.staff.isBarber)
                          const PopupMenuItem(
                            value: 'assign',
                            child: Text('Assign Services'),
                          ),
                        const PopupMenuItem(
                          value: 'password',
                          child: Text('Change Password'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (async) {
                AsyncError(:final error) when p == null => ErrorState(
                  message: error is Failure
                      ? error.userMessage
                      : 'Could not load this profile.',
                  supportCode: error is Failure ? error.requestId : null,
                  onRetry: () => ref.invalidate(staffProfileProvider(_id)),
                ),
                _ when p == null => const Padding(
                  padding: EdgeInsets.all(AppSpace.page),
                  child: SkeletonLoader(
                    child: Column(
                      children: [
                        SkeletonBox(height: 170, radius: 20),
                        SizedBox(height: AppSpace.md),
                        SkeletonBox(height: 100, radius: 16),
                      ],
                    ),
                  ),
                ),
                _ => ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.sm,
                    AppSpace.page,
                    AppSpace.xxl,
                  ),
                  children: [
                    _Hero(p: p),
                    const SizedBox(height: AppSpace.lg),
                    _Cards(s: p.summary),
                    const SizedBox(height: AppSpace.xl),
                    ChipsRow<_Tab>(
                      compact: true,
                      padding: EdgeInsets.zero,
                      selected: _tab,
                      onChanged: (v) => setState(() => _tab = v),
                      options: [
                        const ChipOption(_Tab.appointments, 'Appointments'),
                        // The server lists a member's services only to Staff-Add/Edit/Delete.
                        if (user.canSeeStaffServices)
                          const ChipOption(_Tab.services, 'Assign Services'),
                        const ChipOption(_Tab.earnings, 'Earnings'),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    ..._tabBody(),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _tabBody() => switch (_tab) {
    _Tab.appointments => [
      Row(
        children: [
          _DateBox(
            label: 'Start Date:',
            value: _range.start,
            onTap: () => _pickDate(start: true),
          ),
          const SizedBox(width: AppSpace.sm + 2),
          _DateBox(
            label: 'End Date:',
            value: _range.end,
            onTap: () => _pickDate(start: false),
          ),
        ],
      ),
      if (!_range.isClear)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _range = const StaffRange()),
            child: Text(
              'Clear',
              style: AppType.label.copyWith(color: context.tokens.accentText),
            ),
          ),
        ),
      const SizedBox(height: AppSpace.sm),
      PagedRows<StaffAppointment>(
        async: ref.watch(staffAppointmentsProvider((_id, _range))),
        empty: 'No appointments for this period.',
        builder: (a) => _AppointmentCard(a: a),
        onRetry: () => ref.invalidate(staffAppointmentsProvider((_id, _range))),
        onMore: () => ref
            .read(staffAppointmentsProvider((_id, _range)).notifier)
            .loadMore(),
      ),
    ],
    _Tab.services => [
      PagedRows(
        async: ref.watch(staffServicesProvider(_id)),
        empty: 'No services done yet.',
        builder: (s) => ServiceEarningCard(s: s),
        onRetry: () => ref.invalidate(staffServicesProvider(_id)),
        onMore: () => ref.read(staffServicesProvider(_id).notifier).loadMore(),
      ),
    ],
    _Tab.earnings => [
      PagedRows(
        async: ref.watch(staffEarningsProvider(_id)),
        empty: 'No earnings yet.',
        builder: (d) => DailyEarningCard(d: d),
        onRetry: () => ref.invalidate(staffEarningsProvider(_id)),
        onMore: () => ref.read(staffEarningsProvider(_id).notifier).loadMore(),
      ),
    ],
  };
}

class _Hero extends StatelessWidget {
  const _Hero({required this.p});

  final StaffProfile p;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = p.staff;
    final since = m.createdAt == null
        ? null
        : ShopTime.fullDate(ShopTime.parseDate(m.createdAt!));
    Widget line(IconData icon, String label, String value) => Padding(
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
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          AppAvatar(name: m.name, imageUrl: m.photoUrl, size: 76, ring: true),
          const SizedBox(height: AppSpace.md),
          Text(m.name, style: AppType.title.copyWith(color: t.text)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              StatusPill(label: m.roleLabel, color: t.accent, compact: true),
              StatusPill(
                label: m.active ? 'Active' : 'Deactive',
                color: m.active ? t.success : t.danger,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          line(Icons.mail_outline_rounded, 'Email', m.email),
          if (m.hasPhone) line(Icons.call_outlined, 'Phone', m.phone!),
          if (since != null)
            line(Icons.calendar_today_rounded, 'Staff since', since),
          Divider(height: AppSpace.xl, color: t.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${p.summary.visits}',
                style: AppType.title.copyWith(color: t.text),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                'Total Visits',
                style: AppType.body.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.s});

  final StaffSummary s;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget tile(String label, String value) => Container(
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
        TileGrid(
          children: [
            tile('Complete Services', '${s.appointments}'),
            tile('Total Earn Tip', s.tips.format()),
            tile('Total Product Commission', s.productCommission.format()),
            tile('Total Service Commission', s.serviceCommission.format()),
          ],
        ),
      ],
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Expanded(
      child: Pressable(
        onTap: onTap,
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
                value == null
                    ? 'Any'
                    : ShopTime.fullDate(ShopTime.parseDate(value!)),
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.a});

  final StaffAppointment a;

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
          if (a.staffNames.isNotEmpty) KvLine('Assign To', a.staffNames),
        ],
      ),
    );
  }
}
