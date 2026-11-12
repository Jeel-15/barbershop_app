import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/application/session_controller.dart';
import 'config/env.dart';
import 'security/biometric_capability.dart';
import 'security/biometric_vault.dart';
import 'network/api_client.dart';
import 'storage/storage.dart';

/// Overridden in `bootstrap()` with the real instance (it must be loaded
/// before the first frame).
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPrefsProvider)),
);

final readCacheProvider = Provider<ReadCache>(
  (ref) => ReadCache(ref.watch(sharedPrefsProvider)),
);

final biometricVaultProvider = Provider<BiometricVault>(
  (ref) => SecureBiometricVault(),
);

final biometricCapabilityProvider = Provider<BiometricCapability>(
  (ref) => LocalAuthCapability(),
);

/// The sign-in token: normal secure storage, or the fingerprint-locked vault
/// when the person turned that on (see `lib/features/lock`).
final tokenStoreProvider = Provider<ProtectableTokenStore>((ref) {
  final prefs = ref.watch(appPrefsProvider);
  return ProtectedTokenStore(
    plain: SecureTokenStore(),
    vault: ref.watch(biometricVaultProvider),
    readProtected: () => prefs.biometricEnabled,
    writeProtected: prefs.setBiometricEnabled,
  );
});

/// Phase 1 replaces this with "clear the session and go to Sign in".
final unauthorizedHandlerProvider = Provider<void Function()>((ref) => () {});

/// A signed-in answer showed a permissions version other than the one the app
/// holds. `bootstrap()` connects this to the session (like the 401 handler).
final permissionsVersionHandlerProvider = Provider<void Function(String)>(
  (ref) => (_) {},
);

/// A 403 came back: the user may have lost a permission.
final forbiddenHandlerProvider = Provider<void Function()>((ref) => () {});

/// The API address in use. Production always uses the build's own; test builds
/// can switch (local PC, tunnel, live) from the Connection screen, no rebuild.
class ApiBaseUrl extends Notifier<String> {
  static const defaultPath = '/rosen_barber/public/api/v1';

  @override
  String build() => Env.isProd
      ? Env.apiBaseUrl
      : (ref.watch(appPrefsProvider).serverUrl ?? Env.apiBaseUrl);

  /// Turns what a person pastes into a full API address, or null if it is not
  /// one: "abc.ngrok-free.app" becomes
  /// "https://abc.ngrok-free.app/rosen_barber/public/api/v1".
  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty || s.contains(' ')) return null;
    if (!s.contains('://')) {
      final local = RegExp(r'^(localhost|127\.|10\.|192\.168\.)').hasMatch(s);
      s = '${local ? 'http' : 'https'}://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isEmpty) path = defaultPath;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  /// Switches server. The old sign-in belongs to the old server, so it ends.
  Future<void> use(String? url) async {
    if (Env.isProd) return;
    final prefs = ref.read(appPrefsProvider);
    if (ref.read(sessionControllerProvider) is SignedIn) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    } else {
      await ref.read(readCacheProvider).clearAll();
    }
    await prefs.setServerUrl(url);
    if (url != null) await prefs.rememberServer(url);
    state = url ?? Env.apiBaseUrl;
  }
}

final apiBaseUrlProvider = NotifierProvider<ApiBaseUrl, String>(ApiBaseUrl.new);

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  return ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    // A free ngrok tunnel answers browsers with a warning page; this skips it.
    headers: const {'ngrok-skip-browser-warning': '1'},
    readToken: tokens.read,
    onUnauthorized: () => ref.read(unauthorizedHandlerProvider)(),
    onPermissionsVersion: (v) => ref.read(permissionsVersionHandlerProvider)(v),
    onForbidden: () => ref.read(forbiddenHandlerProvider)(),
  );
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(appPrefsProvider).themeMode;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(appPrefsProvider).setThemeMode(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
