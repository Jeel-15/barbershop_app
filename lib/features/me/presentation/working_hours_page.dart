import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The web's Working Hours ("Manage your availability and breaks for
/// appointments"): a card per weekday with + Add, a Day Off switch and the
/// day's ranges (edit, delete). These hours colour the calendar green.
class WorkingHoursPage extends ConsumerStatefulWidget {
  const WorkingHoursPage({super.key});

  @override
  ConsumerState<WorkingHoursPage> createState() => _WorkingHoursPageState();
}

class _WorkingHoursPageState extends ConsumerState<WorkingHoursPage> {
  /// Days whose switch is being saved (the switch shows the new value at once).
  final _pending = <int, bool>{};

  void _reload() {
    ref.invalidate(workingHoursProvider);
    // The calendar draws these hours as its free and not-available time.
    ref.invalidate(dayAvailabilityProvider);
  }

  Future<void> _guard(Future<void> Function() job) async {
    try {
      await job();
    } on Failure catch (f) {
      if (mounted) showToast(context, f.userMessage, kind: ToastKind.error);
    }
  }

  Future<void> _dayOff(WorkDay d, bool off) => _guard(() async {
    setState(() => _pending[d.slotId] = off);
    try {
      await ref.read(meRepositoryProvider).setDayOff(d.slotId, off: off);
      _reload();
      await ref.read(workingHoursProvider.future);
    } finally {
      if (mounted) setState(() => _pending.remove(d.slotId));
    }
  });

  Future<void> _edit(WorkDay d, {WorkBlock? block}) async {
    final saved = await showAppSheet<String>(
      context,
      title: 'Set Working Hours / Add Break',
      builder: (_) => _HoursForm(day: d, block: block),
    );
    if (saved == null || !mounted) return;
    showToast(context, saved, kind: ToastKind.success);
    _reload();
  }

  Future<void> _delete(WorkBlock b) async {
    final ok = await showConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure to delete Work Time?',
      confirmLabel: 'Yes, confirm!',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _guard(() async {
      final msg = await ref.read(meRepositoryProvider).deleteHours(b.id);
      if (!mounted) return;
      showToast(context, msg, kind: ToastKind.success);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(workingHoursProvider);

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
                          'Working Hours',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          'Manage your availability and breaks for appointments',
                          maxLines: 2,
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
              child: switch (async) {
                AsyncError(:final error) when async.value == null => ErrorState(
                  message: error is Failure
                      ? error.userMessage
                      : 'Could not load your working hours.',
                  supportCode: error is Failure ? error.requestId : null,
                  onRetry: _reload,
                ),
                AsyncData(:final value) ||
                AsyncLoading(:final value?) => AppRefresh(
                  onRefresh: () async {
                    _reload();
                    await ref.read(workingHoursProvider.future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.page,
                      AppSpace.sm,
                      AppSpace.page,
                      AppSpace.xxl,
                    ),
                    children: [
                      if (value.isEmpty)
                        const QuietState(
                          title: 'No days set up',
                          message:
                              'Your week has not been created yet. Ask the owner to set up your slots.',
                        ),
                      for (final d in value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.md),
                          child: _DayCard(
                            day: d,
                            off: _pending[d.slotId] ?? d.isDayOff,
                            onAdd: () => _edit(d),
                            onDayOff: (v) => _dayOff(d, v),
                            onEdit: (b) => _edit(d, block: b),
                            onDelete: _delete,
                          ),
                        ),
                    ],
                  ),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(AppSpace.page),
                  child: SkeletonRows(count: 4),
                ),
              },
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
    required this.off,
    required this.onAdd,
    required this.onDayOff,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkDay day;
  final bool off;
  final VoidCallback onAdd;
  final ValueChanged<bool> onDayOff;
  final ValueChanged<WorkBlock> onEdit;
  final ValueChanged<WorkBlock> onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
                  day.name,
                  style: AppType.heading.copyWith(color: t.text),
                ),
              ),
              AppButton(
                label: '+ Add',
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: onAdd,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Day Off',
                  style: AppType.body.copyWith(color: t.textSecondary),
                ),
              ),
              Switch(value: off, onChanged: onDayOff),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          if (off)
            const _Note('No Hours Set (Day Off)')
          else if (day.blocks.isEmpty)
            const _Note('No Working Hours Set')
          else ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Total Working Hours: ',
                    style: AppType.bodyStrong.copyWith(color: t.text),
                  ),
                  TextSpan(
                    text: '${day.totalHours} hours',
                    style: AppType.body.copyWith(color: t.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final b in day.blocks)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpace.sm),
                padding: const EdgeInsets.only(left: AppSpace.md),
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 18, color: t.accentText),
                    const SizedBox(width: AppSpace.sm + 2),
                    Expanded(
                      child: Text(
                        '${b.startLabel} – ${b.endLabel}',
                        style: AppType.bodyStrong.copyWith(color: t.text),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      icon: Icon(
                        Icons.edit_rounded,
                        size: 19,
                        color: t.textSecondary,
                      ),
                      onPressed: () => onEdit(b),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: t.danger,
                      ),
                      onPressed: () => onDelete(b),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppType.bodyStrong.copyWith(color: t.textMuted),
      ),
    );
  }
}

