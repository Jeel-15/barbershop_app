import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Interactive 3D surface (Revolut Business / Oura style).
///
/// Drag to rotate the child in perspective. When untouched it sways gently by
/// itself; on release it eases back into that sway. [builder] receives the
/// current tilt in the range -1..1 so layers can add their own parallax and
/// specular highlights.
class Tilt3D extends StatefulWidget {
  const Tilt3D({
    super.key,
    required this.builder,
    this.maxAngle = 0.32,
    this.perspective = 0.0012,
    this.idle = true,
  });

  final Widget Function(BuildContext context, Offset tilt) builder;
  final double maxAngle;
  final double perspective;
  final bool idle;

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();
  late final AnimationController _user = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    value: 0,
  );

  Offset _drag = Offset.zero;

  Offset get _idleTilt {
    if (!widget.idle) return Offset.zero;
    final a = _idle.value * math.pi * 2;
    return Offset(math.sin(a) * 0.42, math.cos(a * 1) * 0.26);
  }

  Offset get _tilt => Offset.lerp(_idleTilt, _drag, _user.value)!;

  @override
  void dispose() {
    _idle.dispose();
    _user.dispose();
    super.dispose();
  }

  void _start(DragStartDetails d) {
    _drag = _tilt;
    _user.value = 1;
  }

  void _update(DragUpdateDetails d) {
    final box = context.size ?? const Size(300, 300);
    final next =
        _drag +
        Offset(d.delta.dx / (box.width / 2), d.delta.dy / (box.height / 2));
    setState(() {
      _drag = Offset(
        next.dx.clamp(-1.0, 1.0).toDouble(),
        next.dy.clamp(-1.0, 1.0).toDouble(),
      );
    });
  }

  void _end([Object? _]) {
    _user.animateTo(0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: _end,
      onPanCancel: _end,
      child: AnimatedBuilder(
        animation: Listenable.merge([_idle, _user]),
        builder: (context, _) {
          final tilt = _tilt;
          final m = Matrix4.identity()
            ..setEntry(3, 2, widget.perspective)
            ..rotateX(-tilt.dy * widget.maxAngle)
            ..rotateY(tilt.dx * widget.maxAngle);
          return Transform(
            alignment: Alignment.center,
            transform: m,
            child: widget.builder(context, tilt),
          );
        },
      ),
    );
  }
}
