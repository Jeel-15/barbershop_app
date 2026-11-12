import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The phone's Back button inside the signed-in frame. A page opened on top of
/// the tabs (a form, a profile) closes by itself first; this only decides what
/// Back does on a tab: from another tab it returns to Home, and on Home a second
/// press within two seconds leaves the app (the first one only says so).
class ShellBackHandler extends StatefulWidget {
  const ShellBackHandler({
    super.key,
    required this.atHome,
    required this.onHome,
    required this.onHint,
    required this.child,
    this.onExit,
    this.now = DateTime.now,
  });

  final bool atHome;
  final VoidCallback onHome;

  /// Shows "Press back again to exit".
  final VoidCallback onHint;

  /// Leaves the app (the system call unless a test replaces it).
  final VoidCallback? onExit;
  final DateTime Function() now;
  final Widget child;

  static const window = Duration(seconds: 2);

  @override
  State<ShellBackHandler> createState() => _ShellBackHandlerState();
}

class _ShellBackHandlerState extends State<ShellBackHandler> {
  DateTime? _lastBack;

  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    if (!widget.atHome) {
      _lastBack = null;
      widget.onHome();
      return;
    }
    final now = widget.now();
    final last = _lastBack;
    if (last != null && now.difference(last) < ShellBackHandler.window) {
      (widget.onExit ?? SystemNavigator.pop)();
      return;
    }
    _lastBack = now;
    widget.onHint();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: _onBack,
    child: widget.child,
  );
}
