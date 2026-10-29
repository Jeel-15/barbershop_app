import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/shop/data/shop_repository.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's Slot Configuration ("Configure business hours and appointment
/// slots"): per weekday a Day Off switch and the Shop Open / Close Time.
class SlotsPage extends ConsumerStatefulWidget {
  const SlotsPage({super.key});

  @override
  ConsumerState<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends ConsumerState<SlotsPage> {
  List<ShopDay>? _days;
  final _errors = <String, String>{};
  bool _busy = false;

  Future<void> _pick(ShopDay d, {required bool open}) async {
    final cur = open ? d.open : d.close;
    final p = cur?.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: p == null
          ? TimeOfDay(hour: open ? 9 : 20, minute: 0)
          : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (picked == null) return;
    final v =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _days = [
        for (final x in _days!)
          if (x.day == d.day)
            (open ? x.copyWith(open: v) : x.copyWith(close: v))
          else
            x,
      ];
      _errors.remove(d.day);
    });
  }

  void _toggle(ShopDay d, bool off) => setState(() {
    _days = [
      for (final x in _days!)
        if (x.day == d.day) x.copyWith(isDayOff: off) else x,
    ];
    _errors.remove(d.day);
  });

  /// The server's rules, said up front: an open day needs both times and the
  /// closing time after the opening time.
  bool _validate() {
    final e = <String, String>{};
    for (final d in _days!) {
      if (d.isDayOff) continue;
      if (d.open == null || d.close == null) {
        e[d.day] = 'Opening and closing time are required for an open day.';
      } else if (d.close!.compareTo(d.open!) <= 0) {
        e[d.day] = 'Closing time must be after opening time.';
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _busy = true);
    try {
      final msg = await ref.read(shopRepositoryProvider).saveHours(_days!);
      ref.invalidate(shopHoursProvider);
      ref.invalidate(dayAvailabilityProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, msg, kind: ToastKind.success);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(shopHoursProvider);
    if (_days == null && async.value != null) _days = async.value;
    final days = _days;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.sm,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  RoundBackButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/app/more'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Slot Configuration',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          'Configure business hours and appointment slots',
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: days != null
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.page,
                        AppSpace.sm,
                        AppSpace.page,
                        AppSpace.xl,
                      ),
                      children: [
                        for (final d in days)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.md),
                            child: _DayCard(
                              day: d,
                              error: _errors[d.day],
                              onOff: (v) => _toggle(d, v),
                              onPick: ({required bool open}) =>
                                  _pick(d, open: open),
                            ),
                          ),
                      ],
                    )
                  : async.hasError
                  ? ErrorState(
                      message: async.error is Failure
                          ? (async.error! as Failure).userMessage
                          : 'Could not load the opening hours.',
                      onRetry: () => ref.invalidate(shopHoursProvider),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(AppSpace.page),
                      child: SkeletonRows(count: 5),
                    ),
            ),
            if (days != null)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.page,
                  AppSpace.md,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: AppButton(
                  label: 'Update',
                  loading: _busy,
                  onPressed: _save,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.error,
    required this.onOff,
    required this.onPick,
  });

  final ShopDay day;
  final String? error;
  final ValueChanged<bool> onOff;
  final void Function({required bool open}) onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget time(String label, String? v, {required bool open}) => Expanded(
      child: Pressable(
        onTap: () => onPick(open: open),
        minSize: 0,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: error == null ? t.border : t.danger),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppType.caption.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                v == null ? '--:--' : ShopTime.timeLabel(v),
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.day,
                  style: AppType.heading.copyWith(color: t.text),
                ),
              ),
              Text(
                'Day Off',
                style: AppType.body.copyWith(color: t.textSecondary),
              ),
              Switch(value: day.isDayOff, onChanged: onOff),
            ],
          ),
          if (!day.isDayOff) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                time('Shop Open Time', day.open, open: true),
                const SizedBox(width: AppSpace.sm + 2),
                time('Shop Close Time', day.close, open: false),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: AppType.caption.copyWith(color: t.danger),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
