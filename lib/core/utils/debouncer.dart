import 'dart:async';

/// Waits for the user to stop typing before running [action] (search boxes).
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 350)]);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => cancel();
}