/// The web's "Set Working Hours / Add Break" modal: Quick select (Morning,
/// Evening, Full Day) and Custom time (Start Time, End Time).
class _HoursForm extends ConsumerStatefulWidget {
  const _HoursForm({required this.day, this.block});

  final WorkDay day;
  final WorkBlock? block;

  @override
  ConsumerState<_HoursForm> createState() => _HoursFormState();
}

class _HoursFormState extends ConsumerState<_HoursForm> {
  static const _presets = [
    ('Morning (9:00 AM - 1:00 PM)', '09:00', '13:00'),
    ('Evening (2:00 PM - 6:00 PM)', '14:00', '18:00'),
    ('Full Day (9:00 AM - 8:00 PM)', '09:00', '20:00'),
  ];

  late String _start = widget.block?.start ?? '09:00';
  late String _end = widget.block?.end ?? '17:00';
  bool _busy = false;
  String? _error;

  TimeOfDay _tod(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _label(String hhmm) => _tod(hhmm).format(context);

  Future<void> _pick({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _tod(start ? _start : _end),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = _hhmm(picked);
      } else {
        _end = _hhmm(picked);
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    // The web: "end_time must be a date after start_time".
    if (_end.compareTo(_start) <= 0) {
      setState(() => _error = 'The end time must be after the start time.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(meRepositoryProvider);
      final msg = widget.block == null
          ? await repo.addHours(widget.day.slotId, _start, _end)
          : await repo.updateHours(widget.block!.id, _start, _end);
      if (mounted) Navigator.of(context).pop(msg);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Configure your schedule for ',
                style: AppType.body.copyWith(color: t.textSecondary),
              ),
              TextSpan(
                text: widget.day.name,
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          'Quick select:',
          style: AppType.label.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              AppChoiceChip(
                label: p.$1,
                selected: _start == p.$2 && _end == p.$3,
                onTap: () => setState(() {
                  _start = p.$2;
                  _end = p.$3;
                  _error = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          'Custom time:',
          style: AppType.label.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _TimeField(
              label: 'Start Time',
              value: _label(_start),
              onTap: () => _pick(start: true),
            ),
            const SizedBox(width: AppSpace.sm + 2),
            _TimeField(
              label: 'End Time',
              value: _label(_end),
              onTap: () => _pick(start: false),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.md),
          Text(_error!, style: AppType.body.copyWith(color: t.danger)),
        ],
        const SizedBox(height: AppSpace.xl),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Close',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: AppSpace.sm + 2),
            Expanded(
              flex: 2,
              child: AppButton(label: 'Save', loading: _busy, onPressed: _save),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        minSize: 0,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppType.caption.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(value, style: AppType.bodyStrong.copyWith(color: t.text)),
            ],
          ),
        ),
      ),
    );
  }
}
