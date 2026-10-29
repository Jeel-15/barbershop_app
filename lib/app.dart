import 'package:barbershop_app/brand.dart';
import 'package:barbershop_app/core/network/connectivity.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/router/app_router.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BarbershopApp extends ConsumerWidget {
  const BarbershopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
      // Status bar and bottom bar icons follow the theme (a screen that is
      // always dark says so itself).
      builder: (context, child) => SystemBars(
        // "You're offline" strip for the whole app; unknown yet counts as online.
        child: ConnectionBanner(
          online: ref.watch(connectivityProvider).value ?? true,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
