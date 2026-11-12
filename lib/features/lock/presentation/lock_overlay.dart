import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:barbershop_app/features/lock/presentation/lock_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sits above the whole app (above dialogs and sheets too, because it wraps the
/// Navigator): the unlock panel when the app has locked itself, a brand cover
/// while the app leaves the screen, and the "someone is using it" signal that
/// keeps the inactivity timer from firing.
///
/// The pages underneath stay alive, so a short lock loses nothing (scroll
/// position, a half-filled form).
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SignedIn ? session.bootstrap.user : null;
    final kind =
        ref.watch(biometricKindProvider).value ?? BiometricKind.fingerprint;
    final controller = ref.read(appLockProvider.notifier);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => controller.touch(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Hidden from TalkBack while locked: the content must not be readable.
          ExcludeSemantics(excluding: lock.locked, child: child),
          if (lock.covered && !lock.locked) const _PrivacyCover(),
          if (lock.locked)
            Positioned.fill(
              child: Material(
                key: const Key('lock-overlay'),
                color: context.tokens.bg,
                child: SystemBars(
                  child: SafeArea(
                    child: LockPanel(
                      kind: kind,
                      state: lock,
                      name: user?.name,
                      roleLabel: user?.roleLabel,
                      onUnlock: controller.unlock,
                      onUsePassword: controller.usePassword,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the Recents thumbnail shows: the crest on the brand's dark, nothing private.
class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ColoredBox(
        key: Key('privacy-cover'),
        color: AppColors.ink,
        child: Center(
          child: SizedBox(
            width: 110,
            height: 110 * RosenthalCrest.aspect,
            child: RosenthalCrest(),
          ),
        ),
      ),
    );
  }
}
