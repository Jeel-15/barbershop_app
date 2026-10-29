import 'package:barbershop_app/brand.dart';
import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/presentation/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Sign in with the staff / admin account. Messages are the server's own
/// sentences (the web's); every failure keeps what the user typed.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _email = TextEditingController(
    text: ref.read(appPrefsProvider).lastEmail ?? '',
  );
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _formError;
  String? _supportCode;
  bool _isInfo = false;
  int _shake = 0;

  @override
  void initState() {
    super.initState();
    final s = ref.read(sessionControllerProvider);
    if (s is SignedOut && s.message != null) {
      _formError = s.message;
      _isInfo = true;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _email.text.trim();
    String? e;
    String? p;
    if (email.isEmpty) {
      e = 'Enter your e-mail address.';
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      e = 'That does not look like an e-mail address.';
    }
    if (_password.text.isEmpty) p = 'Enter your password.';
    setState(() {
      _emailError = e;
      _passwordError = p;
      _formError = null;
      _supportCode = null;
    });
    return e == null && p == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .signIn(email: _email.text, password: _password.text);
      if (mounted) context.go('/app/home');
    } on ValidationFailure catch (f) {
      if (!mounted) return;
      AppHaptics.warning();
      setState(() {
        _shake++;
        _emailError = f.errorFor('email');
        _passwordError = f.errorFor('password');
        if (_emailError == null && _passwordError == null) {
          _formError = f.userMessage;
        }
        _isInfo = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      AppHaptics.warning();
      setState(() {
        _shake++;
        _formError = f.userMessage;
        _supportCode = f is ServerFailure ? f.requestId : null;
        _isInfo = false;
        if (f is UnauthorizedFailure) _password.clear();
      });
      if (f is UnauthorizedFailure) _passwordFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: AuthBackdrop(
        child: SafeArea(
          // The button column stays above the keyboard (Revolut / Peloton).
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.sm,
                    AppSpace.page,
                    AppSpace.lg,
                  ),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: RoundBackButton(
                            onPressed: () => context.canPop()
                                ? context.pop()
                                : context.go('/welcome'),
                          ),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _Hero(t: t),
                        const SizedBox(height: AppSpace.xxl),
                        if (_formError != null) ...[
                          AuthBanner(
                            message: _formError!,
                            info: _isInfo,
                            supportCode: _supportCode,
                          ),
                          const SizedBox(height: AppSpace.lg),
                        ],
                        Reveal(
                          delay: const Duration(milliseconds: 260),
                          child: ShakeOnChange(
                            trigger: _shake,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppTextField(
                                  label: 'E-mail',
                                  hint: 'you@rosenthalbarbershop.ca',
                                  controller: _email,
                                  prefixIcon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.username,
                                    AutofillHints.email,
                                  ],
                                  errorText: _emailError,
                                  enabled: !_busy,
                                  onChanged: (_) {
                                    if (_emailError != null) {
                                      setState(() => _emailError = null);
                                    }
                                  },
                                  onSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                ),
                                const SizedBox(height: AppSpace.lg),
                                AppTextField(
                                  label: 'Password',
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  obscure: true,
                                  prefixIcon: Icons.lock_outline_rounded,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  errorText: _passwordError,
                                  enabled: !_busy,
                                  onChanged: (_) {
                                    if (_passwordError != null) {
                                      setState(() => _passwordError = null);
                                    }
                                  },
                                  onSubmitted: (_) => _submit(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Reveal(
                          delay: const Duration(milliseconds: 340),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => context.push(
                                      '/forgot',
                                      extra: _email.text.trim(),
                                    ),
                              child: Text(
                                'Forgot password?',
                                style: AppType.label.copyWith(
                                  fontSize: 13.5,
                                  color: t.accentText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Reveal(
                delay: const Duration(milliseconds: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.sm,
                    AppSpace.page,
                    AppSpace.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: 'Sign in',
                        icon: Icons.lock_open_rounded,
                        loading: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: AppSpace.md),
                      Text(
                        'Staff and admin accounts only',
                        textAlign: TextAlign.center,
                        style: AppType.caption.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crest in a gold halo, brand line, serif headline.
class _Hero extends StatelessWidget {
  const _Hero({required this.t});

  final AppTokens t;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Hero(
          tag: crestHeroTag,
          child: SizedBox(
            width: 104,
            height: 104 * RosenthalCrest.aspect,
            child: RosenthalCrest(),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Reveal(
          delay: const Duration(milliseconds: 60),
          child: Text(
            AppBrand.name.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppType.overline.copyWith(
              color: t.accentText,
              letterSpacing: 3.2,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Reveal(
          delay: const Duration(milliseconds: 140),
          child: Text(
            'Welcome back',
            textAlign: TextAlign.center,
            style: AppText.display(36, color: t.text, height: 1.1),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Reveal(
          delay: const Duration(milliseconds: 200),
          child: Text(
            'Sign in to run the shop from your pocket.',
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}
