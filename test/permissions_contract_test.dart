import 'dart:convert';
import 'dart:io';

import 'package:barbershop_app/features/auth/domain/perm.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app and the server must agree on permissions. `test/fixtures/api_permissions.json`
/// is exported from the web project (`bash tool/live/export_permission_contract.sh`):
/// every stored permission and, per route, the permission(s) it asks for.
///
/// These tests turn "a button the server will refuse" and "a misspelt permission that
/// silently hides a button" into failures at build time instead of surprises in the shop.
void main() {
  final contract =
      jsonDecode(File('test/fixtures/api_permissions.json').readAsStringSync())
          as Map<String, dynamic>;
  final stored = {for (final p in contract['permissions'] as List) p as String};
  final routes = [
    for (final r in contract['routes'] as List)
      (
        method: (r as Map)['method'] as String,
        uri: r['uri'] as String,
        needs: [for (final n in r['needs'] as List) n as String],
      ),
  ];
  final asked = {for (final r in routes) ...r.needs};
  final writeAsked = {
    for (final r in routes)
      if (r.method != 'GET') ...r.needs,
  };

  // lib/ without the list itself.
  final libFiles = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.replaceAll(r'\', '/').endsWith('auth/domain/perm.dart'))
        f,
  ];
  final lib = {for (final f in libFiles) f.path: f.readAsStringSync()};

  // `static const name = 'Value';` (a few wrap onto two lines).
  final names = {
    for (final m in RegExp(
      r"static const (\w+) =\s*'([^']+)';",
    ).allMatches(File('lib/features/auth/domain/perm.dart').readAsStringSync()))
      m.group(2)!: m.group(1)!,
  };

  test('every permission the app names exists on the server', () {
    // Pos_invoice-Show_All is asked for by the server's routes but is not stored
    // (a web quirk, WEB_DEV_FIXES Q67): fine to name it, nobody can hold it.
    for (final p in Perm.all) {
      expect(
        stored.contains(p) || asked.contains(p),
        isTrue,
        reason: '"$p" is not a server permission (typo?)',
      );
    }
  });

  test('the list has no duplicates and every constant is in it', () {
    expect(Perm.all.toSet().length, Perm.all.length);
    expect(
      names.keys.toSet(),
      Perm.all.toSet(),
      reason: 'a constant is missing from Perm.all (or the other way round)',
    );
  });

  test('the app knows every permission the server stores', () {
    final unknown = stored.difference(Perm.all.toSet());
    expect(
      unknown,
      isEmpty,
      reason:
          'New on the server: add to Perm and decide which button it guards: $unknown',
    );
  });

  test('every permission that guards a write is named in the app', () {
    // Asked for by the routes but never stored, so nobody can hold them
    // (a web quirk, WEB_DEV_FIXES Q67). `Gallery-Add` alone opens those routes.
    const neverStored = {'Gallery-Edit', 'Pos_invoice-Show_All'};
    final missing = writeAsked
        .difference(Perm.all.toSet())
        .difference(neverStored);
    expect(
      missing,
      isEmpty,
      reason: 'Server asks for these, the app does not know them',
    );
  });

  test('every Add / Edit / Delete the server enforces guards something', () {
    final actions = RegExp(r'-(Add|Edit|Delete)$');
    final unguarded = <String>[];
    for (final p in writeAsked.where(actions.hasMatch)) {
      final name = names[p];
      if (name == null) continue; // reported by the test above
      final used = lib.values.any((src) => src.contains('Perm.$name'));
      if (!used) unguarded.add(p);
    }
    expect(
      unguarded,
      isEmpty,
      reason:
          'The server refuses these but no screen checks them, so a button may '
          'show that cannot work: $unguarded',
    );
  });

  test('no screen spells a permission as loose text', () {
    final quoted = [for (final p in Perm.all) "'$p'"];
    final offenders = <String>[];
    lib.forEach((path, src) {
      for (final q in quoted) {
        if (src.contains(q)) offenders.add('$path: $q');
      }
      if (RegExp(r"\bcan(Any)?\(\s*\[?\s*'").hasMatch(src)) {
        offenders.add('$path: can(...) with a string');
      }
    });
    expect(offenders, isEmpty, reason: 'Use Perm.<name>: $offenders');
  });
}
