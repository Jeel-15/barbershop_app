import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Small coloured label. Always icon + text, never colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: color),
            SizedBox(width: compact ? 4 : 5),
          ],
          Text(
            label,
            style: AppText.ui(
              compact ? 11 : 12,
              weight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The five appointment statuses with the web's meaning and a consistent look.
class AppointmentStatusPill extends StatelessWidget {
  const AppointmentStatusPill(this.status, {super.key, this.compact = false});

  final AppointmentStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: status.label,
      color: context.tokens.statusColor(status),
      icon: status.icon,
      compact: compact,
    );
  }
}
