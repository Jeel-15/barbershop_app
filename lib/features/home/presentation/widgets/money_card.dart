import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/home/application/money_visibility.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _hidden = '••••••';

/// The shop's money (admin) or the person's own earnings (staff), on More.
/// Hidden until the eye is tapped, so it is never on show by accident.
class MoneyCard extends ConsumerWidget {
  const MoneyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final summary = home.value?.summary;
    if (summary == null) {
      // Loading shows a placeholder; a failure just leaves the card out.
      return home.isLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.page),
              child: SkeletonLoader(
                child: SkeletonBox(height: 118, radius: 28),
              ),
            )
          : const SizedBox.shrink();
    }
    return _MoneyBody(
      summary: summary,
      shown: ref.watch(moneyVisibilityProvider),
      onToggle: () {
        AppHaptics.tap();
        ref.read(moneyVisibilityProvider.notifier).toggle();
      },
    );
  }
}

class _MoneyBody extends StatelessWidget {
  const _MoneyBody({
    required this.summary,
    required this.shown,
    required this.onToggle,
  });

  final DashboardSummary summary;
  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final admin = summary.isAdmin;
    final label = admin ? 'TOTAL REVENUE' : 'MY EARNINGS';

    Widget amount(Money m, TextStyle style) => SoftSwitcher(
      duration: const Duration(milliseconds: 220),
      child: shown
          ? CountUpText(
              key: const ValueKey('shown'),
              value: m.cents.toDouble(),
              builder: (v) => Money(v.round()).format(),
              duration: const Duration(milliseconds: 700),
              style: style,
            )
          : Text(_hidden, key: const ValueKey('hidden'), style: style),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: t.accent.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: t.isDark
                  ? const [Color(0xFF2E2014), Color(0xFF1A120C)]
                  : const [Color(0xFFFFF4DC), Color(0xFFF1DFB8)],
            ),
          ),
          child: Stack(
            children: [
              if (t.isDark)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: GoldDust(count: 14, opacity: 0.45),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: AppType.overline.copyWith(
                              color: t.accentText,
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: shown ? 'Hide amount' : 'Show amount',
                          child: Pressable(
                            onTap: onToggle,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.sm),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  shown
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  key: ValueKey(shown),
                                  size: 22,
                                  color: t.accentText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    amount(
                      summary.revenue,
                      AppText.display(
                        36,
                        color: t.text,
                        height: 1.05,
                        weight: FontWeight.w700,
                      ).copyWith(
                        fontFeatures: const [FontFeature.liningFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.lg),
                      child: Text(
                        admin
                            ? 'All appointments, without tax and tips'
                            : 'Your tips plus your commission',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(color: t.textSecondary),
                      ),
                    ),
                    if (!admin) ...[
                      const SizedBox(height: AppSpace.md),
                      Row(
                        children: [
                          Expanded(
                            child: _Cell(
                              'Commission',
                              amount(summary.commission, AppType.heading),
                            ),
                          ),
                          Expanded(
                            child: _Cell(
                              'Tips Received',
                              amount(summary.tips, AppType.heading),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DefaultTextStyle.merge(
      style: TextStyle(color: t.text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          value,
          Text(label, style: AppType.caption.copyWith(color: t.textSecondary)),
        ],
      ),
    );
  }
}
