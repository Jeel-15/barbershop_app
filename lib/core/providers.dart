import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/env.dart';
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

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Phase 1 replaces this with "clear the session and go to Sign in".
final unauthorizedHandlerProvider = Provider<void Function()>((ref) => () {});

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  return ApiClient(
    baseUrl: Env.apiBaseUrl,
    readToken: tokens.read,
    onUnauthorized: () => ref.read(unauthorizedHandlerProvider)(),
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
