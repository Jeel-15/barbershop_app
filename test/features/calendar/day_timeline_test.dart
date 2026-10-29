import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _appt(int lane, int start, int end, {int status = 0}) =>
    CalendarEvent(
      id: 'a$start',
      isBreak: false,
      laneId: lane,
      title: 'Client',
      date: '2026-10-26',
      startMin: start,
      endMin: end,
      staffName: 'x',
      appointmentId: start,
      status: AppointmentStatus.fromCode(status),
    );

CalendarEvent _break(int lane, int start, int end) => CalendarEvent(
  id: 'b$start',
  isBreak: true,
  laneId: lane,
  title: 'Break',
  date: '2026-10-26',
  startMin: start,
  endMin: end,
  staffName: 'x',
);

CalendarDay _day({
  Map<int, StaffDay> staff = const {},
  List<CalendarEvent> events = const [],
  bool shopOff = false,
  bool known = true,
}) => CalendarDay(
  lanes: const [CalendarLane(id: 1, name: 'Mike')],
  events: events,
  availability: DayAvailability(
    openMin: 9 * 60,
    closeMin: 21 * 60,
    shopDayOff: shopOff,
    staff: staff,
    known: known,
  ),
);

const _nine2one = StaffDay(isDayOff: false, hours: [(540, 780)]);

