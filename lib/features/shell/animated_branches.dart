import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The tabs of the app: all kept alive (so each keeps its scroll and its data),
/// one shown. Switching fades the new tab in with a small rise (Material "fade
/// through", 240 ms); nothing is rebuilt and nothing is kept animating.
class AnimatedBranches extends StatefulWidget {
  const AnimatedBranches({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  State<AnimatedBranches> createState() => _AnimatedBranchesState();
}

class _AnimatedBranchesState extends State<AnimatedBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(AnimatedBranches old) {
    super.didUpdateWidget(old);
    if (old.navigationShell.currentIndex !=
            widget.navigationShell.currentIndex &&
        !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.navigationShell.currentIndex;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != current,
            // Hidden tabs do not tick or paint.
            child: TickerMode(
              enabled: i == current,
              child: i == current
                  ? FadeTransition(
                      opacity: _a,
                      child: AnimatedBuilder(
                        animation: _a,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, 10 * (1 - _a.value)),
                          child: child,
                        ),
                        child: widget.children[i],
                      ),
                    )
                  : widget.children[i],
            ),
          ),
      ],
    );
  }
}
