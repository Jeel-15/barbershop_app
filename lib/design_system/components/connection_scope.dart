import 'package:flutter/widgets.dart';

/// Whether the phone has a connection, told to everything below it.
///
/// The design system stays free of providers: the app puts one of these near
/// the top (fed by the connectivity provider) and the state views read it.
/// Without one above them they assume "online".
class ConnectionScope extends InheritedWidget {
  const ConnectionScope({
    super.key,
    required this.online,
    required super.child,
  });

  final bool online;

  static bool onlineOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectionScope>()?.online ??
      true;

  @override
  bool updateShouldNotify(ConnectionScope old) => old.online != online;
}
