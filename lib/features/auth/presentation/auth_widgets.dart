import 'dart:async';
import 'dart:math' as math;

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Soft brand glow behind the auth screens.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (t.isDark)
          const Positioned.fill(
            child: IgnorePointer(child: GoldDust(count: 18, opacity: 0.55)),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.8),
              radius: 1.1,
              colors: [
                t.accent.withValues(alpha: t.isDark ? 0.16 : 0.18),
                Colors.transparent,
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Inline message above a form: an error (red) or a heads-up (gold).
class AuthBanner extends StatelessWidget {
  const AuthBanner({
    super.key,
    required this.message,
    this.info = false,
    this.supportCode,
  });

  final String message;
  final bool info;
  final String? supportCode;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = info ? t.warning : t.danger;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md + 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              info ? Icons.info_rounded : Icons.error_rounded,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: AppType.body.copyWith(color: t.text, fontSize: 14),
                  ),
                  if (supportCode != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Support code: $supportCode',
                      style: AppType.caption.copyWith(
                        color: t.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A "Resend code in 00:32" label that turns into a button when the wait is over.
class ResendTimer extends StatefulWidget {
  const ResendTimer({
    super.key,
    required this.availableAt,
    required this.onResend,
    required this.clock,
    this.busy = false,
  });

  final DateTime? availableAt;
  final VoidCallback onResend;
  final DateTime Function() clock;
  final bool busy;

  @override
  State<ResendTimer> createState() => _ResendTimerState();
}

class _ResendTimerState extends State<ResendTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final at = widget.availableAt;
    final left = at == null ? Duration.zero : at.difference(widget.clock());
    if (left > Duration.zero) {
      final mm = left.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = left.inSeconds.remainder(60).toString().padLeft(2, '0');
      return Text(
        'Resend code in $mm:$ss',
        style: AppType.caption.copyWith(color: t.textMuted),
      );
    }
    return TextButton(
      onPressed: widget.busy ? null : widget.onResend,
      child: Text(
        'Resend code',
        style: AppType.label.copyWith(fontSize: 14, color: t.accentText),
      ),
    );
  }
}

/// A requirement line that ticks itself (password rules).
class RuleRow extends StatelessWidget {
  const RuleRow(this.text, {super.key, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.fast,
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.circle_outlined,
              key: ValueKey(ok),
              size: 18,
              color: ok ? t.success : t.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppType.caption.copyWith(
                color: ok ? t.text : t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shakes sideways each time [trigger] changes (wrong password).
class ShakeOnChange extends StatefulWidget {
  const ShakeOnChange({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<ShakeOnChange> createState() => _ShakeOnChangeState();
}

class _ShakeOnChangeState extends State<ShakeOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant ShakeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          math.sin(_c.value * math.pi * 6) * 9 * (1 - _c.value),
          0,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
