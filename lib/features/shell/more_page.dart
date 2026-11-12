import 'dart:async';

import 'package:barbershop_app/core/config/env.dart';
import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/domain/auth_user.dart';
import 'package:barbershop_app/features/demo/application/demo_tour.dart';
import 'package:barbershop_app/features/demo/application/tour_script.dart';
import 'package:barbershop_app/features/home/presentation/widgets/money_card.dart';
import 'package:barbershop_app/features/lock/presentation/security_group.dart';
import 'package:barbershop_app/features/shell/nav_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _Entry {
  const _Entry(this.title, this.icon, this.visible, {this.route});

  final String title;

  /// Where the entry opens; entries without one open the "later phase" page.
  final String? route;
  final IconData icon;
  final bool Function(AppModules m) visible;
}

class _Group {
  const _Group(this.title, this.entries);

  final String title;
  final List<_Entry> entries;
}

/// Every module the web panel has, shown only when the server says this user
/// may open it. Entries open the real screen once its phase is built.
final _groups = <_Group>[
  _Group('Work', [
    _Entry(
      'POS & Invoice',
      Icons.receipt_long_rounded,
      (m) => m.invoices,
      route: '/app/invoices',
    ),
    _Entry(
      'Customer',
      Icons.people_alt_rounded,
      (m) => m.customers,
      route: '/app/customers',
    ),
    _Entry(
      'Report',
      Icons.insights_rounded,
      (m) => m.reports,
      route: '/app/reports',
    ),
    // The web's menu says "Report" for staff too; theirs is their own earnings.
    _Entry(
      'Report',
      Icons.payments_rounded,
      (m) => m.staffReport && !m.reports,
      route: '/app/report',
    ),
  ]),
  _Group('Catalog', [
    _Entry(
      'Services',
      Icons.content_cut_rounded,
      (m) => m.services,
      route: '/app/services',
    ),
    _Entry(
      'Service Category',
      Icons.category_rounded,
      (m) => m.serviceCategories,
      route: '/app/service-categories',
    ),
    _Entry(
      'Product',
      Icons.inventory_2_rounded,
      (m) => m.products,
      route: '/app/products',
    ),
    _Entry(
      'GST Setting',
      Icons.percent_rounded,
      (m) => m.gst,
      route: '/app/gst',
    ),
  ]),
  _Group('Shop', [
    _Entry(
      'Setting',
      Icons.storefront_rounded,
      (m) => m.settings,
      route: '/app/settings',
    ),
    _Entry(
      'Working Hours',
      Icons.schedule_rounded,
      (m) => m.workingHours,
      route: '/app/working-hours',
    ),
    _Entry(
      'Closures & holidays',
      Icons.event_busy_rounded,
      (m) => m.shopClosures,
      route: '/app/shop-closures',
    ),
    _Entry('Slots', Icons.timer_outlined, (m) => m.slots, route: '/app/slots'),
    _Entry(
      'Payment methods',
      Icons.credit_card_rounded,
      (m) => m.paymentMethods,
      route: '/app/payment-methods',
    ),
    _Entry(
      'Testimonials',
      Icons.format_quote_rounded,
      (m) => m.testimonials,
      route: '/app/testimonials',
    ),
    _Entry(
      'Gallery',
      Icons.photo_library_rounded,
      (m) => m.gallery,
      route: '/app/gallery',
    ),
  ]),
  _Group('Team', [
    _Entry('Staff', Icons.badge_rounded, (m) => m.staff, route: '/app/staff'),
    _Entry(
      'Roles & Permissions',
      Icons.admin_panel_settings_rounded,
      (m) => m.roles,
      route: '/app/roles',
    ),
  ]),
];