void main() {
  group('who can take a booking', () {
    test('free working time is free; the rest is not', () {
      final t = LaneTimeline.of(_day(staff: {1: _nine2one}), 1);
      expect(t.verdict(10 * 60), SlotVerdict.free);
      expect(t.verdict(8 * 60 + 45), SlotVerdict.unavailable);
      expect(t.verdict(13 * 60), SlotVerdict.unavailable); // working ends 13:00
    });

    test('a booking covers its time; the minute it ends is free again', () {
      final t = LaneTimeline.of(
        _day(staff: {1: _nine2one}, events: [_appt(1, 600, 645)]),
        1,
      );
      expect(t.verdict(600), SlotVerdict.booked);
      expect(t.verdict(644), SlotVerdict.booked);
      expect(t.verdict(645), SlotVerdict.free);
      expect(t.verdict(599), SlotVerdict.free);
    });

    test('a break blocks like a booking', () {
      final t = LaneTimeline.of(
        _day(staff: {1: _nine2one}, events: [_break(1, 720, 750)]),
        1,
      );
      expect(t.verdict(730), SlotVerdict.booked);
      expect(t.verdict(751), SlotVerdict.free);
    });

    test('a break from the availability answer blocks too', () {
      const staff = StaffDay(
        isDayOff: false,
        hours: [(540, 780)],
        breaks: [(600, 660)],
      );
      final t = LaneTimeline.of(_day(staff: {1: staff}), 1);
      expect(t.verdict(630), SlotVerdict.booked);
      expect(t.free, [(540, 600), (660, 780)]);
    });

    test('no working hours set = the whole column is not available (web)', () {
      const none = StaffDay(isDayOff: false, hours: []);
      final t = LaneTimeline.of(_day(staff: {1: none}), 1);
      expect(t.state, LaneState.noHours);
      expect(t.verdict(10 * 60), SlotVerdict.unavailable);
      expect(t.free, isEmpty);
      expect(t.unavailable(540, 1260), [(540, 1260)]);
    });

    test('a day off and a closed shop', () {
      const off = StaffDay(isDayOff: true, hours: []);
      expect(
        LaneTimeline.of(_day(staff: {1: off}), 1).verdict(600),
        SlotVerdict.dayOff,
      );
      expect(
        LaneTimeline.of(
          _day(staff: {1: _nine2one}, shopOff: true),
          1,
        ).verdict(600),
        SlotVerdict.shopClosed,
      );
    });

    test(
      'no data for the barber: nothing is blocked inside the shop hours',
      () {
        final t = LaneTimeline.of(_day(), 1);
        expect(t.state, LaneState.open);
        expect(t.verdict(10 * 60), SlotVerdict.free);
        expect(t.verdict(8 * 60), SlotVerdict.unavailable);
        final unknown = LaneTimeline.of(_day(known: false), 1);
        expect(unknown.verdict(12 * 60), SlotVerdict.free);
      },
    );

    test('the clock plays no part: earlier time can still be booked', () {
      final t = LaneTimeline.of(_day(staff: {1: _nine2one}), 1);
      expect(t.verdict(9 * 60 + 15), SlotVerdict.free);
      expect(t.free, [(540, 780)]);
    });
  });

  group('free stretches', () {
    test('working time minus appointments, in order', () {
      final t = LaneTimeline.of(
        _day(
          staff: {1: _nine2one},
          events: [_appt(1, 570, 600), _appt(1, 660, 720)],
        ),
        1,
      );
      expect(t.free, [(540, 570), (600, 660), (720, 780)]);
    });

    test('overlapping bookings do not make a gap', () {
      final t = LaneTimeline.of(
        _day(
          staff: {1: _nine2one},
          events: [_appt(1, 600, 660), _appt(1, 630, 700)],
        ),
        1,
      );
      expect(t.free, [(540, 600), (700, 780)]);
    });

    test('two working blocks (split shift) keep the gap closed', () {
      const split = StaffDay(isDayOff: false, hours: [(540, 780), (840, 1080)]);
      final t = LaneTimeline.of(_day(staff: {1: split}), 1);
      expect(t.free, [(540, 780), (840, 1080)]);
      expect(t.verdict(13 * 60 + 30), SlotVerdict.unavailable);
      expect(t.unavailable(480, 1140), [(480, 540), (780, 840), (1080, 1140)]);
    });

    test('a booking with no length still takes 15 minutes', () {
      final t = LaneTimeline.of(
        _day(staff: {1: _nine2one}, events: [_appt(1, 600, 600)]),
        1,
      );
      expect(t.verdict(610), SlotVerdict.booked);
      expect(t.verdict(615), SlotVerdict.free);
    });

    test('freeUntil: how long a booking can run from here', () {
      final t = LaneTimeline.of(
        _day(staff: {1: _nine2one}, events: [_appt(1, 660, 720)]),
        1,
      );
      expect(t.freeUntil(600), 660);
      expect(t.freeUntil(661), isNull);
      expect(t.freeUntil(725), 780);
    });
  });

  test('the legend counts each status and the breaks', () {
    final c = DayCounts.of(
      _day(
        events: [
          _appt(1, 600, 630),
          _appt(1, 660, 690, status: 3),
          _appt(1, 700, 730, status: 3),
          _break(1, 720, 750),
        ],
      ),
    );
    expect(c.of(0), 1);
    expect(c.of(3), 2);
    expect(c.of(1), 0);
    expect(c.breaks, 1);
    expect(c.bookings, 3);
  });

  group('what a barber is doing now (the Home board)', () {
    LaneNow now(CalendarDay d, int minute) {
      final b = [
        for (final e in d.forLane(1))
          if (!e.isBreak) e,
      ];
      return LaneNow.of(LaneTimeline.of(d, 1), b, minute);
    }

    final day = _day(
      staff: {
        1: const StaffDay(isDayOff: false, hours: [(540, 780), (840, 1080)]),
      },
      events: [_appt(1, 600, 645), _break(1, 780, 840), _appt(1, 900, 930)],
    );

    test('with a customer: who, and when free again', () {
      final n = now(day, 620);
      expect(n.presence, Presence.busy);
      expect(n.who, 'Client');
      expect(n.freeAt, 645);
    });

    test('free: until the next booking', () {
      final n = now(day, 700);
      expect(n.presence, Presence.free);
      expect(n.until, 780);
      expect(n.canTakeWalkIn, isTrue);
    });

    test('on a break (the gap between two shifts)', () {
      final n = now(day, 800);
      expect(n.presence, Presence.onBreak);
      expect(n.freeAt, 840);
    });

    test('before the first shift: starts later; after the last: done', () {
      expect(now(day, 480).presence, Presence.later);
      expect(now(day, 480).until, 540);
      expect(now(day, 1100).presence, Presence.done);
    });

    test('day off, no hours, shop closed: off with a reason', () {
      final off = _day(staff: {1: const StaffDay(isDayOff: true, hours: [])});
      expect(now(off, 700).presence, Presence.off);
      expect(now(off, 700).offReason, 'Day off');
      final none = _day(staff: {1: const StaffDay(isDayOff: false, hours: [])});
      expect(now(none, 700).offReason, 'No hours set');
      final closed = _day(staff: {1: _nine2one}, shopOff: true);
      expect(now(closed, 700).offReason, 'Shop closed');
    });

    test('booked with no working hours: judged by the bookings', () {
      final d = _day(
        staff: {1: const StaffDay(isDayOff: false, hours: [])},
        events: [_appt(1, 600, 660), _appt(1, 900, 930)],
      );
      expect(now(d, 620).presence, Presence.busy);
      expect(now(d, 620).noHours, isTrue);
      expect(now(d, 700).presence, Presence.later);
      expect(now(d, 700).until, 900);
      expect(now(d, 1000).presence, Presence.done);
    });
  });
}
