import 'dart:convert';

import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the sign-in token lives. Secure storage in the app, memory in tests.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// A [TokenStore] whose token can be locked behind the phone's fingerprint /
/// screen lock (the "biometric vault"). While protected, the token is not on
/// disk in the open: it is decrypted only after the person proves who they
/// are, then kept in memory so the network layer never opens a prompt.
abstract interface class ProtectableTokenStore implements TokenStore {
  /// True when the token lives in the vault (feature on).
  bool get isProtected;

  /// Opens the phone's prompt and returns the token (also keeps it in memory).
  /// Throws [VaultException]. Null: the vault is empty.
  Future<String?> unlock();

  /// Moves the signed-in token into the vault (opens the prompt once).
  /// Throws [VaultException]; on failure the token stays where it was.
  Future<void> protect();

  /// Moves the token back to the normal secure storage (no prompt).
  Future<void> unprotect();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _key = 'auth_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// The real store: the normal secure storage while the feature is off, the
/// biometric vault while it is on. [read] is answered from memory once the
/// token is known, so only [unlock] and [protect] ever open a prompt.
class ProtectedTokenStore implements ProtectableTokenStore {
  ProtectedTokenStore({
    required this._plain,
    required this._vault,
    required this._readProtected,
    required this._writeProtected,
  });

  final TokenStore _plain;
  final BiometricVault _vault;
  final bool Function() _readProtected;
  final Future<void> Function(bool) _writeProtected;

  String? _cache;

  @override
  bool get isProtected => _readProtected();

  @override
  Future<String?> read() async {
    final cached = _cache;
    if (cached != null) return cached;
    // Protected and not unlocked yet: no token, and certainly no prompt.
    if (isProtected) return null;
    return _cache = await _plain.read();
  }

  @override
  Future<void> write(String token) async {
    _cache = token;
    // A new sign-in always starts unprotected (sign-out cleared the vault).
    await _plain.write(token);
  }

  @override
  Future<void> clear() async {
    _cache = null;
    await _plain.clear();
    await _vault.delete();
    await _writeProtected(false);
  }

  @override
  Future<String?> unlock() async {
    final token = await _vault.read();
    _cache = token;
    return token;
  }

  @override
  Future<void> protect() async {
    final token = _cache ?? await _plain.read();
    if (token == null || token.isEmpty) {
      throw StateError('Nothing to protect: not signed in.');
    }
    // Vault first (this opens the prompt and proves it works), flag next,
    // the open copy last: a failure at any step leaves a usable session.
    await _vault.save(token);
    await _writeProtected(true);
    await _plain.clear();
    _cache = token;
  }

  @override
  Future<void> unprotect() async {
    final token = _cache;
    if (token == null) {
      throw StateError('Unlock first: the token is not in memory.');
    }
    await _plain.write(token);
    await _writeProtected(false);
    await _vault.delete();
  }
}

/// In-memory store for tests (and previews). Behaves like [ProtectedTokenStore]
/// with a scripted vault: set [unlockError] to make `unlock` / `protect` fail.
class MemoryTokenStore implements ProtectableTokenStore {
  String? _token;
  bool _protected = false;

  /// False after [lockForColdStart] until `unlock` succeeds (like the real store: no
  /// token, and no prompt, while locked).
  bool _unlocked = true;

  /// Thrown by `unlock` and `protect` when set (a cancelled prompt, an
  /// invalidated key...).
  VaultException? unlockError;

  /// How many prompts were opened (tests).
  int prompts = 0;

  @override
  bool get isProtected => _protected;

  @override
  Future<String?> read() async => _unlocked ? _token : null;

  @override
  Future<void> write(String token) async {
    _token = token;
    _unlocked = true;
  }

  @override
  Future<void> clear() async {
    _token = null;
    _protected = false;
    _unlocked = true;
  }

  @override
  Future<String?> unlock() async {
    prompts++;
    if (unlockError != null) throw unlockError!;
    _unlocked = true;
    return _token;
  }

  @override
  Future<void> protect() async {
    prompts++;
    if (unlockError != null) throw unlockError!;
    _protected = true;
  }

  @override
  Future<void> unprotect() async => _protected = false;

  /// Starts a "launch" in which the saved session is locked behind the vault.
  void lockForColdStart() {
    _protected = true;
    _unlocked = false;
  }
}

/// Small non-secret preferences (appearance, last e-mail used...).
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  ThemeMode get themeMode => switch (_prefs.getString('theme_mode')) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString('theme_mode', mode.name);

