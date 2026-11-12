import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';

/// "+ New" button for a new appointment. [expanded] shows the word; scrolling
/// down collapses it to the plus alone, scrolling up brings the word back.
class NewAppointmentFab extends StatelessWidget {
  const NewAppointmentFab({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final fg = t.isDark ? AppColors.ink : AppColors.espresso;
    return Semantics(
      button: true,
      label: 'New appointment',
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          AppHaptics.tap();
          onPressed();
        },
        scale: 0.94,
        minSize: 0,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 16),
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: fg, size: 26),
              AnimatedSize(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'New',
                          style: AppType.bodyStrong.copyWith(
                            color: fg,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
