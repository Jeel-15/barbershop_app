import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import 'pressable.dart';

/// Round back button (sits on any backdrop).
class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Back',
      child: Pressable(
        onTap: onPressed,
        minSize: 0,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.surface,
            border: Border.all(color: t.border),
          ),
          child: Icon(Icons.arrow_back_rounded, size: 22, color: t.text),
        ),
      ),
    );
  }
}
