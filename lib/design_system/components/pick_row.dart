import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

/// A row in a "pick items" list: a picture, the name, a line of detail, and a
/// gold "× n" badge once the item has been picked. Tap to pick (again for one more).
///
/// The picture is the item's photo; without one (or while it loads, or when it
/// fails) a quiet gold tile with [placeholder] stands in, so the rows line up.
/// A picked item shows a small gold tick on its picture as well as the badge:
/// the picture is what the eye is on, so the state is read there first.
class PickRow extends StatelessWidget {
  const PickRow({
    super.key,
    required this.name,
    required this.detail,
    required this.count,
    required this.onTap,
    this.imageUrl,
    this.placeholder = Icons.content_cut_rounded,
    this.showPicture = true,
  });

  final String name;
  final String detail;
  final int count;
  final VoidCallback onTap;

  /// The item's photo (null / empty = the placeholder tile).
  final String? imageUrl;

  /// What the tile shows without a photo.
  final IconData placeholder;

  /// False keeps the old text-only row.
  final bool showPicture;

  static const double _thumb = 56;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final picked = count > 0;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      minSize: 0,
      child: Semantics(
        button: true,
        selected: picked,
        label: picked ? '$name, picked $count' : name,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.fromLTRB(
            showPicture ? 8 : 14,
            showPicture ? 8 : 12,
            14,
            showPicture ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: picked ? t.accent.withValues(alpha: 0.12) : t.surface,
            borderRadius: AppRadius.control,
            border: Border.all(
              color: picked ? t.accent.withValues(alpha: 0.6) : t.border,
            ),
          ),
          child: Row(
            children: [
              if (showPicture) ...[
                _Thumb(
                  url: imageUrl,
                  icon: placeholder,
                  picked: picked,
                  size: _thumb,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong.copyWith(
                        color: t.text,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      detail,
                      style: AppType.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (picked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '× $count',
                    style: AppType.label.copyWith(
                      color: AppColors.ink,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                Icon(Icons.add_circle_outline_rounded, color: t.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.icon,
    required this.picked,
    required this.size,
  });

  final String? url;
  final IconData icon;
  final bool picked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final box = BorderRadius.circular(12);
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.12),
        borderRadius: box,
        border: Border.all(color: t.accent.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, size: 24, color: t.accentText),
    );
    final hasUrl = (url ?? '').isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The tile stays underneath until the photo has loaded (and for good if it fails).
          tile,
          if (hasUrl)
            ClipRRect(
              borderRadius: box,
              child: Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Photos can be big: decode them at the size shown (3x for sharpness).
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
            ),
          Positioned(
            right: -5,
            bottom: -5,
            child: AnimatedScale(
              scale: picked ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.surface, width: 2),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
