import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:flutter/material.dart';

/// The key to the day: a chip per booking status (colour, icon and how many),
/// then what green and hatched mean. Tapping a status keeps only those
/// bookings bright, so "where are my pending ones" is one tap.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({
    super.key,
    required this.counts,
    required this.focus,
    required this.onFocus,
  });

  final DayCounts counts;

  /// Status codes kept bright; empty = all.
  final Set<int> focus;
  final ValueChanged<Set<int>> onFocus;

  static const _shown = [
    AppointmentStatus.pending,
    AppointmentStatus.confirmed,
    AppointmentStatus.rescheduled,
    AppointmentStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
        children: [
          for (final s in _shown)
            // Completed bookings only matter when there are some.
            if (s != AppointmentStatus.completed || counts.of(s.code) > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _StatusChip(
                  status: s,
                  count: counts.of(s.code),
                  selected: focus.contains(s.code),
                  onTap: () {
                    final next = {...focus};
                    if (!next.add(s.code)) next.remove(s.code);
                    onFocus(next);
                  },
                ),
              ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            color: t.border,
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => showCalendarGuide(context),
            minSize: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 16,
                    color: t.accentText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Guide',
                    style: AppType.label.copyWith(
                      color: t.text,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _Swatch(
            label: 'Free',
            box: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: t.success.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.success.withValues(alpha: 0.7)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _Swatch(
            label: 'Not available',
            box: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CustomPaint(
                  painter: _MiniHatch(t.textMuted.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _Swatch(
            label: 'Break${counts.breaks > 0 ? ' ${counts.breaks}' : ''}',
            box: Icon(Icons.coffee_rounded, size: 14, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final AppointmentStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(status);
    return Pressable(
      onTap: onTap,
      minSize: 0,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.28) : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.45),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              status.label == 'Confirm' ? 'Confirmed' : _word(status),
              style: AppType.label.copyWith(
                color: count == 0 ? t.textMuted : t.text,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: AppType.label.copyWith(
                color: count == 0 ? t.textMuted : color,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _word(AppointmentStatus s) => switch (s) {
    AppointmentStatus.pending => 'Pending',
    AppointmentStatus.confirmed => 'Confirmed',
    AppointmentStatus.rescheduled => 'Rescheduled',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
  };
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.box});

  final String label;
  final Widget box;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        const SizedBox(width: 5),
        Text(
          label,
          style: AppType.caption.copyWith(
            color: t.textSecondary,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _MiniHatch extends CustomPainter {
  _MiniHatch(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 4) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_MiniHatch old) => old.color != color;
}

/// "How to read the calendar": every colour and mark, and what a tap does.
Future<void> showCalendarGuide(BuildContext context) => showAppSheet<void>(
  context,
  title: 'How to read the calendar',
  builder: (ctx) {
    final t = ctx.tokens;
    Widget row(Widget swatch, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 44, child: Center(child: swatch)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.bodyStrong.copyWith(color: t.text)),
                Text(
                  text,
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Widget status(AppointmentStatus s, String text, {bool dashed = false}) =>
        row(
          Container(
            width: 40,
            height: 28,
            decoration: BoxDecoration(
              color: t.statusColor(s).withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: t.statusColor(s),
                width: dashed ? 1.6 : 1,
              ),
            ),
            child: Icon(s.icon, size: 15, color: t.statusColor(s)),
          ),
          s == AppointmentStatus.confirmed
              ? 'Confirmed'
              : s.filterLabel == 'Reschedule'
              ? 'Rescheduled'
              : s.label == 'Complete'
              ? 'Completed'
              : s.label,
          text,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        status(
          AppointmentStatus.pending,
          'Waiting for the shop to confirm it. Dashed outline.',
          dashed: true,
        ),
        status(
          AppointmentStatus.confirmed,
          'Confirmed: the customer is expected.',
        ),
        status(AppointmentStatus.rescheduled, 'Moved to this time.'),
        status(AppointmentStatus.completed, 'Done and invoiced.'),
        row(
          Container(
            width: 40,
            height: 28,
            decoration: BoxDecoration(
              color: t.success.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.success.withValues(alpha: 0.7)),
            ),
          ),
          'Free',
          'Working time with nothing booked. Tap it, then tap Book.',
        ),
        row(
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 28,
              child: CustomPaint(
                painter: _MiniHatch(t.textMuted.withValues(alpha: 0.7)),
              ),
            ),
          ),
          'Not available',
          'Outside working hours, a day off or the shop is closed. Cannot be booked.',
        ),
        row(
          Icon(Icons.coffee_rounded, size: 22, color: t.textSecondary),
          'Break',
          'The barber is away for a while.',
        ),
        row(
          Container(width: 40, height: 2, color: t.danger),
          'Red line',
          'Now. Earlier time is dimmed.',
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Tap a booking to see it and its actions. Tap a status above to keep only those bright.',
          style: AppType.caption.copyWith(color: t.textMuted),
        ),
      ],
    );
  },
);
