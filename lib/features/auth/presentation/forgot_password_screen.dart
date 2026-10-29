import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/forgot_password_controller.dart';
import 'package:barbershop_app/features/auth/presentation/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// E-mail -> 6-digit code -> new password -> done. One screen, the step
/// slides in place so the back arrow and the keyboard behave.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _otpKey = GlobalKey<OtpFieldState>();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _back(ForgotPasswordState s) {
    if (s.step == ResetStep.email || s.step == ResetStep.done) {
      context.canPop() ? context.pop() : context.go('/sign-in');
    } else {
      ref.read(forgotPasswordProvider.notifier).back();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(forgotPasswordProvider);
    final t = context.tokens;
    return PopScope(
      canPop: s.step == ResetStep.email || s.step == ResetStep.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(forgotPasswordProvider.notifier).back();
      },
      child: Scaffold(
        body: AuthBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: s.step == ResetStep.done
                      ? const SizedBox(height: 48)
                      : Padding(
                          padding: const EdgeInsets.only(left: AppSpace.page),
                          child: RoundBackButton(
                            onPressed: s.busy ? null : () => _back(s),
                          ),
                        ),
                ),
                if (s.step != ResetStep.done) _Progress(step: s.step),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.page,
                      AppSpace.xl,
                      AppSpace.page,
                      AppSpace.xxl,
                    ),
                    child: AnimatedSwitcher(
                      duration: AppMotion.normal,
                      switchInCurve: AppMotion.curve,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0.06, 0),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(s.step),
                        child: _step(s, t),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(ForgotPasswordState s, AppTokens t) {
    final c = ref.read(forgotPasswordProvider.notifier);
    switch (s.step) {
      case ResetStep.email:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Heading(
              icon: Icons.lock_reset_rounded,
              title: 'Forgot password?',
              body:
                  'Enter your account e-mail and we will send a 6-digit code.',
            ),
            const SizedBox(height: AppSpace.xl),
            if (s.error != null) ...[
              AuthBanner(message: s.error!, supportCode: s.supportCode),
              const SizedBox(height: AppSpace.lg),
            ],
            AppTextField(
              label: 'E-mail',
              controller: _email,
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              errorText: s.fieldErrors['email'],
              enabled: !s.busy,
              onSubmitted: (_) => c.sendCode(_email.text),
            ),
            const SizedBox(height: AppSpace.xl),
            AppButton(
              label: 'Send code',
              icon: Icons.send_rounded,
              loading: s.busy,
              onPressed: () => c.sendCode(_email.text),
            ),
          ],
        );
      case ResetStep.code:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(
              icon: Icons.mark_email_read_outlined,
              title: 'Enter the code',
              body:
                  'We sent a ${s.otpLength}-digit code to ${s.maskedEmail.isEmpty ? s.email : s.maskedEmail}.',
            ),
            const SizedBox(height: AppSpace.xl),
            if (s.error != null) ...[
              AuthBanner(message: s.error!, supportCode: s.supportCode),
              const SizedBox(height: AppSpace.lg),
            ],
            if (s.notice != null) ...[
              AuthBanner(message: s.notice!, info: true),
              const SizedBox(height: AppSpace.lg),
            ],
            OtpField(
              key: _otpKey,
              length: s.otpLength,
              enabled: !s.busy,
              errorText: s.fieldErrors['otp'],
              onCompleted: c.verify,
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ResendTimer(
                  availableAt: s.resendAvailableAt,
                  clock: ForgotPasswordController.clock,
                  busy: s.busy,
                  onResend: () async {
                    await c.resend();
                    _otpKey.currentState?.clear();
                  },
                ),
                TextButton.icon(
                  onPressed: s.busy
                      ? null
                      : () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          _otpKey.currentState?.setCode(data?.text ?? '');
                        },
                  icon: Icon(
                    Icons.content_paste_rounded,
                    size: 18,
                    color: t.accentText,
                  ),
                  label: Text(
                    'Paste',
                    style: AppType.label.copyWith(color: t.accentText),
                  ),
                ),
              ],
            ),
            if (s.busy)
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.lg),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
          ],
        );
      case ResetStep.password:
        final p = _password.text;
        final okLen = p.length >= s.passwordMinLength;
        final okMatch = p.isNotEmpty && p == _confirm.text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Heading(
              icon: Icons.password_rounded,
              title: 'New password',
              body: 'Choose a password you have not used before.',
            ),
            const SizedBox(height: AppSpace.xl),
            if (s.error != null) ...[
              AuthBanner(message: s.error!, supportCode: s.supportCode),
              const SizedBox(height: AppSpace.lg),
            ],
            AppTextField(
              label: 'New password',
              controller: _password,
              obscure: true,
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              errorText: s.fieldErrors['password'],
              enabled: !s.busy,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpace.lg),
            AppTextField(
              label: 'Confirm password',
              controller: _confirm,
              obscure: true,
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !s.busy,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => c.setPassword(_password.text, _confirm.text),
            ),
            const SizedBox(height: AppSpace.md),
            RuleRow('At least ${s.passwordMinLength} characters', ok: okLen),
            RuleRow('Both passwords match', ok: okMatch),
            const SizedBox(height: AppSpace.xl),
            AppButton(
              label: 'Save password',
              icon: Icons.check_rounded,
              loading: s.busy,
              onPressed: okLen && okMatch
                  ? () => c.setPassword(_password.text, _confirm.text)
                  : null,
            ),
          ],
        );
      case ResetStep.done:
        return Column(
          children: [
            const SizedBox(height: AppSpace.xxl),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.success.withValues(alpha: 0.14),
                border: Border.all(color: t.success.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.check_rounded, size: 48, color: t.success),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(
              'Password changed',
              style: AppType.largeTitle.copyWith(color: t.text),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in with your new password. Other devices have been signed out.',
              style: AppType.body.copyWith(color: t.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.xxl),
            AppButton(
              label: 'Back to sign in',
              icon: Icons.lock_open_rounded,
              onPressed: () => context.go('/sign-in'),
            ),
          ],
        );
    }
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.accent.withValues(alpha: 0.12),
            border: Border.all(color: t.accent.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 32, color: t.accentText),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.display(32, color: t.text, height: 1.1),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppType.body.copyWith(color: t.textSecondary),
        ),
      ],
    );
  }
}

/// Three dots: e-mail, code, password.
class _Progress extends StatelessWidget {
  const _Progress({required this.step});

  final ResetStep step;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final index = step.index;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedContainer(
            duration: AppMotion.normal,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i <= index ? t.accent : t.border,
            ),
          ),
      ],
    );
  }
}
