import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/presentation/appointment_sheet.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/break_sheet.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/calendar_legend.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Filter by Staff" (All Staff or one barber) and the order of the columns
/// (the web lets you drag a column header; here the rows are dragged).
Future<void> showStaffSheet(BuildContext context, List<CalendarLane> lanes) =>
    showAppSheet<void>(
      context,
      title: 'Staff',
      builder: (ctx) => _StaffSheet(lanes: lanes),
    );

class _StaffSheet extends ConsumerWidget {
  const _StaffSheet({required this.lanes});

  final List<CalendarLane> lanes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final current = ref.watch(calendarStaffFilterProvider);
    final order = ref.watch(calendarOrderProvider);
    final ordered = orderLanes(lanes, order);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter by Staff',
          style: AppType.label.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppChoiceChip(
              label: 'All Staff',
              selected: current == null,
              onTap: () {
                ref.read(calendarStaffFilterProvider.notifier).set(null);
                Navigator.of(context).pop();
              },
            ),
            for (final l in ordered)
              AppChoiceChip(
                label: l.name,
                selected: current == l.id,
                onTap: () {
                  ref.read(calendarStaffFilterProvider.notifier).set(l.id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        if (ordered.length > 1) ...[
          const SizedBox(height: AppSpace.xl),
          Text(
            'Column order',
            style: AppType.label.copyWith(color: t.textSecondary),
          ),
          Text(
            'Hold the handle and drag a barber up or down.',
            style: AppType.caption.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final ids = [for (final l in ordered) l.id];
              ids.insert(to, ids.removeAt(from));
              ref.read(calendarOrderProvider.notifier).set(ids);
            },
            children: [
              for (var i = 0; i < ordered.length; i++)
                Container(
                  key: ValueKey(ordered[i].id),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    children: [
                      AppAvatar(
                        name: ordered[i].name,
                        imageUrl: ordered[i].photoUrl,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ordered[i].name,
                          style: AppType.bodyStrong.copyWith(color: t.text),
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: t.textSecondary,
                            semanticLabel: 'Move ${ordered[i].name}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Calendar tab: day view with one column per barber (same data and rules as
/// the web's Staff Calendar).
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  /// Statuses kept bright by the legend (empty = all).
  Set<int> _focus = {};

  Future<void> _pickDate(DateTime current) async {
    final today = ShopTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    ref.read(calendarDateProvider.notifier).select(picked);
    await ref.read(calendarProvider.notifier).ensure(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final date = ref.watch(calendarDateProvider);
    final window = ref.watch(calendarProvider);
    final isToday = ShopTime.isSameDay(date, ShopTime.today());
    final pad = AppNavBar.reservedHeight(context);

    void pick(DateTime d) {
      ref.read(calendarDateProvider.notifier).select(d);
      ref.read(calendarProvider.notifier).ensure(d);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TabHeader(
              eyebrow: ShopTime.weekdayLong(date),
              title: ShopTime.relativeDay(date) == 'Today'
                  ? 'Today'
                  : ShopTime.dayLabel(date),
              // Tap the date to jump to any day.
              onTitleTap: () => _pickDate(date),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isToday)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.sm),
                      child: _HeaderPill(
                        label: 'Today',
                        onTap: () => pick(ShopTime.today()),
                      ),
                    ),
                  // Admin: one barber or All Staff, and the column order.
                  if ((window.value?.lanes.length ?? 0) > 1) ...[
                    HeaderIconButton(
                      icon: Icons.groups_rounded,
                      label: 'Filter by Staff',
                      count: ref.watch(calendarStaffFilterProvider) == null
                          ? 0
                          : 1,
                      onTap: () => showStaffSheet(context, window.value!.lanes),
                    ),
                    const SizedBox(width: AppSpace.sm),
                  ],
                  HeaderIconButton(
                    icon: Icons.add_rounded,
                    label: 'Add Appointment',
                    onTap: () => context.push(
                      '/app/appointment/new?date=${ShopTime.ymd(date)}',
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  HeaderIconButton(
                    icon: Icons.coffee_rounded,
                    label: 'Add Break',
                    onTap: () {
                      final lanes = window.value?.lanes ?? const [];
                      if (lanes.isNotEmpty) showBreakSheet(context, lanes);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            DateStrip(
              selected: date,
              onSelected: pick,
              markers: window.value?.busyDays ?? const {},
              futureDays: 45,
            ),
            const SizedBox(height: AppSpace.sm),
            if (window.value != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: CalendarLegend(
                        counts: DayCounts.of(
                          window.value!.day(
                            date,
                            DayAvailability.fallback(),
                            onlyStaffId: ref.watch(calendarStaffFilterProvider),
                          ),
                        ),
                        focus: _focus,
                        onFocus: (f) => setState(() => _focus = f),
                      ),
                    ),
                    // Zoom the hours: the same as pinching, for one finger.
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.sm),
                      child: HeaderIconButton(
                        icon: Icons.zoom_in_rounded,
                        label: 'Zoom the day',
                        onTap: () =>
                            ref.read(calendarZoomProvider.notifier).step(),
                      ),
                    ),
                    // The whole day on one wide screen: turns the phone sideways.
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.page),
                      child: HeaderIconButton(
                        icon: Icons.fullscreen_rounded,
                        label: 'Landscape view',
                        onTap: () => context.push('/app/calendar/landscape'),
                      ),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: switch (window) {
                AsyncData(:final value) => _Day(
                  window: value,
                  date: date,
                  bottomPadding: pad,
                  focus: _focus,
                ),
                AsyncError(:final error) when window.value == null =>
                  ErrorState(
                    message: error is Failure
                        ? error.userMessage
                        : 'Could not load the calendar.',
                    supportCode: error is Failure ? error.requestId : null,
                    onRetry: () => ref.invalidate(calendarProvider),
                  ),
                _ when window.value != null => _Day(
                  window: window.value!,
                  date: date,
                  bottomPadding: pad,
                  focus: _focus,
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(AppSpace.page),
                  child: SkeletonLoader(
                    child: Column(
                      children: [
                        SkeletonBox(height: 56, radius: 14),
                        SizedBox(height: AppSpace.md),
                        SkeletonBox(height: 300, radius: 14),
                      ],
                    ),
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Day extends ConsumerWidget {
  const _Day({
    required this.window,
    required this.date,
    required this.bottomPadding,
    required this.focus,
  });

  final CalendarWindow window;
  final DateTime date;
  final double bottomPadding;
  final Set<int> focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final avail = ref.watch(dayAvailabilityProvider(ShopTime.ymd(date))).value;
    final only = ref.watch(calendarStaffFilterProvider);
    final day = window.day(
      date,
      avail ?? DayAvailability.fallback(),
      onlyStaffId: only,
      order: ref.watch(calendarOrderProvider),
    );
    return Column(
      children: [
        if (day.availability.shopDayOff)
          Container(
            width: double.infinity,
            color: t.warning.withValues(alpha: 0.14),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.page,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.event_busy_rounded, size: 18, color: t.warning),
                const SizedBox(width: 8),
                Text(
                  'The shop is closed on this day.',
                  style: AppType.label.copyWith(color: t.text),
                ),
              ],
            ),
          ),
        Expanded(
          child: AppRefresh(
            onRefresh: () => ref.read(calendarProvider.notifier).refresh(),
            child: DayGrid(
              day: day,
              date: date,
              focus: focus,
              bottomPadding: bottomPadding,
              zoom: ref.watch(calendarZoomProvider),
              onZoom: (px) => ref.read(calendarZoomProvider.notifier).set(px),
              showHint: ref.watch(calendarZoomHintProvider),
              onHintSeen: () =>
                  ref.read(calendarZoomHintProvider.notifier).dismiss(),
              onLaneLongPress: (_) => showStaffSheet(context, window.lanes),
              onBlocked: (why, lane, minutes) => showToast(
                context,
                slotBlockedMessage(why, lane, minutes),
                kind: ToastKind.info,
              ),
              onSlotTap: (laneId, minutes) {
                final h = (minutes ~/ 60).toString().padLeft(2, '0');
                final m = (minutes % 60).toString().padLeft(2, '0');
                context.push(
                  '/app/appointment/new?staff=$laneId&date=${ShopTime.ymd(date)}&time=$h:$m',
                );
              },
              onEventTap: (e) {
                if (e.appointmentId == null) return;
                showAppointmentSheet(
                  context,
                  laneStaffId: e.laneId,
                  row: e.toAppointmentRow(
                    ref.read(bootstrapProvider).actionsFor(e.status.code),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onTap,
      minSize: 0,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppType.label.copyWith(color: t.text, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
