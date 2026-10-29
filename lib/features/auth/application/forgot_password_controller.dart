import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ResetStep { email, code, password, done }

/// State of the 4-step "forgot password" flow (e-mail, 6-digit code, new
/// password, done). Server messages are shown as they come: they are the
/// web's own sentences.
class ForgotPasswordState {
  const ForgotPasswordState({
    this.step = ResetStep.email,
    this.email = '',
    this.maskedEmail = '',
    this.otpLength = 6,
    this.passwordMinLength = 6,
    this.resendAvailableAt,
    this.resetToken,
    this.busy = false,
    this.error,
    this.fieldErrors = const {},
    this.supportCode,
    this.notice,
  });

  final ResetStep step;
  final String email;
  final String maskedEmail;
  final int otpLength;
  final int passwordMinLength;

  /// The "Resend code" button unlocks at this time.
  final DateTime? resendAvailableAt;
  final String? resetToken;
  final bool busy;

  /// Whole-form error (network, rate limit...).
  final String? error;
  final Map<String, String> fieldErrors;
  final String? supportCode;

  /// Friendly note, e.g. "A new code has been sent".
  final String? notice;

  ForgotPasswordState copyWith({
    ResetStep? step,
    String? email,
    String? maskedEmail,
    int? otpLength,
    int? passwordMinLength,
    DateTime? resendAvailableAt,
    String? resetToken,
    bool? busy,
    String? error,
    Map<String, String>? fieldErrors,
    String? supportCode,
    String? notice,
    bool clearMessages = false,
  }) {
    return ForgotPasswordState(
      step: step ?? this.step,
      email: email ?? this.email,
      maskedEmail: maskedEmail ?? this.maskedEmail,
      otpLength: otpLength ?? this.otpLength,
      passwordMinLength: passwordMinLength ?? this.passwordMinLength,
      resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
      resetToken: resetToken ?? this.resetToken,
      busy: busy ?? this.busy,
      error: error ?? (clearMessages ? null : this.error),
      fieldErrors: fieldErrors ?? (clearMessages ? const {} : this.fieldErrors),
      supportCode: supportCode ?? (clearMessages ? null : this.supportCode),
      notice: notice ?? (clearMessages ? null : this.notice),
    );
  }
}

final forgotPasswordProvider =
    NotifierProvider.autoDispose<ForgotPasswordController, ForgotPasswordState>(
      ForgotPasswordController.new,
    );

class ForgotPasswordController extends Notifier<ForgotPasswordState> {
  /// The API allows 3 resends per 10 minutes; a 45 s pause keeps people well inside that.
  static const resendPause = Duration(seconds: 45);

  /// Fixed in tests.
  static DateTime Function() clock = DateTime.now;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  ForgotPasswordState build() => const ForgotPasswordState();

  /// Starts the flow with an e-mail the user already typed (from Sign in).
  void prefill(String email) {
    if (state.email.isEmpty) state = state.copyWith(email: email);
  }

  Future<void> sendCode(String email) async {
    final clean = email.trim();
    if (!_looksLikeEmail(clean)) {
      state = state.copyWith(
        clearMessages: true,
        fieldErrors: {'email': 'Enter your registered e-mail address.'},
      );
      return;
    }
    await _run(() async {
      final c = await _repo.forgotPassword(clean);
      state = state.copyWith(
        step: ResetStep.code,
        email: clean,
        maskedEmail: c.maskedEmail,
        otpLength: c.otpLength,
        resendAvailableAt: clock().add(resendPause),
        clearMessages: true,
      );
    });
  }

  Future<void> resend() async {
    final at = state.resendAvailableAt;
    if (at != null && clock().isBefore(at)) return;
    await _run(() async {
      final c = await _repo.resendOtp(state.email);
      state = state.copyWith(
        maskedEmail: c.maskedEmail,
        resendAvailableAt: clock().add(resendPause),
        clearMessages: true,
        notice: 'A new code is on its way. The old one no longer works.',
      );
    });
  }

  Future<void> verify(String code) async {
    if (code.length != state.otpLength) return;
    await _run(() async {
      final grant = await _repo.verifyOtp(email: state.email, otp: code);
      state = state.copyWith(
        step: ResetStep.password,
        resetToken: grant.token,
        passwordMinLength: grant.passwordMinLength,
        clearMessages: true,
      );
    });
  }

  Future<void> setPassword(String password, String confirm) async {
    if (password != confirm) {
      state = state.copyWith(
        clearMessages: true,
        fieldErrors: {'password': 'The two passwords do not match.'},
      );
      return;
    }
    await _run(() async {
      await _repo.resetPassword(
        email: state.email,
        resetToken: state.resetToken ?? '',
        password: password,
      );
      state = state.copyWith(step: ResetStep.done, clearMessages: true);
    });
  }

  /// One step back (the screens' back arrow).
  void back() {
    final prev = switch (state.step) {
      ResetStep.code => ResetStep.email,
      ResetStep.password => ResetStep.code,
      _ => state.step,
    };
    state = state.copyWith(step: prev, clearMessages: true);
  }

  Future<void> _run(Future<void> Function() action) async {
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      await action();
    } on ValidationFailure catch (f) {
      state = state.copyWith(
        fieldErrors: {
          for (final e in f.fieldErrors.entries) e.key: e.value.first,
        },
        error: f.fieldErrors.isEmpty ? f.userMessage : null,
        supportCode: f.requestId,
      );
      // An expired/used reset token cannot be fixed on this step.
      if (f.fieldErrors.containsKey('reset_token')) {
        state = state.copyWith(
          step: ResetStep.email,
          error: f.fieldErrors['reset_token']!.first,
        );
      }
    } on Failure catch (f) {
      state = state.copyWith(error: f.userMessage, supportCode: f.requestId);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
}
