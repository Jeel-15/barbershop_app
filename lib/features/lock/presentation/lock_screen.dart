import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:barbershop_app/features/lock/presentation/lock_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Launch with a fingerprint-locked session: the panel opens the phone's prompt
/// by itself, and the app loads once it succeeds.
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final session = ref.watch(sessionControllerProvider);
    final lock = ref.watch(appLockProvider);
    final kind =
        ref.watch(biometricKindProvider).value ?? BiometricKind.fingerprint;
    final locked = session is SessionLocked ? session : null;
    final controller = ref.read(appLockProvider.notifier);

    return PopScope(
      canPop: false, // back must not leave the lock
      child: SystemBars(
        child: Scaffold(
          backgroundColor: t.bg,
          body: SafeArea(
            child: LockPanel(
              kind: kind,
              state: lock,
              name: locked?.name,
              roleLabel: locked?.roleLabel,
              onUnlock: controller.unlock,
              onUsePassword: controller.usePassword,
            ),
          ),
        ),
      ),
    );
  }
}
