import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/typography.dart';
import 'connection_scope.dart';

/// The calm strip that tells the user about the connection, for the whole app.
///
/// Offline: an amber strip grows from the top edge ("You're offline. Showing
/// saved data."), pushing the page down. Back online: it turns green for a
/// moment ("Back online") and folds away. Nothing is shown while all is well.
///
/// The strip fills the status-bar area too (so it looks like a tinted status
/// bar); the page below gets that much less top inset, so it never jumps.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({
    super.key,
    required this.online,
    required this.child,
    this.restoredFor = const Duration(milliseconds: 2400),
  });

  final bool online;
  final Widget child;
  final Duration restoredFor;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

enum _Phase { hidden, offline, restored }

class _ConnectionBannerState extends State<ConnectionBanner>
    with SingleTickerProviderStateMixin {
  static const _strip = 30.0;

  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  _Phase _phase = _Phase.hidden;
  Timer? _fold;

  @override
  void initState() {
    super.initState();
    if (!widget.online) {
      _phase = _Phase.offline;
      _open.value = 1;
    }
  }

  @override
  void didUpdateWidget(ConnectionBanner old) {
    super.didUpdateWidget(old);
    if (old.online == widget.online) return;
    _fold?.cancel();
    if (!widget.online) {
      setState(() => _phase = _Phase.offline);
      _open.forward();
    } else if (_phase == _Phase.offline) {
      setState(() => _phase = _Phase.restored);
      _fold = Timer(widget.restoredFor, () {
        if (!mounted) return;
        _open.reverse().whenComplete(() {
          if (mounted && widget.online) setState(() => _phase = _Phase.hidden);
        });
      });
    }
  }

  @override
  void dispose() {
    _fold?.cancel();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.padding.top;
    final t = context.tokens;
    final reduce = media.disableAnimations;
    return ConnectionScope(
      online: widget.online,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final h = (inset + _strip) * _t.value;
          // The tree keeps the same shape when hidden, so the app below never
          // loses its state when the strip comes and goes.
          // The page loses only what the strip now covers of its top inset.
          final left = (inset - h).clamp(0.0, inset);
          final restored = _phase == _Phase.restored;
          final tint = restored ? t.success : t.warning;
          return Column(
            children: [
              SizedBox(
                height: h,
                width: double.infinity,
                child: _phase == _Phase.hidden
                    ? null
                    : ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.bottomCenter,
                          minHeight: 0,
                          maxHeight: inset + _strip,
                          child: Container(
                            height: inset + _strip,
                            padding: EdgeInsets.only(top: inset),
                            alignment: Alignment.center,
                            color: Color.alphaBlend(
                              tint.withValues(alpha: 0.2),
                              t.bg,
                            ),
                            child: Semantics(
                              liveRegion: true,
                              child: _Message(
                                restored: restored,
                                tint: tint,
                                still: reduce,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(top: left),
                    viewPadding: media.viewPadding.copyWith(top: left),
                  ),
                  child: widget.child,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Message extends StatefulWidget {
  const _Message({
    required this.restored,
    required this.tint,
    required this.still,
  });

  final bool restored;
  final Color tint;
  final bool still;

  @override
  State<_Message> createState() => _MessageState();
}

class _MessageState extends State<_Message>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.still && !widget.restored) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Message old) {
    super.didUpdateWidget(old);
    final run = !widget.still && !widget.restored;
    if (run && !_breath.isAnimating) _breath.repeat(reverse: true);
    if (!run && _breath.isAnimating) _breath.stop();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _breath,
          builder: (context, child) => Opacity(
            opacity: widget.restored ? 1 : 0.55 + 0.45 * _breath.value,
            child: child,
          ),
          child: Icon(
            widget.restored
                ? Icons.check_circle_rounded
                : Icons.wifi_off_rounded,
            size: 16,
            color: widget.tint,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              widget.restored
                  ? 'Back online'
                  : "You're offline. Showing saved data.",
              key: ValueKey(widget.restored),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                color: t.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
