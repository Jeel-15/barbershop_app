import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/shared/contact_actions.dart';
import 'package:flutter/material.dart';

/// "in 25 min", "now", "started 10 min ago" for a booking today.
String whenText(AppointmentRow a) {
  final now = ShopTime.now();
  final s = ShopTime.minutes(a.start);
  final e = ShopTime.minutes(a.end);
  final cur = now.hour * 60 + now.minute;
  if (cur >= s && cur < e) return 'Happening now';
  if (cur >= e) return 'Was at ${a.startLabel}';
  final d = s - cur;
  if (d < 60) return 'In $d min';
  final h = d ~/ 60;
  final m = d % 60;
  return m == 0 ? 'In $h h' : 'In $h h $m min';
}

/// The one booking to look at now, with Call and Confirm in reach.
class NextUpCard extends StatelessWidget {
  const NextUpCard({
    super.key,
    required this.row,
    required this.confirming,
    required this.onConfirm,
    required this.onOpen,
  });

  final AppointmentRow row;
  final bool confirming;
  final VoidCallback onConfirm;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(row.status);
    final hasPhone = (row.customerPhone ?? '').trim().isNotEmpty;
    final detail = [
      '${row.startLabel} – ${row.endLabel}',
      if (row.staffText.isNotEmpty) row.staffText,
    ].join('  ·  ');
    return Pressable(
      onTap: onOpen,
      scale: 0.99,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NEXT UP · ${whenText(row).toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.overline.copyWith(color: color),
                  ),
                ),
                AppointmentStatusPill(row.status, compact: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              row.customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.display(22, color: t.text, height: 1.1),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(color: t.textSecondary),
            ),
            if (row.servicesText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  row.servicesText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
              ),
            if (hasPhone || row.canConfirm) ...[
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  if (hasPhone)
                    Expanded(
                      child: AppButton(
                        label: 'Call',
                        icon: Icons.call_rounded,
                        variant: AppButtonVariant.secondary,
                        compact: true,
                        onPressed: () =>
                            callCustomer(context, row.customerPhone),
                      ),
                    ),
                  if (hasPhone && row.canConfirm)
                    const SizedBox(width: AppSpace.sm + 2),
                  if (row.canConfirm)
                    Expanded(
                      child: AppButton(
                        label: 'Confirm',
                        icon: Icons.check_rounded,
                        compact: true,
                        loading: confirming,
                        onPressed: onConfirm,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One booking in two lines: time, status colour, customer and what is booked.
/// The full tile (phone, every line) is the Bookings tab; Home only has to be
/// read at a glance.
class CompactAppointmentTile extends StatelessWidget {
  const CompactAppointmentTile({
    super.key,
    required this.row,
    required this.onTap,
    this.showDate = false,
  });

  final AppointmentRow row;
  final VoidCallback onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(row.status);
    final dimmed = !row.isOpen;
    final parts = row.startLabel.replaceFirst(RegExp(r'^0'), '').split(' ');
    final what = row.lines.isEmpty
        ? row.servicesText
        : '${row.lines.first}${row.lines.length > 1 ? '  +${row.lines.length - 1}' : ''}';
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: t.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      parts.first,
                      style: AppType.title.copyWith(
                        color: dimmed ? t.textMuted : t.text,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      showDate
                          ? ShopTime.relativeDay(ShopTime.parseDate(row.date))
                          : (parts.length > 1 ? parts.last : ''),
                      maxLines: 1,
                      style: AppType.caption.copyWith(
                        color: showDate ? t.accentText : t.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
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
                        fontSize: 14.5,
                      ),
                    ),
                    if (what.isNotEmpty)
                      Text(
                        what,
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
