import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/failure.dart';
import '../brand/barber_pole.dart';
import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'app_button.dart';
import 'connection_scope.dart';

/// What kind of trouble it is, so the words and the little badge fit it.
enum ErrorMood {
  /// The phone has no connection.
  offline(
    'You’re offline',
    'Your saved info is safe. This will reload by itself when the connection is back.',
    Icons.wifi_off_rounded,
  ),

  /// The phone is connected but the shop's server did not answer.
  unreachable(
    'Can’t connect right now',
    'Nothing is lost. Check your internet, then try again.',
    Icons.cloud_off_rounded,
  ),

  /// Took too long.
  slow(
    'This is taking a while',
    'The server is slow right now. Give it a moment, then try again.',
    Icons.hourglass_bottom_rounded,
  ),

  /// Something broke on our side (5xx).
  server(
    'Our side had a hiccup',
    'It wasn’t you, and nothing is lost. Please try again.',
    Icons.build_circle_outlined,
  ),

  /// Anything else.
  generic('Something didn’t load', 'Please try again.', Icons.refresh_rounded);

  const ErrorMood(this.title, this.message, this.icon);
  final String title;
  final String message;
  final IconData icon;

  /// The failures' own sentences are the only thing the screens pass along, so
  /// the mood is read back from them (one place, not 35).
  static ErrorMood fromMessage(String message, {required bool online}) {
    if (!online) return ErrorMood.offline;
    if (message == const NetworkFailure().message) return ErrorMood.unreachable;
    if (message == const TimeoutFailure().message) return ErrorMood.slow;
    if (message == const ServerFailure().message) return ErrorMood.server;
    return ErrorMood.generic;
  }
}

/// A failed load, said calmly: what happened in a human sentence, that the
/// data is safe, and one button.
///
/// * A barber pole stands still with a small badge; while it retries the pole
///   turns, so the wait looks like work, not like a freeze.
/// * When the phone comes back online it tries again by itself (once).
/// * The support code is there, but folded under "Details".
///
/// [title] and [message] are optional overrides: when the screen passes its own
/// (for example "Could not load times"), the title says what failed and the
/// message is shown as the detail line.
class ErrorState extends StatefulWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.supportCode,
    this.icon,
    this.title,
    this.retryFor = const Duration(milliseconds: 900),
  });

  final String? title;
  final String message;
  final VoidCallback? onRetry;
  final String? supportCode;

  /// Overrides the badge of the mood.
  final IconData? icon;

  /// How long the pole turns at least after a tap on "Try again".
  final Duration retryFor;

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _busy = false;
  bool _details = false;
  bool? _wasOnline;
  Timer? _stop;

  void _retry() {
    if (_busy || widget.onRetry == null) return;
    setState(() => _busy = true);
    if (!MediaQuery.disableAnimationsOf(context)) _spin.repeat();
    widget.onRetry!();
    _stop?.cancel();
    _stop = Timer(widget.retryFor, () {
      if (!mounted) return;
      _spin.stop();
      setState(() => _busy = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final online = ConnectionScope.onlineOf(context);
    // Offline -> online while this is showing: try again, once, without a tap.
    if (_wasOnline == false && online) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retry();
      });
    }
    _wasOnline = online;
  }

  @override
  void dispose() {
    _stop?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final online = ConnectionScope.onlineOf(context);
    final mood = ErrorMood.fromMessage(widget.message, online: online);
    // Own title => say what failed, then the mood's reassurance as the detail.
    final title = widget.title ?? mood.title;
    final body = widget.title == null
        ? mood.message
        : (mood == ErrorMood.generic ? widget.message : mood.message);
    // Centred when it fits; scrolls (instead of overflowing) in a small space.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.hasBoundedHeight ? box.maxHeight : 0,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Figure(
                    spin: _spin,
                    icon: widget.icon ?? mood.icon,
                    still: MediaQuery.disableAnimationsOf(context),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppType.heading.copyWith(color: t.text),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: t.textSecondary),
                  ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(height: AppSpace.xl),
                    AppButton(
                      label: _busy ? 'Trying…' : 'Try again',
                      icon: Icons.refresh_rounded,
                      onPressed: _busy ? null : _retry,
                      expand: false,
                      compact: true,
                    ),
                  ],
                  if (widget.supportCode != null) ...[
                    const SizedBox(height: AppSpace.md),
                    _Details(
                      code: widget.supportCode!,
                      open: _details,
                      onToggle: () => setState(() => _details = !_details),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pole, standing quiet (a slow breath), with a badge for the mood.
class _Figure extends StatefulWidget {
  const _Figure({required this.spin, required this.icon, required this.still});

  final Animation<double> spin;
  final IconData icon;
  final bool still;

  @override
  State<_Figure> createState() => _FigureState();
}

class _FigureState extends State<_Figure> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.still) _breath.repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: widget.still ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, enter, child) => Opacity(
            opacity: enter.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.86 + 0.14 * enter, child: child),
          ),
          child: SizedBox(
            width: 96,
            height: 96,
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, widget.spin]),
              builder: (context, _) {
                final b = Curves.easeInOut.transform(_breath.value);
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.textMuted.withValues(alpha: 0.08 + 0.04 * b),
                      ),
                    ),
                    Opacity(
                      opacity: 0.78,
                      child: BarberPole(
                        width: 20,
                        height: 62,
                        phase: widget.spin.value * 1.4,
                        glow: widget.spin.isAnimating ? 0.35 : 0,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 8 + 2 * b,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.surface,
                          border: Border.all(color: t.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, size: 16, color: t.warning),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.code,
    required this.open,
    required this.onToggle,
  });

  final String code;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Details',
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Support code copied')),
                    );
                  },
                  child: Text(
                    'Support code: $code  (tap to copy)',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(color: t.textMuted),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
