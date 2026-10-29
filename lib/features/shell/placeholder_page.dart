import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';

/// A tab or screen whose real content arrives in a later phase. It keeps the
/// layout (title, bar clearance) so the shell can be judged on its own.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.padForBar = true,
  });

  final String title;
  final IconData icon;
  final String message;
  final bool padForBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: padForBar ? null : AppBar(title: Text(title)),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (padForBar) TabHeader(title: title),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: padForBar ? AppNavBar.reservedHeight(context) : 0,
                ),
                child: EmptyState(
                  icon: icon,
                  title: 'Coming soon',
                  message: message,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
