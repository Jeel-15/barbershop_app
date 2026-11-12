import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/lock/presentation/biometric_offer.dart';
import 'package:barbershop_app/features/shell/back_handler.dart';
import 'package:barbershop_app/features/shell/nav_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The signed-in frame: pages in an indexed stack (each tab keeps its place)
/// and the floating bar built from what this user may open.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _icons = {
    AppTab.home: (Icons.home_outlined, Icons.home_rounded, 'Dashboard'),
    AppTab.appointments: (
      Icons.event_note_outlined,
      Icons.event_note_rounded,
      'Appointments',
    ),
    AppTab.calendar: (
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
      'Calendar',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    // An administrator changed what this user may do (found by a quiet refresh);
    // the menus and screens already follow, this just says why.
    ref.listen(accessNoticeProvider, (_, _) {
      showToast(context, 'Your access was updated by an administrator.');
    });
    final tabs = user.visibleTabs;
    final current = tabs.indexOf(AppTab.values[navigationShell.currentIndex]);

    final items = [
      for (final tab in tabs)
        if (tab == AppTab.more)
          NavItem(
            // Staff get "Me" (a person), the owner gets the menu.
            icon: user.isStaff
                ? Icons.person_outline_rounded
                : Icons.menu_rounded,
            activeIcon: user.isStaff
                ? Icons.person_rounded
                : Icons.menu_rounded,
            label: user.moreLabel,
          )
        else
          NavItem(
            icon: _icons[tab]!.$1,
            activeIcon: _icons[tab]!.$2,
            label: _icons[tab]!.$3,
          ),
    ];

    return ShellBackHandler(
      atHome: navigationShell.currentIndex == AppTab.home.index,
      onHome: () => navigationShell.goBranch(AppTab.home.index),
      onHint: () => showToast(context, 'Press back again to exit'),
      child: BiometricOfferHost(
        child: Scaffold(
          extendBody: true,
          body: navigationShell,
          bottomNavigationBar: AppNavBar(
            items: items,
            currentIndex: current < 0 ? 0 : current,
            center: user.canCreateInvoice
                ? NavCenter(
                    icon: Icons.add_rounded,
                    label: 'Invoice',
                    onTap: () => context.push('/app/invoice/new'),
                  )
                : null,
            onTap: (i) {
              final index = tabs[i].index;
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
          ),
        ),
      ),
    );
  }
}
