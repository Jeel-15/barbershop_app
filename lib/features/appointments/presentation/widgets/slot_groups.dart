import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:flutter/material.dart';

/// Free times split into Morning / Afternoon / Evening (the web's "Select Time"
/// groups). Used by Reschedule and by the booking form.
class SlotGroups extends StatelessWidget {
  const SlotGroups({
    super.key,
    required this.slots,
    required this.selected,
    required this.onSelected,
    this.current,
  });

  final List<TimeSlot> slots;
  final TimeSlot? selected;
  final ValueChanged<TimeSlot> onSelected;

  /// A time that is already this booking's own (editing): always offered.
  final TimeSlot? current;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final all = [
      if (current != null && slots.every((s) => s.start != current!.start))
        current!,
      ...slots,
    ]..sort((a, b) => a.start.compareTo(b.start));

    Widget group(String title, IconData icon, List<TimeSlot> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Column(
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
            const SizedBox(height: AppSpace.sm + 2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in list)
                  AppChoiceChip(
                    label: s.startLabel,
                    selected: selected?.start == s.start,
                    onTap: () => onSelected(s),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group(
          'Morning',
          Icons.wb_sunny_outlined,
          all.where((s) => s.startHour < 12).toList(),
        ),
        group(
          'Afternoon',
          Icons.wb_twilight_rounded,
          all.where((s) => s.startHour >= 12 && s.startHour < 17).toList(),
        ),
        group(
          'Evening',
          Icons.nightlight_round,
          all.where((s) => s.startHour >= 17).toList(),
        ),
      ],
    );
  }
}
