import 'dart:async';

import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:flutter/material.dart';

/// The returning-user panel: who this is, one big unlock button, a way out.
/// Used full-screen at launch and as the cover over the running app.
///
/// Pure widget (no providers): the connectors in `lock_screen.dart` and
/// `lock_overlay.dart` feed it, so it is easy to test.
class LockPanel extends StatefulWidget {
  const LockPanel({
    super.key,
    required this.kind,
    required this.state,
    required this.onUnlock,
    required this.onUsePassword,
    this.name,
    this.roleLabel,
    this.autoPrompt = true,
  });

  final BiometricKind kind;
  final AppLockState state;
  final String? name;
  final String? roleLabel;
  final Future<void> Function() onUnlock;
  final Future<void> Function() onUsePassword;

  /// Open the phone's prompt by itself when the panel appears.
  final bool autoPrompt;

  @override
  State<LockPanel> createState() => _LockPanelState();
}

class _LockPanelState extends State<LockPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  Timer? _auto;
  bool _confirmingExit = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompt) {
      // A moment for the screen to settle: a prompt that opens while the app is
      // still coming to the front is cancelled by Android.
      _auto = Timer(const Duration(milliseconds: 450), () {
        if (mounted && !widget.state.prompting) unawaited(widget.onUnlock());
      });
    }
  }

  @override
  void didUpdateWidget(LockPanel old) {
    super.didUpdateWidget(old);
    if (widget.state.prompting && !_ring.isAnimating) {
      if (!MediaQuery.disableAnimationsOf(context)) _ring.repeat();
    } else if (!widget.state.prompting && _ring.isAnimating) {
      _ring
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ring.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.kind) {
    BiometricKind.face => Icons.face_unlock_rounded,
    BiometricKind.screenLock => Icons.lock_open_rounded,
    _ => Icons.fingerprint_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.state;
    final first = (widget.name ?? '').trim().split(RegExp(r'\s+')).first;
    final label = 'Unlock with ${widget.kind.unlockWith}';

    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpace.xl),
              const SizedBox(
                width: 92,
                height: 92 * RosenthalCrest.aspect,
                child: RosenthalCrest(),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                first.isEmpty ? 'Welcome back' : 'Welcome back,',
                textAlign: TextAlign.center,
                style: AppText.display(
                  first.isEmpty ? 30 : 24,
                  color: t.text,
                  weight: FontWeight.w600,
                ),
              ),
              if (first.isNotEmpty)
                Text(
                  first,
                  textAlign: TextAlign.center,
                  style: AppText.display(
                    32,
                    color: t.text,
                    weight: FontWeight.w700,
                  ),
                ),
              if ((widget.roleLabel ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                StatusPill(label: widget.roleLabel!, color: t.accent),
              ],
              const SizedBox(height: AppSpace.xxl),
              _UnlockButton(
                icon: _icon,
                label: label,
                ring: _ring,
                prompting: s.prompting,
                onTap: s.prompting ? null : () => unawaited(widget.onUnlock()),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                s.prompting ? 'Waiting for you…' : label,
                textAlign: TextAlign.center,
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: s.message == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: AppSpace.sm),
                        child: Text(
                          s.message!,
                          key: const Key('lock-message'),
                          textAlign: TextAlign.center,
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpace.xl),
              if (_confirmingExit)
                _ExitConfirm(
                  onCancel: () => setState(() => _confirmingExit = false),
                  onConfirm: () => unawaited(widget.onUsePassword()),
                )
              else ...[
                if (s.inTrouble)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Text(
                      'Having trouble?',
                      textAlign: TextAlign.center,
                      style: AppType.caption.copyWith(color: t.textMuted),
                    ),
                  ),
                AppButton(
                  label: 'Use password instead',
                  compact: true,
                  variant: s.inTrouble
                      ? AppButtonVariant.primary
                      : AppButtonVariant.secondary,
                  onPressed: () => setState(() => _confirmingExit = true),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              Text(
                'Locked to keep the shop safe',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: t.textMuted),
              ),
              const SizedBox(height: AppSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnlockButton extends StatelessWidget {
  const _UnlockButton({
    required this.icon,
    required this.label,
    required this.ring,
    required this.prompting,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Animation<double> ring;
  final bool prompting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.96,
        minSize: 0,
        child: SizedBox(
          width: 132,
          height: 132,
          child: AnimatedBuilder(
            animation: ring,
            builder: (context, child) {
              // A soft ring that breathes outwards while the prompt is open.
              final v = Curves.easeOut.transform(ring.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (prompting)
                    Container(
                      width: 96 + 36 * v,
                      height: 96 + 36 * v,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: t.accent.withValues(alpha: 0.55 * (1 - v)),
                          width: 2,
                        ),
                      ),
                    ),
                  child!,
                ],
              );
            },
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.goldGradient,
                boxShadow: [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: 50, color: AppColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitConfirm extends StatelessWidget {
  const _ExitConfirm({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const Key('lock-exit-confirm'),
      children: [
        Text(
          'This signs you out of this phone. You will sign in with your password.',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                compact: true,
                variant: AppButtonVariant.secondary,
                onPressed: onCancel,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: AppButton(
                label: 'Sign out',
                compact: true,
                variant: AppButtonVariant.danger,
                onPressed: onConfirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
