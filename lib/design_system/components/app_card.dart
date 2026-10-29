import 'package:flutter/material.dart';

import '../effects/glass.dart';
import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import 'pressable.dart';

/// Content container. Solid by default (fast in lists); `glass` is for hero
/// surfaces over imagery only.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.raised = false,
    this.glass = false,
    this.borderColor,
    this.radius = AppRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool raised;
  final bool glass;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final Widget card = glass
        ? Glass(radius: radius, padding: padding, child: child)
        : Container(
            padding: padding,
            decoration: BoxDecoration(
              color: raised ? t.surfaceRaised : t.surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor ?? t.border),
            ),
            child: child,
          );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.985, minSize: 0, child: card);
  }
}
