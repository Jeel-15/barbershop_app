import 'dart:io';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The frame every catalog list shares: back button, title, the web's
/// subtitle, an Add button (when the user may add) and a search box.
class AdminListShell extends StatelessWidget {
  const AdminListShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    this.addLabel,
    this.onAdd,
    this.searchHint,
    this.query = '',
    this.onSearch,
  });

  final String title;
  final String subtitle;
  final Widget body;

  /// Tooltip / semantic label of the Add button; the button shows only with [onAdd].
  final String? addLabel;
  final VoidCallback? onAdd;
  final String? searchHint;
  final String query;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.sm,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  RoundBackButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/app/more'),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      title,
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                  if (onAdd != null)
                    HeaderIconButton(
                      icon: Icons.add_rounded,
                      label: addLabel ?? 'Add',
                      onTap: onAdd!,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                0,
                AppSpace.page,
                AppSpace.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle,
                  style: AppType.caption.copyWith(color: t.textSecondary),
                ),
              ),
            ),
            if (onSearch != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.page,
                  vertical: AppSpace.sm,
                ),
                child: AppSearchField(
                  hint: searchHint ?? 'Search',
                  initial: query,
                  onChanged: onSearch!,
                ),
              ),
            Divider(height: 1, color: t.border),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// A scrolling area that can always be pulled to refresh.
class ScrollableCenter extends StatelessWidget {
  const ScrollableCenter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [SizedBox(height: 480, child: child)],
  );
}

/// A paged list with pull-to-refresh, skeleton, error and empty states.
class PagedBody<T> extends StatefulWidget {
  const PagedBody({
    super.key,
    required this.async,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onRetry,
    required this.onMore,
    required this.emptyTitle,
    required this.emptyMessage,
    this.countLabel,
  });

  final AsyncValue<PagedState<T>> async;
  final Widget Function(BuildContext, T) itemBuilder;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onMore;
  final String emptyTitle;
  final String emptyMessage;

  /// "ALL SERVICES" etc. shown above the rows with the total.
  final String? countLabel;

  @override
  State<PagedBody<T>> createState() => _PagedBodyState<T>();
}

class _PagedBodyState<T> extends State<PagedBody<T>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) widget.onMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.async.value;
    Widget content;
    if (s == null) {
      content = widget.async.hasError
          ? ScrollableCenter(
              child: ErrorState(
                message: widget.async.error is Failure
                    ? (widget.async.error! as Failure).userMessage
                    : 'Could not load this list.',
                supportCode: widget.async.error is Failure
                    ? (widget.async.error! as Failure).requestId
                    : null,
                onRetry: widget.onRetry,
              ),
            )
          : const Padding(
              padding: EdgeInsets.only(top: AppSpace.md),
              child: SkeletonRows(count: 6),
            );
    } else if (s.items.isEmpty) {
      content = ScrollableCenter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: QuietState(
            title: widget.emptyTitle,
            message: widget.emptyMessage,
          ),
        ),
      );
    } else {
      content = EntranceHost(
        // Rows built right after the list opens come in one by one.
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            AppSpace.md,
            AppSpace.page,
            AppSpace.xxl,
          ),
          itemCount: s.items.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Text(
                  '${widget.countLabel ?? 'ALL'} · ${s.total}',
                  style: AppType.overline.copyWith(color: t.textMuted),
                ),
              );
            }
            if (i == s.items.length + 1) {
              if (s.loadingMore) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              }
              if (s.loadMoreFailed) {
                return TextButton(
                  onPressed: widget.onMore,
                  child: const Text('Could not load more. Tap to retry'),
                );
              }
              return const SizedBox.shrink();
            }
            return StaggerIn(
              index: i - 1,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
                child: widget.itemBuilder(context, s.items[i - 1]),
              ),
            );
          },
        ),
      );
    }
    return AppRefresh(onRefresh: widget.onRefresh, child: content);
  }
}

/// One catalog row: picture, two or three lines, a trailing block and a menu.
class AdminTile extends StatelessWidget {
  const AdminTile({
    super.key,
    required this.title,
    required this.lines,
    this.imageUrl,
    this.icon,
    this.trailing,
    this.badge,
    this.onTap,
    this.menu = const [],
    this.onMenu,
  });

  final String title;
  final List<String> lines;
  final String? imageUrl;

  /// Shown when there is no picture.
  final IconData? icon;
  final Widget? trailing;
  final Widget? badge;
  final VoidCallback? onTap;

