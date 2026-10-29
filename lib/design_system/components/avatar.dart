import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Round picture with initials as the fallback (also while loading or if the
/// file is missing).
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.ring = false,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final bool ring;

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.goldGradient,
      ),
      child: Text(
        initials(name),
        style: AppText.ui(
          size * 0.38,
          weight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );

    Widget child = fallback;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      child = ClipOval(
        child: Stack(
          children: [
            // The initials stay underneath until the picture has loaded.
            fallback,
            Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              frameBuilder: (context, image, frame, sync) => sync
                  ? image
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      child: image,
                    ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: name,
      image: true,
      child: Container(
        decoration: ring
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.accent, width: 2),
              )
            : null,
        padding: ring ? const EdgeInsets.all(2) : null,
        child: child,
      ),
    );
  }
}
