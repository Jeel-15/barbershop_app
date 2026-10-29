import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/presentation/landscape_calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/calendar_fixtures.dart';
import '../../test/helpers/load_fonts.dart';

CalendarEvent _a(int lane, String who, int s, int e, int status) =>
    CalendarEvent(
      id: '$lane-$s',
      isBreak: false,
      laneId: lane,
      title: who,
      date: '2026-10-25',
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
  date: '2026-10-25',
  startMin: s,
  endMin: e,
  staffName: '',
);

CalendarWindow _window() => CalendarWindow(
  from: DateTime(2026, 10, 18),
  to: DateTime(2026, 12, 10),
  lanes: const [
    CalendarLane(id: 1, name: 'Mike'),
    CalendarLane(id: 2, name: 'Mutaz'),
    CalendarLane(id: 3, name: 'Jack Sparrow'),
    CalendarLane(id: 4, name: 'John'),
    CalendarLane(id: 5, name: 'Rossie Rode'),
  ],
  events: [
    _a(1, 'Marcus Lee', 9 * 60 + 30, 10 * 60 + 15, 3),
    _a(1, 'Daniel Okafor', 11 * 60, 12 * 60, 3),
    _a(1, 'Sam Rivera', 15 * 60, 15 * 60 + 45, 0),
    _a(1, 'Tom', 16 * 60 + 30, 17 * 60, 4),
    _a(2, 'Tom', 10 * 60, 10 * 60 + 30, 3),
    _b(2, 13 * 60, 14 * 60),
    _a(2, 'Alex', 16 * 60, 17 * 60, 4),
    _a(3, 'Priya', 9 * 60, 9 * 60 + 45, 3),
    _a(4, 'Leo', 14 * 60 + 30, 15 * 60, 0),
  ],
);

void main() {
  setUpAll(() async {
    await loadAppFonts();
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
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40); // 10:40
  });

  for (final dark in [false, true]) {
    for (final whole in [false, true]) {
      testWidgets(
        'landscape ${dark ? 'dark' : 'light'} ${whole ? 'whole' : 'detail'}',
        (tester) async {
          tester.view.physicalSize = const Size(844, 390);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentUserProvider.overrideWithValue(adminBootstrap().user),
                calendarProvider.overrideWith(() => FixedCalendar(_window())),
                dayAvailabilityProvider.overrideWith(
                  (ref, date) async => const DayAvailability(
                    openMin: 9 * 60,
                    closeMin: 20 * 60,
                    shopDayOff: false,
                    staff: {
                      1: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
                      2: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
                      3: StaffDay(isDayOff: false, hours: [(9 * 60, 12 * 60)]),
                      4: StaffDay(isDayOff: false, hours: [(14 * 60, 20 * 60)]),
                      5: StaffDay(isDayOff: true, hours: []),
                    },
                  ),
                ),
              ],
              child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  home: const LandscapeCalendarPage(),
                ),
              ),
            ),
          );
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (whole) {
            await tester.tap(find.byIcon(Icons.zoom_out_map_rounded));
            for (var i = 0; i < 6; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          while (tester.takeException() != null) {}
          await tester.runAsync(() async {
            final b =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final img = await b.toImage(pixelRatio: 2);
            final data = await img.toByteData(format: ui.ImageByteFormat.png);
            File(
              '${Platform.environment['PREVIEW_DIR']}/landscape_${dark ? 'dark' : 'light'}_${whole ? 'whole' : 'detail'}.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
          });
        },
      );
    }
  }
}
