import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the sign-in token lives. Secure storage in the app, memory in tests.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
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

class MemoryTokenStore implements TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
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
