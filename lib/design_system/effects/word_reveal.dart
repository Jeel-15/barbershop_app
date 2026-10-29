import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Headline that reveals word by word (rise + un-blur + fade).
/// Re-create it with a new Key to replay the animation.
class WordReveal extends StatefulWidget {
  const WordReveal({
    super.key,
    required this.text,
    required this.style,
    this.delay = Duration.zero,
    this.textAlign = CrossAxisAlignment.start,
  });

  final String text;
  final TextStyle style;
  final Duration delay;
  final CrossAxisAlignment textAlign;

  @override
  State<WordReveal> createState() => _WordRevealState();
}

class _WordRevealState extends State<WordReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(widget.delay, _c.forward);
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.text.split('\n');
    final total = lines.fold<int>(
      0,
      (sum, l) => sum + l.trim().split(' ').length,
    );

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Must restart at 0 on every frame, otherwise each rebuild pushes the
        // words' stagger window further out until they never become visible.
        var index = 0;
        final children = <Widget>[];
        for (final line in lines) {
          final words = <Widget>[];
          for (final word in line.trim().split(' ')) {
            final start = (index / total) * 0.55;
            final t = Interval(
              start,
              start + 0.45,
              curve: Curves.easeOutCubic,
            ).transform(_c.value);
            index++;
            Widget w = Text(word, style: widget.style);
            final blur = (1 - t) * 7;
            if (blur > 0.2) {
              w = ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                ),
                child: w,
              );
            }
            words.add(
              Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 24),
                  child: w,
                ),
              ),
            );
          }
          children.add(
            Wrap(
              spacing: (widget.style.fontSize ?? 16) * 0.26,
              children: words,
            ),
          );
        }
        return Column(
          crossAxisAlignment: widget.textAlign,
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
      },
    );
  }
}
