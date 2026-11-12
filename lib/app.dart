import 'dart:async';

import 'package:barbershop_app/brand.dart';
import 'package:barbershop_app/core/config/env.dart';
import 'package:barbershop_app/core/network/connectivity.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/router/app_router.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/demo/application/demo_tour.dart';
import 'package:barbershop_app/features/demo/presentation/demo_overlay.dart';
import 'package:barbershop_app/features/lock/application/app_lock_controller.dart';
import 'package:barbershop_app/features/lock/presentation/lock_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BarbershopApp extends ConsumerStatefulWidget {
  const BarbershopApp({super.key});

  @override
  ConsumerState<BarbershopApp> createState() => _BarbershopAppState();
}

class _BarbershopAppState extends ConsumerState<BarbershopApp>
    with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Registered before the router's own back-button handling, so it gets the
    // back press first (see didPopRoute).
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(
      // Back in front: the app may need to lock, and an admin may have changed
      // this user's access meanwhile (the session limits that to once a minute).
      onResume: () {
        ref.read(appLockProvider.notifier).onResumed();
        ref.read(sessionControllerProvider.notifier).onResume();
      },
      onInactive: () => ref.read(appLockProvider.notifier).onInactive(),
      onPause: () => ref.read(appLockProvider.notifier).onPaused(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
  }

  /// While the lock panel covers the app, "back" must not move the page under it.
  @override
  Future<bool> didPopRoute() async => ref.read(appLockProvider).locked;

  bool _autoStarted = false;

  @override
  Widget build(BuildContext context) {
    // Developer switch (TOUR_AUTOSTART): start the narrated tour by itself once the
    // app is signed in, so a run can be checked without touching the phone.
    ref.listen(sessionControllerProvider, (_, next) {
      if (kTourAutostart && !Env.isProd && !_autoStarted && next is SignedIn) {
        _autoStarted = true;
        Future<void>.delayed(const Duration(seconds: 6), () {
          if (mounted) unawaited(ref.read(demoTourProvider.notifier).start());
        });
      }
    });
    return MaterialApp.router(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
      // Status bar and bottom bar icons follow the theme (a screen that is
      // always dark says so itself).
      builder: (context, child) => RepaintBoundary(
        key: tourBoundaryKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LockGate(
              child: SystemBars(
                // "You're offline" strip for the whole app; unknown yet counts as online.
                child: ConnectionBanner(
                  online: ref.watch(connectivityProvider).value ?? true,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
            // The narrated demo tour draws here (ring, finger, subtitle); nothing otherwise.
            const DemoOverlay(),
          ],
        ),
      ),
    );
  }
}
