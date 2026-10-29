import 'package:barbershop_app/design_system/components/haptics.dart';
import 'package:barbershop_app/design_system/components/pressable.dart';
import 'package:barbershop_app/design_system/tokens/app_tokens.dart';
import 'package:barbershop_app/design_system/tokens/colors.dart';
import 'package:barbershop_app/design_system/tokens/layout.dart';
import 'package:barbershop_app/design_system/tokens/typography.dart';
import 'package:flutter/material.dart';

class NavItem {
  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Small count on the icon (pending bookings...). Null or 0 = none.
  final int? badge;
}

class NavCenter {
  const NavCenter({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Floating bottom bar: up to four tabs and one raised gold action in the
/// middle (Create Invoice). Icons only, no text: labels are read by screen
/// readers (semantics). Solid surface (no blur) so scrolling stays smooth.
/// Pages under it should leave [reservedHeight] of bottom space.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.center,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final NavCenter? center;

  static const double barHeight = 64;
  static const double _raise = 16;

  /// Space the bar occupies above the safe area.
  static double reservedHeight(BuildContext context) =>
      barHeight + _raise + 24 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final half = (items.length / 2).ceil();
    final left = center == null ? items : items.sublist(0, half);
    final right = center == null ? const <NavItem>[] : items.sublist(half);

    Widget item(int index) => Expanded(
      child: _NavButton(
        item: items[index],
        selected: index == currentIndex,
        onTap: () => onTap(index),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, bottom + 10),
      child: SizedBox(
        height: barHeight + _raise,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(barHeight / 2.2),
                border: Border.all(color: t.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: t.isDark ? 0.5 : 0.12,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < left.length; i++) item(i),
                  if (center != null) const SizedBox(width: 78),
                  for (var i = 0; i < right.length; i++) item(left.length + i),
                ],
              ),
            ),
            if (center != null)
              Positioned(bottom: 6, child: _CenterButton(center: center!)),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.accentText : t.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Pressable(
        haptic: false,
        scale: 0.94,
        minSize: 0,
        onTap: () {
          if (!selected) AppHaptics.select();
          onTap();
        },
        child: SizedBox(
          height: AppNavBar.barHeight,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              width: selected ? 60 : 44,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? t.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(21),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    size: 25,
                    color: color,
                  ),
                  if ((item.badge ?? 0) > 0)
                    Positioned(
                      right: selected ? 2 : -4,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: t.danger,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${item.badge! > 99 ? '99+' : item.badge}',
                          style: AppType.label.copyWith(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.center});

  final NavCenter center;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: center.label,
      child: Pressable(
        scale: 0.93,
        minSize: 0,
        onTap: center.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.goldGradient,
                border: Border.all(color: t.surfaceRaised, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(center.icon, color: AppColors.ink, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}