  String? get lastEmail => _prefs.getString('last_email');
  Future<void> setLastEmail(String email) =>
      _prefs.setString('last_email', email);

  /// Test builds only: the API address chosen in the app (null = the build's own).
  String? get serverUrl => _prefs.getString('server_url');
  Future<void> setServerUrl(String? url) => url == null
      ? _prefs.remove('server_url')
      : _prefs.setString('server_url', url);

  /// The last few addresses used, newest first, for one-tap switching.
  List<String> get recentServers =>
      _prefs.getStringList('server_recent') ?? const <String>[];
  Future<void> rememberServer(String url) => _prefs.setStringList(
    'server_recent',
    [url, ...recentServers.where((u) => u != url)].take(4).toList(),
  );

  bool get hapticsOn => _prefs.getBool('haptics') ?? true;
  Future<void> setHaptics(bool on) => _prefs.setBool('haptics', on);

  /// The order of the calendar's barber columns (ids), like the web's
  /// drag-to-reorder; kept per phone.
  List<int> get calendarOrder => [
    for (final s
        in (_prefs.getStringList('calendar_order') ?? const <String>[]))
      ?int.tryParse(s),
  ];

  Future<void> setCalendarOrder(List<int> ids) =>
      _prefs.setStringList('calendar_order', [for (final i in ids) '$i']);

  /// How tall one hour is in the calendar (pinch to zoom); null = the default.
  double? get calendarHourHeight => _prefs.getDouble('calendar_hour_height');
  Future<void> setCalendarHourHeight(double px) =>
      _prefs.setDouble('calendar_hour_height', px);

  /// Pixels per hour of the landscape calendar after a pinch; null = the preset.
  double? get landscapeHourWidth => _prefs.getDouble('landscape_hour_width');
  Future<void> setLandscapeHourWidth(double? px) => px == null
      ? _prefs.remove('landscape_hour_width')
      : _prefs.setDouble('landscape_hour_width', px);

  /// The session is locked behind the fingerprint / screen lock (the biometric vault).
  /// Only a flag: the token itself is in the vault, and a wrong flag can never
  /// open anything (the vault would simply be empty or unreadable).
  bool get biometricEnabled => _prefs.getBool('biometric_enabled') ?? false;
  Future<void> setBiometricEnabled(bool on) =>
      _prefs.setBool('biometric_enabled', on);

  /// Seconds away (or idle) before the app locks; 0 = every time it is left.
  int get lockTimeoutSeconds => _prefs.getInt('lock_timeout_seconds') ?? 300;
  Future<void> setLockTimeoutSeconds(int s) =>
      _prefs.setInt('lock_timeout_seconds', s);

  /// How many times the "turn on fingerprint unlock" offer was answered "Not now".
  int get biometricOfferDeclines => _prefs.getInt('biometric_declines') ?? 0;
  Future<void> setBiometricOfferDeclines(int n) =>
      _prefs.setInt('biometric_declines', n);

  /// The one-time "pinch to zoom" tip has been shown (or used).
  bool get calendarZoomHintSeen =>
      _prefs.getBool('calendar_zoom_hint_seen') ?? false;
  Future<void> setCalendarZoomHintSeen() =>
      _prefs.setBool('calendar_zoom_hint_seen', true);
}

/// Tiny read cache for "show what we had instantly, refresh in the background".
/// Values must be JSON-encodable. Entries older than their TTL are reported as
/// stale (still returned, so offline mode can use them).
class ReadCache {
  ReadCache(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  static String _k(String key) => 'cache:$key';

  Future<void> put(String key, Object? value) {
    return _prefs.setString(
      _k(key),
      jsonEncode({'t': _clock().millisecondsSinceEpoch, 'v': value}),
    );
  }

  CachedValue? get(String key, {Duration ttl = const Duration(minutes: 10)}) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final saved = DateTime.fromMillisecondsSinceEpoch(map['t'] as int);
      return CachedValue(
        map['v'],
        savedAt: saved,
        stale: _clock().difference(saved) > ttl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) => _prefs.remove(_k(key));

  /// Called on sign-out so nothing personal stays on the phone.
  Future<void> clearAll() async {
    for (final k
        in _prefs.getKeys().where((k) => k.startsWith('cache:')).toList()) {
      await _prefs.remove(k);
    }
  }
}

class CachedValue {
  const CachedValue(this.value, {required this.savedAt, required this.stale});

  final Object? value;
  final DateTime savedAt;
  final bool stale;
}
