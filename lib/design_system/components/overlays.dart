import 'package:barbershop_app/design_system/motion/success_burst.dart';
import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'app_button.dart';
import 'haptics.dart';

/// Bottom sheet: grabber, a title row with a close button, scrollable content
/// and an optional [footer] pinned under it (the sheet's buttons). It opens on
/// the root navigator, so it always covers the floating nav bar.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  String? title,
  required WidgetBuilder builder,
  WidgetBuilder? footer,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (ctx) {
      final t = ctx.tokens;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  0,
                  AppSpace.md,
                  AppSpace.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppType.heading.copyWith(color: t.text),
                      ),
                    ),
                    if (dismissible)
                      IconButton(
                        tooltip: 'Close',
                        icon: Icon(Icons.close_rounded, color: t.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.xs,
                  AppSpace.page,
                  AppSpace.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [builder(ctx)],
                ),
              ),
            ),
            if (footer != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.page,
                  AppSpace.md + MediaQuery.paddingOf(ctx).bottom,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: footer(ctx),
              )
            else
              SizedBox(height: MediaQuery.paddingOf(ctx).bottom + AppSpace.sm),
          ],
        ),
      );
    },
  );
}

/// Yes/No question. [destructive] makes the confirm button red and the safe
/// option the default focus. Returns true only when confirmed.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: cancelLabel,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: AppButton(
                label: confirmLabel,
                variant: destructive
                    ? AppButtonVariant.danger
                    : AppButtonVariant.primary,
                compact: true,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// "Done. Undo" snackbar for optimistic actions. [onUndo] runs if the user taps Undo within 5 s.
void showUndoSnack(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          AppHaptics.tap();
          onUndo();
        },
      ),
    ),
  );
}

enum ToastKind { info, success, error }

/// Short message with an icon (not for undoable actions).
void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
}) {
  final t = context.tokens;
  final (icon, color) = switch (kind) {
    ToastKind.success => (Icons.check_circle_rounded, t.success),
    ToastKind.error => (Icons.error_rounded, t.danger),
    ToastKind.info => (Icons.info_rounded, t.info),
  };
  if (kind == ToastKind.success) AppHaptics.success();
  if (kind == ToastKind.error) AppHaptics.warning();
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          kind == ToastKind.success
              ? AnimatedCheck(color: color, size: 22)
              : Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
