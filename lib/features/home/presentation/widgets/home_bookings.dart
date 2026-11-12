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

/// True when this booking is on now or starts within [within] (default 2 hours):
/// the only time Home spends a whole card on "next up".
bool startsSoon(
  AppointmentRow a, {
  Duration within = const Duration(hours: 2),
}) {
  final now = ShopTime.now();
  final cur = now.hour * 60 + now.minute;
  final s = ShopTime.minutes(a.start);
  final e = ShopTime.minutes(a.end);
  if (cur >= e) return false;
  return s - cur <= within.inMinutes;
}
