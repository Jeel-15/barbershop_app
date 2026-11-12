import 'dart:async';

import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:barbershop_app/features/lock/domain/lock_timeout.dart';
import 'package:barbershop_app/features/lock/presentation/biometric_offer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// More / Me > Security: the switch, and how soon the app locks again.
/// Hidden on a phone that cannot do it (no screen lock).
class SecurityGroup extends ConsumerStatefulWidget {
  const SecurityGroup({super.key, required this.leading});

  /// Builds the row icon (the page's own leading style).
  final Widget Function(IconData icon) leading;

  @override
  ConsumerState<SecurityGroup> createState() => _SecurityGroupState();
}

class _SecurityGroupState extends ConsumerState<SecurityGroup> {
  late bool _on = ref.read(biometricSetupProvider).enabled;
  bool _busy = false;

  Future<void> _toggle(bool want, BiometricKind kind) async {
    if (_busy) return;
    setState(() => _busy = true);
    final setup = ref.read(biometricSetupProvider);
    try {
      if (want) {
        final outcome = await setup.enable();
        if (!mounted) return;
        setState(() => _on = outcome == EnableOutcome.enabled);
        showEnableOutcome(context, outcome, kind);
      } else {
        await setup.disable();
        if (!mounted) return;
        setState(() => _on = false);
        showToast(context, '${kind.noun} is off.');
      }
      ref.read(appLockProvider.notifier).timeoutChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTimeout() async {
    final current = ref.read(lockTimeoutProvider);
    final picked = await showAppSheet<LockTimeout>(
      context,
      title: 'Lock after',
      builder: (ctx) => Column(
        children: [
          for (final t in LockTimeout.values)
            AppListRow(
              title: t.label,
              trailing: t == current
                  ? Icon(Icons.check_rounded, color: ctx.tokens.accentText)
                  : null,
              onTap: () => Navigator.of(ctx).pop(t),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await ref.read(lockTimeoutProvider.notifier).set(picked);
    ref.read(appLockProvider.notifier).timeoutChanged();
  }

  @override
  Widget build(BuildContext context) {
    final kind = ref.watch(biometricKindProvider).value ?? BiometricKind.none;
    if (!kind.available && !_on) return const SizedBox.shrink();
    final timeout = ref.watch(lockTimeoutProvider);
    return AppListGroup(
      title: 'Security',
      children: [
        AppListRow(
          title: kind.noun,
          subtitle: _on
              ? 'Locks when you leave the app.'
              : 'Skip typing your password.',
          leading: widget.leading(
            kind == BiometricKind.screenLock
                ? Icons.lock_open_rounded
                : Icons.fingerprint_rounded,
          ),
          trailing: Switch(
            key: const Key('biometric-switch'),
            value: _on,
            onChanged: _busy ? null : (v) => unawaited(_toggle(v, kind)),
          ),
        ),
        if (_on)
          AppListRow(
            title: 'Lock after',
            subtitle: timeout.label,
            leading: widget.leading(Icons.timer_outlined),
            chevron: true,
            onTap: () => unawaited(_pickTimeout()),
          ),
      ],
    );
  }
}
