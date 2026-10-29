import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/home/presentation/widgets/home_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/load_fonts.dart';

CalendarEvent _a(int lane, String who, int s, int e, int status) =>
    CalendarEvent(
      id: '$lane-$s',
      isBreak: false,
      laneId: lane,
      title: who,
      date: '2026-10-27',
      startMin: s,
      endMin: e,
      staffName: '',
      appointmentId: s,
      status: AppointmentStatus.fromCode(status),
    );

CalendarEvent _b(int lane, int s, int e) => CalendarEvent(
  id: 'b$lane-$s',
  isBreak: true,
  laneId: lane,
  title: 'Break',
  date: '2026-10-27',
  startMin: s,
  endMin: e,
  staffName: '',
);

/// What the owner's phone showed: one barber free, the rest without hours.
CalendarDay _real() => const CalendarDay(
  lanes: [
    CalendarLane(id: 1, name: 'mike'),
    CalendarLane(id: 2, name: 'Mutaz'),
    CalendarLane(id: 3, name: 'API Test Staff'),
    CalendarLane(id: 4, name: 'stdtbs'),
    CalendarLane(id: 5, name: 'Jsjsns'),
  ],
  events: [],
  availability: DayAvailability(
    openMin: 9 * 60,
    closeMin: 20 * 60,
    shopDayOff: false,
    staff: {
      1: StaffDay(isDayOff: false, hours: []),
      2: StaffDay(isDayOff: false, hours: []),
      3: StaffDay(isDayOff: false, hours: []),
      4: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
      5: StaffDay(isDayOff: false, hours: []),
    },
  ),
);

CalendarDay _realWithBooking() => CalendarDay(
  lanes: _real().lanes,
  events: [_a(2, 'Marcus Lee', 9 * 60 + 30, 10 * 60, 0)],
  availability: _real().availability,
);

/// A busy shop: busy, free, break, later, done, day off.
CalendarDay _busy() => CalendarDay(
  lanes: const [
    CalendarLane(id: 1, name: 'Mike'),
    CalendarLane(id: 2, name: 'Mutaz'),
    CalendarLane(id: 3, name: 'Jack Sparrow'),
    CalendarLane(id: 4, name: 'John'),
    CalendarLane(id: 5, name: 'Rossie Rode'),
    CalendarLane(id: 6, name: 'Daniel'),
  ],
  events: [
    _a(1, 'Marcus Lee', 9 * 60 + 30, 10 * 60 + 15, 3),
    _a(1, 'Daniel Okafor', 11 * 60, 12 * 60, 3),
    _a(1, 'Sam Rivera', 15 * 60, 15 * 60 + 45, 0),
    _a(2, 'Tom', 10 * 60, 10 * 60 + 30, 3),
    _b(2, 13 * 60, 14 * 60),
    _a(2, 'Alex', 16 * 60, 17 * 60, 4),
    _a(3, 'Priya', 9 * 60, 9 * 60 + 45, 3),
    _a(4, 'Leo', 14 * 60 + 30, 15 * 60, 0),
  ],
  availability: const DayAvailability(
    openMin: 9 * 60,
    closeMin: 20 * 60,
    shopDayOff: false,
    staff: {
      1: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
      2: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
      3: StaffDay(isDayOff: false, hours: [(9 * 60, 12 * 60)]),
      4: StaffDay(isDayOff: false, hours: [(14 * 60, 20 * 60)]),
      5: StaffDay(isDayOff: true, hours: []),
      6: StaffDay(isDayOff: false, hours: []),
    },
  ),
);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    // Real icons in the picture (the test font draws squares).
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.view(
            File(
              'J:/all_folder_of_C_drive/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            ).readAsBytesSync().buffer,
          ),
        ),
      );
    await icons.load();
    ShopTime.init();
    // 14:06 in Edmonton, like the owner's screenshot.
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 20, 6);
  });

  final cases = <String, CalendarDay Function()>{
    'real': _real,
    'real_booking': _realWithBooking,
    'busy': _busy,
    'busy_morning': _busy,
  };

  for (final entry in cases.entries) {
    for (final dark in [true, false]) {
      testWidgets('home board ${entry.key} ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        // 10:10 for the morning case, else 14:06.
        ShopTime.clock = () => entry.key == 'busy_morning'
            ? DateTime.utc(2026, 10, 27, 16, 10)
            : DateTime.utc(2026, 10, 27, 20, 6);
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: StaffCalendarCard(
                      day: entry.value(),
                      onBooking: (_) {},
                      onFree: (_, _) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 2);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${Platform.environment['PREVIEW_DIR']}/board_${entry.key}_${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
        });
      });
    }
  }
}
