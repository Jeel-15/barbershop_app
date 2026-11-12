import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';

/// Labelled input: the label sits above the field (always visible, easier to
/// read than a floating label), errors appear under it in words.
///
/// A label that ends in `*` shows the star in red (the web's wording stays, the
/// required mark becomes easy to see). Units go in [prefixText] (`$`) or
/// [suffixText] (`min`, `%`). With a [validator] the field checks itself when it
/// loses focus for the first time, then again on every change, so a mistake is
/// shown after the person has finished typing and goes away the moment it is
/// fixed. An [errorText] from outside (the server's answer) always wins.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.autofillHints,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.prefixText,
    this.suffixText,
    this.showCounter = false,
    this.clearable = false,
    this.validator,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final String? prefixText;

  /// A unit after the value ("min", "%").
  final String? suffixText;

  /// Shows "12/200" under the field (needs [maxLength]).
  final bool showCounter;

  /// A small x while the field has focus and text, to empty it in one tap.
  final bool clearable;

  /// Returns the message to show, or null when the value is fine.
  final String? Function(String value)? validator;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;
  FocusNode? _ownFocus;
  TextEditingController? _ownController;
  bool _touched = false;
  String? _found;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(AppTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onText);
      _controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _controller.removeListener(_onText);
    _ownFocus?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  void _validate() {
    final found = widget.validator?.call(_controller.text);
    if (found != _found) setState(() => _found = found);
  }

  void _onFocus() {
    // The first time the person leaves the field, judge what they typed.
    if (!_focus.hasFocus && !_touched && _controller.text.isNotEmpty) {
      _touched = true;
      _validate();
    }
    if (mounted) setState(() {});
  }

  void _onText() {
    if (_touched) _validate();
    // The clear button and the counter follow the text.
    if (mounted && (widget.clearable || widget.showCounter)) setState(() {});
  }

  Widget _label(AppTokens t, bool hasError) => FieldLabel(
    widget.label!,
    color: hasError
        ? t.danger
        : _focus.hasFocus
        ? t.accentText
        : t.textSecondary,
  );

  /// What sits at the end of the field: the unit, the clear x, the password eye,
  /// or whatever the caller passed.
  Widget? _suffix(AppTokens t, bool showClear) {
    final Widget? inner = widget.obscure
        ? IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            icon: Icon(
              _hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 20,
              color: t.textMuted,
            ),
            onPressed: () => setState(() => _hidden = !_hidden),
          )
        : showClear
        ? IconButton(
            tooltip: 'Clear',
            icon: Icon(Icons.cancel_rounded, size: 19, color: t.textMuted),
            onPressed: () {
              _controller.clear();
              widget.onChanged?.call('');
            },
          )
        : widget.suffix;
    final unit = widget.suffixText;
    if (unit == null) return inner;
    return Padding(
      padding: EdgeInsets.only(right: inner == null ? 14 : 0, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(unit, style: AppType.body.copyWith(color: t.textSecondary)),
          ?inner,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final error = widget.errorText ?? _found;
    final hasError = error != null;
    final showClear =
        widget.clearable &&
        !widget.obscure &&
        _focus.hasFocus &&
        _controller.text.isNotEmpty;
    final counter = widget.showCounter && widget.maxLength != null
        ? '${_controller.text.characters.length}/${widget.maxLength}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          _label(t, hasError),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          inputFormatters: widget.inputFormatters,
          autofillHints: widget.autofillHints,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          style: AppType.body.copyWith(color: t.text),
          cursorColor: t.accent,
          decoration: InputDecoration(
            hintText: widget.hint,
            counterText: '',
            // Units are drawn as icons: Flutter hides prefixText / suffixText
            // while the field is empty and unfocused, but keeps their room.
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, size: 20, color: t.textMuted)
                : widget.prefixText == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 14, right: 2),
                    child: Text(
                      widget.prefixText!.trimRight(),
                      style: AppType.body.copyWith(color: t.textSecondary),
                    ),
                  ),
            prefixIconConstraints: widget.prefixIcon == null
                ? const BoxConstraints(minWidth: 0, minHeight: 0)
                : null,
            suffixIcon: _suffix(t, showClear),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.control,
              borderSide: BorderSide(color: hasError ? t.danger : t.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.control,
              borderSide: BorderSide(
                color: hasError ? t.danger : t.accent,
                width: 1.6,
              ),
            ),
          ),
        ),
        if (hasError || widget.helperText != null || counter != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasError) ...[
                Icon(Icons.error_rounded, size: 15, color: t.danger),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  error ?? widget.helperText ?? '',
                  style: AppType.caption.copyWith(
                    color: hasError ? t.danger : t.textMuted,
                  ),
                ),
              ),
              if (counter != null) ...[
                const SizedBox(width: 8),
                Text(
                  counter,
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// A field's label. A trailing `*` is drawn in red: the web's wording stays,
/// the required mark gets easy to see.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final raw = text.trimRight();
    final required = raw.endsWith('*');
    final base = required ? raw.substring(0, raw.length - 1).trimRight() : raw;
    return Text.rich(
      TextSpan(
        text: base,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: t.danger, fontWeight: FontWeight.w700),
            ),
        ],
      ),
      style: AppType.label.copyWith(color: color ?? t.textSecondary),
    );
  }
}
