import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/shop/data/shop_repository.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _Tab { general, contact, payment }

/// The web's Settings ("Manage business settings, payments, and account
/// security"): General Settings, Contact Details and Payment Options.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  _Tab _tab = _Tab.general;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(shopSettingsProvider);
    final s = async.value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.sm,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  RoundBackButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/app/more'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          'Manage business settings, payments, and account security',
                          maxLines: 2,
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ChipsRow<_Tab>(
              compact: true,
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              options: const [
                ChipOption(_Tab.general, 'General Settings'),
                ChipOption(_Tab.contact, 'Contact Details'),
                ChipOption(_Tab.payment, 'Payment Options'),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Divider(height: 1, color: t.border),
            Expanded(
              child: s != null
                  ? switch (_tab) {
                      _Tab.general => _General(
                        key: const ValueKey('general'),
                        settings: s.general,
                      ),
                      _Tab.contact => _Contact(
                        key: const ValueKey('contact'),
                        settings: s.contact,
                      ),
                      _Tab.payment => const _PaymentTab(),
                    }
                  : async.hasError
                  ? ErrorState(
                      message: async.error is Failure
                          ? (async.error! as Failure).userMessage
                          : 'Could not load the settings.',
                      onRetry: () => ref.invalidate(shopSettingsProvider),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(AppSpace.page),
                      child: SkeletonRows(count: 4),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A form tab: scrolling fields and a pinned Update button.
class _FormFrame extends StatelessWidget {
  const _FormFrame({
    required this.children,
    required this.label,
    required this.busy,
    required this.onSave,
  });

  final List<Widget> children;
  final String label;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.lg,
              AppSpace.page,
              AppSpace.xl,
            ),
            children: children,
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            AppSpace.md,
            AppSpace.page,
            AppSpace.md,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: AppButton(
            label: label,
            icon: Icons.check_rounded,
            loading: busy,
            onPressed: onSave,
          ),
        ),
      ],
    );
  }
}

class _General extends ConsumerStatefulWidget {
  const _General({super.key, required this.settings});

  final GeneralSettings settings;

  @override
  ConsumerState<_General> createState() => _GeneralState();
}

