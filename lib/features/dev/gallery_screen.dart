import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Debug-only review surface for the whole design system: tokens, type,
/// every component in every state, in dark and light. Open it from the
/// welcome screen long-press (debug) or at /dev/gallery.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String _chip = 'all';
  String _segment = '7d';
  DateTime _day = ShopTime.today();
  bool _loadingBtn = false;
  final _password = TextEditingController(text: 'secret123');

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mode = ref.watch(themeModeProvider);

    Widget block(String title, Widget child, {String? note}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, subtitle: note),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          child: child,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Design gallery'),
        actions: [
          IconButton(
            tooltip: 'Connection test',
            icon: const Icon(Icons.wifi_tethering_rounded),
            onPressed: () => context.push('/dev/connection'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          block(
            'Appearance',
            AppSegmented<ThemeMode>(
              options: const [
                ChipOption(ThemeMode.system, 'System'),
                ChipOption(ThemeMode.dark, 'Dark'),
                ChipOption(ThemeMode.light, 'Light'),
              ],
              selected: mode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
            ),
            note:
                'Every screen is built from tokens, so both themes always work.',
          ),

          block(
            'Type scale',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rosenthal',
                  style: AppType.largeTitle.copyWith(color: t.text),
                ),
                Text(
                  'Title · Today\'s bookings',
                  style: AppType.title.copyWith(color: t.text),
                ),
                Text(
                  'Heading · Skin fade + beard trim',
                  style: AppType.heading.copyWith(color: t.text),
                ),
                Text(
                  'Subheading · Alex, Master barber',
                  style: AppType.subheading.copyWith(color: t.text),
                ),
                Text(
                  'Body · Daniel booked 11:30 AM tomorrow.',
                  style: AppType.body.copyWith(color: t.text),
                ),
                Text(
                  'Caption · Last visit 12 days ago',
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
                Text(
                  'OVERLINE · TODAY',
                  style: AppType.overline.copyWith(color: t.accentText),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      const Money(48650),
                      style: AppType.heroNumber.copyWith(color: t.text),
                      smallCents: true,
                    ),
                    const SizedBox(width: 12),
                    MoneyText(
                      const Money(123456),
                      style: AppType.money.copyWith(color: t.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          block(
            'Colours',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (n, c) in [
                  ('bg', t.bg),
                  ('surface', t.surface),
                  ('raised', t.surfaceRaised),
                  ('border', t.border),
                  ('accent', t.accent),
                  ('success', t.success),
                  ('warning', t.warning),
                  ('info', t.info),
                  ('violet', t.violet),
                  ('danger', t.danger),
                ])
                  Column(
                    children: [
                      Container(
                        width: 58,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.border),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n,
                        style: AppType.caption.copyWith(
                          fontSize: 10.5,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          block(
            'Buttons',
            Column(
              children: [
                AppButton(
                  label: 'Book walk-in',
                  icon: Icons.add_rounded,
                  onPressed: () {},
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: _loadingBtn ? 'Saving' : 'Tap me: loading state',
                  loading: _loadingBtn,
                  onPressed: () async {
                    setState(() => _loadingBtn = true);
                    await Future<void>.delayed(const Duration(seconds: 2));
                    if (mounted) setState(() => _loadingBtn = false);
                  },
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: 'Reschedule',
                  icon: Icons.event_repeat_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {},
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.danger,
                        compact: true,
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: 'Skip',
                        variant: AppButtonVariant.ghost,
                        compact: true,
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const AppButton(label: 'Disabled', onPressed: null),
              ],
            ),
          ),

          block(
            'Inputs',
            Column(
              children: [
                const AppTextField(
                  label: 'Email',
                  hint: 'you@rosenthalbarbershop.ca',
                  prefixIcon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Password',
                  controller: _password,
                  obscure: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  helperText: 'At least 6 characters',
                ),
                const SizedBox(height: 14),
                const AppTextField(
                  label: 'Phone',
                  hint: '780 555 0100',
                  prefixIcon: Icons.phone_rounded,
                  errorText: 'Enter a valid phone number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                AppSearchField(onChanged: (_) {}, hint: 'Search customers'),
              ],
            ),
          ),

          block(
            'Status pills',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in AppointmentStatus.values)
                  AppointmentStatusPill(s),
              ],
            ),
            note:
                'Same meaning as the web badges. Icon + text, never colour alone.',
          ),

          block(
            'KPI tiles',
            Row(
              children: [
                Expanded(
                  child: KpiTile(
                    icon: Icons.event_available_rounded,
                    label: 'Bookings',
                    value: 12,
                    format: (v) => '${v.round()}',
                    highlight: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KpiTile(
                    icon: Icons.payments_rounded,
                    label: 'Revenue',
                    value: 486,
                    format: (v) => '\$${v.round()}',
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: KpiTile(
                    icon: Icons.volunteer_activism_rounded,
                    label: 'Tips',
                    loading: true,
                  ),
                ),
              ],
            ),
          ),

          block(
            'Rows and groups',
            Column(
              children: [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListRow(
                        leading: const AppAvatar(name: 'Daniel Reid'),
                        title: 'Daniel R.',
                        subtitle: 'Skin fade + beard trim · Alex',
                        trailing: const AppointmentStatusPill(
                          AppointmentStatus.pending,
                          compact: true,
                        ),
                        onTap: () {},
                      ),
                      Divider(color: t.border, height: 1),
                      AppListRow(
                        leading: const AppAvatar(name: 'Sam Lee'),
                        title: 'Sam L.',
                        subtitle: '2:30 PM · Buzz cut',
                        trailing: const AppointmentStatusPill(
                          AppointmentStatus.confirmed,
                          compact: true,
                        ),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AppListGroup(
                  children: [
                    AppListRow(
                      leading: Icon(
                        Icons.people_alt_rounded,
                        color: t.accentText,
                      ),
                      title: 'Customers',
                      chevron: true,
                      onTap: () {},
                    ),
                    AppListRow(
                      leading: Icon(
                        Icons.receipt_long_rounded,
                        color: t.accentText,
                      ),
                      title: 'Invoices',
                      subtitle: 'Your sales',
                      chevron: true,
                      onTap: () {},
                    ),
                    AppListRow(
                      leading: Icon(Icons.logout_rounded, color: t.danger),
                      title: 'Sign out',
                      destructive: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),

          block(
            'Avatars',
            const Row(
              children: [
                AppAvatar(name: 'Alex Morgan', size: 36),
                SizedBox(width: 10),
                AppAvatar(name: 'Mike', size: 48),
                SizedBox(width: 10),
                AppAvatar(name: 'Sam Lee', size: 56, ring: true),
                SizedBox(width: 10),
                AppAvatar(
                  name: 'Broken image',
                  imageUrl: 'http://invalid.invalid/x.png',
                  size: 48,
                ),
              ],
            ),
            note:
                'Initials appear while loading or when the picture is missing.',
          ),

          block(
            'Chips and segments',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChipsRow<String>(
                  padding: EdgeInsets.zero,
                  selected: _chip,
                  onChanged: (v) => setState(() => _chip = v),
                  options: const [
                    ChipOption('all', 'All', count: 42),
                    ChipOption(
                      'pending',
                      'Pending',
                      count: 5,
                      icon: Icons.hourglass_top_rounded,
                    ),
                    ChipOption('confirmed', 'Confirmed', count: 12),
                    ChipOption('done', 'Completed', count: 20),
                    ChipOption('cancelled', 'Cancelled', count: 5),
                  ],
                ),
                const SizedBox(height: 12),
                AppSegmented<String>(
                  selected: _segment,
                  onChanged: (v) => setState(() => _segment = v),
                  options: const [
                    ChipOption('1d', 'Today'),
                    ChipOption('7d', '7 days'),
                    ChipOption('30d', '30 days'),
                    ChipOption('m', 'Month'),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  'Date strip',
                  subtitle: 'Dot = has bookings, ring = today, dim = closed',
                ),
                DateStrip(
                  selected: _day,
                  onSelected: (d) => setState(() => _day = d),
                  markers: {
                    ShopTime.today(),
                    ShopTime.today().add(const Duration(days: 2)),
                    ShopTime.today().add(const Duration(days: 3)),
                  },
                  closed: {ShopTime.today().add(const Duration(days: 4))},
                ),
              ],
            ),
          ),

          block(
            'Charts',
            Column(
              children: [
                AppBarChart(
                  data: const [
                    BarDatum('9', 3),
                    BarDatum('10', 5),
                    BarDatum('11', 4),
                    BarDatum('12', 6),
                    BarDatum('1', 8),
                    BarDatum('2', 5),
                    BarDatum('3', 7),
                    BarDatum('4', 4),
                  ],
                  highlight: 4,
                  valueFormat: (v) => '${v.round()} bookings',
                ),
                const SizedBox(height: 16),
                AppDonutChart(
                  slices: [
                    DonutSlice('Cash', 52, t.accent),
                    DonutSlice('Debit', 30, t.info),
                    DonutSlice('Online', 18, t.violet),
                  ],
                  centerTop: '\$1,240',
                  centerBottom: 'this week',
                ),
              ],
            ),
          ),

          block(
            'Loading, empty, error',
            Column(
              children: [
                const AppCard(
                  padding: EdgeInsets.zero,
                  child: SkeletonRows(count: 3),
                ),
                const SizedBox(height: 14),
                AppCard(
                  child: EmptyState(
                    icon: Icons.event_busy_rounded,
                    title: 'No bookings today',
                    message: 'A quiet day. Add a walk-in when someone arrives.',
                    actionLabel: 'Book walk-in',
                    onAction: () {},
                  ),
                ),
                const SizedBox(height: 14),
                AppCard(
                  child: ErrorState(
                    message:
                        'The server took too long to answer. Please try again.',
                    supportCode: 'a1b2c3d4e5f6',
                    onRetry: () {},
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: const OfflineBanner(),
                ),
              ],
            ),
          ),

          block(
            'Sheets, dialogs, toasts',
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButton(
                  label: 'Bottom sheet',
                  expand: false,
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showAppSheet<void>(
                    context,
                    title: 'Reschedule',
                    builder: (ctx) => Column(
                      children: [
                        const AppTextField(label: 'Note', hint: 'Optional'),
                        const SizedBox(height: 14),
                        AppButton(
                          label: 'Save',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                ),
                AppButton(
                  label: 'Confirm dialog',
                  expand: false,
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showConfirm(
                    context,
                    title: 'Cancel this booking?',
                    message:
                        'Daniel will be told. The slot becomes free again.',
                    confirmLabel: 'Yes, cancel',
                    cancelLabel: 'Keep it',
                    destructive: true,
                  ),
                ),
                AppButton(
                  label: 'Undo snackbar',
                  expand: false,
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showUndoSnack(
                    context,
                    'Booking confirmed',
                    onUndo: () => showToast(context, 'Undone'),
                  ),
                ),
                AppButton(
                  label: 'Success toast',
                  expand: false,
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () =>
                      showToast(context, 'Saved', kind: ToastKind.success),
                ),
                AppButton(
                  label: 'Error toast',
                  expand: false,
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showToast(
                    context,
                    'Could not save',
                    kind: ToastKind.error,
                  ),
                ),
              ],
            ),
          ),

          block(
            'Money and time (exact)',
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Money.parse("34.99") * 2 + Money.parse("15.00") = ${(Money.parse("34.99") * 2 + Money.parse("15.00")).format()}',
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  Text(
                    '10% of \$34.99 = ${Money.parse("34.99").percent(10).format()}',
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                  Text(
                    'Shop time now: ${ShopTime.dayLabel(ShopTime.now())}, ${ShopTime.timeLabel(ShopTime.now().hour * 60 + ShopTime.now().minute)}',
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
