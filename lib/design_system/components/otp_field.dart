import 'dart:math' as math;

import 'package:barbershop_app/design_system/components/haptics.dart';
import 'package:barbershop_app/design_system/tokens/app_tokens.dart';
import 'package:barbershop_app/design_system/tokens/layout.dart';
import 'package:barbershop_app/design_system/tokens/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One-time-code input: [length] separate boxes fed by a single hidden text
/// field (so the number pad, paste and the phone's SMS/e-mail code suggestion
/// all work). Calls [onCompleted] when the last digit is typed, shakes when
/// [errorText] appears.
class OtpField extends StatefulWidget {
  const OtpField({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.errorText,
    this.enabled = true,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final String? errorText;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpField> createState() => OtpFieldState();
}

class OtpFieldState extends State<OtpField>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant OtpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorText != null && oldWidget.errorText != widget.errorText) {
      AppHaptics.warning();
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onText() {
    setState(() {});
    final text = _controller.text;
    widget.onChanged?.call(text);
    if (text.length == widget.length) widget.onCompleted?.call(text);
  }

  /// Puts a code in (paste button) and clears it ([clear]).
  void setCode(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    _controller.text = digits.length > widget.length
        ? digits.substring(0, widget.length)
        : digits;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void clear() => _controller.clear();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = _controller.text;
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? () => _focus.requestFocus() : null,
          child: Semantics(
            textField: true,
            label: 'Verification code, ${widget.length} digits',
            child: Stack(
              children: [
                // The real input: invisible, but it owns focus, keyboard and paste.
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      autofocus: widget.autofocus,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(widget.length),
                      ],
                      enableInteractiveSelection: false,
                      showCursor: false,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      math.sin(_shake.value * math.pi * 6) *
                          9 *
                          (1 - _shake.value),
                      0,
                    ),
                    child: child,
                  ),
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _Box(
                              char: i < text.length ? text[i] : '',
                              active:
                                  _focus.hasFocus &&
                                  i ==
                                      text.length.clamp(0, widget.length - 1) &&
                                  widget.enabled,
                              error: hasError,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_rounded, size: 15, color: t.danger),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: AppType.caption.copyWith(color: t.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.char, required this.active, required this.error});

  final String char;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final border = error
        ? t.danger
        : (active ? t.accent : (char.isNotEmpty ? t.textMuted : t.border));
    return AnimatedContainer(
      duration: AppMotion.fast,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border, width: active || error ? 1.8 : 1),
      ),
      child: char.isNotEmpty
          ? Text(
              char,
              style: AppType.title.copyWith(color: t.text, fontSize: 26),
            )
          : (active ? _Caret(color: t.accent) : const SizedBox.shrink()),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret({required this.color});

  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(width: 2, height: 26, color: widget.color),
    );
  }
}
