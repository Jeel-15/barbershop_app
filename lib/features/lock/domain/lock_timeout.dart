/// How long the app may be left, or sit untouched, before it asks for the
/// fingerprint again.
enum LockTimeout {
  /// Every time the app is left. (No inactivity timer in front: the screen in
  /// use is never locked under the person's finger.)
  immediately(0, 'Immediately'),
  oneMinute(60, '1 minute'),
  fiveMinutes(300, '5 minutes'),
  fifteenMinutes(900, '15 minutes');

  const LockTimeout(this.seconds, this.label);

  final int seconds;
  final String label;

  Duration get duration => Duration(seconds: seconds);

  static const fallback = LockTimeout.fiveMinutes;

  static LockTimeout fromSeconds(int seconds) =>
      values.firstWhere((t) => t.seconds == seconds, orElse: () => fallback);
}
