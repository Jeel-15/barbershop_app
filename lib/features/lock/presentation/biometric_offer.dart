import 'dart:async';

import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

IconData _iconFor(BiometricKind k) => switch (k) {
  BiometricKind.face => Icons.face_unlock_rounded,
  BiometricKind.screenLock => Icons.lock_open_rounded,
  _ => Icons.fingerprint_rounded,
};

/// "Open Rosenthal with your fingerprint?" Returns true for "Turn on", false
/// for "Not now" (or closing the sheet).
Future<bool> showBiometricOffer(
  BuildContext context,
  BiometricKind kind,
) async {
  final yes = await showAppSheet<bool>(
    context,
    builder: (ctx) => _OfferBody(kind: kind),
    footer: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: 'Turn on',
          icon: _iconFor(kind),
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        const SizedBox(height: AppSpace.sm),
        AppButton(
          label: 'Not now',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ],
    ),
  );
  return yes ?? false;
}

class _OfferBody extends StatelessWidget {
  const _OfferBody({required this.kind});

  final BiometricKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final what = kind == BiometricKind.screenLock
        ? "your phone's screen lock"
        : 'your ${kind.unlockWith}';
    final warning = kind == BiometricKind.screenLock
        ? "Anyone who knows your phone's PIN will be able to open the app."
        : 'Anyone whose fingerprint is saved on this phone will be able to open the app.';
    return Column(
      children: [
        const SizedBox(height: AppSpace.sm),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.accent.withValues(alpha: 0.12),
            border: Border.all(color: t.accent.withValues(alpha: 0.4)),
          ),
          child: Icon(_iconFor(kind), size: 40, color: t.accentText),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          'Open Rosenthal with $what?',
          textAlign: TextAlign.center,
          style: AppType.heading.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Next time, skip typing your password. It stays on your phone and '
          'the shop never sees it.',
          textAlign: TextAlign.center,
          style: AppType.body.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.md),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.control,
            border: Border.all(color: t.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: t.textMuted),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  warning,
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows the offer once, a moment after a password sign-in (the provider is
/// set by the session), then asks the phone to turn the feature on.
class BiometricOfferHost extends ConsumerStatefulWidget {
  const BiometricOfferHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BiometricOfferHost> createState() => _BiometricOfferHostState();
}

class _BiometricOfferHostState extends ConsumerState<BiometricOfferHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // The flag may already be set: the sign-in finished before this page existed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(biometricOfferProvider)) unawaited(_offer());
    });
  }

  Future<void> _offer() async {
    if (_showing) return;
    _showing = true;
    ref.read(biometricOfferProvider.notifier).dismiss();
    try {
      // A calm beat after landing on the dashboard.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final setup = ref.read(biometricSetupProvider);
      final kind = await setup.kind();
      if (!mounted || !kind.available) return;
      final yes = await showBiometricOffer(context, kind);
      if (!yes) {
        await setup.declineOffer();
        return;
      }
      final outcome = await setup.enable();
      if (!mounted) return;
      ref.read(appLockProvider.notifier).timeoutChanged();
      showEnableOutcome(context, outcome, kind);
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(biometricOfferProvider, (_, on) {
      if (on) unawaited(_offer());
    });
    return widget.child;
  }
}

/// The toast after trying to turn it on (nothing for a cancelled prompt).
void showEnableOutcome(
  BuildContext context,
  EnableOutcome outcome,
  BiometricKind kind,
) {
  switch (outcome) {
    case EnableOutcome.enabled:
      showToast(context, '${kind.noun} is on.', kind: ToastKind.success);
    case EnableOutcome.cancelled:
      break;
    case EnableOutcome.notAvailable:
      showToast(
        context,
        'Set a screen lock on your phone first, then try again in Security.',
        kind: ToastKind.error,
      );
    case EnableOutcome.failed:
      showToast(
        context,
        'Could not turn it on. Please try again in Security.',
        kind: ToastKind.error,
      );
  }
}
