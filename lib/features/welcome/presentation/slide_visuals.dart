import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barbershop_app/design_system/design_system.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// ---------------------------------------------------------------------------
// Slide 1: "Today" at a glance. A glass dashboard card with counting numbers,
// an hour-by-hour bar chart and the next client, plus two drifting notices.
// Tap a tile to move the highlight.
// ---------------------------------------------------------------------------
class TodayPulse extends StatefulWidget {
  const TodayPulse({super.key});

  @override
  State<TodayPulse> createState() => _TodayPulseState();
}

class _TodayPulseState extends State<TodayPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  static const _tiles = [
    (Icons.event_available_rounded, 'Bookings', 12.0, '', 0),
    (Icons.payments_rounded, 'Revenue', 486.0, r'$', 0),
    (Icons.volunteer_activism_rounded, 'Tips', 62.0, r'$', 0),
  ];
  static const _bars = [3.0, 5.0, 4.0, 6.0, 8.0, 5.0, 7.0, 4.0];

  int _hi = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date =
        '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

    return SizedBox(
      width: 340,
      height: 392,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final a = _c.value * math.pi * 2;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 7,
                top: 26,
                width: 326,
                child: Glass(
                  radius: 30,
                  blur: 22,
                  tint: 0.1,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'TODAY',
                            style: AppText.ui(
                              11,
                              weight: FontWeight.w800,
                              letterSpacing: 2.6,
                              color: AppColors.gold,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            date,
                            style: AppText.ui(
                              12.5,
                              weight: FontWeight.w600,
                              color: AppColors.cream.withValues(alpha: 0.7),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF5BD68A),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF5BD68A,
                                  ).withValues(alpha: 0.4 + 0.4 * math.sin(a)),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE',
                            style: AppText.ui(
                              10,
                              weight: FontWeight.w800,
                              letterSpacing: 1.6,
                              color: const Color(0xFF5BD68A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (var i = 0; i < _tiles.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _KpiTile(
                                icon: _tiles[i].$1,
                                label: _tiles[i].$2,
                                value: _tiles[i].$3,
                                prefix: _tiles[i].$4,
                                selected: i == _hi,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _hi = i);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Bookings by hour',
                        style: AppText.ui(
                          11.5,
                          weight: FontWeight.w700,
                          color: AppColors.cream.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 62,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < _bars.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: 1),
                                  duration: Duration(
                                    milliseconds: 700 + i * 90,
                                  ),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, t, _) {
                                    final wave =
                                        1 + 0.07 * math.sin(a + i * 0.8);
                                    return Container(
                                      height:
                                          8 + (_bars[i] / 8) * 52 * t * wave,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(7),
                                        gradient: i == 4
                                            ? AppColors.goldGradient
                                            : null,
                                        color: i == 4
                                            ? null
                                            : Colors.white.withValues(
                                                alpha: 0.16,
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final h in [
                            '9',
                            '10',
                            '11',
                            '12',
                            '1',
                            '2',
                            '3',
                            '4',
                          ])
                            Text(
                              h,
                              style: AppText.ui(
                                10,
                                color: AppColors.cream.withValues(alpha: 0.45),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: Colors.white.withValues(alpha: 0.07),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const _Avatar('D'),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Daniel R.',
                                    style: AppText.ui(
                                      13.5,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Skin fade · with Alex',
                                    style: AppText.ui(
                                      11.5,
                                      color: AppColors.cream.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'in 25 min',
                                  style: AppText.ui(
                                    12.5,
                                    weight: FontWeight.w800,
                                    color: AppColors.goldLight,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const _StatusPill(
                                  label: 'Confirmed',
                                  color: Color(0xFF5BD68A),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -4 + math.sin(a) * 4,
                top: 2 + math.cos(a) * 5,
                child: const _Notice(
                  icon: Icons.notifications_active_rounded,
                  text: '3 new requests',
                ),
              ),
              Positioned(
                left: -6 + math.cos(a) * 4,
                bottom: -16 + math.sin(a + 1) * 4,
                child: const _Notice(
                  icon: Icons.sync_rounded,
                  text: 'Calendar live',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 30,
      blur: 16,
      tint: 0.14,
      padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.goldGradient,
            ),
            child: Icon(icon, size: 15, color: AppColors.ink),
          ),
          const SizedBox(width: 8),
          Text(text, style: AppText.ui(12.5, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.prefix,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double value;
  final String prefix;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.ink : AppColors.cream;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected ? AppColors.goldGradient : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.14),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.38),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? AppColors.ink : AppColors.gold,
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '$prefix${v.round()}',
                style: AppText.ui(21, weight: FontWeight.w800, color: fg),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.ui(
                10.5,
                weight: FontWeight.w600,
                color: fg.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.letter, {this.size = 36});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.goldGradient,
      ),
      child: Text(
        letter,
        style: AppText.display(
          size * 0.5,
          weight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: AppText.ui(10.5, weight: FontWeight.w800, color: color),
      ),
    );
  }
}

/// Small caption that tells people the visual is interactive.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 20,
      blur: 10,
      tint: 0.08,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app_rounded, size: 14, color: AppColors.gold),
          const SizedBox(width: 7),
          Text(
            text,
            style: AppText.ui(
              11.5,
              weight: FontWeight.w600,
              color: AppColors.cream.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide 2: 3D tilting stack of barber cards, each with its day as a timeline.
// Drag to rotate, tap to bring the next barber to the front.
// ---------------------------------------------------------------------------
class BarberDeck extends StatefulWidget {
  const BarberDeck({super.key});

  @override
  State<BarberDeck> createState() => _BarberDeckState();
}

class _BarberData {
  const _BarberData(
    this.image,
    this.name,
    this.role,
    this.today,
    this.next,
    this.booked,
  );
  final String image;
  final String name;
  final String role;
  final String today;
  final String next;
  final List<bool> booked;
}

class _BarberDeckState extends State<BarberDeck> {
  static const _cards = [
    _BarberData(
      'assets/images/cut.jpg',
      'Alex',
      'Master barber',
      '9 today',
      'Next · 2:30 PM',
      [true, true, false, true, true, true, false, true],
    ),
    _BarberData(
      'assets/images/style.jpg',
      'Sam',
      'Fade specialist',
      '7 today',
      'Next · 3:00 PM',
      [true, false, true, true, false, true, true, false],
    ),
    _BarberData(
      'assets/images/barber_working.jpg',
      'Jordan',
      'Beard & shave',
      '5 today',
      'Next · 1:15 PM',
      [false, true, true, false, true, false, true, true],
    ),
  ];

  // slot of each card: 0 = front, 1 = right-back, 2 = left-back
  final List<int> _slots = [0, 1, 2];

  static const _slotSpec = [
    (left: 52.0, top: 38.0, angle: 0.0, scale: 1.0, depth: 1.0),
    (left: 122.0, top: 22.0, angle: 0.13, scale: 0.9, depth: 0.5),
    (left: -4.0, top: 30.0, angle: -0.13, scale: 0.9, depth: 0.3),
  ];

  void _shuffle() {
    HapticFeedback.selectionClick();
    setState(() {
      for (var i = 0; i < _slots.length; i++) {
        _slots[i] = (_slots[i] + 2) % 3;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _shuffle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tilt3D(
            builder: (context, tilt) {
              final order = List<int>.generate(3, (i) => i)
                ..sort((a, b) => _slots[b].compareTo(_slots[a]));
              return SizedBox(
                width: 320,
                height: 350,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final i in order)
                      AnimatedPositioned(
                        key: ValueKey(_cards[i].name),
                        duration: const Duration(milliseconds: 650),
                        curve: Curves.easeOutBack,
                        left:
                            _slotSpec[_slots[i]].left +
                            tilt.dx * -16 * _slotSpec[_slots[i]].depth,
                        top:
                            _slotSpec[_slots[i]].top +
                            tilt.dy * -10 * _slotSpec[_slots[i]].depth,
                        child: AnimatedRotation(
                          turns: _slotSpec[_slots[i]].angle / (math.pi * 2),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutBack,
                          child: AnimatedScale(
                            scale: _slotSpec[_slots[i]].scale,
                            duration: const Duration(milliseconds: 650),
                            curve: Curves.easeOutBack,
                            child: _BarberCard(
                              data: _cards[i],
                              tilt: tilt,
                              front: _slots[i] == 0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const _Hint('Drag to tilt  ·  Tap to switch barber'),
        ],
      ),
    );
  }
}

class _BarberCard extends StatelessWidget {
  const _BarberCard({
    required this.data,
    required this.tilt,
    required this.front,
  });

  final _BarberData data;
  final Offset tilt;
  final bool front;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 206,
      height: 286,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: front ? 0.75 : 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 34,
            offset: Offset(-tilt.dx * 14, 20 - tilt.dy * 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(data.image, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.ink.withValues(alpha: 0.94),
                  ],
                  stops: const [0.34, 0.9],
                ),
              ),
            ),
            if (front)
              // Specular sheen that slides with the tilt.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.2 + tilt.dx * 1.6, -1),
                    end: Alignment(0.2 + tilt.dx * 1.6, 1),
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 14,
              top: 14,
              child: Glass(
                radius: 14,
                blur: 8,
                tint: 0.16,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  data.today,
                  style: AppText.ui(11, weight: FontWeight.w800),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: AppText.display(23, weight: FontWeight.w700),
                  ),
                  Text(
                    data.role,
                    style: AppText.ui(
                      12,
                      color: AppColors.cream.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // The day: gold blocks are booked, pale blocks are free.
                  Row(
                    children: [
                      for (final b in data.booked)
                        Expanded(
                          child: Container(
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              gradient: b ? AppColors.goldGradient : null,
                              color: b
                                  ? null
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        data.next,
                        style: AppText.ui(
                          12.5,
                          weight: FontWeight.w600,
                          color: AppColors.cream.withValues(alpha: 0.85),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.goldGradient,
                        ),
                        child: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 16,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide 3: a booking request you can actually answer: confirm, move it to a
// free slot, or cancel. The status pill and buttons react.
// ---------------------------------------------------------------------------
enum _Req { pending, confirmed, rescheduled, cancelled }

class RequestActionCard extends StatefulWidget {
  const RequestActionCard({super.key});

  @override
  State<RequestActionCard> createState() => _RequestActionCardState();
}

class _RequestActionCardState extends State<RequestActionCard> {
  static const _slots = ['10:30 AM', '11:00 AM', '12:00 PM', '12:30 PM'];
  static const _taken = {1};

  _Req _state = _Req.pending;
  bool _picking = false;
  String _time = '11:30 AM';

  void _set(_Req s, {String? time}) {
    HapticFeedback.mediumImpact();
    setState(() {
      _state = s;
      _picking = false;
      if (time != null) _time = time;
    });
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _state = _Req.pending;
      _picking = false;
      _time = '11:30 AM';
    });
  }

  (String, Color) get _pill => switch (_state) {
    _Req.pending => ('Pending', const Color(0xFFF2B84B)),
    _Req.confirmed => ('Confirmed', const Color(0xFF5BD68A)),
    _Req.rescheduled => ('Rescheduled', const Color(0xFF6FB4FF)),
    _Req.cancelled => ('Cancelled', const Color(0xFFFF7A70)),
  };

  @override
  Widget build(BuildContext context) {
    final (pillText, pillColor) = _pill;
    final cancelled = _state == _Req.cancelled;
    return SizedBox(
      width: 326,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glass(
            radius: 30,
            blur: 22,
            tint: 0.1,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'NEW REQUEST',
                      style: AppText.ui(
                        11,
                        weight: FontWeight.w800,
                        letterSpacing: 2.4,
                        color: AppColors.gold,
                      ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _StatusPill(
                        key: ValueKey(pillText),
                        label: pillText,
                        color: pillColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const _Avatar('D', size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daniel R.',
                            style: AppText.ui(17, weight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Skin fade + beard trim',
                            style: AppText.ui(
                              12.5,
                              color: AppColors.cream.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 7),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        'Tomorrow · $_time',
                        key: ValueKey(_time),
                        style:
                            AppText.ui(
                              13.5,
                              weight: FontWeight.w700,
                              color: AppColors.goldLight,
                            ).copyWith(
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Alex',
                      style: AppText.ui(13, weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _picking
                        ? _picker()
                        : (_state == _Req.pending ? _actions() : _done()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _Hint('Tap an action to try it'),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      key: const ValueKey('actions'),
      children: [
        Expanded(
          flex: 11,
          child: _ActionButton(
            label: 'Confirm',
            icon: Icons.check_rounded,
            primary: true,
            onTap: () => _set(_Req.confirmed),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 12,
          child: _ActionButton(
            label: 'Reschedule',
            icon: Icons.event_repeat_rounded,
            onTap: () => setState(() => _picking = true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 9,
          child: _ActionButton(
            label: 'Cancel',
            icon: Icons.close_rounded,
            danger: true,
            onTap: () => _set(_Req.cancelled),
          ),
        ),
      ],
    );
  }

  Widget _picker() {
    return Column(
      key: const ValueKey('picker'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Free slots tomorrow',
          style: AppText.ui(
            12,
            weight: FontWeight.w700,
            color: AppColors.cream.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _slots.length; i++)
              GestureDetector(
                onTap: _taken.contains(i)
                    ? null
                    : () => _set(_Req.rescheduled, time: _slots[i]),
                child: Container(
                  width: 86,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.07),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    _slots[i],
                    style:
                        AppText.ui(
                          12.5,
                          weight: FontWeight.w700,
                          color: _taken.contains(i)
                              ? AppColors.cream.withValues(alpha: 0.28)
                              : AppColors.cream,
                        ).copyWith(
                          decoration: _taken.contains(i)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _done() {
    final text = switch (_state) {
      _Req.confirmed => 'Daniel is notified. See you at $_time.',
      _Req.rescheduled => 'Moved to $_time. Daniel is notified.',
      _ => 'Request declined. The slot is free again.',
    };
    return Row(
      key: ValueKey('done-${_state.name}'),
      children: [
        Icon(
          _state == _Req.cancelled
              ? Icons.info_outline_rounded
              : Icons.verified_rounded,
          size: 18,
          color: _pill.$2,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppText.ui(
              12.5,
              weight: FontWeight.w600,
              color: AppColors.cream.withValues(alpha: 0.85),
            ),
          ),
        ),
        GestureDetector(
          onTap: _reset,
          child: Text(
            'Try again',
            style:
                AppText.ui(
                  12,
                  weight: FontWeight.w800,
                  color: AppColors.gold,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.gold,
                ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = primary
        ? AppColors.ink
        : (danger ? const Color(0xFFFF8D84) : AppColors.cream);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: primary ? AppColors.goldGradient : null,
          color: primary ? null : Colors.white.withValues(alpha: 0.07),
          border: Border.all(
            color: primary
                ? Colors.transparent
                : (danger
                      ? const Color(0xFFFF7A70).withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.18)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(height: 1),
            Text(
              label,
              style: AppText.ui(11, weight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide 4: a paid invoice (drag to tilt) that flips to "your earnings today".
// ---------------------------------------------------------------------------
class InvoiceTicket extends StatefulWidget {
  const InvoiceTicket({super.key});

  @override
  State<InvoiceTicket> createState() => _InvoiceTicketState();
}

class _InvoiceTicketState extends State<InvoiceTicket>
    with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  bool _back = false;

  @override
  void dispose() {
    _flip.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    _back = !_back;
    _flip.animateTo(_back ? 1 : 0, curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Tilt3D(
        maxAngle: 0.26,
        builder: (context, tilt) {
          return AnimatedBuilder(
            animation: _flip,
            builder: (context, _) {
              final angle = _flip.value * math.pi;
              final showBack = _flip.value > 0.5;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(angle),
                child: showBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _TicketBack(tilt: tilt),
                      )
                    : _TicketFront(tilt: tilt, progress: _progress),
              );
            },
          );
        },
      ),
    );
  }
}

class _TicketShell extends StatelessWidget {
  const _TicketShell({required this.child, required this.tilt});

  final Widget child;
  final Offset tilt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
      height: 384,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: AppColors.goldGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.28),
            blurRadius: 40,
            offset: Offset(-tilt.dx * 16, 22 - tilt.dy * 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF14100C)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.4 + tilt.dx * 1.8, -1),
                  end: Alignment(0.0 + tilt.dx * 1.8, 1),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    AppColors.goldLight.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _TicketFront extends StatelessWidget {
  const _TicketFront({required this.tilt, required this.progress});

  final Offset tilt;
  final Animation<double> progress;

  static const _lines = [
    ('Skin fade', r'$34.99'),
    ('Beard sculpt', r'$24.99'),
    ('Beard oil', r'$15.00'),
    ('Tip', r'$8.00'),
  ];

  @override
  Widget build(BuildContext context) {
    return _TicketShell(
      tilt: tilt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.goldGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.ink,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Text(
                  'INVOICE PAID',
                  style: AppText.ui(
                    12,
                    weight: FontWeight.w800,
                    letterSpacing: 2.2,
                    color: AppColors.goldLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'INVOICE NO.',
              style: AppText.ui(
                10,
                weight: FontWeight.w700,
                letterSpacing: 2.4,
                color: AppColors.cream.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'INV-20261023-0042',
              style: AppText.ui(
                19,
                weight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(height: 12),
            for (final (name, price) in _lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.2),
                child: Row(
                  children: [
                    Text(
                      name,
                      style: AppText.ui(
                        13,
                        color: AppColors.cream.withValues(alpha: 0.82),
                      ),
                    ),
                    const Spacer(),
                    Text(price, style: AppText.ui(13, weight: FontWeight.w700)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const _Perforation(),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'TOTAL',
                  style: AppText.ui(
                    11,
                    weight: FontWeight.w800,
                    letterSpacing: 2.4,
                    color: AppColors.cream.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 82.98),
                  duration: const Duration(milliseconds: 1700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    '\$${v.toStringAsFixed(2)}',
                    style: AppText.ui(
                      28,
                      weight: FontWeight.w800,
                      color: AppColors.goldLight,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) => _StatusTimeline(
                t: progress.value,
                steps: const ['Sold', 'Paid', 'Emailed'],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(
                  Icons.touch_app_rounded,
                  size: 15,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 6),
                Text(
                  'Drag to tilt  ·  Tap to flip',
                  style: AppText.ui(
                    12,
                    color: AppColors.cream.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        22,
        (i) => Expanded(
          child: Container(
            height: 1.4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: i.isEven
                ? AppColors.gold.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.t, required this.steps});

  final double t;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    // 0..1 loop: the fill travels across the steps then resets.
    final fill = Curves.easeInOut.transform(
      (t / 0.85).clamp(0.0, 1.0).toDouble(),
    );
    final last = steps.length - 1;
    return Column(
      children: [
        SizedBox(
          height: 22,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  Container(
                    height: 3,
                    width: (w - 18) * fill,
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  for (var i = 0; i <= last; i++)
                    Positioned(
                      left: (w - 18) * (i / last),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: fill >= i / last - 0.001
                              ? AppColors.gold
                              : const Color(0xFF2A221A),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.7),
                          ),
                        ),
                        child: fill >= i / last - 0.001
                            ? const Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: AppColors.ink,
                              )
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final s in steps)
              Text(
                s,
                style: AppText.ui(
                  11,
                  weight: FontWeight.w600,
                  color: AppColors.cream.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TicketBack extends StatelessWidget {
  const _TicketBack({required this.tilt});

  final Offset tilt;

  @override
  Widget build(BuildContext context) {
    return _TicketShell(
      tilt: tilt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            Text(
              'YOUR EARNINGS TODAY',
              style: AppText.ui(
                12,
                weight: FontWeight.w800,
                letterSpacing: 2.2,
                color: AppColors.goldLight,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(painter: _RingPainter(t)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '\$${(59.20 * t).toStringAsFixed(2)}',
                          style: AppText.ui(27, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'commission + tips',
                          style: AppText.ui(
                            11,
                            color: AppColors.cream.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Legend(
                  color: AppColors.gold,
                  label: 'Commission',
                  value: r'$41.20',
                ),
                _Legend(
                  color: AppColors.goldLight.withValues(alpha: 0.55),
                  label: 'Tips',
                  value: r'$18.00',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppText.ui(
                10.5,
                color: AppColors.cream.withValues(alpha: 0.6),
              ),
            ),
            Text(value, style: AppText.ui(13.5, weight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(c, r, track);

    const commission = 41.20 / 59.20;
    const gap = 0.035;
    final a1 = 2 * math.pi * (commission - gap) * t;
    final a2 = 2 * math.pi * (1 - commission - gap) * t;
    const start = -math.pi / 2;

    canvas.drawArc(
      rect,
      start,
      a1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: start,
          endAngle: start + 2 * math.pi,
          colors: [AppColors.goldDeep, AppColors.gold, AppColors.goldLight],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    canvas.drawArc(
      rect,
      start + 2 * math.pi * commission * t + 0.06,
      a2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = AppColors.goldLight.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t;
}
