import 'package:barbershop_app/design_system/tokens/layout.dart';
import 'package:flutter/material.dart';

/// Tiles in [columns] columns whose rows are as tall as their tallest tile, so
/// large text or a narrow phone never cuts anything off (a fixed aspect ratio
/// does).
class TileGrid extends StatelessWidget {
  const TileGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.spacing = AppSpace.sm + 2,
  });

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: spacing),
                Expanded(
                  child: i + c < children.length
                      ? children[i + c]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}
