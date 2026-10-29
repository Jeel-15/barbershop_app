import 'package:flutter/material.dart';

import '../effects/snipping_scissors.dart';
import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';

/// "Nothing here": the snipping scissors with a title and a line of text
/// (a quiet day on Home, no bookings found, ...).
class QuietState extends StatelessWidget {
  const QuietState({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.xl,
        horizontal: AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          const SnippingScissors(size: 110),
          const SizedBox(height: AppSpace.sm),
          Text(title, style: AppType.heading.copyWith(color: t.text)),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
