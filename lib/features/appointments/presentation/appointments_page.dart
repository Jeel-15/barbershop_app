import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/debouncer.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/appointments_controller.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/presentation/appointment_sheet.dart';
import 'package:barbershop_app/features/appointments/presentation/widgets/appointment_tile.dart';
import 'package:barbershop_app/features/appointments/presentation/widgets/filter_sheet.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bookings tab: the web's Appointments page. Status tabs with live counts,
/// search by name / phone / barber, the filter sheet, grouped by day.
class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends ConsumerState<AppointmentsPage> {
  final _scroll = ScrollController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(appointmentListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Opens or closes the search box; closing clears the search.
  void _toggleSearch() {
    if (_searching) {
      final f = ref.read(appointmentFilterProvider);
      if (f.query.isNotEmpty) _setFilter(f.copyWith(query: ''));
    }
    setState(() => _searching = !_searching);
  }

  void _setFilter(AppointmentFilter f) =>
      ref.read(appointmentFilterProvider.notifier).set(f);

  Future<void> _openFilters() async {
    final user = ref.read(currentUserProvider);
    final lanes = user.isStaff
        ? <CalendarLane>[]
        : (ref.read(calendarProvider).value?.lanes ?? <CalendarLane>[]);
    final res = await showAppointmentFilterSheet(
      context,
      current: ref.read(appointmentFilterProvider),
      barbers: lanes,
    );
    if (res != null) _setFilter(res);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filter = ref.watch(appointmentFilterProvider);
    final list = ref.watch(appointmentListProvider);
    final counts = ref.watch(appointmentCountsProvider).value;
    final pad = AppNavBar.reservedHeight(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TabHeader(
              title: 'Appointments',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeaderIconButton(
                    icon: _searching
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                    label: 'Search',
                    active: _searching || filter.query.isNotEmpty,
                    onTap: _toggleSearch,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  HeaderIconButton(
                    icon: Icons.tune_rounded,
                    label: 'Filter',
                    count: filter.activeCount,
                    onTap: _openFilters,
                  ),
                ],
              ),
            ),
            // The search box only takes room when it is opened.
            AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: _searching
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.page,
                        AppSpace.md,
                        AppSpace.page,
                        0,
                      ),
                      child: _SearchBox(
                        initial: filter.query,
                        onChanged: (q) => _setFilter(filter.copyWith(query: q)),
                        onClose: _toggleSearch,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpace.md),
            ChipsRow<AppointmentStatus?>(
              compact: true,
              selected: filter.status,
              onChanged: (s) => _setFilter(filter.copyWith(status: s)),
              options: [
                ChipOption(null, 'All', count: counts?.all),
                for (final s in const [
                  AppointmentStatus.pending,
                  AppointmentStatus.confirmed,
                  AppointmentStatus.rescheduled,
                  AppointmentStatus.completed,
                  AppointmentStatus.cancelled,
                ])
                  ChipOption(s, s.filterLabel, count: counts?.forStatus(s)),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            if (filter.activeCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  0,
                  AppSpace.page,
                  AppSpace.xs,
                ),
                child: Row(
                  children: [
                    Text(
                      '${filter.activeCount} ${filter.activeCount == 1 ? 'filter' : 'filters'} on',
                      style: AppType.caption.copyWith(color: t.textSecondary),
                    ),
                    TextButton(
                      onPressed: () => _setFilter(
                        filter.copyWith(
                          startDate: null,
                          endDate: null,
                          dayType: null,
                          staffId: null,
                        ),
                      ),
                      child: Text(
                        'Clear',
                        style: AppType.label.copyWith(color: t.accentText),
                      ),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: AppRefresh(
                onRefresh: () =>
                    ref.read(appointmentListProvider.notifier).refresh(),
                child: switch (list) {
                  AsyncData(:final value) => _List(
                    state: value,
                    controller: _scroll,
                    bottom: pad,
                    onOpen: (a) => showAppointmentSheet(context, row: a),
                    onRetryMore: () =>
                        ref.read(appointmentListProvider.notifier).loadMore(),
                  ),
                  AsyncError(:final error) when list.value == null =>
                    _Scrollable(
                      child: ErrorState(
                        message: error is Failure
                            ? error.userMessage
                            : 'Could not load bookings.',
                        supportCode: error is Failure ? error.requestId : null,
                        onRetry: () => ref.invalidate(appointmentListProvider),
                      ),
                    ),
                  _ when list.value != null => _List(
                    state: list.value!,
                    controller: _scroll,
                    bottom: pad,
                    onOpen: (a) => showAppointmentSheet(context, row: a),
                    onRetryMore: () =>
                        ref.read(appointmentListProvider.notifier).loadMore(),
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
    required this.bottom,
    required this.onOpen,
    required this.onRetryMore,
  });

  final AppointmentListState state;
  final ScrollController controller;
  final double bottom;
  final ValueChanged<AppointmentRow> onOpen;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (state.items.isEmpty) {
      return const _Scrollable(
        child: QuietState(
          title: 'No bookings found',
          message: 'Try another status or clear the filters.',
        ),
      );
    }
    // Day headers between rows of different dates.
    final rows = <Object>[];
    String? last;
    for (final a in state.items) {
      if (a.date != last) {
        rows.add(a.date);
        last = a.date;
      }
      rows.add(a);
    }
    return EntranceHost(
      // A new filter or new first booking plays the entrance again.
      resetKey: state.items.first.id,
      child: ListView.builder(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          AppSpace.md,
          AppSpace.page,
          bottom,
        ),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == rows.length) {
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
            return const SizedBox(height: AppSpace.sm);
          }
          final row = rows[i];
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.only(
                top: AppSpace.md,
                bottom: AppSpace.sm,
              ),
              child: Text(
                ShopTime.relativeDay(ShopTime.parseDate(row)).toUpperCase(),
                style: AppType.overline.copyWith(color: t.textMuted),
              ),
            );
          }
          final a = row as AppointmentRow;
          return StaggerIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
              child: AppointmentTile(row: a, onTap: () => onOpen(a)),
            ),
          );
        },
      ),
    );
  }
}

/// The search field that slides open under the header.
class _SearchBox extends StatefulWidget {
  const _SearchBox({
    required this.initial,
    required this.onChanged,
    required this.onClose,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final _c = TextEditingController(text: widget.initial);
  final _debounce = Debouncer();

  @override
  void dispose() {
    _debounce.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: t.accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: t.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _c,
              autofocus: true,
              textInputAction: TextInputAction.search,
              cursorColor: t.accent,
              style: AppType.body.copyWith(color: t.text),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: AppType.body.copyWith(color: t.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (q) => _debounce.run(() => widget.onChanged(q)),
            ),
          ),
          IconButton(
            tooltip: 'Close search',
            icon: Icon(Icons.close_rounded, size: 20, color: t.textSecondary),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}
