import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';

/// The title block every main tab starts with, so Home, Bookings, Calendar
/// and More all open the same way: small grey line, serif title, one trailing
/// control (avatar, button...).
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
    this.onTitleTap,
    this.titleSize = 30,
  });

  final String title;

  /// Small upper-case line above the title (the date, a count...).
  final String? eyebrow;
  final Widget? trailing;

  /// Makes the title a button (with a small arrow), e.g. to jump to a date.
  final VoidCallback? onTitleTap;

  /// A shorter page can ask for a smaller title.
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.lg,
        AppSpace.page,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: AppType.overline.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: 4),
                ],
                if (onTitleTap == null)
                  Text(
                    title,
                    style: AppText.display(
                      titleSize,
                      color: t.text,
                      height: 1.12,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onTitleTap,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.display(
                              titleSize,
                              color: t.text,
                              height: 1.12,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 26,
                          color: t.accentText,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}
