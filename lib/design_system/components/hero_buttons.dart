import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../effects/glass.dart';

/// Primary CTA: gold gradient pill with a periodic light sweep, press-scale,
/// and a soft gold glow.
class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();
  bool _down = false;

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: AppColors.goldGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: LayoutBuilder(
              builder: (context, box) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _sweep,
                      builder: (context, _) {
                        final t = Curves.easeInOut.transform(
                          (_sweep.value / 0.45).clamp(0.0, 1.0).toDouble(),
                        );
                        final w = box.maxWidth;
                        return Positioned(
                          left: -w * 0.35 + t * w * 1.5,
                          top: 0,
                          bottom: 0,
                          width: w * 0.3,
                          child: Transform(
                            transform: Matrix4.skewX(-0.45),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.5),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: AppColors.ink, size: 20),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          widget.label,
                          style: AppText.ui(
                            16.5,
                            weight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary CTA: frosted glass pill.
class GlassButton extends StatefulWidget {
  const GlassButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Glass(
          radius: 30,
          tint: 0.09,
          borderAlpha: 0.32,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                widget.label,
                style: AppText.ui(
                  15.5,
                  weight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
