import 'package:flutter/material.dart';

/// Raw brand colours (identical in dark and light). Screens should prefer the
/// semantic [AppTokens] so both themes keep working; use these only for brand
/// moments (splash, welcome, gold buttons).
class AppColors {
  static const ink = Color(0xFF0B0806);
  static const espresso = Color(0xFF1A120C);
  static const walnut = Color(0xFF2A1B10);
  static const gold = Color(0xFFC4A265);
  static const goldLight = Color(0xFFF3DDA4);
  static const goldDeep = Color(0xFF8C4E24);
  static const cream = Color(0xFFF5ECDD);

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold, goldDeep],
  );
}

/// Appointment statuses, mapped like the web's badges so staff keep the same
/// mental model: pending = amber, confirmed = blue, rescheduled = violet,
/// completed = green, cancelled = red. The words are the web's own: the
/// appointment table badges ([label]) and the status filter ([filterLabel]).
enum AppointmentStatus {
  pending(0, 'Pending', 'Pending', Icons.hourglass_top_rounded),
  completed(1, 'Complete', 'Completed', Icons.check_circle_rounded),
  cancelled(2, 'Reject', 'Cancel', Icons.cancel_rounded),
  confirmed(3, 'Confirm', 'Confirm', Icons.verified_rounded),
  rescheduled(4, 'Reschedule', 'Reschedule', Icons.event_repeat_rounded);

  const AppointmentStatus(this.code, this.label, this.filterLabel, this.icon);

  final int code;

  /// Badge text, as in the web's appointment table.
  final String label;

  /// Option text of the web's Status filter.
  final String filterLabel;
  final IconData icon;

  static AppointmentStatus fromCode(int code) =>
      values.firstWhere((s) => s.code == code, orElse: () => pending);
}
