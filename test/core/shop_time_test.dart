import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(ShopTime.init);
  tearDown(() => ShopTime.clock = DateTime.now);

  group('"today" is shop time, not phone time', () {
    test('06:30 UTC on 23 Oct is 00:30 in Edmonton (still the 23rd)', () {
      ShopTime.clock = () => DateTime.utc(2026, 10, 23, 6, 30);
      expect(ShopTime.ymd(ShopTime.today()), '2026-10-23');
      expect(ShopTime.now().hour, 0);
    });

    test('05:30 UTC on 23 Oct is still the 22nd in Edmonton', () {
      ShopTime.clock = () => DateTime.utc(2026, 10, 23, 5, 30);
      expect(ShopTime.ymd(ShopTime.today()), '2026-10-22');
    });

    test(
      'the offset always comes from the time-zone database, never hard-coded',
      () {
        // Whatever the rules are for a date (they change by law), now() must
        // equal "UTC + the database's offset for that instant".
        for (final utc in [
          DateTime.utc(2026, 7, 1, 12),
          DateTime.utc(2026, 12, 15, 12),
          DateTime.utc(2027, 3, 20, 12),
        ]) {
          ShopTime.clock = () => utc;
          final n = ShopTime.now();
          expect(n.toUtc(), utc);
          expect(n.timeZoneOffset.inHours, anyOf(-6, -7));
        }
      },
    );
  });

  group('dates and times from the API', () {
    test('parseDate / ymd round trip', () {
      final d = ShopTime.parseDate('2026-10-23');
      expect((d.year, d.month, d.day), (2026, 10, 23));
      expect(ShopTime.ymd(d), '2026-10-23');
      expect(ShopTime.parseDate('2026-10-23 14:30:00').day, 23);
    });

    test('minutes / hhmm', () {
      expect(ShopTime.minutes('14:30'), 870);
      expect(ShopTime.minutes('09:05:00'), 545);
      expect(ShopTime.hhmm(870), '14:30');
      expect(ShopTime.hhmm(545), '09:05');
    });

    test('12-hour labels', () {
      expect(ShopTime.timeLabel('00:00'), '12:00 AM');
      expect(ShopTime.timeLabel('09:05'), '9:05 AM');
      expect(ShopTime.timeLabel('12:00'), '12:00 PM');
      expect(ShopTime.timeLabel('14:30'), '2:30 PM');
      expect(ShopTime.timeLabel(23 * 60 + 59), '11:59 PM');
    });
  });

  group('labels', () {
    setUp(
      () => ShopTime.clock = () => DateTime.utc(2026, 10, 23, 18),
    ); // 12:00 Edmonton

    test('relative days', () {
      final today = ShopTime.today();
      expect(ShopTime.relativeDay(today), 'Today');
      expect(
        ShopTime.relativeDay(today.add(const Duration(days: 1))),
        'Tomorrow',
      );
      expect(
        ShopTime.relativeDay(today.subtract(const Duration(days: 1))),
        'Yesterday',
      );
      expect(
        ShopTime.relativeDay(today.add(const Duration(days: 3))),
        'Mon, 26 Oct',
      );
    });

    test('day and full date labels', () {
      final d = DateTime(2026, 10, 23);
      expect(ShopTime.dayLabel(d), 'Fri, 23 Oct');
      expect(ShopTime.fullDate(d), '23 Oct 2026');
      expect(ShopTime.weekdayLong(d), 'Friday');
    });
  });
}
