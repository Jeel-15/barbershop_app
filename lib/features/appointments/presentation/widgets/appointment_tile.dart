import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:flutter/material.dart';

/// One appointment in a list (Home, Appointments): time on the left, status colour rail,
/// customer, services, barber.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    super.key,
    required this.row,
    required this.onTap,
    this.showDate = false,
  });

  final AppointmentRow row;
  final VoidCallback onTap;

  /// Upcoming rows show their day ("Tomorrow") under the time.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(row.status);
    final parts = row.startLabel.replaceFirst(RegExp(r'^0'), '').split(' ');
    final dimmed = !row.isOpen;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: t.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      parts.first,
                      style: AppType.title.copyWith(
                        color: dimmed ? t.textMuted : t.text,
                        fontSize: 19,
                      ),
                    ),
                    Text(
                      parts.length > 1 ? parts.last : '',
                      style: AppType.label.copyWith(color: t.textMuted),
                    ),
                    if (showDate) ...[
                      const SizedBox(height: 2),
                      Text(
                        ShopTime.relativeDay(ShopTime.parseDate(row.date)),
                        textAlign: TextAlign.center,
                        style: AppType.caption.copyWith(
                          color: t.accentText,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      row.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong.copyWith(
                        color: dimmed ? t.textSecondary : t.text,
                      ),
                    ),
                    if ((row.customerPhone ?? '').trim().isNotEmpty)
                      Text(
                        row.customerPhone!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(color: t.textSecondary),
                      ),
                    // "Staff / Services": the web's lines, e.g. "Allen: Men's cut".
                    for (final l in row.lines.take(2))
                      Text(
                        l,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: t.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              AppointmentStatusPill(row.status, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
