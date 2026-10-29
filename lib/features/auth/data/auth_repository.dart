import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';

class LoginResult {
  const LoginResult({required this.token, this.expiresAt});

  final String token;
  final DateTime? expiresAt;
}

/// The code sent by e-mail: where it went and how long it lives.
class OtpChallenge {
  const OtpChallenge({
    required this.maskedEmail,
    required this.otpLength,
    required this.expiresInSeconds,
  });

  final String maskedEmail;
  final int otpLength;
  final int expiresInSeconds;
}

class ResetGrant {
  const ResetGrant({
    required this.token,
    required this.expiresInSeconds,
    required this.passwordMinLength,
  });

  final String token;
  final int expiresInSeconds;
  final int passwordMinLength;
}

/// All `/auth/*` and `/bootstrap` calls (AUTH-1..8).
class AuthRepository {
  const AuthRepository(this._api);

  final ApiClient _api;

  Future<LoginResult> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final res = await _api.post(
      '/auth/login',
      body: {
        'email': email.trim(),
        'password': password,
        'device_name': deviceName,
      },
    );
    return LoginResult(
      token: res.data['token'].toString(),
      expiresAt: DateTime.tryParse((res.data['expires_at'] ?? '').toString()),
    );
  }

  Future<Bootstrap> bootstrap() async {
    final res = await _api.get('/bootstrap');
    return Bootstrap.fromJson(res.data);
  }

  Future<void> logout() => _api.post('/auth/logout');

  Future<void> logoutEverywhere() => _api.post('/auth/logout-all');

  Future<OtpChallenge> forgotPassword(String email) async {
    final res = await _api.post(
      '/auth/forgot-password',
      body: {'email': email.trim()},
    );
    return _challenge(res);
  }

  Future<OtpChallenge> resendOtp(String email) async {
    final res = await _api.post(
      '/auth/resend-otp',
      body: {'email': email.trim()},
    );
    return _challenge(res);
  }

  Future<ResetGrant> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final res = await _api.post(
      '/auth/verify-otp',
      body: {'email': email.trim(), 'otp': otp},
    );
    return ResetGrant(
      token: res.data['reset_token'].toString(),
      expiresInSeconds:
          (res.data['expires_in_seconds'] as num?)?.toInt() ?? 900,
      passwordMinLength:
          (res.data['password_min_length'] as num?)?.toInt() ?? 6,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String password,
  }) {
    return _api.post(
      '/auth/reset-password',
      body: {
        'email': email.trim(),
        'reset_token': resetToken,
        'password': password,
        'password_confirmation': password,
      },
    );
  }

  OtpChallenge _challenge(ApiResponse res) => OtpChallenge(
    maskedEmail: (res.data['masked_email'] ?? 'your email').toString(),
    otpLength: (res.data['otp_length'] as num?)?.toInt() ?? 6,
    expiresInSeconds: (res.data['expires_in_seconds'] as num?)?.toInt() ?? 600,
  );
}
