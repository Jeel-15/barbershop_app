import 'package:barbershop_app/app.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/storage/storage.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/core/utils/frame_log.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unexpected errors must not paint a red or grey box over the app, or take it
/// down: a widget that fails to build becomes a quiet card, and an error from
/// nowhere in particular is logged and swallowed (the screen keeps working).
void _calmErrors() {
  final report = FlutterError.onError;
  FlutterError.onError = (details) {
    report?.call(details); // still logged
  };
  ErrorWidget.builder = (_) => const FriendlyErrorWidget();
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled: $error\n$stack');
    return true;
  };
}

/// Everything that must be ready before the first frame, then runs the app.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  ShopTime.init();
  FrameLog.start();
  _calmErrors();
  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  AppHaptics.enabled = AppPrefs(prefs).hapticsOn;

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // The app draws behind the status bar and the bottom bar; SystemBars (in
  // app.dart) picks readable icons for the screen that is showing.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemBars.styleFor(light: true));

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        appVersionProvider.overrideWithValue(AppVersion.parse(info.version)),
        // Any 401 ends the session and the router returns to Sign in.
        unauthorizedHandlerProvider.overrideWith(
          (ref) =>
              () => ref.read(sessionControllerProvider.notifier).expire(),
        ),
      ],
      child: const BarbershopApp(),
    ),
  );
}
