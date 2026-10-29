import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/data/calendar_repository.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Add Breaks" (web): pick the barber, then either how long (from now) or
/// the rest of the day.
Future<void> showBreakSheet(BuildContext context, List<CalendarLane> lanes) {
  return showAppSheet<void>(
    context,
    title: 'Add a break',
    builder: (_) => _BreakSheet(lanes: lanes),
  );
}

class _BreakSheet extends ConsumerStatefulWidget {
  const _BreakSheet({required this.lanes});

  final List<CalendarLane> lanes;

  @override
  ConsumerState<_BreakSheet> createState() => _BreakSheetState();
}

class _BreakSheetState extends ConsumerState<_BreakSheet> {
  late int? _staff = widget.lanes.length == 1 ? widget.lanes.first.id : null;
  bool _rest = false;
  int _minutes = 30;
  bool _busy = false;

  static const _options = [15, 30, 45, 60, 90, 120];

  Future<void> _save() async {
    if (_staff == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(calendarRepositoryProvider)
          .addBreak(
            staffId: _staff!,
            restOfDay: _rest,
            hours: _minutes ~/ 60,
            minutes: _minutes % 60,
          );
      await ref.read(calendarProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Break added.', kind: ToastKind.success);
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.lanes.length > 1) ...[
          Text('Barber', style: AppType.label.copyWith(color: t.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in widget.lanes)
                AppChoiceChip(
                  label: l.name,
                  selected: _staff == l.id,
                  onTap: () => setState(() => _staff = l.id),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        Text(
          'The break starts now.',
          style: AppType.caption.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: AppSpace.sm),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _rest,
          onChanged: (v) => setState(() => _rest = v),
          title: Text(
            'Rest of the day',
            style: AppType.bodyStrong.copyWith(color: t.text),
          ),
        ),
        if (!_rest) ...[
          Text(
            'How long',
            style: AppType.label.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _options)
                AppChoiceChip(
                  label: m < 60
                      ? '$m min'
                      : '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}',
                  selected: _minutes == m,
                  onTap: () => setState(() => _minutes = m),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        AppButton(
          label: 'Add break',
          icon: Icons.coffee_rounded,
          loading: _busy,
          onPressed: _staff == null ? null : _save,
        ),
      ],
    );
  }
}
