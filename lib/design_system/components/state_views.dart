import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'app_button.dart';

/// "Nothing here yet" with a way forward.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accent.withValues(alpha: 0.12),
                border: Border.all(color: t.accent.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 34, color: t.accentText),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppType.heading.copyWith(color: t.text),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: t.textSecondary),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpace.xl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Thin strip shown under the app bar when the phone has no connection.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.message = "You're offline. Showing saved data.",
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.page,
        vertical: 8,
      ),
      color: t.warning.withValues(alpha: 0.16),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: t.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppType.caption.copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}
