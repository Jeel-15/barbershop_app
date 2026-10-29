import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:flutter/material.dart';

/// The web's filter form (Start Date, End Date, Day Type, Staff Name) as a
/// bottom sheet. Returns the new filter, or null if dismissed.
Future<AppointmentFilter?> showAppointmentFilterSheet(
  BuildContext context, {
  required AppointmentFilter current,
  required List<CalendarLane> barbers,
}) {
  final ctl = _FilterController(current);
  return showAppSheet<AppointmentFilter>(
    context,
    title: 'Filter',
    builder: (_) => _FilterBody(ctl: ctl, barbers: barbers),
    footer: (ctx) => ListenableBuilder(
      listenable: ctl,
      builder: (_, _) => Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Clear',
              variant: AppButtonVariant.secondary,
              compact: true,
              onPressed: ctl.isClear
                  ? null
                  : () => Navigator.of(ctx).pop(ctl.cleared()),
            ),
          ),
          const SizedBox(width: AppSpace.sm + 2),
          Expanded(
            flex: 2,
            child: AppButton(
              label: 'Show results',
              compact: true,
              onPressed: () => Navigator.of(ctx).pop(ctl.result),
            ),
          ),
        ],
      ),
    ),
  );
}

enum _Preset { any, today, tomorrow, week, custom }

/// The choices made so far, shared by the sheet body and its pinned buttons.
class _FilterController extends ChangeNotifier {
  _FilterController(this.base)
    : start = base.startDate,
      end = base.endDate,
      dayType = base.dayType,
      staff = base.staffId {
    preset = _presetFor();
  }

  final AppointmentFilter base;
  String? start;
  String? end;
  String? dayType;
  int? staff;
  late _Preset preset;

  _Preset _presetFor() {
    if (start == null || end == null) return _Preset.any;
    final today = ShopTime.today();
    final t = ShopTime.ymd(today);
    final tm = ShopTime.ymd(today.add(const Duration(days: 1)));
    final wk = ShopTime.ymd(today.add(const Duration(days: 6)));
    if (start == t && end == t) return _Preset.today;
    if (start == tm && end == tm) return _Preset.tomorrow;
    if (start == t && end == wk) return _Preset.week;
    return _Preset.custom;
  }

  bool get isClear =>
      start == null && end == null && dayType == null && staff == null;

  void setPreset(_Preset p) {
    final today = ShopTime.today();
    String ymd(DateTime d) => ShopTime.ymd(d);
    preset = p;
    switch (p) {
      case _Preset.any:
        start = null;
        end = null;
      case _Preset.today:
        start = end = ymd(today);
      case _Preset.tomorrow:
        start = end = ymd(today.add(const Duration(days: 1)));
      case _Preset.week:
        start = ymd(today);
        end = ymd(today.add(const Duration(days: 6)));
      case _Preset.custom:
        start ??= ymd(today);
        end ??= ymd(today);
    }
    notifyListeners();
  }

  void setDate(bool isStart, DateTime d) {
    if (isStart) {
      start = ShopTime.ymd(d);
      if (end == null || end!.compareTo(start!) < 0) end = start;
    } else {
      end = ShopTime.ymd(d);
      if (start == null || start!.compareTo(end!) > 0) start = end;
    }
    notifyListeners();
  }

  void setDayType(String? v) {
    dayType = v;
    notifyListeners();
  }

  void setStaff(int? v) {
    staff = v;
    notifyListeners();
  }

  AppointmentFilter get result => base.copyWith(
    startDate: start,
    endDate: end,
    dayType: dayType,
    staffId: staff,
  );

  AppointmentFilter cleared() => base.copyWith(
    startDate: null,
    endDate: null,
    dayType: null,
    staffId: null,
  );
}

class _FilterBody extends StatelessWidget {
  const _FilterBody({required this.ctl, required this.barbers});

  final _FilterController ctl;
  final List<CalendarLane> barbers;

  Future<void> _pick(BuildContext context, bool isStart) async {
    final value = isStart ? ctl.start : ctl.end;
    final d = await showDatePicker(
      context: context,
      initialDate: ShopTime.parseDate(value ?? ShopTime.ymd(ShopTime.today())),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) ctl.setDate(isStart, d);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            icon: Icons.calendar_month_rounded,
            title: 'Date',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (p, text) in const [
                  (_Preset.any, 'Any date'),
                  (_Preset.today, 'Today'),
                  (_Preset.tomorrow, 'Tomorrow'),
                  (_Preset.week, 'Next 7 days'),
                  (_Preset.custom, 'Choose dates'),
                ])
                  AppChoiceChip(
                    label: text,
                    selected: ctl.preset == p,
                    onTap: () => ctl.setPreset(p),
                  ),
              ],
            ),
          ),
          if (ctl.preset == _Preset.custom) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Start Date',
                    value: ctl.start,
                    onTap: () => _pick(context, true),
                  ),
                ),
                const SizedBox(width: AppSpace.sm + 2),
                Expanded(
                  child: _DateField(
                    label: 'End Date',
                    value: ctl.end,
                    onTap: () => _pick(context, false),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          _Section(
            icon: Icons.wb_twilight_rounded,
            title: 'Day Type',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (v, text) in const [
                  (null, 'All Times'),
                  ('Morning', 'Morning'),
                  ('Afternoon', 'Afternoon'),
                  ('Evening', 'Evening'),
                ])
                  AppChoiceChip(
                    label: text,
                    selected: ctl.dayType == v,
                    onTap: () => ctl.setDayType(v),
                  ),
              ],
            ),
          ),
          if (barbers.length > 1) ...[
            const SizedBox(height: AppSpace.xl),
            _Section(
              icon: Icons.content_cut_rounded,
              title: 'Staff Name',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppChoiceChip(
                    label: 'All Staff',
                    selected: ctl.staff == null,
                    onTap: () => ctl.setStaff(null),
                  ),
                  for (final b in barbers)
                    AppChoiceChip(
                      label: b.name,
                      selected: ctl.staff == b.id,
                      onTap: () => ctl.setStaff(b.id),
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

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: t.accentText),
            const SizedBox(width: 7),
            Text(
              title.toUpperCase(),
              style: AppType.overline.copyWith(color: t.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        child,
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onTap,
      minSize: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.control,
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppType.caption.copyWith(color: t.textMuted)),
            const SizedBox(height: 2),
            Text(
              value == null
                  ? 'Select'
                  : ShopTime.dayLabel(ShopTime.parseDate(value!)),
              style: AppType.bodyStrong.copyWith(color: t.text, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
