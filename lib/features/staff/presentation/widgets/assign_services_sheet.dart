import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The web's "Assign Services" modal (Staff Service page): tick the services
/// this barber does, then Save Assignments.
Future<bool?> showAssignServicesSheet(
  BuildContext context,
  StaffMember member,
) => showAppSheet<bool>(
  context,
  title: 'Assign Services',
  builder: (_) => _AssignForm(member: member),
);

class _AssignForm extends ConsumerStatefulWidget {
  const _AssignForm({required this.member});

  final StaffMember member;

  @override
  ConsumerState<_AssignForm> createState() => _AssignFormState();
}

class _AssignFormState extends ConsumerState<_AssignForm> {
  Set<int>? _picked;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final ids = await ref
          .read(staffRepositoryProvider)
          .assignedServices(widget.member.id);
      if (mounted) setState(() => _picked = ids.toSet());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(staffRepositoryProvider)
          .assignServices(widget.member.id, _picked!.toList()..sort());
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, msg, kind: ToastKind.success);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final options = ref.watch(staffFormOptionsProvider);
    final picked = _picked;
    if (_error != null) {
      return ErrorState(
        message: _error is Failure
            ? (_error! as Failure).userMessage
            : 'Could not load the services.',
        onRetry: _load,
      );
    }
    if (picked == null || options.value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: SkeletonRows(count: 4),
      );
    }
    final services = options.value!.services;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.member.name,
          style: AppType.bodyStrong.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.md),
        for (final s in services)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: picked.contains(s.id),
            title: Text(s.name, style: AppType.body.copyWith(color: t.text)),
            onChanged: (v) => setState(() {
              if (v == true) {
                picked.add(s.id);
              } else {
                picked.remove(s.id);
              }
            }),
          ),
        const SizedBox(height: AppSpace.lg),
        AppButton(label: 'Save Assignments', loading: _busy, onPressed: _save),
      ],
    );
  }
}
