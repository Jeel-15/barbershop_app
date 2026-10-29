import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';

/// Loading placeholder. Wrap a group of [SkeletonBox]es in ONE [SkeletonLoader]
/// (a single shimmer for the whole group keeps it cheap).
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" switch: static placeholders then.
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) {
            final x = -1.0 + 3.0 * _c.value;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(x - 1, 0),
                end: Alignment(x, 0),
                colors: [
                  Colors.transparent,
                  t.shimmerHighlight.withValues(alpha: 0.9),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(rect),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: context.tokens.shimmerBase,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}

/// A list of row-shaped placeholders (avatar + two lines).
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpace.page,
      vertical: AppSpace.sm,
    ),
  });

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < count; i++)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SkeletonBox(height: 46, circle: true),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 160, height: 14),
                          SizedBox(height: 8),
                          SkeletonBox(width: 110, height: 11),
                        ],
                      ),
                    ),
                    SizedBox(width: 14),
                    SkeletonBox(width: 54, height: 22, radius: 11),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
