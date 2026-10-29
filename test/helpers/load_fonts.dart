import 'dart:io';

import 'package:flutter/services.dart';

/// `flutter test` does not load the fonts declared in pubspec by itself, so
/// text would be measured with the square test font and layouts overflow in
/// ways they never do on a phone. Call this in `setUpAll` to measure real text.
Future<void> loadAppFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Manrope', [
    'Manrope-400.ttf',
    'Manrope-500.ttf',
    'Manrope-600.ttf',
    'Manrope-700.ttf',
    'Manrope-800.ttf',
  ]);
  await family('PlayfairDisplay', [
    'PlayfairDisplay-400.ttf',
    'PlayfairDisplay-600.ttf',
    'PlayfairDisplay-700.ttf',
    'PlayfairDisplay-800.ttf',
  ]);
}
