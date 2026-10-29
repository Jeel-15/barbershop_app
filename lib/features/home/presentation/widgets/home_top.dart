import 'package:barbershop_app/core/utils/money.dart';
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

/// The money and the counts in one card. Admin: shop revenue, then Upcoming /
/// Customers / Completed. Staff: own earnings (commission and tips), then the
/// five booking counts. The counts open Bookings with that filter.
class HomeSummaryCard extends StatelessWidget {
  const HomeSummaryCard({
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
    final admin = summary.isAdmin;

    // Upcoming = booked for a later day (the web's definition).
    final tomorrow = ShopTime.today().add(const Duration(days: 1));
    final upcoming = _Count(
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
    _Count byStatus(String label, int value, AppointmentStatus s) => _Count(
      icon: s.icon,
      label: label,
      value: value,
      color: t.statusColor(s),
      onTap: onCount == null
          ? null
          : () => onCount!(AppointmentFilter(status: s)),
    );
    final counts = admin
        ? [
            upcoming,
            _Count(
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: t.accent.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: t.isDark
                ? const [Color(0xFF2E2014), Color(0xFF1A120C)]
                : const [Color(0xFFFFF4DC), Color(0xFFF1DFB8)],
          ),
        ),
        child: Stack(
          children: [
            if (t.isDark)
              const Positioned.fill(
                child: IgnorePointer(child: GoldDust(count: 16, opacity: 0.5)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg + 4,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL REVENUE',
                    style: AppType.overline.copyWith(color: t.accentText),
                  ),
                  const SizedBox(height: 2),
                  CountUpText(
                    value: summary.revenue.cents.toDouble(),
                    builder: (v) => Money(v.round()).format(),
                    duration: const Duration(milliseconds: 1100),
                    style:
                        AppText.display(
                          38,
                          color: t.text,
                          height: 1.05,
                          weight: FontWeight.w700,
                        ).copyWith(
                          fontFeatures: const [FontFeature.liningFigures()],
                        ),
                  ),
                  Text(
                    admin
                        ? 'All appointments, without tax and tips'
                        : 'Your tips plus your commission',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  if (!admin) ...[
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _Cell(
                            'Commission',
                            summary.commission.format(hideZeroCents: true),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: t.accent.withValues(alpha: 0.25),
                        ),
                        Expanded(
                          child: _Cell(
                            'Tips Received',
                            summary.tips.format(hideZeroCents: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  Divider(height: 1, color: t.accent.withValues(alpha: 0.25)),
                  const SizedBox(height: AppSpace.md),
                  // Up to three counts share the row; more (staff) slide sideways.
                  if (counts.length <= 3)
                    Row(children: [for (final c in counts) Expanded(child: c)])
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < counts.length; i++) ...[
                            if (i > 0) const SizedBox(width: AppSpace.xl),
                            counts[i],
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.heading.copyWith(color: t.text),
        ),
        Text(label, style: AppType.caption.copyWith(color: t.textSecondary)),
      ],
    );
  }
}

/// A count over its name, with the status colour: "11 / Customers".
class _Count extends StatelessWidget {
  const _Count({
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
        minSize: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  CountUpText(
                    value: value.toDouble(),
                    builder: (v) => '${v.round()}',
                    duration: const Duration(milliseconds: 800),
                    style: AppType.title.copyWith(color: t.text, fontSize: 19),
                  ),
                ],
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  color: t.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
