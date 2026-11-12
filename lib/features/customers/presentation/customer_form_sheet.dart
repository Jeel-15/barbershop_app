import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The web's "Add New Customer" / "Update Customer" modal: Full Name, Email
/// (Optional), Phone Number, Status. Returns the saved customer, or null when
/// closed without saving.
Future<CustomerSummary?> showCustomerFormSheet(
  BuildContext context, {
  CustomerSummary? editing,
}) => showAppSheet<CustomerSummary>(
  context,
  title: editing == null ? 'Add New Customer' : 'Update Customer',
  builder: (_) => _CustomerForm(editing: editing),
);

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.editing});

  final CustomerSummary? editing;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _email = TextEditingController(text: widget.editing?.email);
  late final _phone = TextEditingController(text: widget.editing?.phone);
  late bool _active = widget.editing?.isActive ?? true;

  bool _busy = false;
  String? _nameError;
  String? _phoneError;
  String? _emailError;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    // The web's own checks, in the web's words.
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Please Enter Full Name' : null;
      _phoneError = _phone.text.trim().isEmpty
          ? 'Please Enter Phone No.'
          : null;
      _emailError = null;
    });
    if (_nameError != null || _phoneError != null) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final repo = ref.read(customersRepositoryProvider);
    final input = CustomerInput(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      isActive: _active,
    );
    try {
      final saved = widget.editing == null
          ? await repo.create(input)
          : await repo.update(widget.editing!.id, input);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _nameError = f.errorFor('full_name');
        _phoneError = f.errorFor('phone_number');
        _emailError = f.errorFor('email');
        _busy = false;
      });
      if (_nameError == null && _phoneError == null && _emailError == null) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Full Name *',
          hint: 'Enter Full Name',
          prefixIcon: Icons.person_outline_rounded,
          clearable: true,
          controller: _name,
          errorText: _nameError,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofocus: widget.editing == null,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Email (Optional)',
          hint: 'Enter Email Address',
          prefixIcon: Icons.mail_outline_rounded,
          clearable: true,
          validator: (v) =>
              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
              ? null
              : 'Enter a valid email address.',
          controller: _email,
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Phone Number *',
          hint: 'Enter Phone No.',
          prefixIcon: Icons.phone_outlined,
          clearable: true,
          controller: _phone,
          errorText: _phoneError,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          maxLength: 20,
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Status *', style: AppType.label.copyWith(color: t.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            AppChoiceChip(
              label: 'Active',
              selected: _active,
              onTap: () => setState(() => _active = true),
            ),
            AppChoiceChip(
              label: 'Deactive',
              selected: !_active,
              onTap: () => setState(() => _active = false),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        AppButton(
          label: widget.editing == null ? 'Add Customer' : 'Update Customer',
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}
