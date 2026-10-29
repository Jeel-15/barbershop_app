import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Audit switch: SMALL=1 runs every widget test on a 320x640 phone with 1.6x text.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.environment['SMALL'] == '1') {
    setUp(() {
      final b = TestWidgetsFlutterBinding.ensureInitialized();
      b.platformDispatcher.views.first
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      b.platformDispatcher.textScaleFactorTestValue = 1.6;
    });
  }
  await testMain();
}
