import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/staff/domain/staff_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The web's "Change Password" modal: New Password *, Confirm New Password *.
Future<void> showChangePasswordSheet(
  BuildContext context,
  StaffMember member,
) => showAppSheet<void>(
  context,
  title: 'Change Password',
  builder: (_) => _PasswordForm(member: member),
);

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm({required this.member});

  final StaffMember member;

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _newError;
  String? _confirmError;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // The web's own checks and words.
    final p = _new.text;
    final c = _confirm.text;
    setState(() {
      _newError = p.isEmpty
          ? 'Please enter a new password'
          : p.length < 6
          ? 'Password must be at least 6 characters long'
          : null;
      _confirmError = c.isEmpty
          ? 'Please confirm your password'
          : c != p
          ? 'Passwords do not match'
          : null;
    });
    if (_newError != null || _confirmError != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(staffRepositoryProvider)
          .changePassword(widget.member.id, p, c);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, msg, kind: ToastKind.success);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _newError = f.errorFor('new_password');
        _confirmError = f.errorFor('confirm_password');
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final eye = IconButton(
      tooltip: _show ? 'Hide' : 'Show',
      icon: Icon(
        _show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 20,
        color: t.textMuted,
      ),
      onPressed: () => setState(() => _show = !_show),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.member.name,
          style: AppType.body.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'New Password *',
          controller: _new,
          errorText: _newError,
          obscure: !_show,
          suffix: eye,
          textInputAction: TextInputAction.next,
          autofocus: true,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Confirm New Password *',
          controller: _confirm,
          errorText: _confirmError,
          obscure: !_show,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(
          label: 'Update Password',
          icon: Icons.lock_rounded,
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}
