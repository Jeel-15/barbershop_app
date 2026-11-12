import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'app_button.dart';
import 'overlays.dart';

/// One line of a review: "Skin fade x 2" ... "$70.00".
class ReviewRow {
  const ReviewRow(
    this.label,
    this.value, {
    this.note,
    this.strong = false,
    this.color,
  });

  final String label;
  final String value;

  /// A grey line under the label ("with Mike").
  final String? note;
  final bool strong;

  /// Tints the value (a discount in green).
  final Color? color;
}

/// A titled group of [ReviewRow]s ("Customer", "Services"...).
class ReviewSection {
  const ReviewSection(this.title, this.rows, {this.icon});

  final String title;
  final IconData? icon;
  final List<ReviewRow> rows;
}

/// "Check before you save": everything that is about to be saved, in words, with
/// anything unusual called out, and two buttons. Returns true for [confirmLabel]
/// (the caller then saves) and false for [editLabel], dragging the sheet down or
/// the phone's Back (the form is left exactly as it was).
Future<bool> showReviewSheet(
  BuildContext context, {
  required String title,
  required List<ReviewSection> sections,
  String? intro,
  List<String> warnings = const [],
  ReviewRow? total,
  String confirmLabel = 'Done',
  String editLabel = 'Edit',
}) async {
  final ok = await showAppSheet<bool>(
    context,
    title: title,
    builder: (ctx) => ReviewBody(
      intro: intro,
      sections: sections,
      warnings: warnings,
      total: total,
    ),
    footer: (ctx) => Row(
      children: [
        Expanded(
          flex: 2,
          child: AppButton(
            label: editLabel,
            icon: Icons.edit_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          flex: 3,
          child: AppButton(
            label: confirmLabel,
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The content of the review sheet (also used on its own in tests).
class ReviewBody extends StatelessWidget {
  const ReviewBody({
    super.key,
    required this.sections,
    this.intro,
    this.warnings = const [],
    this.total,
  });

  final String? intro;
  final List<ReviewSection> sections;
  final List<String> warnings;
  final ReviewRow? total;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (intro != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Text(
              intro!,
              style: AppType.body.copyWith(color: t.textSecondary),
            ),
          ),
        if (warnings.isNotEmpty) ...[
          _Warnings(warnings),
          const SizedBox(height: AppSpace.md),
        ],
        for (final s in sections) ...[
          _Section(s),
          const SizedBox(height: AppSpace.md),
        ],
        if (total != null) _Total(total!),
      ],
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings(this.messages);

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: t.isDark ? 0.14 : 0.12),
        borderRadius: AppRadius.card,
        border: Border.all(color: t.warning.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: t.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m,
                      style: AppType.label.copyWith(
                        color: t.text,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.section);

  final ReviewSection section;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (section.icon != null) ...[
                Icon(section.icon, size: 16, color: t.accentText),
                const SizedBox(width: 6),
              ],
              Text(
                section.title.toUpperCase(),
                style: AppType.overline.copyWith(color: t.accentText),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < section.rows.length; i++) ...[
            if (i > 0)
              Divider(height: 14, color: t.border.withValues(alpha: 0.6)),
            _Row(section.rows[i]),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.row);

  final ReviewRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = (row.strong ? AppType.bodyStrong : AppType.body);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: style.copyWith(color: t.text)),
                if (row.note != null)
                  Text(
                    row.note!,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          if (row.value.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(row.value, style: style.copyWith(color: row.color ?? t.text)),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.row);

  final ReviewRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.1),
        borderRadius: AppRadius.card,
        border: Border.all(color: t.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: AppType.bodyStrong.copyWith(color: t.text),
            ),
          ),
          Text(row.value, style: AppText.display(26, color: t.text)),
        ],
      ),
    );
  }
}