/// "More" for the owner and "Me" for staff: profile, every available module,
/// appearance and sign out.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final user = ref.watch(currentUserProvider);
    final boot = ref.watch(bootstrapProvider);
    final theme = ref.watch(themeModeProvider);
    final prefs = ref.watch(appPrefsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(bottom: AppNavBar.reservedHeight(context)),
          children: [
            TabHeader(title: user.moreLabel),
            const SizedBox(height: AppSpace.md),
            _ProfileCard(
              user: user,
              shopName: boot.shop.name,
              onTap: user.modules.profile
                  ? () => context.push('/app/profile')
                  : null,
            ),
            // Shop revenue (admin) or own earnings (staff), hidden until the eye.
            if (user.modules.dashboard) ...[
              const SizedBox(height: AppSpace.md),
              const MoneyCard(),
            ],
            for (final g in _groups)
              if (g.entries.any((e) => e.visible(user.modules)))
                AppListGroup(
                  title: g.title,
                  children: [
                    for (final e in g.entries)
                      if (e.visible(user.modules))
                        AppListRow(
                          title: e.title,
                          leading: _Leading(icon: e.icon),
                          chevron: true,
                          onTap: () => e.route != null
                              ? context.push(e.route!)
                              : context.push('/app/coming', extra: e.title),
                        ),
                  ],
                ),
            AppListGroup(
              title: 'App',
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: AppType.bodyStrong.copyWith(color: t.text),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      AppSegmented<ThemeMode>(
                        options: const [
                          ChipOption(ThemeMode.dark, 'Dark'),
                          ChipOption(ThemeMode.light, 'Light'),
                          ChipOption(ThemeMode.system, 'Auto'),
                        ],
                        selected: theme,
                        onChanged: (m) =>
                            ref.read(themeModeProvider.notifier).set(m),
                      ),
                    ],
                  ),
                ),
                _HapticsRow(
                  initial: prefs.hapticsOn,
                  onChanged: (v) {
                    AppHaptics.enabled = v;
                    prefs.setHaptics(v);
                  },
                ),
                // A narrated, hands-free walkthrough of the whole app (dev and demo builds).
                if (!Env.isProd)
                  AppListRow(
                    title: 'Demo tour',
                    subtitle: 'A guided, narrated walkthrough',
                    leading: const _Leading(icon: Icons.play_circle_rounded),
                    chevron: true,
                    onTap: () => _startTour(context, ref),
                  ),
                AppListRow(
                  title: 'About',
                  subtitle:
                      'Version ${ref.watch(appVersionProvider)}${Env.isProd ? '' : ' · ${Env.flavor.name}'}',
                  leading: const _Leading(icon: Icons.info_outline_rounded),
                  trailing: Text(
                    'API ${boot.apiVersion}',
                    style: AppType.caption.copyWith(color: t.textMuted),
                  ),
                ),
              ],
            ),
            // Fingerprint / screen lock: hidden on a phone that cannot do it.
            SecurityGroup(leading: (icon) => _Leading(icon: icon)),
            AppListGroup(
              title: 'Account',
              children: [
                AppListRow(
                  title: 'Sign out',
                  leading: const _Leading(icon: Icons.logout_rounded),
                  onTap: () => _signOut(context, ref, everywhere: false),
                ),
                AppListRow(
                  title: 'Sign out of all devices',
                  subtitle: 'Ends every session of this account',
                  leading: const _Leading(
                    icon: Icons.devices_other_rounded,
                    destructive: true,
                  ),
                  destructive: true,
                  onTap: () => _signOut(context, ref, everywhere: true),
                ),
              ],
            ),
            if (!Env.isProd)
              AppListGroup(
                title: 'Developer',
                children: [
                  AppListRow(
                    title: 'Design gallery',
                    leading: const _Leading(icon: Icons.palette_outlined),
                    chevron: true,
                    onTap: () => context.push('/dev/gallery'),
                  ),
                  AppListRow(
                    title: 'Connection test',
                    leading: const _Leading(icon: Icons.wifi_tethering_rounded),
                    chevron: true,
                    onTap: () => context.push('/dev/connection'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Lets the person pick what the narrated tour plays: everything, or one chapter.
  Future<void> _startTour(BuildContext context, WidgetRef ref) async {
    final tour = ref.read(demoTourProvider.notifier);
    final List<TourChapter> chapters;
    try {
      chapters = await tour.chapters();
    } catch (_) {
      if (context.mounted) {
        showToast(
          context,
          'The tour script could not be read.',
          kind: ToastKind.error,
        );
      }
      return;
    }
    if (!context.mounted) return;
    final t = context.tokens;
    final picked = await showAppSheet<List<TourChapter>>(
      context,
      title: 'Demo tour',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'It plays by itself with a voice, pressing real buttons. Some '
            'chapters create real demo data: use it on the test server only.',
            style: AppType.caption.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          AppListRow(
            title: 'Play all chapters',
            subtitle: '${chapters.length} chapters',
            leading: const _Leading(icon: Icons.play_circle_rounded),
            onTap: () => Navigator.of(ctx).pop(chapters),
          ),
          for (final c in chapters)
            AppListRow(
              title: c.name,
              subtitle: '${c.beats.length} parts',
              leading: const _Leading(icon: Icons.play_arrow_rounded),
              onTap: () => Navigator.of(ctx).pop([c]),
            ),
        ],
      ),
    );
    if (picked == null || picked.isEmpty) return;
    unawaited(tour.start(chapters: picked));
  }

  Future<void> _signOut(
    BuildContext context,
    WidgetRef ref, {
    required bool everywhere,
  }) async {
    final ok = await showConfirm(
      context,
      title: everywhere ? 'Sign out of all devices?' : 'Sign out?',
      message: everywhere
          ? 'Every phone and browser using this account will need to sign in again.'
          : 'You will need your password to come back.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok) return;
    try {
      final c = ref.read(sessionControllerProvider.notifier);
      everywhere ? await c.signOutEverywhere() : await c.signOut();
    } on Failure catch (f) {
      if (context.mounted) {
        showToast(context, f.userMessage, kind: ToastKind.error);
      }
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.shopName, this.onTap});

  final AuthUser user;
  final String shopName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.page),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          AppAvatar(
            name: user.name,
            imageUrl: user.profileImageUrl,
            size: 60,
            ring: true,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading.copyWith(color: t.text),
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    StatusPill(label: user.roleLabel, color: t.accent),
                    if (shopName.isNotEmpty)
                      StatusPill(label: shopName, color: t.info),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? card
        : Pressable(onTap: onTap, scale: 0.99, minSize: 0, child: card);
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.icon, this.destructive = false});

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = destructive ? t.danger : t.accentText;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: c),
    );
  }
}

class _HapticsRow extends StatefulWidget {
  const _HapticsRow({required this.initial, required this.onChanged});

  final bool initial;
  final ValueChanged<bool> onChanged;

  @override
  State<_HapticsRow> createState() => _HapticsRowState();
}

class _HapticsRowState extends State<_HapticsRow> {
  late bool _on = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      title: 'Haptic feedback',
      leading: const _Leading(icon: Icons.vibration_rounded),
      trailing: Switch(
        value: _on,
        onChanged: (v) {
          setState(() => _on = v);
          widget.onChanged(v);
        },
      ),
    );
  }
}
