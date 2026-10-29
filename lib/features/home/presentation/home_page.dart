import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/appointments_controller.dart';
import 'package:barbershop_app/features/appointments/presentation/appointment_sheet.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/domain/auth_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:barbershop_app/features/home/presentation/widgets/home_bookings.dart';
import 'package:barbershop_app/features/home/presentation/widgets/home_calendar.dart';
import 'package:barbershop_app/features/home/presentation/widgets/home_extras.dart';
import 'package:barbershop_app/features/home/presentation/widgets/home_top.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _pagePad = EdgeInsets.symmetric(horizontal: AppSpace.page);

/// Home: the web dashboard, in the same order and with the same cards:
/// overview, staff calendar, today, upcoming, top services, top products.
/// The server's `widgets` flags decide which blocks a user gets.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int? _confirmingId;

  Future<void> _confirm(AppointmentRow row) async {
    setState(() => _confirmingId = row.id);
    try {
      await ref.read(homeProvider.notifier).confirm(row);
      ref.invalidate(calendarProvider);
      if (mounted) {
        showToast(
          context,
          'Booking for ${row.customerName} confirmed.',
          kind: ToastKind.success,
        );
      }
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _confirmingId = null);
    }
  }

  void _openBookings() => context.go('/app/appointments');

  void _openBooking(AppointmentRow a) => showAppointmentSheet(context, row: a);

  /// A count card opens the Bookings tab already filtered.
  void _openFiltered(AppointmentFilter f) {
    ref.read(appointmentFilterProvider.notifier).set(f);
    _openBookings();
  }

  Future<void> _refresh() async {
    ref.invalidate(calendarProvider);
    await ref.read(homeProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    final user = ref.watch(currentUserProvider);
    final pad = AppNavBar.reservedHeight(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AppRefresh(
          onRefresh: _refresh,
          child: SoftSwitcher(
            animateSize: false,
            duration: const Duration(milliseconds: 280),
            child: switch (home) {
              AsyncData(:final value) => KeyedSubtree(
                key: const ValueKey('content'),
                child: _content(context, value, user, pad),
              ),
              AsyncError(:final error) when home.value == null => KeyedSubtree(
                key: const ValueKey('error'),
                child: _error(error, pad),
              ),
              _ when home.value != null => KeyedSubtree(
                key: const ValueKey('content'),
                child: _content(context, home.value!, user, pad),
              ),
              _ => KeyedSubtree(
                key: const ValueKey('loading'),
                child: _loading(user, pad),
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _loading(AuthUser user, double pad) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.lg,
        AppSpace.page,
        pad,
      ),
      children: [
        HomeHeader(user: user, onAvatar: () {}),
        const SizedBox(height: AppSpace.md),
        const SkeletonLoader(
          child: Column(
            children: [
              SkeletonBox(height: 170, radius: 28),
              SizedBox(height: AppSpace.md),
              SkeletonBox(height: 120, radius: 20),
              SizedBox(height: AppSpace.md),
              SkeletonBox(height: 190, radius: 28),
              SizedBox(height: AppSpace.md),
              SkeletonBox(height: 60, radius: 14),
              SizedBox(height: AppSpace.sm),
              SkeletonBox(height: 60, radius: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _error(Object error, double pad) {
    final f = error is Failure ? error : null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: pad),
      children: [
        SizedBox(
          height: 520,
          child: ErrorState(
            message: f?.userMessage ?? 'Could not load Home.',
            supportCode: f?.requestId,
            onRetry: () => ref.invalidate(homeProvider),
          ),
        ),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    HomeData data,
    AuthUser user,
    double pad,
  ) {
    final s = data.summary;
    final modules = user.modules;
    final next = data.nextUp;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: pad),
      children: [
        HomeHeader(user: user, onAvatar: () => context.go('/app/more')),
        // Phone offline: the strip at the top of the app already says so.
        if (data.fromCache && ConnectionScope.onlineOf(context)) ...[
          const SizedBox(height: AppSpace.md),
          const Padding(
            padding: _pagePad,
            child: OfflineBanner(
              message: "Can't reach the shop right now. Showing saved data.",
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Padding(
          padding: _pagePad,
          child: HomeSummaryCard(
            summary: s,
            onCount: modules.appointments ? _openFiltered : null,
          ),
        ),
        if (s.showToday && next != null) ...[
          const SizedBox(height: AppSpace.lg),
          Padding(
            padding: _pagePad,
            child: NextUpCard(
              row: next,
              confirming: _confirmingId == next.id,
              onConfirm: () => _confirm(next),
              onOpen: () => _openBooking(next),
            ),
          ),
        ],
        if (modules.calendar) ...[
          SectionHeader(
            'Staff Calendar',
            subtitle: 'Today, by barber',
            actionLabel: 'Open Full Calendar',
            onAction: () => context.go('/app/calendar'),
          ),
          const Padding(padding: _pagePad, child: _StaffCalendarBlock()),
        ],
        if (s.showToday || (s.showUpcoming && data.upcoming.isNotEmpty)) ...[
          SectionHeader(
            'Appointments',
            actionLabel: modules.appointments ? 'View All' : null,
            onAction: _openBookings,
          ),
          Padding(
            padding: _pagePad,
            child: AppointmentsBlock(
              today: s.showToday ? data.today : const [],
              upcoming: s.showUpcoming ? data.upcoming : const [],
              upcomingTotal: s.upcoming,
              showToday: s.showToday,
              onOpen: _openBooking,
            ),
          ),
        ],
        if ((s.showTopServices && data.topServices.isNotEmpty) ||
            (s.showTopProducts && data.products.isNotEmpty)) ...[
          const SectionHeader('Highlights', subtitle: 'What sells best'),
          Padding(
            padding: _pagePad,
            child: HomeInsightsCard(
              services: s.showTopServices ? data.topServices : const [],
              products: s.showTopProducts ? data.products : const [],
            ),
          ),
        ],
      ],
    );
  }
}

/// Today's and upcoming bookings in one block with a switch, three at a time:
/// the full lists are the Bookings tab ("View All").
class AppointmentsBlock extends StatefulWidget {
  const AppointmentsBlock({
    super.key,
    required this.today,
    required this.upcoming,
    required this.upcomingTotal,
    required this.showToday,
    required this.onOpen,
  });

  final List<AppointmentRow> today;
  final List<AppointmentRow> upcoming;
  final int upcomingTotal;
  final bool showToday;
  final void Function(AppointmentRow row) onOpen;

  @override
  State<AppointmentsBlock> createState() => _AppointmentsBlockState();
}

enum _Day { today, upcoming }

class _AppointmentsBlockState extends State<AppointmentsBlock> {
  static const _limit = 3;
  _Day? _picked;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final hasUpcoming = widget.upcoming.isNotEmpty;
    final both = widget.showToday && hasUpcoming;
    // Open on what matters: today, unless there is nothing today but later.
    final view =
        _picked ??
        (widget.showToday && (widget.today.isNotEmpty || !hasUpcoming)
            ? _Day.today
            : _Day.upcoming);
    final rows = view == _Day.today ? widget.today : widget.upcoming;
    final shown = _all ? rows : rows.take(_limit).toList();

    final body = rows.isEmpty
        ? const QuietState(
            title: 'Quiet day',
            message: 'No appointments left for today.',
          )
        : Column(
            children: [
              for (final a in shown) ...[
                CompactAppointmentTile(
                  row: a,
                  showDate: view == _Day.upcoming,
                  onTap: () => widget.onOpen(a),
                ),
                const SizedBox(height: AppSpace.sm + 2),
              ],
              if (rows.length > _limit)
                Pressable(
                  onTap: () => setState(() => _all = !_all),
                  minSize: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        _all
                            ? 'Show less'
                            : 'Show ${rows.length - _limit} more',
                        style: AppType.label.copyWith(
                          color: context.tokens.accentText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (both) ...[
          SegmentedTabs<_Day>(
            items: [
              SegmentItem(_Day.today, 'Today', count: widget.today.length),
              SegmentItem(
                _Day.upcoming,
                'Upcoming',
                count: widget.upcomingTotal,
              ),
            ],
            selected: view,
            onChanged: (v) => setState(() {
              _picked = v;
              _all = false;
            }),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        // Today <-> Upcoming and "Show more" swap softly instead of jumping.
        SoftSwitcher(
          child: KeyedSubtree(key: ValueKey('${view.name}-$_all'), child: body),
        ),
      ],
    );
  }
}

/// Today's slice of the calendar window, with its own loading state so the
/// rest of Home never waits for it.
class _StaffCalendarBlock extends ConsumerWidget {
  const _StaffCalendarBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(calendarProvider);
    final today = ShopTime.today();
    final avail =
        ref.watch(dayAvailabilityProvider(ShopTime.ymd(today))).value ??
        DayAvailability.fallback();
    return switch (window) {
      AsyncData(:final value) when value.lanes.isNotEmpty => StaffCalendarCard(
        day: value.day(today, avail, order: ref.watch(calendarOrderProvider)),
        // A booking opens its details and actions, right here.
        onBooking: (e) {
          if (e.appointmentId == null) return;
          showAppointmentSheet(
            context,
            laneStaffId: e.laneId,
            row: e.toAppointmentRow(
              ref.read(bootstrapProvider).actionsFor(e.status.code),
            ),
          );
        },
        // A free time starts a booking for that barber at that time.
        onFree: (lane, minute) {
          final h = (minute ~/ 60).toString().padLeft(2, '0');
          final m = (minute % 60).toString().padLeft(2, '0');
          context.push(
            '/app/appointment/new?staff=${lane.id}&date=${ShopTime.ymd(today)}&time=$h:$m',
          );
        },
      ),
      AsyncData() => const SizedBox.shrink(),
      AsyncError() => const SizedBox.shrink(),
      _ => const SkeletonLoader(child: SkeletonBox(height: 120, radius: 20)),
    };
  }
}
