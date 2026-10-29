import 'package:flutter/material.dart';

import '../../core/utils/debouncer.dart';
import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';

/// Search box that reports the text 350 ms after typing stops.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.initial = '',
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final String initial;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );
  final _debounce = Debouncer();

  @override
  void dispose() {
    _debounce.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextField(
      controller: _c,
      textInputAction: TextInputAction.search,
      style: AppType.body.copyWith(color: t.text),
      cursorColor: t.accent,
      onChanged: (v) {
        setState(() {});
        _debounce.run(() => widget.onChanged(v.trim()));
      },
      onSubmitted: (v) {
        _debounce.cancel();
        widget.onChanged(v.trim());
      },
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        prefixIcon: Icon(Icons.search_rounded, color: t.textMuted),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: Icon(Icons.close_rounded, size: 20, color: t.textMuted),
                onPressed: () {
                  _c.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: t.accent, width: 1.6),
        ),
      ),
    );
  }
}
