import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

/// Small "- 2 +" control for quantities (services, products).
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.qty,
    required this.onChanged,
  });

  final int qty;

  /// Called with the new quantity; 0 means "remove".
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget btn(IconData icon, VoidCallback onTap, String label) => Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        minSize: 0,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: t.accentText),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, () => onChanged(qty - 1), 'Fewer'),
          SizedBox(
            width: 22,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: AppType.bodyStrong.copyWith(color: t.text),
            ),
          ),
          btn(Icons.add_rounded, () => onChanged(qty + 1), 'More'),
        ],
      ),
    );
  }
}
