import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when the server's minimum app version is newer than this build.
/// There is no way past it: the app and the server must agree.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final s = ref.watch(sessionControllerProvider);
    final current = s is UpdateRequired ? s.current.toString() : '';
    final latest = s is UpdateRequired ? s.latest.toString() : '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EmptyState(
                icon: Icons.system_update_rounded,
                title: 'Update needed',
                message:
                    'This version of the app (v$current) is too old for the shop server. Install v$latest to continue.',
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                'Ask the shop owner for the latest app file.',
                style: AppType.caption.copyWith(color: t.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
