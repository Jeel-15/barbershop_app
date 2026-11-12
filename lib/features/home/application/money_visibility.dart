import 'dart:async';

import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the money card on More shows its amount. Hidden at every app start
/// (nothing is saved), shown by the eye, hidden again after [autoHide] or when
/// the app leaves the foreground, and when another person signs in.
class MoneyVisibility extends Notifier<bool> {
  static const autoHide = Duration(seconds: 60);

  Timer? _timer;
  late final _Lifecycle _lifecycle;

  @override
  bool build() {
    // A different user must never inherit the revealed state.
    ref.watch(currentUserProvider.select((u) => u.id));
    _lifecycle = _Lifecycle(hide);
    WidgetsBinding.instance.addObserver(_lifecycle);
    ref.onDispose(() {
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(_lifecycle);
    });
    return false;
  }

  void reveal() {
    state = true;
    _timer?.cancel();
    _timer = Timer(autoHide, hide);
  }

  void hide() {
    _timer?.cancel();
    if (state) state = false;
  }

  void toggle() => state ? hide() : reveal();
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this._hide);

  final VoidCallback _hide;

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _hide();
  }
}

final moneyVisibilityProvider = NotifierProvider<MoneyVisibility, bool>(
  MoneyVisibility.new,
);
