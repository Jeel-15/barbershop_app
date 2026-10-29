import 'package:barbershop_app/core/storage/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('AppPrefs', () {
    test('defaults: dark theme, haptics on', () {
      final p = AppPrefs(prefs);
      expect(p.themeMode, ThemeMode.dark);
      expect(p.hapticsOn, isTrue);
      expect(p.lastEmail, isNull);
    });

    test('theme mode persists', () async {
      await AppPrefs(prefs).setThemeMode(ThemeMode.light);
      expect(AppPrefs(prefs).themeMode, ThemeMode.light);
      await AppPrefs(prefs).setThemeMode(ThemeMode.system);
      expect(AppPrefs(prefs).themeMode, ThemeMode.system);
    });
  });

  group('ReadCache', () {
    test('returns what was stored', () async {
      final c = ReadCache(prefs);
      await c.put('today', {
        'a': 1,
        'list': [1, 2],
      });
      final v = c.get('today')!;
      expect(v.value, {
        'a': 1,
        'list': [1, 2],
      });
      expect(v.stale, isFalse);
    });

    test('is stale after its TTL but still returned (offline use)', () async {
      var now = DateTime(2026, 10, 23, 12);
      final c = ReadCache(prefs, clock: () => now);
      await c.put('k', 'v');
      now = now.add(const Duration(minutes: 11));
      expect(c.get('k')!.stale, isTrue);
      expect(c.get('k', ttl: const Duration(hours: 1))!.stale, isFalse);
      expect(c.get('k')!.value, 'v');
    });

    test('missing and corrupt entries are null', () async {
      final c = ReadCache(prefs);
      expect(c.get('nope'), isNull);
      await prefs.setString('cache:bad', '{not json');
      expect(c.get('bad'), isNull);
    });

    test('clearAll removes cached data only (sign-out)', () async {
      final c = ReadCache(prefs);
      await c.put('a', 1);
      await c.put('b', 2);
      await AppPrefs(prefs).setThemeMode(ThemeMode.light);
      await c.clearAll();
      expect(c.get('a'), isNull);
      expect(c.get('b'), isNull);
      expect(AppPrefs(prefs).themeMode, ThemeMode.light);
    });
  });

  test('MemoryTokenStore', () async {
    final s = MemoryTokenStore();
    expect(await s.read(), isNull);
    await s.write('t');
    expect(await s.read(), 't');
    await s.clear();
    expect(await s.read(), isNull);
  });
}
