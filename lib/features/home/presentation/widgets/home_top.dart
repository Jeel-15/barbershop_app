import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/auth/domain/auth_user.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:flutter/material.dart';

/// Greeting tab header: today's date, serif greeting, avatar.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.user, required this.onAvatar});

  final AuthUser user;
  final VoidCallback onAvatar;

  static String greeting() {
    final h = ShopTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return TabHeader(
      eyebrow: ShopTime.dayLabel(ShopTime.today()),
      // One line: the greeting is not worth a second line of the first screen.
      title: '${greeting()}, ${user.firstName}',
      titleSize: 25,
      trailing: Pressable(
        onTap: onAvatar,
        minSize: 0,
        child: Semantics(
          button: true,
          label: 'Open profile and menu',
          child: AppAvatar(
            name: user.name,
            imageUrl: user.profileImageUrl,
            size: 46,
            ring: true,
          ),
        ),
      ),
    );
  }
}

/// The booking counts as small chips in one row that slides sideways. No money
/// here (that is the card on More). Admin: Upcoming / Customers / Completed,
/// like the web's cards. Staff: Upcoming / Completed / Confirmed / Scheduled /
/// Cancelled. A chip with a list behind it opens Bookings with that filter.
class HomeCountChips extends StatelessWidget {
  const HomeCountChips({
    super.key,
    required this.summary,
    required this.onCount,
  });

  final DashboardSummary summary;

  /// Opens Bookings with this filter; null when the user cannot open Bookings.
  final ValueChanged<AppointmentFilter>? onCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Upcoming = booked for a later day (the web's definition).
    final tomorrow = ShopTime.today().add(const Duration(days: 1));
    final upcoming = _Chip(
      icon: Icons.event_available_rounded,
      label: 'Upcoming',
      value: summary.upcoming,
      color: t.statusColor(AppointmentStatus.pending),
      onTap: onCount == null
          ? null
          : () => onCount!(
              AppointmentFilter(
                startDate: ShopTime.ymd(tomorrow),
                endDate: ShopTime.ymd(tomorrow.add(const Duration(days: 730))),
              ),
            ),
    );
    _Chip byStatus(String label, int value, AppointmentStatus s) => _Chip(
      icon: s.icon,
      label: label,
      value: value,
      color: t.statusColor(s),
      onTap: onCount == null
          ? null
          : () => onCount!(AppointmentFilter(status: s)),
    );
    final chips = summary.isAdmin
        ? [
            upcoming,
            _Chip(
              icon: Icons.people_alt_rounded,
              label: 'Customers',
              value: summary.customers,
              color: t.violet,
            ),
            byStatus(
              'Completed',
              summary.completed,
              AppointmentStatus.completed,
            ),
          ]
        : [
            upcoming,
            byStatus(
              'Completed',
              summary.completed,
              AppointmentStatus.completed,
            ),
            byStatus(
              'Confirmed',
              summary.confirmed,
              AppointmentStatus.confirmed,
            ),
            byStatus(
              'Scheduled',
              summary.rescheduled,
              AppointmentStatus.rescheduled,
            ),
            byStatus(
              'Cancelled',
              summary.cancelled,
              AppointmentStatus.cancelled,
            ),
          ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) => StaggerIn(index: i, child: chips[i]),
      ),
    );
  }
}

/// "● 11  Customers": the status colour, the count, its name.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: onTap != null,
      label: '$value $label',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.96,
        minSize: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 8),
              CountUpText(
                value: value.toDouble(),
                builder: (v) => '${v.round()}',
                duration: const Duration(milliseconds: 700),
                style: AppType.title.copyWith(color: t.text, fontSize: 17),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: AppType.caption.copyWith(
                  color: t.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
