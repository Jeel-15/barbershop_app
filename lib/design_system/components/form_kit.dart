import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'app_button.dart';
import 'haptics.dart';
import 'overlays.dart';
import 'round_back_button.dart';

/// A titled group of fields in one card ("Basics", "Price and time"...), so a
/// long form reads as a few small steps instead of one long list.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
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
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 17, color: t.accentText),
                ),
                const SizedBox(width: AppSpace.sm + 2),
              ],
              Expanded(
                child: Text(
                  title,
                  style: AppType.subheading.copyWith(color: t.text),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: AppType.caption.copyWith(color: t.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpace.lg),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.lg),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Two short fields side by side (price and duration).
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpace.md),
        Expanded(child: children[i]),
      ],
    ],
  );
}

/// An on / off setting inside a [FormSection]: the words, one grey line that
/// says what it does, and the switch. Use a divider between two of them.
class SwitchTile extends StatelessWidget {
  const SwitchTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      toggled: value,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AppHaptics.select();
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
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
        ),
      ),
    );
  }
}

/// The frame of a form page: the back button and title, the form, and a button
/// bar that stays at the bottom (above the keyboard). When [dirty] is true,
/// leaving (the back button or the phone's Back) first asks "Discard changes?".
class FormPageFrame extends StatelessWidget {
  const FormPageFrame({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.subtitle,
    this.dirty = false,
    this.bottom,
  });

  final String title;
  final String? subtitle;

  /// Leaves the page (pop, or go to the list when there is nothing to pop to).
  final VoidCallback onClose;
  final bool dirty;
  final Widget child;

  /// Usually a [FormActionBar]; null while the form is still loading.
  final Widget? bottom;

  Future<void> _tryClose(BuildContext context) async {
    if (!dirty) {
      onClose();
      return;
    }
    final leave = await showConfirm(
      context,
      title: 'Discard changes?',
      message: 'What you changed on this page will not be saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (leave) onClose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryClose(context);
      },
      child: Scaffold(
        body: SafeArea(
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
                    RoundBackButton(onPressed: () => _tryClose(context)),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppType.heading.copyWith(color: t.text),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption.copyWith(
                                color: t.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
              ?bottom,
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom bar of a form: one main button, and optionally a quieter one
/// next to it ("Cancel").
class FormActionBar extends StatelessWidget {
  const FormActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.page,
        AppSpace.md,
        AppSpace.page,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          if (secondaryLabel != null) ...[
            Expanded(
              flex: 2,
              child: AppButton(
                label: secondaryLabel!,
                variant: AppButtonVariant.secondary,
                onPressed: loading ? null : onSecondary,
              ),
            ),
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            flex: 3,
            child: AppButton(
              label: label,
              loading: loading,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// After a failed Save: brings the first field that shows an error into view
/// (give each such field a GlobalKey) and nudges the phone. The form's list must
/// build all its sections (a large scroll cache extent), or a field far below
/// has no place to scroll to yet.
void scrollToFirstError(Iterable<GlobalKey?> keys) {
  AppHaptics.warning();
  // The frame that shows the errors may already be on its way; make sure one is.
  WidgetsBinding.instance.ensureVisualUpdate();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final k in keys) {
      final c = k?.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(
          c,
          alignment: 0.12,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
  });
}