  /// Menu entries as `(key, label, destructive)`.
  final List<(String, String, bool)> menu;
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final card = Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        menu.isEmpty ? AppSpace.md : AppSpace.xs,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          _Thumb(url: imageUrl, icon: icon, name: title),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A long name keeps its words (up to two lines); the status pill drops
                // below it instead of squeezing the name into "Aftersh...".
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                    ?badge,
                  ],
                ),
                for (final l in lines)
                  Text(
                    l,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (menu.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: t.textSecondary,
              ),
              color: t.surfaceRaised,
              onSelected: onMenu,
              itemBuilder: (_) => [
                for (final m in menu)
                  PopupMenuItem(
                    value: m.$1,
                    child: Text(
                      m.$2,
                      style: m.$3 ? TextStyle(color: t.danger) : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
    return onTap == null
        ? card
        : Pressable(onTap: onTap, scale: 0.99, minSize: 0, child: card);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.icon, required this.name});

  final String? url;
  final IconData? icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final box = BorderRadius.circular(12);
    if ((url ?? '').isNotEmpty) {
      // The tile stays underneath while the picture loads (and for good if it
      // fails), so a slow or missing photo never leaves a hole in the row.
      return Stack(
        children: [
          _fallback(t, box),
          ClipRRect(
            borderRadius: box,
            child: Image.network(
              url!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              cacheWidth: 156,
              errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52),
              frameBuilder: (context, image, frame, sync) => sync
                  ? image
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 220),
                      child: image,
                    ),
            ),
          ),
        ],
      );
    }
    return _fallback(t, box);
  }

  Widget _fallback(AppTokens t, BorderRadius box) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: t.accent.withValues(alpha: 0.12),
      borderRadius: box,
    ),
    child: Icon(icon ?? Icons.image_outlined, size: 22, color: t.accentText),
  );
}

/// The picture field of a form: shows the saved picture or the picked one,
/// opens the gallery on tap and shows the error in words. [compact] is a square
/// tile with the words beside it (a form that has more to fill in); the default
/// is the wide picture.
class ImagePickField extends StatelessWidget {
  const ImagePickField({
    super.key,
    required this.label,
    required this.onPick,
    this.pickedPath,
    this.savedUrl,
    this.error,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPick;
  final String? pickedPath;
  final String? savedUrl;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final has = pickedPath != null || (savedUrl ?? '').isNotEmpty;
    return compact ? _compact(t, has) : _wide(t, has);
  }

  Widget _picture(AppTokens t, {required Widget empty}) => pickedPath != null
      ? Image.file(File(pickedPath!), fit: BoxFit.cover)
      : (savedUrl ?? '').isNotEmpty
      ? Image.network(
          savedUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => empty,
        )
      : empty;

  Widget _compact(AppTokens t, bool has) {
    final edge = error == null ? t.border : t.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, color: error == null ? null : t.danger),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              button: true,
              label: has ? 'Change photo' : 'Choose photo',
              child: Pressable(
                onTap: onPick,
                minSize: 0,
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: has
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: _picture(t, empty: const SizedBox()),
                              )
                            : CustomPaint(
                                painter: _DashedBorder(color: edge, radius: 18),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: t.accent.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_rounded,
                                        size: 30,
                                        color: t.accentText,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Choose photo',
                                        style: AppType.caption.copyWith(
                                          color: t.accentText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      if (has)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: t.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.border),
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 15,
                              color: t.accentText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error ??
                        (has
                            ? 'Tap the photo to change it.'
                            : 'A clear photo.'),
                    style: AppType.label.copyWith(
                      color: error == null ? t.text : t.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'JPG, PNG or GIF. Max 2MB.',
                    style: AppType.caption.copyWith(color: t.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _wide(AppTokens t, bool has) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 8),
        Pressable(
          onTap: onPick,
          minSize: 0,
          child: Container(
            width: double.infinity,
            height: 150,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: error == null ? t.border : t.danger),
            ),
            child: _picture(t, empty: _empty(t)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          error ?? (has ? 'Tap to change' : 'JPG, PNG or GIF. Max 2MB.'),
          style: AppType.caption.copyWith(
            color: error == null ? t.textMuted : t.danger,
          ),
        ),
      ],
    );
  }

  Widget _empty(AppTokens t) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_photo_alternate_rounded, size: 30, color: t.accentText),
      const SizedBox(height: 6),
      Text(
        'Choose photo',
        style: AppType.label.copyWith(color: t.textSecondary),
      ),
    ],
  );
}

/// A dashed rounded outline: "put something here".
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.8),
      );
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// A labelled switch row (Active, Eligible for Tip, Default...).
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.bodyStrong.copyWith(color: t.text)),
                if (hint != null)
                  Text(
                    hint!,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The web's single-choice Category select, as chips.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.names,
    required this.selected,
    required this.onSelected,
    this.error,
  });

  /// Category id → name.
  final Map<int, String> names;
  final int? selected;
  final ValueChanged<int> onSelected;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in names.entries)
              AppChoiceChip(
                label: e.value,
                selected: selected == e.key,
                onTap: () => onSelected(e.key),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              style: AppType.caption.copyWith(color: t.danger),
            ),
          ),
      ],
    );
  }
}