class _GeneralState extends ConsumerState<_General> {
  late final _reminder = TextEditingController(
    text: '${widget.settings.reminderDays}',
  );
  late final _duration = TextEditingController(
    text: '${widget.settings.defaultDuration}',
  );
  late final _fee = TextEditingController(
    text: widget.settings.serviceFee.toApi(),
  );
  late bool _mail = widget.settings.invoiceMail;
  final _errors = <String, String>{};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_reminder, _duration, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    final e = <String, String>{};
    final r = int.tryParse(_reminder.text.trim());
    if (r == null || r < 1) e['reminder'] = 'Enter a whole number, 1 or more';
    final d = int.tryParse(_duration.text.trim());
    if (d == null || d < 1) e['duration'] = 'Enter a whole number, 1 or more';
    final f = double.tryParse(_fee.text.trim());
    if (f == null || f < 0) e['fee'] = 'Enter an amount, 0 or more';
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(shopRepositoryProvider)
          .saveGeneral(
            reminderDays: int.parse(_reminder.text.trim()),
            defaultDuration: int.parse(_duration.text.trim()),
            serviceFee: _fee.text,
            invoiceMail: _mail,
          );
      ref.invalidate(shopSettingsProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, msg, kind: ToastKind.success);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final e in {
          'service_reminder_day': 'reminder',
          'service_default_duration': 'duration',
          'service_fee': 'fee',
        }.entries) {
          final m = f.errorFor(e.key);
          if (m != null) _errors[e.value] = m;
        }
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
    return _FormFrame(
      label: 'Update',
      busy: _busy,
      onSave: _save,
      children: [
        Text(
          'General Business Settings',
          style: AppType.subheading.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Service Reminder Day',
          hint: 'Enter Day',
          controller: _reminder,
          errorText: _errors['reminder'],
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Service Default Duration (Minutes)',
          hint: 'Enter Duration',
          controller: _duration,
          errorText: _errors['duration'],
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpace.lg),
        AppTextField(
          label: 'Service Fee',
          hint: 'Enter Service Fee',
          controller: _fee,
          errorText: _errors['fee'],
          helperText:
              'Deducted per service before staff commission (not shown on invoice).',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpace.lg),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice Mail Send',
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              Switch(value: _mail, onChanged: (v) => setState(() => _mail = v)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Contact extends ConsumerStatefulWidget {
  const _Contact({super.key, required this.settings});

  final ContactSettings settings;

  @override
  ConsumerState<_Contact> createState() => _ContactState();
}

class _ContactState extends ConsumerState<_Contact> {
  late final Map<String, TextEditingController> _c = {
    for (final k in ContactSettings.keys)
      k: TextEditingController(text: widget.settings[k]),
  };
  final _errors = <String, String>{};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    final e = <String, String>{};
    String v(String k) => _c[k]!.text.trim();
    bool bad(String email) =>
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (v('contact_address').isEmpty) {
      e['contact_address'] = 'The contact address field is required.';
    }
    if (v('contact_phone').isEmpty) {
      e['contact_phone'] = 'The contact phone field is required.';
    }
    if (v('contact_email').isEmpty) {
      e['contact_email'] = 'The contact email field is required.';
    } else if (bad(v('contact_email'))) {
      e['contact_email'] = 'The contact email must be a valid email address.';
    }
    if (v('support_email').isNotEmpty && bad(v('support_email'))) {
      e['support_email'] = 'The support email must be a valid email address.';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final msg = await ref.read(shopRepositoryProvider).saveContact({
        for (final e in _c.entries) e.key: e.value.text,
      });
      ref.invalidate(shopSettingsProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, msg, kind: ToastKind.success);
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        for (final k in ContactSettings.keys) {
          final m = f.errorFor(k);
          if (m != null) _errors[k] = m;
        }
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    TextInputType? type,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.lg),
    child: AppTextField(
      label: label,
      hint: hint,
      controller: _c[key],
      errorText: _errors[key],
      keyboardType: type,
      maxLines: lines,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _FormFrame(
      label: 'Update Contact Details',
      busy: _busy,
      onSave: _save,
      children: [
        Text(
          'Contact Details',
          style: AppType.subheading.copyWith(color: t.text),
        ),
        const SizedBox(height: 4),
        Text(
          'These details appear in the website footer, contact page, header, and booking pages.',
          style: AppType.caption.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        _field('footer_about', 'Footer About Text', lines: 3),
        _field('contact_address', 'Address *', lines: 2),
        _field('contact_phone', 'Phone *', type: TextInputType.phone),
        _field('whatsapp', 'WhatsApp Number', type: TextInputType.phone),
        _field(
          'contact_email',
          'Info Email *',
          type: TextInputType.emailAddress,
        ),
        _field(
          'support_email',
          'Support Email',
          type: TextInputType.emailAddress,
        ),
        _field('website_url', 'Website URL', type: TextInputType.url),
        Text(
          'Social Media Links',
          style: AppType.subheading.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.md),
        _field('facebook_url', 'Facebook', type: TextInputType.url),
        _field('instagram_url', 'Instagram', type: TextInputType.url),
        _field('tiktok_url', 'TikTok', type: TextInputType.url),
        _field('youtube_url', 'YouTube', type: TextInputType.url),
        _field('twitter_url', 'Twitter / X', type: TextInputType.url),
        _field('linkedin_url', 'LinkedIn', type: TextInputType.url),
      ],
    );
  }
}

class _PaymentTab extends StatelessWidget {
  const _PaymentTab();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.page),
      children: [
        Text(
          'Payment Options',
          style: AppType.subheading.copyWith(color: t.text),
        ),
        const SizedBox(height: AppSpace.md),
        AppListGroup(
          children: [
            AppListRow(
              title: 'Custom Payment Methods',
              subtitle: 'Add, rename or remove the ways customers can pay',
              leading: Icon(Icons.credit_card_rounded, color: t.accentText),
              chevron: true,
              onTap: () => context.push('/app/payment-methods'),
            ),
          ],
        ),
      ],
    );
  }
}
