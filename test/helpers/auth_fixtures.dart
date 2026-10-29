import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/storage/storage.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/data/auth_repository.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_fixtures.dart';
import 'home_fixtures.dart';

/// `/bootstrap` answer as the real API sends it (trimmed). [modules] overrides flags.
Map<String, dynamic> bootstrapJson({
  String name = 'API Admin',
  String role = 'Admin',
  bool isStaff = false,
  Map<String, bool>? modules,
  List<String> permissions = const ['appointments.view'],
  String minVersion = '1.0.0',
  String latestVersion = '1.0.0',
}) {
  final base = <String, bool>{
    'dashboard': true,
    'appointments': true,
    'calendar': true,
    'invoices': true,
    'invoice_write': true,
    'reports': true,
    'staff_report': true,
    'customers': true,
    'services': true,
    'staff': true,
    'settings': true,
    'roles': true,
    'profile': true,
  };
  return {
    'user': {
      'id': 1,
      'name': name,
      'email': 'apitest.admin@rosen.test',
      'phone': null,
      'role': role,
      'roles': [role],
      'is_staff': isStaff,
      'is_barber': isStaff,
      'profile_image_url': null,
      'permissions': permissions,
      'modules': {...base, ...?modules},
      'home': 'dashboard',
    },
    'shop': {'name': 'Rosenthal Barbershop'},
    'currency': {'code': 'CAD', 'symbol': r'$'},
    'timezone': 'America/Edmonton',
    'payment_methods': [
      {'id': 1, 'name': 'Cash'},
    ],
    // Index = status code (pending, completed, cancelled, confirmed, rescheduled).
    // The web's buttons per status (Complete = the invoice page).
    'appointment_actions': [
      ['confirm', 'complete', 'cancel', 'reschedule', 'view'],
      ['view'],
      ['reschedule', 'view'],
      ['cancel', 'complete', 'view'],
      ['confirm', 'complete', 'cancel', 'view'],
    ],
    'slot_step_minutes': 10,
    'shop_hours': <Object>[],
    'limits': {'per_page_max': 50, 'upload_max_kb': 2048},
    'app': {
      'api_version': 'v1',
      'build': 'test',
      'min_app_version': minVersion,
      'latest_app_version': latestVersion,
      'feature_flags': <String, bool>{},
    },
  };
}

Bootstrap adminBootstrap() => Bootstrap.fromJson(bootstrapJson());

/// The admin with these permissions (e.g. `Pos_invoice-Edit`).
Bootstrap adminBootstrapWith(List<String> permissions) =>
    Bootstrap.fromJson(bootstrapJson(permissions: permissions));

Bootstrap staffBootstrap() => Bootstrap.fromJson(
  bootstrapJson(
    name: 'API Staff',
    role: 'Staff',
    isStaff: true,
    modules: {
      'invoice_write': false,
      'calendar': false,
      'staff': false,
      'roles': false,
      'settings': false,
      'reports': false,
    },
  ),
);

/// Scripted stand-in for the API: set what each call should do.
class FakeAuthRepository implements AuthRepository {
  Bootstrap? bootstrapResult;
  Failure? bootstrapFailure;
  Failure? loginFailure;
  Failure? verifyFailure;
  Failure? forgotFailure;
  final calls = <String>[];

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    calls.add('login:$email');
    if (loginFailure != null) throw loginFailure!;
    return const LoginResult(token: 'tok-123');
  }

  @override
  Future<Bootstrap> bootstrap() async {
    calls.add('bootstrap');
    if (bootstrapFailure != null) throw bootstrapFailure!;
    return bootstrapResult ?? adminBootstrap();
  }

  @override
  Future<void> logout() async => calls.add('logout');

  @override
  Future<void> logoutEverywhere() async => calls.add('logout-all');

  @override
  Future<OtpChallenge> forgotPassword(String email) async {
    calls.add('forgot:$email');
    if (forgotFailure != null) throw forgotFailure!;
    return const OtpChallenge(
      maskedEmail: 'a***@rosen.test',
      otpLength: 6,
      expiresInSeconds: 600,
    );
  }

  @override
  Future<OtpChallenge> resendOtp(String email) async {
    calls.add('resend:$email');
    return const OtpChallenge(
      maskedEmail: 'a***@rosen.test',
      otpLength: 6,
      expiresInSeconds: 600,
    );
  }

  @override
  Future<ResetGrant> verifyOtp({
    required String email,
    required String otp,
  }) async {
    calls.add('verify:$otp');
    if (verifyFailure != null) throw verifyFailure!;
    return const ResetGrant(
      token: 'reset-tok',
      expiresInSeconds: 900,
      passwordMinLength: 6,
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String password,
  }) async {
    calls.add('reset:$resetToken');
  }
}

/// Everything a session test needs, with in-memory storage.
class AuthHarness {
  AuthHarness._(this.container, this.repo, this.tokens);

  final ProviderContainer container;
  final FakeAuthRepository repo;
  final MemoryTokenStore tokens;

  static Future<AuthHarness> create({
    FakeAuthRepository? repo,
    String? savedToken,
    AppVersion version = const AppVersion(1, 0, 0),
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final fake = repo ?? FakeAuthRepository();
    final tokens = MemoryTokenStore();
    if (savedToken != null) await tokens.write(savedToken);
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sp),
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(fake),
        appVersionProvider.overrideWithValue(version),
      ],
    );
    return AuthHarness._(container, fake, tokens);
  }

  List<Override> get overrides => [
    sharedPrefsProvider.overrideWithValue(container.read(sharedPrefsProvider)),
    tokenStoreProvider.overrideWithValue(tokens),
    authRepositoryProvider.overrideWithValue(repo),
    appVersionProvider.overrideWithValue(container.read(appVersionProvider)),
    // Home would call the real API otherwise.
    homeProvider.overrideWith(() => FixedHome(adminHomeRaw())),
    calendarProvider.overrideWith(
      () => FixedCalendar(calendarWindow('2026-10-26')),
    ),
    dayAvailabilityProvider.overrideWith(
      (ref, date) async => DayAvailability.fallback(),
    ),
  ];

  /// What the app has saved so far, to start a second "launch" from it.
  Map<String, Object> prefsSnapshot() {
    final sp = container.read(sharedPrefsProvider);
    return {for (final k in sp.getKeys()) k: sp.get(k)!};
  }

  /// Lets the cold-start `restore()` finish.
  Future<SessionState> settle() async {
    container.read(sessionControllerProvider);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(sessionControllerProvider);
  }
}
