import 'package:flutter/material.dart';

import '../tokens/layout.dart';
import 'haptics.dart';

/// Press feedback for anything tappable: scales down slightly, optional haptic,
/// and exposes button semantics. Minimum touch target is enforced.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
    this.scale = 0.97,
    this.semanticLabel,
    this.minSize = kMinTarget,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final double scale;
  final String? semanticLabel;
  final double minSize;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) AppHaptics.tap();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.minSize,
            minWidth: widget.minSize,
          ),
          child: AnimatedScale(
            scale: _down ? widget.scale : 1,
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
