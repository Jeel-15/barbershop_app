import 'package:flutter/material.dart';

/// What Flutter shows in place of a widget that threw while building (instead
/// of the red or grey error box): a quiet card that says only this part failed.
///
/// It can be built anywhere, even where there is no Theme or Material, so it
/// uses fixed colours and no inherited styles.
class FriendlyErrorWidget extends StatelessWidget {
  const FriendlyErrorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF1B1511),
              borderRadius: BorderRadius.all(Radius.circular(16)),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x33C9A24D)),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.content_cut_rounded,
                    size: 26,
                    color: Color(0xFFC9A24D),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'This part didn’t load',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF3EBDD),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Go back and open it again. Everything else is fine.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFB9AE9C),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
