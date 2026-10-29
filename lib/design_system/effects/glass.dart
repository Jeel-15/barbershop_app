import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass surface (Moonly / Fresha style) over whatever is behind it.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.blur = 18,
    this.tint = 0.10,
    this.borderAlpha = 0.22,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double tint;
  final double borderAlpha;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: shape,
            color: Colors.white.withValues(alpha: tint),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderAlpha),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
